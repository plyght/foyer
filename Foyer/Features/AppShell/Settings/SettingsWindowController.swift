import AppKit
import Luminare
import SwiftUI

/// Owns the single Luminare settings window (620x687, non-resizable, hides
/// when Foyer is deactivated and keeps its position for the session, like
/// Alcove; Part D §5.2).
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    let navigation = SettingsNavigation()
    private var window: LuminareWindow?

    private init() {}

    var isVisible: Bool { window?.isVisible ?? false }

    func show(tab: SettingsTab?) {
        if let tab { navigation.selection = tab }
        let window = self.window ?? makeWindow()
        self.window = window
        ShellPermissions.shared.refresh()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func close() {
        window?.close()
    }

    private func makeWindow() -> LuminareWindow {
        let navigation = self.navigation
        let window = LuminareWindow {
            SettingsRootView(navigation: navigation)
        }
        window.title = "Foyer Settings"
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = true
        window.collectionBehavior.insert(.moveToActiveSpace)
        return window
    }
}

/// Window content: sidebar (≈225 incl. divider) + pane (395).
struct SettingsRootView: View {
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        LuminareDividedStack {
            SettingsSidebar(navigation: navigation)
                .frame(width: SettingsMetrics.sidebarWidth)

            SettingsPaneContainer(tab: navigation.selection)
                .frame(width: SettingsMetrics.paneWidth)
        }
        .frame(width: SettingsMetrics.windowSize.width, height: SettingsMetrics.windowSize.height)
        .luminareTint(overridingWith: SettingsMetrics.accent)
    }
}

// MARK: - Sidebar

struct SettingsSidebar: View {
    @ObservedObject var navigation: SettingsNavigation
    let hasBattery: Bool = ShellPowerSource.hasInternalBattery

    var body: some View {
        LuminareSidebar {
            ForEach(SettingsTab.SidebarGroup.allCases, id: \.self) { group in
                VStack(alignment: .leading, spacing: 6) {
                    if let title = group.title {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                    }
                    VStack(spacing: 0) {
                        ForEach(group.tabs) { tab in
                            SettingsSidebarButton(
                                tab: tab,
                                isSelected: navigation.selection == tab,
                                isAvailable: isAvailable(tab),
                                badge: tab == .fileTray ? "Soon" : nil
                            ) {
                                navigation.selection = tab
                            }
                        }
                    }
                }
            }
        }
    }

    private func isAvailable(_ tab: SettingsTab) -> Bool {
        switch tab {
        case .battery: return hasBattery
        case .fileTray: return false
        default: return true
        }
    }
}

struct SettingsSidebarButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let isAvailable: Bool
    let badge: String?
    let action: () -> Void

    @State var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                SettingsTabIcon(tab: tab, size: 20)
                Text(tab.title)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .overlay {
                            Capsule().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
                        }
                }
            }
            .padding(.horizontal, 8)
            .frame(width: SettingsMetrics.sidebarButton.width, height: SettingsMetrics.sidebarButton.height)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.5)
        .onHover { hovering in
            isHovering = hovering
        }
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    private var backgroundColor: Color {
        if isSelected { return Color.primary.opacity(0.1) }
        if isHovering && isAvailable { return Color.primary.opacity(0.05) }
        return Color.clear
    }
}

/// 20x20 rounded square with a white glyph, tinted per pane. Calendar shows
/// today's day number like Alcove's "11" tile.
struct SettingsTabIcon: View {
    let tab: SettingsTab
    var size: CGFloat = 20

    var body: some View {
        Group {
            if tab == .calendar {
                SettingsCalendarGlyph(size: size)
            } else {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(tab.tint.gradient)
                    .overlay {
                        Image(systemName: tab.symbol)
                            .font(.system(size: size * 0.55, weight: .semibold))
                            .foregroundStyle(Color.white)
                    }
            }
        }
        .frame(width: size, height: size)
    }
}

/// Calendar app-style glyph: white tile with a red header and the day.
struct SettingsCalendarGlyph: View {
    var size: CGFloat = 20
    var day: Int = Calendar.current.component(.day, from: Date())

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(Color.white)
            Rectangle()
                .fill(SettingsTab.calendar.tint)
                .frame(height: size * 0.28)
            Text("\(day)")
                .font(.system(size: size * 0.5, weight: .medium))
                .foregroundStyle(Color.black.opacity(0.85))
                .frame(maxHeight: .infinity)
                .padding(.top, size * 0.22)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5)
        }
    }
}

// MARK: - Pane container

struct SettingsPaneContainer: View {
    let tab: SettingsTab

    var body: some View {
        LuminarePane {
            LuminareForm {
                paneContent
                    .padding(.horizontal, 4)
            }
            .luminareMinHeight(SettingsMetrics.rowMinHeight)
            .luminareSectionHorizontalPadding(8)
        } header: {
            HStack(spacing: 8) {
                SettingsTabIcon(tab: tab, size: 20)
                Text(tab.title)
                    .font(.system(size: 16, weight: .semibold))
            }
        }
    }

    @ViewBuilder private var paneContent: some View {
        switch tab {
        case .general: SettingsGeneralPane()
        case .battery: SettingsBatteryPane()
        case .connectivity: SettingsConnectivityPane()
        case .focus: SettingsFocusPane()
        case .display: SettingsDisplayPane()
        case .sound: SettingsSoundPane()
        case .nowPlaying: SettingsNowPlayingPane()
        case .calendar: SettingsCalendarPane()
        case .fileTray: SettingsFileTrayPane()
        case .lockScreen: SettingsLockScreenPane()
        case .about: SettingsAboutPane()
        }
    }
}

struct SettingsFileTrayPane: View {
    var body: some View {
        LuminareSection {
            VStack(spacing: 8) {
                Image(systemName: "tray.full.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("File Tray is coming soon.")
                    .font(.system(size: 13, weight: .medium))
                Text("Drop files on the island to keep them close at hand.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }
}
