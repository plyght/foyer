import AppKit

/// Base notch metrics for a screen (teardown Part E §1, fn 0x100238df8).
struct NotchGeometry: Equatable {
    var closedSize: CGSize
    var expandedSize: CGSize
    var hasHardwareNotch: Bool
    var style: NotchShape.Style

    static let zero = NotchGeometry(closedSize: .zero, expandedSize: .zero, hasHardwareNotch: false, style: .notch)

    /// Real notch: W-L-R × safeTop, expanded max(W-L-R+160, 345) × max(safeTop+142, 175).
    /// No notch + simulation: 140 × (M-1) (24 when M ≤ 0), expanded 345 × 175.
    /// No notch, no simulation: 74 × (M-5.5) (19.5 when M ≤ 0) floating pill, expanded 321 × 175.
    static func compute(for screen: NSScreen, forceSimulated: Bool) -> NotchGeometry {
        let G = Constants.Geometry.self
        let frame = screen.frame
        let menuBar = frame.maxY - screen.visibleFrame.maxY

        if screen.hasHardwareNotch,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = frame.width - left.width - right.width
            let height = screen.safeAreaInsets.top
            return NotchGeometry(
                closedSize: CGSize(width: width, height: height),
                expandedSize: CGSize(width: max(width + G.expandedExtraWidth, G.expandedMinWidth),
                                     height: max(height + G.expandedExtraHeight, G.expandedMinHeight)),
                hasHardwareNotch: true,
                style: .notch)
        }

        if forceSimulated {
            let height = menuBar > 0 ? menuBar - 1 : G.simulatedHeightFallback
            return NotchGeometry(
                closedSize: CGSize(width: G.simulatedWidth, height: height),
                expandedSize: CGSize(width: G.expandedMinWidth, height: G.expandedMinHeight),
                hasHardwareNotch: false,
                style: .notch)
        }

        let height = menuBar > 0 ? menuBar - 5.5 : G.compactFallbackHeightFallback
        return NotchGeometry(
            closedSize: CGSize(width: G.compactFallbackWidth, height: height),
            expandedSize: CGSize(width: G.compactFallbackExpandedWidth, height: G.expandedMinHeight),
            hasHardwareNotch: false,
            style: .pill)
    }
}

extension NSScreen {
    /// Alcove's predicate: safe-area top inset and both auxiliary top areas
    /// present and non-empty. Not a model-name or built-in check.
    var hasHardwareNotch: Bool {
        guard safeAreaInsets.top > 0,
              let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea,
              !left.isEmpty, !right.isEmpty else { return false }
        return true
    }

    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    var displayUUID: String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    var isBuiltIn: Bool { CGDisplayIsBuiltin(displayID) != 0 }

    /// SF Symbol used by the display chooser (macbook / laptopcomputer / display).
    var chooserSymbol: String {
        if hasHardwareNotch { return "macbook" }
        if isBuiltIn { return "laptopcomputer" }
        return "display"
    }
}
