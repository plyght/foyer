import SwiftUI

/// Settings panes in Alcove's sidebar order (Part D §5.2). Licence and trial
/// are intentionally absent.
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case battery, connectivity, focus, display, sound
    case nowPlaying, calendar, fileTray, lockScreen
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .battery: return "Battery"
        case .connectivity: return "Connectivity"
        case .focus: return "Focus"
        case .display: return "Display"
        case .sound: return "Sound"
        case .nowPlaying: return "Now Playing"
        case .calendar: return "Calendar"
        case .fileTray: return "File Tray"
        case .lockScreen: return "Lock Screen"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .battery: return "bolt.fill"
        case .connectivity: return "headphones"
        case .focus: return "moon.fill"
        case .display: return "sun.max.fill"
        case .sound: return "speaker.wave.2.fill"
        case .nowPlaying: return "play.fill"
        case .calendar: return "calendar"
        case .fileTray: return "tray.fill"
        case .lockScreen: return "lock.fill"
        case .about: return "info"
        }
    }

    /// Tint of the 20x20 rounded-square pane icon (Battery amber,
    /// Connectivity green, Focus indigo, Display purple, Sound pink, Now
    /// Playing rose, Calendar rose, File Tray grey, Lock Screen black, About grey).
    var tint: Color {
        switch self {
        case .general: return Color(red: 0.55, green: 0.55, blue: 0.58)
        case .battery: return Color(red: 0.98, green: 0.55, blue: 0.24)
        case .connectivity: return Color(red: 0.20, green: 0.78, blue: 0.47)
        case .focus: return Color(red: 99 / 255, green: 102 / 255, blue: 241 / 255)
        case .display: return Color(red: 0.69, green: 0.38, blue: 0.95)
        case .sound: return Color(red: 0.93, green: 0.33, blue: 0.75)
        case .nowPlaying: return Color(red: 0.98, green: 0.24, blue: 0.40)
        case .calendar: return Color(red: 0.98, green: 0.24, blue: 0.33)
        case .fileTray: return Color(red: 0.55, green: 0.55, blue: 0.58)
        case .lockScreen: return Color(red: 0.11, green: 0.11, blue: 0.12)
        case .about: return Color(red: 0.55, green: 0.55, blue: 0.58)
        }
    }

    enum SidebarGroup: String, CaseIterable {
        case root, notifications, liveActivities, app

        var title: String? {
            switch self {
            case .root: return nil
            case .notifications: return "Notifications"
            case .liveActivities: return "Live Activities"
            case .app: return "Foyer"
            }
        }

        var tabs: [SettingsTab] {
            switch self {
            case .root: return [.general]
            case .notifications: return [.battery, .connectivity, .focus, .display, .sound]
            case .liveActivities: return [.nowPlaying, .calendar, .fileTray, .lockScreen]
            case .app: return [.about]
            }
        }
    }

    /// Accepts "now playing", "now-playing", "nowPlaying", "lock_screen", …
    init?(urlName: String) {
        let normalized = urlName.lowercased().filter { $0.isLetter }
        switch normalized {
        case "general": self = .general
        case "battery": self = .battery
        case "connectivity", "bluetooth", "airpods": self = .connectivity
        case "focus": self = .focus
        case "display", "brightness": self = .display
        case "sound", "volume": self = .sound
        case "nowplaying", "media", "music": self = .nowPlaying
        case "calendar", "events": self = .calendar
        case "filetray": self = .fileTray
        case "lockscreen", "lock": self = .lockScreen
        case "about", "updates", "update": self = .about
        default: return nil
        }
    }
}

/// Selected pane, shared by the window controller, sidebar and URL routes.
@MainActor
final class SettingsNavigation: ObservableObject {
    @Published var selection: SettingsTab = .general
}
