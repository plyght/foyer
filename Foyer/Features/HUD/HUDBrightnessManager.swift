import AppKit
import Combine
import CoreGraphics
import Foundation

// DisplayServices (private) signatures, resolved with dlsym (Part E §5).
// SetBrightnessSmooth takes the *delta* from the current brightness: Alcove
// computes `target - clamp(current)` before calling it (0x10011b818).
private typealias HUDDSGetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
private typealias HUDDSSetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
private typealias HUDDSSetBrightnessSmooth = @convention(c) (CGDirectDisplayID, Float) -> Int32
private typealias HUDDSCanChangeBrightness = @convention(c) (CGDirectDisplayID) -> Bool
private typealias HUDDSGetBrightnessIncrement = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
private typealias HUDDSRegisterForBrightnessChange = @convention(c) (CGDirectDisplayID, UnsafeRawPointer?, CFNotificationCallback) -> Int32
private typealias HUDDSUnregisterForBrightnessChange = @convention(c) (CGDirectDisplayID, UnsafeRawPointer?) -> Int32

/// The resolved DisplayServices entry points (all optional).
private struct HUDDisplayServices {
    let getBrightness: HUDDSGetBrightness?
    let setBrightness: HUDDSSetBrightness?
    let setBrightnessSmooth: HUDDSSetBrightnessSmooth?
    let canChangeBrightness: HUDDSCanChangeBrightness?
    let getBrightnessIncrement: HUDDSGetBrightnessIncrement?
    let register: HUDDSRegisterForBrightnessChange?
    let unregister: HUDDSUnregisterForBrightnessChange?

    static func load() -> HUDDisplayServices {
        let path = PrivateAPI.displayServices
        return HUDDisplayServices(
            getBrightness: PrivateAPI.symbol("DisplayServicesGetBrightness", in: path, as: HUDDSGetBrightness.self),
            setBrightness: PrivateAPI.symbol("DisplayServicesSetBrightness", in: path, as: HUDDSSetBrightness.self),
            setBrightnessSmooth: PrivateAPI.symbol("DisplayServicesSetBrightnessSmooth", in: path, as: HUDDSSetBrightnessSmooth.self),
            canChangeBrightness: PrivateAPI.symbol("DisplayServicesCanChangeBrightness", in: path, as: HUDDSCanChangeBrightness.self),
            getBrightnessIncrement: PrivateAPI.symbol("DisplayServicesGetBrightnessIncrement", in: path, as: HUDDSGetBrightnessIncrement.self),
            register: PrivateAPI.symbol("DisplayServicesRegisterForBrightnessChangeNotifications", in: path, as: HUDDSRegisterForBrightnessChange.self),
            unregister: PrivateAPI.symbol("DisplayServicesUnregisterForBrightnessChangeNotifications", in: path, as: HUDDSUnregisterForBrightnessChange.self))
    }
}

/// DisplayServices brightness-change callback. Delivery thread is not
/// documented, so hop to the main actor.
private func hudBrightnessDidChange(_ center: CFNotificationCenter?,
                                    _ observer: UnsafeMutableRawPointer?,
                                    _ name: CFNotificationName?,
                                    _ object: UnsafeRawPointer?,
                                    _ userInfo: CFDictionary?) {
    Task { @MainActor in
        HUDBrightnessManager.shared.hardwareBrightnessChanged()
    }
}

/// Display brightness through DisplayServices (Part E §5, Part F §4).
///
/// - The change observer is registered only when
///   `DisplayServicesCanChangeBrightness` is true for the built-in display
///   (Alcove's gate at 0x1001197cc).
/// - Key steps use `DisplayServicesGetBrightnessIncrement` when it reports a
///   value in (0, 1], otherwise 1/16; Shift+Option scales by 0.25.
/// - An optimistic local target plus a short callback-suppression window keep
///   asynchronous hardware callbacks from fighting recent key writes.
/// - External displays: any display DisplayServices can drive (e.g. Apple
///   Studio Display) works; others pass the key through (BetterDisplay or the
///   system handles them, and BetterDisplay OSDs are mirrored by
///   `HUDBetterDisplayBridge`).
@MainActor
final class HUDBrightnessManager: ObservableObject {
    static let shared = HUDBrightnessManager()

    /// Brightness of the targeted display, 0…1.
    @Published private(set) var level: Float = 0
    /// The HUD shows a display glyph instead of the sun for external screens.
    @Published private(set) var isExternalDisplay = false

    private let api = HUDDisplayServices.load()
    private var observedDisplayID: CGDirectDisplayID?
    private var targetDisplayID: CGDirectDisplayID?
    private var localTarget: [CGDirectDisplayID: Float] = [:]
    private var suppressionDeadline: [CGDirectDisplayID: Date] = [:]
    private var writeTask: Task<Void, Never>?
    private var screenObserver: AnyCancellable?
    private var isStarted = false

    private init() {}

    // MARK: Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        updateObservedDisplay()
        screenObserver = NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                MainActor.assumeIsolated {
                    HUDBrightnessManager.shared.updateObservedDisplay()
                }
            }
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        screenObserver = nil
        writeTask?.cancel()
        writeTask = nil
        if let display = observedDisplayID {
            _ = api.unregister?(display, Self.observerToken(display))
        }
        observedDisplayID = nil
    }

    // MARK: Capability

    func canChangeBrightness(_ display: CGDirectDisplayID) -> Bool {
        guard let can = api.canChangeBrightness, api.getBrightness != nil,
              api.setBrightness != nil || api.setBrightnessSmooth != nil else { return false }
        return can(display)
    }

    /// The display a brightness key should drive: the screen under the
    /// pointer when DisplayServices can change it, else the built-in panel,
    /// else any changeable display. nil means "let the system handle it".
    func resolveTargetDisplay() -> CGDirectDisplayID? {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
           canChangeBrightness(screen.displayID) {
            return screen.displayID
        }
        let ids = Self.activeDisplays()
        if let builtIn = ids.first(where: { CGDisplayIsBuiltin($0) != 0 && canChangeBrightness($0) }) {
            return builtIn
        }
        return ids.first(where: { canChangeBrightness($0) })
    }

    // MARK: Key steps

    /// Applies one key step. Returns false when no display can be driven, in
    /// which case the caller passes the key through.
    @discardableResult
    func step(up: Bool, fine: Bool) -> Bool {
        guard let display = resolveTargetDisplay() else { return false }
        targetDisplayID = display
        isExternalDisplay = CGDisplayIsBuiltin(display) == 0

        var increment = HUDConstants.fallbackBrightnessIncrement
        if let getIncrement = api.getBrightnessIncrement {
            var value: Float = 0
            if getIncrement(display, &value) == 0, value > 0, value <= 1 {
                increment = value
            }
        }
        if fine { increment *= HUDConstants.fineStepScale }

        let current: Float
        if let local = localTarget[display], let deadline = suppressionDeadline[display], deadline > Date() {
            current = local
        } else {
            current = readBrightness(display) ?? level
        }
        let index = (current / increment).rounded()
        let target = min(max((index + (up ? 1 : -1)) * increment, 0), 1)

        localTarget[display] = target
        suppressionDeadline[display] = Date().addingTimeInterval(HUDConstants.brightnessCallbackSuppression)
        level = target
        write(target, to: display)
        return true
    }

    /// Shows an externally reported brightness (BetterDisplay OSD).
    func applyExternalLevel(_ value: Float, isExternal: Bool) {
        level = min(max(value, 0), 1)
        isExternalDisplay = isExternal
    }

    /// Refreshes `level` from hardware for the display the HUD would target.
    func refresh() {
        guard let display = targetDisplayID ?? resolveTargetDisplay() else { return }
        if let deadline = suppressionDeadline[display], deadline > Date() { return }
        if let value = readBrightness(display) {
            level = value
            isExternalDisplay = CGDisplayIsBuiltin(display) == 0
        }
    }

    // MARK: Hardware callbacks

    fileprivate func hardwareBrightnessChanged() {
        guard let display = observedDisplayID else { return }
        if let deadline = suppressionDeadline[display], deadline > Date() { return }
        localTarget[display] = nil
        // Only follow the observed (built-in) panel when it is what the HUD
        // currently represents.
        if targetDisplayID == nil || targetDisplayID == display, let value = readBrightness(display) {
            level = value
            isExternalDisplay = false
        }
    }

    private func updateObservedDisplay() {
        let builtIn = Self.activeDisplays().first(where: { CGDisplayIsBuiltin($0) != 0 })
        let newObserved: CGDirectDisplayID?
        if let builtIn, canChangeBrightness(builtIn) {
            newObserved = builtIn
        } else {
            newObserved = nil
        }
        guard newObserved != observedDisplayID else { return }
        if let old = observedDisplayID {
            _ = api.unregister?(old, Self.observerToken(old))
        }
        observedDisplayID = nil
        if let display = newObserved, let register = api.register {
            if register(display, Self.observerToken(display), hudBrightnessDidChange) == 0 {
                observedDisplayID = display
            }
        }
        if targetDisplayID.map({ !Self.activeDisplays().contains($0) }) ?? false {
            targetDisplayID = nil
        }
        refresh()
    }

    // MARK: I/O

    private func readBrightness(_ display: CGDirectDisplayID) -> Float? {
        guard let get = api.getBrightness else { return nil }
        var value: Float = 0
        guard get(display, &value) == 0 else { return nil }
        return min(max(value, 0), 1)
    }

    /// Coalesced write: the smooth API first (delta from the current value),
    /// the ordinary setter as fallback (0x10011b7a0).
    private func write(_ target: Float, to display: CGDirectDisplayID) {
        writeTask?.cancel()
        let api = self.api
        writeTask = Task { @MainActor in
            guard !Task.isCancelled else { return }
            var current: Float = 0
            let hasCurrent = api.getBrightness.map { $0(display, &current) == 0 } ?? false
            let clampedCurrent = min(max(current, 0), 1)
            if hasCurrent, let smooth = api.setBrightnessSmooth, smooth(display, target - clampedCurrent) == 0 {
                return
            }
            guard !Task.isCancelled else { return }
            _ = api.setBrightness?(display, target)
        }
    }

    // MARK: Helpers

    private static func observerToken(_ display: CGDirectDisplayID) -> UnsafeRawPointer? {
        UnsafeRawPointer(bitPattern: UInt(display))
    }

    private static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}
