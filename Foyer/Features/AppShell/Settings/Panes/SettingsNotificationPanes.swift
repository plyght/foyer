import Defaults
import Luminare
import SwiftUI

// Notifications: Battery, Connectivity, Focus, Display, Sound (lead §5,
// Part D §2-3, Part C2 §1.1).

struct SettingsBatteryPane: View {
    @Default(.enableBattery) private var enableBattery
    @Default(.batteryDuration) private var batteryDuration
    @Default(.warnOnLowBattery) private var warnOnLowBattery
    @Default(.lowBatteryThreshold) private var lowBatteryThreshold
    @Default(.playSoundOnLowBattery) private var playSoundOnLowBattery
    @Default(.notifyOnLowPowerMode) private var notifyOnLowPowerMode
    @Default(.hideBatteryLabel) private var hideBatteryLabel
    @Default(.hideBatteryPercentage) private var hideBatteryPercentage

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LuminareSection {
                SettingsFeatureToggleRow(.battery, isOn: $enableBattery)
                SettingsSliderRow("Duration", value: $batteryDuration, options: SettingsSliderStops.notificationDuration, unit: "s")
                    .disabled(!enableBattery)
                SettingsToggleRow("Hide label", isOn: $hideBatteryLabel)
                    .disabled(!enableBattery)
                SettingsToggleRow("Hide percentage", isOn: $hideBatteryPercentage)
                    .disabled(!enableBattery)
            }

            LuminareSection("Low Battery") {
                SettingsToggleRow("Warn on low battery", isOn: $warnOnLowBattery)
                SettingsSliderRow(
                    "Low battery threshold", value: $lowBatteryThreshold,
                    options: SettingsSliderStops.batteryThreshold, unit: "%", fractionDigits: 0
                )
                    .disabled(!warnOnLowBattery)
                SettingsToggleRow("Play sound on low battery", isOn: $playSoundOnLowBattery, sound: .lowBattery)
                    .disabled(!warnOnLowBattery)
                SettingsToggleRow(
                    "Notify on Low Power Mode", isOn: $notifyOnLowPowerMode,
                    info: "Shows a notification when Low Power Mode turns on or off.", sound: .lowPower
                )
            }
            .disabled(!enableBattery)
        }
    }
}

struct SettingsConnectivityPane: View {
    @Default(.enableConnectivity) private var enableConnectivity
    @Default(.connectivityDuration) private var connectivityDuration
    @Default(.warnOnLowConnectBattery) private var warnOnLowConnectBattery
    @Default(.lowConnectBatteryThreshold) private var lowConnectBatteryThreshold
    @Default(.playSoundOnLowConnectBattery) private var playSoundOnLowConnectBattery
    @Default(.connectivityModel) private var connectivityModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LuminareSection {
                SettingsFeatureToggleRow(.connectivity, isOn: $enableConnectivity, permission: .bluetooth)
                SettingsSliderRow("Duration", value: $connectivityDuration, options: SettingsSliderStops.notificationDuration, unit: "s")
                    .disabled(!enableConnectivity)
                SettingsToggleRow("Low battery warning", isOn: $warnOnLowConnectBattery)
                    .disabled(!enableConnectivity)
                SettingsSliderRow(
                    "Low battery threshold", value: $lowConnectBatteryThreshold,
                    options: SettingsSliderStops.batteryThreshold, unit: "%", fractionDigits: 0
                )
                .disabled(!warnOnLowConnectBattery)
                    .disabled(!enableConnectivity)
                SettingsToggleRow("Play sound on low battery", isOn: $playSoundOnLowConnectBattery, sound: .lowBattery)
                    .disabled(!warnOnLowConnectBattery)
                    .disabled(!enableConnectivity)
                SettingsTilePicker(
                    ConnectivityModel.allCases, selection: $connectivityModel,
                    height: SettingsMetrics.tallTileHeight, title: { $0.settingsTitle }
                ) { model, _ in
                    SettingsDarkTile {
                        switch model {
                        case .threeDimensional:
                            Image(systemName: "airpodspro")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(
                                    LinearGradient(colors: [Color.white, Color(white: 0.55)], startPoint: .top, endPoint: .bottom)
                                )
                                .shadow(color: Color.white.opacity(0.35), radius: 3)
                        case .symbol:
                            Image(systemName: "airpodspro")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color.white)
                        }
                    }
                }
                    .disabled(!enableConnectivity)
            }
        }
    }
}

struct SettingsFocusPane: View {
    @Default(.enableFocus) private var enableFocus
    @Default(.focusDuration) private var focusDuration
    @Default(.playSoundOnSleepFocus) private var playSoundOnSleepFocus
    @Default(.replaceWaveformDuringFocus) private var replaceWaveformDuringFocus
    @Default(.hideLabel) private var hideLabel
    @Default(.allowBatteryWhenFocused) private var allowBatteryWhenFocused
    @Default(.allowConnectivityWhenFocused) private var allowConnectivityWhenFocused
    @Default(.allowBrightnessWhenFocused) private var allowBrightnessWhenFocused
    @Default(.allowVolumeWhenFocused) private var allowVolumeWhenFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            LuminareSection {
                SettingsFeatureToggleRow(.focus, isOn: $enableFocus)
                SettingsSliderRow("Duration", value: $focusDuration, options: SettingsSliderStops.notificationDuration, unit: "s")
                    .disabled(!enableFocus)
                SettingsToggleRow(
                    "Play sound on sleep focus", isOn: $playSoundOnSleepFocus,
                    info: "Plays a sound when a Sleep focus begins.", sound: .sleep
                )
                    .disabled(!enableFocus)
                SettingsToggleRow(
                    "Replace waveform during focus", isOn: $replaceWaveformDuringFocus,
                    info: "Shows the Focus glyph instead of the waveform while media plays during a Focus."
                )
                    .disabled(!enableFocus)
                SettingsToggleRow("Hide label", isOn: $hideLabel)
                    .disabled(!enableFocus)
            }

            LuminareSection("Allowed Notifications") {
                SettingsAllowedRow(tab: .battery, isOn: $allowBatteryWhenFocused)
                SettingsAllowedRow(tab: .connectivity, isOn: $allowConnectivityWhenFocused)
                SettingsAllowedRow(tab: .display, isOn: $allowBrightnessWhenFocused)
                SettingsAllowedRow(tab: .sound, isOn: $allowVolumeWhenFocused)
            }
        }
    }
}

/// Row with a pane icon, used by "Allowed Notifications" and "Widgets".
struct SettingsAllowedRow: View {
    let tab: SettingsTab
    let isOn: Binding<Bool>
    let title: String?

    init(tab: SettingsTab, isOn: Binding<Bool>, title: String? = nil) {
        self.tab = tab
        self.isOn = isOn
        self.title = title
    }

    var body: some View {
        LuminareCompose {
            SettingsSwitch(isOn: isOn)
        } label: {
            HStack(spacing: 8) {
                SettingsTabIcon(tab: tab, size: 18)
                Text(title ?? tab.title)
            }
        }
    }
}

struct SettingsDisplayPane: View {
    @Default(.enableBrightness) private var enableBrightness
    @Default(.brightnessDuration) private var brightnessDuration
    @Default(.brightnessProgressStyle) private var brightnessProgressStyle
    @Default(.showBrightnessPercentage) private var showBrightnessPercentage
    @Default(.hideBrightnessLabel) private var hideBrightnessLabel
    @Default(.brightnessSpeed) private var brightnessSpeed

    var body: some View {
        LuminareSection {
            SettingsFeatureToggleRow(.display, isOn: $enableBrightness, permission: .accessibility)
            SettingsSliderRow("Duration", value: $brightnessDuration, options: SettingsSliderStops.hudDuration, unit: "s")
                .disabled(!enableBrightness)
            SettingsTilePicker(
                BrightnessProgressStyle.allCases, selection: $brightnessProgressStyle, title: { $0.settingsTitle }
            ) { style, _ in
                SettingsDarkTile {
                    SettingsHUDBarPreview(fill: style.previewFill, glow: style == .glow)
                }
            }
                .disabled(!enableBrightness)
            SettingsToggleRow("Show percentage", isOn: $showBrightnessPercentage)
                .disabled(!enableBrightness)
            SettingsToggleRow("Hide label", isOn: $hideBrightnessLabel)
                .disabled(!enableBrightness)
            SettingsHUDSpeedPicker(selection: $brightnessSpeed)
                .disabled(!enableBrightness)
        }
    }
}

struct SettingsSoundPane: View {
    @Default(.enableVolume) private var enableVolume
    @Default(.volumeDuration) private var volumeDuration
    @Default(.volumeProgressStyle) private var volumeProgressStyle
    @Default(.showVolumePercentage) private var showVolumePercentage
    @Default(.hideVolumeLabel) private var hideVolumeLabel
    @Default(.volumeSpeed) private var volumeSpeed
    @Default(.volumeOutputDevice) private var volumeOutputDevice

    var body: some View {
        LuminareSection {
            SettingsFeatureToggleRow(.sound, isOn: $enableVolume, permission: .accessibility)
            SettingsSliderRow("Duration", value: $volumeDuration, options: SettingsSliderStops.hudDuration, unit: "s")
                .disabled(!enableVolume)
            SettingsTilePicker(
                VolumeProgressStyle.allCases, selection: $volumeProgressStyle, title: { $0.settingsTitle }
            ) { style, _ in
                SettingsDarkTile {
                    SettingsHUDBarPreview(fill: style.previewFill, glow: style == .decibel)
                }
            }
                .disabled(!enableVolume)
            SettingsToggleRow("Show percentage", isOn: $showVolumePercentage)
                .disabled(!enableVolume)
            SettingsToggleRow("Hide label", isOn: $hideVolumeLabel)
                .disabled(!enableVolume)
            SettingsHUDSpeedPicker(selection: $volumeSpeed)
                .disabled(!enableVolume)
            SettingsTilePicker(
                VolumeLeadingGlyph.allCases, selection: $volumeOutputDevice, title: { $0.settingsTitle }
            ) { glyph, _ in
                SettingsDarkTile {
                    Image(systemName: glyph.settingsSymbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
            }
                .disabled(!enableVolume)
        }
    }
}

/// Smooth (tortoise) / Fast (hare) / Instant (bolt).
struct SettingsHUDSpeedPicker: View {
    let selection: Binding<HUDSpeed>

    var body: some View {
        SettingsTilePicker(HUDSpeed.allCases, selection: selection, title: { $0.settingsTitle }) { speed, isSelected in
            SettingsSymbolTile(symbol: speed.settingsSymbol, isSelected: isSelected)
        }
    }
}

/// A HUD progress bar on a black card (White / Accent / Glow / Decibel).
struct SettingsHUDBarPreview: View {
    let fill: AnyShapeStyle
    let glow: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * 0.72
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule()
                    .fill(fill)
                    .frame(width: width * 0.62)
                    .shadow(color: glow ? Color.white.opacity(0.9) : Color.clear, radius: glow ? 4 : 0)
            }
            .frame(width: width, height: 4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

extension BrightnessProgressStyle {
    var previewFill: AnyShapeStyle {
        switch self {
        case .white: return AnyShapeStyle(Color.white)
        case .accent: return AnyShapeStyle(SettingsMetrics.accent)
        case .glow:
            return AnyShapeStyle(LinearGradient(colors: [Color.white.opacity(0.4), Color.white], startPoint: .leading, endPoint: .trailing))
        }
    }
}

extension VolumeProgressStyle {
    var previewFill: AnyShapeStyle {
        switch self {
        case .white: return AnyShapeStyle(Color.white)
        case .accent: return AnyShapeStyle(SettingsMetrics.accent)
        case .decibel:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 0.98, green: 0.30, blue: 0.45), Color(red: 1.0, green: 0.42, blue: 0.35)],
                startPoint: .leading, endPoint: .trailing
            ))
        }
    }
}
