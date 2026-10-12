import Defaults
import Foundation

// All settings, named and defaulted exactly like Alcove's 136 Defaults keys
// (teardown Appendix B + Part B §2.3). Licence keys are intentionally absent.
// Feature folders may add their own keys in an `extension Defaults.Keys`.

extension Defaults.Keys {
    // MARK: Internal
    static let isFirstLaunch = Key<Bool>("isFirstLaunch", default: true)
    static let hasPromptedAccessibilityPermission = Key<Bool>("hasPromptedAccessibilityPermission", default: false)
    static let hasPromptedAudioPermission = Key<Bool>("hasPromptedAudioPermission", default: false)
    static let hasPromptedBluetoothPermission = Key<Bool>("hasPromptedBluetoothPermission", default: false)
    static let hasPromptedCalendarPermission = Key<Bool>("hasPromptedCalendarPermission", default: false)
    static let hasPromptedLocationPermission = Key<Bool>("hasPromptedLocationPermission", default: false)

    // MARK: General
    static let launchAtLogin = Key<Bool>("launchAtLogin", default: false)
    static let hideMenuBarIcon = Key<Bool>("hideMenuBarIcon", default: false)
    static let hideWhileInFullscreen = Key<Bool>("hideWhileInFullscreen", default: true)
    static let hideWhileInMissionControl = Key<Bool>("hideWhileInMissionControl", default: true)
    static let hideWhileGaming = Key<Bool>("hideWhileGaming", default: false)
    static let hideFromScreenCapture = Key<Bool>("hideFromScreenCapture", default: false)
    static let forceSimulatedNotch = Key<Bool>("forceSimulatedNotch", default: false)
    static let notchAdjustedWidth = Key<Double>("notchAdjustedWidth", default: 0)
    static let notchAdjustedHeight = Key<Double>("notchAdjustedHeight", default: 0)
    static let showOnDisplay = Key<DisplayType>("showOnDisplay", default: .mainScreen)
    static let showOnDisplayName = Key<String?>("showOnDisplayName")
    static let showOnDisplaySymbol = Key<String?>("showOnDisplaySymbol")
    static let showOnDisplayUUID = Key<String?>("showOnDisplayUUID")
    static let showRemainingTime = Key<Bool>("showRemainingTime", default: true)

    // MARK: Idle activity
    static let idleActivity = Key<IdleActivity>("idleActivity", default: .calendar)
    static let mostRecentActivity = Key<Bool>("mostRecentActivity", default: false)
    static let forceEnableActivity = Key<Bool>("forceEnableActivity", default: false)

    // MARK: Behaviour
    static let contrastOutline = Key<Bool>("contrastOutline", default: true)
    static let progressiveBlur = Key<Bool>("progressiveBlur", default: true)
    static let enableHaptics = Key<Bool>("enableHaptics", default: true)
    static let expandNotchOnHover = Key<Bool>("expandNotchOnHover", default: false)
    static let hoverDuration = Key<Double>("hoverDuration", default: 0)

    // MARK: Gestures
    static let naturalMovement = Key<Bool>("naturalMovement", default: false)
    static let swipeToToggle = Key<Bool>("swipeToToggle", default: true)
    static let swipeToCycleActivity = Key<Bool>("swipeToCycleActivity", default: true)
    static let swipeToDismiss = Key<Bool>("swipeToDismiss", default: true)
    static let swipeToSkip = Key<Bool>("swipeToSkip", default: true)

    // MARK: Battery
    static let enableBattery = Key<Bool>("enableBattery", default: true)
    static let batteryDuration = Key<Double>("batteryDuration", default: 5)
    static let warnOnLowBattery = Key<Bool>("warnOnLowBattery", default: true)
    static let lowBatteryThreshold = Key<Double>("lowBatteryThreshold", default: 10)
    static let playSoundOnLowBattery = Key<Bool>("playSoundOnLowBattery", default: true)
    static let notifyOnLowPowerMode = Key<Bool>("notifyOnLowPowerMode", default: true)
    static let hideBatteryLabel = Key<Bool>("hideBatteryLabel", default: false)
    static let hideBatteryPercentage = Key<Bool>("hideBatteryPercentage", default: false)

    // MARK: Connectivity
    static let enableConnectivity = Key<Bool>("enableConnectivity", default: true)
    static let connectivityDuration = Key<Double>("connectivityDuration", default: 5)
    static let warnOnLowConnectBattery = Key<Bool>("warnOnLowConnectBattery", default: true)
    static let lowConnectBatteryThreshold = Key<Double>("lowConnectBatteryThreshold", default: 20)
    static let playSoundOnLowConnectBattery = Key<Bool>("playSoundOnLowConnectBattery", default: true)
    static let connectivityModel = Key<ConnectivityModel>("connectivityModel", default: .threeDimensional)

    // MARK: Focus
    static let enableFocus = Key<Bool>("enableFocus", default: true)
    static let focusDuration = Key<Double>("focusDuration", default: 5)
    static let playSoundOnSleepFocus = Key<Bool>("playSoundOnSleepFocus", default: false)
    static let replaceWaveformDuringFocus = Key<Bool>("replaceWaveformDuringFocus", default: false)
    static let replaceWaveformDuringFocusModeIdentifier = Key<String?>("replaceWaveformDuringFocusModeIdentifier")
    static let hideLabel = Key<Bool>("hideLabel", default: false)
    static let allowBatteryWhenFocused = Key<Bool>("allowBatteryWhenFocused", default: true)
    static let allowConnectivityWhenFocused = Key<Bool>("allowConnectivityWhenFocused", default: true)
    static let allowBrightnessWhenFocused = Key<Bool>("allowBrightnessWhenFocused", default: true)
    static let allowVolumeWhenFocused = Key<Bool>("allowVolumeWhenFocused", default: true)

    // MARK: Display (brightness HUD)
    static let enableBrightness = Key<Bool>("enableBrightness", default: true)
    static let brightnessDuration = Key<Double>("brightnessDuration", default: 1.5)
    static let brightnessProgressStyle = Key<BrightnessProgressStyle>("brightnessProgressStyle", default: .white)
    static let showBrightnessPercentage = Key<Bool>("showBrightnessPercentage", default: false)
    static let hideBrightnessLabel = Key<Bool>("hideBrightnessLabel", default: false)
    static let brightnessSpeed = Key<HUDSpeed>("brightnessSpeed", default: .fast)

    // MARK: Sound (volume HUD)
    static let enableVolume = Key<Bool>("enableVolume", default: true)
    static let volumeDuration = Key<Double>("volumeDuration", default: 1.5)
    static let volumeProgressStyle = Key<VolumeProgressStyle>("volumeProgressStyle", default: .white)
    static let showVolumePercentage = Key<Bool>("showVolumePercentage", default: false)
    static let hideVolumeLabel = Key<Bool>("hideVolumeLabel", default: false)
    static let volumeSpeed = Key<HUDSpeed>("volumeSpeed", default: .fast)
    static let volumeOutputDevice = Key<VolumeLeadingGlyph>("volumeOutputDevice", default: .device)

    // MARK: Now Playing
    static let enableNowPlaying = Key<Bool>("enableNowPlaying", default: true)
    static let idleDuration = Key<Double>("idleDuration", default: 3)
    static let songTitleBadge = Key<SongTitleBadge>("songTitleBadge", default: .explicit)
    static let progressStyle = Key<NowPlayingFormat>("progressStyle", default: .mono)
    static let useLiveWaveform = Key<Bool>("useLiveWaveform", default: false)
    static let disableWaveform = Key<Bool>("disableWaveform", default: false)
    static let disableAlbumArtFlip = Key<Bool>("disableAlbumArtFlip", default: false)
    static let hideWhileSourceIsActive = Key<Bool>("hideWhileSourceIsActive", default: false)
    static let hideSongTitleExtras = Key<Bool>("hideSongTitleExtras", default: false)
    static let controlChoice = Key<ControlChoice>("controlChoice", default: .shuffle)
    static let automaticMusicApp = Key<Bool>("automaticMusicApp", default: true)
    static let musicApp = Key<MusicApp>("musicApp", default: .system)
    static let enableQuickPeek = Key<Bool>("enableQuickPeek", default: true)
    static let whenSongChanges = Key<Bool>("whenSongChanges", default: true)
    static let peekDuration = Key<Double>("peekDuration", default: 2)

    // MARK: Calendar
    static let enableCalendar = Key<Bool>("enableCalendar", default: true)
    static let timeBeforeEvent = Key<Double>("timeBeforeEvent", default: 15)
    static let playSoundOnCalendarEvent = Key<Bool>("playSoundOnCalendarEvent", default: true)
    static let playHourlyChime = Key<Bool>("playHourlyChime", default: false)
    static let useCalendarColor = Key<Bool>("useCalendarColor", default: false)
    static let disableActivityDuringEvents = Key<Bool>("disableActivityDuringEvents", default: false)
    static let showWeatherOnEmptyDay = Key<Bool>("showWeatherOnEmptyDay", default: false)
    static let useEventIndicators = Key<Bool>("useEventIndicators", default: false)
    static let alwaysShowMonthView = Key<Bool>("alwaysShowMonthView", default: false)
    static let notifyWhenTimeToLeave = Key<Bool>("notifyWhenTimeToLeave", default: false)
    static let playSoundOnTimeToLeave = Key<Bool>("playSoundOnTimeToLeave", default: true)
    static let timeToLeaveBuffer = Key<Double>("timeToLeaveBuffer", default: 10)
    static let timeToLeaveDuration = Key<Double>("timeToLeaveDuration", default: 8)
    static let defaultTransportType = Key<TransportType>("defaultTransportType", default: .automobile)
    static let excludedCalendars = Key<[String]>("excludedCalendars", default: [])
    static let calendarDisplayModes = Key<[String: CalendarDisplayMode]>("calendarDisplayModes", default: [:])
    static let enableCalendarQuickPeek = Key<Bool>("enableCalendarQuickPeek", default: true)
    static let beforeEventStarts = Key<Bool>("beforeEventStarts", default: false)
    static let whenEventIsStarting = Key<Bool>("whenEventIsStarting", default: true)
    static let calendarPeekDuration = Key<Double>("calendarPeekDuration", default: 4)
    static let useColoredCalendarIndicator = Key<Bool>("useColoredCalendarIndicator", default: true)
    static let weatherStyle = Key<WeatherStyle>("weatherStyle", default: .symbol)

    // MARK: Lock screen
    static let enableLockScreen = Key<Bool>("enableLockScreen", default: true)
    static let keepAwake = Key<Double>("keepAwake", default: 0)
    static let showOnScreenSaver = Key<Bool>("showOnScreenSaver", default: false)
    static let playSoundOnLock = Key<Bool>("playSoundOnLock", default: false)
    static let playSoundOnUnlock = Key<Bool>("playSoundOnUnlock", default: true)
    static let allowBatteryWidgetWhenLocked = Key<Bool>("allowBatteryWidgetWhenLocked", default: true)
    static let allowConnectivityWidgetWhenLocked = Key<Bool>("allowConnectivityWidgetWhenLocked", default: true)
    static let allowFocusWidgetWhenLocked = Key<Bool>("allowFocusWidgetWhenLocked", default: true)
    static let allowCalendarWidgetWhenLocked = Key<Bool>("allowCalendarWidgetWhenLocked", default: false)
    static let allowNowPlayingWidgetWhenLocked = Key<Bool>("allowNowPlayingWidgetWhenLocked", default: true)
    static let allowWeatherWidgetWhenLocked = Key<Bool>("allowWeatherWidgetWhenLocked", default: false)
    static let lockScreenWidgetOrder = Key<[LockScreenWidget]>("lockScreenWidgetOrder", default: LockScreenWidget.allCases)
    static let nowPlayingStyle = Key<WidgetMaterial>("nowPlayingStyle", default: .glass)
    static let hideIdleDuration = Key<Double>("hideIdleDuration", default: 10)
    static let showVolumeControl = Key<Bool>("showVolumeControl", default: false)
    static let nowPlayingWidgetOffset = Key<Double>("nowPlayingWidgetOffset", default: 0)
    static let allowBatteryWhenLocked = Key<Bool>("allowBatteryWhenLocked", default: true)
    static let allowConnectivityWhenLocked = Key<Bool>("allowConnectivityWhenLocked", default: true)
    static let allowFocusWhenLocked = Key<Bool>("allowFocusWhenLocked", default: true)
    static let allowBrightnessWhenLocked = Key<Bool>("allowBrightnessWhenLocked", default: true)
    static let allowVolumeWhenLocked = Key<Bool>("allowVolumeWhenLocked", default: true)

    // MARK: Updates
    static let automaticallyCheckForUpdates = Key<Bool>("automaticallyCheckForUpdates", default: true)
    static let earlyBirdUpdates = Key<Bool>("earlyBirdUpdates", default: false)
}
