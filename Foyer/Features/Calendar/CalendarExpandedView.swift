import Defaults
import SwiftUI

// MARK: - Row model

/// One row of the day column (Part D §1.3).
enum CalendarRowModel: Identifiable {
    case event(CalendarEventItem)
    /// "2 all-day events" pill with each calendar's coloured glyph.
    case allDaySummary(count: Int, colors: [Color])
    /// "3 more events" with stacked coloured bars.
    case more(count: Int, colors: [Color])

    var id: String {
        switch self {
        case .event(let event): return event.id
        case .allDaySummary(let count, _): return "allday-\(count)"
        case .more(let count, _): return "more-\(count)"
        }
    }
}

/// Splits the day's events into the left column, an optional right-column
/// continuation, and decides when the month grid is shown.
enum CalendarRowBuilder {
    struct Layout {
        var left: [CalendarRowModel]
        /// Rows continued in the right column (instead of the month grid).
        var right: [CalendarRowModel]
        var showsMonth: Bool { right.isEmpty }
    }

    static func layout(events: [CalendarEventItem], now: Date, capacity: Int,
                       alwaysShowMonth: Bool, allowOverflowColumn: Bool) -> Layout {
        guard !events.isEmpty, capacity > 0 else { return Layout(left: [], right: []) }

        if alwaysShowMonth {
            return Layout(left: condensed(events: events, now: now, capacity: capacity), right: [])
        }

        let rows = events.map { CalendarRowModel.event($0) }
        if rows.count <= capacity {
            return Layout(left: rows, right: [])
        }
        guard allowOverflowColumn else {
            return Layout(left: truncated(events: events, capacity: capacity), right: [])
        }
        let left = Array(rows.prefix(capacity))
        let rest = Array(events.dropFirst(capacity))
        return Layout(left: left, right: truncated(events: rest, capacity: capacity))
    }

    /// Up to `capacity` rows, the last replaced by "N more events" when needed.
    static func truncated(events: [CalendarEventItem], capacity: Int) -> [CalendarRowModel] {
        if events.count <= capacity { return events.map { CalendarRowModel.event($0) } }
        let shown = max(0, capacity - 1)
        var rows = events.prefix(shown).map { CalendarRowModel.event($0) }
        let hidden = Array(events.dropFirst(shown))
        rows.append(.more(count: hidden.count, colors: hidden.prefix(3).map { $0.calendarColor }))
        return rows
    }

    /// "Always show month view": all-day summary, the current/next timed event,
    /// then "N more events".
    static func condensed(events: [CalendarEventItem], now: Date, capacity: Int) -> [CalendarRowModel] {
        var rows: [CalendarRowModel] = []
        let allDay = events.filter { $0.isAllDay }
        let timed = events.filter { !$0.isAllDay }

        if allDay.count == 1, let only = allDay.first {
            rows.append(.event(only))
        } else if allDay.count > 1 {
            rows.append(.allDaySummary(count: allDay.count, colors: allDay.prefix(3).map { $0.calendarColor }))
        }
        if let next = timed.first(where: { $0.end > now }) ?? timed.first {
            rows.append(.event(next))
            let others = timed.filter { $0.id != next.id && $0.end > now }
            if !others.isEmpty {
                rows.append(.more(count: others.count, colors: others.prefix(3).map { $0.calendarColor }))
            }
        }
        if rows.count > capacity {
            rows = Array(rows.prefix(capacity))
        }
        return rows
    }
}

// MARK: - Expanded page

/// Expanded `.calendar` page, 175 tall at the base width: left column = rose
/// weekday, large day number, events or the empty state; right column = the
/// month grid or the continuation of the event list.
struct CalendarExpandedView: View {
    @ObservedObject private var manager = CalendarManager.shared
    @ObservedObject private var weather = WeatherManager.shared
    @Environment(\.notchGeometry) private var geometry

    @Default(.alwaysShowMonthView) private var alwaysShowMonthView
    @Default(.useEventIndicators) private var useEventIndicators
    @Default(.useCalendarColor) private var useCalendarColor
    @Default(.showWeatherOnEmptyDay) private var showWeatherOnEmptyDay

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 30)) { context in
            content(now: context.date)
        }
        .onAppear {
            if showWeatherOnEmptyDay { weather.refreshIfNeeded() }
        }
    }

    private var topInset: CGFloat {
        geometry.hasHardwareNotch ? geometry.closedSize.height + 4 : CalendarStyle.expandedTopInset
    }

    private var pageHeight: CGFloat {
        geometry.expandedSize.height > 0 ? geometry.expandedSize.height : Constants.Geometry.expandedMinHeight
    }

    /// Two-line event rows fit three to a column on a simulated notch; below
    /// a hardware notch only two.
    private var capacity: Int {
        geometry.hasHardwareNotch ? CalendarStyle.rowsPerColumn - 1 : CalendarStyle.rowsPerColumn
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let events = manager.remainingExpandedEventsToday(now: now)
        let hadEvents = !manager.expandedEvents(on: now).isEmpty
        let layout = CalendarRowBuilder.layout(events: events, now: now, capacity: capacity,
                                               alwaysShowMonth: alwaysShowMonthView,
                                               allowOverflowColumn: true)

        HStack(alignment: .top, spacing: CalendarStyle.columnSpacing) {
            VStack(alignment: .leading, spacing: 0) {
                CalendarDateHeader(date: now)
                if !manager.hasAccess {
                    CalendarAccessPrompt()
                        .padding(.top, 8)
                } else if layout.left.isEmpty {
                    CalendarEmptyDayView(hadEventsToday: hadEvents,
                                         weather: showWeatherOnEmptyDay ? weather.snapshot : nil)
                        .padding(.top, 10)
                } else {
                    CalendarRowsView(rows: layout.left, now: now)
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if layout.showsMonth {
                    CalendarMonthGridView(
                        month: now,
                        today: now,
                        indicators: useEventIndicators
                            ? manager.indicatorColors(forMonthOf: now, useCalendarColor: useCalendarColor)
                            : [:],
                        availableHeight: pageHeight - topInset - CalendarStyle.expandedBottomInset)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(CalendarFormat.dayHeader(now))
                            .font(.system(size: CalendarStyle.headerFontSize, weight: .bold))
                            .tracking(CalendarStyle.headerTracking)
                            .foregroundStyle(CalendarStyle.secondaryText)
                            .lineLimit(1)
                        CalendarRowsView(rows: layout.right, now: now)
                            .padding(.top, 8)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.top, topInset)
        .padding(.leading, CalendarStyle.expandedLeadingInset)
        .padding(.trailing, CalendarStyle.expandedTrailingInset)
        .padding(.bottom, CalendarStyle.expandedBottomInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Day column pieces

/// "SUNDAY" (rose, ~11 pt bold, letter-spaced) over "11" (white, ~34 pt).
struct CalendarDateHeader: View {
    let date: Date
    var numberSize: CGFloat = CalendarStyle.dayNumberSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(CalendarFormat.weekday(date))
                .font(.system(size: CalendarStyle.headerFontSize, weight: .bold))
                .tracking(CalendarStyle.headerTracking)
                .foregroundStyle(CalendarStyle.rose)
                .lineLimit(1)
            Text(CalendarFormat.dayNumber(date))
                .font(.system(size: numberSize, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.top, -2)
        }
    }
}

/// "No events today / Your day is clear", or the weather when enabled.
struct CalendarEmptyDayView: View {
    let hadEventsToday: Bool
    let weather: CalendarWeatherSnapshot?

    var body: some View {
        if let weather {
            CalendarWeatherSummary(snapshot: weather)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(hadEventsToday ? String(localized: "No more events today") : String(localized: "No events today"))
                    .font(.system(size: CalendarStyle.eventTitleSize, weight: .semibold))
                    .foregroundStyle(.white)
                Text(String(localized: "Your day is clear"))
                    .font(.system(size: CalendarStyle.eventTimeSize, weight: .medium))
                    .foregroundStyle(CalendarStyle.secondaryText)
            }
            .padding(.top, 14)
        }
    }
}

/// Weather shown on an empty day: symbol, temperature, condition, high/low.
struct CalendarWeatherSummary: View {
    let snapshot: CalendarWeatherSnapshot

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: snapshot.symbolName)
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 24, weight: .medium))
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(WeatherFormat.temperature(snapshot.temperature))
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                Text(snapshot.condition)
                    .font(.system(size: CalendarStyle.eventTimeSize, weight: .medium))
                    .foregroundStyle(CalendarStyle.secondaryText)
                    .lineLimit(1)
                Text(WeatherFormat.highLow(snapshot))
                    .font(.system(size: CalendarStyle.eventTimeSize, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(CalendarStyle.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.top, 4)
    }
}

/// Shown when calendar access is missing (Alcove's `CalendarPermissionView`).
struct CalendarAccessPrompt: View {
    @ObservedObject private var manager = CalendarManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Foyer needs your permission to display your upcoming calendar events."))
                .font(.system(size: CalendarStyle.eventTimeSize, weight: .medium))
                .foregroundStyle(CalendarStyle.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)
            Button {
                manager.requestAccess()
            } label: {
                Text(manager.canRequestAccess ? String(localized: "Allow Access") : String(localized: "Open Settings"))
                    .font(.system(size: CalendarStyle.eventTitleSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(CalendarStyle.rose))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

/// A vertical stack of rows.
struct CalendarRowsView: View {
    let rows: [CalendarRowModel]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: CalendarStyle.eventRowSpacing) {
            ForEach(rows) { row in
                switch row {
                case .event(let event):
                    CalendarEventRowView(event: event, now: now)
                case .allDaySummary(let count, let colors):
                    CalendarSummaryRow(
                        text: count == 1 ? String(localized: "1 all-day event") : String(localized: "\(count) all-day events"),
                        colors: colors, style: .glyphs)
                case .more(let count, let colors):
                    CalendarSummaryRow(
                        text: count == 1 ? String(localized: "1 more event") : String(localized: "\(count) more events"),
                        colors: colors, style: .bars)
                }
            }
        }
    }
}

/// One event: all-day = glyph pill on one line; timed = 3 px bar, title, time
/// range on a tinted rounded background.
struct CalendarEventRowView: View {
    let event: CalendarEventItem
    let now: Date

    @Default(.useCalendarColor) private var useCalendarColor

    private var tint: Color { useCalendarColor ? event.calendarColor : CalendarStyle.rose }
    private var titleColor: Color {
        if event.isBirthday { return Color.white.opacity(0.75) }
        return useCalendarColor ? event.calendarColor : .white
    }
    private var background: Color {
        if event.isBirthday { return Color.white.opacity(0.08) }
        return useCalendarColor ? event.calendarColor.opacity(0.16) : Color.white.opacity(0.08)
    }

    var body: some View {
        Group {
            if event.isAllDay {
                HStack(spacing: 5) {
                    Image(systemName: event.isBirthday ? "gift.circle.fill" : "calendar.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(event.isBirthday ? Color.white.opacity(0.6) : event.calendarColor)
                    Text(event.title)
                        .font(.system(size: CalendarStyle.eventTitleSize, weight: .semibold))
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
            } else {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(tint)
                        .frame(width: CalendarStyle.eventBarWidth)
                        .padding(.vertical, 1)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(event.title)
                            .font(.system(size: CalendarStyle.eventTitleSize, weight: .semibold))
                            .foregroundStyle(titleColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(CalendarFormat.timeRange(event.start, event.end))
                            .font(.system(size: CalendarStyle.eventTimeSize, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(useCalendarColor ? event.calendarColor.opacity(0.75) : CalendarStyle.secondaryText)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .opacity(event.end <= now ? 0.5 : 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CalendarStyle.eventRowCorner, style: .continuous)
                .fill(background))
    }
}

/// "2 all-day events" / "3 more events".
struct CalendarSummaryRow: View {
    enum Style { case glyphs, bars }

    let text: String
    let colors: [Color]
    let style: Style

    @Default(.useCalendarColor) private var useCalendarColor

    var body: some View {
        HStack(spacing: 5) {
            switch style {
            case .glyphs:
                HStack(spacing: -4) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { item in
                        Image(systemName: "calendar.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(item.element)
                            .background(Circle().fill(Color.black).padding(-1))
                    }
                }
            case .bars:
                HStack(spacing: 2) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { item in
                        RoundedRectangle(cornerRadius: 1, style: .continuous)
                            .fill(useCalendarColor ? item.element : CalendarStyle.rose)
                            .frame(width: 2, height: 12)
                    }
                }
            }
            Text(text)
                .font(.system(size: CalendarStyle.eventTitleSize, weight: .semibold))
                .foregroundStyle(CalendarStyle.secondaryText)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
    }
}

// MARK: - Month grid

/// Rose month name, weekday letters (locale's first weekday), day numbers in
/// a 21 x 20 grid; weekend greyed; today in a filled rose circle; optional
/// 2-3 px event dots under the day number.
struct CalendarMonthGridView: View {
    let month: Date
    let today: Date
    /// Day of month → dot colour (empty when indicators are off).
    let indicators: [Int: Color]
    let availableHeight: CGFloat

    private var calendar: Calendar { Calendar.current }

    private var monthStart: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
    }

    private var dayCount: Int {
        calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
    }

    /// Blank cells before day 1.
    private var leadingBlanks: Int {
        let weekday = calendar.component(.weekday, from: monthStart)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var rowCount: Int {
        Int(ceil(Double(leadingBlanks + dayCount) / 7))
    }

    /// Header block: month name + spacing + weekday letters + spacing.
    private var headerBlock: CGFloat { 14 + CalendarStyle.gridHeaderSpacing + 12 + 3 }

    private var rowPitch: CGFloat {
        let rows = CGFloat(max(rowCount, 1))
        let fit = floor((availableHeight - headerBlock) / rows)
        return max(14, min(CalendarStyle.gridRowPitch, fit))
    }

    /// Weekday symbols rotated to start at the locale's first weekday.
    private var weekdaySymbols: [(symbol: String, isWeekend: Bool)] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        guard symbols.count == 7 else { return [] }
        var result: [(symbol: String, isWeekend: Bool)] = []
        for i in 0..<7 {
            let index = (calendar.firstWeekday - 1 + i) % 7
            // weekday numbers are 1-based, Sunday = 1.
            let isWeekend = Self.isWeekendWeekday(index + 1, calendar: calendar, reference: monthStart)
            result.append((symbols[index], isWeekend))
        }
        return result
    }

    private static func isWeekendWeekday(_ weekday: Int, calendar: Calendar, reference: Date) -> Bool {
        var comps = DateComponents()
        comps.weekday = weekday
        guard let date = calendar.nextDate(after: reference, matching: comps, matchingPolicy: .nextTime) else {
            return weekday == 1 || weekday == 7
        }
        return calendar.isDateInWeekend(date)
    }

    var body: some View {
        let pitch = rowPitch
        let weekdays = weekdaySymbols
        let todayDay = calendar.isDate(today, equalTo: monthStart, toGranularity: .month)
            ? calendar.component(.day, from: today) : -1

        VStack(alignment: .leading, spacing: 0) {
            Text(CalendarFormat.month(month))
                .font(.system(size: CalendarStyle.headerFontSize, weight: .bold))
                .tracking(CalendarStyle.headerTracking)
                .foregroundStyle(CalendarStyle.rose)
                .lineLimit(1)
                .frame(height: 14, alignment: .leading)
                .padding(.leading, 3)

            HStack(spacing: 0) {
                ForEach(0..<weekdays.count, id: \.self) { i in
                    Text(weekdays[i].symbol)
                        .font(.system(size: CalendarStyle.gridWeekdayFontSize, weight: .bold))
                        .foregroundStyle(weekdays[i].isWeekend ? CalendarStyle.weekendGrey : Color.white.opacity(0.9))
                        .frame(width: CalendarStyle.gridColumnPitch, height: 12)
                }
            }
            .padding(.top, CalendarStyle.gridHeaderSpacing)
            .padding(.bottom, 3)

            VStack(spacing: 0) {
                ForEach(0..<rowCount, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            let day = row * 7 + column - leadingBlanks + 1
                            CalendarDayCell(
                                day: (day >= 1 && day <= dayCount) ? day : nil,
                                isToday: day == todayDay,
                                isWeekend: weekdays.count == 7 ? weekdays[column].isWeekend : false,
                                indicator: indicators[day],
                                height: pitch)
                        }
                    }
                }
            }
        }
        .fixedSize()
    }
}

private struct CalendarDayCell: View {
    let day: Int?
    let isToday: Bool
    let isWeekend: Bool
    let indicator: Color?
    let height: CGFloat

    var body: some View {
        ZStack {
            if let day {
                if isToday {
                    Circle()
                        .fill(CalendarStyle.rose)
                        .frame(width: CalendarStyle.todayCircle, height: CalendarStyle.todayCircle)
                }
                Text("\(day)")
                    .font(.system(size: CalendarStyle.gridDayFontSize, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color.white : (isWeekend ? CalendarStyle.weekendGrey : Color.white))
                if let indicator {
                    Circle()
                        .fill(isToday ? Color.white : indicator)
                        .frame(width: CalendarStyle.indicatorDot, height: CalendarStyle.indicatorDot)
                        .offset(y: isToday ? CalendarStyle.todayCircle / 2 + 2 : 7)
                }
            }
        }
        .frame(width: CalendarStyle.gridColumnPitch, height: height)
    }
}

// MARK: - Duo column

/// The calendar half of the Duo page: date header and today's next events
/// (or the empty state / weather).
struct CalendarDuoColumn: View {
    @ObservedObject private var manager = CalendarManager.shared
    @ObservedObject private var weather = WeatherManager.shared
    @Default(.alwaysShowMonthView) private var alwaysShowMonthView
    @Default(.showWeatherOnEmptyDay) private var showWeatherOnEmptyDay
    @Environment(\.notchGeometry) private var geometry

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 30)) { context in
            let now = context.date
            let events = manager.remainingExpandedEventsToday(now: now)
            let capacity = geometry.hasHardwareNotch ? CalendarStyle.rowsPerColumn - 1 : CalendarStyle.rowsPerColumn
            let rows = alwaysShowMonthView
                ? CalendarRowBuilder.condensed(events: events, now: now, capacity: capacity)
                : CalendarRowBuilder.truncated(events: events, capacity: capacity)

            VStack(alignment: .leading, spacing: 0) {
                CalendarDateHeader(date: now)
                if !manager.hasAccess {
                    CalendarAccessPrompt()
                        .padding(.top, 8)
                } else if rows.isEmpty {
                    CalendarEmptyDayView(hadEventsToday: !manager.expandedEvents(on: now).isEmpty,
                                         weather: showWeatherOnEmptyDay ? weather.snapshot : nil)
                        .padding(.top, 10)
                } else {
                    CalendarRowsView(rows: rows, now: now)
                        .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, geometry.hasHardwareNotch ? geometry.closedSize.height + 4 : CalendarStyle.expandedTopInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
