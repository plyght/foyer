import AVFoundation
import AppKit
import Defaults
import SwiftUI

// MARK: Device glyph

/// The device artwork. "3D models" plays Alcove's own AirPods clip from a
/// locally installed Alcove.app (looping, muted, 6.000 s) when available,
/// otherwise an original turntable animation of the SF Symbol; "Symbols"
/// is the static SF Symbol.
@MainActor
struct SystemDeviceGlyph: View {
    let kind: SystemDeviceKind
    var size: CGFloat
    var style: ConnectivityModel
    /// The clips have an opaque black background: only use them on the black island.
    var allowsVideo: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .frame(width: size, height: size)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: kind.airPodsModel?.displayName ?? "Bluetooth device"))
    }

    @ViewBuilder
    private var content: some View {
        if style == .threeDimensional && kind.supportsModelAnimation && !reduceMotion {
            if allowsVideo, let url = videoURL {
                SystemLoopingVideoView(url: url)
                    // The model fills ~60 % of the 96×96 clip; enlarge and clip.
                    .frame(width: size * 1.4, height: size * 1.4)
                    .frame(width: size, height: size)
                    .clipped()
            } else {
                SystemTurntableSymbol(symbol: kind.symbolName, tint: kind.tint, size: size)
            }
        } else {
            SystemStaticDeviceSymbol(symbol: kind.symbolName, tint: kind.tint, size: size)
        }
    }

    private var videoURL: URL? {
        guard let name = kind.videoResourceName else { return nil }
        return AlcoveAssets.video(named: name)
    }
}

struct SystemStaticDeviceSymbol: View {
    let symbol: String
    let tint: Color
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.8, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
    }
}

/// Original "3D" presentation: a gentle Y-axis turntable sway and a light
/// sweep, one cycle every 6.0 s (the length of Alcove's clips).
struct SystemTurntableSymbol: View {
    let symbol: String
    let tint: Color
    let size: CGFloat

    var body: some View {
        TimelineView(.animation) { context in
            turntableFrame(at: context.date)
        }
        .frame(width: size, height: size)
    }

    private func symbolImage() -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.8, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .frame(width: size, height: size)
    }

    private func turntableFrame(at date: Date) -> some View {
        let loop = SystemConstants.Connectivity.modelLoop
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loop) / loop
        let angle = sin(phase * 2 * Double.pi) * 28
        let bob = CGFloat(sin(phase * 4 * Double.pi)) * size * 0.03
        // The sweep crosses during the first 40 % of each loop.
        let sweep = CGFloat(min(max((phase - 0.05) / 0.4, 0), 1))
        let band = LinearGradient(colors: [Color.white.opacity(0), Color.white.opacity(0.75), Color.white.opacity(0)],
                                  startPoint: .leading, endPoint: .trailing)

        return ZStack {
            symbolImage()
                .foregroundStyle(tint)
            band
                .frame(width: size * 0.45, height: size)
                .offset(x: (sweep * 2 - 1) * size)
                .frame(width: size, height: size)
                .clipped()
                .mask { symbolImage() }
                .blendMode(.plusLighter)
        }
        .frame(width: size, height: size)
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        .offset(y: bob)
    }
}

// MARK: Looping video (Alcove.app clips, never bundled)

struct SystemLoopingVideoView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> SystemLoopingVideoNSView {
        let view = SystemLoopingVideoNSView(frame: .zero)
        view.load(url)
        return view
    }

    func updateNSView(_ nsView: SystemLoopingVideoNSView, context: Context) {
        nsView.load(url)
    }

    static func dismantleNSView(_ nsView: SystemLoopingVideoNSView, coordinator: ()) {
        nsView.stop()
    }
}

/// AVQueuePlayer + AVPlayerLooper in an AVPlayerLayer, muted.
final class SystemLoopingVideoNSView: NSView {
    private let player = AVQueuePlayer()
    private let playerLayer = AVPlayerLayer()
    private var looper: AVPlayerLooper?
    private var currentURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.actionAtItemEnd = .advance
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = NSColor.clear.cgColor
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func load(_ url: URL) {
        guard url != currentURL else { return }
        currentURL = url
        looper?.disableLooping()
        player.removeAllItems()
        let item = AVPlayerItem(url: url)
        looper = AVPlayerLooper(player: player, templateItem: item)
        if window != nil { player.play() }
    }

    func stop() {
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        currentURL = nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            player.pause()
        } else {
            player.play()
        }
    }
}

// MARK: Battery ring

struct SystemBatteryRing: View {
    let percent: Int
    let tint: Color
    var size: CGFloat = SystemConstants.Connectivity.ringSize
    var lineWidth: CGFloat = SystemConstants.Connectivity.ringLineWidth

    var body: some View {
        let fraction = CGFloat(min(max(percent, 0), 100)) / 100
        ZStack {
            Circle()
                .stroke(tint.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(Constants.Animations.standard, value: percent)
    }
}

/// Green above the connected-device threshold, red at or below it.
private func systemConnectivityTint(_ level: Int, threshold: Double) -> Color {
    Double(level) <= threshold ? Constants.Battery.low : Constants.Battery.charging
}

// MARK: Notification wings

/// Leading wing: the device artwork.
@MainActor
struct SystemConnectivityNotificationLeading: View {
    let event: SystemConnectivityEvent
    @ObservedObject private var manager = SystemConnectivityManager.shared
    @Default(.connectivityModel) private var model
    @Environment(\.notchGeometry) private var geometry

    var body: some View {
        let device = manager.device(event.device.id) ?? event.device
        let height = geometry.closedSize.height > 0 ? geometry.closedSize.height : 32
        let size = max(16, min(height - 6, 28))
        SystemDeviceGlyph(kind: device.kind, size: size, style: model)
            .opacity(event.kind == .disconnected ? 0.55 : 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, 6)
    }
}

/// Trailing wing: battery percentage + ring, or the connection state.
@MainActor
struct SystemConnectivityNotificationTrailing: View {
    let event: SystemConnectivityEvent
    @ObservedObject private var manager = SystemConnectivityManager.shared
    @Default(.lowConnectBatteryThreshold) private var threshold

    var body: some View {
        let device = event.kind == .disconnected ? event.device : (manager.device(event.device.id) ?? event.device)
        Group {
            if event.kind == .disconnected {
                Text("Disconnected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            } else if let level = device.battery.primary {
                HStack(spacing: 5) {
                    Text(verbatim: "\(level)%")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(systemConnectivityTint(level, threshold: threshold))
                        .lineLimit(1)
                        .fixedSize()
                    SystemBatteryRing(percent: level, tint: systemConnectivityTint(level, threshold: threshold))
                }
            } else {
                Text("Connected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        .padding(.trailing, 8)
    }
}

// MARK: Lock-screen widget

/// Connected Bluetooth devices with their battery. Renders nothing when no
/// device is connected. White content for the lock screen's glass card.
@MainActor
struct ConnectivityLockWidget: View {
    @ObservedObject private var manager = SystemConnectivityManager.shared
    @Default(.connectivityModel) private var model
    @Default(.lowConnectBatteryThreshold) private var threshold

    init() {}

    var body: some View {
        if !manager.devices.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(manager.devices.suffix(3))) { device in
                    row(device)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .shadow(color: Color.black.opacity(0.15), radius: 2, y: 1)
            .animation(Constants.Animations.standard, value: manager.devices)
        }
    }

    private func row(_ device: SystemConnectedDevice) -> some View {
        HStack(spacing: 10) {
            SystemDeviceGlyph(kind: device.kind, size: 24, style: model, allowsVideo: false)
            Text(verbatim: device.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if let level = device.battery.primary {
                Text(verbatim: "\(level)%")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.85))
                SystemBatteryRing(percent: level, tint: systemConnectivityTint(level, threshold: threshold))
            }
        }
        .accessibilityElement(children: .combine)
    }
}
