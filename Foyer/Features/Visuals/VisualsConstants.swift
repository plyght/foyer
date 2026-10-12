import SwiftUI

/// Constants of the visual-effects feature (progressive blur and the contrast
/// outline's luminance sampling). Teardown: Part D §6 "Contrast outline &
/// Progressive blur", Part A §6 "Blur", lead notes §2.
enum VisualsConstants {

    // MARK: Contrast outline luminance

    /// The outline appeared only in captures taken ≥ 20 s after a wallpaper
    /// change; captures 2-12 s after showed nothing (Part D §6, OBSERVED), so
    /// the backdrop is re-sampled on a ~20 s cadence.
    static let luminanceResampleInterval: Double = 20
    /// Region sampled around the island, centred on the top edge of the
    /// screen (points). Wide enough to cover the expanded compact activity
    /// (216-332 pt) plus the outline's surroundings.
    static let sampleSize = CGSize(width: 360, height: 44)
    /// Downsampled bitmap used to average the sampled region.
    static let sampleBitmapWidth = 36
    static let sampleBitmapHeight = 6
    /// Hysteresis around mid-grey (Rec. 709 luma, 0…1). Black (0) shows the
    /// outline, silver 231/255 (0.906) hides it (Part D §6, OBSERVED).
    static let darkThreshold: Double = 0.45
    static let lightThreshold: Double = 0.55
    /// Rec. 709 luma weights (same weights as Alcove's `brightenDarkPixels` kernel).
    static let lumaRed: Double = 0.2126
    static let lumaGreen: Double = 0.7152
    static let lumaBlue: Double = 0.0722
    /// Wallpaper thumbnails are decoded at most this large (pixels, longest side).
    static let wallpaperThumbnailMaxPixels = 1024
    /// Outline fade when the sampled backdrop flips between dark and light.
    static let outlineFade = Animation.easeOut(duration: 0.25)

    // MARK: Progressive blur

    /// Maximum blur radius at the top edge of the band. The teardown recovers
    /// `ProgressiveBlurEffect.maxBlurRadius` but not its value (UNVERIFIED);
    /// 18 pt reads like the system's own menu-bar material.
    static let progressiveBlurMaxRadius: CGFloat = 18
    /// Opacity / blur ramp from the top edge (location 0) to the bottom (1).
    static let progressiveBlurStops: [(location: CGFloat, strength: CGFloat)] = [
        (0.00, 1.00),
        (0.30, 0.85),
        (0.60, 0.45),
        (0.85, 0.12),
        (1.00, 0.00),
    ]
    /// Horizontal feather at the left and right ends of the band, as a
    /// fraction of its width, so it never ends in a hard vertical edge.
    static let progressiveBlurSideFeather: CGFloat = 0.12
}
