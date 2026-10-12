import AppKit
import Defaults
import SwiftUI

/// Scripted walkthrough used by the UI-capture CI workflow.
///
/// Launch with `-FoyerDemo YES [-FoyerDemoDir /path]`. Each step puts Foyer
/// into a state, waits for it to settle, then writes `<NN>-<name>.ready` into
/// the demo directory; the workflow takes a screenshot whenever a marker
/// appears and the whole run is screen-recorded. `done` is written at the end.
@MainActor
enum DemoDriver {
    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: "FoyerDemo") }

    private static var directory: URL {
        let path = UserDefaults.standard.string(forKey: "FoyerDemoDir") ?? "/tmp/foyer-demo"
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static var stepIndex = 0

    static func startIfRequested() {
        guard isEnabled else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task { @MainActor in
            await run()
            write("done", contents: "ok")
            try? await Task.sleep(for: .seconds(2))
            NSApp.terminate(nil)
        }
    }

    // MARK: Script

    private static func run() async {
        let controller = NotchController.shared
        await wait(2.5) // panels up, managers started

        guard let model = NotchWindowManager.shared.primaryModel else {
            log("no notch model; aborting")
            return
        }

        // Idle.
        await step("closed")

        // Hover bump (140→152, +5 tall).
        hover(model, true)
        await step("hover", settle: 0.6)
        hover(model, false)
        await wait(0.6)

        // HUDs.
        VolumeManager.shared.setVolume(0.35)
        HUDPresenter.present(.volume)
        await step("hud-volume", settle: 0.9)
        VolumeManager.shared.setVolume(0.8)
        HUDPresenter.present(.volume)
        await step("hud-volume-up", settle: 0.4)
        await wait(2.5)
        HUDPresenter.present(.brightness)
        await step("hud-brightness", settle: 0.9)
        await wait(2.5)

        // Battery notifications.
        SystemBatteryManager.shared.present(.charging)
        await step("battery-charging", settle: 0.8)
        await wait(1.5)
        SystemBatteryManager.shared.present(.lowBattery)
        await step("battery-low", settle: 0.8)
        await wait(1.5)
        SystemBatteryManager.shared.present(.lowPowerOn)
        await step("battery-low-power", settle: 0.8)
        controller.dismissNotification()
        await wait(1)

        // Now Playing: the workflow plays a tone in QuickTime Player.
        if await waitFor(seconds: 15, { controller.activities[.nowPlaying] != nil }) {
            await step("nowplaying-compact", settle: 1.0)
            hover(model, true)
            await step("nowplaying-compact-hover", settle: 0.6)
            model.open(page: .nowPlaying)
            await step("nowplaying-expanded", settle: 1.0)
            controller.send(.next)
            await step("nowplaying-skip", settle: 0.4)
            model.close()
            hover(model, false)
            await wait(1)
        } else {
            log("Now Playing activity never appeared")
            write(nextName("nowplaying-missing"), contents: "missing")
        }

        // Calendar page (synthetic EventKit access may be denied in CI).
        if controller.pages[.calendar] != nil {
            model.open(page: .calendar)
            await step("calendar-expanded", settle: 1.0)
            model.close()
            await wait(1)
        }

        // Duo page.
        let previousIdle = Defaults[.idleActivity]
        Defaults[.idleActivity] = .duo
        await wait(0.3)
        model.open(page: .duo)
        await step("duo-expanded", settle: 1.0)
        model.close()
        Defaults[.idleActivity] = previousIdle
        await wait(1)

        // Cycling activities (swipe up / swipe down).
        if !controller.orderedActivities.isEmpty {
            controller.dismissVisibleActivity()
            await step("cycle-dismissed", settle: 1.0)
            controller.restoreDismissedActivity()
            await step("cycle-restored", settle: 1.0)
        }

        // Rubber-band open via synthetic scroll would need a trackpad; show
        // the expanded default page instead.
        model.open()
        await step("expanded-default", settle: 1.0)
        model.close()
        await wait(1)

        // Lock screen widgets (without actually locking the session).
        controller.isScreenLocked = true
        LockScreenManager.shared.presenter.show()
        await step("lockscreen-widgets", settle: 1.5)
        LockScreenManager.shared.presenter.hide()
        controller.isScreenLocked = false
        await wait(1)

        // Settings window panes.
        AppShellModule.openSettings()
        await step("settings", settle: 1.5)
        NSApp.windows.filter { $0.isVisible && !($0 is OverlayPanel) }.forEach { $0.close() }
        await wait(0.5)

        // Simulated notch off → floating pill.
        Defaults[.forceSimulatedNotch] = false
        await step("pill-closed", settle: 1.0)
        Defaults[.forceSimulatedNotch] = true
        await wait(1)
    }

    // MARK: Helpers

    private static func hover(_ model: NotchViewModel, _ inside: Bool) {
        let rect = model.screenHitRect
        let point = inside ? CGPoint(x: rect.midX, y: rect.midY) : CGPoint(x: rect.midX, y: rect.minY - 300)
        // Move the real cursor too so recordings show it.
        if let screen = NSScreen.screens.first {
            CGWarpMouseCursorPosition(CGPoint(x: point.x, y: screen.frame.maxY - point.y))
        }
        model.mouseMoved(to: point)
    }

    private static func step(_ name: String, settle: Double = 0.8) async {
        await wait(settle)
        write(nextName(name), contents: describe())
        // Give the workflow time to grab the screenshot.
        await wait(1.2)
    }

    private static func nextName(_ name: String) -> String {
        stepIndex += 1
        return String(format: "%02d-%@.ready", stepIndex, name)
    }

    private static func describe() -> String {
        guard let model = NotchWindowManager.shared.primaryModel else { return "" }
        let f = model.shapeFrame
        return "presentation=\(model.presentation) shape=\(Int(f.width))x\(Int(f.height)) hover=\(model.isHovering) expanded=\(model.isExpanded)"
    }

    private static func write(_ name: String, contents: String) {
        let url = directory.appendingPathComponent(name)
        try? contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func log(_ message: String) {
        NSLog("[FoyerDemo] %@", message)
    }

    private static func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private static func waitFor(seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return true }
            await wait(0.25)
        }
        return condition()
    }
}
