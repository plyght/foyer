import Defaults
import Luminare
import SwiftUI

/// General (lead §5): system rows, Display on, Idle Activity cards,
/// Behaviour and Gestures.
struct SettingsGeneralPane: View {
    @Default(.launchAtLogin) private var launchAtLogin
    @Default(.hideMenuBarIcon) private var hideMenuBarIcon
    @Default(.hideWhileInFullscreen) private var hideWhileInFullscreen
    @Default(.hideWhileInMissionControl) private var hideWhileInMissionControl
    @Default(.hideWhileGaming) private var hideWhileGaming
    @Default(.hideFromScreenCapture) private var hideFromScreenCapture
    @Default(.forceSimulatedNotch) private var forceSimulatedNotch
    @Default(.notchAdjustedWidth) private var notchAdjustedWidth
    @Default(.notchAdjustedHeight) private var notchAdjustedHeight
    @Default(.showOnDisplay) private var showOnDisplay
    @Default(.showOnDisplayUUID) private var showOnDisplayUUID
    @Default(.showOnDisplayName) private var showOnDisplayName
    @Default(.showOnDisplaySymbol) private var showOnDisplaySymbol

    @Default(.idleActivity) private var idleActivity
    @Default(.mostRecentActivity) private var mostRecentActivity

    @Default(.contrastOutline) private var contrastOutline
    @Default(.progressiveBlur) private var progressiveBlur
    @Default(.enableHaptics) private var enableHaptics
    @Default(.expandNotchOnHover) private var expandNotchOnHover
    @Default(.hoverDuration) private var hoverDuration

    @Default(.naturalMovement) private var naturalMovement
    @Default(.swipeToToggle) private var swipeToToggle
    @Default(.swipeToCycleActivity) private var swipeToCycleActivity
    @Default(.swipeToDismiss) private var swipeToDismiss
    @Default(.swipeToSkip) private var swipeToSkip

    @ObservedObject private var displays = SettingsDisplayList.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            systemSection
            idleActivitySection
            behaviourSection
            gesturesSection
        }
    }

    // MARK: Sections

    private var systemSection: some View {
        LuminareSection {
            SettingsToggleRow("Launch at login", isOn: $launchAtLogin)
            SettingsToggleRow(
                "Hide menu bar icon", isOn: $hideMenuBarIcon,
                info: "Open Foyer again from Finder or Spotlight to show Settings while the icon is hidden."
            )
            SettingsToggleRow("Hide in fullscreen", isOn: $hideWhileInFullscreen)
            SettingsToggleRow("Hide in mission control", isOn: $hideWhileInMissionControl)
            SettingsToggleRow("Hide while gaming", isOn: $hideWhileGaming)
            SettingsToggleRow("Hide from screen capture", isOn: $hideFromScreenCapture)
            SettingsToggleRow(
                "Force simulated notch", isOn: $forceSimulatedNotch,
                info: "Draws a notch flush with the top of displays that have none, instead of a floating capsule."
            )
            if displays.hasHardwareNotch {
                notchTuningRows
            }
            displayRow
        }
    }

    @ViewBuilder private var notchTuningRows: some View {
        SettingsSliderRow(
            "Notch width tuning", value: $notchAdjustedWidth, options: SettingsSliderStops.notchTuning,
            unit: "px", fractionDigits: 0,
            onChange: { _ in SoundPlayer.play(.haptic, volume: 0.5) }
        )
        SettingsSliderRow(
            "Notch height tuning", value: $notchAdjustedHeight, options: SettingsSliderStops.notchTuning,
            unit: "px", fractionDigits: 0,
            onChange: { _ in SoundPlayer.play(.haptic, volume: 0.5) }
        )
    }

    private var displayRow: some View {
        SettingsControlRow("Display on") {
            Picker("", selection: displayTag) {
                Label("Main display", systemImage: "display")
                    .tag(ShellDisplaySelection.mainTag)
                Label("All displays", systemImage: "rectangle.on.rectangle")
                    .tag(ShellDisplaySelection.allTag)
                if displays.hasBuiltIn {
                    Label("Built-in display", systemImage: "laptopcomputer")
                        .tag(ShellDisplaySelection.builtInTag)
                }
                Divider()
                ForEach(displays.entries) { entry in
                    Label(entry.name, systemImage: entry.symbol)
                        .tag(ShellDisplaySelection.uuidPrefix + entry.uuid)
                }
                if let missing = disconnectedDisplayTag {
                    Label("\(showOnDisplayName ?? "Display") (disconnected)", systemImage: showOnDisplaySymbol ?? "display")
                        .tag(missing)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private var displayTag: Binding<String> {
        let type = showOnDisplay
        let uuid = showOnDisplayUUID
        return Binding(
            get: {
                switch type {
                case .mainScreen: return ShellDisplaySelection.mainTag
                case .allDisplays: return ShellDisplaySelection.allTag
                case .builtInDisplay: return ShellDisplaySelection.builtInTag
                case .specificDisplay: return ShellDisplaySelection.uuidPrefix + (uuid ?? "")
                }
            },
            set: { tag in
                ShellDisplaySelection.select(tag: tag)
            }
        )
    }

    /// Tag for a chosen display that is not connected right now.
    private var disconnectedDisplayTag: String? {
        guard showOnDisplay == .specificDisplay else { return nil }
        let uuid = showOnDisplayUUID ?? ""
        guard !displays.entries.contains(where: { $0.uuid == uuid }) else { return nil }
        return ShellDisplaySelection.uuidPrefix + uuid
    }

    private var idleActivitySection: some View {
        LuminareSection("Idle Activity") {
            SettingsToggleRow(
                "Most Recent", isOn: $mostRecentActivity, symbol: "clock.arrow.circlepath",
                info: "Shows whichever live activity changed last instead of the one chosen below."
            )
            SettingsTilePicker(
                IdleActivity.allCases, selection: $idleActivity, height: SettingsMetrics.tallTileHeight,
                title: { $0.settingsTitle }
            ) { activity, isSelected in
                SettingsIdleActivityPreview(activity: activity, isSelected: isSelected)
            }
        }
    }

    private var behaviourSection: some View {
        LuminareSection("Behaviour") {
            SettingsToggleRow(
                "Contrast outline", isOn: $contrastOutline,
                info: "Adds a faint outline so the island stays visible over dark wallpapers and windows."
            )
            SettingsToggleRow(
                "Progressive blur", isOn: $progressiveBlur,
                info: "Softly blurs the content behind the bottom edge of the expanded island."
            )
            SettingsToggleRow("Haptic feedback", isOn: $enableHaptics)
            SettingsToggleRow(
                "Expand on hover", isOn: $expandNotchOnHover,
                info: "Opens the expanded view when the pointer rests on the island, without clicking."
            )
            if expandNotchOnHover {
                SettingsSliderRow("Hover delay", value: $hoverDuration, options: SettingsSliderStops.hoverDelay, unit: "s")
            }
        }
    }

    private var gesturesSection: some View {
        LuminareSection("Gestures") {
            SettingsToggleRow("Natural movement", isOn: $naturalMovement)
            SettingsToggleRow("Swipe to toggle open", isOn: $swipeToToggle)
            SettingsToggleRow(
                "Swipe to cycle activity", isOn: $swipeToCycleActivity,
                info: "Swipe up on the island to hide the current live activity and show the next one; swipe down to bring it back."
            )
            SettingsToggleRow(
                "Swipe to dismiss activity", isOn: $swipeToDismiss,
                info: "Swipe up on a notification or Quick Peek to dismiss it early."
            )
            SettingsToggleRow("Swipe to skip media", isOn: $swipeToSkip)
        }
    }
}

/// Mini previews on the Idle Activity cards: None (⊘), Playing (rose play
/// tile), Calendar (rose "11" tile), Duo (both).
struct SettingsIdleActivityPreview: View {
    let activity: IdleActivity
    let isSelected: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(activity == .none ? Color.primary.opacity(0.07) : SettingsTab.nowPlaying.tint.opacity(isSelected ? 0.22 : 0.16))
            switch activity {
            case .none:
                Image(systemName: "nosign")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            case .nowPlaying:
                SettingsMiniAppTile(color: SettingsTab.nowPlaying.tint, symbol: "play.fill", size: 22)
            case .calendar:
                SettingsCalendarGlyph(size: 22)
            case .duo:
                HStack(spacing: -4) {
                    SettingsMiniAppTile(color: SettingsTab.nowPlaying.tint, symbol: "play.fill", size: 22)
                    SettingsCalendarGlyph(size: 22)
                }
            }
        }
    }
}
