import SwiftUI

/// Slider stops. Alcove's `SliderPicker` snaps to fixed values; the ranges
/// below reproduce the knob positions in the AX dumps (340 pt track, 20 pt
/// knob): Duration 5.0 s sits at 71 % (stops 0.5…7), HUD 1.5 s at 50 %,
/// Idle 3 s at 30 % (0…10), Peek 2 s / 4 s at 20 % / 60 % (1…6), Time before
/// event 15 m at 40 % (5…30), lock-screen Idle 10 m at 67 % (0…15) and
/// Offset 0 px centred.
enum SettingsSliderStops {
    static let notificationDuration: [Double] = [0.5, 1, 2, 3, 4, 5, 6, 7]
    static let hudDuration: [Double] = SettingsMetrics.stops(from: 0.5, through: 2.5, by: 0.1)
    static let batteryThreshold: [Double] = SettingsMetrics.stops(from: 5, through: 50, by: 5)
    static let mediaIdle: [Double] = SettingsMetrics.stops(from: 0, through: 10, by: 1)
    static let peekDuration: [Double] = SettingsMetrics.stops(from: 1, through: 6, by: 0.5)
    static let timeBeforeEvent: [Double] = SettingsMetrics.stops(from: 5, through: 30, by: 5)
    static let timeToLeaveBuffer: [Double] = SettingsMetrics.stops(from: 0, through: 30, by: 5)
    static let timeToLeaveDuration: [Double] = SettingsMetrics.stops(from: 1, through: 15, by: 1)
    static let keepAwake: [Double] = [0, 5, 10, 15, 20, 30, 45, 60]
    static let lockIdle: [Double] = SettingsMetrics.stops(from: 0, through: 15, by: 1)
    static let widgetOffset: [Double] = SettingsMetrics.stops(from: -20, through: 20, by: 1)
    static let notchTuning: [Double] = SettingsMetrics.stops(from: -20, through: 20, by: 1)
    static let hoverDelay: [Double] = SettingsMetrics.stops(from: 0, through: 1, by: 0.1)
}

// Titles and glyphs of the enum settings, as Alcove labels them.

extension IdleActivity {
    var settingsTitle: String {
        switch self {
        case .none: return "None"
        case .nowPlaying: return "Playing"
        case .calendar: return "Calendar"
        case .duo: return "Duo"
        }
    }
}

extension BrightnessProgressStyle {
    var settingsTitle: String {
        switch self {
        case .white: return "White"
        case .accent: return "Accent"
        case .glow: return "Glow"
        }
    }
}

extension VolumeProgressStyle {
    var settingsTitle: String {
        switch self {
        case .white: return "White"
        case .accent: return "Accent"
        case .decibel: return "Decibel"
        }
    }
}

extension HUDSpeed {
    var settingsTitle: String {
        switch self {
        case .smooth: return "Smooth"
        case .fast: return "Fast"
        case .instant: return "Instant"
        }
    }

    var settingsSymbol: String {
        switch self {
        case .smooth: return "tortoise.fill"
        case .fast: return "hare.fill"
        case .instant: return "bolt.fill"
        }
    }
}

extension VolumeLeadingGlyph {
    var settingsTitle: String {
        switch self {
        case .symbol: return "Show symbol"
        case .device: return "Show device"
        }
    }

    var settingsSymbol: String {
        switch self {
        case .symbol: return "speaker.wave.2.fill"
        case .device: return "headphones"
        }
    }
}

extension SongTitleBadge {
    var settingsTitle: String {
        switch self {
        case .none: return "None"
        case .explicit: return "Explicit"
        case .explicitOutline: return "Outline"
        }
    }

    var settingsSymbol: String {
        switch self {
        case .none: return "nosign"
        case .explicit: return "e.square.fill"
        case .explicitOutline: return "e.square"
        }
    }
}

extension NowPlayingFormat {
    var settingsTitle: String {
        switch self {
        case .mono: return "Monochrome"
        case .colored: return "Colored"
        case .gradient: return "Gradient"
        }
    }
}

extension ControlChoice {
    var settingsTitle: String {
        switch self {
        case .favorite: return "Favorite"
        case .shuffle: return "Shuffle"
        case .`repeat`: return "Repeat"
        case .copy: return "Copy"
        }
    }

    var settingsSymbol: String {
        switch self {
        case .favorite: return "heart.fill"
        case .shuffle: return "shuffle"
        case .`repeat`: return "repeat"
        case .copy: return "link"
        }
    }
}

extension MusicApp {
    var settingsTitle: String {
        switch self {
        case .music: return "Music"
        case .spotify: return "Spotify"
        case .system: return "System"
        }
    }

    var settingsBundleIdentifier: String? {
        switch self {
        case .music: return "com.apple.Music"
        case .spotify: return "com.spotify.client"
        case .system: return nil
        }
    }
}

extension ConnectivityModel {
    var settingsTitle: String {
        switch self {
        case .threeDimensional: return "3D models"
        case .symbol: return "Symbols"
        }
    }
}

extension WidgetMaterial {
    var settingsTitle: String {
        switch self {
        case .glass: return "Glass"
        case .clear: return "Clear"
        case .frosted: return "Frosted"
        }
    }
}

extension CalendarDisplayMode {
    /// Alcove's per-calendar popup: Both / Live Activity / Expanded View
    /// (Part D §1.7 corrects the lead's "Notification").
    var settingsTitle: String {
        switch self {
        case .both: return "Both"
        case .activity: return "Live Activity"
        case .notification: return "Expanded View"
        }
    }
}

extension TransportType {
    var settingsTitle: String {
        switch self {
        case .automobile: return "Driving"
        case .walking: return "Walking"
        case .transit: return "Transit"
        }
    }

    var settingsSymbol: String {
        switch self {
        case .automobile: return "car.fill"
        case .walking: return "figure.walk"
        case .transit: return "tram.fill"
        }
    }
}

extension WeatherStyle {
    var settingsTitle: String {
        switch self {
        case .symbol: return "Symbol"
        case .temperature: return "Temperature"
        }
    }
}

extension LockScreenWidget {
    var settingsTitle: String {
        switch self {
        case .battery: return "Battery"
        case .connectivity: return "Connectivity"
        case .focus: return "Focus"
        case .calendar: return "Calendar"
        case .nowPlaying: return "Now Playing"
        case .weather: return "Weather"
        }
    }

    var settingsTab: SettingsTab? {
        switch self {
        case .battery: return .battery
        case .connectivity: return .connectivity
        case .focus: return .focus
        case .calendar: return .calendar
        case .nowPlaying: return .nowPlaying
        case .weather: return nil
        }
    }
}
