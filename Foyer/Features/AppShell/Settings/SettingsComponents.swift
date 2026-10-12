import AppKit
import IOKit.ps
import Luminare
import SwiftUI

// Small controls Alcove added on top of its vendored Luminare (lead §5.1):
// 44x20 switches, segmented icon-tile pickers (76x50 cards at 88 pitch with a
// 2 px accent ring), nested row buttons, checkboxes, info tooltips, sound
// previews and permission "unblock" badges.

enum SettingsMetrics {
    static let windowSize = Constants.SettingsWindow.size
    /// Sidebar ≈ 225 incl. divider, scroll area 395 (Part D §5.2).
    static let sidebarWidth: CGFloat = 224
    static let paneWidth: CGFloat = 395
    static let sidebarButton = Constants.SettingsWindow.sidebarButton
    /// Row pitch 42 = 4 + content + 4 + 1 px separator in a Luminare section.
    static let rowMinHeight: CGFloat = Constants.SettingsWindow.rowPitch - 9
    static let toggleSize = Constants.SettingsWindow.toggleSize
    static let tileHeight: CGFloat = 38
    static let tallTileHeight: CGFloat = Constants.SettingsWindow.segmentedCard.height
    static let tileSpacing: CGFloat = Constants.SettingsWindow.segmentedPitch - Constants.SettingsWindow.segmentedCard.width
    static let accent: Color = Constants.SettingsWindow.accent

    /// Evenly spaced slider stops, rounded to avoid floating-point drift.
    static func stops(from start: Double, through end: Double, by step: Double) -> [Double] {
        guard step > 0, end >= start else { return [start] }
        let count = Int(((end - start) / step).rounded())
        return (0...count).map { index in
            ((start + Double(index) * step) * 10_000).rounded() / 10_000
        }
    }
}

/// Whether this Mac has an internal battery (the Battery pane is disabled
/// otherwise, like Alcove on a desktop/VM).
enum ShellPowerSource {
    static var hasInternalBattery: Bool {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return false }
        guard let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return false }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if let type = description["Type"] as? String, type == "InternalBattery" {
                return true
            }
        }
        return false
    }
}

// MARK: - Switch (44x20)

/// Alcove's toggle: 44x20 track, knob slides over 250 ms ease-in-out with no
/// overshoot while the track fades from grey to the accent.
struct SettingsSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsSwitchBody(isOn: configuration.$isOn)
    }
}

private struct SettingsSwitchBody: View {
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let size = SettingsMetrics.toggleSize
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(isOn ? SettingsMetrics.accent : Color.primary.opacity(0.13))
            Capsule(style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.2), radius: 1, x: 0, y: 0.5)
                .frame(width: 26, height: size.height - 4)
                .padding(2)
        }
        .frame(width: size.width, height: size.height)
        .opacity(isEnabled ? 1 : 0.45)
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            guard isEnabled else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                isOn.toggle()
            }
        }
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(Text(verbatim: isOn ? "on" : "off"))
    }
}

/// A switch that is locked until `permission` is granted (unless it is
/// already on, so it can still be turned off).
struct SettingsSwitch: View {
    let isOn: Binding<Bool>
    let permission: ShellPermissionKind?
    @ObservedObject private var permissions = ShellPermissions.shared

    init(isOn: Binding<Bool>, permission: ShellPermissionKind? = nil) {
        self.isOn = isOn
        self.permission = permission
    }

    var body: some View {
        Toggle("", isOn: isOn)
            .labelsHidden()
            .toggleStyle(SettingsSwitchToggleStyle())
            .disabled(isLocked)
    }

    private var isLocked: Bool {
        guard let permission else { return false }
        return !permissions.isGranted(permission) && !isOn.wrappedValue
    }
}

// MARK: - Rows

/// Row label: optional glyph, title, subtitle, ⓘ tooltip and ▶ sound preview.
struct SettingsRowLabel: View {
    let title: String
    let symbol: String?
    let symbolColor: Color?
    let subtitle: String?
    let info: String?
    let sound: FoyerSound?
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, symbol: String? = nil, symbolColor: Color? = nil, subtitle: String? = nil,
         info: String? = nil, sound: FoyerSound? = nil) {
        self.title = title
        self.symbol = symbol
        self.symbolColor = symbolColor
        self.subtitle = subtitle
        self.info = info
        self.sound = sound
    }

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(symbolColor ?? Color.secondary)
                    .frame(width: 18)
            }
            Text(title)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let info {
                SettingsInfoButton(text: info)
            }
            if let sound {
                SettingsSoundPreviewButton(sound: sound)
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
    }
}

struct SettingsToggleRow: View {
    let title: String
    let isOn: Binding<Bool>
    let symbol: String?
    let symbolColor: Color?
    let subtitle: String?
    let info: String?
    let sound: FoyerSound?
    let permission: ShellPermissionKind?

    init(_ title: String, isOn: Binding<Bool>, symbol: String? = nil, symbolColor: Color? = nil,
         subtitle: String? = nil, info: String? = nil, sound: FoyerSound? = nil,
         permission: ShellPermissionKind? = nil) {
        self.title = title
        self.isOn = isOn
        self.symbol = symbol
        self.symbolColor = symbolColor
        self.subtitle = subtitle
        self.info = info
        self.sound = sound
        self.permission = permission
    }

    var body: some View {
        LuminareCompose {
            HStack(spacing: 8) {
                if let permission {
                    SettingsUnblockBadge(kind: permission)
                }
                SettingsSwitch(isOn: isOn, permission: permission)
            }
        } label: {
            SettingsRowLabel(title, symbol: symbol, symbolColor: symbolColor, subtitle: subtitle, info: info, sound: sound)
        }
    }
}

/// The enable row at the top of a feature pane: accent glyph + title + switch.
struct SettingsFeatureToggleRow: View {
    let tab: SettingsTab
    let isOn: Binding<Bool>
    let permission: ShellPermissionKind?

    init(_ tab: SettingsTab, isOn: Binding<Bool>, permission: ShellPermissionKind? = nil) {
        self.tab = tab
        self.isOn = isOn
        self.permission = permission
    }

    var body: some View {
        SettingsToggleRow(tab.title, isOn: isOn, symbol: tab == .calendar ? "calendar" : tab.symbol,
                          symbolColor: SettingsMetrics.accent, permission: permission)
    }
}

/// A row with a label and arbitrary trailing control (popup, button, …).
struct SettingsControlRow<Control: View>: View {
    let title: String
    let symbol: String?
    let info: String?
    let control: Control

    init(_ title: String, symbol: String? = nil, info: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.symbol = symbol
        self.info = info
        self.control = control()
    }

    var body: some View {
        LuminareCompose {
            control
        } label: {
            SettingsRowLabel(title, symbol: symbol, info: info)
        }
    }
}

/// Duration / threshold slider (Alcove's `SliderPicker`): title and an
/// inline value capsule ("5.0 s") on the first line, a 340 pt track with
/// stops below. Values snap to `options`.
struct SettingsSliderRow: View {
    let title: String
    let value: Binding<Double>
    let options: [Double]
    let unit: String
    let fractionDigits: Int
    let onChange: ((Double) -> Void)?

    init(_ title: String, value: Binding<Double>, options: [Double], unit: String,
         fractionDigits: Int = 1, onChange: ((Double) -> Void)? = nil) {
        self.title = title
        self.value = value
        self.options = options.isEmpty ? [value.wrappedValue] : options
        self.unit = unit
        self.fractionDigits = fractionDigits
        self.onChange = onChange
    }

    var body: some View {
        LuminareSliderPicker(
            options,
            selection: snapped,
            content: { option in
                Text(SettingsSliderRow.format(option, digits: fractionDigits, unit: unit))
                    .monospaced()
            },
            label: {
                Text(title)
            }
        )
    }

    private var snapped: Binding<Double> {
        let options = self.options
        let value = self.value
        let onChange = self.onChange
        return Binding(
            get: { SettingsSliderRow.nearest(to: value.wrappedValue, in: options) },
            set: { newValue in
                guard newValue != value.wrappedValue else { return }
                value.wrappedValue = newValue
                onChange?(newValue)
            }
        )
    }

    static func nearest(to value: Double, in options: [Double]) -> Double {
        var best = options.first ?? value
        var bestDistance = abs(best - value)
        for option in options {
            let distance = abs(option - value)
            if distance < bestDistance {
                best = option
                bestDistance = distance
            }
        }
        return best
    }

    static func format(_ value: Double, digits: Int, unit: String) -> String {
        let number = String(format: "%.\(max(0, digits))f", value)
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}

// MARK: - Accessories

struct SettingsInfoButton: View {
    let text: String

    var body: some View {
        Image(systemName: "info.circle")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .luminareToolTip(padding: 0) {
                Text(text)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 220, alignment: .leading)
                    .padding(10)
            }
            .accessibilityLabel(text)
    }
}

struct SettingsSoundPreviewButton: View {
    let sound: FoyerSound

    var body: some View {
        Button {
            SoundPlayer.play(sound)
        } label: {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Preview sound")
        .accessibilityLabel("Preview sound")
    }
}

/// "Unblock" capsule shown while a permission is missing; clicking it asks
/// for the permission or opens the Privacy pane.
struct SettingsUnblockBadge: View {
    let kind: ShellPermissionKind
    @ObservedObject private var permissions = ShellPermissions.shared

    init(kind: ShellPermissionKind) {
        self.kind = kind
    }

    var body: some View {
        if !permissions.isGranted(kind) {
            Button {
                permissions.unblock(kind)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("Unblock")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(Color.orange)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background {
                    Capsule(style: .continuous).fill(Color.orange.opacity(0.15))
                }
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .help(kind.reason)
        }
    }
}

/// A full-width row asking for a missing permission.
struct SettingsPermissionRow: View {
    let kind: ShellPermissionKind
    let message: String
    @ObservedObject private var permissions = ShellPermissions.shared

    init(kind: ShellPermissionKind, message: String) {
        self.kind = kind
        self.message = message
    }

    var body: some View {
        LuminareCompose {
            Button(buttonTitle) {
                permissions.unblock(kind)
            }
            .buttonStyle(SettingsCapsuleButtonStyle())
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.orange)
                Text(message)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var buttonTitle: String {
        permissions.state(kind) == .notDetermined ? "Allow…" : "Open Settings…"
    }
}

// MARK: - Segmented icon-tile picker

/// Alcove's `SegmentedPicker`: equal-width preview cards (76x50 at 88 pitch
/// for four options) with a caption; the selected card gets a 2 px accent
/// ring and a bold caption.
struct SettingsTilePicker<Value: Hashable, Preview: View>: View {
    let options: [Value]
    let selection: Binding<Value>
    let height: CGFloat
    let title: (Value) -> String
    let preview: (Value, Bool) -> Preview

    init(_ options: [Value], selection: Binding<Value>, height: CGFloat = SettingsMetrics.tileHeight,
         title: @escaping (Value) -> String, @ViewBuilder preview: @escaping (Value, Bool) -> Preview) {
        self.options = options
        self.selection = selection
        self.height = height
        self.title = title
        self.preview = preview
    }

    var body: some View {
        HStack(alignment: .top, spacing: SettingsMetrics.tileSpacing) {
            ForEach(options, id: \.self) { option in
                SettingsTileButton(
                    isSelected: option == selection.wrappedValue,
                    height: height,
                    title: title(option),
                    content: preview(option, option == selection.wrappedValue)
                ) {
                    withAnimation(Constants.Animations.standard) {
                        selection.wrappedValue = option
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}

struct SettingsTileButton<Content: View>: View {
    let isSelected: Bool
    let height: CGFloat
    let title: String
    let content: Content
    let action: () -> Void

    init(isSelected: Bool, height: CGFloat, title: String, content: Content, action: @escaping () -> Void) {
        self.isSelected = isSelected
        self.height = height
        self.title = title
        self.content = content
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                content
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    }
                    .padding(3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(isSelected ? SettingsMetrics.accent : Color.clear, lineWidth: 2)
                    }
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .bold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsScaleFadeButtonStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

/// Light card with a centred SF Symbol (Speed, Extra button, Transport …).
struct SettingsSymbolTile: View {
    let symbol: String
    let isSelected: Bool
    var tint: Color? = nil

    var body: some View {
        ZStack {
            Rectangle()
                .fill(isSelected ? SettingsMetrics.accent.opacity(0.14) : Color.primary.opacity(0.06))
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? (tint ?? SettingsMetrics.accent) : Color.secondary)
        }
    }
}

/// Black card used for HUD style and glyph previews.
struct SettingsDarkTile<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            Rectangle().fill(Color.black)
            content
        }
        .environment(\.colorScheme, .dark)
    }
}

/// A rounded app-like tile (Playing / Calendar idle-activity previews).
struct SettingsMiniAppTile: View {
    let color: Color
    let symbol: String?
    var size: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.5, weight: .bold))
                        .foregroundStyle(Color.white)
                }
            }
    }
}

// MARK: - Button and toggle styles

/// `ScaleFadeButtonStyle`: slight shrink and fade while pressed.
struct SettingsScaleFadeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

/// Rows of a grouped section that act as buttons (Alcove's
/// `TopNestedButtonStyle` / `BottomNestedButtonStyle`): full-width, hover
/// highlight, corners following the section's rounding.
struct SettingsNestedRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SettingsNestedRowBody(label: configuration.label, isPressed: configuration.isPressed)
    }
}

private struct SettingsNestedRowBody<Label: View>: View {
    let label: Label
    let isPressed: Bool
    @State private var isHovering = false

    init(label: Label, isPressed: Bool) {
        self.label = label
        self.isPressed = isPressed
    }

    var body: some View {
        label
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: SettingsMetrics.rowMinHeight, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(isPressed ? 0.1 : (isHovering ? 0.05 : 0)))
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

/// Compact capsule push button ("Check for Updates…", "Allow…").
struct SettingsCapsuleButtonStyle: ButtonStyle {
    var prominent: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background {
                Capsule(style: .continuous)
                    .fill(prominent ? SettingsMetrics.accent : Color.primary.opacity(configuration.isPressed ? 0.16 : 0.08))
            }
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Capsule(style: .continuous))
    }
}

/// Calendar checkbox tinted in the calendar colour.
struct SettingsCheckboxToggleStyle: ToggleStyle {
    var tint: Color

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(configuration.isOn ? tint : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(configuration.isOn ? tint : Color.secondary.opacity(0.6), lineWidth: 1.2)
                    }
                    .overlay {
                        if configuration.isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .heavy))
                                .foregroundStyle(Color.white)
                        }
                    }
                    .frame(width: 14, height: 14)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Displays

/// Live list of connected screens for the "Display on" popup.
@MainActor
final class SettingsDisplayList: ObservableObject {
    static let shared = SettingsDisplayList()

    struct Entry: Identifiable, Hashable {
        let uuid: String
        let name: String
        let symbol: String
        var id: String { uuid }
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var hasBuiltIn = false
    @Published private(set) var hasHardwareNotch = false
    private var observer: NSObjectProtocol?

    private init() {
        reload()
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in SettingsDisplayList.shared.reload() }
        }
    }

    func reload() {
        let screens = NSScreen.screens
        entries = screens.compactMap { screen in
            guard let uuid = screen.displayUUID else { return nil }
            return Entry(uuid: uuid, name: screen.localizedName, symbol: screen.chooserSymbol)
        }
        hasBuiltIn = screens.contains(where: \.isBuiltIn)
        hasHardwareNotch = screens.contains(where: \.hasHardwareNotch)
    }
}
