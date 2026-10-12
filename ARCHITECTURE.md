# Foyer architecture

Foyer is a free, open-source "Dynamic Island for your Mac", built from the
measurements in `alcove_teardown/ALCOVE_TEARDOWN.md` (Alcove 1.7.7). Section
numbers below (§7.1, Part C …) refer to that file.

## Build

- `project.yml` is an [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec.
  `xcodegen generate` → `Foyer.xcodeproj` (not committed).
- CI (`.github/workflows/build.yml`) builds on the `xcode-27` (public preview, arm64) runner with the newest
  Xcode (beta included), ad-hoc signs, uploads `Foyer.zip`, and publishes a GitHub Release for
  `v*` tags. The in-app updater reads those releases.
- Swift 5 language mode, deployment target macOS 15.0, built with the macOS 27 SDK, universal binary.
- `ui-capture.yml` is the separate test build: it runs a scripted demo and uploads screenshots, recordings and logs.
- Packages: sindresorhus/Defaults 8.x (settings), MrKai77/Luminare (settings
  window), twostraws/Vortex (particles).

## Targets

| Target | Bundle id | Purpose |
|---|---|---|
| Foyer | `app.foyer.Foyer` | LSUIElement agent app, `foyer://` URL scheme, AppleScript sdef |
| FoyerHelper.xpc | `com.apple.controlcenter.FoyerHelper` | MediaRemote access on 15.4+ and update install (like AlcoveHelper) |

`Shared/FoyerHelperProtocol.swift` is compiled into both.

## Core (`Foyer/Core`)

- `Support/Constants.swift`: every spring, duration, size and threshold.
  Use these instead of literals.
- `Settings/DefaultsKeys.swift`, `SettingsTypes.swift`: all settings keys
  (Alcove's names and defaults). Feature-only keys go in the feature folder as
  `extension Defaults.Keys`.
- `Notch/`:
  - `NotchShape`: the island outline.
  - `NotchPanels`: `NotchPanel`, `NotchBackdropPanel`, `LockPanel`.
  - `NotchGeometry`: the Part E size formula.
  - `NotchWindowManager`: one fixed 624×320 panel pair per target display, plus
    mouse and scroll monitors.
  - `NotchViewModel`: per-screen hover, expand and swipes.
  - `NotchController`: shared content.
  - `NotchView` / `NotchBackdropView`: rendering.
- `Services/`:
  - `Haptics.perform(.generic | .levelChange)`.
  - `SoundPlayer.play(FoyerSound)`.
- `Support/PrivateAPI.swift`: `dlopen`/`dlsym` loader for private frameworks.
  Never link private frameworks directly.

### Publishing content

All calls go through `NotchController.shared` and run on the main actor:

```swift
// Long-lived compact activity (notch + two wings). One visible at a time.
NotchController.shared.setActivity(LiveActivity(id: .nowPlaying, wingWidth: 41, priority: 10,
    leading: AnyView(ArtworkThumb()), trailing: AnyView(CompactWaveform())))
NotchController.shared.removeActivity(.nowPlaying)

// Transient notification / HUD. Same kind replaces in place and restarts the timer.
NotchController.shared.post(NotchNotification(kind: .volume, category: .sound, wingWidth: 95,
    duration: Defaults[.volumeDuration], animation: Constants.Animations.hud,
    leading: AnyView(VolumeGlyph()), trailing: AnyView(VolumeBar())))

// Quick Peek (233×70 two-row capsule).
NotchController.shared.showQuickPeek(QuickPeek(source: .nowPlaying, duration: Defaults[.peekDuration],
    content: AnyView(NowPlayingPeekView())))

// Expanded pages (click / swipe down to open; swipe down inside to cycle pages).
NotchController.shared.registerPage(ExpandedPage(id: .nowPlaying, height: 120, priority: 10,
    content: AnyView(NowPlayingExpandedView())))
```

Views should observe their own `ObservableObject` managers so they update live
without re-publishing. Read `@Environment(\.notchGeometry)` for the notch size
and `@Environment(\.notchViewModel)` for open/close.

Context flags set by features:
- `isFocusActive` (Focus)
- `isScreenLocked` (Lock)
- `backdropIsDark` (Visuals)
- `setHidden(_:reason:)` (fullscreen, Mission Control, gaming, source app, …)
- `setFullscreen(_:screen:)`

`mediaCommandHandler` is installed by Now Playing for swipe-to-skip.

### Gestures (implemented in core)

| Where | Gesture | Effect |
|---|---|---|
| Compact | Fingers up > 35 pt | Dismiss the visible activity; the next one fades in |
| Compact | Fingers down > 35 pt, on release | Restore the last dismissed activity, otherwise expand |
| Compact | Horizontal > 70 pt | Previous / next track |
| Expanded | Up > 105 pt | Close |
| Expanded | Down > 75 pt | Next page |
| Expanded | Horizontal > 35 pt | Skip |

A 15 pt reversal resets the distance, and a new gesture within 0.5 s is ignored.

## Features (`Foyer/Features/<Name>`)

Each feature exposes `enum <Name>Module { @MainActor static func start() }`,
called from `AppDelegate`.

| Folder | Module | Owns |
|---|---|---|
| `NowPlaying/` (+ `FoyerHelper/`) | `NowPlayingModule` | MediaRemote helper, Music/Spotify AppleScript, compact/expanded/peek views, waveform (fake + live), marquee, artwork flip & palette, explicit badge, extra buttons. Provides `NowPlayingDuoColumn`, `NowPlayingLockWidget` |
| `HUD/` | `HUDModule` (`start`, `stop`) | Event tap OSD suppression, volume (CoreAudio), brightness (DisplayServices), keyboard backlight, HUD views and speeds. Provides `VolumeManager.shared` |
| `Calendar/` | `CalendarModule` | EventKit, calendar activity/page/peek, chime, time to leave, weather, Focus (`FocusManager.shared`). Provides `CalendarDuoColumn`, `CalendarLockWidget`, `FocusLockWidget`, `WeatherLockWidget` |
| `System/` | `SystemModule` | Battery & Low Power, Bluetooth/AirPods connectivity, fullscreen/Mission Control/Spaces (CGS), games. Provides `BatteryLockWidget`, `ConnectivityLockWidget` |
| `Visuals/` + `LockScreen/` | `VisualsModule`, `LockScreenModule` (`start`, `stop`) | Progressive blur (`ProgressiveBlurBand`), contrast-outline luminance sampling, sounds and icon assets, lock-screen panel/space/widgets, keep awake |
| `AppShell/` | `AppShellModule` (`start`, `openSettings`, `handle(url:)`) | Menu bar, Luminare settings window, onboarding, updater, URL scheme, AppleScript, launch at login, permissions |

Original assets only: the repo and CI releases never contain Alcove's sounds,
videos or artwork. `AlcoveAssets` (core) optionally uses them on your own Mac:
from the git-ignored `LocalAssets/Alcove/` bundled into local builds, or from an
installed `Alcove.app` at runtime. See `LocalAssets/README.md`.
