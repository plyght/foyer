import AppKit
import Defaults
import SwiftUI

/// Which level a HUD shows.
enum HUDLevelSource {
    case volume
    case brightness
    case keyboardBacklight

    var notificationKind: NotificationKind {
        switch self {
        case .volume: return .volume
        case .brightness: return .brightness
        case .keyboardBacklight: return .keyboardBacklight
        }
    }

    var category: NotificationCategory {
        switch self {
        case .volume: return .sound
        case .brightness, .keyboardBacklight: return .display
        }
    }
}

/// Fill style of the HUD bar (Part C2 §1.6).
enum HUDBarStyle: Equatable {
    /// Light-grey fill on a dark track.
    case white
    /// System accent fill.
    case accent
    /// Green glowing meter (Sound only); warms to amber/rose near full scale.
    case decibel
    /// White fill with a soft glow (Display only).
    case glow

    init(_ style: VolumeProgressStyle) {
        switch style {
        case .white: self = .white
        case .accent: self = .accent
        case .decibel: self = .decibel
        }
    }

    init(_ style: BrightnessProgressStyle) {
        switch style {
        case .white: self = .white
        case .accent: self = .accent
        case .glow: self = .glow
        }
    }
}

// MARK: - Entry views (type-erased into the notification)

/// Left wing: glyph + label ("Sound" / "Display" / "Keyboard").
struct HUDLeadingView: View {
    let source: HUDLevelSource

    var body: some View {
        switch source {
        case .volume: HUDVolumeLeading()
        case .brightness: HUDBrightnessLeading()
        case .keyboardBacklight: HUDKeyboardLeading()
        }
    }
}

/// Right wing: bar + optional percentage.
struct HUDTrailingView: View {
    let source: HUDLevelSource

    var body: some View {
        switch source {
        case .volume: HUDVolumeTrailing()
        case .brightness: HUDBrightnessTrailing()
        case .keyboardBacklight: HUDKeyboardTrailing()
        }
    }
}

// MARK: - Volume

private struct HUDVolumeLeading: View {
    @ObservedObject private var manager = VolumeManager.shared
    @Default(.hideVolumeLabel) private var hideLabel
    @Default(.volumeOutputDevice) private var glyphMode

    var body: some View {
        HUDLeadingContent(symbol: symbol,
                          variableValue: variableValue,
                          label: hideLabel ? nil : label)
    }

    private var symbol: String {
        if manager.isMuted { return "speaker.slash.fill" }
        switch glyphMode {
        case .symbol:
            return "speaker.wave.3.fill"
        case .device:
            return HUDDeviceGlyph.symbol(for: manager.outputDeviceKind)
        }
    }

    private var variableValue: Double? {
        guard !manager.isMuted, glyphMode == .symbol else { return nil }
        return Double(manager.volume)
    }

    /// "Sound" (OBSERVED). With "Show device", personal wireless devices are
    /// named instead so the glyph and text agree.
    private var label: String {
        guard glyphMode == .device else { return HUDStrings.sound }
        switch manager.outputDeviceKind {
        case .airPods, .airPodsGen3, .airPodsGen4, .airPodsPro, .airPodsMax, .beats,
             .bluetoothHeadphones, .bluetoothSpeaker, .homePod, .airPlay:
            return manager.outputDeviceName.isEmpty ? HUDStrings.sound : manager.outputDeviceName
        default:
            return HUDStrings.sound
        }
    }
}

private struct HUDVolumeTrailing: View {
    @ObservedObject private var manager = VolumeManager.shared
    @Default(.volumeProgressStyle) private var style
    @Default(.showVolumePercentage) private var showPercentage
    @Default(.volumeSpeed) private var speed

    var body: some View {
        HUDTrailingContent(level: Double(manager.displayedLevel),
                           style: HUDBarStyle(style),
                           showPercentage: showPercentage,
                           tween: HUDConstants.fillTween(speed))
    }
}

// MARK: - Brightness

private struct HUDBrightnessLeading: View {
    @ObservedObject private var manager = HUDBrightnessManager.shared
    @Default(.hideBrightnessLabel) private var hideLabel

    var body: some View {
        HUDLeadingContent(symbol: symbol, variableValue: nil,
                          label: hideLabel ? nil : HUDStrings.display)
    }

    private var symbol: String {
        if manager.isExternalDisplay { return "display" }
        return manager.level < 0.5 ? "sun.min.fill" : "sun.max.fill"
    }
}

private struct HUDBrightnessTrailing: View {
    @ObservedObject private var manager = HUDBrightnessManager.shared
    @Default(.brightnessProgressStyle) private var style
    @Default(.showBrightnessPercentage) private var showPercentage
    @Default(.brightnessSpeed) private var speed

    var body: some View {
        HUDTrailingContent(level: Double(manager.level),
                           style: HUDBarStyle(style),
                           showPercentage: showPercentage,
                           tween: HUDConstants.fillTween(speed))
    }
}

// MARK: - Keyboard backlight

private struct HUDKeyboardLeading: View {
    @ObservedObject private var manager = HUDKeyboardBacklightManager.shared
    @Default(.hideBrightnessLabel) private var hideLabel

    var body: some View {
        HUDLeadingContent(symbol: manager.level < 0.5 ? "light.min" : "light.max",
                          variableValue: nil,
                          label: hideLabel ? nil : HUDStrings.keyboard)
    }
}

private struct HUDKeyboardTrailing: View {
    @ObservedObject private var manager = HUDKeyboardBacklightManager.shared
    @Default(.brightnessProgressStyle) private var style
    @Default(.showBrightnessPercentage) private var showPercentage
    @Default(.brightnessSpeed) private var speed

    var body: some View {
        HUDTrailingContent(level: Double(manager.level),
                           style: HUDBarStyle(style),
                           showPercentage: showPercentage,
                           tween: HUDConstants.fillTween(speed))
    }
}

// MARK: - Shared content

private enum HUDStrings {
    static let sound = String(localized: "Sound")
    static let display = String(localized: "Display")
    static let keyboard = String(localized: "Keyboard")
}

/// Glyph (16 pt column) then the label, inset ~12 px from the HUD edge.
private struct HUDLeadingContent: View {
    let symbol: String
    let variableValue: Double?
    let label: String?

    var body: some View {
        HStack(spacing: HUDConstants.labelSpacing) {
            glyph
                .font(.system(size: HUDConstants.glyphSize, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: HUDConstants.glyphFrame, height: HUDConstants.glyphFrame)
            if let label {
                Text(label)
                    .font(.system(size: HUDConstants.labelFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, HUDConstants.leadingInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var glyph: some View {
        let name = HUDDeviceGlyph.resolved(symbol)
        if let variableValue {
            Image(systemName: name, variableValue: min(max(variableValue, 0), 1))
        } else {
            Image(systemName: name)
        }
    }
}

/// The bar (73 px, or 43 px + value when "Show percentage" is on), ~11 px
/// from the HUD's outer edge.
private struct HUDTrailingContent: View {
    let level: Double
    let style: HUDBarStyle
    let showPercentage: Bool
    let tween: Double

    var body: some View {
        HStack(spacing: HUDConstants.percentageGap) {
            HUDLevelBar(level: level,
                        style: style,
                        length: showPercentage ? HUDConstants.barLengthWithPercentage : HUDConstants.barLength,
                        tween: tween)
            if showPercentage {
                Text(verbatim: "\(Int((min(max(level, 0), 1) * 100).rounded()))")
                    .font(.system(size: HUDConstants.percentageFontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.9))
                    .lineLimit(1)
                    .contentTransition(.numericText(value: level))
                    .animation(.easeOut(duration: tween), value: level)
                    .frame(width: HUDConstants.percentageWidth, alignment: .trailing)
            }
        }
        .padding(.trailing, HUDConstants.trailingInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

/// Rounded ~4 px bar. Each new value retargets a short ease-out tween
/// (≈70-100 ms whatever the Speed setting, Part C2 §1.4).
private struct HUDLevelBar: View {
    let level: Double
    let style: HUDBarStyle
    let length: CGFloat
    let tween: Double

    var body: some View {
        let clamped = min(max(level, 0), 1)
        let fill = fillColor(clamped)
        ZStack(alignment: .leading) {
            Capsule(style: .continuous)
                .fill(trackColor(fill))
                .frame(width: length, height: HUDConstants.barHeight)
            Capsule(style: .continuous)
                .fill(fill)
                .frame(width: length * CGFloat(clamped), height: HUDConstants.barHeight)
                .shadow(color: glows ? fill.opacity(0.85) : Color.clear,
                        radius: glows ? HUDConstants.glowRadius : 0)
        }
        .frame(width: length, height: HUDConstants.barHeight, alignment: .leading)
        .animation(.easeOut(duration: tween), value: clamped)
        .animation(.easeOut(duration: tween), value: length)
    }

    private var glows: Bool {
        style == .decibel || style == .glow
    }

    private func fillColor(_ level: Double) -> Color {
        switch style {
        case .white, .glow:
            return HUDConstants.whiteFill
        case .accent:
            return Color.accentColor
        case .decibel:
            if level > 0.9 { return HUDConstants.rose }
            if level > 0.75 { return HUDConstants.amber }
            return HUDConstants.emerald
        }
    }

    private func trackColor(_ fill: Color) -> Color {
        switch style {
        case .white, .glow:
            return HUDConstants.unfilledTrack
        case .accent, .decibel:
            return fill.opacity(0.25)
        }
    }
}

// MARK: - Device glyphs

/// SF Symbols for the output device ("Show device"). Foyer draws symbols,
/// not Alcove's AirPods videos.
enum HUDDeviceGlyph {
    static let fallback = "speaker.wave.2.fill"

    @MainActor
    static func symbol(for kind: VolumeOutputDeviceKind) -> String {
        switch kind {
        case .builtInSpeakers:
            return VolumeManager.hostIsLaptop ? "laptopcomputer" : "desktopcomputer"
        case .builtInHeadphones: return "headphones"
        case .airPods: return "airpods"
        case .airPodsGen3: return "airpods.gen3"
        case .airPodsGen4: return exists("airpods.gen4") ? "airpods.gen4" : "airpods.gen3"
        case .airPodsPro: return "airpodspro"
        case .airPodsMax: return "airpodsmax"
        case .beats: return "beats.headphones"
        case .bluetoothHeadphones: return "headphones"
        case .bluetoothSpeaker: return "hifispeaker.fill"
        case .homePod: return "homepod.fill"
        case .airPlay: return "airplayaudio"
        case .display: return "display"
        case .usb, .other: return "hifispeaker.fill"
        }
    }

    /// Returns `name` when the running system has it, else a safe fallback.
    static func resolved(_ name: String) -> String {
        exists(name) ? name : fallback
    }

    private static func exists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}
