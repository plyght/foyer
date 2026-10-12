import Defaults
import SwiftUI

/// Lock-screen calendar widget (drawn on the lock feature's glass material):
/// the date on the left, the next two events of today (or tomorrow, marked
/// "Tomorrow") on the right.
struct CalendarLockWidget: View {
    @ObservedObject private var manager = CalendarManager.shared
    @Default(.useCalendarColor) private var useCalendarColor

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 30)) { context in
            let now = context.date
            let upcoming = upcomingEvents(now: now)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(CalendarFormat.weekday(now))
                        .font(.system(size: 11, weight: .bold))
                        .tracking(CalendarStyle.headerTracking)
                        .foregroundStyle(CalendarStyle.rose)
                    Text(CalendarFormat.dayNumber(now))
                        .font(.system(size: 30, weight: .regular))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
                .frame(minWidth: 56, alignment: .leading)

                VStack(alignment: .leading, spacing: 6) {
                    if !manager.hasAccess {
                        Text(String(localized: "Calendar access needed"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    } else if upcoming.events.isEmpty {
                        Text(String(localized: "No more events today"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(String(localized: "Your day is clear"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.6))
                    } else {
                        if upcoming.isTomorrow {
                            Text(String(localized: "Tomorrow").uppercased())
                                .font(.system(size: 10, weight: .bold))
                                .tracking(CalendarStyle.headerTracking)
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        ForEach(upcoming.events) { event in
                            row(event, now: now)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 260, maxWidth: .infinity, alignment: .leading)
        .environment(\.colorScheme, .dark)
    }

    private func upcomingEvents(now: Date) -> (events: [CalendarEventItem], isTomorrow: Bool) {
        let today = manager.remainingExpandedEventsToday(now: now).filter { !$0.isAllDay }
        if !today.isEmpty { return (Array(today.prefix(2)), false) }
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: now) else { return ([], false) }
        let next = manager.expandedEvents(on: tomorrow).filter { !$0.isAllDay }
        return (Array(next.prefix(2)), !next.isEmpty)
    }

    private func row(_ event: CalendarEventItem, now: Date) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(useCalendarColor ? event.calendarColor : CalendarStyle.rose)
                .frame(width: CalendarStyle.eventBarWidth, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(event.isInProgress(at: now)
                     ? String(localized: "Now · ends \(CalendarFormat.time(event.end))")
                     : CalendarFormat.timeRange(event.start, event.end))
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
        }
    }
}
