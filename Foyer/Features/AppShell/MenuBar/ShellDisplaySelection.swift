import AppKit
import Defaults

/// Writes the "Display on" choice used by both the menu-bar Display submenu
/// and Settings › General. `NotchWindowManager` observes `showOnDisplay` and
/// `showOnDisplayUUID`, so the UUID is written before the type.
@MainActor
enum ShellDisplaySelection {
    /// Tag strings used by the Settings popup.
    static let mainTag = "main"
    static let allTag = "all"
    static let builtInTag = "builtin"
    static let uuidPrefix = "uuid:"

    static var hasBuiltInDisplay: Bool {
        NSScreen.screens.contains(where: \.isBuiltIn)
    }

    static var currentTag: String {
        switch Defaults[.showOnDisplay] {
        case .mainScreen: return mainTag
        case .allDisplays: return allTag
        case .builtInDisplay: return builtInTag
        case .specificDisplay: return uuidPrefix + (Defaults[.showOnDisplayUUID] ?? "")
        }
    }

    static func select(tag: String) {
        if tag == mainTag {
            selectMain()
        } else if tag == allTag {
            selectAll()
        } else if tag == builtInTag {
            selectBuiltIn()
        } else if tag.hasPrefix(uuidPrefix) {
            let uuid = String(tag.dropFirst(uuidPrefix.count))
            if let screen = NSScreen.screens.first(where: { $0.displayUUID == uuid }) {
                select(screen: screen)
            }
        }
    }

    static func selectMain() {
        Defaults[.showOnDisplay] = .mainScreen
    }

    static func selectAll() {
        Defaults[.showOnDisplay] = .allDisplays
    }

    static func selectBuiltIn() {
        Defaults[.showOnDisplay] = .builtInDisplay
    }

    static func select(screen: NSScreen) {
        guard let uuid = screen.displayUUID else { return }
        Defaults[.showOnDisplayName] = screen.localizedName
        Defaults[.showOnDisplaySymbol] = screen.chooserSymbol
        Defaults[.showOnDisplayUUID] = uuid
        Defaults[.showOnDisplay] = .specificDisplay
    }

    static func isSelected(screen: NSScreen) -> Bool {
        Defaults[.showOnDisplay] == .specificDisplay && Defaults[.showOnDisplayUUID] == screen.displayUUID
    }

    /// Display name of the current choice ("Main display", "All displays", …).
    static var currentTitle: String {
        switch Defaults[.showOnDisplay] {
        case .mainScreen: return "Main display"
        case .allDisplays: return "All displays"
        case .builtInDisplay: return "Built-in display"
        case .specificDisplay: return Defaults[.showOnDisplayName] ?? "Display"
        }
    }
}
