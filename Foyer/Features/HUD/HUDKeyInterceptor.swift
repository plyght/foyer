import AppKit
import ApplicationServices
import Combine
import CoreGraphics
import Defaults
import Foundation

/// Session event-tap callback (C function pointer, no captures). The tap's
/// run-loop source is on the main run loop, so the callback runs on the main
/// thread and can enter the main actor synchronously.
private func hudEventTapCallback(proxy: CGEventTapProxy,
                                 type: CGEventType,
                                 event: CGEvent,
                                 userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                HUDKeyInterceptor.shared.reenableTap()
            }
        }
        return Unmanaged.passUnretained(event)
    }
    guard type.rawValue == HUDConstants.systemDefinedEventType, Thread.isMainThread else {
        return Unmanaged.passUnretained(event)
    }
    let swallow: Bool = MainActor.assumeIsolated {
        HUDKeyInterceptor.shared.handle(event)
    }
    // Returning NULL swallows the event, which keeps the system OSD from
    // appearing (Alcove 0x100137194: `xzr` instead of the event pointer).
    return swallow ? nil : Unmanaged.passUnretained(event)
}

/// Intercepts `NX_SYSDEFINED` media keys (subtype 8) with an active session
/// event tap, applies volume / brightness / keyboard-backlight changes itself
/// and shows Foyer's HUD instead of the system OSD (Part E §6).
///
/// Key/modifier matrix:
/// - 0 / 1 sound up/down, 7 mute, 2 / 3 brightness up/down, 21 / 22 keyboard
///   illumination up/down.
/// - Shift+Option (`flags & 0xa0000 == 0xa0000`): fine step (1/64).
/// - Option without Shift on a sound or brightness key: opens the Sound or
///   Displays settings pane.
/// - Command: always passed through.
/// - Disabled HUD, gaming (with "Hide while gaming"), a HUD filtered out by
///   Focus/Lock "Allowed Notifications", or a device Foyer cannot drive: the
///   key passes through so macOS handles it.
///
/// The tap needs Accessibility. Trust is polled so granting it in System
/// Settings enables the HUD without a relaunch (Part B §6); an existing tap
/// keeps working if trust is revoked, as in Alcove.
@MainActor
final class HUDKeyInterceptor: ObservableObject {
    static let shared = HUDKeyInterceptor()

    /// True while the event tap is installed and enabled.
    @Published private(set) var isActive = false

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pollTask: Task<Void, Never>?
    /// Keys whose key-down was swallowed; their key-up is swallowed too.
    private var swallowedKeys: Set<Int> = []

    private init() {}

    // MARK: Lifecycle

    func start() {
        installTapIfPossible()
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(HUDConstants.accessibilityPollInterval))
                guard !Task.isCancelled else { return }
                HUDKeyInterceptor.shared.refreshAccessibility()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        removeTap()
    }

    /// Installs the tap once Accessibility is granted, or re-enables a
    /// disabled one. Called periodically; AppShell may call it right after
    /// the user grants the permission.
    func refreshAccessibility() {
        if tap == nil {
            installTapIfPossible()
        } else if let tap, !CGEvent.tapIsEnabled(tap: tap) {
            reenableTap()
        }
    }

    private func installTapIfPossible() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let mask = CGEventMask(1) << CGEventMask(HUDConstants.systemDefinedEventType)
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                             place: .headInsertEventTap,
                                             options: .defaultTap,
                                             eventsOfInterest: mask,
                                             callback: hudEventTapCallback,
                                             userInfo: nil) else { return }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            CFMachPortInvalidate(newTap)
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        tap = newTap
        runLoopSource = source
        isActive = true
        // Pick up the current values so the first HUD opens at the right level.
        HUDBrightnessManager.shared.refresh()
    }

    private func removeTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        swallowedKeys.removeAll()
        isActive = false
    }

    /// Re-enables a tap the system disabled (timeout or user input), after an
    /// `AXIsProcessTrusted` check (Alcove 0x1001367fc).
    fileprivate func reenableTap() {
        guard let tap else { return }
        if AXIsProcessTrusted() {
            CGEvent.tapEnable(tap: tap, enable: true)
            isActive = true
        } else {
            isActive = CGEvent.tapIsEnabled(tap: tap)
        }
    }

    // MARK: Event handling

    /// Returns true to swallow the event.
    fileprivate func handle(_ event: CGEvent) -> Bool {
        guard let nsEvent = NSEvent(cgEvent: event),
              nsEvent.type == .systemDefined,
              nsEvent.subtype.rawValue == HUDConstants.mediaKeySubtype else { return false }

        let data1 = nsEvent.data1
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyFlags = data1 & 0x0000_FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let isRepeat = (keyFlags & 0x1) != 0
        let flags = event.flags.rawValue
            | UInt64(nsEvent.modifierFlags.rawValue)
            | CGEventSource.flagsState(.combinedSessionState).rawValue

        if keyState == HUDConstants.keyStateUp {
            guard swallowedKeys.remove(keyCode) != nil else { return false }
            if keyCode == HUDConstants.keySoundUp || keyCode == HUDConstants.keySoundDown {
                playVolumeFeedbackIfNeeded(flags: flags)
            }
            return true
        }
        guard keyState == HUDConstants.keyStateDown else { return false }

        if isRepeat {
            // The decision is made on the initial press; repeats follow it.
            guard swallowedKeys.contains(keyCode) else { return false }
            _ = apply(keyCode: keyCode, isRepeat: true, flags: flags)
            return true
        }

        let swallow = apply(keyCode: keyCode, isRepeat: false, flags: flags)
        if swallow {
            swallowedKeys.insert(keyCode)
        } else {
            swallowedKeys.remove(keyCode)
        }
        return swallow
    }

    /// Applies one key-down. Returns false to pass the key through.
    private func apply(keyCode: Int, isRepeat: Bool, flags: UInt64) -> Bool {
        let K = HUDConstants.self
        if flags & K.flagCommand != 0 { return false }
        let fine = flags & K.fineModifierMask == K.fineModifierMask
        let optionOnly = flags & K.flagOption != 0 && flags & K.flagShift == 0

        switch keyCode {
        case K.keySoundUp, K.keySoundDown, K.keyMute:
            guard Defaults[.enableVolume], !isSuppressed(.sound) else { return false }
            if optionOnly {
                if !isRepeat { openSettingsPane(K.soundPreferencesURL) }
                return true
            }
            let volume = VolumeManager.shared
            if keyCode == K.keyMute {
                if isRepeat { return true }
                guard volume.canMute || volume.isAdjustable else { return false }
                volume.toggleMute()
            } else {
                guard volume.isAdjustable else { return false }
                volume.step(up: keyCode == K.keySoundUp, fine: fine)
            }
            Haptics.perform(.levelChange)
            HUDPresenter.present(.volume)
            return true

        case K.keyBrightnessUp, K.keyBrightnessDown:
            guard Defaults[.enableBrightness], !isSuppressed(.display) else { return false }
            if optionOnly {
                if !isRepeat { openSettingsPane(K.displayPreferencesURL) }
                return true
            }
            guard HUDBrightnessManager.shared.step(up: keyCode == K.keyBrightnessUp, fine: fine) else { return false }
            Haptics.perform(.levelChange)
            HUDPresenter.present(.brightness)
            return true

        case K.keyIlluminationUp, K.keyIlluminationDown:
            guard Defaults[.enableBrightness], !isSuppressed(.display), !optionOnly else { return false }
            guard HUDKeyboardBacklightManager.shared.step(up: keyCode == K.keyIlluminationUp, fine: fine) else { return false }
            Haptics.perform(.levelChange)
            HUDPresenter.present(.keyboardBacklight)
            return true

        default:
            return false
        }
    }

    /// The notch is hidden while a classified game is frontmost and "Hide
    /// while gaming" is on, and the Sound HUD is suppressed (Part G §7). The
    /// key then goes to macOS. Same when Focus/Lock filters the category.
    private func isSuppressed(_ category: NotificationCategory) -> Bool {
        let controller = NotchController.shared
        if Defaults[.hideWhileGaming], controller.hideReasons.contains(.gaming) { return true }
        if !controller.isAllowed(category) { return true }
        // Nowhere to draw the HUD (every notch hidden, e.g. fullscreen):
        // let the system OSD show instead of swallowing the key silently.
        let models = NotchWindowManager.shared.allModels
        return models.isEmpty || models.allSatisfy { $0.isHidden }
    }

    private func openSettingsPane(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    /// macOS "Play feedback when volume is changed" plays a tick on release;
    /// Shift inverts it. Alcove reads the same preference and plays its
    /// `volume` sound (Part G §8).
    private func playVolumeFeedbackIfNeeded(flags: UInt64) {
        let K = HUDConstants.self
        let value = CFPreferencesCopyAppValue(K.volumeFeedbackDefaultsKey as CFString, kCFPreferencesAnyApplication)
        let preference = (value as? NSNumber)?.intValue == 1
        let shiftOnly = flags & K.flagShift != 0 && flags & K.flagOption == 0
        guard preference != shiftOnly else { return }
        guard !VolumeManager.shared.isMuted else { return }
        SoundPlayer.play(.volume)
    }
}
