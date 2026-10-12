import Defaults
import SwiftUI

/// Calendar / Time to Leave / Weather / Focus measurements, taken from the
/// teardown (Part D §1-§2, §7.2, §7.6, Part I §2.1). Shared values (durations,
/// springs, notch sizes) come from `Constants`.
enum CalendarStyle {

    // MARK: Palette (STATIC asset catalog, Tailwind values)

    /// `AlcoveRoseColor` (244, 63, 94): calendar glyph, weekday, month, today circle.
    static let rose = Color(red: 244 / 255, green: 63 / 255, blue: 94 / 255)
    /// `AlcoveIndigoColor` (99, 102, 241): Do Not Disturb.
    static let indigo = Color(red: 99 / 255, green: 102 / 255, blue: 241 / 255)
    /// `AlcoveSkyColor` (14, 165, 233): time to leave.
    static let sky = Color(red: 14 / 255, green: 165 / 255, blue: 233 / 255)
    /// `AlcoveGreenColor` (74, 222, 128).
    static let green = Color(red: 74 / 255, green: 222 / 255, blue: 128 / 255)
    /// `AlcoveAmberColor` (245, 158, 11).
    static let amber = Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255)
    /// `AlcoveOrangeColor` (251, 146, 60).
    static let orange = Color(red: 251 / 255, green: 146 / 255, blue: 60 / 255)
    /// `AlcovePinkColor` (203, 102, 217).
    static let pink = Color(red: 203 / 255, green: 102 / 255, blue: 217 / 255)
    /// `AlcoveEmeraldColor` (16, 185, 129).
    static let emerald = Color(red: 16 / 255, green: 185 / 255, blue: 129 / 255)
    /// Focus "Off" glyph / label.
    static let offGrey = Color.white.opacity(0.45)
    /// Weekend days in the month grid (~55 % white).
    static let weekendGrey = Color.white.opacity(0.55)
    /// Secondary text (times, "Your day is clear").
    static let secondaryText = Color.white.opacity(0.5)

    // MARK: Compact activity (216 x 28: 140 + 2 x 38)

    /// Wing beside the notch for the calendar / focus / time-to-leave content.
    static let wing: CGFloat = Constants.Geometry.activityWing
    /// Glyph and countdown text are ~13 pt semibold.
    static let compactFontSize: CGFloat = 13
    static let compactGlyphSize: CGFloat = 13
    /// Countdown ring: ~16 px diameter, ~2.5 px stroke, dim track in the same colour.
    static let ringDiameter: CGFloat = 15
    static let ringLineWidth: CGFloat = 2.5
    static let ringTrackOpacity: Double = 0.25
    /// Inset of wing content from the outer edge of the wing.
    static let wingInset: CGFloat = 4

    // MARK: Focus content swap (216 → 144 → 216)

    /// Shrink leg: 216 → 144 in 333 ms, ease-out.
    static let focusShrinkDuration: Double = 0.333
    /// Grow leg: 144 → 216 in 470 ms, ease-out.
    static let focusGrowDuration: Double = 0.47
    /// Wing of the empty, shrunken intermediate state: 140 + 2 x 2 = 144.
    static let focusShrunkWing: CGFloat = 2

    // MARK: Quick Peek (233 x 70)

    /// Row-2 indicator bar: 3 px wide, ~11 px tall.
    static let peekBarWidth: CGFloat = 3
    static let peekBarHeight: CGFloat = 12
    static let peekTitleSize: CGFloat = 13
    static let peekDetailSize: CGFloat = 12
    static let peekHorizontalInset: CGFloat = 6

    // MARK: Expanded page (362 x 175)

    /// Left column starts 18 px from the body edge.
    static let expandedLeadingInset: CGFloat = 18
    static let expandedTrailingInset: CGFloat = 18
    /// Top of "SUNDAY" / "OCTOBER" on a simulated notch.
    static let expandedTopInset: CGFloat = 13
    static let expandedBottomInset: CGFloat = 8
    static let columnSpacing: CGFloat = 14
    /// "SUNDAY" / "OCTOBER": ~11 pt bold, letter-spaced, rose.
    static let headerFontSize: CGFloat = 11
    static let headerTracking: CGFloat = 0.4
    /// Large day number "11": ~34 pt.
    static let dayNumberSize: CGFloat = 34
    /// Event rows.
    static let eventTitleSize: CGFloat = 11
    static let eventTimeSize: CGFloat = 10
    static let eventRowHeight: CGFloat = 26
    static let eventRowSpacing: CGFloat = 4
    static let eventRowCorner: CGFloat = 6
    static let eventBarWidth: CGFloat = 3
    /// Rows that fit under the day number in one column.
    static let rowsPerColumn = 3

    // MARK: Month grid

    /// Column pitch 21 px, row pitch 20 px, glyphs ~10 pt bold.
    static let gridColumnPitch: CGFloat = 21
    static let gridRowPitch: CGFloat = 20
    /// Tighter rows when the content has to start below a hardware notch.
    static let gridRowPitchCompact: CGFloat = 17
    static let gridDayFontSize: CGFloat = 10
    static let gridWeekdayFontSize: CGFloat = 9
    /// Today: filled rose circle ~16 px.
    static let todayCircle: CGFloat = 16
    /// Event indicator: 2 px dot centred under the day number.
    static let indicatorDot: CGFloat = 3
    static let gridHeaderSpacing: CGFloat = 5

    // MARK: Behaviour

    /// Evaluation tick for countdowns, peeks and chime.
    static let tickInterval: TimeInterval = 1
    /// Debounce for EventKit change notifications.
    static let reloadDebounce: TimeInterval = 0.3
    /// Weather cache lifetime (`calendarConditionsTTL`).
    static let weatherTTL: TimeInterval = 30 * 60
    /// Re-sample the travel time this often while an event is pending.
    static let etaRefreshInterval: TimeInterval = 5 * 60
    /// Only events starting within this window are considered for time to leave.
    static let timeToLeaveLookahead: TimeInterval = 4 * 60 * 60
    /// Location fixes newer than this are reused.
    static let locationMaxAge: TimeInterval = 10 * 60
    static let locationTimeout: TimeInterval = 15
    /// Priorities of the compact activities (Now Playing is 10).
    static let idlePriority = 4
    static let inProgressPriority = 6
    static let upcomingPriority = 15
    static let timeToLeavePriority = 30
    /// Calendar expanded page priority (Now Playing's page is 10, so the player
    /// leads while media plays; swipe down reaches the calendar).
    static let pagePriority = 5
}

// Feature-only settings keys. Swift names are prefixed to stay unique across
// feature folders; the stored names match Alcove's.
extension Defaults.Keys {
    /// Last weather snapshot (JSON), so the lock widget and empty day render
    /// immediately after launch (`cachedWeather`).
    static let calendarCachedWeather = Key<Data?>("cachedWeather")
}

/// Small formatting helpers shared by the calendar views.
enum CalendarFormat {
    /// Compact countdown: "15m" … "1m", then seconds "46s" under one minute,
    /// hours as "1h" / "1h 5m".
    static func countdown(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.up)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = Int((Double(seconds) / 60).rounded(.up))
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// Duration label used in the Quick Peek ("1h", "29m", "1h 30m").
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = max(0, Int((interval / 60).rounded()))
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    static func time(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// "10:12 AM – 10:42 AM".
    static func timeRange(_ start: Date, _ end: Date) -> String {
        "\(time(start)) – \(time(end))"
    }

    /// "SUNDAY".
    static func weekday(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE")
        return f.string(from: date).uppercased()
    }

    /// "OCTOBER".
    static func month(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("LLLL")
        return f.string(from: date).uppercased()
    }

    /// "SUNDAY, 11 OCT".
    static func dayHeader(_ date: Date) -> String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEdMMM")
        return f.string(from: date).uppercased()
    }

    static func dayNumber(_ date: Date) -> String {
        String(Calendar.current.component(.day, from: date))
    }
}
