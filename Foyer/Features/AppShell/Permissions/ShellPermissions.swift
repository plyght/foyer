import AppKit
import ApplicationServices
import CoreBluetooth
import CoreLocation
import CoreServices
import Defaults
import EventKit
import os

/// The TCC permissions Foyer asks for. Calendar, Bluetooth and Accessibility
/// are requested during onboarding; Location and Audio Capture are requested
/// lazily from Settings ("unblock" badges), like Alcove (lead §3).
enum ShellPermissionKind: String, CaseIterable, Identifiable {
    case accessibility, calendar, bluetooth, location, audioCapture

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .calendar: return "Calendars"
        case .bluetooth: return "Bluetooth"
        case .location: return "Location Services"
        case .audioCapture: return "System Audio Recording"
        }
    }

    /// Explains why the permission is needed (used as tooltip on unblock badges).
    var reason: String {
        switch self {
        case .accessibility: return "Foyer needs Accessibility access to hide and replace the system HUDs."
        case .calendar: return "Foyer needs access to your calendars to show upcoming events."
        case .bluetooth: return "Foyer needs Bluetooth access to show the battery of your AirPods and other devices."
        case .location: return "Foyer needs your location for weather and time-to-leave alerts."
        case .audioCapture: return "Foyer needs permission to capture system audio to display the live waveform."
        }
    }

    /// Anchor of the matching pane in System Settings › Privacy & Security.
    var privacyAnchor: String {
        switch self {
        case .accessibility: return "Privacy_Accessibility"
        case .calendar: return "Privacy_Calendars"
        case .bluetooth: return "Privacy_Bluetooth"
        case .location: return "Privacy_LocationServices"
        case .audioCapture: return "Privacy_ScreenCapture"
        }
    }
}

enum ShellPermissionState: Equatable {
    case notDetermined, denied, granted
}

/// Automation (Apple Events) permission for one target application.
enum ShellAutomationState: Equatable {
    case granted, denied, notDetermined, notRunning, notInstalled, unknown
}

enum ShellLog {
    static let logger = Logger(subsystem: "app.foyer.Foyer", category: "AppShell")
}

/// Central permission state for onboarding and Settings. Reads are cheap and
/// refreshed whenever Foyer becomes active, so the "unblock" badges disappear
/// as soon as the user flips the switch in System Settings.
@MainActor
final class ShellPermissions: ObservableObject {
    static let shared = ShellPermissions()

    @Published private(set) var states: [ShellPermissionKind: ShellPermissionState] = [:]
    @Published private(set) var automation: [String: ShellAutomationState] = [:]

    private let locationManager = CLLocationManager()
    private let locationDelegate = ShellLocationDelegate()
    private let bluetoothDelegate = ShellBluetoothDelegate()
    private var bluetoothManager: CBCentralManager?
    private var calendarRequestStore: EKEventStore?
    private var activationObserver: NSObjectProtocol?
    private var accessibilityPoll: Task<Void, Never>?

    private init() {
        locationManager.delegate = locationDelegate
        refresh()
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in ShellPermissions.shared.refresh() }
        }
    }

    // MARK: Reading

    func state(_ kind: ShellPermissionKind) -> ShellPermissionState {
        states[kind] ?? .notDetermined
    }

    func isGranted(_ kind: ShellPermissionKind) -> Bool {
        state(kind) == .granted
    }

    func refresh() {
        var new: [ShellPermissionKind: ShellPermissionState] = [:]
        for kind in ShellPermissionKind.allCases {
            new[kind] = currentState(of: kind)
        }
        if new != states { states = new }
    }

    private func currentState(of kind: ShellPermissionKind) -> ShellPermissionState {
        switch kind {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : (Defaults[.hasPromptedAccessibilityPermission] ? .denied : .notDetermined)
        case .calendar:
            return Self.calendarState()
        case .bluetooth:
            switch CBManager.authorization {
            case .allowedAlways: return .granted
            case .notDetermined: return .notDetermined
            case .denied, .restricted: return .denied
            @unknown default: return .denied
            }
        case .location:
            switch locationManager.authorizationStatus {
            case .notDetermined: return .notDetermined
            case .denied, .restricted: return .denied
            default: return .granted
            }
        case .audioCapture:
            return Self.audioCaptureState()
        }
    }

    static func calendarState() -> ShellPermissionState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        case .denied, .restricted, .writeOnly: return .denied
        default: return .granted
        }
    }

    // MARK: Requesting

    /// Asks for `kind`: shows the system prompt when it was never answered,
    /// otherwise opens the matching System Settings pane.
    func unblock(_ kind: ShellPermissionKind) {
        refresh()
        if state(kind) == .notDetermined {
            request(kind)
        } else if state(kind) == .denied {
            openSettings(for: kind)
        }
    }

    /// Shows the system prompt for `kind` (no-op once answered, except
    /// Accessibility which also opens System Settings).
    func request(_ kind: ShellPermissionKind, completion: (@MainActor (Bool) -> Void)? = nil) {
        switch kind {
        case .accessibility:
            Defaults[.hasPromptedAccessibilityPermission] = true
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            let trusted = AXIsProcessTrustedWithOptions(options)
            if !trusted { openSettings(for: .accessibility) }
            pollAccessibility()
            refresh()
            completion?(trusted)

        case .calendar:
            Defaults[.hasPromptedCalendarPermission] = true
            let store = EKEventStore()
            calendarRequestStore = store
            store.requestFullAccessToEvents { granted, error in
                if let error { ShellLog.logger.error("Calendar access request failed: \(error.localizedDescription, privacy: .public)") }
                Task { @MainActor in
                    ShellPermissions.shared.refresh()
                    NotificationCenter.default.post(name: .shellCalendarAccessChanged, object: nil)
                    completion?(granted)
                }
            }

        case .bluetooth:
            Defaults[.hasPromptedBluetoothPermission] = true
            if CBManager.authorization == .notDetermined {
                bluetoothDelegate.onChange = {
                    Task { @MainActor in
                        ShellPermissions.shared.refresh()
                        completion?(ShellPermissions.shared.isGranted(.bluetooth))
                    }
                }
                // Creating a central manager triggers the TCC prompt.
                bluetoothManager = CBCentralManager(delegate: bluetoothDelegate, queue: nil)
            } else {
                refresh()
                completion?(isGranted(.bluetooth))
            }

        case .location:
            Defaults[.hasPromptedLocationPermission] = true
            if locationManager.authorizationStatus == .notDetermined {
                locationDelegate.onChange = {
                    Task { @MainActor in
                        ShellPermissions.shared.refresh()
                        completion?(ShellPermissions.shared.isGranted(.location))
                    }
                }
                locationManager.requestWhenInUseAuthorization()
            } else {
                refresh()
                completion?(isGranted(.location))
            }

        case .audioCapture:
            Defaults[.hasPromptedAudioPermission] = true
            Self.requestAudioCapture { granted in
                Task { @MainActor in
                    ShellPermissions.shared.refresh()
                    completion?(granted)
                }
            }
        }
    }

    /// Async wrapper for `request(_:completion:)`.
    func requestAndWait(_ kind: ShellPermissionKind) async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let once = ShellOnce()
            request(kind) { granted in
                if once.claim() { continuation.resume(returning: granted) }
            }
        }
    }

    func openSettings(for kind: ShellPermissionKind) {
        let string = "x-apple.systempreferences:com.apple.preference.security?\(kind.privacyAnchor)"
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Polls `AXIsProcessTrusted` every 0.5 s for up to five minutes after a
    /// prompt, so badges and onboarding update without relaunching.
    func pollAccessibility() {
        accessibilityPoll?.cancel()
        accessibilityPoll = Task { @MainActor in
            for _ in 0..<600 {
                try? await Task.sleep(for: .milliseconds(500))
                if Task.isCancelled { return }
                if AXIsProcessTrusted() {
                    ShellPermissions.shared.refresh()
                    return
                }
            }
        }
    }

    // MARK: Audio capture (private TCC)

    private typealias TCCPreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int32
    private typealias TCCRequestFunction = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void

    private static let audioCaptureService = "kTCCServiceAudioCapture" as CFString

    static func audioCaptureState() -> ShellPermissionState {
        guard let preflight = PrivateAPI.symbol("TCCAccessPreflight", in: PrivateAPI.tcc, as: TCCPreflightFunction.self) else {
            return Defaults[.hasPromptedAudioPermission] ? .denied : .notDetermined
        }
        // 0 = granted, 1 = denied, 2 = not determined.
        switch preflight(audioCaptureService, nil) {
        case 0: return .granted
        case 1: return .denied
        default: return .notDetermined
        }
    }

    private static func requestAudioCapture(_ completion: @escaping (Bool) -> Void) {
        guard let request = PrivateAPI.symbol("TCCAccessRequest", in: PrivateAPI.tcc, as: TCCRequestFunction.self) else {
            completion(false)
            return
        }
        request(audioCaptureService, nil) { granted in
            completion(granted)
        }
    }

    // MARK: Automation (Apple Events)

    func isRunning(_ bundleIdentifier: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty
    }

    func isInstalled(_ bundleIdentifier: String) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    func automationState(for bundleIdentifier: String) -> ShellAutomationState {
        automation[bundleIdentifier] ?? .unknown
    }

    /// Reads the automation permission for `bundleIdentifier` without prompting.
    func refreshAutomation(for bundleIdentifier: String) async {
        let state = await determineAutomation(bundleIdentifier, ask: false)
        automation[bundleIdentifier] = state
    }

    /// Sends the harmless permission probe that makes macOS show the
    /// "Foyer wants access to control …" prompt. When `launchIfNeeded` is set
    /// and the target is installed but not running, it is launched hidden in
    /// the background first, because Apple Events need a running target.
    @discardableResult
    func requestAutomation(for bundleIdentifier: String, launchIfNeeded: Bool,
                           quitIfLaunched: Bool = false) async -> ShellAutomationState {
        var didLaunch = false
        if !isRunning(bundleIdentifier) {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
                automation[bundleIdentifier] = .notInstalled
                return .notInstalled
            }
            guard launchIfNeeded else {
                automation[bundleIdentifier] = .notRunning
                return .notRunning
            }
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.hides = true
            configuration.addsToRecentItems = false
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                if let error {
                    ShellLog.logger.error("Could not launch \(bundleIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            for _ in 0..<40 {
                if isRunning(bundleIdentifier) { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
            didLaunch = true
            // Give the target a moment to install its Apple Event handlers.
            try? await Task.sleep(for: .milliseconds(600))
        }
        let state = await determineAutomation(bundleIdentifier, ask: true)
        automation[bundleIdentifier] = state
        if didLaunch && quitIfLaunched {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
                app.terminate()
            }
        }
        return state
    }

    private func determineAutomation(_ bundleIdentifier: String, ask: Bool) async -> ShellAutomationState {
        let status = await Task.detached(priority: .userInitiated) {
            ShellPermissions.automationStatus(bundleIdentifier: bundleIdentifier, ask: ask)
        }.value
        switch status {
        case 0: return .granted
        case -1743: return .denied // errAEEventNotPermitted
        case -1744: return .notDetermined // errAEEventWouldRequireUserConsent
        case -600: return .notRunning // procNotFound
        default: return .unknown
        }
    }

    /// Blocking: AEDeterminePermissionToAutomateTarget waits for the user's
    /// answer when it prompts, so it always runs off the main thread.
    nonisolated static func automationStatus(bundleIdentifier: String, ask: Bool) -> OSStatus {
        let descriptor = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
        guard let target = descriptor.aeDesc else { return OSStatus(-600) }
        let wildcard: FourCharCode = 0x2A2A_2A2A // '****'
        return AEDeterminePermissionToAutomateTarget(target, wildcard, wildcard, ask)
    }
}

extension Notification.Name {
    /// Posted after the calendar permission prompt is answered.
    static let shellCalendarAccessChanged = Notification.Name("app.foyer.shell.calendarAccessChanged")
}

/// Resumes a continuation exactly once across racing callbacks.
final class ShellOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

private final class ShellLocationDelegate: NSObject, CLLocationManagerDelegate {
    var onChange: (() -> Void)?

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let handler = onChange
        onChange = nil
        Task { @MainActor in ShellPermissions.shared.refresh() }
        handler?()
    }
}

private final class ShellBluetoothDelegate: NSObject, CBCentralManagerDelegate {
    var onChange: (() -> Void)?

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // The first update arrives once the prompt has been answered (or
        // immediately when the permission was already decided).
        guard CBManager.authorization != .notDetermined else { return }
        let handler = onChange
        onChange = nil
        Task { @MainActor in ShellPermissions.shared.refresh() }
        handler?()
    }
}
