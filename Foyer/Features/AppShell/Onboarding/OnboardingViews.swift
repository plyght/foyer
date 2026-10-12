import AppKit
import SwiftUI

/// Card sizes from the screenshots (464x600 px at 1.5x ≈ 310x400 pt; the
/// teardown quotes ~312 wide). The Welcome card is wider (≈ 358 pt).
private enum OnboardingMetrics {
    static let cardSize = CGSize(width: 312, height: 400)
    static let welcomeSize = CGSize(width: 360, height: 400)
    static let cornerRadius: CGFloat = 24
    static let illustrationSize = CGSize(width: 124, height: 116)
    static let panelSize = CGSize(width: 240, height: 80)
    static let buttonSize = CGSize(width: 144, height: 28)
}

struct OnboardingRootView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        ZStack {
            if model.step == .welcome {
                OnboardingWelcomeCard(model: model)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96)),
                        removal: .opacity
                    ))
            } else {
                OnboardingPermissionCard(model: model, step: model.step)
                    .id(model.step)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(x: 24)),
                        removal: .opacity.combined(with: .offset(x: -24))
                    ))
            }
        }
        .opacity(model.isDismissing ? 0 : 1)
        .scaleEffect(model.isDismissing ? 0.94 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Permission card

struct OnboardingPermissionCard: View {
    @ObservedObject var model: OnboardingModel
    let step: OnboardingStep

    var body: some View {
        VStack(spacing: 0) {
            OnboardingDialogIllustration(step: step)
                .padding(.top, 24)

            Text(step.message)
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
                .padding(.top, 18)

            panel
                .padding(.top, 18)

            Spacer(minLength: 8)

            hint
                .padding(.horizontal, 24)

            Button {
                model.primaryAction()
            } label: {
                Text(model.buttonTitle)
            }
            .buttonStyle(OnboardingContinueButtonStyle(isWaiting: model.isWorking || model.isWaitingForAccessibility))
            .keyboardShortcut(.defaultAction)
            .padding(.top, 12)

            if step == .accessibility && model.isWaitingForAccessibility {
                Button("Not now") {
                    model.skipAccessibility()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 6)
            }
        }
        .padding(.bottom, 22)
        .frame(width: OnboardingMetrics.cardSize.width, height: OnboardingMetrics.cardSize.height)
        .background {
            OnboardingCardBackground(dark: false)
        }
        .clipShape(RoundedRectangle(cornerRadius: OnboardingMetrics.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OnboardingMetrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.25), radius: 24, x: 0, y: 12)
        .environment(\.colorScheme, .light)
    }

    @ViewBuilder private var panel: some View {
        if step == .accessibility {
            OnboardingHUDPreview()
        } else {
            OnboardingTilePanel(model: model, tiles: step.tiles)
        }
    }

    private var hint: some View {
        Text("Choose “\(step.systemButtonTitle)” once \(Image(systemName: "apple.logo")) Apple requests permission to interact on behalf of Foyer.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The stylised permission dialog at the top of each card: app badge, two
/// text lines and two pill buttons whose right one pulses to the accent.
struct OnboardingDialogIllustration: View {
    let step: OnboardingStep
    @State private var highlighted = false

    init(step: OnboardingStep) {
        self.step = step
    }

    var body: some View {
        VStack(spacing: 0) {
            badge
                .padding(.top, 16)
            Capsule()
                .fill(Color.black.opacity(0.18))
                .frame(width: 70, height: 4)
                .padding(.top, 14)
            Capsule()
                .fill(Color.black.opacity(0.1))
                .frame(width: 44, height: 4)
                .padding(.top, 5)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Capsule()
                    .fill(Color.black.opacity(0.08))
                    .frame(width: 48, height: 16)
                Capsule()
                    .fill(highlighted ? Constants.SettingsWindow.accent : Color.black.opacity(0.08))
                    .frame(width: 48, height: 16)
                    .overlay {
                        Capsule()
                            .fill(Color.white.opacity(highlighted ? 0.7 : 0))
                            .frame(width: 22, height: 3)
                    }
            }
            .padding(.bottom, 12)
        }
        .frame(width: OnboardingMetrics.illustrationSize.width, height: OnboardingMetrics.illustrationSize.height)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.9))
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).delay(0.4).repeatForever(autoreverses: true)) {
                highlighted = true
            }
        }
    }

    @ViewBuilder private var badge: some View {
        switch step {
        case .music:
            OnboardingBadgeIcon(symbol: "hand.raised.fill", colors: [Color(red: 0.25, green: 0.85, blue: 0.75), Color(red: 0.1, green: 0.62, blue: 0.6)], corner: "gearshape.2.fill")
        case .browser:
            OnboardingBadgeIcon(symbol: "globe", colors: [Color(red: 0.35, green: 0.65, blue: 1.0), Color(red: 0.15, green: 0.4, blue: 0.9)], corner: "speaker.wave.2.fill")
        case .calendar:
            SettingsCalendarGlyph(size: 44)
        case .bluetooth:
            OnboardingBadgeIcon(symbol: "airpodspro", colors: [Color(red: 0.3, green: 0.6, blue: 1.0), Color(red: 0.12, green: 0.38, blue: 0.95)], corner: nil)
        case .accessibility:
            OnboardingBadgeIcon(symbol: "lock.fill", colors: [Color(red: 1.0, green: 0.78, blue: 0.3), Color(red: 0.95, green: 0.55, blue: 0.1)], corner: "accessibility")
        case .welcome:
            EmptyView()
        }
    }
}

struct OnboardingBadgeIcon: View {
    let symbol: String
    let colors: [Color]
    let corner: String?

    var body: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .frame(width: 44, height: 44)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .overlay(alignment: .bottomTrailing) {
                if let corner {
                    Circle()
                        .fill(Color(red: 0.2, green: 0.45, blue: 0.95))
                        .frame(width: 18, height: 18)
                        .overlay {
                            Image(systemName: corner)
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.white)
                        }
                        .overlay {
                            Circle().strokeBorder(Color.white, lineWidth: 1.5)
                        }
                        .offset(x: 6, y: 6)
                }
            }
    }
}

/// Three app tiles separated by hairlines (Music / Spotify / System, …).
struct OnboardingTilePanel: View {
    @ObservedObject var model: OnboardingModel
    let tiles: [OnboardingTile]
    @ObservedObject var permissions: ShellPermissions = ShellPermissions.shared

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(tiles.enumerated()), id: \.element.id) { index, tile in
                if index > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.08))
                        .frame(width: 1, height: 48)
                }
                tileView(tile)
            }
        }
        .frame(width: OnboardingMetrics.panelSize.width, height: OnboardingMetrics.panelSize.height)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.35))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
        }
    }

    private func tileView(_ tile: OnboardingTile) -> some View {
        VStack(spacing: 6) {
            Group {
                if tile.bundleIdentifier != nil, ShellAppIconView.icon(for: tile.bundleIdentifier) != nil {
                    ShellAppIconView(bundleIdentifier: tile.bundleIdentifier, fallbackSymbol: tile.symbol, size: 36)
                } else {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.86)], startPoint: .top, endPoint: .bottom))
                        .frame(width: 32, height: 32)
                        .overlay {
                            Image(systemName: tile.symbol)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(Color.black.opacity(0.75))
                        }
                        .frame(width: 36, height: 36)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                statusBadge(for: tile)
                    .offset(x: 4, y: 4)
            }
            Text(tile.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            model.tapTile(tile)
        }
        .help(tile.automates ? "Allow Foyer to control \(tile.name)" : tile.name)
    }

    @ViewBuilder private func statusBadge(for tile: OnboardingTile) -> some View {
        if tile.automates, let bundleIdentifier = tile.bundleIdentifier {
            switch permissions.automationState(for: bundleIdentifier) {
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white, Color.green)
            case .denied:
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white, Color.red)
            default:
                EmptyView()
            }
        }
    }
}

/// Accessibility preview: a black HUD pill that alternates Display ↔ Sound
/// over a blurred backdrop (`onb_accessibility_preview_strip.png`).
struct OnboardingHUDPreview: View {
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(
                colors: [Color(red: 0.42, green: 0.62, blue: 0.85), Color(red: 0.55, green: 0.72, blue: 0.82), Color(red: 0.35, green: 0.6, blue: 0.62)],
                startPoint: .top, endPoint: .bottom
            )
            .blur(radius: 6)
            TimelineView(.periodic(from: Date(), by: 1.6)) { context in
                OnboardingHUDPill(isSound: OnboardingHUDPreview.isSoundPhase(context.date))
                    .animation(Constants.Animations.hud, value: OnboardingHUDPreview.isSoundPhase(context.date))
            }
            .padding(.top, 6)
        }
        .frame(width: OnboardingMetrics.panelSize.width, height: OnboardingMetrics.panelSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
        }
    }
}

extension OnboardingHUDPreview {
    static func isSoundPhase(_ date: Date) -> Bool {
        Int(date.timeIntervalSinceReferenceDate / 1.6) % 2 == 1
    }
}

struct OnboardingHUDPill: View {
    let isSound: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isSound ? "speaker.wave.2.fill" : "sun.max.fill")
                .font(.system(size: 9, weight: .bold))
                .contentTransition(.symbolEffect(.replace))
            Text(isSound ? "Sound" : "Display")
                .font(.system(size: 10, weight: .semibold))
                .contentTransition(.opacity)
            Spacer(minLength: 8)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                Capsule()
                    .fill(Color.white)
                    .frame(width: isSound ? 30 : 22)
            }
            .frame(width: 44, height: 3)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 10)
        .frame(width: isSound ? 176 : 168, height: 22)
        .background {
            Capsule(style: .continuous).fill(Color.black)
        }
        .environment(\.colorScheme, .dark)
    }
}

// MARK: - Welcome card

struct OnboardingWelcomeCard: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .interpolation(.high)
                .frame(width: 84, height: 84)
                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 6)
                .padding(.top, 28)

            Text("Foyer")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(colors: [Color.white, Color.white.opacity(0.72)], startPoint: .top, endPoint: .bottom)
                )
                .padding(.top, 2)

            Text("It bubbles up notifications, alerts and activities, fluidly transforming itself into your notch.")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
                .padding(.top, 6)

            HStack(alignment: .top, spacing: 10) {
                OnboardingGestureTile(gesture: .horizontal)
                OnboardingGestureTile(gesture: .vertical)
                OnboardingGestureTile(gesture: .tap)
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)

            Spacer(minLength: 12)

            Button {
                model.primaryAction()
            } label: {
                Text("Get Started")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .frame(width: 160, height: 30)
                    .background {
                        Capsule(style: .continuous).fill(Color.white)
                    }
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(SettingsScaleFadeButtonStyle())
            .keyboardShortcut(.defaultAction)
            .padding(.bottom, 24)
        }
        .frame(width: OnboardingMetrics.welcomeSize.width, height: OnboardingMetrics.welcomeSize.height)
        .background {
            OnboardingCardBackground(dark: true)
        }
        .clipShape(RoundedRectangle(cornerRadius: OnboardingMetrics.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: OnboardingMetrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.35), radius: 28, x: 0, y: 14)
        .environment(\.colorScheme, .dark)
    }
}

enum OnboardingGesture {
    case horizontal, vertical, tap

    var caption: String {
        switch self {
        case .horizontal: return "Swipe horizontally to skip media"
        case .vertical: return "Swipe vertically to toggle open"
        case .tap: return "Tap for the expanded view"
        }
    }
}

/// A mini island with an animated finger hint.
struct OnboardingGestureTile: View {
    let gesture: OnboardingGesture
    @State private var animating = false

    init(gesture: OnboardingGesture) {
        self.gesture = gesture
    }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                island
                finger
            }
            .frame(height: 70)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }

            Text(gesture.caption)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                animating = true
            }
        }
    }

    private var island: some View {
        let expanded = gesture != .horizontal && animating
        return UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: expanded ? 10 : 6,
            bottomTrailingRadius: expanded ? 10 : 6,
            topTrailingRadius: 0,
            style: .continuous
        )
        .fill(Color.black)
        .frame(width: expanded ? 64 : 40, height: expanded ? 26 : 12)
        .overlay {
            if gesture == .horizontal {
                Image(systemName: animating ? "forward.fill" : "backward.fill")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.8))
            }
        }
    }

    private var finger: some View {
        let symbol: String
        let offset: CGSize
        switch gesture {
        case .horizontal:
            symbol = "hand.point.up.left.fill"
            offset = CGSize(width: animating ? 16 : -16, height: 34)
        case .vertical:
            symbol = "hand.point.up.left.fill"
            offset = CGSize(width: 0, height: animating ? 40 : 28)
        case .tap:
            symbol = "hand.tap.fill"
            offset = CGSize(width: 0, height: 30)
        }
        return Image(systemName: symbol)
            .font(.system(size: 18))
            .foregroundStyle(Color.white.opacity(0.9))
            .scaleEffect(gesture == .tap && animating ? 0.85 : 1)
            .offset(offset)
    }
}

// MARK: - Shared pieces

struct OnboardingContinueButtonStyle: ButtonStyle {
    var isWaiting: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isWaiting ? Color.secondary : Color.primary)
            .frame(width: OnboardingMetrics.buttonSize.width, height: OnboardingMetrics.buttonSize.height)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.7 : 0.92))
                    .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
            }
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Frosted glass behind the card plus soft tinted glows (light), or a dark
/// glass for the Welcome card.
struct OnboardingCardBackground: View {
    let dark: Bool

    var body: some View {
        ZStack {
            OnboardingVisualEffect(material: dark ? .hudWindow : .popover, dark: dark)
            if dark {
                Color.black.opacity(0.28)
                RadialGradient(
                    colors: [Color(red: 0.55, green: 0.3, blue: 0.95).opacity(0.25), Color.clear],
                    center: .top, startRadius: 0, endRadius: 260
                )
            } else {
                Color.white.opacity(0.25)
                RadialGradient(
                    colors: [Constants.SettingsWindow.accent.opacity(0.22), Color.clear],
                    center: UnitPoint(x: 0.2, y: 0.35), startRadius: 0, endRadius: 200
                )
                RadialGradient(
                    colors: [Color(red: 0.55, green: 0.9, blue: 0.75).opacity(0.22), Color.clear],
                    center: UnitPoint(x: 0.85, y: 0.8), startRadius: 0, endRadius: 220
                )
            }
        }
    }
}

struct OnboardingVisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let dark: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = material
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    }
}
