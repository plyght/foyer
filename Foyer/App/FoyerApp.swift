import AppKit
import Defaults
import SwiftUI

@main
enum FoyerMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

/// Agent app (LSUIElement): menu-bar item, no Dock icon. Each feature exposes
/// a `<Name>Module.start()` entry point that wires its managers into
/// `NotchController.shared`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NotchWindowManager.shared.start()

        VisualsModule.start()
        SystemModule.start()
        HUDModule.start()
        NowPlayingModule.start()
        CalendarModule.start()
        LockScreenModule.start()
        AppShellModule.start()

        DemoDriver.startIfRequested()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppShellModule.openSettings()
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(AppShellModule.handle(url:))
    }

    func applicationWillTerminate(_ notification: Notification) {
        HUDModule.stop()
        LockScreenModule.stop()
    }
}
