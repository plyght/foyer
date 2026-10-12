import SwiftUI

/// Single-line text that scrolls right-to-left when it overflows: the text is
/// drawn twice with a gap and loops continuously, pausing 1.25 s at the start
/// of each pass, with soft fade edges. Uses the STATIC 30 pt/s constant
/// (Part A §1.2 `NSMarqueeTextView`); Part C's OBSERVED ~330 px/s is noted as a
/// discrepancy in the teardown and not used.
struct NowPlayingMarqueeText: View {
    let text: String
    var font: Font
    var color: Color
    var speed: CGFloat = Constants.Marquee.speed
    var pause: Double = Constants.Marquee.pause
    var gap: CGFloat = Constants.Marquee.gap
    var fadeWidth: CGFloat = 10

    @State private var textSize: CGSize = .zero
    @State private var containerWidth: CGFloat = 0
    @State private var cycleStart = Date()

    private var overflows: Bool { containerWidth > 0 && textSize.width > containerWidth + 0.5 }

    var body: some View {
        // A truncated hidden copy gives the line height and fills the width;
        // a fixed-size hidden copy behind it measures the full text width.
        label
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alignment: .leading) {
                label
                    .fixedSize()
                    .hidden()
                    .background(sizeReader { textSize = $0 })
            }
            .background(sizeReader { containerWidth = $0.width })
            .overlay(alignment: .leading) {
                if overflows {
                    Color.clear
                        .overlay(alignment: .leading) { scrolling }
                        .clipped()
                        .mask(edgeMask)
                        .transition(.opacity.animation(.easeOut(duration: Constants.Marquee.fade)))
                } else {
                    label
                        .transition(.opacity.animation(.easeOut(duration: Constants.Marquee.fade)))
                }
            }
            .onChange(of: text) { _, _ in cycleStart = Date() }
            .onChange(of: overflows) { _, _ in cycleStart = Date() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }

    private var label: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private var scrolling: some View {
        let distance = textSize.width + gap
        let travel = Double(distance / max(speed, 1))
        let period = pause + travel
        return TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(cycleStart).truncatingRemainder(dividingBy: max(period, 0.01))
            let progress = max(0, elapsed - pause) / max(travel, 0.01)
            HStack(spacing: gap) {
                label.fixedSize()
                label.fixedSize()
            }
            .fixedSize()
            .offset(x: -CGFloat(progress) * distance)
        }
    }

    private var edgeMask: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            let fade = min(fadeWidth / width, 0.45)
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: fade),
                .init(color: .black, location: 1 - fade),
                .init(color: .clear, location: 1),
            ], startPoint: .leading, endPoint: .trailing)
        }
    }

    private func sizeReader(_ update: @escaping (CGSize) -> Void) -> some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { update(proxy.size) }
                .onChange(of: proxy.size) { _, newValue in update(newValue) }
        }
    }
}
