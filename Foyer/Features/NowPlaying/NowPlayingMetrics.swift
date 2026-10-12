import SwiftUI

/// Now Playing measurements that are not in `Constants` (teardown Part C §1,
/// Part C2 §2–§4, Part H.3, v3 live pass).
enum NowPlayingMetrics {

    // MARK: Compact activity (Part C §1)
    enum Compact {
        /// Square artwork in the left wing, ~22x22 with ~5 pt corners.
        static let artworkSize: CGFloat = 22
        static let artworkCornerRadius: CGFloat = 5
        /// Distance of the artwork from the outer edge of the left wing.
        static let artworkInset: CGFloat = 7
        /// The 5-bar group is right-aligned ~10 pt from the panel edge.
        static let waveformInset: CGFloat = 10
        /// Focus glyph that replaces the waveform during a matching Focus.
        static let focusGlyphSize: CGFloat = 12
    }

    // MARK: Expanded player, 362x120 (Part C §1, Part C2 §3.2)
    enum Expanded {
        static let height: CGFloat = Constants.Geometry.mediaExpandedHeight
        /// Height while the output/volume row is open (Part C2 §3.3: ≈150).
        static let heightWithVolumeRow: CGFloat = 150
        static let artworkSize: CGFloat = 56
        static let artworkCornerRadius: CGFloat = 10
        static let inset: CGFloat = 14
        static let titleSize: CGFloat = 13
        static let artistSize: CGFloat = 11
        static let timeSize: CGFloat = 10
        static let trackHeight: CGFloat = 4
        static let trackHeightActive: CGFloat = 6
        static let controlSize: CGFloat = 15
        static let playPauseSize: CGFloat = 21
        static let buttonHitSize = CGSize(width: 36, height: 28)
        static let volumeTrackWidth: CGFloat = 170
    }

    // MARK: Quick Peek, 233x70 two-row capsule (Part C2 §4.2)
    enum Peek {
        static let textSize: CGFloat = 11
    }

    // MARK: Explicit badge (Part H.3, Part I §1.2)
    enum Badge {
        /// ~11x11 px including anti-aliasing (9x9 solid core).
        static let glyphSize: CGFloat = 10
        /// 5-6 px after the title in the expanded player, 4 px on the lock screen.
        static let spacing: CGFloat = 5
        static let lockSpacing: CGFloat = 4
        /// #747478 in the dark expanded panel.
        static let color = Color(red: 116 / 255, green: 116 / 255, blue: 120 / 255)
    }

    // MARK: Colours (Part C2 §2.1)
    enum Palette {
        /// Unfilled scrubber (26,26,28).
        static let trackBackground = Color(red: 26 / 255, green: 26 / 255, blue: 28 / 255)
        /// Monochrome scrubber fill.
        static let monoFill = Color(white: 0.78)
        /// Secondary label grey (110,110,112).
        static let secondaryText = Color(red: 110 / 255, green: 110 / 255, blue: 112 / 255)
        static let waveformFallback = Color(white: 0.75)
        static let placeholderBackground = Color(white: 0.16)
    }

    // MARK: Lock-screen widget content (v3 live pass: ~360x185 card; the
    // card chrome itself comes from the LockScreen feature)
    enum Lock {
        static let padding: CGFloat = 16
        static let artworkSize: CGFloat = 52
        static let artworkCornerRadius: CGFloat = 10
    }

    // MARK: Live waveform (Part F §1, v3 live pass)
    enum Live {
        /// The compact glyph uses the 5-band variant (drops the 81 Hz edge).
        static let compactBandCount = 5
        static let fftSize = 2048
        /// dB window mapped to 0…1 (a −34…−28 dBFS tone pins the bar).
        static let floorDB: Float = -72
        static let ceilingDB: Float = -30
        /// Keep the tap alive this long after playback pauses.
        static let teardownGrace: Double = 2
    }

    // MARK: Behaviour
    /// AppleScript polling while Music/Spotify is the fallback source.
    static let scriptPollPlaying: Double = 1
    static let scriptPollPaused: Double = 2.5
    /// Helper liveness check before falling back to in-process MediaRemote.
    static let helperTimeout: Double = 2.5
    /// Artwork is decoded at most this size (points × 2 for Retina).
    static let artworkMaxPixel: CGFloat = 600
}
