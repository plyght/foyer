import SwiftUI

/// Measurements and timings specific to the Sound / Display HUDs.
/// Sources: teardown Part C §3.1, Part C2 §1.3-1.6, Part E §5-6, Part F §4,
/// master sheet §7.2.
enum HUDConstants {

    // MARK: Steps (Part E §6 key matrix, Part F §4)

    /// One key press = 1/16 of the range.
    static let normalStep: Float = 1.0 / 16.0
    /// Shift+Option scales the step by 0.25 → 1/64.
    static let fineStepScale: Float = 0.25
    /// Modifier mask that selects the fine step: `(flags & 0xa0000) == 0xa0000`.
    static let fineModifierMask: UInt64 = 0xa0000

    // MARK: Event tap (Part E §6)

    /// `NX_SYSDEFINED` CGEvent type.
    static let systemDefinedEventType: UInt32 = 14
    /// NSEvent subtype for auxiliary-control (media) buttons.
    static let mediaKeySubtype: Int16 = 8
    /// Key-state byte for down / up in `data1`.
    static let keyStateDown = 0x0A
    static let keyStateUp = 0x0B

    /// `NX_KEYTYPE_*` values.
    static let keySoundUp = 0
    static let keySoundDown = 1
    static let keyBrightnessUp = 2
    static let keyBrightnessDown = 3
    static let keyMute = 7
    static let keyIlluminationUp = 21
    static let keyIlluminationDown = 22

    /// CGEventFlags bits.
    static let flagShift: UInt64 = 0x20000
    static let flagControl: UInt64 = 0x40000
    static let flagOption: UInt64 = 0x80000
    static let flagCommand: UInt64 = 0x100000

    /// Accessibility trust is re-checked so granting it in System Settings
    /// enables the HUD without a relaunch (OBSERVED "within ~10 s", Part B §6).
    static let accessibilityPollInterval: Double = 2

    /// System Settings panes opened by Option + key (Part E §6, 0x10013b070/90).
    static let soundPreferencesURL = "x-apple.systempreferences:com.apple.preference.sound"
    static let displayPreferencesURL = "x-apple.systempreferences:com.apple.preference.displays"

    /// macOS "Play feedback when volume is changed" (read by Alcove at 0x100021f7c).
    static let volumeFeedbackDefaultsKey = "com.apple.sound.beep.feedback"

    // MARK: Brightness (Part E §5)

    /// Hardware increment is preferred; fallback is 1/16 (0x3d800000).
    static let fallbackBrightnessIncrement: Float = 0.0625
    /// Hardware callbacks that arrive this soon after a key write are ignored
    /// so they do not fight the optimistic local target (Task.sleep literal
    /// 0.5 s, §7.2; the exact Alcove interval is UNVERIFIED).
    static let brightnessCallbackSuppression: Double = 0.5
    /// BetterDisplay OSD debounce constant found next to its observers.
    static let betterDisplayDebounce: Double = 0.075

    // MARK: Layout (Part C §3.1, Part C2 §1.3 / §1.6, montage at 3x)

    /// Full bar track ≈ 73 px (length = 73 × level).
    static let barLength: CGFloat = 73
    /// Bar is ~4 px tall, rounded.
    static let barHeight: CGFloat = 4
    /// With "Show percentage" the bar is shortened to ~43 px and the value
    /// ("56", no % sign) sits right of it.
    static let barLengthWithPercentage: CGFloat = 43
    static let percentageGap: CGFloat = 8
    static let percentageWidth: CGFloat = 22
    /// Glyph sits ~12 px from the HUD edge; the wing already carries the
    /// shape's 6 px top-corner padding.
    static let leadingInset: CGFloat = 6
    /// Bar ends ~11 px from the HUD edge.
    static let trailingInset: CGFloat = 5
    static let glyphFrame: CGFloat = 16
    static let glyphSize: CGFloat = 13
    /// Label starts ~33 px from the HUD edge.
    static let labelSpacing: CGFloat = 5
    /// "Sound" label: SF rounded ~12 pt, white.
    static let labelFontSize: CGFloat = 12
    static let percentageFontSize: CGFloat = 12

    // MARK: Colours (Part C2 §1.6; palette from Assets.car, Part F §5)

    /// White style fill (≈ 200-235/255 grey) and unfilled track.
    static let whiteFill = Color(white: 0.92)
    static let unfilledTrack = Color.white.opacity(0.22)
    static let emerald = Color(red: 0x10 / 255, green: 0xB9 / 255, blue: 0x81 / 255)
    static let amber = Color(red: 0xF5 / 255, green: 0x9E / 255, blue: 0x0B / 255)
    static let rose = Color(red: 0xF4 / 255, green: 0x3F / 255, blue: 0x5E / 255)
    static let glowRadius: CGFloat = 4

    // MARK: Timing (Part C2 §1.4 / §1.5, §7.2)

    /// Bar-fill tween per speed (83 / 100 / 67 ms OBSERVED). The speed has no
    /// meaningful effect on the fill; each press retargets the running tween.
    static func fillTween(_ speed: HUDSpeed) -> Double {
        switch speed {
        case .smooth: return 0.083
        case .fast: return 0.1
        case .instant: return 0.067
        }
    }

    /// What Speed does change: the HUD open/close choreography (≈ 930 / 800 /
    /// 667 ms appear). Fast is the measured `Constants.Animations.hud` spring;
    /// Smooth and Instant scale its response by the measured ratios.
    static func presentationAnimation(_ speed: HUDSpeed) -> Animation {
        let D = Constants.Durations.self
        switch speed {
        case .fast:
            return Constants.Animations.hud
        case .smooth:
            let scale = D.hudChoreographySmooth / D.hudChoreographyFast
            return .spring(response: 0.4875 * scale, dampingFraction: 1)
        case .instant:
            let scale = D.hudChoreographyInstant / D.hudChoreographyFast
            return .spring(response: 0.4875 * scale, dampingFraction: 1)
        }
    }

    /// The duration is counted from when the HUD has finished opening
    /// (1.5 s + ~0.27 s OBSERVED for a single press); later presses restart
    /// the plain duration.
    static let firstPresentationExtraHold: Double = 0.27
}
