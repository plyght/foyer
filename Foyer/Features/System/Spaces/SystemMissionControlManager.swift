import AppKit
import ApplicationServices
import Combine
import Defaults

/// Detects Mission Control / App Exposé and hides the island while it is
/// open (`hideWhileInMissionControl`, default on).
///
/// Primary source: the Dock's accessibility notifications
/// (`AXExposeShowAllWindows`, `AXExposeShowFrontWindows`, `AXExposeExit`),
/// which need the Accessibility permission Foyer already asks for. Without
/// it, a light CGWindowList check looks for Dock-owned windows that cover a
/// whole display, nudged by the Dock's `com.apple.expose.*` distributed
/// notifications.
@MainActor
final class SystemMissionControlManager: ObservableObject {
    static let shared = SystemMissionControlManager()

    @Published private(set) var isMissionControlActive = false

    nonisolated private static let dockBundleIdentifier = "com.apple.dock"
    nonisolated private static let showNotifications = ["AXExposeShowAllWindows", "AXExposeShowFrontWindows"]
    nonisolated private static let exitNotifications = ["AXExposeExit", "AXExposeShowDesktop"]

    private var axObserver: AXObserver?
    private var axDockPID: pid_t = 0
    private var lastAXAttempt: Date = .distantPast
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private var defaultsObservers: [Defaults.Observation] = []
    private var nudgeTasks: [Task<Void, Never>] = []
    private var isStarted = false

    private init() {}

    var usesAccessibilityNotifications: Bool { axObserver != nil }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let workspace = NSWorkspace.shared.notificationCenter
        let launch = workspace.addObserver(forName: NSWorkspace.didLaunchApplicationNotification,
                                           object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let isDock = app?.bundleIdentifier == SystemMissionControlManager.dockBundleIdentifier
            guard isDock else { return }
            SystemMainThread.run {
                SystemMissionControlManager.shared.teardownAXObserver()
                SystemMissionControlManager.shared.installAXObserverIfPossible(force: true)
            }
        }
        let terminate = workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification,
                                              object: nil, queue: .main) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let isDock = app?.bundleIdentifier == SystemMissionControlManager.dockBundleIdentifier
            guard isDock else { return }
            SystemMainThread.run {
                SystemMissionControlManager.shared.teardownAXObserver()
                SystemMissionControlManager.shared.setActive(false)
            }
        }
        // Leaving Mission Control by picking a window or Space activates an
        // app or switches Space; use those as a safety net for a missed exit.
        let space = workspace.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                          object: nil, queue: .main) { _ in
            SystemMainThread.run { SystemMissionControlManager.shared.safetyRecheck() }
        }
        let activate = workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                             object: nil, queue: .main) { _ in
            SystemMainThread.run { SystemMissionControlManager.shared.safetyRecheck() }
        }
        workspaceObservers = [launch, terminate, space, activate]

        let distributed = DistributedNotificationCenter.default()
        for name in ["com.apple.expose.awake", "com.apple.expose.front.awake"] {
            let token = distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { _ in
                SystemMainThread.run { SystemMissionControlManager.shared.nudge() }
            }
            distributedObservers.append(token)
        }

        defaultsObservers.append(Defaults.observe(.hideWhileInMissionControl, options: []) { _ in
            Task { @MainActor in SystemMissionControlManager.shared.apply() }
        })

        let timer = Timer(timeInterval: SystemConstants.MissionControl.fallbackPollInterval, repeats: true) { _ in
            SystemMainThread.run { SystemMissionControlManager.shared.tick() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        installAXObserverIfPossible(force: true)
        apply()
    }

    // MARK: State

    private func setActive(_ active: Bool) {
        guard active != isMissionControlActive else { return }
        isMissionControlActive = active
        apply()
    }

    private func apply() {
        let hide = isMissionControlActive && Defaults[.hideWhileInMissionControl]
        let isHidden = NotchController.shared.hideReasons.contains(.missionControl)
        if hide != isHidden {
            NotchController.shared.setHidden(hide, reason: .missionControl)
        }
    }

    fileprivate func handleDockNotification(_ name: String) {
        if Self.showNotifications.contains(name) {
            setActive(true)
        } else if Self.exitNotifications.contains(name) {
            setActive(false)
        }
    }

    // MARK: Polling / fallback

    private func tick() {
        if axObserver == nil {
            if Date().timeIntervalSince(lastAXAttempt) >= SystemConstants.MissionControl.axRetryInterval {
                installAXObserverIfPossible(force: false)
            }
        }
        guard axObserver == nil else { return }
        // Fallback only costs anything when the setting is on.
        guard Defaults[.hideWhileInMissionControl] || isMissionControlActive else { return }
        setActive(Self.dockCoversADisplay())
    }

    private func nudge() {
        guard axObserver == nil else { return }
        setActive(Self.dockCoversADisplay())
        nudgeTasks.forEach { $0.cancel() }
        nudgeTasks = [0.2, 0.5].map { delay in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                SystemMissionControlManager.shared.tick()
            }
        }
    }

    private func safetyRecheck() {
        guard isMissionControlActive else { return }
        if axObserver != nil {
            // Exposé closes before an app activates or the Space switches.
            setActive(false)
        } else {
            setActive(Self.dockCoversADisplay())
        }
    }

    /// Mission Control draws its overview in Dock-owned windows above the
    /// desktop that span an entire display.
    static func dockCoversADisplay() -> Bool {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: dockBundleIdentifier).first
        else { return false }
        let dockPID = Int(dock.processIdentifier)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return false }
        let screens = NSScreen.screens
        guard let primaryHeight = screens.first?.frame.maxY else { return false }

        for window in info {
            guard let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.intValue, pid == dockPID,
                  let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue, layer > 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }
            if let alpha = (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue, alpha <= 0.01 { continue }
            // CG window bounds are top-left based; convert to AppKit space.
            let appKitRect = CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY,
                                    width: bounds.width, height: bounds.height)
            for screen in screens {
                let frame = screen.frame
                let overlap = frame.intersection(appKitRect)
                guard !overlap.isNull, frame.width > 0, frame.height > 0 else { continue }
                let coverage = (overlap.width * overlap.height) / (frame.width * frame.height)
                if coverage >= SystemConstants.MissionControl.coverage { return true }
            }
        }
        return false
    }

    // MARK: Accessibility observer on the Dock

    private func installAXObserverIfPossible(force: Bool) {
        lastAXAttempt = Date()
        guard axObserver == nil, AXIsProcessTrusted() else { return }
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: Self.dockBundleIdentifier).first
        else { return }
        let pid = dock.processIdentifier

        var created: AXObserver?
        let status = AXObserverCreate(pid, systemMissionControlAXCallback, &created)
        guard status == .success, let observer = created else { return }

        let element = AXUIElementCreateApplication(pid)
        var registered = 0
        for name in Self.showNotifications + Self.exitNotifications {
            let result = AXObserverAddNotification(observer, element, name as CFString, nil)
            if result == .success || result == .notificationAlreadyRegistered { registered += 1 }
        }
        guard registered > 0 else { return }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        axObserver = observer
        axDockPID = pid
    }

    private func teardownAXObserver() {
        guard let observer = axObserver else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        axObserver = nil
        axDockPID = 0
    }
}

/// C callback for the Dock's Exposé notifications (delivered on the main run loop).
private func systemMissionControlAXCallback(_ observer: AXObserver, _ element: AXUIElement,
                                            _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    let name = notification as String
    SystemMainThread.run { SystemMissionControlManager.shared.handleDockNotification(name) }
}
