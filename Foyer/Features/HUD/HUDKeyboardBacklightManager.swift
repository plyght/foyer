import AppKit
import Combine
import Foundation

// CoreBrightness `KeyboardBrightnessClient` method shapes, called through
// their IMPs so float/UInt64 arguments are passed correctly.
private typealias HUDKBCopyIDs = @convention(c) (AnyObject, Selector) -> Unmanaged<NSArray>?
private typealias HUDKBBrightnessForKeyboard = @convention(c) (AnyObject, Selector, UInt64) -> Float
private typealias HUDKBSetBrightness = @convention(c) (AnyObject, Selector, Float, UInt64) -> ObjCBool

/// Keyboard backlight via the private `KeyboardBrightnessClient`
/// (CoreBrightness), best effort. Keys 21/22 (illumination up/down) are only
/// swallowed when the client resolves and reports a backlit keyboard;
/// otherwise they pass through to macOS (Part E §6: the exact Alcove
/// actuator is UNVERIFIED).
@MainActor
final class HUDKeyboardBacklightManager: ObservableObject {
    static let shared = HUDKeyboardBacklightManager()

    @Published private(set) var level: Float = 0

    private var client: NSObject?
    private var keyboardID: UInt64 = 1
    private var resolved = false

    private init() {}

    var isAvailable: Bool {
        resolveIfNeeded()
        return client != nil
    }

    /// Applies one key step (1/16, 1/64 fine). Returns false when the
    /// backlight cannot be driven.
    @discardableResult
    func step(up: Bool, fine: Bool) -> Bool {
        resolveIfNeeded()
        guard let client else { return false }
        let step = HUDConstants.normalStep * (fine ? HUDConstants.fineStepScale : 1)
        let current = readLevel(client) ?? level
        let index = (current / step).rounded()
        let target = min(max((index + (up ? 1 : -1)) * step, 0), 1)
        guard writeLevel(client, target) else { return false }
        level = target
        return true
    }

    func refresh() {
        resolveIfNeeded()
        guard let client, let value = readLevel(client) else { return }
        level = value
    }

    // MARK: Private

    private func resolveIfNeeded() {
        guard !resolved else { return }
        resolved = true
        guard PrivateAPI.handle(PrivateAPI.coreBrightness) != nil,
              let cls = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return }
        let instance = cls.init()

        let brightnessSel = NSSelectorFromString("brightnessForKeyboard:")
        let setSel = NSSelectorFromString("setBrightness:forKeyboard:")
        guard instance.responds(to: brightnessSel), instance.responds(to: setSel) else { return }

        let idsSel = NSSelectorFromString("copyKeyboardBacklightIDs")
        if instance.responds(to: idsSel), let imp = instance.method(for: idsSel) {
            let copyIDs = unsafeBitCast(imp, to: HUDKBCopyIDs.self)
            if let ids = copyIDs(instance, idsSel)?.takeRetainedValue() as? [NSNumber] {
                guard let first = ids.first else { return } // no backlit keyboard
                keyboardID = first.uint64Value
            }
        }

        client = instance
        if let value = readLevel(instance) { level = value }
    }

    private func readLevel(_ client: NSObject) -> Float? {
        let sel = NSSelectorFromString("brightnessForKeyboard:")
        guard let imp = client.method(for: sel) else { return nil }
        let fn = unsafeBitCast(imp, to: HUDKBBrightnessForKeyboard.self)
        let value = fn(client, sel, keyboardID)
        guard value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }

    private func writeLevel(_ client: NSObject, _ value: Float) -> Bool {
        let sel = NSSelectorFromString("setBrightness:forKeyboard:")
        guard let imp = client.method(for: sel) else { return false }
        let fn = unsafeBitCast(imp, to: HUDKBSetBrightness.self)
        return fn(client, sel, value, keyboardID).boolValue
    }
}
