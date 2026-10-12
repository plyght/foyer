import AppKit

/// Visual effects: the progressive blur band (`ProgressiveBlurBand`, drawn
/// by the core backdrop view) and the contrast-outline luminance sampling
/// that drives `NotchController.shared.backdropIsDark`.
enum VisualsModule {
    @MainActor
    static func start() {
        VisualsLuminanceSampler.shared.start()
    }

    @MainActor
    static func stop() {
        VisualsLuminanceSampler.shared.stop()
    }
}
