import SwiftUI

/// Lock-screen timings and layout. Sources: v3 "Lock-screen widget (now
/// OBSERVED)", Part D §4, Part E §4, Part F §9 of the teardown.
enum LockScreenConstants {

    // MARK: Detection

    /// `CGSessionCopyCurrentDictionary` key polled by Alcove's LockManager.
    static let sessionLockedKey = "CGSSessionScreenIsLocked"
    /// Polling cadence of the session dictionary (fallback to the
    /// distributed notifications).
    static let pollInterval: Double = 1
    /// A poll must disagree with the current state this many times in a row
    /// before it wins (lock/unlock debounce), so a notification that races
    /// ahead of the session dictionary is not undone.
    static let pollDebounceCount = 2
    /// Lock widget idle check cadence.
    static let idleCheckInterval: Double = 1

    // MARK: Widget timing (OBSERVED)

    /// The lock screen appears first; the widget stays absent for ~0.4 s.
    static let widgetAppearDelay: Double = 0.4
    /// …then fades/scales in over ~100-200 ms. LockManager's handler uses
    /// `withAnimation(.easeOut(duration: 0.15))` (Part E §4, STATIC).
    static let widgetFadeDuration: Double = 0.15
    static let widgetFade = Animation.easeOut(duration: widgetFadeDuration)
    /// Scale the widget grows from while fading in.
    static let widgetAppearScale: CGFloat = 0.94
    /// Blur the widget sheds while fading in.
    static let widgetAppearBlur: CGFloat = 6

    // MARK: Widget layout

    /// The Now Playing card measured ~344×162 pt, centred above the account
    /// avatar (1600×1200 capture, card x 628…972, y 785…947).
    static let largeWidgetWidth: CGFloat = 344
    /// Bottom edge of the widget stack above the bottom of the screen
    /// (1200 - 947 in the same capture; loginwindow anchors the avatar to
    /// the bottom, so a fixed inset tracks it on every screen size).
    static let widgetBottomInset: CGFloat = 253
    static let largeCornerRadius: CGFloat = 22
    static let smallCornerRadius: CGFloat = 18
    static let widgetSpacing: CGFloat = 10
    /// Transparent margin around the stack inside the panel (room for the
    /// shadow and the appear scale).
    static let panelMargin: CGFloat = 24
    /// Initial panel content size before the first measurement.
    static let initialContentSize = CGSize(width: 344, height: 162)

    // MARK: Notch glyph (Part D §4)

    /// The lock pill is the activity size: notch + 2 × 38 = 216 wide.
    static let lockWing: CGFloat = Constants.Geometry.activityWing
    static let lockGlyphSize: CGFloat = 12
    /// Above every other activity while locked.
    static let lockActivityPriority = 1_000

    // MARK: Window server

    /// Absolute level of the private CGS space holding the lock panels and
    /// the notch while locked: the "notification center at screen lock"
    /// level, above loginwindow's shield.
    static let spaceLevel: Int32 = 400

    // MARK: Keep awake (Part E §4, STATIC)

    /// LockManager takes three assertions at level 255 (kIOPMAssertionLevelOn).
    static let keepAwakeAssertionTypes = [
        "NoIdleSleepAssertion",
        "NoDisplaySleepAssertion",
        "PreventUserIdleDisplaySleep",
    ]
    static let keepAwakeAssertionName = "Foyer lock screen keep awake"
}
