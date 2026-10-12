import AppKit
import Combine
import Defaults

/// Detects fullscreen Spaces per display through CGS (Part A §4,
/// 0x100127f4c / 0x100128054) and reports them with
/// `NotchController.shared.setFullscreen(_:screen:)`. The core applies
/// `hideWhileInFullscreen`.
@MainActor
final class SystemSpaceManager: ObservableObject {
    static let shared = SystemSpaceManager()

    /// Displays whose current Space is a fullscreen Space.
    @Published private(set) var fullscreenDisplays: Set<CGDirectDisplayID> = []
    @Published private(set) var activeSpaceID: UInt64 = 0

    private var reported: Set<CGDirectDisplayID> = []
    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var followUpTasks: [Task<Void, Never>] = []
    private var isStarted = false

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true

        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                SystemMainThread.run { self?.refreshWithFollowUps() }
            }
            workspaceObservers.append(token)
        }

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)

        let timer = Timer(timeInterval: SystemConstants.Spaces.pollInterval, repeats: true) { [weak self] _ in
            SystemMainThread.run { self?.refresh() }
        }
        timer.tolerance = SystemConstants.Spaces.pollInterval / 2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        refresh()
    }

    /// Refreshes now and again shortly after (the Space switch animates).
    private func refreshWithFollowUps() {
        refresh()
        followUpTasks.forEach { $0.cancel() }
        followUpTasks = SystemConstants.Spaces.followUpDelays.map { delay in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func refresh() {
        let screens = NSScreen.screens
        var fullscreen = Set<CGDirectDisplayID>()

        let displays = SystemCGS.managedDisplaySpaces()
        if displays.isEmpty {
            // No managed-space info: fall back to the active space for the
            // main screen.
            if let space = SystemCGS.activeSpace() {
                activeSpaceID = space
                if let type = SystemCGS.spaceType(space), SystemCGS.isFullscreenType(type),
                   let main = NSScreen.main {
                    fullscreen.insert(main.displayID)
                }
            }
        } else {
            if let space = SystemCGS.activeSpace() { activeSpaceID = space }
            var byIdentifier: [String: Bool] = [:]
            var sharedSpaces: Bool?
            for display in displays {
                guard let identifier = display["Display Identifier"] as? String else { continue }
                let isFullscreen = Self.currentSpaceIsFullscreen(display)
                if identifier.lowercased() == "main" {
                    sharedSpaces = isFullscreen
                } else {
                    byIdentifier[identifier.lowercased()] = isFullscreen
                }
            }
            for screen in screens {
                let id = screen.displayID
                if let uuid = screen.displayUUID?.lowercased(), let value = byIdentifier[uuid] {
                    if value { fullscreen.insert(id) }
                } else if let shared = sharedSpaces {
                    // "Displays have separate Spaces" off: one entry for all.
                    if shared { fullscreen.insert(id) }
                }
            }
        }

        if fullscreen != fullscreenDisplays { fullscreenDisplays = fullscreen }
        report(fullscreen, screens: screens)
    }

    private func report(_ fullscreen: Set<CGDirectDisplayID>, screens: [NSScreen]) {
        let controller = NotchController.shared
        let present = Set(screens.map(\.displayID))
        // Clear displays that went away or left fullscreen.
        for id in reported where !fullscreen.contains(id) || !present.contains(id) {
            controller.setFullscreen(false, screen: id)
        }
        for id in fullscreen where !reported.contains(id) {
            controller.setFullscreen(true, screen: id)
        }
        reported = fullscreen.intersection(present)
    }

    /// Reads the "Current Space" type (bit 2 = fullscreen); falls back to
    /// `CGSSpaceGetType` on its id, as Alcove does.
    private static func currentSpaceIsFullscreen(_ display: [String: Any]) -> Bool {
        guard let current = display["Current Space"] as? [String: Any] else { return false }
        if let type = current["type"] as? NSNumber {
            return SystemCGS.isFullscreenType(type.intValue)
        }
        let idValue = (current["ManagedSpaceID"] as? NSNumber) ?? (current["id64"] as? NSNumber)
        if let idValue, let type = SystemCGS.spaceType(idValue.uint64Value) {
            return SystemCGS.isFullscreenType(type)
        }
        return false
    }
}
