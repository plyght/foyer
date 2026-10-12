import Defaults
import SwiftUI

/// Battery outline with a level fill, a cap and an optional bolt
/// (`Alcove.Battery`: level, lowBatteryThreshold, showPercentage,
/// isLowPowerMode, symbolReduction; bolt is an SF Symbol).
struct SystemBatteryGlyph: View {
    /// 0...1.
    var level: Double
    var tint: Color
    var showsBolt: Bool
    var size: CGSize = SystemConstants.Battery.glyphSize

    var body: some View {
        let corner = size.height * 0.32
        let inset: CGFloat = 2
        let clamped = min(max(level, 0), 1)
        let innerWidth = size.width - inset * 2
        let fillWidth = max(innerWidth * CGFloat(clamped), clamped > 0 ? 2 : 0)

        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.4), lineWidth: 1)
                RoundedRectangle(cornerRadius: max(corner - inset, 1), style: .continuous)
                    .fill(tint)
                    .frame(width: fillWidth, height: size.height - inset * 2)
                    .padding(.leading, inset)
            }
            .frame(width: size.width, height: size.height)
            .overlay {
                if showsBolt {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: size.height * 0.78, weight: .heavy))
                        .foregroundStyle(Color.white)
                        .shadow(color: Color.black.opacity(0.55), radius: 0.6)
                }
            }

            RoundedRectangle(cornerRadius: 1, style: .continuous)
                .fill(Color.white.opacity(0.4))
                .frame(width: 1.5, height: size.height * 0.38)
        }
        .animation(Constants.Animations.standard, value: clamped)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Battery"))
        .accessibilityValue(Text(verbatim: "\(Int((clamped * 100).rounded()))%"))
    }
}

/// Leading wing: the coloured state label ("Charging", "Low Battery", "Low Power").
@MainActor
struct SystemBatteryNotificationLeading: View {
    let alert: SystemBatteryAlert
    @Default(.hideBatteryLabel) private var hideLabel

    var body: some View {
        Group {
            if hideLabel {
                if alert == .lowPowerOn || alert == .lowPowerOff {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(labelColor)
                } else if alert == .charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(labelColor)
                } else {
                    Color.clear
                }
            } else {
                Text(alert.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: hideLabel ? .center : .leading)
        .padding(.leading, hideLabel ? 0 : 8)
    }

    private var labelColor: Color {
        switch alert {
        case .charging: return Constants.Battery.charging
        case .lowBattery: return Constants.Battery.low
        case .lowPowerOn: return SystemConstants.Battery.lowPowerTint
        case .lowPowerOff: return Color.white.opacity(0.7)
        }
    }
}

/// Trailing wing: percentage + battery glyph, live.
@MainActor
struct SystemBatteryNotificationTrailing: View {
    let alert: SystemBatteryAlert
    @ObservedObject private var battery = SystemBatteryManager.shared
    @Default(.hideBatteryPercentage) private var hidePercentage
    /// Observed so the tint follows threshold changes.
    @Default(.lowBatteryThreshold) private var threshold

    var body: some View {
        let tint = battery.tint(for: alert)
        HStack(spacing: 5) {
            if !hidePercentage {
                Text(verbatim: "\(battery.percent)%")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.numericText(value: Double(battery.percent)))
            }
            SystemBatteryGlyph(level: battery.level, tint: tint,
                               showsBolt: alert == .charging || (battery.isPluggedIn && battery.isCharging))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: hidePercentage ? .center : .trailing)
        .padding(.trailing, hidePercentage ? 0 : 8)
        .animation(Constants.Animations.standard, value: battery.percent)
    }
}

/// Lock-screen battery widget: large glyph, percentage and state line.
/// Renders nothing on Macs without a battery. Designed to sit on the lock
/// screen's glass card (white content, no background of its own).
@MainActor
struct BatteryLockWidget: View {
    @ObservedObject private var battery = SystemBatteryManager.shared
    @Default(.showRemainingTime) private var showRemainingTime

    init() {}

    var body: some View {
        if battery.hasBattery {
            HStack(spacing: 12) {
                SystemBatteryGlyph(level: battery.level, tint: battery.tint(),
                                   showsBolt: battery.isPluggedIn && battery.isCharging,
                                   size: CGSize(width: 38, height: 18))
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "\(battery.percent)%")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Color.white)
                        .contentTransition(.numericText(value: Double(battery.percent)))
                    statusLine
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.65))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .shadow(color: Color.black.opacity(0.15), radius: 2, y: 1)
            .animation(Constants.Animations.standard, value: battery.percent)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if battery.isPluggedIn && battery.isFullyCharged {
            Text("Fully Charged")
        } else if battery.isPluggedIn && battery.isCharging {
            if showRemainingTime, let minutes = battery.remainingMinutes {
                Text("Charging · \(Self.format(minutes: minutes)) until full")
            } else {
                Text("Charging")
            }
        } else if battery.isPluggedIn {
            Text("Power Adapter")
        } else if battery.isLowPowerModeEnabled {
            Text("Low Power")
        } else if showRemainingTime, let minutes = battery.remainingMinutes {
            Text("\(Self.format(minutes: minutes)) remaining")
        } else {
            Text("Battery")
        }
    }

    private static func format(minutes: Int) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = minutes >= 60 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: TimeInterval(minutes * 60)) ?? "\(minutes) min"
    }
}
