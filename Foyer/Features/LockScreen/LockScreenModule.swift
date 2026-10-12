import AppKit

/// Lock screen: lock/unlock and screen-saver detection, the lock glyph in the
/// notch, the widget panels above loginwindow (in a private CGS space), lock
/// and unlock sounds, keep awake and the idle hide.
enum LockScreenModule {
    @MainActor
    static func start() {
        LockScreenManager.shared.start()
    }

    @MainActor
    static func stop() {
        LockScreenManager.shared.stop()
    }
}
