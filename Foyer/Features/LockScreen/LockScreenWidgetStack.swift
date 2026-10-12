import AppKit
import Defaults
import SwiftUI

/// The lock-screen widgets in `lockScreenWidgetOrder`, each gated by its
/// `allow…WidgetWhenLocked` setting (Part D §4, lead §5 Lock Screen pane).
///
/// Widgets stack vertically as cards 344 pt wide, the width of the observed
/// Now Playing card, centred above the account avatar. Each card gets the
/// material chosen in Settings (Glass / Clear / Frosted); the widgets draw
/// their own content and padding only. A widget with nothing to show renders
/// no view, so its card disappears with it.
///
/// Appearance: absent for ~0.4 s after the lock screen appears, then fades and
/// scales in over ~150 ms; fades out in ~150 ms on unlock (v3, OBSERVED).
struct LockScreenWidgetStack: View {
    @ObservedObject var manager: LockScreenManager

    @Default(.lockScreenWidgetOrder) private var order
    @Default(.allowBatteryWidgetWhenLocked) private var allowBattery
    @Default(.allowConnectivityWidgetWhenLocked) private var allowConnectivity
    @Default(.allowFocusWidgetWhenLocked) private var allowFocus
    @Default(.allowCalendarWidgetWhenLocked) private var allowCalendar
    @Default(.allowNowPlayingWidgetWhenLocked) private var allowNowPlaying
    @Default(.allowWeatherWidgetWhenLocked) private var allowWeather
    @Default(.nowPlayingStyle) private var material

    var body: some View {
        let visible = manager.widgetsVisible
        VStack(spacing: LockScreenConstants.widgetSpacing) {
            ForEach(enabledWidgets) { widget in
                widgetContent(widget)
                    .frame(width: LockScreenConstants.largeWidgetWidth)
                    .modifier(LockScreenCardChrome(material: material,
                                                   cornerRadius: Self.isLarge(widget)
                                                       ? LockScreenConstants.largeCornerRadius
                                                       : LockScreenConstants.smallCornerRadius))
            }
        }
        .fixedSize()
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : LockScreenConstants.widgetAppearScale, anchor: .bottom)
        .blur(radius: visible ? 0 : LockScreenConstants.widgetAppearBlur)
        .allowsHitTesting(visible)
    }

    private var enabledWidgets: [LockScreenWidget] {
        // Keep the stored order, drop duplicates, append cases a stored
        // order from an older version doesn't know about.
        var seen = Set<LockScreenWidget>()
        var result: [LockScreenWidget] = []
        for widget in order + LockScreenWidget.allCases where !seen.contains(widget) {
            seen.insert(widget)
            if isAllowed(widget) { result.append(widget) }
        }
        return result
    }

    private func isAllowed(_ widget: LockScreenWidget) -> Bool {
        switch widget {
        case .battery: return allowBattery
        case .connectivity: return allowConnectivity
        case .focus: return allowFocus
        case .calendar: return allowCalendar
        case .nowPlaying: return allowNowPlaying
        case .weather: return allowWeather
        }
    }

    private static func isLarge(_ widget: LockScreenWidget) -> Bool {
        switch widget {
        case .nowPlaying, .calendar: return true
        case .battery, .connectivity, .focus, .weather: return false
        }
    }

    @ViewBuilder
    private func widgetContent(_ widget: LockScreenWidget) -> some View {
        switch widget {
        case .battery: BatteryLockWidget()
        case .connectivity: ConnectivityLockWidget()
        case .focus: FocusLockWidget()
        case .calendar: CalendarLockWidget()
        case .nowPlaying: NowPlayingLockWidget()
        case .weather: WeatherLockWidget()
        }
    }
}

// MARK: - Card chrome and materials

/// Card background for a lock-screen widget in the chosen material, clipped
/// to a continuous rounded rectangle with a hairline highlight.
private struct LockScreenCardChrome: ViewModifier {
    let material: WidgetMaterial
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .foregroundStyle(.white)
            .background {
                LockScreenMaterialBackground(material: material)
                    .clipShape(shape)
            }
            .overlay {
                shape
                    .strokeBorder(borderGradient, lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .clipShape(shape)
            .contentShape(shape)
            .shadow(color: .black.opacity(material == .clear ? 0.10 : 0.18), radius: 14, y: 6)
    }

    private var borderGradient: LinearGradient {
        let top: Double
        let bottom: Double
        switch material {
        case .glass: top = 0.32; bottom = 0.08
        case .clear: top = 0.26; bottom = 0.10
        case .frosted: top = 0.22; bottom = 0.06
        }
        return LinearGradient(colors: [.white.opacity(top), .white.opacity(bottom)],
                              startPoint: .top, endPoint: .bottom)
    }
}

/// Glass: a live, wallpaper-tinted blur (observed: the card picks up the
/// wallpaper's colour). Clear: no blur, just a faint tint so the wallpaper
/// shows through. Frosted: a heavier, lighter, more opaque blur.
private struct LockScreenMaterialBackground: View {
    let material: WidgetMaterial

    var body: some View {
        switch material {
        case .glass:
            ZStack {
                LockScreenEffectView(material: .popover, appearanceName: .vibrantDark)
                Color.white.opacity(0.08)
            }
        case .clear:
            ZStack {
                Color.black.opacity(0.14)
                Color.white.opacity(0.04)
            }
        case .frosted:
            ZStack {
                LockScreenEffectView(material: .fullScreenUI, appearanceName: .vibrantDark)
                Color.white.opacity(0.18)
            }
        }
    }
}

/// Behind-window `NSVisualEffectView`, always active (Foyer is never the
/// active app on the lock screen).
private struct LockScreenEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let appearanceName: NSAppearance.Name

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        view.material = material
        view.appearance = NSAppearance(named: appearanceName)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        if nsView.material != material { nsView.material = material }
        if nsView.appearance?.name != appearanceName {
            nsView.appearance = NSAppearance(named: appearanceName)
        }
        nsView.state = .active
    }
}
