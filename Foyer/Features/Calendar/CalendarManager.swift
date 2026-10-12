import AppKit
import Combine
import CoreLocation
import Defaults
import EventKit
import SwiftUI

/// A calendar event occurrence, copied out of EventKit so views never touch
/// `EKEvent` (which is not thread-safe and changes under the store).
struct CalendarEventItem: Identifiable, Equatable {
    /// Unique per occurrence (recurring events share `eventIdentifier`).
    let id: String
    let eventIdentifier: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let calendarID: String
    let calendarTitle: String
    let calendarColor: Color
    let isBirthday: Bool
    let location: String?
    let coordinate: CLLocationCoordinate2D?
    let url: URL?
    /// Routing from `calendarDisplayModes`.
    let showsInActivity: Bool
    let showsInExpanded: Bool

    var duration: TimeInterval { end.timeIntervalSince(start) }

    func isInProgress(at date: Date) -> Bool { start <= date && date < end }

    /// Elapsed fraction 0…1 while running.
    func progress(at date: Date) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, date.timeIntervalSince(start) / duration))
    }

    static func == (lhs: CalendarEventItem, rhs: CalendarEventItem) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.start == rhs.start && lhs.end == rhs.end
            && lhs.calendarID == rhs.calendarID && lhs.isAllDay == rhs.isAllDay
            && lhs.location == rhs.location && lhs.showsInActivity == rhs.showsInActivity
            && lhs.showsInExpanded == rhs.showsInExpanded
    }
}

/// A calendar row for the settings pane (`excludedCalendars`, `calendarDisplayModes`).
struct CalendarSourceItem: Identifiable, Equatable {
    let id: String
    let title: String
    let color: Color
    let sourceTitle: String
    let isBirthdays: Bool
    let isSubscribed: Bool
}

/// EventKit access: authorization, calendars, and the events of the visible
/// month plus tomorrow. Everything else in the feature reads from here.
@MainActor
final class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    let store = EKEventStore()

    @Published private(set) var authorization: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var calendars: [CalendarSourceItem] = []
    /// All loaded occurrences (included calendars only), sorted by start.
    @Published private(set) var events: [CalendarEventItem] = []
    /// Bumped on midnight so date-dependent views refresh.
    @Published private(set) var today: Date = Calendar.current.startOfDay(for: Date())

    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var reloadTask: Task<Void, Never>?
    private var started = false

    private init() {}

    var hasAccess: Bool {
        switch authorization {
        case .fullAccess: return true
        case .authorized: return true
        default: return false
        }
    }

    var canRequestAccess: Bool { authorization == .notDetermined }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            _ = MainActor.assumeIsolated { self?.scheduleReload() }
        })
        observers.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            _ = MainActor.assumeIsolated { self?.dayChanged() }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            _ = MainActor.assumeIsolated { self?.refreshAuthorization() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            _ = MainActor.assumeIsolated { self?.dayChanged() }
        })

        let keys: [Defaults._AnyKey] = [.excludedCalendars, .calendarDisplayModes, .enableCalendar]
        Defaults.publisher(keys: keys, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.scheduleReload() }
            .store(in: &cancellables)

        // Onboarding asks on first launch; afterwards ask once if it never happened.
        if authorization == .notDetermined, !Defaults[.isFirstLaunch], !Defaults[.hasPromptedCalendarPermission] {
            requestAccess()
        }
        reload()
    }

    /// Asks for full access (macOS 14+ API). Safe to call repeatedly; when the
    /// user already denied, opens the Calendars privacy pane instead.
    func requestAccess() {
        Defaults[.hasPromptedCalendarPermission] = true
        switch authorization {
        case .notDetermined:
            NSApp.activate()
            let store = self.store
            Task { @MainActor [weak self] in
                _ = try? await store.requestFullAccessToEvents()
                self?.refreshAuthorization()
            }
        case .denied, .restricted, .writeOnly:
            openPrivacySettings()
        default:
            refreshAuthorization()
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func refreshAuthorization() {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status != authorization {
            authorization = status
            if hasAccess { store.refreshSourcesIfNecessary() }
        }
        reload()
    }

    private func dayChanged() {
        let start = Calendar.current.startOfDay(for: Date())
        if start != today { today = start }
        reload()
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(CalendarStyle.reloadDebounce))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    // MARK: Loading

    func reload() {
        let start = Calendar.current.startOfDay(for: Date())
        if start != today { today = start }

        guard hasAccess else {
            if !calendars.isEmpty { calendars = [] }
            if !events.isEmpty { events = [] }
            return
        }

        let ekCalendars = store.calendars(for: .event)
        let sources = ekCalendars
            .map { cal in
                CalendarSourceItem(id: cal.calendarIdentifier,
                                   title: cal.title,
                                   color: CalendarManager.color(of: cal),
                                   sourceTitle: cal.source?.title ?? "",
                                   isBirthdays: cal.type == .birthday,
                                   isSubscribed: cal.isSubscribed)
            }
            .sorted { lhs, rhs in
                if lhs.sourceTitle != rhs.sourceTitle { return lhs.sourceTitle < rhs.sourceTitle }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        if sources != calendars { calendars = sources }

        guard Defaults[.enableCalendar] else {
            if !events.isEmpty { events = [] }
            return
        }

        let excluded = Set(Defaults[.excludedCalendars])
        let modes = Defaults[.calendarDisplayModes]
        let included = ekCalendars.filter { !excluded.contains($0.calendarIdentifier) }
        guard !included.isEmpty else {
            if !events.isEmpty { events = [] }
            return
        }

        // Visible month (for indicator dots) through tomorrow (for "TMRW").
        let cal = Calendar.current
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today
        let nextMonth = cal.date(byAdding: .month, value: 1, to: monthStart) ?? today.addingTimeInterval(31 * 86_400)
        let dayAfterTomorrow = cal.date(byAdding: .day, value: 2, to: today) ?? today.addingTimeInterval(2 * 86_400)
        let rangeStart = min(monthStart, today)
        let rangeEnd = max(nextMonth, dayAfterTomorrow)

        let predicate = store.predicateForEvents(withStart: rangeStart, end: rangeEnd, calendars: included)
        let loaded = store.events(matching: predicate).compactMap { event -> CalendarEventItem? in
            CalendarManager.item(from: event, modes: modes)
        }
        .sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            return lhs.title < rhs.title
        }
        if loaded != events { events = loaded }
    }

    private static func item(from event: EKEvent, modes: [String: CalendarDisplayMode]) -> CalendarEventItem? {
        guard let start = event.startDate, let end = event.endDate else { return nil }
        if event.status == .canceled { return nil }
        let calendar: EKCalendar? = event.calendar
        let calendarID = calendar?.calendarIdentifier ?? ""
        let mode = modes[calendarID] ?? .both
        let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
        let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CalendarEventItem(
            id: "\(identifier)|\(Int(start.timeIntervalSince1970))",
            eventIdentifier: identifier,
            title: title.isEmpty ? String(localized: "New Event") : title,
            start: start,
            end: max(end, start),
            isAllDay: event.isAllDay,
            calendarID: calendarID,
            calendarTitle: calendar?.title ?? "",
            calendarColor: calendar.map { color(of: $0) } ?? CalendarStyle.rose,
            isBirthday: calendar?.type == .birthday,
            location: (location?.isEmpty ?? true) ? nil : location,
            coordinate: event.structuredLocation?.geoLocation?.coordinate,
            url: event.url,
            showsInActivity: mode != .notification,
            showsInExpanded: mode != .activity)
    }

    private static func color(of calendar: EKCalendar) -> Color {
        if let ns = calendar.color { return Color(nsColor: ns) }
        return CalendarStyle.rose
    }

    // MARK: Queries

    /// Events of `day` shown in the expanded view (all-day first, then timed).
    func expandedEvents(on day: Date) -> [CalendarEventItem] {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
        return events.filter { event in
            event.showsInExpanded && event.start < dayEnd && event.end > dayStart
        }
        .sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            return lhs.start < rhs.start
        }
    }

    /// Today's expanded events that have not ended yet (all-day kept all day).
    func remainingExpandedEventsToday(now: Date = Date()) -> [CalendarEventItem] {
        expandedEvents(on: now).filter { $0.isAllDay || $0.end > now }
    }

    /// Timed events that drive the compact activity, peeks and time to leave.
    func activityEvents() -> [CalendarEventItem] {
        events.filter { $0.showsInActivity && !$0.isAllDay }
    }

    /// Day-of-month → indicator colour for the given month.
    func indicatorColors(forMonthOf date: Date, useCalendarColor: Bool) -> [Int: Color] {
        let cal = Calendar.current
        var result: [Int: Color] = [:]
        for event in events where event.showsInExpanded {
            guard cal.isDate(event.start, equalTo: date, toGranularity: .month) else { continue }
            let day = cal.component(.day, from: event.start)
            if result[day] == nil {
                result[day] = useCalendarColor ? event.calendarColor : Color.white.opacity(0.6)
            }
        }
        return result
    }

    // MARK: Actions

    /// Opens the event in Calendar.app (`ical://ekevent/<id>`).
    func open(_ event: CalendarEventItem?) {
        if let event,
           let encoded = event.eventIdentifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
           let url = URL(string: "ical://ekevent/\(encoded)?method=show&options=more"),
           NSWorkspace.shared.open(url) {
            return
        }
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }
}
