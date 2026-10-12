import Defaults
import SwiftUI

/// Tint rules (Part D §1.2/§1.5):
/// - glyph, countdown and ring: rose, or the event's calendar colour with
///   "Use calendar color";
/// - Quick Peek indicator bar: the calendar colour with "Use colored calendar
///   indicator", otherwise the glyph tint.
enum CalendarTint {
    static func accent(for event: CalendarEventItem?, useCalendarColor: Bool) -> Color {
        guard useCalendarColor, let event else { return CalendarStyle.rose }
        return event.calendarColor
    }

    static func indicator(for event: CalendarEventItem, useColoredIndicator: Bool, useCalendarColor: Bool) -> Color {
        useColoredIndicator ? event.calendarColor : accent(for: event, useCalendarColor: useCalendarColor)
    }
}

// MARK: - Compact activity (216 x 28)

/// Left wing: `calendar.badge.clock` while an event is pending/running,
/// plain `calendar` when idle.
struct CalendarCompactLeading: View {
    @ObservedObject private var live = CalendarLiveController.shared
    @Default(.useCalendarColor) private var useCalendarColor

    var body: some View {
        let tint = CalendarTint.accent(for: live.trackedEvent, useCalendarColor: useCalendarColor)
        HStack(spacing: 0) {
            Image(systemName: live.trackedEvent == nil ? "calendar" : "calendar.badge.clock")
                .font(.system(size: CalendarStyle.compactGlyphSize, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
            Spacer(minLength: 0)
        }
        .padding(.leading, CalendarStyle.wingInset)
        .animation(Constants.Animations.standard, value: tint)
    }
}

/// Right wing: countdown text (`15m` … `46s`) before the event, a progress
/// ring while it runs, the day number when idle.
struct CalendarCompactTrailing: View {
    @ObservedObject private var live = CalendarLiveController.shared
    @Default(.useCalendarColor) private var useCalendarColor

    var body: some View {
        let tint = CalendarTint.accent(for: live.trackedEvent, useCalendarColor: useCalendarColor)
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            content(tint: tint)
        }
        .padding(.trailing, CalendarStyle.wingInset)
    }

    @ViewBuilder
    private func content(tint: Color) -> some View {
        if let event = live.trackedEvent {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                if event.isInProgress(at: context.date) || context.date >= event.start {
                    CalendarProgressRing(progress: event.progress(at: context.date), tint: tint)
                        .transition(.opacity)
                } else {
                    Text(CalendarFormat.countdown(event.start.timeIntervalSince(context.date)))
                        .font(.system(size: CalendarStyle.compactFontSize, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(tint)
                        .lineLimit(1)
                        .fixedSize()
                        .contentTransition(.numericText(countsDown: true))
                }
            }
        } else {
            Text(CalendarFormat.dayNumber(Date()))
                .font(.system(size: CalendarStyle.compactFontSize, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// Elapsed-time ring: dim track plus an arc from 12 o'clock, clockwise.
struct CalendarProgressRing: View {
    var progress: Double
    var tint: Color
    var diameter: CGFloat = CalendarStyle.ringDiameter
    var lineWidth: CGFloat = CalendarStyle.ringLineWidth

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(CalendarStyle.ringTrackOpacity), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
        .animation(.linear(duration: 1), value: progress)
    }
}

// MARK: - Quick Peek (233 x 70)

/// Two-row capsule: row 1 = glyph + countdown/ring beside the notch; row 2 =
/// coloured bar, event title, and `clock` + duration (before start) or
/// `hourglass` + remaining time (at start).
struct CalendarPeekView: View {
    enum Stage { case before, starting }

    let event: CalendarEventItem
    let stage: Stage

    @Environment(\.notchGeometry) private var geometry
    @Default(.useCalendarColor) private var useCalendarColor
    @Default(.useColoredCalendarIndicator) private var useColoredIndicator

    var body: some View {
        let tint = CalendarTint.accent(for: event, useCalendarColor: useCalendarColor)
        let bar = CalendarTint.indicator(for: event, useColoredIndicator: useColoredIndicator,
                                         useCalendarColor: useCalendarColor)
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: CalendarStyle.compactGlyphSize, weight: .semibold))
                        .foregroundStyle(tint)
                    Spacer(minLength: 0)
                    if context.date >= event.start {
                        CalendarProgressRing(progress: event.progress(at: context.date), tint: tint)
                    } else {
                        Text(CalendarFormat.countdown(event.start.timeIntervalSince(context.date)))
                            .font(.system(size: CalendarStyle.compactFontSize, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(tint)
                            .fixedSize()
                    }
                }
                .padding(.horizontal, CalendarStyle.peekHorizontalInset)
                .frame(height: max(geometry.closedSize.height, 24))

                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(bar)
                        .frame(width: CalendarStyle.peekBarWidth, height: CalendarStyle.peekBarHeight)
                    Text(event.title)
                        .font(.system(size: CalendarStyle.peekTitleSize, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    detail(now: context.date)
                        .layoutPriority(2)
                }
                .padding(.horizontal, CalendarStyle.peekHorizontalInset + 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func detail(now: Date) -> some View {
        let started = now >= event.start
        HStack(spacing: 3) {
            Image(systemName: started ? "hourglass" : "clock.fill")
                .font(.system(size: CalendarStyle.peekDetailSize - 1, weight: .semibold))
            Text(started ? CalendarFormat.duration(event.end.timeIntervalSince(now))
                         : CalendarFormat.duration(event.duration))
                .font(.system(size: CalendarStyle.peekDetailSize, weight: .medium))
                .monospacedDigit()
        }
        .foregroundStyle(CalendarStyle.secondaryText)
        .fixedSize()
    }
}

// MARK: - Start notification (used when Quick Peek is off)

struct CalendarEventNotificationLeading: View {
    let event: CalendarEventItem
    @Default(.useCalendarColor) private var useCalendarColor

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: CalendarStyle.compactGlyphSize, weight: .semibold))
                .foregroundStyle(CalendarTint.accent(for: event, useCalendarColor: useCalendarColor))
            Text(event.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.leading, CalendarStyle.wingInset)
    }
}

struct CalendarEventNotificationTrailing: View {
    let event: CalendarEventItem
    @Default(.useCalendarColor) private var useCalendarColor

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Text(CalendarFormat.timeRange(event.start, event.end))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(CalendarStyle.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.trailing, CalendarStyle.wingInset)
    }
}
