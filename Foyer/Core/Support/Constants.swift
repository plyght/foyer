import SwiftUI

/// Every timing, size and threshold Foyer uses, taken from the Alcove 1.7.7
/// teardown (`alcove_teardown/ALCOVE_TEARDOWN.md`, section 7 "master sheet").
/// Where a STATIC constant and an OBSERVED measurement disagree, the STATIC
/// value wins, as the teardown recommends.
enum Constants {

    // MARK: Springs and curves (§7.1)
    enum Animations {
        /// Notch open (main morph). STATIC `Spring(duration: 0.5, bounce: 0.375)`.
        static let open = Animation.spring(duration: 0.5, bounce: 0.375)
        /// Notch close: content blurs out first, then the shape contracts with
        /// no visible overshoot (417-583 ms). STATIC candidate `(0.35, -0.2)`.
        static let close = Animation.spring(duration: 0.35, bounce: -0.2)
        /// Expanded content swap (media player). STATIC `Spring(duration: 0.3, bounce: 0.25)`.
        static let contentSwap = Animation.spring(duration: 0.3, bounce: 0.25)
        /// Media control strip. STATIC `Spring(duration: 0.35, bounce: 0.4).delay(0.1)`.
        static let controlStrip = Animation.spring(duration: 0.35, bounce: 0.4).delay(0.1)
        /// Live activity containers: appear/disappear 450 ms, no overshoot.
        static let liveActivity = Animation.spring(response: 0.5, dampingFraction: 1)
        static let liveActivityFast = Animation.spring(response: 0.3, dampingFraction: 1)
        /// Notifications container.
        static let notification = Animation.spring(response: 0.5, dampingFraction: 1)
        /// Global default (settings, lists, HUD content).
        static let standard = Animation.spring(response: 0.2, dampingFraction: 1)
        /// HUD / DummyNotch: opens in ~500 ms, dismisses in ~600 ms.
        static let hud = Animation.spring(response: 0.4875, dampingFraction: 1)
        static let hudOverdamped = Animation.spring(duration: 0.35, bounce: -0.2)
        /// Hover bump: ~117 ms in, ~267 ms out.
        static let hoverIn = Animation.spring(response: 0.2, dampingFraction: 1)
        static let hoverOut = Animation.spring(response: 0.3, dampingFraction: 1)
        /// Bouncy variants found in the binary.
        static let bouncy = Animation.spring(duration: 0.4, bounce: 0.35)
        static let quickPeekOpen = Animation.spring(duration: 0.4, bounce: 0.35)
        /// Small fades.
        static let fadeFast = Animation.easeOut(duration: 0.1)
        static let fade = Animation.easeOut(duration: 0.15)
        static let pauseFade = Animation.easeOut(duration: 0.25)
        static let easeInOut = Animation.easeInOut(duration: 0.2)
        /// Shimmer loop.
        static let shimmer = Animation.linear(duration: 1.5).delay(0.25).repeatForever(autoreverses: false)
        /// Content fade-in lags the shape by ~100 ms.
        static let contentDelay: Double = 0.1
        /// Content blurs/fades out ~200 ms before the shape contracts.
        static let contentOutDuration: Double = 0.2
        /// Artwork 3D flip, total 300 ms (150 ms per half).
        static let artworkFlipHalf: Double = 0.15
    }

    // MARK: Durations and holds (§7.2)
    enum Durations {
        static let hover: Double = 0
        static let idle: Double = 3
        static let peek: Double = 2
        static let calendarPeek: Double = 4
        static let battery: Double = 5
        static let connectivity: Double = 5
        static let focus: Double = 5
        static let brightness: Double = 1.5
        static let volume: Double = 1.5
        static let hideIdleMinutes: Double = 10
        static let timeBeforeEventMinutes: Double = 15
        static let timeToLeaveMinutes: Double = 8
        static let timeToLeaveBufferMinutes: Double = 10
        /// HUD appear choreography per speed (Smooth / Fast / Instant).
        static let hudChoreographySmooth: Double = 0.93
        static let hudChoreographyFast: Double = 0.8
        static let hudChoreographyInstant: Double = 0.667
        /// Cycle activity: old fades out 117 ms, empty 467 ms, new fades in 200 ms.
        static let cycleFadeOut: Double = 0.117
        static let cycleEmpty: Double = 0.467
        static let cycleFadeIn: Double = 0.2
        /// Track-skip glyph flash.
        static let skipGlyph: Double = 0.4
        /// Debounces recovered as `Duration.seconds` literals.
        static let swipeReset: Double = 0.5
        static let notificationSwap: Double = 0.275
        static let quickPeekReset: Double = 0.475
    }

    // MARK: Geometry (§7.3, Part E)
    enum Geometry {
        /// The two host panels are fixed 624x320, top-centred, never resized.
        static let panelSize = CGSize(width: 624, height: 320)
        /// Simulated notch (no hardware notch, "Force simulated notch" on).
        static let simulatedWidth: CGFloat = 140
        static let simulatedHeightFallback: CGFloat = 24
        /// Compact fallback (no notch, simulation off): floating capsule.
        static let compactFallbackWidth: CGFloat = 74
        static let compactFallbackHeightFallback: CGFloat = 19.5
        static let compactFallbackExpandedWidth: CGFloat = 321
        /// Floating capsule sits ~4 pt below the top edge.
        static let pillTopInset: CGFloat = 4
        /// Base expanded size: max(W + 160, 345) x max(H + 142, 175).
        static let expandedExtraWidth: CGFloat = 160
        static let expandedMinWidth: CGFloat = 345
        static let expandedExtraHeight: CGFloat = 142
        static let expandedMinHeight: CGFloat = 175
        /// The settled expanded body measures 362 at its centre row against a
        /// 345 base (OBSERVED, Parts C/D).
        static let expandedBodyExtra: CGFloat = 17
        /// Expanded media player is shorter than the calendar page.
        static let mediaExpandedHeight: CGFloat = 120
        /// Compact live activity: notch + two wings. Calendar 216, Now Playing 216-222.
        static let activityWing: CGFloat = 38
        static let nowPlayingWing: CGFloat = 41
        /// Sound/Display HUD: 326-332 wide.
        static let hudWing: CGFloat = 95
        /// Quick Peek capsule 233x70.
        static let peekExtraWidth: CGFloat = 93
        static let peekHeight: CGFloat = 70
        /// Hover bump: width x1.086 (140→152, 216→234), height +5.
        static let hoverWidthScale: CGFloat = 1.086
        static let hoverExtraHeight: CGFloat = 5
        /// Rubber band while dragging toward open: +0.3 pt/pt wide, +0.22 pt/pt tall.
        static let rubberBandWidth: CGFloat = 0.3
        static let rubberBandHeight: CGFloat = 0.22
        /// NotchShape radii. Bottom radius is clamped to ≤ 24 (continuous curve,
        /// which reads as ~32-34 px on screen when expanded).
        static let maxCornerRadius: CGFloat = 24
        static let closedTopRadius: CGFloat = 6
        static let closedBottomRadius: CGFloat = 8
        static let peekTopRadius: CGFloat = 8
        static let peekBottomRadius: CGFloat = 10
        static let expandedTopRadius: CGFloat = 13
        static let expandedBottomRadius: CGFloat = 24
        /// Duo (split) page.
        static let duoWidth: CGFloat = 580
        /// Contrast outline: ~1.5 px, white at ~9 % alpha.
        static let outlineWidth: CGFloat = 1.5
        static let outlineOpacity: Double = 0.09
    }

    // MARK: Gesture thresholds (§7.4, Part I), in scroll points
    enum Swipes {
        static let verticalSuccess: CGFloat = 35
        static let verticalReset: CGFloat = 15
        static let cycleActivitySuccess: CGFloat = 35
        static let cycleActivityReset: CGFloat = 15
        static let horizontalSuccess: CGFloat = 70
        static let horizontalReset: CGFloat = 15
        /// Inside the expanded panel.
        static let expandedCloseSuccess: CGFloat = 105
        static let expandedPageSuccess: CGFloat = 75
        static let expandedHorizontalSuccess: CGFloat = 35
    }

    // MARK: Waveform (§7.5, Part F)
    enum Waveform {
        static let fakeBarCount = 5
        static let liveBandCount = 6
        static let barWidth: CGFloat = 2
        static let barPitch: CGFloat = 4
        static let compactMaxHeight: CGFloat = 12
        static let expandedBarWidth: CGFloat = 3
        static let expandedBarPitch: CGFloat = 5
        static let expandedMaxHeight: CGFloat = 20
        static let minBarHeight: CGFloat = 2
        static let fakeRetargetHz: Double = 17
        static let liveRefreshHz: Double = 20
        static let barTween: Double = 0.08
        static let liveBandEdges: [Double] = [20, 81, 170, 527, 1500, 4500, 10000]
    }

    // MARK: Marquee
    enum Marquee {
        static let fade: Double = 0.1
        static let speed: CGFloat = 30
        static let pause: Double = 1.25
        static let gap: CGFloat = 24
    }

    // MARK: Battery
    enum Battery {
        static let charging = Color(red: 0x8D / 255, green: 0xEB / 255, blue: 0x92 / 255)
        static let low = Color(red: 0xFA / 255, green: 0x63 / 255, blue: 0x75 / 255)
        static let lowPower = Color(red: 1.0, green: 0.8, blue: 0.2)
    }

    // MARK: Settings window (Part D §5.2)
    enum SettingsWindow {
        static let size = CGSize(width: 620, height: 687)
        static let sidebarButton = CGSize(width: 200, height: 38)
        static let rowPitch: CGFloat = 42
        static let toggleSize = CGSize(width: 44, height: 20)
        static let segmentedCard = CGSize(width: 76, height: 50)
        static let segmentedPitch: CGFloat = 88
        /// Accent (Alcove's teal 45,212,191). Foyer uses its own accent.
        static let accent = Color(red: 0.36, green: 0.62, blue: 1.0)
    }

    /// Repository used for update checks.
    static let updateRepository = "plyght/foyer"
}
