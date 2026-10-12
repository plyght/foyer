import SwiftUI

/// Long-lived activities that occupy the compact notch (notch + two wings).
/// Only one is visible at a time; swiping cycles between them.
enum LiveActivityID: String, CaseIterable, Hashable {
    case nowPlaying, calendar, focus, lock, timeToLeave, game
}

/// A live activity published by a feature. Views are type-erased so features
/// stay decoupled from the core; they should observe their own managers so
/// they update without re-publishing.
struct LiveActivity: Identifiable {
    let id: LiveActivityID
    /// Width of each wing beside the notch (Calendar 38 → 216, Now Playing 41 → 222).
    var wingWidth: CGFloat = Constants.Geometry.activityWing
    /// Higher wins when `mostRecentActivity` is off.
    var priority: Int = 0
    var updatedAt: Date = .now
    var leading: AnyView
    var trailing: AnyView
}

/// Transient notifications (HUDs and alerts). They replace the compact content
/// for `duration` seconds, then the previous state returns.
enum NotificationKind: String, Hashable {
    case volume, brightness, keyboardBacklight
    case battery, lowPower
    case connectivity
    case focus
    case calendarEvent, timeToLeave
    case lockState
    case update
    case generic
}

/// Category used for the "Allowed Notifications" filters while focused/locked.
enum NotificationCategory: Hashable {
    case battery, connectivity, focus, display, sound, other
}

struct NotchNotification: Identifiable {
    let id = UUID()
    var kind: NotificationKind
    var category: NotificationCategory = .other
    var wingWidth: CGFloat = Constants.Geometry.activityWing
    /// nil keeps the closed notch height (one row).
    var height: CGFloat? = nil
    var duration: TimeInterval
    /// Animation used to open/close the notification (HUDs use `Constants.Animations.hud`).
    var animation: Animation = Constants.Animations.notification
    var leading: AnyView
    var trailing: AnyView
    /// Optional content drawn under the wings when `height` is taller than the notch.
    var body: AnyView? = nil
}

/// The two-row Quick Peek capsule (233x70) shown briefly when media changes or
/// an event is about to start.
struct QuickPeek: Identifiable {
    let id = UUID()
    var source: LiveActivityID
    var duration: TimeInterval
    var extraWidth: CGFloat = Constants.Geometry.peekExtraWidth
    var height: CGFloat = Constants.Geometry.peekHeight
    var content: AnyView
}

enum ExpandedPageID: String, CaseIterable, Hashable {
    case nowPlaying, calendar, duo
}

/// A page of the expanded notch. Swiping down inside the expanded panel cycles
/// pages.
struct ExpandedPage: Identifiable {
    let id: ExpandedPageID
    /// nil uses the base expanded width (max(W+160, 345) + 17).
    var width: CGFloat? = nil
    /// nil uses the base expanded height (max(H+142, 175)).
    var height: CGFloat? = nil
    var priority: Int = 0
    var content: AnyView
}

enum HideReason: Hashable {
    case fullscreen, missionControl, gaming, sourceAppActive, screenSaver, locked, user
}

enum MediaCommand {
    case togglePlayPause, next, previous
}

enum SkipDirection { case previous, next }

/// The active Focus mode, published by the Focus feature
/// (`FocusManager.shared.currentFocus`) and read by others.
struct FocusMode: Equatable {
    var identifier: String
    var name: String
    var symbolName: String
    var tint: Color
    var isSleep: Bool
}
