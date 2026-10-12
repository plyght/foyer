import Defaults
import Luminare
import SwiftUI

/// Now Playing (lead §5, Part C2 §2-3): idle duration, explicit badge,
/// format, waveform options, extra button, source and Quick Peek.
struct SettingsNowPlayingPane: View {
    @Default(.enableNowPlaying) private var enableNowPlaying
    @Default(.idleDuration) private var idleDuration
    @Default(.songTitleBadge) private var songTitleBadge
    @Default(.progressStyle) private var progressStyle
    @Default(.useLiveWaveform) private var useLiveWaveform
    @Default(.disableWaveform) private var disableWaveform
    @Default(.disableAlbumArtFlip) private var disableAlbumArtFlip
    @Default(.hideWhileSourceIsActive) private var hideWhileSourceIsActive
    @Default(.hideSongTitleExtras) private var hideSongTitleExtras
    @Default(.showRemainingTime) private var showRemainingTime
    @Default(.controlChoice) private var controlChoice
    @Default(.automaticMusicApp) private var automaticMusicApp
    @Default(.musicApp) private var musicApp
    @Default(.enableQuickPeek) private var enableQuickPeek
    @Default(.whenSongChanges) private var whenSongChanges
    @Default(.peekDuration) private var peekDuration

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            mainSection
            sourceSection
            extensionSection
        }
    }

    private var mainSection: some View {
        LuminareSection {
            SettingsFeatureToggleRow(.nowPlaying, isOn: $enableNowPlaying)
            Group {
                SettingsSliderRow("Idle duration", value: $idleDuration, options: SettingsSliderStops.mediaIdle, unit: "s")
                    .disabled(!enableNowPlaying)
                SettingsTilePicker(SongTitleBadge.allCases, selection: $songTitleBadge, title: { $0.settingsTitle }) { badge, _ in
                    SettingsDarkTile {
                        Image(systemName: badge.settingsSymbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(badge == .none ? Color.white.opacity(0.45) : Color.white)
                    }
                }
                .disabled(!enableNowPlaying)
                SettingsTilePicker(NowPlayingFormat.allCases, selection: $progressStyle, title: { $0.settingsTitle }) { format, _ in
                    SettingsDarkTile {
                        SettingsWaveformPreview(format: format)
                    }
                }
                .disabled(!enableNowPlaying)
            }
            Group {
                SettingsToggleRow(
                    "Use live waveform", isOn: $useLiveWaveform,
                    info: "Draws the waveform from the audio that is actually playing instead of an animation.",
                    permission: .audioCapture
                )
                .disabled(!enableNowPlaying || disableWaveform)
                SettingsToggleRow("Disable compact waveform", isOn: $disableWaveform)
                    .disabled(!enableNowPlaying)
                SettingsToggleRow("Disable artwork flip", isOn: $disableAlbumArtFlip)
                    .disabled(!enableNowPlaying)
                SettingsToggleRow("Hide while source app is active", isOn: $hideWhileSourceIsActive)
                    .disabled(!enableNowPlaying)
                SettingsToggleRow("Hide media title extras", isOn: $hideSongTitleExtras)
                    .disabled(!enableNowPlaying)
                SettingsToggleRow("Show remaining time", isOn: $showRemainingTime)
                    .disabled(!enableNowPlaying)
            }
            SettingsTilePicker(ControlChoice.allCases, selection: $controlChoice, title: { $0.settingsTitle }) { choice, isSelected in
                SettingsSymbolTile(symbol: choice.settingsSymbol, isSelected: isSelected)
            }
            .disabled(!enableNowPlaying)
        }
    }

    private var sourceSection: some View {
        LuminareSection("Source") {
            SettingsToggleRow(
                "Automatic", isOn: $automaticMusicApp, symbol: "wand.and.stars",
                subtitle: automaticMusicApp ? nil : "∙ \(musicApp.settingsTitle)",
                info: "Follows whichever app is playing. Turn off to always control one app."
            )
            if !automaticMusicApp {
                SettingsTilePicker(MusicApp.allCases, selection: musicAppBinding, height: SettingsMetrics.tallTileHeight,
                                   title: { $0.settingsTitle }) { app, isSelected in
                    ZStack {
                        Rectangle()
                            .fill(isSelected ? SettingsMetrics.accent.opacity(0.14) : Color.primary.opacity(0.06))
                        ShellAppIconView(bundleIdentifier: app.settingsBundleIdentifier, fallbackSymbol: "gearshape.fill", size: 30)
                    }
                }
            }
        }
        .disabled(!enableNowPlaying)
    }

    /// Choosing Music or Spotify asks for the Automation permission right away.
    private var musicAppBinding: Binding<MusicApp> {
        Binding(
            get: { musicApp },
            set: { app in
                musicApp = app
                if let bundleIdentifier = app.settingsBundleIdentifier {
                    Task { @MainActor in
                        await ShellPermissions.shared.requestAutomation(for: bundleIdentifier, launchIfNeeded: false)
                    }
                }
            }
        )
    }

    private var extensionSection: some View {
        LuminareSection("Extension") {
            SettingsToggleRow("Quick Peek", isOn: $enableQuickPeek, symbol: "rectangle.topthird.inset.filled",
                              symbolColor: SettingsMetrics.accent)
            SettingsToggleRow("When media changes", isOn: $whenSongChanges)
                .disabled(!enableQuickPeek)
            SettingsSliderRow("Peek duration", value: $peekDuration, options: SettingsSliderStops.peekDuration, unit: "s")
                .disabled(!enableQuickPeek)
        }
        .disabled(!enableNowPlaying)
    }
}

/// Five-bar waveform in the three Now Playing formats.
struct SettingsWaveformPreview: View {
    let format: NowPlayingFormat

    static let heights: [CGFloat] = [0.45, 0.85, 0.6, 1.0, 0.5]
    static let colored = Color(red: 0.98, green: 0.36, blue: 0.48)

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<SettingsWaveformPreview.heights.count, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(fill(at: index))
                    .frame(width: 3, height: 16 * SettingsWaveformPreview.heights[index])
            }
        }
    }

    private func fill(at index: Int) -> AnyShapeStyle {
        switch format {
        case .mono:
            return AnyShapeStyle(Color.white)
        case .colored:
            return AnyShapeStyle(SettingsWaveformPreview.colored)
        case .gradient:
            return AnyShapeStyle(LinearGradient(
                colors: [Color(red: 1.0, green: 0.45, blue: 0.35), Color(red: 0.85, green: 0.3, blue: 0.9)],
                startPoint: .bottom, endPoint: .top
            ))
        }
    }
}

/// The icon of an installed app, or a grey tile with `fallbackSymbol`.
struct ShellAppIconView: View {
    let bundleIdentifier: String?
    let fallbackSymbol: String
    var size: CGFloat = 32

    var body: some View {
        if let image = ShellAppIconView.icon(for: bundleIdentifier) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                .fill(Color.gray.gradient)
                .frame(width: size * 0.84, height: size * 0.84)
                .overlay {
                    Image(systemName: fallbackSymbol)
                        .font(.system(size: size * 0.42, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                .frame(width: size, height: size)
        }
    }

    static func icon(for bundleIdentifier: String?) -> NSImage? {
        guard let bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
