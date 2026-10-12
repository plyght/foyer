# Working notes (lead)
## Bundle
- Alcove 1.7.7 (build 199), com.henrikruscon.Alcove, Henrik Ruscon team 287NUTSP69, Developer ID, notarized, hardened runtime, NOT sandboxed, universal x86_64+arm64, 13.6MB binary, min macOS 15, built w/ Xcode 27 beta SDK macosx27.0. LSUIElement (agent app). URL scheme alcove://
- Entitlements: weatherkit, apple-events (temp exception: spotify, Music, Safari, Chrome, Dia), network.client, calendars, location, keychain group.
- XPC helper AlcoveHelper.xpc with bundle id com.apple.controlcenter.AlcoveHelper (spoofs Apple bundle prefix to pass MediaRemote entitlement check on macOS 15.4+). Contains MediaRemoteHelper (MRMediaRemoteCommand, PrivateMediaRemote, PrivateProtocolBuffer), UpdateHelper (installUpdateWithZipPath:appBundlePath:reply:, uses /usr/bin/ditto, relaunch), BetterDisplayIntegrationRequestData.
- Linked private frameworks: MediaRemote, DisplayServices (Get/SetBrightness, SetBrightnessSmooth, RegisterForBrightnessChangeNotifications), dlopen LoggingSupport.
- Private CGS: CGSSpaceCreate/SetAbsoluteLevel/AddWindowsToSpaces/ShowSpaces/HideSpaces (lock screen overlay via private space), CGSCopyManagedDisplaySpaces, CGSGetActiveSpace, CGShieldingWindowLevel.
- CGEventTapCreate (media keys/brightness/volume interception -> accessibility). AXIsProcessTrustedWithOptions.
- AudioHardwareCreateAggregateDevice -> process tap for live waveform (NSAudioCaptureUsageDescription).
- method_setImplementation / imp_implementationWithBlock (swizzling), CGWindowListCreateImage (wallpaper/outline sampling), IOPMAssertion (keep awake), IOPS (battery), IOBluetooth/CoreBluetooth (AirPods battery), EventKit, WeatherKit, MapKit MKETAResponse (time to leave), CoreLocation, iCloud KVS (NSUbiquitousKeyValueStore settings sync), Keychain (license), OpenDirectory, SCDynamicStoreCopyComputerName.
- CIKernel brightenDarkPixels(threshold,boost) luminance 0.2126/0.7152/0.0722.
- 3rd party: Defaults (sindresorhus), SimplyCoreAudio, Vortex (twostraws particles), KeychainAccess, DominantColors, MarqueeText.
- Classes: AboutController AccessibilityController AppState ArtworkCutoutLayer AudioManager BatteryManager BluetoothController BrightnessManager BrowserController CalendarController/Manager ClearGlassLayerView ConnectivityManager FocusManager GameManager HapticFeedback IntroController LicenseController/Manager LockController/Manager LockPanel LoopingVideoPlayback MaterialBackdropLumaView MaterialLuminanceAggregator MediaKeyManager MediaManager MissionControlManager NSMarqueeTextView NSWaveformView NotchBackdropPanel NotchController NotchCoordinator NotchPanel NotchSwipeMonitor ProgressiveBlurView ScreenManager SettingsController SnapshotManager SoundManager SpaceManager UpdateController/Manager VariableBlurEngine VolumeManager WeatherManager XPCManager WaveformAnimationClock WaveformSpectrumCenter WallpaperChangeMonitor NotchContrastOutlineLuminanceState MediaProgressLayerTrackView
- Animation-ish props: alignmentSpringStiffness/Damping/Mass, alignmentAnimationDuration, symbolAppearanceAnimationDuration, many *Debounce, swipe thresholds (horizontal/vertical/cycleActivity Success/Reset)
- Endpoints: api.tryalcove.com (/updates/latest needs license, /changelog public JSON), buy/recover/discord.tryalcove.com, music.apple.com/api/oembed
- Resources: AirPods 3D model mp4 loops (3,4,Pro,Pro2,Pro3,Max x10 colors), sounds (alt-jingle, blips, chime, directions, event, haptic, lock, low-battery, low-power, pad, sleep, unlock, volume)
- Assets: 66 named colors (Alcove* palette + button/container/modal tokens), custom SF glyphs link/lock/repeat/spotify/swipe
- Files: ~/alcove-research/{localizable.txt,changelog.txt,changelog.json,bin_strings.txt,helper_strings.txt,imports.txt,assets.json}
## Onboarding observed
1 Music/Spotify/System AppleEvents perm -> 2 Safari/Chrome/Dia -> 3 Calendar/Fantastical/Notion -> Calendar full-access TCC prompt ...
## Screen: 1600x1200 @1x, no notch, no battery, VM. Capture: ~/alcove-research/rec.sh name secs (ffmpeg avfoundation 60fps)
4 Bluetooth: AirPods/AirPods Pro/AirPods Max (Calendar Allow Full Access accepted)
Bluetooth TCC allowed. 5 Accessibility: 'hide and replace the system HUDs', preview animates Display<->Sound HUD pill
Accessibility granted via System Settings (VM pw 'devin'). Onboarding Continue shows 'Waiting...' while polling AXIsProcessTrusted.
6 Activate Alcove: segmented License/Trial/Purchase cards, License Key field, Recover license link, Activate License button
7 Trial started -> Welcome card (dark glass, app icon, 'Alcove' wordmark, 3 gesture tiles: swipe horiz skip media / swipe vert toggle open / tap expanded view, Get Started)
8 Get Started -> onboarding closes, black pill appears top-center (simulated notch already active on notchless display)
Menu bar item menu: Display > (submenu), 'Version 1.7.7' (disabled), Settings... (cmd-,), Quit Alcove (cmd-Q)
Settings window: sidebar General | Notifications: Battery(disabled, no battery), Connectivity, Focus, Display, Sound | Live Activities: Now Playing, Calendar, File Tray (Soon), Lock Screen | Alcove: License (Trial badge), About. General defaults: Launch at login off, Hide in fullscreen on, Hide in mission control on, Hide while gaming off, Hide from screen capture off, Force simulated notch off, Display on: Main display; Idle Activity: Most Recent off, None/Playing/Calendar(sel)/Duo; Behaviour: Contrast outline on, Progressive blur on, Haptic feedback on...
Force simulated notch ON: pill (rounded capsule floating ~4pt below top) changes to flush-top notch shape with concave outer shoulders (like real MBP notch)
Behaviour: Contrast outline on, Progressive blur on, Haptic feedback on, Expand on hover (info i) off
Gestures: Natural movement off, Swipe to toggle open on, Swipe to cycle activity (i) on ...
Click notch -> expanded Calendar activity: left 'SUNDAY' (red caps) '11' large, 'No events today' / 'Your day is clear'; right 'OCTOBER' red + month grid M-S w/ today red circle, weekends grey. Panel ~440x220pt @ 1600 wide, bottom corners large radius, top flush w/ concave shoulders. Progressive blur visible under panel on window beneath.
## Measured (clip notch_close_then_open.mp4, 60fps, 1600px wide display, px = pt @1x)
- Closed simulated notch: x 730..869 => 140 px wide (later frames), ~28 px tall incl. shoulders? (top row dark 12+)
- Expanded calendar: x 622..979 => 358 px wide
- CLOSE (click outside): frame84->119 (~583ms) to within 1px, final px at f143 (~983ms). Width 358->345 (2f)->306->169 by ~300ms: fast ease, no overshoot (critically damped / overdamped)
- OPEN (click notch): f264->f295 (~517ms). Overshoot: 358 target, peak 378 (+20px, +5.6%) at f283 (~317ms after onset), settles f295. Underdamped spring.
- reopen->close second time f439->f475 (~600ms) consistent
