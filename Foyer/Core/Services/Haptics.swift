import AppKit
import Defaults

/// One debounced wrapper over `NSHapticFeedbackManager.defaultPerformer`,
/// always `.now` (Part F §3). `.levelChange` for HUD steps, `.generic` for
/// notch clicks and swipes.
@MainActor
enum Haptics {
    private static var last: Date = .distantPast

    static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard Defaults[.enableHaptics] else { return }
        let now = Date()
        guard now.timeIntervalSince(last) > 0.05 else { return }
        last = now
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
