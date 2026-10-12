import AppKit
import Defaults
import SwiftUI

/// Owns the lock-screen panels (core `LockPanel`, one per target display) and
/// the private high-level CGS space that keeps them, and the notch panels,
/// above loginwindow while the Mac is locked (Part A §4 `SpaceManager`:
/// `CGSSpaceCreate` → `CGSSpaceSetAbsoluteLevel` → `CGSShowSpaces`, windows
/// moved in with `CGSAddWindowsToSpaces`).
///
/// Each panel is sized to its widget stack (plus a margin) so it never
/// covers loginwindow's avatar or password field, and is bottom-anchored
/// `widgetBottomInset` points above the screen bottom, raised by the user's
/// `nowPlayingWidgetOffset`.
@MainActor
final class LockScreenPresenter {
    private struct Entry {
        let panel: LockPanel
        var contentSize: CGSize
    }

    private var entries: [CGDirectDisplayID: Entry] = [:]
    private var space: SystemCGSSpace?
    private var spacedWindows: [NSWindow] = []
    private(set) var isShowing = false
    private var isInteractive = true

    // MARK: Show / hide

    /// `useSpace: false` keeps the panels in the normal window space; the
    /// private high-level space is only visible over the real lock screen, so
    /// the CI demo shows the widgets without it.
    func show(useSpace: Bool = true) {
        if !isShowing {
            isShowing = true
            buildPanels()
            if useSpace { attachToSpace() }
        } else {
            // Make sure every target display has a panel (displays may have
            // changed while hidden).
            if Set(entries.keys) != Set(NotchWindowManager.targetScreens().map(\.displayID)) {
                rebuild()
            }
        }
    }

    func hide() {
        guard isShowing else { return }
        isShowing = false
        detachFromSpace()
        for entry in entries.values {
            entry.panel.orderOut(nil)
            entry.panel.contentView = nil
        }
        entries.removeAll()
    }

    func rebuildIfShowing() {
        guard isShowing else { return }
        rebuild()
    }

    private func rebuild() {
        detachFromSpace()
        let targets = NotchWindowManager.targetScreens()
        let targetIDs = Set(targets.map(\.displayID))
        for (id, entry) in entries where !targetIDs.contains(id) {
            entry.panel.orderOut(nil)
            entry.panel.contentView = nil
            entries[id] = nil
        }
        buildPanels()
        attachToSpace()
    }

    /// Ignore clicks while the widgets are faded out (idle hide).
    func setInteractive(_ interactive: Bool) {
        isInteractive = interactive
        for entry in entries.values {
            entry.panel.ignoresMouseEvents = !interactive
        }
    }

    // MARK: Panels

    private func buildPanels() {
        for screen in NotchWindowManager.targetScreens() {
            let id = screen.displayID
            if let entry = entries[id] {
                entry.panel.setFrame(Self.panelFrame(contentSize: entry.contentSize, on: screen), display: true)
                continue
            }
            let size = LockScreenConstants.initialContentSize
            let frame = Self.panelFrame(contentSize: size, on: screen)
            let panel = LockPanel(contentRect: frame)
            let root = LockScreenRootView(manager: LockScreenManager.shared, screenID: id)
            let hosting = LockScreenHostingView(rootView: root)
            hosting.sizingOptions = []
            panel.contentView = hosting
            panel.setFrame(frame, display: false)
            panel.ignoresMouseEvents = !isInteractive
            panel.orderFrontRegardless()
            entries[id] = Entry(panel: panel, contentSize: size)
        }
    }

    /// Called by the root view whenever the widget stack's size changes.
    func updateContentSize(_ size: CGSize, for screenID: CGDirectDisplayID) {
        guard var entry = entries[screenID], size.width > 0, size.height > 0 else { return }
        guard abs(entry.contentSize.width - size.width) > 0.5 || abs(entry.contentSize.height - size.height) > 0.5 else {
            return
        }
        entry.contentSize = size
        entries[screenID] = entry
        guard let screen = NSScreen.screens.first(where: { $0.displayID == screenID }) else { return }
        entry.panel.setFrame(Self.panelFrame(contentSize: size, on: screen), display: true)
    }

    static func panelFrame(contentSize: CGSize, on screen: NSScreen) -> CGRect {
        let margin = LockScreenConstants.panelMargin
        let width = ceil(contentSize.width) + 2 * margin
        let height = ceil(contentSize.height) + 2 * margin
        let frame = screen.frame
        var bottom = frame.minY + LockScreenConstants.widgetBottomInset + CGFloat(Defaults[.nowPlayingWidgetOffset]) - margin
        // Stay on screen whatever the offset.
        bottom = min(max(bottom, frame.minY), frame.maxY - height)
        return CGRect(x: (frame.midX - width / 2).rounded(), y: bottom.rounded(), width: width, height: height)
    }

    // MARK: CGS space

    private func attachToSpace() {
        if space == nil {
            space = SystemCGSSpace(level: LockScreenConstants.spaceLevel)
        }
        guard let space else { return }
        var windows: [NSWindow] = entries.values.map { $0.panel }
        // The island itself must also stay above loginwindow while locked.
        for model in NotchWindowManager.shared.allModels {
            if let panel = model.panel { windows.append(panel) }
        }
        for window in windows where window.windowNumber > 0 {
            space.add(window)
        }
        spacedWindows = windows
    }

    private func detachFromSpace() {
        guard let space else {
            spacedWindows.removeAll()
            return
        }
        for window in spacedWindows where window.windowNumber > 0 {
            space.remove(window)
        }
        spacedWindows.removeAll()
        space.destroy()
        self.space = nil
    }
}

/// Hosting view that takes the first click, so the Now Playing widget's
/// buttons respond even though Foyer is never the active app on the lock
/// screen.
private final class LockScreenHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Root of a lock panel: the widget stack bottom-centred in the panel,
/// reporting its size so the panel can hug it.
private struct LockScreenRootView: View {
    @ObservedObject var manager: LockScreenManager
    let screenID: CGDirectDisplayID

    var body: some View {
        let id = screenID
        return LockScreenWidgetStack(manager: manager)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: LockScreenContentSizeKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(LockScreenContentSizeKey.self) { size in
                Task { @MainActor in
                    LockScreenManager.shared.presenter.updateContentSize(size, for: id)
                }
            }
            .padding(LockScreenConstants.panelMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .environment(\.colorScheme, .dark)
    }
}

private struct LockScreenContentSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
