import AppKit
import Defaults
import SwiftUI

/// App shell: menu-bar item, Luminare settings window, onboarding, updater,
/// `foyer://` URLs, AppleScript, launch at login and permissions.
enum AppShellModule {
    @MainActor private static var started = false
    /// URLs can arrive before `start()` on a cold launch; replay them after.
    @MainActor private static var pendingRoutes: [ShellURLRoute] = []

    @MainActor static func start() {
        guard !started else { return }
        started = true

        ShellScripting.register()
        ShellLaunchAtLogin.start()
        ShellPermissions.shared.refresh()
        ShellMenuBarController.shared.start()
        ShellUpdateManager.shared.start()

        if Defaults[.isFirstLaunch] {
            OnboardingWindowController.shared.show()
        }

        let routes = pendingRoutes
        pendingRoutes = []
        if !routes.isEmpty {
            Task { @MainActor in
                // Let the notch panels finish their first layout.
                try? await Task.sleep(for: .milliseconds(300))
                routes.forEach { AppShellModule.perform($0) }
            }
        }
    }

    @MainActor static func openSettings() {
        SettingsWindowController.shared.show(tab: nil)
    }

    /// `foyer://` routes. Alcove's `alcove://` only recognises a licence
    /// route (Part G §9); Foyer has no licensing and instead exposes:
    ///
    /// - `foyer://settings[/<pane>]` (also `?pane=`), `foyer://about`
    /// - `foyer://open[/<page>]` (`expand`), `foyer://close` (`collapse`), `foyer://toggle`
    /// - `foyer://update` (check for updates)
    /// - `foyer://onboarding`
    ///
    /// Anything else is accepted by Launch Services and ignored.
    @MainActor static func handle(url: URL) {
        guard let route = ShellURLRoute(url: url) else {
            ShellLog.logger.notice("Ignoring URL \(url.absoluteString, privacy: .public)")
            return
        }
        guard started else {
            pendingRoutes.append(route)
            return
        }
        perform(route)
    }

    @MainActor static func perform(_ route: ShellURLRoute) {
        switch route {
        case .settings(let tab):
            SettingsWindowController.shared.show(tab: tab)
        case .open(let page):
            ShellIsland.open(page: page)
        case .close:
            ShellIsland.close()
        case .toggle:
            ShellIsland.toggle()
        case .checkForUpdates:
            SettingsWindowController.shared.show(tab: .about)
            Task { @MainActor in
                await ShellUpdateManager.shared.checkForUpdates(userInitiated: true)
            }
        case .onboarding:
            OnboardingWindowController.shared.show()
        }
    }
}

/// Parsed `foyer://` URL.
enum ShellURLRoute: Equatable {
    case settings(SettingsTab?)
    case open(ExpandedPageID?)
    case close
    case toggle
    case checkForUpdates
    case onboarding

    init?(url: URL) {
        guard url.scheme?.lowercased() == "foyer" else { return nil }

        var parts: [String] = []
        if let host = url.host(percentEncoded: false), !host.isEmpty {
            parts.append(host)
        }
        parts.append(contentsOf: url.pathComponents.filter { $0 != "/" && !$0.isEmpty })
        // `foyer:settings` (no slashes) has neither host nor path components.
        if parts.isEmpty, let opaque = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path, !opaque.isEmpty {
            parts = opaque.split(separator: "/").map(String.init)
        }
        parts = parts.map { $0.lowercased() }

        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func queryValue(_ name: String) -> String? {
            query.first(where: { $0.name.lowercased() == name })?.value?.lowercased()
        }

        guard let head = parts.first else { return nil }
        let argument = parts.count > 1 ? parts[1] : nil

        switch head {
        case "settings", "preferences", "prefs":
            let name = argument ?? queryValue("pane") ?? queryValue("tab")
            self = .settings(name.flatMap(SettingsTab.init(urlName:)))
        case "about":
            self = .settings(.about)
        case "open", "expand", "show":
            let name = argument ?? queryValue("page")
            self = .open(name.flatMap(ShellURLRoute.page(named:)))
        case "close", "collapse", "hide":
            self = .close
        case "toggle":
            self = .toggle
        case "update", "updates", "check-for-updates", "checkforupdates":
            self = .checkForUpdates
        case "onboarding", "welcome":
            self = .onboarding
        default:
            return nil
        }
    }

    private static func page(named name: String) -> ExpandedPageID? {
        switch name {
        case "nowplaying", "now-playing", "media", "music": return .nowPlaying
        case "calendar", "events": return .calendar
        case "duo": return .duo
        default: return ExpandedPageID(rawValue: name)
        }
    }
}

/// Opens and closes the island on the primary display.
@MainActor
enum ShellIsland {
    static var isExpanded: Bool {
        NotchWindowManager.shared.primaryModel?.isExpanded ?? false
    }

    static func open(page: ExpandedPageID? = nil) {
        guard let model = NotchWindowManager.shared.primaryModel else { return }
        if let page, NotchController.shared.orderedPages.contains(where: { $0.id == page }) {
            model.open(page: page)
        } else {
            model.open()
        }
    }

    static func close() {
        NotchWindowManager.shared.primaryModel?.close()
    }

    static func toggle() {
        isExpanded ? close() : open()
    }
}
