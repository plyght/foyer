import Defaults
import Luminare
import SwiftUI

/// Lock Screen (Part D §4, AX dump `ax_settings_Lock_Screen.txt`): keep
/// awake, screen saver, lock/unlock sounds, widget list (reorderable), Now
/// Playing widget material/idle/volume/offset, Weather, allowed HUDs.
struct SettingsLockScreenPane: View {
    @Default(.enableLockScreen) private var enableLockScreen
    @Default(.keepAwake) private var keepAwake
    @Default(.showOnScreenSaver) private var showOnScreenSaver
    @Default(.playSoundOnLock) private var playSoundOnLock
    @Default(.playSoundOnUnlock) private var playSoundOnUnlock

    @Default(.allowBatteryWidgetWhenLocked) private var allowBatteryWidgetWhenLocked
    @Default(.allowConnectivityWidgetWhenLocked) private var allowConnectivityWidgetWhenLocked
    @Default(.allowFocusWidgetWhenLocked) private var allowFocusWidgetWhenLocked
    @Default(.allowCalendarWidgetWhenLocked) private var allowCalendarWidgetWhenLocked
    @Default(.allowNowPlayingWidgetWhenLocked) private var allowNowPlayingWidgetWhenLocked
    @Default(.allowWeatherWidgetWhenLocked) private var allowWeatherWidgetWhenLocked
    @Default(.lockScreenWidgetOrder) private var lockScreenWidgetOrder

    @Default(.nowPlayingStyle) private var nowPlayingStyle
    @Default(.hideIdleDuration) private var hideIdleDuration
    @Default(.showVolumeControl) private var showVolumeControl
    @Default(.nowPlayingWidgetOffset) private var nowPlayingWidgetOffset

    @Default(.allowBatteryWhenLocked) private var allowBatteryWhenLocked
    @Default(.allowConnectivityWhenLocked) private var allowConnectivityWhenLocked
    @Default(.allowFocusWhenLocked) private var allowFocusWhenLocked
    @Default(.allowBrightnessWhenLocked) private var allowBrightnessWhenLocked
    @Default(.allowVolumeWhenLocked) private var allowVolumeWhenLocked

    @State private var isReordering = false

    /// Widgets listed in the "Widgets" section (Now Playing and Weather have
    /// their own sections, like Alcove).
    private static let listedWidgets: [LockScreenWidget] = [.battery, .connectivity, .focus, .calendar]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            mainSection
            widgetsSection
            nowPlayingSection
            weatherSection
            allowedSection
        }
    }

    private var mainSection: some View {
        LuminareSection {
            SettingsFeatureToggleRow(.lockScreen, isOn: $enableLockScreen)
            SettingsSliderRow("Keep awake", value: $keepAwake, options: SettingsSliderStops.keepAwake, unit: "m", fractionDigits: 0)
                .disabled(!enableLockScreen)
            SettingsToggleRow("Show on screen saver", isOn: $showOnScreenSaver)
                .disabled(!enableLockScreen)
            SettingsToggleRow("Play sound on lock", isOn: $playSoundOnLock, sound: .lock)
                .disabled(!enableLockScreen)
            SettingsToggleRow("Play sound on unlock", isOn: $playSoundOnUnlock, sound: .unlock)
                .disabled(!enableLockScreen)
        }
    }

    private var widgetsSection: some View {
        LuminareSection {
            ForEach(orderedListedWidgets, id: \.self) { widget in
                SettingsLockWidgetRow(
                    widget: widget,
                    isOn: binding(for: widget),
                    isReordering: isReordering,
                    canMoveUp: canMove(widget, by: -1),
                    canMoveDown: canMove(widget, by: 1),
                    move: { offset in move(widget, by: offset) }
                )
            }
        } header: {
            HStack {
                Text("Widgets")
                    .fontWeight(.medium)
                Spacer()
                Button {
                    withAnimation(Constants.Animations.standard) { isReordering.toggle() }
                } label: {
                    Image(systemName: isReordering ? "checkmark.circle.fill" : "square.3.layers.3d.down.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isReordering ? SettingsMetrics.accent : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(isReordering ? "Done" : "Reorder widgets")
            }
        }
        .disabled(!enableLockScreen)
    }

    private var nowPlayingSection: some View {
        LuminareSection {
            SettingsAllowedRow(tab: .nowPlaying, isOn: $allowNowPlayingWidgetWhenLocked)
            SettingsTilePicker(WidgetMaterial.allCases, selection: $nowPlayingStyle, height: SettingsMetrics.tallTileHeight,
                               title: { $0.settingsTitle }) { material, _ in
                SettingsWidgetMaterialPreview(material: material)
            }
            .disabled(!allowNowPlayingWidgetWhenLocked)
            SettingsSliderRow("Idle duration", value: $hideIdleDuration, options: SettingsSliderStops.lockIdle, unit: "m", fractionDigits: 0)
                .disabled(!allowNowPlayingWidgetWhenLocked)
            SettingsToggleRow("Show volume control", isOn: $showVolumeControl)
                .disabled(!allowNowPlayingWidgetWhenLocked)
            SettingsSliderRow(
                "Offset tuning", value: $nowPlayingWidgetOffset, options: SettingsSliderStops.widgetOffset,
                unit: "px", fractionDigits: 0
            )
            .disabled(!allowNowPlayingWidgetWhenLocked)
        }
        .disabled(!enableLockScreen)
    }

    private var weatherSection: some View {
        LuminareSection {
            SettingsToggleRow(
                "Weather", isOn: $allowWeatherWidgetWhenLocked, symbol: "cloud.sun.fill",
                symbolColor: SettingsMetrics.accent, permission: .location
            )
        }
        .disabled(!enableLockScreen)
    }

    private var allowedSection: some View {
        LuminareSection("Allowed Notifications") {
            SettingsAllowedRow(tab: .battery, isOn: $allowBatteryWhenLocked)
            SettingsAllowedRow(tab: .connectivity, isOn: $allowConnectivityWhenLocked)
            SettingsAllowedRow(tab: .focus, isOn: $allowFocusWhenLocked)
            SettingsAllowedRow(tab: .display, isOn: $allowBrightnessWhenLocked)
            SettingsAllowedRow(tab: .sound, isOn: $allowVolumeWhenLocked)
        }
        .disabled(!enableLockScreen)
    }

    // MARK: Widgets

    private var fullOrder: [LockScreenWidget] {
        var order = lockScreenWidgetOrder
        for widget in LockScreenWidget.allCases where !order.contains(widget) {
            order.append(widget)
        }
        return order
    }

    private var orderedListedWidgets: [LockScreenWidget] {
        fullOrder.filter { SettingsLockScreenPane.listedWidgets.contains($0) }
    }

    private func binding(for widget: LockScreenWidget) -> Binding<Bool> {
        switch widget {
        case .battery: return $allowBatteryWidgetWhenLocked
        case .connectivity: return $allowConnectivityWidgetWhenLocked
        case .focus: return $allowFocusWidgetWhenLocked
        case .calendar: return $allowCalendarWidgetWhenLocked
        case .nowPlaying: return $allowNowPlayingWidgetWhenLocked
        case .weather: return $allowWeatherWidgetWhenLocked
        }
    }

    private func canMove(_ widget: LockScreenWidget, by offset: Int) -> Bool {
        let listed = orderedListedWidgets
        guard let index = listed.firstIndex(of: widget) else { return false }
        return listed.indices.contains(index + offset)
    }

    /// Swaps `widget` with its neighbour among the listed widgets, keeping
    /// the positions of the unlisted ones in the stored order.
    private func move(_ widget: LockScreenWidget, by offset: Int) {
        var listed = orderedListedWidgets
        guard let index = listed.firstIndex(of: widget), listed.indices.contains(index + offset) else { return }
        listed.swapAt(index, index + offset)
        var result: [LockScreenWidget] = []
        var next = 0
        for item in fullOrder {
            if SettingsLockScreenPane.listedWidgets.contains(item) {
                result.append(listed[next])
                next += 1
            } else {
                result.append(item)
            }
        }
        withAnimation(Constants.Animations.standard) {
            lockScreenWidgetOrder = result
        }
    }
}

struct SettingsLockWidgetRow: View {
    let widget: LockScreenWidget
    let isOn: Binding<Bool>
    let isReordering: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void

    var body: some View {
        LuminareCompose {
            if isReordering {
                HStack(spacing: 4) {
                    reorderButton(symbol: "chevron.up", enabled: canMoveUp) { move(-1) }
                    reorderButton(symbol: "chevron.down", enabled: canMoveDown) { move(1) }
                }
            } else {
                SettingsSwitch(isOn: isOn)
            }
        } label: {
            HStack(spacing: 8) {
                if let tab = widget.settingsTab {
                    SettingsTabIcon(tab: tab, size: 18)
                }
                Text(widget.settingsTitle)
            }
        }
    }

    private func reorderButton(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 20)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

/// Glass / Clear / Frosted capsules over a blurred backdrop.
struct SettingsWidgetMaterialPreview: View {
    let material: WidgetMaterial

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.20, green: 0.38, blue: 0.55), Color(red: 0.45, green: 0.62, blue: 0.70), Color(red: 0.30, green: 0.45, blue: 0.52)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Capsule(style: .continuous)
                .fill(capsuleFill)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(material == .frosted ? 0 : 0.35), lineWidth: 1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
        }
    }

    private var capsuleFill: Color {
        switch material {
        case .glass: return Color.white.opacity(0.28)
        case .clear: return Color.white.opacity(0.06)
        case .frosted: return Color.white.opacity(0.72)
        }
    }
}
