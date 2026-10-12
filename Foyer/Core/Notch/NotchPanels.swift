import AppKit
import Defaults

/// Window level shared by the panels: CGShieldingWindowLevel (above the menu
/// bar and screen saver). Alcove's interactive panel sits one above the backdrop.
enum NotchWindowLevel {
    static var backdrop: NSWindow.Level { NSWindow.Level(rawValue: Int(CGShieldingWindowLevel())) }
    static var notch: NSWindow.Level { NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1) }
    static var lock: NSWindow.Level { NSWindow.Level(rawValue: Int(CGShieldingWindowLevel())) }
}

/// Shared configuration for Foyer's borderless overlay panels (Part A §4):
/// style mask 0x8080, no shadow, clear, unmovable, no animation behaviour,
/// collection behaviour 0x151 (all spaces, stationary, ignores cycle,
/// fullscreen auxiliary).
class OverlayPanel: NSPanel {
    init(contentRect: NSRect, level: NSWindow.Level, visibleWithoutLogin: Bool) {
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
                   backing: .buffered,
                   defer: false)
        hasShadow = false
        backgroundColor = .clear
        isOpaque = false
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        canBecomeVisibleWithoutLogin = visibleWithoutLogin
        // `isFloatingPanel` resets `level` to .floating, so set it first.
        isFloatingPanel = true
        hidesOnDeactivate = false
        self.level = level
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        applySharingType()
    }

    func applySharingType() {
        sharingType = Defaults[.hideFromScreenCapture] ? .none : .readOnly
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Keep the frame exactly where it is placed: AppKit would otherwise push
    /// the panel below the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// The interactive island. Mouse events pass through except over the shape
/// (the view model toggles `ignoresMouseEvents` from cursor tracking).
final class NotchPanel: OverlayPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, level: NotchWindowLevel.notch, visibleWithoutLogin: true)
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
    }
}

/// Backdrop layer below the island: shadow, progressive blur. Never interactive.
final class NotchBackdropPanel: OverlayPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, level: NotchWindowLevel.backdrop, visibleWithoutLogin: false)
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = false
        colorSpace = .extendedSRGB
    }
}

/// Lock-screen overlay panel (used by the Lock feature).
final class LockPanel: OverlayPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, level: NotchWindowLevel.lock, visibleWithoutLogin: true)
        ignoresMouseEvents = false
    }
}
