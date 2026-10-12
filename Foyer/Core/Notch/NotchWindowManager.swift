import AppKit
import Combine
import Defaults
import SwiftUI

/// Creates and maintains the notch panel pairs (interactive + backdrop), one
/// pair per target display. Panels are fixed 624x320, top-centred, never
/// resized; all states are drawn inside them (Part B §1.1).
@MainActor
final class NotchWindowManager {
    static let shared = NotchWindowManager()

    private struct PanelPair {
        let model: NotchViewModel
        let panel: NotchPanel
        let backdrop: NotchBackdropPanel
    }

    private var pairs: [CGDirectDisplayID: PanelPair] = [:]
    private var monitors: [Any] = []
    private var observers: [Defaults.Observation] = []
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    /// The view model of the main (or first) visible notch.
    var primaryModel: NotchViewModel? {
        if let main = NSScreen.main, let pair = pairs[main.displayID] { return pair.model }
        return pairs.values.first?.model
    }

    func model(for screen: CGDirectDisplayID) -> NotchViewModel? { pairs[screen]?.model }

    var allModels: [NotchViewModel] { pairs.values.map(\.model) }

    func start() {
        rebuild()
        installMonitors()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)

        observers.append(Defaults.observe(keys: .forceSimulatedNotch, .showOnDisplay, .showOnDisplayUUID,
                                          options: []) { [weak self] in
            Task { @MainActor in self?.rebuild() }
        })
        observers.append(Defaults.observe(.hideFromScreenCapture, options: []) { [weak self] _ in
            Task { @MainActor in
                self?.pairs.values.forEach {
                    $0.panel.applySharingType()
                    $0.backdrop.applySharingType()
                }
            }
        })
    }

    // MARK: Target screens

    /// Screens selected by Settings › General › Display.
    static func targetScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        switch Defaults[.showOnDisplay] {
        case .allDisplays:
            return screens
        case .builtInDisplay:
            return screens.first(where: \.isBuiltIn).map { [$0] } ?? NSScreen.main.map { [$0] } ?? []
        case .specificDisplay:
            // A missing specific display shows nothing until it returns (Part G §14).
            if let uuid = Defaults[.showOnDisplayUUID], let match = screens.first(where: { $0.displayUUID == uuid }) {
                return [match]
            }
            return []
        case .mainScreen:
            // Prefer the notched built-in screen, like Alcove's "Main display".
            if let notched = screens.first(where: \.hasHardwareNotch) { return [notched] }
            return NSScreen.main.map { [$0] } ?? []
        }
    }

    func rebuild() {
        let targets = Self.targetScreens()
        let targetIDs = Set(targets.map(\.displayID))

        for (id, pair) in pairs where !targetIDs.contains(id) {
            pair.panel.orderOut(nil)
            pair.backdrop.orderOut(nil)
            pairs[id] = nil
        }

        for screen in targets {
            let frame = Self.panelFrame(on: screen)
            if let pair = pairs[screen.displayID] {
                pair.model.updateGeometry(for: screen)
                pair.model.panelFrame = frame
                pair.panel.setFrame(frame, display: false)
                pair.backdrop.setFrame(frame, display: false)
                continue
            }

            let model = NotchViewModel(screenID: screen.displayID)
            model.updateGeometry(for: screen)
            model.panelFrame = frame

            let backdrop = NotchBackdropPanel(contentRect: frame)
            backdrop.contentView = NSHostingView(rootView: NotchBackdropView(model: model))
            backdrop.setFrame(frame, display: false)

            let panel = NotchPanel(contentRect: frame)
            let hosting = NotchHostingView(rootView: NotchView(model: model))
            hosting.model = model
            panel.contentView = hosting
            panel.setFrame(frame, display: false)
            model.panel = panel

            backdrop.orderFrontRegardless()
            panel.orderFrontRegardless()
            pairs[screen.displayID] = PanelPair(model: model, panel: panel, backdrop: backdrop)
        }
    }

    static func panelFrame(on screen: NSScreen) -> CGRect {
        let size = Constants.Geometry.panelSize
        let f = screen.frame
        return CGRect(x: f.midX - size.width / 2, y: f.maxY - size.height, width: size.width, height: size.height)
    }

    // MARK: Event monitors

    private func installMonitors() {
        let moveMask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: moveMask, handler: { [weak self] _ in
            Task { @MainActor in self?.mouseMoved() }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: moveMask, handler: { [weak self] event in
            Task { @MainActor in self?.mouseMoved() }
            return event
        }) { monitors.append(m) }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            Task { @MainActor in
                let point = NSEvent.mouseLocation
                self?.pairs.values.forEach { $0.model.mouseDownOutside(at: point) }
            }
        }) { monitors.append(m) }

        // Swipes reach us only while the cursor is over a notch (the panel
        // accepts mouse events then).
        if let m = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            guard let self, let window = event.window as? NotchPanel,
                  let pair = self.pairs.values.first(where: { $0.panel === window }) else { return event }
            pair.model.handleScroll(event)
            return nil
        }) { monitors.append(m) }
    }

    private func mouseMoved() {
        let point = NSEvent.mouseLocation
        for pair in pairs.values { pair.model.mouseMoved(to: point) }
    }
}

/// Hosting view that accepts the first click so a tap on the inactive
/// (non-activating) panel reaches SwiftUI immediately.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    weak var model: NotchViewModel?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
