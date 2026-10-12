import AppKit
import Defaults
import EventKit
import Luminare
import SwiftUI

/// Calendar (Part D §1.7): event options, time to leave, the per-calendar
/// list (checkbox in the calendar colour + Both / Live Activity / Expanded
/// View popup) and Quick Peek.
struct SettingsCalendarPane: View {
    @Default(.enableCalendar) private var enableCalendar
    @Default(.timeBeforeEvent) private var timeBeforeEvent
    @Default(.playSoundOnCalendarEvent) private var playSoundOnCalendarEvent
    @Default(.playHourlyChime) private var playHourlyChime
    @Default(.useCalendarColor) private var useCalendarColor
    @Default(.disableActivityDuringEvents) private var disableActivityDuringEvents
    @Default(.showWeatherOnEmptyDay) private var showWeatherOnEmptyDay
    @Default(.weatherStyle) private var weatherStyle
    @Default(.useEventIndicators) private var useEventIndicators
    @Default(.alwaysShowMonthView) private var alwaysShowMonthView

    @Default(.notifyWhenTimeToLeave) private var notifyWhenTimeToLeave
    @Default(.playSoundOnTimeToLeave) private var playSoundOnTimeToLeave
    @Default(.timeToLeaveBuffer) private var timeToLeaveBuffer
    @Default(.timeToLeaveDuration) private var timeToLeaveDuration
    @Default(.defaultTransportType) private var defaultTransportType

    @Default(.excludedCalendars) private var excludedCalendars
    @Default(.calendarDisplayModes) private var calendarDisplayModes

    @Default(.enableCalendarQuickPeek) private var enableCalendarQuickPeek
    @Default(.beforeEventStarts) private var beforeEventStarts
    @Default(.whenEventIsStarting) private var whenEventIsStarting
    @Default(.calendarPeekDuration) private var calendarPeekDuration
    @Default(.useColoredCalendarIndicator) private var useColoredCalendarIndicator

    @ObservedObject private var calendars = SettingsCalendarStore.shared
    @ObservedObject private var permissions = ShellPermissions.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            mainSection
            timeToLeaveSection
            calendarsSection
            extensionSection
        }
        .onAppear {
            calendars.reload()
        }
    }

    private var mainSection: some View {
        LuminareSection {
            SettingsFeatureToggleRow(.calendar, isOn: $enableCalendar, permission: .calendar)
            Group {
                SettingsSliderRow(
                    "Time before event", value: $timeBeforeEvent, options: SettingsSliderStops.timeBeforeEvent,
                    unit: "m", fractionDigits: 0
                )
                .disabled(!enableCalendar)
                SettingsToggleRow(
                    "Play sound on calendar event", isOn: $playSoundOnCalendarEvent,
                    info: "Plays a sound when an event begins.", sound: .event
                )
                .disabled(!enableCalendar)
                SettingsToggleRow(
                    "Play hourly chime", isOn: $playHourlyChime,
                    info: "Plays a soft chime at the top of every hour.", sound: .chime
                )
                .disabled(!enableCalendar)
                SettingsToggleRow("Use calendar color", isOn: $useCalendarColor)
                    .disabled(!enableCalendar)
                SettingsToggleRow("Disable activity during events", isOn: $disableActivityDuringEvents)
                    .disabled(!enableCalendar)
            }
            Group {
                SettingsToggleRow(
                    "Show weather on empty day", isOn: $showWeatherOnEmptyDay,
                    info: "Shows the weather in the calendar activity when there are no events left today.",
                    permission: .location
                )
                .disabled(!enableCalendar)
                if showWeatherOnEmptyDay {
                    SettingsTilePicker(WeatherStyle.allCases, selection: $weatherStyle, title: { $0.settingsTitle }) { style, isSelected in
                        SettingsWeatherStyleTile(style: style, isSelected: isSelected)
                    }
                    .disabled(!enableCalendar)
                }
                SettingsToggleRow("Use event indicators", isOn: $useEventIndicators)
                    .disabled(!enableCalendar)
                SettingsToggleRow("Always show month view", isOn: $alwaysShowMonthView)
                    .disabled(!enableCalendar)
            }
        }
    }

    private var timeToLeaveSection: some View {
        LuminareSection("Time to Leave") {
            SettingsToggleRow(
                "Notify when time to leave", isOn: $notifyWhenTimeToLeave,
                info: "Uses the event's location and travel time to tell you when to leave.",
                permission: .location
            )
            if notifyWhenTimeToLeave {
                SettingsToggleRow("Play sound", isOn: $playSoundOnTimeToLeave, sound: .directions)
                SettingsSliderRow(
                    "Extra buffer", value: $timeToLeaveBuffer, options: SettingsSliderStops.timeToLeaveBuffer,
                    unit: "m", fractionDigits: 0
                )
                SettingsSliderRow(
                    "Notify for", value: $timeToLeaveDuration, options: SettingsSliderStops.timeToLeaveDuration,
                    unit: "m", fractionDigits: 0
                )
                SettingsTilePicker(TransportType.allCases, selection: $defaultTransportType, title: { $0.settingsTitle }) { type, isSelected in
                    SettingsSymbolTile(symbol: type.settingsSymbol, isSelected: isSelected)
                }
            }
        }
        .disabled(!enableCalendar)
    }

    @ViewBuilder private var calendarsSection: some View {
        LuminareSection("Calendars") {
            if !permissions.isGranted(.calendar) {
                SettingsPermissionRow(kind: .calendar, message: "Foyer cannot read your calendars.")
            } else if calendars.items.isEmpty {
                Text("No calendars found.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowMinHeight)
            } else {
                ForEach(calendars.items) { item in
                    SettingsCalendarRow(
                        item: item,
                        isIncluded: includedBinding(for: item.id),
                        mode: modeBinding(for: item.id)
                    )
                }
            }
        }
        .disabled(!enableCalendar)
    }

    private var extensionSection: some View {
        LuminareSection("Extension") {
            SettingsToggleRow("Quick Peek", isOn: $enableCalendarQuickPeek, symbol: "rectangle.topthird.inset.filled",
                              symbolColor: SettingsMetrics.accent)
            SettingsToggleRow("Before event starts", isOn: $beforeEventStarts)
                .disabled(!enableCalendarQuickPeek)
            SettingsToggleRow("When event is starting", isOn: $whenEventIsStarting)
                .disabled(!enableCalendarQuickPeek)
            SettingsSliderRow("Peek duration", value: $calendarPeekDuration, options: SettingsSliderStops.peekDuration, unit: "s")
                .disabled(!enableCalendarQuickPeek)
            SettingsToggleRow("Use colored calendar indicator", isOn: $useColoredCalendarIndicator)
        }
        .disabled(!enableCalendar)
    }

    // MARK: Bindings

    private func includedBinding(for identifier: String) -> Binding<Bool> {
        Binding(
            get: { !Defaults[.excludedCalendars].contains(identifier) },
            set: { included in
                var list = Defaults[.excludedCalendars].filter { $0 != identifier }
                if !included { list.append(identifier) }
                Defaults[.excludedCalendars] = list
            }
        )
    }

    private func modeBinding(for identifier: String) -> Binding<CalendarDisplayMode> {
        Binding(
            get: { Defaults[.calendarDisplayModes][identifier] ?? .both },
            set: { mode in
                var dictionary = Defaults[.calendarDisplayModes]
                dictionary[identifier] = mode
                Defaults[.calendarDisplayModes] = dictionary
            }
        )
    }
}

struct SettingsWeatherStyleTile: View {
    let style: WeatherStyle
    let isSelected: Bool

    var body: some View {
        switch style {
        case .symbol:
            SettingsSymbolTile(symbol: "cloud.sun.fill", isSelected: isSelected)
        case .temperature:
            ZStack {
                Rectangle()
                    .fill(isSelected ? SettingsMetrics.accent.opacity(0.14) : Color.primary.opacity(0.06))
                Text(verbatim: "18°")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? SettingsMetrics.accent : Color.secondary)
            }
        }
    }
}

struct SettingsCalendarRow: View {
    let item: SettingsCalendarStore.Item
    let isIncluded: Binding<Bool>
    let mode: Binding<CalendarDisplayMode>

    var body: some View {
        LuminareCompose {
            Picker("", selection: mode) {
                Text(CalendarDisplayMode.both.settingsTitle).tag(CalendarDisplayMode.both)
                Divider()
                Text(CalendarDisplayMode.activity.settingsTitle).tag(CalendarDisplayMode.activity)
                Text(CalendarDisplayMode.notification.settingsTitle).tag(CalendarDisplayMode.notification)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(!isIncluded.wrappedValue)
        } label: {
            Toggle(isOn: isIncluded) {
                HStack(spacing: 5) {
                    if item.isBirthday {
                        Image(systemName: "gift.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Text(item.title)
                        .lineLimit(1)
                    if !item.sourceTitle.isEmpty {
                        Text(item.sourceTitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .toggleStyle(SettingsCheckboxToggleStyle(tint: item.color))
        }
    }
}

/// EventKit calendars for the Calendars list (read directly, independent of
/// the Calendar feature).
@MainActor
final class SettingsCalendarStore: ObservableObject {
    static let shared = SettingsCalendarStore()

    struct Item: Identifiable {
        let id: String
        let title: String
        let sourceTitle: String
        let color: Color
        let isBirthday: Bool
    }

    @Published private(set) var items: [Item] = []
    private var store: EKEventStore?
    private var observers: [NSObjectProtocol] = []

    private init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in SettingsCalendarStore.shared.reload() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .shellCalendarAccessChanged, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                // A store created before access was granted stays empty.
                SettingsCalendarStore.shared.store = nil
                SettingsCalendarStore.shared.reload()
            }
        })
        reload()
    }

    func reload() {
        guard ShellPermissions.calendarState() == .granted else {
            if !items.isEmpty { items = [] }
            return
        }
        let store = self.store ?? EKEventStore()
        self.store = store
        var result: [Item] = []
        for calendar in store.calendars(for: .event) {
            let source: EKSource? = calendar.source
            let nsColor: NSColor? = calendar.color
            result.append(Item(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                sourceTitle: source?.title ?? "",
                color: Color(nsColor: nsColor ?? NSColor.systemGray),
                isBirthday: calendar.type == .birthday
            ))
        }
        result.sort { lhs, rhs in
            if lhs.sourceTitle != rhs.sourceTitle { return lhs.sourceTitle < rhs.sourceTitle }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        items = result
    }
}
