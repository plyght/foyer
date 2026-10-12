import AppKit
import CoreGraphics
import Defaults
import IOKit.pwr_mgt
import SwiftUI

/// Lock-screen state machine (Alcove's `LockManager`, Part E §4).
///
/// Sources:
/// - distributed notifications `com.apple.screenIsLocked` / `…IsUnlocked`,
///   `com.apple.screenLockUIIsShown` / `…IsHidden`,
///   `com.apple.screensaver.didstart` / `…didstop`;
/// - workspace `screensDidSleep` / `screensDidWake`;
/// - polling `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]`.
///
/// Effects: `NotchController.shared.isScreenLocked`, the `lock.fill` live
/// activity in the notch (216 wide), the lock-screen widget panels, lock and
/// unlock sounds, keep-awake power assertions and the idle hide.
@MainActor
final class LockScreenManager: ObservableObject {
    static let shared = LockScreenManager()

    @Published private(set) var isLocked = false
    @Published private(set) var isScreenSaverRunning = false
    @Published private(set) var isDisplayAsleep = false
    /// Widgets faded out after `hideIdleDuration` minutes without input.
    @Published private(set) var isIdleHidden = false
    /// Drives the widget fade/scale.
    @Published private(set) var widgetsVisible = false

    let presenter = LockScreenPresenter()

    private var isStarted = false
    private var distributedObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var centerObservers: [NSObjectProtocol] = []
    private var defaultsObservations: [Defaults.Observation] = []
    private var pollTimer: Timer?
    private var idleTimer: Timer?
    private var pollDisagreements = 0
    private var presentTask: Task<Void, Never>?
    private var keepAwakeTask: Task<Void, Never>?
    private var assertionIDs: [IOPMAssertionID] = []
    private var appliedScreenSaverHide = false
    private var appliedLockedHide = false

    private init() {}

    // MARK: Lifecycle

    func start() {
        guard !isStarted else { return }
        isStarted = true
        installObservers()

        let poll = Timer(timeInterval: LockScreenConstants.pollInterval, repeats: true) { _ in
            Task { @MainActor in LockScreenManager.shared.pollSession() }
        }
        poll.tolerance = 0.2
        RunLoop.main.add(poll, forMode: .common)
        pollTimer = poll

        // Resynchronise with the session at launch (Alcove does the same).
        if Self.sessionIsLocked() {
            setLocked(true, playSound: false)
        }
        refreshPresentation()
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false

        pollTimer?.invalidate()
        pollTimer = nil
        stopIdleTimer()
        presentTask?.cancel()
        presentTask = nil

        let distributed = DistributedNotificationCenter.default()
        distributedObservers.forEach { distributed.removeObserver($0) }
        distributedObservers.removeAll()
        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspace.removeObserver($0) }
        workspaceObservers.removeAll()
        centerObservers.forEach { NotificationCenter.default.removeObserver($0) }
        centerObservers.removeAll()
        defaultsObservations.forEach { $0.invalidate() }
        defaultsObservations.removeAll()

        endKeepAwake()
        widgetsVisible = false
        presenter.hide()
        NotchController.shared.removeActivity(.lock)
        if appliedScreenSaverHide {
            NotchController.shared.setHidden(false, reason: .screenSaver)
            appliedScreenSaverHide = false
        }
        if appliedLockedHide {
            NotchController.shared.setHidden(false, reason: .locked)
            appliedLockedHide = false
        }
    }

    private func installObservers() {
        let distributed = DistributedNotificationCenter.default()
        func observe(_ name: String, _ handler: @escaping @MainActor @Sendable () -> Void) {
            let token = distributed.addObserver(forName: NSNotification.Name(name), object: nil, queue: .main) { _ in
                Task { @MainActor in handler() }
            }
            distributedObservers.append(token)
        }

        observe("com.apple.screenIsLocked") {
            LockScreenManager.shared.setLocked(true, playSound: true)
        }
        observe("com.apple.screenIsUnlocked") {
            LockScreenManager.shared.setLocked(false, playSound: true)
        }
        // The lock UI appearing is a lock in every case Alcove handles.
        observe("com.apple.screenLockUIIsShown") {
            LockScreenManager.shared.setLocked(true, playSound: true)
        }
        // The lock UI also hides while the session stays locked (display
        // sleep, screen saver), so only the session dictionary decides.
        observe("com.apple.screenLockUIIsHidden") {
            LockScreenManager.shared.resyncWithSession()
        }
        observe("com.apple.screensaver.didstart") {
            LockScreenManager.shared.setScreenSaverRunning(true)
        }
        observe("com.apple.screensaver.didstop") {
            LockScreenManager.shared.setScreenSaverRunning(false)
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                                        object: nil, queue: .main) { _ in
            Task { @MainActor in LockScreenManager.shared.setDisplayAsleep(true) }
        })
        workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                                        object: nil, queue: .main) { _ in
            Task { @MainActor in
                LockScreenManager.shared.setDisplayAsleep(false)
                LockScreenManager.shared.resyncWithSession()
            }
        })

        centerObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in LockScreenManager.shared.presenter.rebuildIfShowing() }
        })

        defaultsObservations.append(Defaults.observe(keys: .enableLockScreen, .showOnScreenSaver, .hideIdleDuration,
                                                     options: []) {
            Task { @MainActor in LockScreenManager.shared.settingsChanged() }
        })
        defaultsObservations.append(Defaults.observe(keys: .nowPlayingWidgetOffset, .showOnDisplay, .showOnDisplayUUID,
                                                     options: []) {
            Task { @MainActor in LockScreenManager.shared.presenter.rebuildIfShowing() }
        })
        defaultsObservations.append(Defaults.observe(.keepAwake, options: []) { _ in
            Task { @MainActor in
                let manager = LockScreenManager.shared
                if manager.isLocked { manager.beginKeepAwake() }
            }
        })
    }

    // MARK: Session polling

    /// Whether the login session reports the screen as locked.
    static func sessionIsLocked() -> Bool {
        guard let dictionary = CGSessionCopyCurrentDictionary() else { return false }
        let info = dictionary as NSDictionary
        guard let value = info[LockScreenConstants.sessionLockedKey] else { return false }
        if let number = value as? NSNumber { return number.boolValue }
        if let flag = value as? Bool { return flag }
        return false
    }

    private func pollSession() {
        let locked = Self.sessionIsLocked()
        if locked == isLocked {
            pollDisagreements = 0
            return
        }
        pollDisagreements += 1
        if pollDisagreements >= LockScreenConstants.pollDebounceCount {
            pollDisagreements = 0
            setLocked(locked, playSound: true)
        }
    }

    private func resyncWithSession() {
        pollDisagreements = 0
        setLocked(Self.sessionIsLocked(), playSound: true)
    }

    // MARK: State changes

    private func setLocked(_ locked: Bool, playSound: Bool) {
        pollDisagreements = 0
        guard locked != isLocked else { return }
        isLocked = locked
        NotchController.shared.isScreenLocked = locked
        let enabled = Defaults[.enableLockScreen]

        if locked {
            isIdleHidden = false
            if enabled && playSound && Defaults[.playSoundOnLock] {
                SoundPlayer.play(.lock)
            }
            if enabled {
                showLockActivity()
            }
            beginKeepAwake()
        } else {
            if enabled && playSound && Defaults[.playSoundOnUnlock] {
                SoundPlayer.play(.unlock)
            }
            NotchController.shared.removeActivity(.lock)
            endKeepAwake()
            isIdleHidden = false
        }
        refreshPresentation()
    }

    private func setScreenSaverRunning(_ running: Bool) {
        guard running != isScreenSaverRunning else { return }
        isScreenSaverRunning = running
        if running { isIdleHidden = false }
        refreshPresentation()
        if !running {
            // The screen saver often hands over to the lock screen.
            resyncWithSession()
        }
    }

    private func setDisplayAsleep(_ asleep: Bool) {
        guard asleep != isDisplayAsleep else { return }
        isDisplayAsleep = asleep
        if !asleep { isIdleHidden = false }
        refreshPresentation()
    }

    private func settingsChanged() {
        if isLocked {
            if Defaults[.enableLockScreen] {
                showLockActivity()
            } else {
                NotchController.shared.removeActivity(.lock)
            }
        }
        refreshIdleState()
        refreshPresentation()
    }

    private func showLockActivity() {
        let activity = LiveActivity(id: .lock,
                                    wingWidth: LockScreenConstants.lockWing,
                                    priority: LockScreenConstants.lockActivityPriority,
                                    leading: AnyView(LockScreenNotchGlyph()),
                                    trailing: AnyView(Color.clear))
        NotchController.shared.undismiss(.lock)
        NotchController.shared.setActivity(activity)
        NotchController.shared.touchActivity(.lock)
    }

    // MARK: Presentation

    /// Whether the widget panels should be on screen at all.
    private var wantsPanels: Bool {
        guard Defaults[.enableLockScreen] else { return false }
        if isScreenSaverRunning {
            return Defaults[.showOnScreenSaver]
        }
        return isLocked
    }

    private func refreshPresentation() {
        let controller = NotchController.shared

        // The notch disappears under the screen saver unless the user asked
        // for it there (OBSERVED: no notch while ScreenSaverEngine runs).
        let hideForSaver = isScreenSaverRunning && !Defaults[.showOnScreenSaver]
        if hideForSaver != appliedScreenSaverHide {
            appliedScreenSaverHide = hideForSaver
            controller.setHidden(hideForSaver, reason: .screenSaver)
        }
        // With the lock-screen feature off, the notch stays off the lock screen.
        let hideForLock = isLocked && !Defaults[.enableLockScreen]
        if hideForLock != appliedLockedHide {
            appliedLockedHide = hideForLock
            controller.setHidden(hideForLock, reason: .locked)
        }

        let panels = wantsPanels
        let widgets = panels && !isIdleHidden && !isDisplayAsleep

        if panels {
            startIdleTimer()
        } else {
            stopIdleTimer()
        }

        presentTask?.cancel()
        if widgets {
            let freshlyShown = !presenter.isShowing
            presenter.show()
            presenter.setInteractive(true)
            guard !widgetsVisible else { return }
            presentTask = Task { @MainActor in
                if freshlyShown {
                    // The lock screen appears first; the widget follows ~0.4 s later.
                    try? await Task.sleep(for: .seconds(LockScreenConstants.widgetAppearDelay))
                    guard !Task.isCancelled else { return }
                }
                withAnimation(LockScreenConstants.widgetFade) {
                    LockScreenManager.shared.widgetsVisible = true
                }
            }
        } else {
            presenter.setInteractive(false)
            if widgetsVisible {
                withAnimation(LockScreenConstants.widgetFade) { widgetsVisible = false }
            }
            guard !panels, presenter.isShowing else { return }
            presentTask = Task { @MainActor in
                // Let the ~150 ms fade finish before the panels leave.
                try? await Task.sleep(for: .seconds(LockScreenConstants.widgetFadeDuration + 0.05))
                guard !Task.isCancelled else { return }
                LockScreenManager.shared.presenter.hide()
            }
        }
    }

    // MARK: Idle hide

    private func startIdleTimer() {
        guard idleTimer == nil else { return }
        let timer = Timer(timeInterval: LockScreenConstants.idleCheckInterval, repeats: true) { _ in
            Task { @MainActor in LockScreenManager.shared.refreshIdleState() }
        }
        timer.tolerance = 0.25
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func stopIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    private func refreshIdleState() {
        let minutes = Defaults[.hideIdleDuration]
        let hidden: Bool
        if minutes > 0, wantsPanels {
            hidden = Self.secondsSinceLastInput() >= minutes * 60
        } else {
            hidden = false
        }
        guard hidden != isIdleHidden else { return }
        isIdleHidden = hidden
        refreshPresentation()
    }

    /// Seconds since the last keyboard, mouse or trackpad input.
    static func secondsSinceLastInput() -> Double {
        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
            .leftMouseDragged, .scrollWheel, .keyDown, .flagsChanged,
        ]
        var shortest = Double.greatestFiniteMagnitude
        for type in types {
            let seconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
            if seconds < shortest { shortest = seconds }
        }
        return shortest == .greatestFiniteMagnitude ? 0 : shortest
    }

    // MARK: Keep awake

    /// Holds the display awake for `keepAwake` minutes after locking.
    func beginKeepAwake() {
        endKeepAwake()
        let minutes = Defaults[.keepAwake]
        guard minutes > 0, isLocked, Defaults[.enableLockScreen] else { return }

        let name = LockScreenConstants.keepAwakeAssertionName as CFString
        for type in LockScreenConstants.keepAwakeAssertionTypes {
            var id: IOPMAssertionID = 0
            let result = IOPMAssertionCreateWithName(type as CFString,
                                                     IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                     name,
                                                     &id)
            if result == kIOReturnSuccess {
                assertionIDs.append(id)
            }
        }

        keepAwakeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            LockScreenManager.shared.releaseAssertions()
        }
    }

    func endKeepAwake() {
        keepAwakeTask?.cancel()
        keepAwakeTask = nil
        releaseAssertions()
    }

    private func releaseAssertions() {
        for id in assertionIDs {
            IOPMAssertionRelease(id)
        }
        assertionIDs.removeAll()
    }
}

/// White `lock.fill` glyph in the left wing while locked (Part D §4).
struct LockScreenNotchGlyph: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: LockScreenConstants.lockGlyphSize, weight: .semibold))
            .foregroundStyle(.white)
            .accessibilityLabel(Text("Locked"))
    }
}
