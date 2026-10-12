import Foundation

/// Entry point of the Now Playing feature (called from `AppDelegate`).
///
/// Wires `NowPlayingManager` into `NotchController.shared`: the compact
/// `.nowPlaying` activity, the `.nowPlaying` expanded page, media Quick Peeks,
/// `mediaCommandHandler` for swipe-to-skip, and the `.sourceAppActive` hide
/// reason. Other features embed `NowPlayingDuoColumn` and
/// `NowPlayingLockWidget`.
enum NowPlayingModule {
    @MainActor
    static func start() {
        NowPlayingManager.shared.start()
        // Touch the shared hubs so permission state and device listeners are
        // ready before the first waveform appears.
        _ = NowPlayingSpectrumCenter.shared
        _ = NowPlayingFakeWaveformDriver.shared
    }
}
