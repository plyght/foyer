import AppKit
import ApplicationServices
import Defaults
import SwiftUI

/// First-run steps (lead §3, Part D §5.1) without Alcove's activation step.
enum OnboardingStep: Int, CaseIterable {
    case music, browser, calendar, bluetooth, accessibility, welcome

    var message: String {
        switch self {
        case .music: return "Foyer needs your permission to control and display your playing music."
        case .browser: return "Foyer needs your permission to identify and focus tabs playing audio."
        case .calendar: return "Foyer needs your permission to show your upcoming events and meetings."
        case .bluetooth: return "Foyer needs your permission to show the battery of your AirPods."
        case .accessibility: return "Foyer needs your permission to hide and replace the system HUDs."
        case .welcome: return ""
        }
    }

    /// The button macOS shows in its own prompt for this step.
    var systemButtonTitle: String {
        switch self {
        case .calendar: return "Allow Full Access"
        case .accessibility: return "Open"
        default: return "Allow"
        }
    }

    var tiles: [OnboardingTile] {
        switch self {
        case .music:
            return [
                OnboardingTile(name: "Music", bundleIdentifier: "com.apple.Music", symbol: "music.note", automates: true),
                OnboardingTile(name: "Spotify", bundleIdentifier: "com.spotify.client", symbol: "dot.radiowaves.right", automates: true),
                OnboardingTile(name: "System", bundleIdentifier: "com.apple.systempreferences", symbol: "gearshape.fill", automates: false),
            ]
        case .browser:
            return [
                OnboardingTile(name: "Safari", bundleIdentifier: "com.apple.Safari", symbol: "safari", automates: true),
                OnboardingTile(name: "Chrome", bundleIdentifier: "com.google.Chrome", symbol: "globe", automates: true),
                OnboardingTile(name: "Dia", bundleIdentifier: "company.thebrowser.dia", symbol: "globe", automates: true),
            ]
        case .calendar:
            return [
                OnboardingTile(name: "Calendar", bundleIdentifier: "com.apple.iCal", symbol: "calendar", automates: false),
                OnboardingTile(name: "Fantastical", bundleIdentifier: "com.flexibits.fantastical2.mac", symbol: "calendar", automates: false),
                OnboardingTile(name: "Notion", bundleIdentifier: "com.cron.electron", symbol: "calendar", automates: false),
            ]
        case .bluetooth:
            return [
                OnboardingTile(name: "AirPods", bundleIdentifier: nil, symbol: "airpods", automates: false),
                OnboardingTile(name: "AirPods Pro", bundleIdentifier: nil, symbol: "airpodspro", automates: false),
                OnboardingTile(name: "AirPods Max", bundleIdentifier: nil, symbol: "airpodsmax", automates: false),
            ]
        case .accessibility, .welcome:
            return []
        }
    }
}

struct OnboardingTile: Identifiable, Hashable {
    let name: String
    let bundleIdentifier: String?
    let symbol: String
    /// Whether tapping it asks for the Automation (Apple Events) permission.
    let automates: Bool

    var id: String { name }
}

@MainActor
final class OnboardingModel: ObservableObject {
    @Published private(set) var step: OnboardingStep = .music
    @Published private(set) var isWorking = false
    @Published private(set) var isWaitingForAccessibility = false
    @Published private(set) var isDismissing = false

    private let onFinish: @MainActor () -> Void
    private var accessibilityTask: Task<Void, Never>?

    init(onFinish: @escaping @MainActor () -> Void) {
        self.onFinish = onFinish
    }

    var buttonTitle: String {
        if step == .welcome { return "Get Started" }
        if isWaitingForAccessibility || isWorking { return "Waiting…" }
        return "Continue"
    }

    // MARK: Actions

    func primaryAction() {
        switch step {
        case .music, .browser:
            guard !isWorking else { return }
            isWorking = true
            let tiles = step.tiles.filter(\.automates)
            Task { @MainActor in
                await self.requestAutomation(for: tiles)
                self.isWorking = false
                self.advance()
            }

        case .calendar:
            guard !isWorking else { return }
            if ShellPermissions.calendarState() != .notDetermined {
                advance()
                return
            }
            isWorking = true
            Task { @MainActor in
                _ = await ShellPermissions.shared.requestAndWait(.calendar)
                self.isWorking = false
                self.advance()
            }

        case .bluetooth:
            guard !isWorking else { return }
            ShellPermissions.shared.refresh()
            if ShellPermissions.shared.state(.bluetooth) != .notDetermined {
                advance()
                return
            }
            isWorking = true
            ShellPermissions.shared.request(.bluetooth)
            Task { @MainActor in
                // Wait for the prompt to be answered (up to a minute).
                for _ in 0..<240 {
                    try? await Task.sleep(for: .milliseconds(250))
                    ShellPermissions.shared.refresh()
                    if ShellPermissions.shared.state(.bluetooth) != .notDetermined { break }
                }
                self.isWorking = false
                self.advance()
            }

        case .accessibility:
            if AXIsProcessTrusted() {
                accessibilityTask?.cancel()
                isWaitingForAccessibility = false
                ShellPermissions.shared.refresh()
                advance()
                return
            }
            if isWaitingForAccessibility {
                // Pressing "Waiting…" again re-opens the Privacy pane.
                ShellPermissions.shared.openSettings(for: .accessibility)
                return
            }
            isWaitingForAccessibility = true
            ShellPermissions.shared.request(.accessibility)
            accessibilityTask?.cancel()
            accessibilityTask = Task { @MainActor in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    if AXIsProcessTrusted() {
                        ShellPermissions.shared.refresh()
                        self.isWaitingForAccessibility = false
                        self.advance()
                        return
                    }
                }
            }

        case .welcome:
            finish()
        }
    }

    /// Skips the Accessibility wait (shown only while waiting).
    func skipAccessibility() {
        accessibilityTask?.cancel()
        isWaitingForAccessibility = false
        advance()
    }

    /// Tapping an app tile asks for its Automation permission right away,
    /// launching it hidden (and quitting it again) when it is not running.
    func tapTile(_ tile: OnboardingTile) {
        guard tile.automates, let bundleIdentifier = tile.bundleIdentifier, !isWorking else { return }
        Task { @MainActor in
            await ShellPermissions.shared.requestAutomation(for: bundleIdentifier, launchIfNeeded: true, quitIfLaunched: true)
        }
    }

    private func requestAutomation(for tiles: [OnboardingTile]) async {
        let permissions = ShellPermissions.shared
        let installed = tiles.compactMap(\.bundleIdentifier).filter { permissions.isInstalled($0) }
        let running = installed.filter { permissions.isRunning($0) }
        if running.isEmpty {
            // Nothing is running: probe the first installed app so the
            // system prompt still appears once, then quit it again.
            if let first = installed.first, permissions.automationState(for: first) != .granted {
                await permissions.requestAutomation(for: first, launchIfNeeded: true, quitIfLaunched: true)
            }
            return
        }
        for bundleIdentifier in running where permissions.automationState(for: bundleIdentifier) != .granted {
            await permissions.requestAutomation(for: bundleIdentifier, launchIfNeeded: false)
        }
    }

    private func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else {
            finish()
            return
        }
        withAnimation(.spring(duration: 0.5, bounce: 0.15)) {
            step = next
        }
    }

    private func finish() {
        guard !isDismissing else { return }
        Defaults[.isFirstLaunch] = false
        withAnimation(.easeIn(duration: 0.25)) {
            isDismissing = true
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(300))
            self.onFinish()
        }
    }
}
