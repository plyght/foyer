import AppKit
import Defaults

/// Cocoa Scripting support for `Foyer.sdef` (Part G §12). Alcove only
/// exposes AppKit's generic Standard/Text suites; Foyer includes those too
/// (via `CocoaStandard.sdef`) and adds a small "Foyer Suite":
///
/// ```applescript
/// tell application "Foyer"
///     expand island
///     get island expanded
///     set idle activity to "duo"
///     show settings pane "calendar"
///     check for updates
/// end tell
/// ```
@MainActor
enum ShellScripting {
    /// Makes sure the command classes named in the sdef are registered with
    /// the Objective-C runtime before the first Apple Event arrives.
    static func register() {
        let classes: [AnyClass] = [
            ShellExpandIslandCommand.self,
            ShellCollapseIslandCommand.self,
            ShellToggleIslandCommand.self,
            ShellShowSettingsCommand.self,
            ShellCheckForUpdatesCommand.self,
        ]
        for cls in classes {
            _ = NSStringFromClass(cls)
        }
    }
}

@objc(FoyerExpandIslandCommand)
final class ShellExpandIslandCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated {
            ShellIsland.open()
        }
        return nil
    }
}

@objc(FoyerCollapseIslandCommand)
final class ShellCollapseIslandCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated {
            ShellIsland.close()
        }
        return nil
    }
}

@objc(FoyerToggleIslandCommand)
final class ShellToggleIslandCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated {
            ShellIsland.toggle()
        }
        return nil
    }
}

@objc(FoyerShowSettingsCommand)
final class ShellShowSettingsCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let paneName = (evaluatedArguments?["pane"] as? String)?.lowercased()
        let tab = paneName.flatMap { SettingsTab(urlName: $0) }
        if paneName != nil, tab == nil {
            scriptErrorNumber = -1728 // errAENoSuchObject
            scriptErrorString = "Unknown settings pane \"\(paneName ?? "")\"."
            return nil
        }
        MainActor.assumeIsolated {
            SettingsWindowController.shared.show(tab: tab)
        }
        return nil
    }
}

@objc(FoyerCheckForUpdatesCommand)
final class ShellCheckForUpdatesCommand: NSScriptCommand {
    override func performDefaultImplementation() -> Any? {
        MainActor.assumeIsolated {
            AppShellModule.perform(.checkForUpdates)
        }
        return nil
    }
}

/// Scriptable application properties (cocoa keys in `Foyer.sdef`). Cocoa
/// Scripting reads and writes them on `NSApp` with key-value coding.
extension NSApplication {
    @objc var foyerIslandExpanded: Bool {
        get { ShellIsland.isExpanded }
        set { newValue ? ShellIsland.open() : ShellIsland.close() }
    }

    @objc var foyerIdleActivity: String {
        get { Defaults[.idleActivity].rawValue }
        set {
            if let activity = IdleActivity(rawValue: newValue) {
                Defaults[.idleActivity] = activity
            }
        }
    }

    @objc var foyerUpdateAvailable: Bool {
        if case .available = ShellUpdateManager.shared.state { return true }
        return false
    }
}
