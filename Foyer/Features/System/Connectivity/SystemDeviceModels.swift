import AppKit
import SwiftUI

/// AirPods models, in the order of Alcove's model tags (classifier
/// 0x10031a2c4, Part E §3).
enum SystemAirPodsModel: Int, CaseIterable {
    case airPods = 0
    case airPods2 = 1
    case airPods3 = 2
    case airPods4 = 3
    case airPodsPro = 4
    case airPodsPro2 = 5
    case airPodsPro3 = 6
    case airPodsMax = 7
    case airPodsMax2 = 8

    /// Exact lower-case four-character model identifiers (first component of
    /// the CoreAudio model UID / the Bluetooth product id in hex).
    static func classify(_ identifier: String?) -> SystemAirPodsModel? {
        guard var id = identifier?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty else { return nil }
        if let first = id.split(separator: " ").first { id = String(first) }
        if id.hasPrefix("0x") { id = String(id.dropFirst(2)) }
        while id.count < 4 { id = "0" + id }
        switch id {
        case "2002": return .airPods
        case "200f": return .airPods2
        case "2013": return .airPods3
        case "201b", "2019": return .airPods4
        case "200e": return .airPodsPro
        case "2014", "2024": return .airPodsPro2
        case "2027": return .airPodsPro3
        case "200a": return .airPodsMax
        case "201f", "202d": return .airPodsMax2
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .airPods: return "AirPods"
        case .airPods2: return "AirPods (2nd generation)"
        case .airPods3: return "AirPods (3rd generation)"
        case .airPods4: return "AirPods 4"
        case .airPodsPro: return "AirPods Pro"
        case .airPodsPro2: return "AirPods Pro 2"
        case .airPodsPro3: return "AirPods Pro 3"
        case .airPodsMax: return "AirPods Max"
        case .airPodsMax2: return "AirPods Max 2"
        }
    }

    var isMax: Bool { self == .airPodsMax || self == .airPodsMax2 }

    /// Name of the matching clip in a locally installed Alcove.app (Part F §6).
    /// AirPods 1/2 have no clip of their own and reuse "airpods-3" (INFERRED).
    func videoResourceName(color: SystemAirPodsMaxColor) -> String {
        switch self {
        case .airPods, .airPods2, .airPods3: return "airpods-3"
        case .airPods4: return "airpods-4"
        case .airPodsPro: return "airpods-pro"
        case .airPodsPro2: return "airpods-pro-2"
        case .airPodsPro3: return "airpods-pro-3"
        case .airPodsMax, .airPodsMax2: return "airpods-max-" + color.assetSuffix
        }
    }

    /// Has two buds (left/right) and a case.
    var hasBuds: Bool { !isMax }

    /// SF Symbols, best first; the first one this macOS knows is used.
    var symbolCandidates: [String] {
        switch self {
        case .airPods, .airPods2: return ["airpods"]
        case .airPods3: return ["airpods.gen3", "airpods"]
        case .airPods4: return ["airpods.gen4", "airpods.gen3", "airpods"]
        case .airPodsPro, .airPodsPro2, .airPodsPro3: return ["airpodspro", "airpods.pro", "airpods"]
        case .airPodsMax, .airPodsMax2: return ["airpodsmax", "headphones"]
        }
    }
}

/// AirPods Max colours (mapper 0x10031a290: `colorID & 0x3f`, minus 2,
/// bounds 0...20, table lookup; unavailable / out of range → space gray).
enum SystemAirPodsMaxColor: String, CaseIterable {
    case red, skyBlue, spaceGray, silver, green, midnight, starlight, blue, orange, purple

    private static let table: [SystemAirPodsMaxColor] = [
        .red,                                   // 2
        .skyBlue,                               // 3
        .spaceGray, .spaceGray, .spaceGray, .spaceGray, .spaceGray, .spaceGray,
        .spaceGray, .spaceGray, .spaceGray, .spaceGray, .spaceGray, .spaceGray, // 4...15
        .silver,                                // 16
        .green,                                 // 17
        .midnight,                              // 18
        .starlight,                             // 19
        .blue,                                  // 20
        .orange,                                // 21
        .purple,                                // 22
    ]

    static func from(colorID: Int?) -> SystemAirPodsMaxColor {
        guard let colorID else { return .spaceGray }
        let index = (colorID & 0x3f) - 2
        guard index >= 0, index < table.count else { return .spaceGray }
        return table[index]
    }

    /// Alcove's asset suffix (`airpods-max-<suffix>.mp4`).
    var assetSuffix: String {
        switch self {
        case .skyBlue: return "sky-blue"
        case .spaceGray: return "space-gray"
        default: return rawValue
        }
    }

    /// Lightened shades so the glyph reads on the black island.
    var tint: Color {
        switch self {
        case .red: return Color(red: 0.90, green: 0.45, blue: 0.43)
        case .skyBlue: return Color(red: 0.66, green: 0.80, blue: 0.90)
        case .spaceGray: return Color(white: 0.68)
        case .silver: return Color(white: 0.92)
        case .green: return Color(red: 0.66, green: 0.80, blue: 0.64)
        case .midnight: return Color(red: 0.50, green: 0.55, blue: 0.66)
        case .starlight: return Color(red: 0.95, green: 0.91, blue: 0.84)
        case .blue: return Color(red: 0.50, green: 0.64, blue: 0.92)
        case .orange: return Color(red: 0.96, green: 0.64, blue: 0.40)
        case .purple: return Color(red: 0.74, green: 0.64, blue: 0.90)
        }
    }
}

/// What a connected device is, for its glyph.
enum SystemDeviceKind: Equatable {
    case airPods(SystemAirPodsModel, SystemAirPodsMaxColor)
    case headphones
    case speaker
    case homePod
    case homePodMini
    case keyboard
    case mouse
    case trackpad
    case gameController
    case phone
    case computer
    case watch
    case generic

    var isAirPods: Bool {
        if case .airPods = self { return true }
        return false
    }

    var airPodsModel: SystemAirPodsModel? {
        if case let .airPods(model, _) = self { return model }
        return nil
    }

    /// The animated "3D models" presentation applies to AirPods and other
    /// headphones; everything else is always a static symbol.
    var supportsModelAnimation: Bool {
        switch self {
        case .airPods, .headphones: return true
        default: return false
        }
    }

    /// Alcove clip name for AirPods, nil for every other device.
    var videoResourceName: String? {
        if case let .airPods(model, color) = self { return model.videoResourceName(color: color) }
        return nil
    }

    var tint: Color {
        if case let .airPods(model, color) = self, model.isMax { return color.tint }
        return .white
    }

    var symbolCandidates: [String] {
        switch self {
        case let .airPods(model, _): return model.symbolCandidates
        case .headphones: return ["headphones"]
        case .speaker: return ["hifispeaker.fill", "speaker.wave.2.fill"]
        case .homePod: return ["homepod.fill", "hifispeaker.fill"]
        case .homePodMini: return ["homepodmini.fill", "homepod.fill", "hifispeaker.fill"]
        case .keyboard: return ["keyboard.fill", "keyboard"]
        case .mouse: return ["magicmouse.fill", "computermouse.fill", "magicmouse"]
        case .trackpad: return ["rectangle.and.hand.point.up.left.fill", "hand.point.up.left.fill"]
        case .gameController: return ["gamecontroller.fill"]
        case .phone: return ["iphone"]
        case .computer: return ["laptopcomputer"]
        case .watch: return ["applewatch"]
        case .generic: return ["dot.radiowaves.left.and.right", "antenna.radiowaves.left.and.right"]
        }
    }

    /// First candidate this system can render.
    @MainActor
    var symbolName: String {
        SystemSymbolCache.resolve(symbolCandidates)
    }

    /// Bluetooth Class of Device fallback. Audio (major 4) follows Alcove's
    /// table at 0x10031b210 (index minor - 1; minors 1/2/6 are headphones);
    /// peripherals (major 5) use the keyboard / pointing bits.
    static func classify(name: String, classMajor: UInt32, classMinor: UInt32,
                         modelIdentifier: String?, colorID: Int?) -> SystemDeviceKind {
        if let model = SystemAirPodsModel.classify(modelIdentifier) {
            return .airPods(model, model.isMax ? SystemAirPodsMaxColor.from(colorID: colorID) : .spaceGray)
        }
        let lowered = name.lowercased()
        if lowered.contains("homepod") {
            return lowered.contains("mini") ? .homePodMini : .homePod
        }
        switch classMajor {
        case 4: // Audio/Video
            switch classMinor {
            case 1, 2, 6: return .headphones
            default:
                if lowered.contains("airpods") || lowered.contains("headphone") || lowered.contains("buds")
                    || lowered.contains("beats") {
                    return .headphones
                }
                return .speaker
            }
        case 5: // Peripheral
            let kind = classMinor & 0x30
            let subtype = classMinor & 0x0f
            if subtype == 1 || subtype == 2 { return .gameController }
            if kind == 0x20 {
                return lowered.contains("trackpad") ? .trackpad : .mouse
            }
            if kind == 0x10 || kind == 0x30 {
                if lowered.contains("trackpad") { return .trackpad }
                if lowered.contains("mouse") { return .mouse }
                return .keyboard
            }
            if lowered.contains("keyboard") { return .keyboard }
            if lowered.contains("trackpad") { return .trackpad }
            if lowered.contains("mouse") { return .mouse }
            if lowered.contains("controller") || lowered.contains("gamepad") { return .gameController }
            return .generic
        case 2: return .phone
        case 1: return .computer
        case 7: return .watch
        case 8: return .gameController
        default:
            if lowered.contains("airpods") || lowered.contains("headphone") { return .headphones }
            if lowered.contains("keyboard") { return .keyboard }
            if lowered.contains("trackpad") { return .trackpad }
            if lowered.contains("mouse") { return .mouse }
            if lowered.contains("controller") { return .gameController }
            return .generic
        }
    }
}

/// Battery readings for a Bluetooth device, 0...100 each.
struct SystemDeviceBattery: Equatable {
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    /// `batteryPercentSingle` (single-cell devices; not the case).
    var single: Int?

    var isEmpty: Bool { left == nil && right == nil && caseLevel == nil && single == nil }

    /// `AirPodsState`: leftOnly 0, rightOnly 1, both 2.
    enum BudState { case leftOnly, rightOnly, both, none }

    var budState: BudState {
        switch (left != nil, right != nil) {
        case (true, true): return .both
        case (true, false): return .leftOnly
        case (false, true): return .rightOnly
        default: return .none
        }
    }

    /// The level shown and checked against the threshold: the lowest bud,
    /// else the single cell.
    var primary: Int? {
        let buds = [left, right].compactMap { $0 }
        if let lowest = buds.min() { return lowest }
        return single
    }

    /// Fills missing values from `other`.
    func merged(with other: SystemDeviceBattery) -> SystemDeviceBattery {
        SystemDeviceBattery(left: left ?? other.left,
                            right: right ?? other.right,
                            caseLevel: caseLevel ?? other.caseLevel,
                            single: single ?? other.single)
    }

    static func valid(_ value: Int?) -> Int? {
        guard let value, value > 0, value < 0x65 else { return nil }
        return value
    }
}

/// A connected Bluetooth device as Foyer tracks it.
struct SystemConnectedDevice: Identifiable, Equatable {
    /// Normalised address (lower-case hex digits only).
    var id: String
    var name: String
    var kind: SystemDeviceKind
    var battery: SystemDeviceBattery
    var modelIdentifier: String?
    var connectedAt: Date

    var displayName: String {
        if !name.isEmpty { return name }
        return kind.airPodsModel?.displayName ?? "Bluetooth Device"
    }
}

/// Normalises Bluetooth addresses from IOBluetooth ("aa-bb-…"),
/// system_profiler ("AA:BB:…") and CoreAudio UIDs ("AA-BB-…:output").
enum SystemBluetoothAddress {
    static func normalize(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        var source = raw
        if raw.contains("-"), let head = raw.split(separator: ":").first {
            // "AA-BB-CC-DD-EE-FF:output" → drop the role suffix.
            source = String(head)
        }
        let hex = source.lowercased().filter { $0.isHexDigit }
        return hex.count == 12 ? hex : nil
    }
}

/// Caches which SF Symbols exist on this macOS.
@MainActor
enum SystemSymbolCache {
    private static var cache: [String: String] = [:]

    static func resolve(_ candidates: [String]) -> String {
        let key = candidates.joined(separator: "|")
        if let hit = cache[key] { return hit }
        let found = candidates.first { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }
            ?? candidates.last ?? "questionmark"
        cache[key] = found
        return found
    }
}
