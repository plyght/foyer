import Defaults
import SwiftUI

/// HUDs and system keys: event-tap OSD suppression, volume (CoreAudio),
/// brightness (DisplayServices), keyboard backlight, BetterDisplay OSD
/// bridge, and the Sound / Display HUD views.
enum HUDModule {
    @MainActor
    static func start() {
        VolumeManager.shared.start()
        HUDBrightnessManager.shared.start()
        HUDBetterDisplayBridge.shared.start()
        HUDKeyInterceptor.shared.start()
        HUDPassiveObserver.shared.start()
    }

    @MainActor
    static func stop() {
        HUDKeyInterceptor.shared.stop()
        HUDBetterDisplayBridge.shared.stop()
        HUDBrightnessManager.shared.stop()
        VolumeManager.shared.stop()
    }
}

/// Posts or extends the HUD notification. Views observe their managers, so a
/// repeated key only re-arms the timer (the HUD is dismissed `duration`
/// seconds after the last press, Part C §3.1).
@MainActor
enum HUDPresenter {
    static func present(_ source: HUDLevelSource) {
        let controller = NotchController.shared
        let duration: Double
        let speed: HUDSpeed
        switch source {
        case .volume:
            duration = Defaults[.volumeDuration]
            speed = Defaults[.volumeSpeed]
        case .brightness, .keyboardBacklight:
            duration = Defaults[.brightnessDuration]
            speed = Defaults[.brightnessSpeed]
        }

        let kind = source.notificationKind
        if let current = controller.notification, current.kind == kind {
            controller.extendNotification(kind, duration: duration)
            return
        }

        controller.post(NotchNotification(
            kind: kind,
            category: source.category,
            wingWidth: Constants.Geometry.hudWing,
            duration: duration + HUDConstants.firstPresentationExtraHold,
            animation: HUDConstants.presentationAnimation(speed),
            leading: AnyView(HUDLeadingView(source: source)),
            trailing: AnyView(HUDTrailingView(source: source))))
    }
}
