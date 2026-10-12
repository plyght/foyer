import SwiftUI

/// The island outline (teardown Part A §2).
///
/// `.notch` is flush with the top edge: a body with continuous bottom corners
/// plus two concave "ears" that blend into the menu bar, like a MacBook Pro
/// notch. The rect handed to the shape includes the ears, so the body is
/// `rect.width - 2 * topCornerRadius` wide. The bottom radius is clamped to
/// 24 pt as in Alcove.
///
/// `.pill` is a capsule, used when there is no hardware notch and simulation
/// is off.
struct NotchShape: Shape {
    enum Style: Equatable { case notch, pill }

    var style: Style = .notch
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        switch style {
        case .pill:
            let radius = min(rect.width, rect.height) / 2
            return Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        case .notch:
            return notchPath(in: rect)
        }
    }

    private func notchPath(in rect: CGRect) -> Path {
        let ear = max(0, min(topCornerRadius, rect.width / 4, rect.height / 2))
        let bodyMinX = rect.minX + ear
        let bodyMaxX = rect.maxX - ear
        let bodyWidth = bodyMaxX - bodyMinX
        let r = max(0, min(bottomCornerRadius, Constants.Geometry.maxCornerRadius, bodyWidth / 2, rect.height - ear))
        // Continuous-corner approximation: the curve starts ~1.28r from the
        // corner, like `RoundedCornerStyle.continuous`.
        let k: CGFloat = 1.28 * r
        let c: CGFloat = 0.3 * r

        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Left ear: concave join from the menu bar into the body.
        p.addQuadCurve(to: CGPoint(x: bodyMinX, y: rect.minY + ear),
                       control: CGPoint(x: bodyMinX, y: rect.minY))
        p.addLine(to: CGPoint(x: bodyMinX, y: rect.maxY - k))
        // Bottom-left continuous corner.
        p.addCurve(to: CGPoint(x: bodyMinX + k, y: rect.maxY),
                   control1: CGPoint(x: bodyMinX, y: rect.maxY - c),
                   control2: CGPoint(x: bodyMinX + c, y: rect.maxY))
        p.addLine(to: CGPoint(x: bodyMaxX - k, y: rect.maxY))
        // Bottom-right continuous corner.
        p.addCurve(to: CGPoint(x: bodyMaxX, y: rect.maxY - k),
                   control1: CGPoint(x: bodyMaxX - c, y: rect.maxY),
                   control2: CGPoint(x: bodyMaxX, y: rect.maxY - c))
        p.addLine(to: CGPoint(x: bodyMaxX, y: rect.minY + ear))
        // Right ear.
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: bodyMaxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

#Preview {
    NotchShape(topCornerRadius: 6, bottomCornerRadius: 8)
        .fill(.black)
        .frame(width: 152, height: 28)
        .padding()
}
