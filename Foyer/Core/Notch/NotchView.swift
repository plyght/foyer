import Defaults
import SwiftUI

/// Root view of a `NotchPanel`. Draws the island top-centred in the fixed
/// 624x320 panel and swaps content by presentation state.
struct NotchView: View {
    @ObservedObject var model: NotchViewModel
    @Default(.contrastOutline) private var contrastOutline

    var body: some View {
        let frame = model.shapeFrame
        let shape = NotchShape(style: model.shapeStyle,
                               topCornerRadius: model.topCornerRadius,
                               bottomCornerRadius: model.bottomCornerRadius)

        ZStack(alignment: .top) {
            Color.clear

            ZStack(alignment: .top) {
                shape.fill(Color.black)

                content
                    .padding(.horizontal, model.shapeStyle == .notch ? model.topCornerRadius : 0)
                    .frame(width: frame.width, height: frame.height, alignment: .top)
                    .clipShape(shape)

                if contrastOutline && model.controller.backdropIsDark {
                    ContrastOutline(shape: shape)
                }
            }
            .frame(width: frame.width, height: frame.height)
            .contentShape(shape)
            .onTapGesture { model.tap() }
            .offset(y: frame.minY)
        }
        .frame(width: Constants.Geometry.panelSize.width, height: Constants.Geometry.panelSize.height, alignment: .top)
        .opacity(model.isHidden ? 0 : 1)
        .environment(\.notchGeometry, model.geometry)
        .environment(\.notchViewModel, model)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var content: some View {
        switch model.presentation {
        case .expanded:
            if let page = model.currentPage {
                page.content
                    .id(page.id)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .opacity(model.expandedContentVisible ? 1 : 0)
                    .blur(radius: model.expandedContentVisible ? 0 : 8)
                    .transition(.opacity)
            }
        case .notification:
            if let n = model.controller.notification {
                WingsLayout(notchWidth: model.geometry.closedSize.width,
                            notchHeight: model.geometry.closedSize.height,
                            leading: n.leading, trailing: n.trailing, extra: n.body)
                    .id(n.kind)
                    .transition(.blurFade)
            }
        case .peek:
            if let p = model.controller.quickPeek {
                p.content
                    .id(p.id)
                    .transition(.blurFade)
            }
        case .activity:
            if let a = model.controller.visibleActivity {
                WingsLayout(notchWidth: model.geometry.closedSize.width,
                            notchHeight: model.geometry.closedSize.height,
                            leading: a.leading, trailing: a.trailing, extra: nil)
                    .id(a.id)
                    .transition(.blurFade)
            }
        case .closed:
            EmptyView()
        }

        if let glyph = model.controller.skipGlyph, !model.isExpanded {
            SkipGlyph(direction: glyph)
                .transition(.opacity)
        }
    }
}

/// Lays content out in the two wings beside the physical notch.
struct WingsLayout: View {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    let leading: AnyView
    let trailing: AnyView
    let extra: AnyView?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                leading
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Color.clear.frame(width: notchWidth)
                trailing
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: notchHeight)
            if let extra {
                extra.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// ⏮ / ⏭ flashed at the notch edge after a horizontal swipe (≈0.3-0.5 s).
private struct SkipGlyph: View {
    let direction: SkipDirection

    var body: some View {
        HStack {
            if direction == .next { Spacer() }
            Image(systemName: direction == .next ? "forward.fill" : "backward.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10)
            if direction == .previous { Spacer() }
        }
        .frame(maxHeight: .infinity)
    }
}

/// ~1.5 px white outline at ~9 % alpha, shown over dark backdrops so the black
/// island stays legible (Part D §6).
struct ContrastOutline: View {
    let shape: NotchShape

    var body: some View {
        shape
            .stroke(Color.white.opacity(Constants.Geometry.outlineOpacity),
                    lineWidth: Constants.Geometry.outlineWidth)
            .allowsHitTesting(false)
    }
}

extension AnyTransition {
    /// Content enters with a blur + fade (lagging the shape by ~100 ms) and
    /// leaves faster than the shape contracts.
    static var blurFade: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: BlurFadeModifier(progress: 0), identity: BlurFadeModifier(progress: 1))
                .animation(Constants.Animations.fade.delay(Constants.Animations.contentDelay)),
            removal: .modifier(active: BlurFadeModifier(progress: 0), identity: BlurFadeModifier(progress: 1))
                .animation(Constants.Animations.fadeFast))
    }
}

private struct BlurFadeModifier: ViewModifier {
    let progress: Double
    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .blur(radius: (1 - progress) * 6)
            .scaleEffect(0.96 + 0.04 * progress)
    }
}

// MARK: Environment

private struct NotchGeometryKey: EnvironmentKey {
    static let defaultValue: NotchGeometry = .zero
}

private struct NotchViewModelKey: EnvironmentKey {
    static let defaultValue: NotchViewModel? = nil
}

extension EnvironmentValues {
    /// Base metrics of the notch the view is drawn in.
    var notchGeometry: NotchGeometry {
        get { self[NotchGeometryKey.self] }
        set { self[NotchGeometryKey.self] = newValue }
    }

    /// The view model of the notch the view is drawn in (for open/close).
    var notchViewModel: NotchViewModel? {
        get { self[NotchViewModelKey.self] }
        set { self[NotchViewModelKey.self] = newValue }
    }
}
