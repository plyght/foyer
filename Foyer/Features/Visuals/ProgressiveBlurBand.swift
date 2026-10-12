import AppKit
import SwiftUI

/// The progressive (variable) blur drawn along the top edge of the screen
/// behind the expanded island (Part A §6 `ProgressiveBlurView` /
/// `VariableBlurEngine`, `progressiveBlur` key). The blur is strongest at the
/// top edge and fades to nothing at the bottom of the band; it spans the full
/// width of the 624 pt backdrop panel with feathered ends.
///
/// Implementation: a behind-window `NSVisualEffectView` whose backdrop layer
/// gets Core Animation's `variableBlur` filter (resolved at runtime, like
/// Alcove's `VariableBlurEngine.filter: NSObject?`) driven by a gradient mask.
/// When that filter is unavailable the effect view is simply faded out with
/// the same gradient through its public `maskImage`, which still reads as a
/// soft progressive blur.
struct ProgressiveBlurBand: View {
    let height: CGFloat

    init(height: CGFloat) {
        self.height = height
    }

    var body: some View {
        VisualsProgressiveBlurRepresentable(maxRadius: VisualsConstants.progressiveBlurMaxRadius)
            .frame(maxWidth: .infinity)
            .frame(height: max(height, 0))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct VisualsProgressiveBlurRepresentable: NSViewRepresentable {
    let maxRadius: CGFloat

    func makeNSView(context: Context) -> VisualsVariableBlurView {
        let view = VisualsVariableBlurView(frame: .zero)
        view.maxRadius = maxRadius
        return view
    }

    func updateNSView(_ nsView: VisualsVariableBlurView, context: Context) {
        if nsView.maxRadius != maxRadius {
            nsView.maxRadius = maxRadius
        }
    }
}

/// Behind-window effect view with a top-to-bottom variable blur.
final class VisualsVariableBlurView: NSVisualEffectView {
    var maxRadius: CGFloat = VisualsConstants.progressiveBlurMaxRadius {
        didSet { invalidateBlur() }
    }

    private var lastSize: CGSize = .zero
    private var maskCGImage: CGImage?
    private weak var backdropLayer: CALayer?
    private var appliedFilter: NSObject?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        wantsLayer = true
        material = .hudWindow
        blendingMode = .behindWindow
        // The app is an inactive agent; keep the material live regardless.
        state = .active
        isEmphasized = false
        appearance = NSAppearance(named: .darkAqua)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        invalidateBlur()
    }

    override func layout() {
        super.layout()
        refresh()
    }

    private func invalidateBlur() {
        lastSize = .zero
        appliedFilter = nil
        needsLayout = true
    }

    private func refresh() {
        let size = bounds.size
        guard size.width >= 1, size.height >= 1 else { return }

        if abs(size.width - lastSize.width) > 0.5 || abs(size.height - lastSize.height) > 0.5 || maskCGImage == nil {
            lastSize = size
            maskCGImage = VisualsBlurMask.make(size: size)
            appliedFilter = nil
            if let cg = maskCGImage {
                maskImage = NSImage(cgImage: cg, size: size)
            } else {
                maskImage = nil
            }
        }
        applyVariableBlurIfPossible()
    }

    /// Swaps the backdrop layer's gaussian blur for a mask-driven variable blur.
    private func applyVariableBlurIfPossible() {
        guard let mask = maskCGImage, let rootLayer = layer else { return }
        let backdrop: CALayer
        if let cached = backdropLayer, cached.superlayer != nil {
            backdrop = cached
        } else if let found = Self.findBackdropLayer(in: rootLayer) {
            backdropLayer = found
            backdrop = found
        } else {
            return
        }

        // Already ours and still installed.
        if let applied = appliedFilter, let current = backdrop.filters, current.count == 1,
           let first = current.first as AnyObject?, first === applied {
            return
        }

        guard let filter = VisualsVariableBlurFilter.make(radius: maxRadius, mask: mask) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.filters = [filter]
        CATransaction.commit()
        appliedFilter = filter
    }

    private static func findBackdropLayer(in layer: CALayer) -> CALayer? {
        let name = String(describing: type(of: layer))
        if name.contains("Backdrop") { return layer }
        for sub in layer.sublayers ?? [] {
            if let found = findBackdropLayer(in: sub) { return found }
        }
        return nil
    }
}

/// Runtime access to Core Animation's private `CAFilter` "variableBlur".
/// Returns nil (and the view falls back to the alpha mask) whenever the class
/// or selector is missing.
private enum VisualsVariableBlurFilter {
    static func make(radius: CGFloat, mask: CGImage) -> NSObject? {
        guard let filterClass = NSClassFromString("CAFilter") as? NSObject.Type else { return nil }
        let selector = NSSelectorFromString("filterWithType:")
        guard filterClass.responds(to: selector) else { return nil }
        guard let unmanaged = filterClass.perform(selector, with: "variableBlur") else { return nil }
        guard let filter = unmanaged.takeUnretainedValue() as? NSObject else { return nil }
        filter.setValue(radius, forKey: "inputRadius")
        filter.setValue(mask, forKey: "inputMaskImage")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        return filter
    }
}

/// Builds the band's mask: opaque at the top edge fading to clear at the
/// bottom, with feathered left/right ends.
enum VisualsBlurMask {
    static func make(size: CGSize) -> CGImage? {
        let width = max(Int(size.width.rounded(.up)), 1)
        let height = max(Int(size.height.rounded(.up)), 1)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let w = CGFloat(width)
        let h = CGFloat(height)

        // Vertical ramp. Core Graphics' origin is bottom-left, so the top edge
        // of the band is y = h.
        let stops = VisualsConstants.progressiveBlurStops
        let colors = stops.map { CGColor(gray: 0, alpha: $0.strength) } as CFArray
        var locations = stops.map { $0.location }
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: &locations) {
            context.drawLinearGradient(gradient,
                                       start: CGPoint(x: 0, y: h),
                                       end: CGPoint(x: 0, y: 0),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }

        // Horizontal feather (multiplies the existing alpha).
        let feather = min(max(VisualsConstants.progressiveBlurSideFeather, 0), 0.5)
        if feather > 0 {
            let sideColors = [
                CGColor(gray: 0, alpha: 0),
                CGColor(gray: 0, alpha: 1),
                CGColor(gray: 0, alpha: 1),
                CGColor(gray: 0, alpha: 0),
            ] as CFArray
            var sideLocations: [CGFloat] = [0, feather, 1 - feather, 1]
            if let side = CGGradient(colorsSpace: space, colors: sideColors, locations: &sideLocations) {
                context.setBlendMode(.destinationIn)
                context.drawLinearGradient(side,
                                           start: CGPoint(x: 0, y: 0),
                                           end: CGPoint(x: w, y: 0),
                                           options: [])
            }
        }
        return context.makeImage()
    }
}
