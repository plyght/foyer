import AppKit
import Combine
import Defaults

/// Alcove's `GameManager` (Part G §7): classifies the **frontmost**
/// application only, by an explicit bundle-id set plus a Minecraft runtime
/// path fragment. It deliberately does not look at `LSApplicationCategoryType`,
/// Game Mode, GPU load or fullscreen (a synthetic app in the action-games
/// category kept the notch visible). With `hideWhileGaming` on, the island
/// hides while a listed game is in front.
@MainActor
final class SystemGameManager: ObservableObject {
    static let shared = SystemGameManager()

    /// Constant array at 0x100590950.
    nonisolated static let trackedGameBundleIdentifiers: Set<String> = [
        "com.riotgames.leagueoflegends",
        "com.riotgames.leagueoflegends.gameclient",
        "com.riotgames.leagueclient",
        "com.riotgames.leagueclientux",
        "com.nvidia.gfnpc.mall",
    ]

    /// Lower-cased bundle path fragments (Minecraft's Java runtime).
    nonisolated static let trackedGamePathFragments: [String] = [
        "/application support/minecraft/runtime/",
    ]

    @Published private(set) var isGaming = false
    @Published private(set) var frontmostGameBundleIdentifier: String?

    private var frontmostApplicationObserver: NSObjectProtocol?
    private var defaultsObservers: [Defaults.Observation] = []
    private var isStarted = false

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true

        frontmostApplicationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            SystemMainThread.run { SystemGameManager.shared.evaluate(app) }
        }

        defaultsObservers.append(Defaults.observe(.hideWhileGaming, options: []) { _ in
            Task { @MainActor in SystemGameManager.shared.apply() }
        })

        evaluate(NSWorkspace.shared.frontmostApplication)
    }

    /// Re-reads the frontmost application.
    func refresh() {
        evaluate(NSWorkspace.shared.frontmostApplication)
    }

    private func evaluate(_ app: NSRunningApplication?) {
        let gaming = app.map { Self.isGame($0) } ?? false
        let identifier = gaming ? app?.bundleIdentifier : nil
        if frontmostGameBundleIdentifier != identifier { frontmostGameBundleIdentifier = identifier }
        if gaming != isGaming { isGaming = gaming }
        apply()
    }

    private func apply() {
        let hide = isGaming && Defaults[.hideWhileGaming]
        if hide != NotchController.shared.hideReasons.contains(.gaming) {
            NotchController.shared.setHidden(hide, reason: .gaming)
        }
    }

    /// Classification at 0x1001276f0: bundle id membership first, then the
    /// lower-cased bundle path. Processes without a bundle (the Java runtime
    /// launched by Minecraft) are matched on their executable path.
    static func isGame(_ app: NSRunningApplication) -> Bool {
        if let identifier = app.bundleIdentifier, trackedGameBundleIdentifiers.contains(identifier) {
            return true
        }
        let path = (app.bundleURL ?? app.executableURL)?.path.lowercased() ?? ""
        guard !path.isEmpty else { return false }
        return trackedGamePathFragments.contains { path.contains($0) }
    }
}
