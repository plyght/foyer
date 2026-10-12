import Defaults
import Foundation

// Enum-valued settings. Raw values match the strings Alcove writes to
// UserDefaults (teardown Part B §2.3) so behaviour lines up one-to-one.

enum IdleActivity: String, CaseIterable, Identifiable, Defaults.Serializable {
    case none, nowPlaying, calendar, duo
    var id: String { rawValue }
}

enum DisplayType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case builtInDisplay, mainScreen, allDisplays, specificDisplay
    var id: String { rawValue }
}

enum BrightnessProgressStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case white, accent, glow
    var id: String { rawValue }
}

enum VolumeProgressStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case white, accent, decibel
    var id: String { rawValue }
}

enum HUDSpeed: String, CaseIterable, Identifiable, Defaults.Serializable {
    case smooth, fast, instant
    var id: String { rawValue }
}

enum VolumeLeadingGlyph: String, CaseIterable, Identifiable, Defaults.Serializable {
    case symbol, device
    var id: String { rawValue }
}

enum SongTitleBadge: String, CaseIterable, Identifiable, Defaults.Serializable {
    case none, explicit, explicitOutline
    var id: String { rawValue }
}

/// Now Playing format: Monochrome / Colored / Gradient.
enum NowPlayingFormat: String, CaseIterable, Identifiable, Defaults.Serializable {
    case mono, colored, gradient
    var id: String { rawValue }
}

/// The extra button in the expanded player.
enum ControlChoice: String, CaseIterable, Identifiable, Defaults.Serializable {
    case favorite, shuffle, `repeat`, copy
    var id: String { rawValue }
}

enum MusicApp: String, CaseIterable, Identifiable, Defaults.Serializable {
    case music, spotify, system
    var id: String { rawValue }
}

enum ConnectivityModel: String, CaseIterable, Identifiable, Defaults.Serializable {
    case threeDimensional, symbol
    var id: String { rawValue }
}

/// Lock-screen widget material: Glass / Clear / Frosted.
enum WidgetMaterial: String, CaseIterable, Identifiable, Defaults.Serializable {
    case glass, clear, frosted
    var id: String { rawValue }
}

/// Per-calendar display mode: show in Activity, Notification or Both.
enum CalendarDisplayMode: String, CaseIterable, Identifiable, Defaults.Serializable {
    case activity, notification, both
    var id: String { rawValue }
}

enum TransportType: String, CaseIterable, Identifiable, Defaults.Serializable {
    case automobile, walking, transit
    var id: String { rawValue }
}

enum WeatherStyle: String, CaseIterable, Identifiable, Defaults.Serializable {
    case symbol, temperature
    var id: String { rawValue }
}

enum LockScreenWidget: String, CaseIterable, Identifiable, Defaults.Serializable {
    case battery, connectivity, focus, calendar, nowPlaying, weather
    var id: String { rawValue }
}
