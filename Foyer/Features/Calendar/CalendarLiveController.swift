import AppKit
import Combine
import Defaults
import SwiftUI

/// Drives the calendar's presence in the notch: the compact `.calendar` live
/// activity (idle / countdown / ring), the Quick Peeks before and at event
/// start with the event sound, the hourly chime, and the expanded page.
///
/// Only ONE event is tracked at a time (Part D §1.2): the running event keeps
/// the activity until it ends; overlapping events are not announced.
@MainActor
final class CalendarLiveController: ObservableObject {
    static let shared = CalendarLiveController()

    enum Phase: Equatable {
        /// No event in range; the activity (if forced on) shows the date.
        case idle
        /// Next event starts within `timeBeforeEvent`: glyph + countdown.
        case upcoming
        /// Event running: glyph + progress ring.
        case inProgress
    }

    /// The event the compact activity follows.
    @Published private(set) var trackedEvent: CalendarEventItem?
    @Published private(set) var phase: Phase = .idle

    private let manager = CalendarManager.shared
    private var cancellables = Set<AnyCancellable>()
    private var tickTimer: Timer?
    private var chimeTimer: Timer?
    private var started = false

    /// Per-event bookkeeping so each peek/sound fires once.
    private var announcedBefore: Set<String> = []
    private var announcedStart: Set<String> = []
    /// Events the user dismissed from the menu ("Dismiss Event").
    private var dismissedEvents: Set<String> = []
    private var activityPhase: Phase?
    private var activityPriority: Int?
    private var pageRegistered = false

    private init() {}

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true

        // Mark everything already running or already inside the window as
        // announced, so launching mid-event does not replay peeks and sounds.
        let now = Date()
        let window = Defaults[.timeBeforeEvent] * 60
        for event in manager.activityEvents() where event.start <= now.addingTimeInterval(window) && event.end > now {
            announcedBefore.insert(event.id)
            if event.start <= now { announcedStart.insert(event.id) }
        }

        manager.$events
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)
        manager.$authorization
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updatePage() }
            .store(in: &cancellables)

        let keys: [Defaults._AnyKey] = [
            .enableCalendar, .timeBeforeEvent, .disableActivityDuringEvents, .idleActivity,
            .forceEnableActivity, .useCalendarColor,
        ]
        Defaults.publisher(keys: keys, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.updatePage()
                self?.evaluate()
            }
            .store(in: &cancellables)

        let timer = Timer(timeInterval: CalendarStyle.tickInterval, repeats: true) { [weak self] _ in
            _ = MainActor.assumeIsolated { self?.evaluate() }
        }
        timer.tolerance = 0.05
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer

        scheduleChime()
        updatePage()
        evaluate()
    }

    // MARK: Expanded page

    private func updatePage() {
        let wanted = Defaults[.enableCalendar] && Defaults[.idleActivity] != .none
        if wanted {
            NotchController.shared.registerPage(ExpandedPage(
                id: .calendar,
                priority: CalendarStyle.pagePriority,
                content: AnyView(CalendarExpandedView())))
            pageRegistered = true
        } else if pageRegistered {
            NotchController.shared.unregisterPage(.calendar)
            pageRegistered = false
        }
    }

    // MARK: Evaluation (every second)

    func evaluate() {
        let now = Date()
        guard Defaults[.enableCalendar], manager.hasAccess else {
            setTracked(nil, phase: .idle)
            updateActivity()
            return
        }

        let window = max(0, Defaults[.timeBeforeEvent]) * 60
        let candidates = manager.activityEvents().filter { !dismissedEvents.contains($0.id) && $0.end > now }

        // Keep following the tracked event while it is still pending/running.
        var next: CalendarEventItem?
        if let current = trackedEvent,
           let fresh = candidates.first(where: { $0.id == current.id }),
           fresh.start <= now.addingTimeInterval(window) {
            next = fresh
        } else if let running = candidates.first(where: { $0.isInProgress(at: now) }) {
            next = running
        } else if let upcoming = candidates.first(where: { $0.start > now && $0.start.timeIntervalSince(now) <= window }) {
            next = upcoming
        }

        if let event = next {
            let newPhase: Phase = event.isInProgress(at: now) ? .inProgress : .upcoming
            let isNewEvent = trackedEvent?.id != event.id
            setTracked(event, phase: newPhase)
            if isNewEvent {
                // A new event deserves to be seen even if the last one was swiped away.
                NotchController.shared.undismiss(.calendar)
            }
            announceIfNeeded(event, now: now, window: window)
        } else {
            setTracked(nil, phase: .idle)
        }
        updateActivity()
    }

    private func setTracked(_ event: CalendarEventItem?, phase newPhase: Phase) {
        if trackedEvent != event { trackedEvent = event }
        if phase != newPhase { phase = newPhase }
    }

    // MARK: Compact activity

    private func updateActivity() {
        let controller = NotchController.shared
        let enabled = Defaults[.enableCalendar]
        let idleAllowed = Defaults[.forceEnableActivity]
            && (Defaults[.idleActivity] == .calendar || Defaults[.idleActivity] == .duo)

        var show: Phase?
        switch phase {
        case .upcoming:
            show = .upcoming
        case .inProgress:
            if !Defaults[.disableActivityDuringEvents] {
                show = .inProgress
            } else if idleAllowed {
                show = .idle
            }
        case .idle:
            if idleAllowed && manager.hasAccess { show = .idle }
        }
        if !enabled { show = nil }

        guard let shown = show else {
            if activityPhase != nil {
                controller.removeActivity(.calendar)
                activityPhase = nil
                activityPriority = nil
            }
            return
        }

        let priority: Int
        switch shown {
        case .upcoming: priority = CalendarStyle.upcomingPriority
        case .inProgress: priority = CalendarStyle.inProgressPriority
        case .idle: priority = CalendarStyle.idlePriority
        }
        guard shown != activityPhase || priority != activityPriority || controller.activities[.calendar] == nil else { return }
        activityPhase = shown
        activityPriority = priority
        controller.setActivity(LiveActivity(
            id: .calendar,
            wingWidth: CalendarStyle.wing,
            priority: priority,
            leading: AnyView(CalendarCompactLeading()),
            trailing: AnyView(CalendarCompactTrailing())))
        if shown != .idle { controller.touchActivity(.calendar) }
    }

    // MARK: Peeks and sounds

    private func announceIfNeeded(_ event: CalendarEventItem, now: Date, window: TimeInterval) {
        // T - timeBeforeEvent: "Before event starts" peek.
        if event.start > now, !announcedBefore.contains(event.id) {
            announcedBefore.insert(event.id)
            if Defaults[.enableCalendarQuickPeek] && Defaults[.beforeEventStarts] {
                showPeek(for: event, stage: .before)
                playEventSound()
            }
        }
        // T = start: "When event is starting" peek (this IS the event notification).
        if event.start <= now, !announcedStart.contains(event.id) {
            announcedStart.insert(event.id)
            announcedBefore.insert(event.id)
            // Do not announce events that started long ago (e.g. after wake).
            guard now.timeIntervalSince(event.start) < 60 else { return }
            if Defaults[.enableCalendarQuickPeek] {
                if Defaults[.whenEventIsStarting] { showPeek(for: event, stage: .starting) }
            } else {
                postStartNotification(for: event)
            }
            playEventSound()
        }
    }

    private func playEventSound() {
        guard Defaults[.playSoundOnCalendarEvent] else { return }
        SoundPlayer.play(.event)
    }

    private func showPeek(for event: CalendarEventItem, stage: CalendarPeekView.Stage) {
        NotchController.shared.showQuickPeek(QuickPeek(
            source: .calendar,
            duration: Defaults[.calendarPeekDuration],
            content: AnyView(CalendarPeekView(event: event, stage: stage))))
    }

    /// Fallback when Quick Peek is off: a one-row notification in the wings.
    private func postStartNotification(for event: CalendarEventItem) {
        NotchController.shared.post(NotchNotification(
            kind: .calendarEvent,
            category: .other,
            wingWidth: Constants.Geometry.hudWing,
            duration: Defaults[.calendarPeekDuration],
            leading: AnyView(CalendarEventNotificationLeading(event: event)),
            trailing: AnyView(CalendarEventNotificationTrailing(event: event))))
    }

    // MARK: Hourly chime (sound only, Part D §8.2)

    private func scheduleChime() {
        chimeTimer?.invalidate()
        let cal = Calendar.current
        let now = Date()
        guard let nextHour = cal.nextDate(after: now, matching: DateComponents(minute: 0, second: 0),
                                          matchingPolicy: .nextTime) else { return }
        let timer = Timer(fire: nextHour, interval: 0, repeats: false) { [weak self] _ in
            _ = MainActor.assumeIsolated {
                self?.chime()
                self?.scheduleChime()
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        chimeTimer = timer
    }

    private func chime() {
        guard Defaults[.enableCalendar], Defaults[.playHourlyChime] else { return }
        // Skip when the top of the hour is long past (timer delayed by sleep).
        let minute = Calendar.current.component(.minute, from: Date())
        guard minute == 0 else { return }
        SoundPlayer.play(.chime)
    }

    // MARK: Menu actions (for the menu-bar item while an event is active)

    /// "Dismiss Event": stop following the current event.
    func dismissTrackedEvent() {
        guard let event = trackedEvent else { return }
        dismissedEvents.insert(event.id)
        NotchController.shared.dismissQuickPeek()
        evaluate()
    }

    /// "Open in Calendar".
    func openTrackedEvent() {
        manager.open(trackedEvent)
    }

    /// The event's meeting link, if any ("Join %@").
    var trackedEventJoinURL: URL? {
        guard let event = trackedEvent else { return nil }
        if let url = event.url, url.scheme?.hasPrefix("http") == true { return url }
        if let location = event.location,
           let url = URL(string: location), url.scheme?.hasPrefix("http") == true {
            return url
        }
        return nil
    }
}
