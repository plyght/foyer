import Combine
import Defaults
import SwiftUI

/// Drives the synthetic waveform (Part C §2.8, §7.5): five bars that pick a
/// new random-walk target ~17 times a second while something plays. Shared by
/// every fake waveform on screen; it only ticks while a view owns it.
@MainActor
final class NowPlayingFakeWaveformDriver: ObservableObject {
    static let shared = NowPlayingFakeWaveformDriver()

    /// 0…1 per bar.
    @Published private(set) var levels: [CGFloat]

    private var owners = Set<UUID>()
    private var timer: AnyCancellable?
    private var playingObserver: AnyCancellable?
    private var velocities: [CGFloat]

    private init() {
        let count = Constants.Waveform.fakeBarCount
        levels = (0..<count).map { _ in CGFloat.random(in: 0.2...0.8) }
        velocities = Array(repeating: 0, count: count)
    }

    func acquire(_ owner: UUID) {
        owners.insert(owner)
        if playingObserver == nil {
            // @Published emits before the value is stored; hop once so the
            // timer sees the new state.
            playingObserver = NowPlayingManager.shared.$isPlaying
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.updateTimer() }
        }
        updateTimer()
    }

    func release(_ owner: UUID) {
        owners.remove(owner)
        updateTimer()
    }

    private func updateTimer() {
        let shouldRun = !owners.isEmpty && NowPlayingManager.shared.isPlaying
        if shouldRun, timer == nil {
            timer = Timer.publish(every: 1 / Constants.Waveform.fakeRetargetHz, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in self?.step() }
        } else if !shouldRun, timer != nil {
            // Freeze on pause: the bars keep their last heights and fade with the content.
            timer?.cancel()
            timer = nil
        }
    }

    /// Independent per-bar random walk with a little momentum, bouncing off
    /// the ends, plus occasional jumps so it never looks periodic.
    private func step() {
        var next = levels
        for index in next.indices {
            var velocity = velocities[index] * 0.55 + CGFloat.random(in: -0.32...0.32)
            if CGFloat.random(in: 0...1) < 0.08 {
                velocity = CGFloat.random(in: -0.6...0.6)
            }
            var value = next[index] + velocity
            if value > 1 { value = 2 - value; velocity = -abs(velocity) }
            if value < 0 { value = -value; velocity = abs(velocity) }
            next[index] = min(max(value, 0), 1)
            velocities[index] = velocity
        }
        levels = next
    }
}

/// Bar geometry for each place a waveform appears.
struct NowPlayingWaveformStyle: Equatable {
    var barWidth: CGFloat
    var pitch: CGFloat
    var maxHeight: CGFloat
    /// Live band count (5 in the compact glyph, 6 elsewhere).
    var liveBands: Int

    /// 2 pt bars, 4 pt pitch, 2–12 pt tall.
    static let compact = NowPlayingWaveformStyle(barWidth: Constants.Waveform.barWidth,
                                                 pitch: Constants.Waveform.barPitch,
                                                 maxHeight: Constants.Waveform.compactMaxHeight,
                                                 liveBands: NowPlayingMetrics.Live.compactBandCount)
    /// 3 pt bars, 5 pt pitch, up to 20 pt.
    static let expanded = NowPlayingWaveformStyle(barWidth: Constants.Waveform.expandedBarWidth,
                                                  pitch: Constants.Waveform.expandedBarPitch,
                                                  maxHeight: Constants.Waveform.expandedMaxHeight,
                                                  liveBands: Constants.Waveform.liveBandCount)
}

/// The Now Playing waveform glyph: live (process tap) when "Use live
/// waveform" is on and capture works, synthetic otherwise.
struct NowPlayingWaveformView: View {
    var style: NowPlayingWaveformStyle = .compact
    var tint: Color

    @Default(.useLiveWaveform) private var useLiveWaveform
    @ObservedObject private var spectrum = NowPlayingSpectrumCenter.shared
    @State private var owner = UUID()

    var body: some View {
        // A ZStack (not a Group) so appear/disappear track the container,
        // not each branch, and ownership survives fake ⇄ live switches.
        ZStack {
            if useLiveWaveform && spectrum.isLive {
                NowPlayingLiveBars(style: style, tint: tint)
            } else {
                NowPlayingFakeBars(style: style, tint: tint)
            }
        }
        .onAppear { spectrum.acquire(owner) }
        .onDisappear { spectrum.release(owner) }
    }
}

/// Bars drawn vertically centred, 0.08 s ease-out tween per update.
private struct NowPlayingBars: View {
    let heights: [CGFloat]
    let style: NowPlayingWaveformStyle
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: style.pitch - style.barWidth) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(tint)
                    .frame(width: style.barWidth, height: heights[index])
            }
        }
        .frame(height: style.maxHeight)
        .animation(.easeOut(duration: Constants.Waveform.barTween), value: heights)
    }
}

private struct NowPlayingFakeBars: View {
    let style: NowPlayingWaveformStyle
    let tint: Color

    @ObservedObject private var driver = NowPlayingFakeWaveformDriver.shared
    @State private var owner = UUID()

    var body: some View {
        let minHeight = Constants.Waveform.minBarHeight
        let heights = driver.levels.map { level -> CGFloat in
            (minHeight + level * (style.maxHeight - minHeight)).rounded()
        }
        NowPlayingBars(heights: heights, style: style, tint: tint)
            .onAppear { driver.acquire(owner) }
            .onDisappear { driver.release(owner) }
    }
}

private struct NowPlayingLiveBars: View {
    let style: NowPlayingWaveformStyle
    let tint: Color

    @ObservedObject private var spectrum = NowPlayingSpectrumCenter.shared

    var body: some View {
        let levels = style.liveBands <= NowPlayingMetrics.Live.compactBandCount ? spectrum.compactLevels : spectrum.levels
        // h = clamp(maxHeight × level, 2 pt, maxHeight), pixel-rounded (Part F §1).
        let heights = levels.map { level -> CGFloat in
            min(max(style.maxHeight * level, Constants.Waveform.minBarHeight), style.maxHeight).rounded()
        }
        NowPlayingBars(heights: heights, style: style, tint: tint)
    }
}

/// Trailing glyph of the compact activity: the waveform, or the active Focus
/// symbol when "Replace waveform during focus" matches the current Focus.
struct NowPlayingCompactTrailingGlyph: View {
    var style: NowPlayingWaveformStyle = .compact

    @ObservedObject private var manager = NowPlayingManager.shared
    @ObservedObject private var focus = FocusManager.shared
    @Default(.replaceWaveformDuringFocus) private var replaceDuringFocus
    @Default(.replaceWaveformDuringFocusModeIdentifier) private var replaceFocusIdentifier

    var body: some View {
        if let mode = matchingFocus {
            Image(systemName: mode.symbolName)
                .font(.system(size: NowPlayingMetrics.Compact.focusGlyphSize, weight: .semibold))
                .foregroundStyle(mode.tint)
                .transition(.opacity)
        } else {
            NowPlayingWaveformView(style: style, tint: manager.palette.waveformColor)
                .transition(.opacity)
        }
    }

    private var matchingFocus: FocusMode? {
        guard replaceDuringFocus, let current = focus.currentFocus else { return nil }
        if let wanted = replaceFocusIdentifier, !wanted.isEmpty, wanted != current.identifier { return nil }
        return current
    }
}
