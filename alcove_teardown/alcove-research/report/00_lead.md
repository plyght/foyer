# Alcove 1.7.7 teardown: features, UI/UX, animation timings and internals

**How to read this file.** Sections 1-6 are the lead pass (product, architecture, onboarding, menu, the full Settings catalogue, the Luminare fork, first timings). Section 7 is the **master sheet** that reconciles every timing, constant, size and gesture threshold across all parts; start there if you are building the clone. Parts A-E are the full deep-dive reports, kept verbatim with their evidence paths rewritten to point into this zip:
- **A** static RE: all 723 animation call sites, NotchShape path, windowing, 136 Defaults keys, Swift type map, r2 scripts
- **B** runtime: windows/levels, persistence, logs, XPC/helper, network, TCC, media-key path
- **C / C2** Now Playing, HUDs, Quick Peek, gestures (thresholds), waveform, formats, extra buttons
- **D** calendar, focus, connectivity, lock screen UI, contrast outline, Settings window metrics (Luminare comparison)
- **E** hardware paths: notch-size formula, battery/IOPS, AirPods model table, OSD suppression via event tap, lock notifications/CGS spaces, brightness

Zip layout: `report/` (this file), `clips/` + `children/*/evidence/**/*.mp4` (60 fps raw clips), `strips/` + child `strips/` (frame strips), `shot_*.png` (lead screenshots), `*.txt|json` (static dumps), `rec.sh`, `measure.py`, `assemble.py`, `prompts/` (the parallel briefs).

Prepared for a clone/competitor build. Every fact is tagged:
- **OBSERVED**: seen live on the test Mac and recorded (clip/frame refs given)
- **STATIC**: taken from the app binary, resources or entitlements
- **INFERRED**: a reasoned guess from the evidence
- **UNVERIFIED**: needs hardware this VM lacks (a real notch, a battery, AirPods, Touch ID, more than one display)

Test rig: macOS VM, one 1600x1200 display at 1x (so 1 px = 1 pt), no physical notch, so **Force simulated notch** was turned ON. Recordings: 60 fps ffmpeg/AVFoundation (`rec.sh`). Per-frame geometry: `measure.py` (the bounding box of near-black pixels in a top-centre crop).

## 1. Product and distribution (STATIC/OBSERVED)
| Item | Value |
|---|---|
| Name / tagline | Alcove, "Dynamic Island for your Mac" |
| Version | 1.7.7 (build 199), universal binary (x86_64 + arm64), main binary 13.6 MB |
| Bundle id | `com.henrikruscon.Alcove`, team 287NUTSP69 (Henrik Ruscon), Developer ID, notarized + stapled, hardened runtime, **not sandboxed** |
| Minimum OS | macOS 15.0. Built with the Xcode beta SDK macosx27.0 |
| App type | `LSUIElement` agent app: menu-bar icon, no Dock icon. URL scheme `alcove://` |
| Download | https://download.tryalcove.com/Alcove.dmg (drag-to-Applications DMG) |
| Price / trial | $14.99, 72 h trial, up to 3 devices per licence |
| Backend | `api.tryalcove.com` (`/changelog` is public JSON, `/updates/latest` needs a licence), plus buy., recover. and discord.tryalcove.com |
| Updates | Self-updater. The XPC helper's `UpdateHelper.installUpdateWithZipPath:appBundlePath:reply:` unzips with `/usr/bin/ditto` and relaunches |

## 2. Architecture overview (STATIC unless marked)
- **UI stack:** SwiftUI hosted in AppKit `NSPanel`s (`NotchPanel` = interactive island, `NotchBackdropPanel` = backdrop/shadow/blur layer, `LockPanel` = lock-screen overlay). Coordinators: `NotchCoordinator` / `NotchController` own the state machine. Each feature has a Manager (data) and a Controller (UI) pair: Media, Calendar, Battery, Bluetooth/Connectivity, Brightness, Volume, Focus, Lock, Weather, Game, Space, MissionControl, Screen, Snapshot, Sound, Update, License.
- **Private APIs:**
  - `MediaRemote.framework` for now playing. On macOS 15.4+ the helper XPC is bundle-id-spoofed as `com.apple.controlcenter.AlcoveHelper` (INFERRED: to pass MediaRemote's client allow-list) and uses `PrivateMediaRemote`/`ProtocolBuffer`.
  - `DisplayServices` for brightness: Get/Set/SetBrightnessSmooth and a change-notification registration.
  - CGS (window server):
    - `CGSSpaceCreate` / `CGSSpaceSetAbsoluteLevel` / `CGSAddWindowsToSpaces` / `CGSShowSpaces` / `CGSHideSpaces` put the lock-screen panel in its own high-level space.
    - `CGSCopyManagedDisplaySpaces` and `CGSGetActiveSpace` handle fullscreen and space detection.
    - `CGShieldingWindowLevel` is also used.
  - `LoggingSupport` is opened at runtime with dlopen.
- **Input:** `CGEventTapCreate` (needs Accessibility) intercepts the media, volume and brightness keys so Alcove can suppress the system OSD and draw its own HUD. Trackpad swipes are read by `NotchSwipeMonitor` (scroll-wheel phases).
- **Audio:** `AudioHardwareCreateAggregateDevice` plus a process tap feed the live waveform (`WaveformSpectrumSession`/`Center`, `WaveformAnimationClock`), gated by `NSAudioCaptureUsageDescription`. Uses SimplyCoreAudio for devices and volume.
- **Other frameworks:** EventKit (calendar), WeatherKit + CoreLocation (weather), MapKit `MKETAResponse` (time to leave), IOKit power sources (battery), IOPMAssertion (keep awake), CoreBluetooth/IOBluetooth (AirPods battery), ScriptingBridge/AppleEvents (Music, Spotify, Safari, Chrome, Dia), Keychain via KeychainAccess (licence), NSUbiquitousKeyValueStore (settings sync), Metal + CoreImage (the CIKernel `brightenDarkPixels`, threshold/boost on Rec.709 luma, used to lift dark artwork), `CGWindowListCreateImage` (samples what is behind the notch for the contrast outline: `NotchContrastOutlineLuminanceState`, `MaterialLuminanceAggregator`), and method swizzling (`method_setImplementation`).
- **Third-party packages:** sindresorhus/Defaults (settings), twostraws/Vortex (particles), SimplyCoreAudio, KeychainAccess, DominantColors (artwork palette), MarqueeText.
- **Resources:**
  - Looping AirPods 3D-model videos: AirPods 3, 4, Pro, Pro 2, Pro 3, and Max in 10 colours.
  - Sounds: alt-jingle, blips, chime, directions, event, haptic, lock, low-battery, low-power, pad, sleep, unlock, volume.
  - Asset catalog of 122 assets, including 66 named colours (the Alcove palette plus button/container/modal tokens) and custom glyphs (link, lock, repeat, spotify, swipe gestures).

## 3. First run and onboarding (OBSERVED, screenshots `shot_onb_*.png`)
Each step is a centred, frosted-glass light card, about 312x320 pt, with an animated illustration and one Continue button:
1. **Music control:** Music, Spotify and System tiles. Triggers the AppleEvents automation prompts.
2. **Browser:** Safari, Chrome and Dia, to "identify and focus tabs playing audio".
3. **Calendar:** Calendar, Fantastical and Notion tiles, then the TCC prompt "Alcove would like full access to your calendar" (Allow Full Access).
4. **Bluetooth:** AirPods, AirPods Pro and AirPods Max, then the Bluetooth TCC prompt.
5. **Accessibility:** "hide and replace the system HUDs". The preview animates a Display HUD into a Sound HUD pill. Continue opens System Settings > Privacy > Accessibility, and the button shows "Waiting..." while it polls `AXIsProcessTrusted`.
6. **Activate Alcove:** a three-tile segmented picker (License / Trial / Purchase).
   - License: key field plus "Recover license".
   - Trial: "Trial is limited to 72 hours." with a Start Trial button.
   - Purchase: opens the store.
7. **Welcome:** dark glass card with the app icon, "Alcove" wordmark and "It bubbles up notifications, alerts and activities, fluidly transforming itself into your notch". Three gesture tiles: swipe horizontally to skip media, swipe vertically to toggle open, tap for the expanded view. Then **Get Started**.
8. The card dismisses and the island appears. On a notchless screen with the simulated notch OFF it is a floating capsule about 4 pt below the top edge. With **Force simulated notch** ON it becomes a flush-top notch with concave "shoulders", like a MacBook Pro notch.

Location permission is requested later and lazily: weather and time-to-leave show "unblock"/lock badges until it is granted. Audio capture follows the same pattern for the live waveform.

## 4. Menu-bar item (OBSERVED)
The menu contains **Display >** (screen chooser), a disabled "Version 1.7.7" row, **Settings...** (Cmd-,) and **Quit Alcove** (Cmd-Q).

## 5. Settings: complete catalogue with defaults (OBSERVED via the accessibility tree)
The window is about 396x438 pt with a translucent light material, sidebar about 144 pt, grouped inset rows, mint-green accent toggles, and each section headed by an SF Symbol in a coloured rounded square. Full dump: `settings_ax/general.txt`.

**General**
- Launch at login(off)
- Hide in fullscreen(on)
- Hide in mission control(on)
- Hide while gaming(off)
- Hide from screen capture(off)
- Force simulated notch(on, default off)
- Display on: Main display (popup; menu bar Display submenu too)

**Idle Activity**
- Most Recent(off)
- None / Playing / Calendar(selected default) / Duo

**Behaviour**
- Contrast outline(on)
- Progressive blur(on)
- Haptic feedback(on)
- Expand on hover (info)(off)

**Gestures**
- Natural movement(off)
- Swipe to toggle open(on)
- Swipe to cycle activity (info)(on)
- Swipe to dismiss activity (info)(on)
- Swipe to skip media(on)

**Sidebar**
- General
- Notifications: Battery(disabled: no battery), Connectivity, Focus, Display, Sound
- Live Activities: Now Playing, Calendar, File Tray (Soon, disabled), Lock Screen
- Alcove: License (Trial), About

**Connectivity**
- enable(on)
- Duration slider 5.0 s
- Warn on low battery(on)
- Low battery threshold 20% slider (for connected devices such as AirPods; the Mac's own battery threshold is 10 % in the binary, see Part E)
- Play sound on low battery(on, preview play button)
- Style picker: 3D models (AirPods Pro video) / Symbols

**Focus**
- enable(on)
- Duration 5.0 s slider
- Play sound on sleep focus(off, preview)
- Replace waveform during focus(off)
- Hide label(off)
- Allowed Notifications (during focus): Battery(on), Connectivity(on), Display(on), Sound(on)

**Display (brightness HUD)**
- enable(on)
- Duration 1.5 s slider
- Progress style: White / Accent / Glow
- Show percentage(off)
- Hide label(off)
- Speed: Smooth (tortoise) / Fast (hare) / Instant (bolt)

**Sound (volume HUD)**
- enable(on)
- Duration 1.5 s
- Progress style: White / Accent / Decibel
- Show percentage(off)
- Hide label(off)
- Speed Smooth/Fast/Instant
- Leading glyph: Show symbol (speaker) / Show device (AirPods Pro)

**Now Playing**
- enable(on)
- Idle duration 3 s slider (how long paused media lingers)
- Explicit badge: None / Explicit (e.square.fill) / third glyph
- Format: Monochrome / Colored / Gradient
- Use live waveform (disabled until audio-capture "unblock")
- Disable compact waveform(off)
- Disable artwork flip(off)
- Hide while source app is active(off)
- Hide media title extras(off)
- Extra button: Favorite / Shuffle / Repeat / Copy (link)
- Source: Automatic · System (gear popup)
- Extension(on?)
- Quick Peek(on): When media changes(on), Peek duration 2 s

**Calendar**
- enable(on)
- Time before event 15 m slider
- Play sound on calendar event(on, preview)
- Play hourly chime(off, preview)
- Use calendar color(off)
- Disable activity during events(off)
- Show weather on empty day (locked: needs location)(off)
- Use event indicators(off)
- Always show month view(off)
- Notify when time to leave ("unblock": needs location)(off)
- Calendars: per-calendar checkbox + popup "Both" (show in Activity/Notification/Both) for Calendar, Birthdays
- Quick Peek(on): Before event starts(off), When event is starting(on), Peek duration 4 s
- Use colored calendar indicator(on)

**Lock Screen**
- enable(on)
- Keep awake 0 m slider
- Show on screen saver(off)
- Play sound on lock(off, preview)
- Play sound on unlock(on, preview)
- Widgets: Battery(on), Connectivity(on), Focus(on), Calendar(off), Now Playing(on)
- Widget material: Glass / Clear / Frosted
- Idle duration 10 m
- Show volume control(off)
- Offset tuning 0 px slider
- Weather (locked: needs location)(off)
- Allowed Notifications: Battery, Connectivity, Focus, Display, Sound (all on)

**License**
- Trial row with live countdown '2d 23h 56m 59s' (ticks per second)
- Activate header + Purchase link
- License Key monospace field with key.fill glyph. TRIAL VERIFIED started 2026-10-11 09:52 local.

**About**
- Check Updates... (1.7.7)
- Automatically check for updates(on)
- Feedback card 'Estimated reply: 48h'
- Send Feedback...
- Join Discord...

### 5.1 Settings window implementation: forked Luminare (STATIC + user hint)
The user reports that the settings UI is a lightly modified [MrKai77/Luminare](https://github.com/MrKai77/Luminare). The binary agrees:
- There is no `Luminare` module name and no `luminare*` modifier or environment keys (`luminareTint`, `luminareAnimation`, ...), so the source was vendored into the `Alcove` module and renamed rather than linked as a package.
- These Luminare components are present with the `Luminare` prefix removed: `SidebarButtonStyle` (exact upstream name), `SliderPicker` (upstream `LuminareSliderPicker`), `Section` (upstream `LuminareSection`) and `Toggle` (upstream `LuminareToggle`).
- Custom additions not in any upstream commit: `TopNestedButtonStyle`/`BottomNestedButtonStyle` (the first and last rows of a grouped section), `ScaleFadeButtonStyle`, `SegmentedPicker` (the icon-tile pickers such as Smooth/Fast/Instant and White/Accent/Glow), `DropdownPicker`/`AppKitMenuPicker`/`InvisiblePopUpButton` (NSPopUpButton-backed menus), `ListToggle`, `HighlightButtonStyle`, `RoundedToggleStyle`, `CheckboxToggleStyle`, `SettingsSection` and `ChangelogSectionView`.
- Clone tip: start from Luminare (`LuminareWindow` + `LuminareSection` + `LuminareSliderPicker`), then add segmented icon-tile pickers and nested-row button styles to match Alcove.


## 6. The island: geometry and measured animations (OBSERVED)
| State | Width x height (pt) | Notes |
|---|---|---|
| Closed (simulated notch) | 140 x ~28 | Flush to the top, concave outer shoulders, about 8-10 pt bottom radius |
| Hover (Expand on hover OFF) | 152 x ~33 | Breathing bump plus a soft drop shadow, no content |
| Expanded, Calendar | 358 x ~175 | Two columns: the day (red "SUNDAY", large "11", "No events today / Your day is clear") and the month grid (red "OCTOBER", today in a red circle, weekend days grey). Large bottom corner radius (~24 pt INFERRED) |

| Transition | Onset to settle (1 px) | Character | Evidence |
|---|---|---|---|
| Click to open (closed to calendar) | **~517 ms** (31 frames) | Underdamped spring: width overshoots to 378 (+20 px: **+5.6 % of the final width**, **+9.2 % of the 218 px change**) at ~317 ms, then settles. The shape leads; content blurs and fades in from about frame 7 and is sharp by about 300 ms | `clips/notch_close_then_open.mp4` f264-295, `strips/notch_close_then_open_open.png` |
| Click outside to close | **~583 ms** to 1 px, last 1 px at ~983 ms | No overshoot (critically damped or overdamped). Content blurs and fades out first (~200 ms), then the shape contracts | same clip f84-119, `strips/..._close.png` |
| Second open to close | ~600 ms | Repeats consistently | f439-475 |
| Hover in | **~117 ms** to visually settled, last 1 px ~450 ms | Fast, snappy grow of +12 px wide and +5 px tall | `clips/hover.mp4` f94-101 |
| Hover out | **~267 ms** | Smooth, no overshoot | f294-310 |

INFERRED spring fit (superseded by STATIC `Spring(duration: 0.5, bounce: 0.375)`; the overshoot relative to the change, 9.2 %, is what matches that spring): an open overshoot of 5.6 % gives a damping ratio of ζ ≈ 0.68 (from ln(0.056) = -πζ/√(1-ζ²)). The time to peak (~317 ms, ≈ half a damped period) gives a natural period of about 0.63 s. Together these point to a SwiftUI `.spring(response: ~0.45-0.5, dampingFraction: ~0.7)` for opening and a `dampingFraction ≈ 1` spring for closing. Constants recovered statically are in section 7 and supersede this estimate where present.
