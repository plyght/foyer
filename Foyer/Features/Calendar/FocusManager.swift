import AppKit
import Combine
import Defaults
import SwiftUI

/// Tracks the active Focus mode and announces changes in the notch
/// (Part D §2): 216 x 28, mode glyph on the left, "On"/"Off" on the right,
/// shown for `focusDuration` after a shrink-to-144-and-regrow content swap.
///
/// Detection (no public API exposes the mode on macOS):
/// 1. `~/Library/DoNotDisturb/DB/Assertions.json` (active assertion → mode id)
///    and `ModeConfigurations.json` (name / symbol / tint of custom modes),
///    watched with a directory event source plus a cheap modification-date
///    poll. Reading these may require Full Disk Access on recent macOS.
/// 2. Best effort when the files are unreadable: the distributed
///    notifications `_NSDoNotDisturbEnabledNotification` /
///    `_NSDoNotDisturbDisabledNotification` (generic Do Not Disturb) and
///    `com.apple.donotdisturb.state.changed` (re-read).
@MainActor
final class FocusManager: ObservableObject {
    static let shared = FocusManager()

    @Published var currentFocus: FocusMode?
    /// False when the Focus database could not be read (Full Disk Access).
    @Published private(set) var canReadFocusDatabase = true

    private let databaseURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)
    private var assertionsURL: URL { databaseURL.appendingPathComponent("Assertions.json") }
    private var configurationsURL: URL { databaseURL.appendingPathComponent("ModeConfigurations.json") }

    private var directorySource: DispatchSourceFileSystemObject?
    private var pollTimer: Timer?
    private var lastModification: Date?
    private var readTask: Task<Void, Never>?
    private var presentTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    private init() {}

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true

        // Initial state: no announcement.
        let initial = readFocusFromDatabase()
        currentFocus = initial.mode
        canReadFocusDatabase = initial.readable
        updateContextFlag()

        startDirectoryWatcher()
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            _ = MainActor.assumeIsolated { self?.pollModificationDate() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer

        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: NSNotification.Name("_NSDoNotDisturbEnabledNotification"),
                                            object: nil, queue: .main) { [weak self] _ in
            _ = MainActor.assumeIsolated { self?.legacyNotification(enabled: true) }
        })
        observers.append(center.addObserver(forName: NSNotification.Name("_NSDoNotDisturbDisabledNotification"),
                                            object: nil, queue: .main) { [weak self] _ in
            _ = MainActor.assumeIsolated { self?.legacyNotification(enabled: false) }
        })
        for name in ["com.apple.donotdisturb.state.changed", "com.apple.notificationcenterui.dndprefs_changed"] {
            observers.append(center.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { [weak self] _ in
                _ = MainActor.assumeIsolated { self?.scheduleRead() }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            _ = MainActor.assumeIsolated { self?.scheduleRead() }
        })

        Defaults.publisher(.enableFocus, options: [])
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateContextFlag() }
            .store(in: &cancellables)
    }

    private func updateContextFlag() {
        let active = Defaults[.enableFocus] && currentFocus != nil
        if NotchController.shared.isFocusActive != active {
            NotchController.shared.isFocusActive = active
        }
    }

    // MARK: Watching

    private func startDirectoryWatcher() {
        let fd = open(databaseURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend, .attrib], queue: .main)
        source.setEventHandler { [weak self] in
            _ = MainActor.assumeIsolated { self?.scheduleRead() }
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        directorySource = source
    }

    private func pollModificationDate() {
        let attributes = try? FileManager.default.attributesOfItem(atPath: assertionsURL.path)
        let modified = attributes?[.modificationDate] as? Date
        if modified != lastModification {
            lastModification = modified
            scheduleRead()
        }
    }

    /// Coalesces bursts of file events (the database is rewritten atomically).
    private func scheduleRead() {
        readTask?.cancel()
        readTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.15))
            guard !Task.isCancelled, let self else { return }
            let result = self.readFocusFromDatabase()
            self.canReadFocusDatabase = result.readable
            guard result.readable else { return }
            self.apply(result.mode)
        }
    }

    private func legacyNotification(enabled: Bool) {
        // When the database is readable it is the source of truth.
        let result = readFocusFromDatabase()
        if result.readable {
            apply(result.mode)
        } else {
            apply(enabled ? FocusCatalog.mode(for: FocusCatalog.doNotDisturb, configurations: [:]) : nil)
        }
    }

    // MARK: Parsing

    private func readFocusFromDatabase() -> (mode: FocusMode?, readable: Bool) {
        guard let data = try? Data(contentsOf: assertionsURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (nil, false)
        }
        if lastModification == nil {
            lastModification = (try? FileManager.default.attributesOfItem(atPath: assertionsURL.path))?[.modificationDate] as? Date
        }
        let entries = root["data"] as? [[String: Any]] ?? []
        var identifier: String?
        for entry in entries {
            let records = entry["storeAssertionRecords"] as? [[String: Any]] ?? []
            // The most recent assertion wins.
            let sorted = records.sorted {
                ($0["assertionStartDateTimestamp"] as? Double ?? 0) > ($1["assertionStartDateTimestamp"] as? Double ?? 0)
            }
            for record in sorted {
                if let details = record["assertionDetails"] as? [String: Any],
                   let mode = details["assertionDetailsModeIdentifier"] as? String, !mode.isEmpty {
                    identifier = mode
                    break
                }
            }
            if identifier != nil { break }
        }
        guard let identifier else { return (nil, true) }
        return (FocusCatalog.mode(for: identifier, configurations: readConfigurations()), true)
    }

    /// modeIdentifier → (name, symbol, tint name) from ModeConfigurations.json.
    private func readConfigurations() -> [String: FocusCatalog.Configuration] {
        guard let data = try? Data(contentsOf: configurationsURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = root["data"] as? [[String: Any]] else { return [:] }
        var result: [String: FocusCatalog.Configuration] = [:]
        for entry in entries {
            guard let configurations = entry["modeConfigurations"] as? [String: Any] else { continue }
            for (key, value) in configurations {
                guard let dict = value as? [String: Any],
                      let mode = dict["mode"] as? [String: Any] else { continue }
                let id = mode["modeIdentifier"] as? String ?? key
                result[id] = FocusCatalog.Configuration(
                    name: mode["name"] as? String,
                    symbolName: mode["symbolImageName"] as? String,
                    tintName: mode["tintColorName"] as? String)
            }
        }
        return result
    }

    // MARK: Changes

    private func apply(_ mode: FocusMode?) {
        let previous = currentFocus
        guard previous?.identifier != mode?.identifier else {
            // Same mode; pick up renamed / recoloured configurations silently.
            if previous != mode { currentFocus = mode }
            return
        }
        currentFocus = mode
        updateContextFlag()

        if let mode {
            announce(mode, isOn: true)
            if mode.isSleep, Defaults[.enableFocus], Defaults[.playSoundOnSleepFocus] {
                SoundPlayer.play(.sleep)
            }
        } else if let previous {
            announce(previous, isOn: false)
        }
    }

    /// Focus notification with the content swap: shrink to the empty 144 px
    /// notch (333 ms ease-out), regrow to 216 with the glyph (470 ms
    /// ease-out), hold `focusDuration`, then shrink/regrow back.
    private func announce(_ mode: FocusMode, isOn: Bool) {
        guard Defaults[.enableFocus] else { return }
        let controller = NotchController.shared
        guard controller.isAllowed(.focus) else { return }

        presentTask?.cancel()
        let shrink = CalendarStyle.focusShrinkDuration
        let grow = CalendarStyle.focusGrowDuration
        let hold = max(0.5, Defaults[.focusDuration])
        let swapIn = controller.visibleActivity != nil || controller.notification != nil

        presentTask = Task { @MainActor in
            if swapIn {
                controller.post(FocusManager.blank(duration: shrink + grow + 1, animation: .easeOut(duration: shrink)))
                try? await Task.sleep(for: .seconds(shrink))
                guard !Task.isCancelled else { return }
            }
            controller.post(NotchNotification(
                kind: .focus,
                category: .focus,
                wingWidth: CalendarStyle.wing,
                duration: grow + hold + 1,
                animation: .easeOut(duration: grow),
                leading: AnyView(FocusNotificationLeading(mode: mode, isOn: isOn)),
                trailing: AnyView(FocusNotificationTrailing(mode: mode, isOn: isOn))))

            try? await Task.sleep(for: .seconds(grow + hold))
            guard !Task.isCancelled, controller.notification?.kind == .focus else { return }
            if controller.visibleActivity != nil {
                // Swap back: shrink, then the blank expires and the activity regrows.
                controller.post(FocusManager.blank(duration: shrink, animation: .easeOut(duration: shrink)))
            } else {
                controller.dismissNotification(.focus)
            }
        }
    }

    private static func blank(duration: TimeInterval, animation: Animation) -> NotchNotification {
        NotchNotification(
            kind: .generic,
            category: .focus,
            wingWidth: CalendarStyle.focusShrunkWing,
            duration: duration,
            animation: animation,
            leading: AnyView(Color.clear),
            trailing: AnyView(Color.clear))
    }
}

// MARK: - Catalog

/// Built-in Focus modes (identifiers recovered from Alcove's strings) and the
/// mapping of `tintColorName` values to colours.
enum FocusCatalog {
    struct Configuration {
        var name: String?
        var symbolName: String?
        var tintName: String?
    }

    static let doNotDisturb = "com.apple.donotdisturb.mode.default"
    static let sleep = "com.apple.sleep.sleep-mode"

    private struct Builtin {
        let name: String
        let symbol: String
        let tint: Color
    }

    private static func builtin(_ identifier: String) -> Builtin? {
        switch identifier {
        case doNotDisturb:
            return Builtin(name: String(localized: "Do Not Disturb"), symbol: "moon.fill", tint: CalendarStyle.indigo)
        case sleep:
            return Builtin(name: String(localized: "Sleep"), symbol: "bed.double.fill",
                           tint: Color(red: 0.36, green: 0.80, blue: 0.83))
        case "com.apple.donotdisturb.mode.driving":
            return Builtin(name: String(localized: "Driving"), symbol: "car.fill", tint: CalendarStyle.amber)
        case "com.apple.donotdisturb.mode.workout":
            return Builtin(name: String(localized: "Fitness"), symbol: "figure.run", tint: CalendarStyle.green)
        case "com.apple.focus.work":
            return Builtin(name: String(localized: "Work"), symbol: "person.lanyardcard.fill", tint: CalendarStyle.sky)
        case "com.apple.focus.personal-time":
            return Builtin(name: String(localized: "Personal"), symbol: "person.fill", tint: CalendarStyle.pink)
        case "com.apple.focus.gaming":
            return Builtin(name: String(localized: "Gaming"), symbol: "gamecontroller.fill",
                           tint: Color(red: 0.23, green: 0.51, blue: 0.96))
        case "com.apple.focus.mindfulness":
            return Builtin(name: String(localized: "Mindfulness"), symbol: "apple.meditate", tint: CalendarStyle.emerald)
        case "com.apple.focus.reading":
            return Builtin(name: String(localized: "Reading"), symbol: "book.fill", tint: CalendarStyle.orange)
        case "com.apple.focus.reduce-interruptions":
            return Builtin(name: String(localized: "Reduce Interruptions"), symbol: "sparkles",
                           tint: Color(red: 0.55, green: 0.36, blue: 0.96))
        default:
            return nil
        }
    }

    static func mode(for identifier: String, configurations: [String: Configuration]) -> FocusMode {
        let config = configurations[identifier]
        let base = builtin(identifier)
        let name = nonEmpty(config?.name) ?? base?.name ?? String(localized: "Focus")
        var symbol = nonEmpty(config?.symbolName) ?? base?.symbol ?? "moon.fill"
        if NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil {
            symbol = base?.symbol ?? "moon.fill"
        }
        let tint = color(named: config?.tintName) ?? base?.tint ?? CalendarStyle.indigo
        return FocusMode(identifier: identifier, name: name, symbolName: symbol, tint: tint,
                         isSleep: identifier == sleep)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func color(named name: String?) -> Color? {
        guard let name = name?.lowercased() else { return nil }
        if name.contains("indigo") { return CalendarStyle.indigo }
        if name.contains("purple") { return Color(red: 0.69, green: 0.32, blue: 0.87) }
        if name.contains("pink") { return CalendarStyle.pink }
        if name.contains("red") { return CalendarStyle.rose }
        if name.contains("orange") { return CalendarStyle.orange }
        if name.contains("yellow") { return Color(red: 0.98, green: 0.76, blue: 0.22) }
        if name.contains("green") { return CalendarStyle.green }
        if name.contains("mint") { return Color(red: 0.0, green: 0.78, blue: 0.75) }
        if name.contains("teal") { return Color(red: 0.36, green: 0.80, blue: 0.83) }
        if name.contains("cyan") { return Color(red: 0.2, green: 0.75, blue: 0.95) }
        if name.contains("blue") { return Color(red: 0.23, green: 0.51, blue: 0.96) }
        if name.contains("brown") { return Color(red: 0.64, green: 0.52, blue: 0.37) }
        if name.contains("gray") || name.contains("grey") { return Color.gray }
        return nil
    }
}

// MARK: - Views

/// Mode glyph: tinted when turning on, grey when turning off.
struct FocusNotificationLeading: View {
    let mode: FocusMode
    let isOn: Bool

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: mode.symbolName)
                .font(.system(size: CalendarStyle.compactGlyphSize, weight: .semibold))
                .foregroundStyle(isOn ? mode.tint : CalendarStyle.offGrey)
            Spacer(minLength: 0)
        }
        .padding(.leading, CalendarStyle.wingInset)
    }
}

/// "On" / "Off" label (~13 pt semibold) in the same colour; empty with "Hide label".
struct FocusNotificationTrailing: View {
    let mode: FocusMode
    let isOn: Bool
    @Default(.hideLabel) private var hideLabel

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            if !hideLabel {
                Text(isOn ? String(localized: "On") : String(localized: "Off"))
                    .font(.system(size: CalendarStyle.compactFontSize, weight: .semibold))
                    .foregroundStyle(isOn ? mode.tint : CalendarStyle.offGrey)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.trailing, CalendarStyle.wingInset)
    }
}

/// Lock-screen Focus widget (drawn on the lock feature's glass material).
struct FocusLockWidget: View {
    @ObservedObject private var focus = FocusManager.shared

    var body: some View {
        let mode = focus.currentFocus
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((mode?.tint ?? Color.white).opacity(mode == nil ? 0.12 : 0.22))
                Image(systemName: mode?.symbolName ?? "moon.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(mode?.tint ?? Color.white.opacity(0.6))
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode?.name ?? String(localized: "Focus"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(mode == nil ? String(localized: "Off") : String(localized: "On"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
        .environment(\.colorScheme, .dark)
        .animation(Constants.Animations.standard, value: mode?.identifier)
    }
}
