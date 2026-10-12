import Defaults
import SwiftUI

// MARK: - Compact activity (Part C §1)

/// Left wing: 22×22 artwork, ~5 pt corners, fading with playback.
struct NowPlayingCompactLeading: View {
    @ObservedObject private var manager = NowPlayingManager.shared

    var body: some View {
        NowPlayingArtworkView(image: manager.artworkImage,
                              identity: manager.artworkIdentity,
                              size: NowPlayingMetrics.Compact.artworkSize,
                              cornerRadius: NowPlayingMetrics.Compact.artworkCornerRadius)
            .opacity(manager.contentVisible ? 1 : 0)
            .padding(.leading, NowPlayingMetrics.Compact.artworkInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Right wing: the 5-bar waveform (or the Focus glyph), right-aligned
/// ~10 pt from the edge, hidden with "Disable waveform".
struct NowPlayingCompactTrailing: View {
    @ObservedObject private var manager = NowPlayingManager.shared
    @Default(.disableWaveform) private var disableWaveform

    var body: some View {
        ZStack(alignment: .trailing) {
            if !disableWaveform {
                NowPlayingCompactTrailingGlyph(style: .compact)
                    .opacity(manager.contentVisible && manager.isPlaying ? 1 : 0)
            }
        }
        .padding(.trailing, NowPlayingMetrics.Compact.waveformInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

// MARK: - Quick Peek (Part C2 §4.2)

/// 233×70 two-row capsule: row 1 mirrors the compact activity, row 2 is a
/// centred "♪ Title · Artist" line (clipped, not marqueed).
struct NowPlayingPeekView: View {
    @ObservedObject private var manager = NowPlayingManager.shared
    @Environment(\.notchGeometry) private var geometry

    var body: some View {
        let title = manager.snapshot?.title ?? ""
        let artist = manager.snapshot?.artist ?? ""
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                NowPlayingArtworkView(image: manager.artworkImage,
                                      identity: manager.artworkIdentity,
                                      size: NowPlayingMetrics.Compact.artworkSize,
                                      cornerRadius: NowPlayingMetrics.Compact.artworkCornerRadius)
                    .padding(.leading, NowPlayingMetrics.Compact.artworkInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: geometry.closedSize.width)
                NowPlayingWaveformView(style: .compact, tint: manager.palette.waveformColor)
                    .padding(.trailing, NowPlayingMetrics.Compact.waveformInset)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(height: max(geometry.closedSize.height, NowPlayingMetrics.Compact.artworkSize + 4))

            HStack(spacing: 4) {
                Image(systemName: "music.note")
                    .font(.system(size: NowPlayingMetrics.Peek.textSize - 1, weight: .semibold))
                    .foregroundStyle(manager.palette.waveformColor)
                (Text(title.isEmpty ? "No Title" : title).foregroundStyle(Color.white)
                    + Text(artist.isEmpty ? "" : " · \(artist)").foregroundStyle(NowPlayingMetrics.Palette.secondaryText))
                    .font(.system(size: NowPlayingMetrics.Peek.textSize, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Expanded player (362×120, Part C §1 / Part C2 §3.2)

struct NowPlayingExpandedView: View {
    @ObservedObject private var manager = NowPlayingManager.shared
    @Environment(\.notchGeometry) private var geometry
    @State private var controlsShown = false

    private typealias M = NowPlayingMetrics.Expanded

    var body: some View {
        let identity = manager.snapshot?.trackIdentity ?? ""
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                NowPlayingArtworkView(image: manager.artworkImage,
                                      identity: manager.artworkIdentity,
                                      size: M.artworkSize,
                                      cornerRadius: M.artworkCornerRadius)

                NowPlayingTitleBlock(titleSize: M.titleSize, artistSize: M.artistSize,
                                     titleColor: .white, artistColor: NowPlayingMetrics.Palette.secondaryText,
                                     badgeColor: NowPlayingMetrics.Badge.color,
                                     badgeSpacing: NowPlayingMetrics.Badge.spacing)
                    .id(identity)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, alignment: .leading)

                NowPlayingWaveformView(style: .expanded, tint: manager.palette.waveformColor)
                    .opacity(manager.isPlaying ? 1 : 0.35)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 6)
            }
            .frame(height: M.artworkSize)
            .animation(Constants.Animations.contentSwap, value: identity)

            NowPlayingProgressBar(labelSize: M.timeSize, labelColor: NowPlayingMetrics.Palette.secondaryText)
                .frame(height: 12)
                .padding(.top, 5)

            NowPlayingTransportControls(showsVolumeButton: true)
                .frame(height: M.buttonHitSize.height)
                .padding(.top, 3)
                .scaleEffect(controlsShown ? 1 : 0.85)
                .opacity(controlsShown ? 1 : 0)

            if manager.isVolumeRowVisible {
                NowPlayingVolumeRow(trackWidth: M.volumeTrackWidth)
                    .frame(height: 26)
                    .padding(.top, 2)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer(minLength: 0)
        }
        .padding(.top, M.inset + NowPlayingManager.hardwareNotchExtra(for: geometry))
        .padding(.horizontal, M.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            withAnimation(Constants.Animations.controlStrip) { controlsShown = true }
        }
        .onDisappear { controlsShown = false }
    }
}

/// Title (bold, marquee, explicit badge) over artist (regular, grey, marquee).
struct NowPlayingTitleBlock: View {
    var titleSize: CGFloat
    var artistSize: CGFloat
    var titleColor: Color
    var artistColor: Color
    var badgeColor: Color
    var badgeSpacing: CGFloat
    var alignment: HorizontalAlignment = .leading

    @ObservedObject private var manager = NowPlayingManager.shared

    var body: some View {
        let snapshot = manager.snapshot
        let title = (snapshot?.title.isEmpty ?? true) ? "No Title" : (snapshot?.title ?? "")
        let artist = snapshot?.artist ?? ""
        let explicit = snapshot?.isExplicit ?? false
        let titleFont = Font.system(size: titleSize, weight: .semibold)

        VStack(alignment: alignment, spacing: 2) {
            // Badge follows the title width; once the title overflows it
            // scrolls and the badge pins to the trailing edge.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: badgeSpacing) {
                    Text(title)
                        .font(titleFont)
                        .foregroundStyle(titleColor)
                        .lineLimit(1)
                        .fixedSize()
                    NowPlayingExplicitBadge(isExplicit: explicit, color: badgeColor)
                }
                HStack(alignment: .firstTextBaseline, spacing: badgeSpacing) {
                    NowPlayingMarqueeText(text: title, font: titleFont, color: titleColor)
                    NowPlayingExplicitBadge(isExplicit: explicit, color: badgeColor)
                }
            }
            if !artist.isEmpty {
                NowPlayingMarqueeText(text: artist, font: .system(size: artistSize, weight: .regular), color: artistColor)
            }
        }
    }
}

/// `e.square.fill` (or `e.square` for the outline variant), ~11×11 incl.
/// anti-aliasing, after the title (Part H.3). Never shown in compact, hover
/// or Quick Peek.
struct NowPlayingExplicitBadge: View {
    let isExplicit: Bool
    var color: Color = NowPlayingMetrics.Badge.color

    @Default(.songTitleBadge) private var badge
    @Default(.hideSongTitleExtras) private var hideExtras

    var body: some View {
        if isExplicit && !hideExtras && badge != SongTitleBadge.none {
            Image(systemName: badge == .explicitOutline ? "e.square" : "e.square.fill")
                .font(.system(size: NowPlayingMetrics.Badge.glyphSize, weight: .medium))
                .foregroundStyle(color)
                .offset(y: 1)
                .accessibilityLabel("Explicit")
        }
    }
}

// MARK: - Progress

/// Elapsed · scrubber · remaining (`-m:ss`), ~10 pt monospaced digits, a 4 pt
/// rounded track whose fill follows the Monochrome / Colored / Gradient
/// format (Part C2 §2.1). Drag or click to seek.
struct NowPlayingProgressBar: View {
    var labelSize: CGFloat = NowPlayingMetrics.Expanded.timeSize
    var labelColor: Color = NowPlayingMetrics.Palette.secondaryText
    var trackBackground: Color = NowPlayingMetrics.Palette.trackBackground
    /// Lock-screen widget: white fill regardless of format.
    var forceWhiteFill = false

    @ObservedObject private var manager = NowPlayingManager.shared
    @Default(.progressStyle) private var format
    @Default(.showRemainingTime) private var showRemainingTime
    @State private var scrubFraction: Double?

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !manager.isPlaying || scrubFraction != nil)) { context in
            let duration = manager.duration
            let live = manager.elapsed(at: context.date)
            let elapsed = scrubFraction.map { $0 * duration } ?? live
            let fraction = duration > 0 ? min(max(elapsed / duration, 0), 1) : 0

            HStack(spacing: 8) {
                Text(Self.timeString(elapsed))
                    .frame(minWidth: 28, alignment: .leading)
                track(fraction: fraction, duration: duration)
                Text(duration > 0 ? (showRemainingTime ? "-" + Self.timeString(max(0, duration - elapsed)) : Self.timeString(duration)) : "--:--")
                    .frame(minWidth: 32, alignment: .trailing)
            }
            .font(.system(size: labelSize, weight: .medium).monospacedDigit())
            .foregroundStyle(labelColor)
            .lineLimit(1)
        }
    }

    private func track(fraction: Double, duration: Double) -> some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let height = scrubFraction != nil ? NowPlayingMetrics.Expanded.trackHeightActive : NowPlayingMetrics.Expanded.trackHeight
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(trackBackground)
                Capsule(style: .continuous)
                    .fill(fillStyle)
                    .frame(width: max(height, width * CGFloat(fraction)))
                    .opacity(fraction > 0 ? 1 : 0)
            }
            .frame(height: height)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard duration > 0 else { return }
                        let next = min(max(Double(value.location.x / width), 0), 1)
                        if scrubFraction == nil {
                            withAnimation(Constants.Animations.standard) { scrubFraction = next }
                        } else {
                            scrubFraction = next
                        }
                    }
                    .onEnded { value in
                        guard duration > 0 else { scrubFraction = nil; return }
                        let final = min(max(Double(value.location.x / width), 0), 1)
                        manager.seek(to: final * duration)
                        withAnimation(Constants.Animations.standard) { scrubFraction = nil }
                    }
            )
        }
    }

    private var fillStyle: AnyShapeStyle {
        if forceWhiteFill { return AnyShapeStyle(Color.white) }
        switch format {
        case .mono:
            return AnyShapeStyle(NowPlayingMetrics.Palette.monoFill)
        case .colored:
            return AnyShapeStyle(manager.palette.coloredFill)
        case .gradient:
            return AnyShapeStyle(LinearGradient(colors: manager.palette.gradientColors,
                                                startPoint: .leading, endPoint: .trailing))
        }
    }

    static func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(max(0, seconds).rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Transport controls

/// Extra button · previous · play/pause (larger) · next · output/volume.
struct NowPlayingTransportControls: View {
    var showsVolumeButton: Bool = true
    var showsExtraButton: Bool = true
    var foreground: Color = .white
    var controlSize: CGFloat = NowPlayingMetrics.Expanded.controlSize
    var playPauseSize: CGFloat = NowPlayingMetrics.Expanded.playPauseSize
    var spacing: CGFloat = 10

    @ObservedObject private var manager = NowPlayingManager.shared

    var body: some View {
        HStack(spacing: spacing) {
            if showsExtraButton {
                NowPlayingExtraButton(size: controlSize, foreground: foreground)
            }
            NowPlayingControlButton(systemName: "backward.fill", size: controlSize, foreground: foreground) {
                manager.previous()
            }
            NowPlayingControlButton(systemName: manager.isPlaying ? "pause.fill" : "play.fill",
                                    size: playPauseSize, foreground: foreground) {
                manager.togglePlayPause()
            }
            NowPlayingControlButton(systemName: "forward.fill", size: controlSize, foreground: foreground) {
                manager.next()
            }
            if showsVolumeButton {
                NowPlayingControlButton(systemName: "hifispeaker.fill", size: controlSize - 1,
                                        foreground: foreground, highlighted: manager.isVolumeRowVisible) {
                    manager.toggleVolumeRow()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Left-slot button chosen by `controlChoice` (Part C2 §3.3).
struct NowPlayingExtraButton: View {
    var size: CGFloat = NowPlayingMetrics.Expanded.controlSize
    var foreground: Color = .white

    @ObservedObject private var manager = NowPlayingManager.shared
    @Default(.controlChoice) private var choice

    var body: some View {
        switch choice {
        case .favorite:
            NowPlayingControlButton(systemName: manager.isFavorite ? "star.fill" : "star", size: size,
                                    foreground: foreground, highlighted: manager.isFavorite) {
                manager.toggleFavorite()
            }
            .disabled(!manager.canFavorite)
            .opacity(manager.canFavorite ? 1 : 0.35)
        case .shuffle:
            NowPlayingControlButton(systemName: "shuffle", size: size, foreground: foreground,
                                    highlighted: manager.shuffleMode.isOn) {
                manager.toggleShuffle()
            }
        case .repeat:
            NowPlayingControlButton(systemName: manager.repeatMode == .one ? "repeat.1" : "repeat", size: size,
                                    foreground: foreground, highlighted: manager.repeatMode.isOn) {
                manager.cycleRepeat()
            }
        case .copy:
            NowPlayingControlButton(systemName: manager.didCopyLink ? "checkmark" : "link", size: size,
                                    foreground: foreground) {
                manager.copyLink()
            }
        }
    }
}

struct NowPlayingControlButton: View {
    let systemName: String
    var size: CGFloat
    var foreground: Color = .white
    var highlighted = false
    let action: () -> Void

    init(systemName: String, size: CGFloat, foreground: Color = .white, highlighted: Bool = false,
         action: @escaping () -> Void) {
        self.systemName = systemName
        self.size = size
        self.foreground = foreground
        self.highlighted = highlighted
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(foreground)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: NowPlayingMetrics.Expanded.buttonHitSize.width,
                       height: NowPlayingMetrics.Expanded.buttonHitSize.height)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(highlighted ? 0.14 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(NowPlayingPressButtonStyle())
        .animation(Constants.Animations.standard, value: highlighted)
    }
}

/// Small press-down scale used by every media button.
struct NowPlayingPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(Constants.Animations.standard, value: configuration.isPressed)
    }
}

// MARK: - Volume row

/// speaker · 170 pt track · speaker.wave.3 (Part C2 §3.3), bound to the HUD
/// feature's `VolumeManager.shared`.
struct NowPlayingVolumeRow: View {
    var trackWidth: CGFloat? = NowPlayingMetrics.Expanded.volumeTrackWidth
    var foreground: Color = Color(white: 0.6)
    var fill: Color = .white
    var trackBackground: Color = NowPlayingMetrics.Palette.trackBackground

    @ObservedObject private var volume = VolumeManager.shared
    @State private var isDragging = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(foreground)
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let level = CGFloat(min(max(volume.volume, 0), 1))
                let height: CGFloat = isDragging ? 6 : 4
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous).fill(trackBackground)
                    Capsule(style: .continuous).fill(fill)
                        .frame(width: max(height, width * level))
                        .opacity(level > 0 ? 1 : 0)
                }
                .frame(height: height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging { withAnimation(Constants.Animations.standard) { isDragging = true } }
                            volume.setVolume(Float(min(max(value.location.x / width, 0), 1)))
                        }
                        .onEnded { value in
                            volume.setVolume(Float(min(max(value.location.x / width, 0), 1)))
                            withAnimation(Constants.Animations.standard) { isDragging = false }
                        }
                )
            }
            .frame(width: trackWidth)
            .frame(maxWidth: trackWidth == nil ? .infinity : nil)
            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(foreground)
        }
        .frame(maxWidth: .infinity)
    }
}
