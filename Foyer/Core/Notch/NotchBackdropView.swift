import Defaults
import SwiftUI

/// Root view of the `NotchBackdropPanel`: the soft drop shadow under the
/// island (visible on hover and when expanded) and the progressive blur band
/// along the top edge while expanded.
struct NotchBackdropView: View {
    @ObservedObject var model: NotchViewModel
    @Default(.progressiveBlur) private var progressiveBlur

    var body: some View {
        let frame = model.shapeFrame
        let shape = NotchShape(style: model.shapeStyle,
                               topCornerRadius: model.topCornerRadius,
                               bottomCornerRadius: model.bottomCornerRadius)
        let lifted = model.isHovering || model.isExpanded

        ZStack(alignment: .top) {
            Color.clear

            if progressiveBlur && model.isExpanded {
                ProgressiveBlurBand(height: frame.height + 40)
                    .transition(.opacity)
            }

            shape
                .fill(Color.black)
                .frame(width: frame.width, height: frame.height)
                .shadow(color: .black.opacity(lifted ? 0.45 : 0), radius: model.isExpanded ? 18 : 8, y: 4)
                .offset(y: frame.minY)
        }
        .frame(width: Constants.Geometry.panelSize.width, height: Constants.Geometry.panelSize.height, alignment: .top)
        .opacity(model.isHidden ? 0 : 1)
        .animation(Constants.Animations.standard, value: lifted)
    }
}
