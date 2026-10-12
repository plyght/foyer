import AppKit
import Combine
import Defaults
import IOKit
import IOKit.ps
import SwiftUI

/// Notifications the Mac battery can raise. Alcove's strings are
/// "Charging", "Low Battery" and "Low Power" (Part E §2); Foyer adds the
/// matching "off" state for Low Power Mode.
enum SystemBatteryAlert: Equatable {
    case charging
    case lowBattery
    case lowPowerOn
    case lowPowerOff

    var title: LocalizedStringKey {
        switch self {
        case .charging: return "Charging"
        case .lowBattery: return "Low Battery"
        case .lowPowerOn: return "Low Power"
        case .lowPowerOff: return "Low Power Off"
        }
    }

    var notificationKind: NotificationKind {
        switch self {
        case .charging, .lowBattery: return .battery
        case .lowPowerOn, .lowPowerOff: return .lowPower
        }
    }
}

/// One reading of the internal battery (IOPS + AppleSmartBattery registry).
struct SystemBatterySnapshot: Equatable {
    var hasBattery = false
    /// 0...100.
    var percent = 0
    /// `ExternalConnected` (registry) or "Power Source State" == "AC Power".
    var isPluggedIn = false
    /// `IsCharging` (registry) or "Is Charging" (IOPS).
    var isCharging = false
    var isFullyCharged = false
    /// Minutes, nil when unknown / still calculating.
    var minutesToEmpty: Int?
    var minutesToFull: Int?
}

/// Alcove's `BatteryManager` + `BatteryHelper` (Part E §2, Part F §5).
@MainActor
final class SystemBatteryManager: ObservableObject {
    static let shared = SystemBatteryManager()

    @Published private(set) var hasBattery = false
    /// 0...1 (`_batteryLevel`, integer level / 100).
    @Published private(set) var level: Double = 0
    @Published private(set) var isPluggedIn = false
    @Published private(set) var isCharging = false
    @Published private(set) var isFullyCharged = false
    @Published private(set) var isLowPowerModeEnabled = ProcessInfo.processInfo.isLowPowerModeEnabled
    /// Minutes to empty while discharging, to full while charging.
    @Published private(set) var remainingMinutes: Int?

    var percent: Int { Int((level * 100).rounded()) }

    private var wasOnBattery = false
    private var hasPassedThreshold = false
    private var hasRecentlyChangedPowerSource = false
    private var runLoopSource: CFRunLoopSource?
    private var lowPowerObserver: NSObjectProtocol?
    private var defaultsObservers: [Defaults.Observation] = []
    private var settleTask: Task<Void, Never>?
    private var lowPowerTask: Task<Void, Never>?
    private var hasInitialReading = false
    private var isStarted = false

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true

        installPowerSourceNotification()

        lowPowerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { _ in
            SystemMainThread.run { SystemBatteryManager.shared.lowPowerModeChanged() }
        }

        defaultsObservers.append(Defaults.observe(.lowBatteryThreshold, options: []) { _ in
            Task { @MainActor in SystemBatteryManager.shared.rearmThreshold() }
        })

        refresh()
    }

    // MARK: Sources

    /// `IOPSNotificationCreateRunLoopSource` on the current (main) run loop,
    /// default mode, like `BatteryHelper.open`.
    private func installPowerSourceNotification() {
        guard runLoopSource == nil else { return }
        guard let source = IOPSNotificationCreateRunLoopSource(systemPowerSourcesChanged, nil)?.takeRetainedValue()
        else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    /// Reads IOPS (filtering `Type == InternalBattery`) and the
    /// AppleSmartBattery registry entry. Registry keys win where both exist.
    nonisolated static func readSnapshot() -> SystemBatterySnapshot {
        var snapshot = SystemBatterySnapshot()

        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                let raw = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                guard let description = raw as? [String: Any],
                      (description["Type"] as? String) == "InternalBattery" else { continue }
                if let present = description["Is Present"] as? Bool, !present { continue }
                snapshot.hasBattery = true
                let current = (description["Current Capacity"] as? NSNumber)?.doubleValue ?? 0
                let maximum = (description["Max Capacity"] as? NSNumber)?.doubleValue ?? 100
                if maximum > 0 {
                    snapshot.percent = Int((current / maximum * 100).rounded())
                }
                snapshot.isPluggedIn = (description["Power Source State"] as? String) == "AC Power"
                snapshot.isCharging = (description["Is Charging"] as? Bool) ?? false
                snapshot.isFullyCharged = (description["Is Charged"] as? Bool) ?? false
                if let toEmpty = (description["Time to Empty"] as? NSNumber)?.intValue, toEmpty > 0 {
                    snapshot.minutesToEmpty = toEmpty
                }
                if let toFull = (description["Time to Full Charge"] as? NSNumber)?.intValue, toFull > 0 {
                    snapshot.minutesToFull = toFull
                }
                break
            }
        }

        if let registry = smartBatteryProperties() {
            snapshot.hasBattery = true
            if let external = registry["ExternalConnected"] as? Bool { snapshot.isPluggedIn = external }
            if let charging = registry["IsCharging"] as? Bool { snapshot.isCharging = charging }
            if let full = registry["FullyCharged"] as? Bool { snapshot.isFullyCharged = full }
            if let toEmpty = (registry["AvgTimeToEmpty"] as? NSNumber)?.intValue {
                // 65535 means "still calculating".
                snapshot.minutesToEmpty = (toEmpty > 0 && toEmpty < 65535) ? toEmpty : snapshot.minutesToEmpty
            }
            if let toFull = (registry["AvgTimeToFull"] as? NSNumber)?.intValue {
                snapshot.minutesToFull = (toFull > 0 && toFull < 65535) ? toFull : snapshot.minutesToFull
            }
        }

        snapshot.percent = min(max(snapshot.percent, 0), 100)
        return snapshot
    }

    /// `IOServiceGetMatchingService(IOServiceNameMatching("AppleSmartBattery"))`.
    nonisolated private static func smartBatteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else { return nil }
        return dictionary
    }

    // MARK: State machine

    /// Battery refresh (0x10012e4f8): reads state, then runs the edge triggers.
    func refresh() {
        let snapshot = Self.readSnapshot()
        let isInitial = !hasInitialReading
        hasInitialReading = true

        let previouslyOnBattery = wasOnBattery
        let onBattery = !snapshot.isPluggedIn

        if hasBattery != snapshot.hasBattery { hasBattery = snapshot.hasBattery }
        let newLevel = Double(snapshot.percent) / 100
        if level != newLevel { level = newLevel }
        if isPluggedIn != snapshot.isPluggedIn { isPluggedIn = snapshot.isPluggedIn }
        if isCharging != snapshot.isCharging { isCharging = snapshot.isCharging }
        if isFullyCharged != snapshot.isFullyCharged { isFullyCharged = snapshot.isFullyCharged }
        let minutes = snapshot.isPluggedIn ? snapshot.minutesToFull : snapshot.minutesToEmpty
        if remainingMinutes != minutes { remainingMinutes = minutes }
        wasOnBattery = onBattery

        guard snapshot.hasBattery else { return }

        if isInitial {
            // Latch silently when launched already below the threshold.
            hasPassedThreshold = onBattery && isAtOrBelowThreshold
            return
        }

        if previouslyOnBattery != onBattery {
            powerSourceChanged(pluggedIn: !onBattery)
        } else {
            checkLowBattery()
        }
    }

    private var isAtOrBelowThreshold: Bool {
        Double(percent) <= Defaults[.lowBatteryThreshold]
    }

    private func powerSourceChanged(pluggedIn: Bool) {
        hasRecentlyChangedPowerSource = true
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(SystemConstants.Battery.powerSourceSettle))
            guard !Task.isCancelled, let self else { return }
            self.hasRecentlyChangedPowerSource = false
            self.checkLowBattery()
        }

        if pluggedIn {
            hasPassedThreshold = false
            present(.charging)
        }
    }

    /// Threshold crossing with `_hasPassedThreshold` latching: one warning
    /// per discharge below the threshold, re-armed above it or on AC.
    private func checkLowBattery() {
        guard hasBattery else { return }
        if isPluggedIn || !isAtOrBelowThreshold {
            hasPassedThreshold = false
            return
        }
        guard !hasPassedThreshold, !hasRecentlyChangedPowerSource else { return }
        hasPassedThreshold = true
        guard Defaults[.warnOnLowBattery] else { return }
        present(.lowBattery)
        if Defaults[.enableBattery], Defaults[.playSoundOnLowBattery] {
            // `low-power.caf` is the laptop low-battery sound (Part G §8);
            // `low-battery.caf` belongs to connected devices.
            SoundPlayer.play(.lowPower)
        }
    }

    private func rearmThreshold() {
        hasPassedThreshold = !isPluggedIn && isAtOrBelowThreshold
    }

    /// Low-power handler (0x10012f82c): compares with the prior state.
    private func lowPowerModeChanged() {
        let enabled = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard enabled != isLowPowerModeEnabled else { return }
        isLowPowerModeEnabled = enabled
        lowPowerTask?.cancel()
        lowPowerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(SystemConstants.Battery.lowPowerSettle))
            guard !Task.isCancelled, let self else { return }
            self.refresh()
            guard self.hasBattery, Defaults[.notifyOnLowPowerMode],
                  self.isLowPowerModeEnabled == enabled else { return }
            self.present(enabled ? .lowPowerOn : .lowPowerOff)
            if enabled, Defaults[.enableBattery], Defaults[.playSoundOnLowBattery] {
                SoundPlayer.play(.lowPower)
            }
        }
    }

    // MARK: Presentation

    func present(_ alert: SystemBatteryAlert) {
        guard Defaults[.enableBattery], hasBattery else { return }
        let hideLabel = Defaults[.hideBatteryLabel]
        let hidePercentage = Defaults[.hideBatteryPercentage]
        let wing: CGFloat
        if !hideLabel {
            wing = SystemConstants.Battery.labelWing
        } else if !hidePercentage {
            wing = SystemConstants.Battery.percentageWing
        } else {
            wing = SystemConstants.Battery.glyphWing
        }
        let notification = NotchNotification(
            kind: alert.notificationKind,
            category: .battery,
            wingWidth: wing,
            duration: Defaults[.batteryDuration],
            animation: Constants.Animations.notification,
            leading: AnyView(SystemBatteryNotificationLeading(alert: alert)),
            trailing: AnyView(SystemBatteryNotificationTrailing(alert: alert)))
        NotchController.shared.post(notification)
    }

    /// Fill colour of the glyph: green while charging / full on AC, amber in
    /// Low Power Mode, red at or below the threshold, white otherwise.
    func tint(for alert: SystemBatteryAlert? = nil) -> Color {
        if let alert {
            switch alert {
            case .charging: return Constants.Battery.charging
            case .lowBattery: return Constants.Battery.low
            case .lowPowerOn: return SystemConstants.Battery.lowPowerTint
            case .lowPowerOff: break
            }
        }
        if isPluggedIn && (isCharging || isFullyCharged) { return Constants.Battery.charging }
        if isLowPowerModeEnabled { return SystemConstants.Battery.lowPowerTint }
        if isAtOrBelowThreshold { return Constants.Battery.low }
        return .white
    }
}

/// IOPS run-loop callback (main run loop): re-read the battery.
private func systemPowerSourcesChanged(_ context: UnsafeMutableRawPointer?) {
    SystemMainThread.run { SystemBatteryManager.shared.refresh() }
}
