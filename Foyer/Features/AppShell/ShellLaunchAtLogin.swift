import AppKit
import Defaults
import ServiceManagement

/// Keeps `launchAtLogin` and `SMAppService.mainApp` in sync (Part B §2.3:
/// the toggle drives register/unregister).
@MainActor
enum ShellLaunchAtLogin {
    private static var observation: Defaults.Observation?
    private static var isApplying = false

    static func start() {
        // Reflect what the system currently has (the user may have changed it
        // in System Settings › General › Login Items).
        let status = SMAppService.mainApp.status
        switch status {
        case .enabled:
            if !Defaults[.launchAtLogin] { setDefaultSilently(true) }
        case .notRegistered, .notFound:
            if Defaults[.launchAtLogin] { apply(true) }
        case .requiresApproval:
            break
        @unknown default:
            break
        }

        observation = Defaults.observe(.launchAtLogin, options: []) { change in
            let enabled = change.newValue
            Task { @MainActor in
                ShellLaunchAtLogin.apply(enabled)
            }
        }
    }

    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func apply(_ enabled: Bool) {
        guard !isApplying else { return }
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled { try service.register() }
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
        } catch {
            ShellLog.logger.error("Launch at login (\(enabled)) failed: \(error.localizedDescription, privacy: .public)")
            // Mirror the real state back so the toggle does not lie.
            setDefaultSilently(service.status == .enabled)
        }
    }

    private static func setDefaultSilently(_ value: Bool) {
        isApplying = true
        Defaults[.launchAtLogin] = value
        // The observation callback hops through a Task; reset afterwards.
        Task { @MainActor in
            ShellLaunchAtLogin.isApplying = false
        }
    }
}
