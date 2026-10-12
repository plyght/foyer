import Combine
import Defaults
import SwiftUI

/// Shared content state of the island: live activities, notifications, Quick
/// Peeks and expanded pages. Features publish into it; every on-screen notch
/// (one per target display) renders from it through its own `NotchViewModel`.
@MainActor
final class NotchController: ObservableObject {
    static let shared = NotchController()

    // MARK: Published content
    @Published private(set) var activities: [LiveActivityID: LiveActivity] = [:]
    @Published private(set) var dismissedActivities: [LiveActivityID] = []
    @Published private(set) var notification: NotchNotification?
    @Published private(set) var quickPeek: QuickPeek?
    @Published private(set) var pages: [ExpandedPageID: ExpandedPage] = [:]
    @Published private(set) var hideReasons: Set<HideReason> = []
    /// Screens (CGDirectDisplayID) currently showing a fullscreen space.
    @Published private(set) var fullscreenScreens: Set<CGDirectDisplayID> = []
    /// Cycle transition: content fades out, the notch sits empty, new content fades in.
    @Published private(set) var isCyclingActivity = false
    @Published private(set) var skipGlyph: SkipDirection?

    // MARK: Context flags set by features
    /// Set by the Focus feature.
    @Published var isFocusActive = false
    /// Set by the Lock feature.
    @Published var isScreenLocked = false
    /// Set by the visual-effects feature from backdrop luminance sampling.
    @Published var backdropIsDark = true

    /// Handler for media commands from gestures (installed by Now Playing).
    var mediaCommandHandler: ((MediaCommand) -> Void)?

    private var notificationTask: Task<Void, Never>?
    private var peekTask: Task<Void, Never>?
    private var cycleTask: Task<Void, Never>?
    private var skipGlyphTask: Task<Void, Never>?

    private init() {}

    // MARK: Live activities

    /// Inserts or replaces an activity.
    func setActivity(_ activity: LiveActivity) {
        let isNew = activities[activity.id] == nil
        withAnimation(isNew ? Constants.Animations.liveActivity : nil) {
            activities[activity.id] = activity
        }
    }

    func removeActivity(_ id: LiveActivityID) {
        guard activities[id] != nil || dismissedActivities.contains(id) else { return }
        withAnimation(Constants.Animations.liveActivity) {
            activities[id] = nil
            dismissedActivities.removeAll { $0 == id }
        }
    }

    /// Bumps an activity to "most recent" (used when `mostRecentActivity` is on).
    func touchActivity(_ id: LiveActivityID) {
        activities[id]?.updatedAt = .now
    }

    /// Ordered activities, excluding dismissed ones.
    var orderedActivities: [LiveActivity] {
        let mostRecent = Defaults[.mostRecentActivity]
        return activities.values
            .filter { !dismissedActivities.contains($0.id) }
            .sorted {
                // While locked, the lock glyph always leads.
                if self.isScreenLocked, $0.id == .lock || $1.id == .lock { return $0.id == .lock }
                if mostRecent, $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                if $0.priority != $1.priority { return $0.priority > $1.priority }
                return $0.id.rawValue < $1.id.rawValue
            }
    }

    var visibleActivity: LiveActivity? {
        isCyclingActivity ? nil : orderedActivities.first
    }

    func isDismissed(_ id: LiveActivityID) -> Bool { dismissedActivities.contains(id) }

    /// Swipe up on the compact notch: dismiss the visible activity; the next
    /// one fades in (fade out 117 ms, empty 467 ms, fade in 200 ms).
    func dismissVisibleActivity() {
        guard let current = orderedActivities.first else { return }
        runCycleTransition {
            self.dismissedActivities.append(current.id)
        }
    }

    /// Swipe down while something is dismissed: restore the last dismissed one.
    @discardableResult
    func restoreDismissedActivity() -> Bool {
        guard let last = dismissedActivities.last else { return false }
        runCycleTransition {
            self.dismissedActivities.removeAll { $0 == last }
            self.activities[last]?.updatedAt = .now
        }
        return true
    }

    /// Clears a dismissal without animation (e.g. when the activity's content
    /// changes meaningfully and should be shown again).
    func undismiss(_ id: LiveActivityID) {
        dismissedActivities.removeAll { $0 == id }
    }

    private func runCycleTransition(_ change: @escaping () -> Void) {
        cycleTask?.cancel()
        withAnimation(.easeOut(duration: Constants.Durations.cycleFadeOut)) {
            isCyclingActivity = true
        }
        cycleTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Constants.Durations.cycleFadeOut))
            withAnimation(Constants.Animations.liveActivity) { change() }
            try? await Task.sleep(for: .seconds(Constants.Durations.cycleEmpty))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: Constants.Durations.cycleFadeIn)) {
                self.isCyclingActivity = false
            }
        }
    }

    // MARK: Notifications

    /// Shows a notification, replacing any notification of the same kind and
    /// restarting its timer (HUD key repeats). Notifications of a filtered
    /// category are dropped while focused or locked, per the user's
    /// "Allowed Notifications" settings.
    func post(_ new: NotchNotification) {
        guard isAllowed(new.category) else { return }
        notificationTask?.cancel()
        if notification?.kind == new.kind {
            // Same kind (e.g. a repeated volume key): swap in place, views are
            // keyed by kind so nothing re-animates.
            notification = new
        } else {
            withAnimation(new.animation) { notification = new }
        }
        let duration = new.duration
        let animation = new.animation
        notificationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            withAnimation(animation) { self.notification = nil }
        }
    }

    /// Re-arms the timer of the visible notification of `kind` without
    /// replacing its views (used by HUDs whose views observe live values).
    func extendNotification(_ kind: NotificationKind, duration: TimeInterval) {
        guard let current = notification, current.kind == kind else { return }
        notificationTask?.cancel()
        let animation = current.animation
        notificationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            withAnimation(animation) { self.notification = nil }
        }
    }

    func dismissNotification(_ kind: NotificationKind? = nil) {
        guard let current = notification, kind == nil || current.kind == kind else { return }
        notificationTask?.cancel()
        withAnimation(current.animation) { notification = nil }
    }

    func isAllowed(_ category: NotificationCategory) -> Bool {
        if isFocusActive {
            switch category {
            case .battery where !Defaults[.allowBatteryWhenFocused]: return false
            case .connectivity where !Defaults[.allowConnectivityWhenFocused]: return false
            case .display where !Defaults[.allowBrightnessWhenFocused]: return false
            case .sound where !Defaults[.allowVolumeWhenFocused]: return false
            default: break
            }
        }
        if isScreenLocked {
            switch category {
            case .battery where !Defaults[.allowBatteryWhenLocked]: return false
            case .connectivity where !Defaults[.allowConnectivityWhenLocked]: return false
            case .focus where !Defaults[.allowFocusWhenLocked]: return false
            case .display where !Defaults[.allowBrightnessWhenLocked]: return false
            case .sound where !Defaults[.allowVolumeWhenLocked]: return false
            default: break
            }
        }
        return true
    }

    // MARK: Quick Peek

    func showQuickPeek(_ peek: QuickPeek) {
        peekTask?.cancel()
        withAnimation(Constants.Animations.quickPeekOpen) { quickPeek = peek }
        peekTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(peek.duration))
            guard !Task.isCancelled else { return }
            withAnimation(Constants.Animations.close) { self.quickPeek = nil }
        }
    }

    func dismissQuickPeek() {
        peekTask?.cancel()
        guard quickPeek != nil else { return }
        withAnimation(Constants.Animations.close) { quickPeek = nil }
    }

    // MARK: Expanded pages

    func registerPage(_ page: ExpandedPage) {
        pages[page.id] = page
    }

    func unregisterPage(_ id: ExpandedPageID) {
        pages[id] = nil
    }

    /// Pages in display order. When the idle activity is Duo and both halves
    /// exist, the Duo page leads.
    var orderedPages: [ExpandedPage] {
        var result = pages.values.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            return $0.id.rawValue < $1.id.rawValue
        }
        if Defaults[.idleActivity] == .duo, pages[.nowPlaying] != nil, pages[.calendar] != nil {
            let duo = ExpandedPage(id: .duo, width: Constants.Geometry.duoWidth, priority: .max,
                                   content: AnyView(DuoPage()))
            result.insert(duo, at: 0)
        }
        return result
    }

    // MARK: Visibility

    func setHidden(_ hidden: Bool, reason: HideReason) {
        withAnimation(Constants.Animations.standard) {
            if hidden { hideReasons.insert(reason) } else { hideReasons.remove(reason) }
        }
    }

    func setFullscreen(_ isFullscreen: Bool, screen: CGDirectDisplayID) {
        withAnimation(Constants.Animations.standard) {
            if isFullscreen { fullscreenScreens.insert(screen) } else { fullscreenScreens.remove(screen) }
        }
    }

    func isHidden(on screen: CGDirectDisplayID) -> Bool {
        if !hideReasons.isEmpty { return true }
        return Defaults[.hideWhileInFullscreen] && fullscreenScreens.contains(screen)
    }

    // MARK: Media gestures

    func send(_ command: MediaCommand) {
        mediaCommandHandler?(command)
        switch command {
        case .next: flashSkipGlyph(.next)
        case .previous: flashSkipGlyph(.previous)
        case .togglePlayPause: break
        }
    }

    private func flashSkipGlyph(_ direction: SkipDirection) {
        skipGlyphTask?.cancel()
        withAnimation(Constants.Animations.fadeFast) { skipGlyph = direction }
        skipGlyphTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Constants.Durations.skipGlyph))
            guard !Task.isCancelled else { return }
            withAnimation(Constants.Animations.fade) { self.skipGlyph = nil }
        }
    }
}

/// Duo page: Now Playing and Calendar side by side.
private struct DuoPage: View {
    var body: some View {
        HStack(spacing: 16) {
            NowPlayingDuoColumn()
                .frame(maxWidth: .infinity)
            CalendarDuoColumn()
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
}
