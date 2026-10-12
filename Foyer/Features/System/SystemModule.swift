import AppKit
import Defaults
import SwiftUI

/// System state: Mac battery and Low Power Mode, Bluetooth / AirPods
/// connectivity, fullscreen Spaces, Mission Control and games.
///
/// Provides `BatteryLockWidget`, `ConnectivityLockWidget` and
/// `SystemCGSSpace` (private CGS space used by the lock screen).
enum SystemModule {
    @MainActor private static var isStarted = false

    @MainActor
    static func start() {
        guard !isStarted else { return }
        isStarted = true

        SystemSpaceManager.shared.start()
        SystemMissionControlManager.shared.start()
        SystemGameManager.shared.start()
        SystemBatteryManager.shared.start()
        SystemConnectivityManager.shared.start()
    }

    /// Triggers the Bluetooth TCC prompt (used by onboarding / settings).
    @MainActor
    static func requestBluetoothPermission() {
        SystemConnectivityManager.shared.requestBluetoothPermission()
    }
}

/// Feature-specific measurements that are not in `Constants`.
enum SystemConstants {
    enum Battery {
        /// Wing that fits the "Low Battery" label (same as the HUD wings, 326-332 wide).
        static let labelWing: CGFloat = Constants.Geometry.hudWing
        /// Label hidden, percentage + glyph shown.
        static let percentageWing: CGFloat = 76
        /// Label and percentage hidden: just the glyph.
        static let glyphWing: CGFloat = 44
        /// Battery glyph body (excluding the cap).
        static let glyphSize = CGSize(width: 25, height: 12)
        /// `_hasRecentlyChangedPowerSource` guard (STATIC 0.5 s wait, Part E §2).
        static let powerSourceSettle: Double = 0.5
        /// Low Power Mode hand-off delay (STATIC 0.2 s wait, Part E §2).
        static let lowPowerSettle: Double = 0.2
        /// Low Power Mode amber (AlcoveAmberBright #FBC337, Part F §5).
        static let lowPowerTint = Constants.Battery.lowPower
    }

    enum Connectivity {
        /// Wing for a battery readout (percentage + ring).
        static let batteryWing: CGFloat = 58
        /// Wing for a "Connected" / "Disconnected" label.
        static let labelWing: CGFloat = Constants.Geometry.hudWing
        /// The AirPods clips are 6.000 s seamless loops (360 frames at 60 fps).
        static let modelLoop: Double = 6.0
        /// Connect notifications are held briefly so model and battery can be read.
        static let presentDelay: Double = 0.5
        /// `IOBluetoothDevice.register(forConnectNotifications:)` replays every
        /// already-connected device right after registering; those are ignored.
        static let initialSuppression: Double = 2.0
        /// The same device toggling within this window is not re-announced.
        static let flapWindow: Double = 2.0
        /// Battery re-read cadence while devices are connected (`timer`).
        static let batteryPoll: Double = 60
        /// system_profiler is expensive; throttle it.
        static let profilerThrottle: Double = 30
        static let profilerTimeout: Double = 10
        static let ringSize: CGFloat = 16
        static let ringLineWidth: CGFloat = 2.5
    }

    enum Spaces {
        /// Light polling for fullscreen spaces between workspace notifications.
        static let pollInterval: Double = 1.5
        /// Re-checks after a Space change (the switch animation takes a moment).
        static let followUpDelays: [Double] = [0.35, 0.9]
        /// CGSSpaceType bit 2 (`ubfx w0, w0, 2, 1` at 0x100127ff0 / 0x100128040).
        static let fullscreenTypeBit = 2
    }

    enum MissionControl {
        static let fallbackPollInterval: Double = 1.0
        /// A Dock window covering this share of a screen counts as Mission Control.
        static let coverage: CGFloat = 0.9
        static let axRetryInterval: Double = 5
    }
}

/// Runs main-actor work from callbacks that may arrive on the main thread
/// (run-loop sources, ObjC notifications) or elsewhere.
enum SystemMainThread {
    static func run(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { body() }
        } else {
            Task { @MainActor in body() }
        }
    }
}
