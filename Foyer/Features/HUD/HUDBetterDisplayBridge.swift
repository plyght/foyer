import AppKit
import Defaults
import Foundation

/// One decoded BetterDisplay OSD payload (fields from Part E §6:
/// systemIconID, value, maxValue, displayID/displayId/targetDisplayID).
struct HUDBetterDisplayOSD: Sendable {
    var systemIconID: Int?
    var value: Double
    var maxValue: Double
    var displayID: UInt32?

    /// OSDUIHelper icon ids: 1 is brightness; 3/4 (volume/mute) and the
    /// others are not mirrored. A missing id is treated as brightness, which
    /// is what BetterDisplay drives for external screens.
    var isBrightness: Bool {
        guard let id = systemIconID else { return true }
        return id == 1
    }

    var level: Double {
        guard maxValue > 0 else { return min(max(value, 0), 1) }
        return min(max(value / maxValue, 0), 1)
    }

    static func decode(_ notification: Notification) -> HUDBetterDisplayOSD? {
        var dict: [String: Any] = [:]
        if let string = notification.object as? String,
           let data = string.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            dict = json
        }
        if let info = notification.userInfo {
            for (key, value) in info {
                if let key = key as? String { dict[key] = value }
            }
        }
        guard let value = number(dict["value"]) else { return nil }
        let maxValue = number(dict["maxValue"]) ?? 1
        let icon = number(dict["systemIconID"]).flatMap { $0.isFinite && abs($0) < 1_000_000 ? Int($0) : nil }
        let display = number(dict["displayID"]) ?? number(dict["displayId"]) ?? number(dict["targetDisplayID"])
        return HUDBetterDisplayOSD(systemIconID: icon,
                                   value: value,
                                   maxValue: maxValue,
                                   displayID: display.flatMap(displayIdentifier))
    }

    private static func displayIdentifier(_ value: Double) -> UInt32? {
        guard value.isFinite, value >= 0, value <= Double(UInt32.max) else { return nil }
        return UInt32(value)
    }

    private static func number(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }
}

/// Mirrors BetterDisplay's external-display brightness OSD into Foyer's
/// Display HUD (Alcove subscribes to `com.betterdisplay.BetterDisplay.osd`,
/// Part E §6). Brightness keys Foyer cannot drive pass through the event
/// tap, BetterDisplay handles them and reports the result here.
@MainActor
final class HUDBetterDisplayBridge {
    static let shared = HUDBetterDisplayBridge()

    private static let osdNotification = Notification.Name("com.betterdisplay.BetterDisplay.osd")

    private var observer: NSObjectProtocol?
    private var lastHaptic: Date = .distantPast

    private init() {}

    func start() {
        guard observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.osdNotification, object: nil, queue: .main
        ) { notification in
            guard let osd = HUDBetterDisplayOSD.decode(notification) else { return }
            MainActor.assumeIsolated {
                HUDBetterDisplayBridge.shared.handle(osd)
            }
        }
    }

    func stop() {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observer = nil
    }

    private func handle(_ osd: HUDBetterDisplayOSD) {
        guard osd.isBrightness, Defaults[.enableBrightness] else { return }
        let controller = NotchController.shared
        if Defaults[.hideWhileGaming], controller.hideReasons.contains(.gaming) { return }

        let isExternal: Bool
        if let id = osd.displayID, id != 0 {
            isExternal = CGDisplayIsBuiltin(id) == 0
        } else {
            isExternal = true
        }
        HUDBrightnessManager.shared.applyExternalLevel(Float(osd.level), isExternal: isExternal)

        let now = Date()
        if now.timeIntervalSince(lastHaptic) > HUDConstants.betterDisplayDebounce {
            Haptics.perform(.levelChange)
        }
        lastHaptic = now
        HUDPresenter.present(.brightness)
    }
}
