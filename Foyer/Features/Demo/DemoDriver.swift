import AVFoundation
import AppKit
import MediaPlayer
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
        logWindows()

        guard let model = NotchWindowManager.shared.primaryModel else {
            log("no notch model; aborting")
            return
        }

        // Idle.
        await step("closed")

        // Hover bump (140→152, +5 tall) with Expand on hover off…
        let expandOnHover = Defaults[.expandNotchOnHover]
        Defaults[.expandNotchOnHover] = false
        hover(model, true)
        await step("hover", settle: 0.6)
        hover(model, false)
        await wait(0.6)
        // …and hover-to-expand (the default) with it on.
        Defaults[.expandNotchOnHover] = true
        hover(model, true)
        await step("hover-expand", settle: 0.7)
        hover(model, false)
        await wait(1.0)
        Defaults[.expandNotchOnHover] = false

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
        SystemBatteryManager.shared.present(.charging, force: true)
        await step("battery-charging", settle: 0.8)
        await wait(1.5)
        SystemBatteryManager.shared.present(.lowBattery, force: true)
        await step("battery-low", settle: 0.8)
        await wait(1.5)
        SystemBatteryManager.shared.present(.lowPowerOn, force: true)
        await step("battery-low-power", settle: 0.8)
        controller.dismissNotification()
        await wait(1)

        // Now Playing: play a tone and publish it as Foyer's own now-playing item.
        DemoMedia.start()
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
        LockScreenManager.shared.presenter.show(useSpace: false)
        await step("lockscreen-widgets", settle: 1.5)
        logWindows(name: "windows-lock.txt")
        LockScreenManager.shared.presenter.hide()
        controller.isScreenLocked = false
        await wait(1)

        // Settings window panes.
        AppShellModule.openSettings()
        await step("settings", settle: 1.5)
        NSApp.windows.filter { $0.isVisible && !($0 is OverlayPanel) }.forEach { $0.close() }
        await wait(0.5)

        DemoMedia.stop()

        Defaults[.expandNotchOnHover] = expandOnHover

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
        guard let model = NotchWindowManager.shared.primaryModel else { return "no-model" }
        let c = NotchController.shared
        let f = model.shapeFrame
        let panel = model.panel
        return [
            "presentation=\(model.presentation)",
            "shape=\(Int(f.width))x\(Int(f.height))",
            "hover=\(model.isHovering) expanded=\(model.isExpanded)",
            "hidden=\(model.isHidden) reasons=\(c.hideReasons.map { "\($0)" }.sorted()) fullscreen=\(c.fullscreenScreens.count)",
            "activities=\(c.orderedActivities.map(\.id.rawValue)) pages=\(c.pages.keys.map(\.rawValue).sorted())",
            "panel=\(panel.map { "\($0.frame) visible=\($0.isVisible) onActiveSpace=\($0.isOnActiveSpace) occlusion=\($0.occlusionState.contains(.visible))" } ?? "nil")",
        ].joined(separator: " ")
    }

    /// Logs on-screen windows above the normal level, to diagnose what may
    /// cover or hide the notch on a CI runner.
    private static func logWindows(name: String = "windows.txt") {
        let options: CGWindowListOption = [.optionOnScreenOnly]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return }
        var lines: [String] = []
        for w in info {
            let layer = (w[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            guard layer != 0 else { continue }
            let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
            let bounds = (w[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero
            let alpha = (w[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            lines.append("\(owner) layer=\(layer) bounds=\(bounds) alpha=\(alpha)")
        }
        let screens = NSScreen.screens.map { "\($0.frame) scale=\($0.backingScaleFactor) notch=\($0.hasHardwareNotch)" }
        write(name, contents: (["screens: \(screens)"] + lines).joined(separator: "\n"))
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

/// A short looping tone published through MPNowPlayingInfoCenter, so the real
/// Now Playing pipeline (MediaRemote → helper → Foyer) has something to show.
@MainActor
private enum DemoMedia {
    private static var player: AVAudioPlayer?

    static func start() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("foyer-demo-tone.wav")
        try? toneWAV().write(to: url)
        if let p = try? AVAudioPlayer(contentsOf: url) {
            p.numberOfLoops = -1
            p.volume = 0.2
            p.play()
            player = p
        }
        let artwork = NSImage(size: NSSize(width: 300, height: 300), flipped: false) { rect in
            let gradient = NSGradient(colors: [NSColor.systemPink, NSColor.systemPurple, NSColor.systemBlue])
            gradient?.draw(in: rect, angle: 45)
            return true
        }
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Foyer Test Tone — A Long Title That Should Scroll In The Marquee",
            MPMediaItemPropertyArtist: "Foyer CI",
            MPMediaItemPropertyAlbumTitle: "Capture",
            MPMediaItemPropertyPlaybackDuration: 120.0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 12.0,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            MPMediaItemPropertyArtwork: MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork },
        ]
        center.playbackState = .playing
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { _ in .success }
        commands.pauseCommand.addTarget { _ in .success }
        commands.togglePlayPauseCommand.addTarget { _ in .success }
        commands.nextTrackCommand.addTarget { _ in .success }
        commands.previousTrackCommand.addTarget { _ in .success }
    }

    static func stop() {
        player?.stop()
        player = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    /// 2 s of a soft 440 Hz tone as 16-bit mono PCM WAV.
    private static func toneWAV() -> Data {
        let rate = 44_100, seconds = 2
        let count = rate * seconds
        var samples = Data(capacity: count * 2)
        for i in 0..<count {
            let v = sin(2 * Double.pi * 440 * Double(i) / Double(rate)) * 0.25
            var s = Int16(v * Double(Int16.max)).littleEndian
            withUnsafeBytes(of: &s) { samples.append(contentsOf: $0) }
        }
        var data = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { var x = v.littleEndian; withUnsafeBytes(of: &x) { data.append(contentsOf: $0) } }
        data.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + samples.count))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(1)
        u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        data.append(contentsOf: Array("data".utf8)); u32(UInt32(samples.count))
        data.append(samples)
        return data
    }
}
