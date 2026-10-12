import AppKit
import SwiftUI

/// Borderless, transparent floating window that hosts the onboarding cards
/// near the top centre of the main display.
@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()

    private var window: OnboardingWindow?
    private var model: OnboardingModel?

    private static let windowSize = NSSize(width: 440, height: 500)

    private init() {}

    func show() {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let model = OnboardingModel {
            OnboardingWindowController.shared.close()
        }
        let size = Self.windowSize
        let window = OnboardingWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.title = "Welcome to Foyer"

        let hosting = NSHostingView(rootView: OnboardingRootView(model: model))
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            let origin = NSPoint(
                x: (visible.midX - size.width / 2).rounded(),
                y: (visible.maxY - size.height - 40).rounded()
            )
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }

        self.window = window
        self.model = model
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.orderOut(nil)
        window = nil
        model = nil
    }
}

final class OnboardingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
