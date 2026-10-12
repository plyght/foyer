import AppKit
import QuartzCore

final class ClockDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    let clock = NSTextField(labelWithString: "Ready: process-cold launch, warm filesystem cache")
    let status = NSTextField(labelWithString: "One launch only. No onboarding or license changes.")
    var started: CFTimeInterval?
    var timer: Timer?
    var button: NSButton!
    func applicationDidFinishLaunching(_ note: Notification) {
        window = NSWindow(contentRect: NSRect(x: 40, y: 80, width: 740, height: 160),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Alcove process-cold launch clock (warm filesystem cache)"
        clock.frame = NSRect(x: 20, y: 112, width: 700, height: 24)
        clock.font = .monospacedSystemFont(ofSize: 18, weight: .medium)
        status.frame = NSRect(x: 20, y: 78, width: 700, height: 24)
        button = NSButton(title: "Launch Alcove once", target: self, action: #selector(launch))
        button.frame = NSRect(x: 20, y: 20, width: 190, height: 34)
        let stop = NSButton(title: "Stop clock helper", target: NSApp, action: #selector(NSApplication.terminate(_:)))
        stop.frame = NSRect(x: 230, y: 20, width: 180, height: 34)
        [clock, status, button, stop].forEach { window.contentView!.addSubview($0) }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func launch() {
        guard started == nil else { return }
        started = CACurrentMediaTime()
        let stamp = Date().ISO8601Format()
        status.stringValue = "Launch requested: \(stamp)"
        print("LAUNCH_REQUEST \(stamp)")
        fflush(stdout)
        button.isEnabled = false
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self, let start = self.started else { return }
            let elapsed = CACurrentMediaTime() - start
            self.clock.stringValue = String(format: "Launch elapsed: %.3f s • WARM FILESYSTEM CACHE", elapsed)
            if elapsed > 8 { timer.invalidate() }
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/Alcove.app"), configuration: config) { app, error in
            DispatchQueue.main.async {
                let elapsed = CACurrentMediaTime() - (self.started ?? CACurrentMediaTime())
                print("OPEN_COMPLETION pid=\(app?.processIdentifier ?? -1) elapsed=\(elapsed) error=\(String(describing: error))")
                fflush(stdout)
            }
        }
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = ClockDelegate()
app.delegate = delegate
app.run()
