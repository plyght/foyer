import AppKit
import Carbon.HIToolbox
import Defaults

/// Replaces the system volume / brightness OSD **without Accessibility**.
///
/// `hidutil` remaps the media keys at the HID layer to spare function keys
/// (F13–F19) for the current login session; that needs no root and no TCC
/// permission. Carbon global hot keys (also permission-free) catch those
/// spare keys and Foyer applies the change and draws its own HUD. macOS never
/// receives a volume or brightness key, so it never shows its OSD.
///
/// Used whenever the Accessibility event tap isn't active. The user's own
/// `UserKeyMapping` entries are kept, and the original mapping is restored on
/// quit, or on the next launch after a crash.
@MainActor
final class HUDKeyRemapper: ObservableObject {
    static let shared = HUDKeyRemapper()

    @Published private(set) var isActive = false

    /// One remapped key: HID source usage, spare-key destination usage, the
    /// Carbon virtual key code of that spare key, and Foyer's NX key code.
    private struct Route {
        let sources: [UInt64]
        let destination: UInt64
        let virtualKey: UInt32
        let nxKeyCode: Int
    }

    // HID usages: Consumer page 0x0C, Apple top-case page 0xFF, Keyboard page 0x07.
    private static let routes: [Route] = [
        Route(sources: [0x0C_0000_00E9], destination: 0x07_0000_0068, virtualKey: UInt32(kVK_F13), nxKeyCode: HUDConstants.keySoundUp),
        Route(sources: [0x0C_0000_00EA], destination: 0x07_0000_0069, virtualKey: UInt32(kVK_F14), nxKeyCode: HUDConstants.keySoundDown),
        Route(sources: [0x0C_0000_00E2], destination: 0x07_0000_006A, virtualKey: UInt32(kVK_F15), nxKeyCode: HUDConstants.keyMute),
        Route(sources: [0x0C_0000_006F, 0xFF_0000_0004], destination: 0x07_0000_006B, virtualKey: UInt32(kVK_F16), nxKeyCode: HUDConstants.keyBrightnessUp),
        Route(sources: [0x0C_0000_0070, 0xFF_0000_0005], destination: 0x07_0000_006C, virtualKey: UInt32(kVK_F17), nxKeyCode: HUDConstants.keyBrightnessDown),
        Route(sources: [0xFF_0000_0008], destination: 0x07_0000_006D, virtualKey: UInt32(kVK_F18), nxKeyCode: HUDConstants.keyIlluminationUp),
        Route(sources: [0xFF_0000_0009], destination: 0x07_0000_006E, virtualKey: UInt32(kVK_F19), nxKeyCode: HUDConstants.keyIlluminationDown),
    ]

    /// Modifier combinations to catch (hot keys match modifiers exactly).
    private static let modifierSets: [UInt32] = [
        0,
        UInt32(shiftKey),
        UInt32(optionKey),
        UInt32(optionKey | shiftKey),
        UInt32(cmdKey),
        UInt32(controlKey),
    ]

    private static let signature: OSType = 0x464F_5952 // 'FOYR'
    private static let backupURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Foyer", isDirectory: true).appendingPathComponent("UserKeyMapping.backup.json")
    }()

    private var hotKeys: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private var originalMapping: [[String: UInt64]] = []
    private var heldKey: (route: Int, flags: UInt64)?
    private var repeatTask: Task<Void, Never>?
    private var refreshTimer: Timer?

    private init() {}

    // MARK: Lifecycle

    /// Restores a mapping left behind by a crash. Call once at launch.
    func recoverIfNeeded() {
        guard let data = try? Data(contentsOf: Self.backupURL),
              let saved = try? JSONDecoder().decode([[String: UInt64]].self, from: data) else { return }
        Self.setUserKeyMapping(saved)
        try? FileManager.default.removeItem(at: Self.backupURL)
    }

    /// Turns remapping on or off to match the current state.
    func update() {
        let wanted = !HUDKeyInterceptor.shared.isActive
            && (Defaults[.enableVolume] || Defaults[.enableBrightness])
        if wanted && !isActive { activate() }
        if !wanted && isActive { deactivate() }
    }

    func deactivate() {
        guard isActive else { return }
        refreshTimer?.invalidate()
        refreshTimer = nil
        repeatTask?.cancel()
        heldKey = nil
        hotKeys.forEach { UnregisterEventHotKey($0) }
        hotKeys.removeAll()
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
        Self.setUserKeyMapping(originalMapping)
        try? FileManager.default.removeItem(at: Self.backupURL)
        isActive = false
    }

    private func activate() {
        originalMapping = Self.currentUserKeyMapping().filter { entry in
            // Drop stale Foyer entries from an earlier session.
            !Self.routes.contains { $0.destination == entry["HIDKeyboardModifierMappingDst"] }
        }
        saveBackup()
        guard installHotKeys() else { return }
        applyMapping()
        isActive = true

        // Newly attached keyboards, wake and login-session changes can drop
        // the mapping; re-assert it periodically (hidutil is cheap).
        let timer = Timer(timeInterval: 30, repeats: true) { _ in
            Task { @MainActor in HUDKeyRemapper.shared.applyMapping() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func applyMapping() {
        var mapping = originalMapping
        for route in Self.routes {
            for source in route.sources {
                mapping.removeAll { $0["HIDKeyboardModifierMappingSrc"] == source }
                mapping.append(["HIDKeyboardModifierMappingSrc": source, "HIDKeyboardModifierMappingDst": route.destination])
            }
        }
        Self.setUserKeyMapping(mapping)
    }

    private func saveBackup() {
        let dir = Self.backupURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(originalMapping) {
            try? data.write(to: Self.backupURL, options: .atomic)
        }
    }

    // MARK: Hot keys

    private func installHotKeys() -> Bool {
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        var ref: EventHandlerRef?
        let status = InstallEventHandler(GetApplicationEventTarget(), hudHotKeyHandler, specs.count, &specs, nil, &ref)
        guard status == noErr, let ref else { return false }
        handlerRef = ref

        for (routeIndex, route) in Self.routes.enumerated() {
            for (modIndex, modifiers) in Self.modifierSets.enumerated() {
                let id = EventHotKeyID(signature: Self.signature, id: UInt32(routeIndex * 16 + modIndex))
                var hotKey: EventHotKeyRef?
                if RegisterEventHotKey(route.virtualKey, modifiers, id, GetApplicationEventTarget(), 0, &hotKey) == noErr,
                   let hotKey {
                    hotKeys.append(hotKey)
                }
            }
        }
        return !hotKeys.isEmpty
    }

    fileprivate func hotKey(id: UInt32, pressed: Bool) {
        let routeIndex = Int(id / 16)
        let modIndex = Int(id % 16)
        guard Self.routes.indices.contains(routeIndex), Self.modifierSets.indices.contains(modIndex) else { return }
        let flags = Self.cgFlags(fromCarbon: Self.modifierSets[modIndex])
        let keyCode = Self.routes[routeIndex].nxKeyCode

        if pressed {
            guard heldKey?.route != routeIndex else { return } // system auto-repeat, if any
            heldKey = (routeIndex, flags)
            fire(keyCode: keyCode, flags: flags, isRepeat: false)
            startRepeat(routeIndex: routeIndex, keyCode: keyCode, flags: flags)
        } else {
            guard heldKey?.route == routeIndex else { return }
            heldKey = nil
            repeatTask?.cancel()
            if keyCode == HUDConstants.keySoundUp || keyCode == HUDConstants.keySoundDown {
                HUDKeyInterceptor.shared.volumeKeyReleased(flags: flags)
            }
        }
    }

    private func fire(keyCode: Int, flags: UInt64, isRepeat: Bool) {
        let interceptor = HUDKeyInterceptor.shared
        if !interceptor.apply(keyCode: keyCode, isRepeat: isRepeat, flags: flags) {
            // Declined (HUD disabled, gaming, Command…): the key can't reach
            // macOS any more, so still change the level, without a HUD.
            interceptor.applyWithoutHUD(keyCode: keyCode, flags: flags)
        }
    }

    /// Key repeat while held, following the user's keyboard repeat settings.
    private func startRepeat(routeIndex: Int, keyCode: Int, flags: UInt64) {
        repeatTask?.cancel()
        guard keyCode != HUDConstants.keyMute else { return }
        let delay = NSEvent.keyRepeatDelay
        let interval = max(NSEvent.keyRepeatInterval, 0.03)
        repeatTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            while !Task.isCancelled, self.heldKey?.route == routeIndex {
                self.fire(keyCode: keyCode, flags: flags, isRepeat: true)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    private static func cgFlags(fromCarbon modifiers: UInt32) -> UInt64 {
        var flags: UInt64 = 0
        if modifiers & UInt32(shiftKey) != 0 { flags |= HUDConstants.flagShift }
        if modifiers & UInt32(optionKey) != 0 { flags |= HUDConstants.flagOption }
        if modifiers & UInt32(cmdKey) != 0 { flags |= HUDConstants.flagCommand }
        if modifiers & UInt32(controlKey) != 0 { flags |= CGEventFlags.maskControl.rawValue }
        return flags
    }

    // MARK: hidutil

    private static func currentUserKeyMapping() -> [[String: UInt64]] {
        guard let output = runHidutil(["property", "--get", "UserKeyMapping"]) else { return [] }
        // Output is an NSArray description: pairs of Src/Dst decimal numbers.
        var result: [[String: UInt64]] = []
        var current: [String: UInt64] = [:]
        for line in output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            for key in ["HIDKeyboardModifierMappingSrc", "HIDKeyboardModifierMappingDst"] where text.hasPrefix(key) {
                let digits = text.drop(while: { !$0.isNumber }).prefix(while: { $0.isNumber })
                if let value = UInt64(digits) { current[key] = value }
            }
            if text.hasPrefix("}"), current.count == 2 {
                result.append(current)
                current = [:]
            }
        }
        return result
    }

    private static func setUserKeyMapping(_ mapping: [[String: UInt64]]) {
        let entries = mapping.compactMap { entry -> String? in
            guard let src = entry["HIDKeyboardModifierMappingSrc"], let dst = entry["HIDKeyboardModifierMappingDst"] else { return nil }
            return "{\"HIDKeyboardModifierMappingSrc\":\(src),\"HIDKeyboardModifierMappingDst\":\(dst)}"
        }
        let json = "{\"UserKeyMapping\":[\(entries.joined(separator: ","))]}"
        _ = runHidutil(["property", "--set", json])
    }

    @discardableResult
    private static func runHidutil(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

/// Carbon hot-key callback (runs on the main thread).
private func hudHotKeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &hotKeyID)
    guard status == noErr, hotKeyID.signature == 0x464F_5952 else { return OSStatus(eventNotHandledErr) }
    let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
    let id = hotKeyID.id
    MainActor.assumeIsolated {
        HUDKeyRemapper.shared.hotKey(id: id, pressed: pressed)
    }
    return noErr
}
