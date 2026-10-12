import Defaults
import SwiftUI

// MARK: - Duo column

/// Compact player for the Duo page (Now Playing beside Calendar). The
/// explicit badge shows here too (Part H.3 / Part I §1.1).
struct NowPlayingDuoColumn: View {
    @ObservedObject private var manager = NowPlayingManager.shared
    @Environment(\.notchGeometry) private var geometry

    var body: some View {
        VStack(spacing: 0) {
            if manager.snapshot != nil {
                HStack(alignment: .center, spacing: 10) {
                    NowPlayingArtworkView(image: manager.artworkImage,
                                          identity: manager.artworkIdentity,
                                          size: 48,
                                          cornerRadius: 9)
                    NowPlayingTitleBlock(titleSize: NowPlayingMetrics.Expanded.titleSize,
                                         artistSize: NowPlayingMetrics.Expanded.artistSize,
                                         titleColor: .white,
                                         artistColor: NowPlayingMetrics.Palette.secondaryText,
                                         badgeColor: NowPlayingMetrics.Badge.color,
                                         badgeSpacing: NowPlayingMetrics.Badge.spacing)
                        .id(manager.snapshot?.trackIdentity ?? "")
                        .transition(.opacity)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    NowPlayingWaveformView(style: .compact, tint: manager.palette.waveformColor)
                        .opacity(manager.isPlaying ? 1 : 0.35)
                }
                .frame(height: 48)
                .animation(Constants.Animations.contentSwap, value: manager.snapshot?.trackIdentity ?? "")

                NowPlayingProgressBar()
                    .frame(height: 12)
                    .padding(.top, 10)

                NowPlayingTransportControls(showsVolumeButton: false, showsExtraButton: true, spacing: 6)
                    .frame(height: NowPlayingMetrics.Expanded.buttonHitSize.height)
                    .padding(.top, 6)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Color(white: 0.45))
                    Text("Not Playing")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(NowPlayingMetrics.Palette.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Spacer(minLength: 0)
        }
        // Start below the closed notch so nothing sits under the camera housing.
        .padding(.top, geometry.closedSize.height + 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

// MARK: - Lock-screen widget

/// The lock-screen media widget (v3 live pass), laid out like the expanded
/// player: artwork, marquee title + white explicit badge, artist and the
/// waveform; elapsed / progress / remaining; extra · previous · play/pause ·
/// next; plus the volume row when `showVolumeControl` is on.
///
/// `LockScreenWidgetStack` supplies the card: width, the Glass / Clear /
/// Frosted material from `nowPlayingStyle`, border, shadow and the ~0.4 s
/// delayed fade/scale-in. This view draws content and padding only, and
/// renders nothing when nothing is playing so the card disappears with it.
struct NowPlayingLockWidget: View {
    @ObservedObject private var manager = NowPlayingManager.shared
    @Default(.nowPlayingStyle) private var material
    @Default(.showVolumeControl) private var showVolumeControl

    private typealias L = NowPlayingMetrics.Lock

    var body: some View {
        if manager.snapshot != nil {
            content
                .onAppear { manager.lockScreenWidgetDidShow() }
                .onDisappear { manager.lockScreenWidgetDidHide() }
        }
    }

    /// Secondary text is a touch stronger on the see-through Clear material.
    private var secondary: Color {
        Color.white.opacity(material == .clear ? 0.75 : 0.65)
    }

    private var content: some View {
        let identity = manager.snapshot?.trackIdentity ?? ""
        return VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                NowPlayingArtworkView(image: manager.artworkImage,
                                      identity: manager.artworkIdentity,
                                      size: L.artworkSize,
                                      cornerRadius: L.artworkCornerRadius)
                NowPlayingTitleBlock(titleSize: 14, artistSize: 12,
                                     titleColor: .white, artistColor: secondary,
                                     badgeColor: .white, badgeSpacing: NowPlayingMetrics.Badge.lockSpacing)
                    .id(identity)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, alignment: .leading)
                NowPlayingWaveformView(style: .compact, tint: .white)
                    .opacity(manager.isPlaying ? 1 : 0.4)
            }
            .animation(Constants.Animations.contentSwap, value: identity)

            NowPlayingProgressBar(labelSize: 11, labelColor: secondary,
                                  trackBackground: Color.white.opacity(0.18), forceWhiteFill: true)
                .frame(height: 14)

            NowPlayingTransportControls(showsVolumeButton: false, showsExtraButton: true,
                                        foreground: .white, controlSize: 17, playPauseSize: 24, spacing: 18)
                .frame(height: 32)

            if showVolumeControl {
                NowPlayingVolumeRow(trackWidth: nil, foreground: secondary, fill: .white,
                                    trackBackground: Color.white.opacity(0.18))
                    .frame(height: 20)
            }
        }
        .padding(L.padding)
        .frame(maxWidth: .infinity)
        .environment(\.colorScheme, .dark)
    }
}
