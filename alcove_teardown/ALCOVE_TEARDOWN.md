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


## 7. Master timing and constant sheet (reconciled across all parts)
Where a STATIC constant and an OBSERVED measurement exist for the same thing, both are given. When building a clone, use the STATIC value.

### 7.1 Springs and curves (STATIC, Part A §1.2; addresses there)
| Use | SwiftUI animation | Live check (OBSERVED) |
|---|---|---|
| Notch open/close (main morph) | `Spring(duration: 0.5, bounce: 0.375)` (≈ response 0.5, dampingFraction 0.625) | Open settles in ~517 ms. Width overshoot is 20 px on a 218 px change (9.2 %), which matches the predicted 8-9 % for ζ 0.625. Part C measured 430-467 ms with +3-4 % on the media layout. |
| Expanded content swap (media player) | `Spring(duration: 0.3, bounce: 0.25)` | Artwork flip is 300 ms (Part C) |
| Media control strip | `Spring(duration: 0.35, bounce: 0.4)` + `.delay(0.1)` | |
| Live activities / notifications containers | `spring(response: 0.5 / 0.3, dampingFraction: 1)` | Activity appear is 450 ms with no overshoot (Part C) |
| Global default (settings, lists, HUD content) | `spring(response: 0.2, dampingFraction: 1)` | |
| HUD / DummyNotch | `spring(response: 0.4875, dampingFraction: 1)`; `Spring(bounce: -0.2)` (overdamped) | Volume HUD opens in 500 ms and dismisses in 600 ms, no overshoot (Part C) |
| Close | Same main spring; content blurs out first | 583 ms to 1 px; Part C: 417-450 ms, no visible overshoot (INFERRED: the bounce is masked because the shape shrinks into the flush top edge) |
| Small fades | `easeOut(0.1)` ×31; 0.15 / 0.4 / 0.55 / 0.6 variants; `easeInOut(0.2)`; `easeIn(0.15)` | Pause fade is 250 ms (Part C) |
| Shimmer | `linear(1.5).delay(0.25).repeatForever` | |
| Waveform bars | CABasicAnimation 0.08 s easeOut | Updates at ~17 Hz, 5 bars, 2 px wide, 4 px pitch, tinted from artwork |
| Marquee | 0.1 s fade; scroll constants 30 pt/s, 1.25 s pause | Part C measured ~330 px/s (INFERRED: the speed scales with overflow length, or 30 is a different unit) |

### 7.2 Durations and holds
| Item | Default | Source |
|---|---|---|
| Hover delay (`hoverDuration`) | 0 s; Expand on hover is off by default | STATIC + OBSERVED (no measurable delay) |
| Hover bump | 140 to 152 wide, ~117 ms in, ~267 ms out | OBSERVED (lead) |
| Paused media lingers (`idleDuration`) | 3 s, then a 467 ms shrink | STATIC + OBSERVED |
| Quick Peek (`peekDuration`) | 2 s setting; observed hold 1.75 s (2.1 s from first motion); open 270-380 ms (+2-3 %), collapse 320-420 ms; 233x70 two-row capsule | STATIC + OBSERVED |
| Calendar Quick Peek | 4 s | STATIC |
| Battery / Connectivity / Focus activity | 5 s each | STATIC + settings UI |
| Mac low-battery threshold | 10 % (binary default); the 20 % in the Connectivity pane is for connected devices | STATIC (Part E) |
| Brightness / Volume HUD | 1.5 s after the last key press | STATIC + OBSERVED |
| HUD Speed Smooth / Fast / Instant | HUD appear choreography ≈ 930 / 800 / 667 ms; the bar-fill tween stays ~70-100 ms at every speed | OBSERVED (Part C2) |
| Lock-screen idle (`hideIdleDuration`) | 10 min | STATIC |
| Time before event | 15 min | STATIC |
| Time to leave | duration 8 min, buffer 10 min | STATIC |
| Task.sleep literals | 0.02, 0.05, 0.1, 0.15, 0.2, 0.25, 0.275, 0.35, 0.45, 0.475, 0.5, 0.8, 1.5, 2.0, 4.75 s | STATIC |

### 7.3 Geometry (1 pt = 1 px on the test display)
| State | Size | Source |
|---|---|---|
| Host panels | 2 fixed 624x320 windows (interactive + backdrop) at the shielding level; never resized. Everything is drawn inside them | OBSERVED (Part B) |
| Closed notch (simulated) | 140-144 x 28-29 | OBSERVED (lead, B) |
| Hover | 152 x 33 | OBSERVED |
| Compact Now Playing | 222 x 29 | OBSERVED (B) |
| Volume HUD | 326-332 x 28-29 | OBSERVED (B, C) |
| Quick Peek | 233 x 70 | OBSERVED (C2) |
| Expanded (calendar / media) | 358-375 x ~175 | OBSERVED |
| Corner radius | NotchShape = three continuous rounded rects (body + two 2r "ears"), r clamped to ≤ 24 pt | STATIC |
| Real-notch size | W = screen.width − auxTopLeft.width − auxTopRight.width; H = safeAreaInsets.top (fn 0x100238df8) | STATIC (Part E) |
| Expanded size | max(W+160, 345) × max(H+142, 175) | STATIC (Part E) |
| Simulated notch | 140 × (menuBarHeight − 1), expanding to 345×175 | STATIC + OBSERVED |
| No-notch compact (simulation off) | 74 × (menuBarHeight − 5.5), expanding to 321×175 | STATIC (Part E) |

### 7.4 Gesture thresholds (OBSERVED, Part C; synthetic continuous scroll events, accumulated delta resolved on phase-ended)
| Gesture | Threshold |
|---|---|
| Swipe to toggle open (scroll up, -dy) | 35 px (-34 no, -36 yes) |
| Dismiss activity (+dy on compact) | 35 px; 30 px observed with a Calendar activity |
| Close expanded (+dy) | ~105 px |
| Skip media (horizontal) | ~80 px (lower confidence) |
| Cycle activity | seen once at +100 px; not reproducible |
| Reversing direction mid-gesture | does not reset; the net delta counts |
| Natural movement | did not invert open, but suppressed the +dy dismiss |

### 7.5 Waveform: fake vs live (STATIC + OBSERVED)
- **Default (fake) waveform** (OBSERVED): with "Use live waveform" off, the compact/expanded waveform is a synthetic animation, not audio-driven: 5 bars, 2 px wide, 4 px pitch, retargeted ~17 Hz via CABasicAnimation 0.08 s easeOut, tinted from the artwork's dominant colour. It animates while playing and freezes/fades on pause.
- **Live waveform** (STATIC; live UNVERIFIED on VM): Settings → Now Playing → "Use live waveform" (`useLiveWaveform`, with a crossed-mic "unblock" button when permission is missing). Info.plist `NSAudioCaptureUsageDescription` = "Alcove needs your permission to display the live waveform." (macOS 14.4+ audio-capture TCC). The pipeline symbols are `WaveformSpectrumCenter` (shared hub, `activeSpectrumOwners`, `spectrumObservers`), `WaveformSpectrumSession`, `spectrumPID` (the now-playing source app's PID), `spectrumTap`, `spectrumAnalyzer`, `liveSpectrumBandCount`/`bandCount`, `usesLiveSpectrum`, `AudioHardwareCreateAggregateDevice` ("Failed creating aggregate device with error: %d."), and the SimplyCoreAudio device-change notifications. INFERRED design: a per-process Core Audio tap on the source app's PID (CATapDescription → AudioHardwareCreateProcessTap, resolved at runtime because it is not in the static imports), wrapped in a private aggregate device with an IOProc; the analyser bins the buffers into `liveSpectrumBandCount` bands and drives the same NSWaveformView bars. It is per-app, so it reflects the song only, not system sounds. Session refcounting (`activeSpectrumOwners`) lets the compact view, the expanded view and the lock screen share one tap.
- **Clone recipe**: `CATapDescription(stereoMixdownOfProcesses: [AudioObjectID for pid])` → `AudioHardwareCreateProcessTap` → aggregate device with `kAudioAggregateDeviceTapListKey` → `AudioDeviceCreateIOProcIDWithBlock` → vDSP FFT → log-spaced bands → smoothing → bars. Fall back to the fake animation when TCC is denied.

### 7.6 Additions from Part D (OBSERVED)
- Expanded (calendar) open: underdamped, peak +4 % at 250 ms, settles ~470 ms; close 550 ms, no overshoot.
- Calendar Quick Peek: 216x28 → 233x70 in 200 ms (470 ms from fully closed), hold 4.05-4.15 s (4 s setting), close 380-500 ms. The media Quick Peek uses the same capsule with a 2 s setting.
- Focus / lock content swap: shrink 216 → 144 (333-350 ms), then regrow (470 ms); 5 s hold.
- Settings window: pane switches have no transition; toggles animate in 250 ms. Window 620x687, sidebar buttons 200x38, row pitch 42 px, toggles 44x20.
- Contrast outline: ~1.5 px, white at ~9 % alpha over dark wallpaper; luminance-gated (absent over light/silver) and debounced (~20 s re-evaluation), driven by `MaterialBackdropLumaView` / `NotchContrastOutlineLuminanceState`.
- Hourly chime: sound only, no visual.


## Part F additions (gap-closing RE, v2)

What the extra reverse-engineering pass closed, and what it couldn't. Full detail and addresses in Part F.

| Item | Answer | Evidence |
|---|---|---|
| Live waveform source | Per-app tap: private `MPCProcessAudioTap initWithPID:refreshRate:numberOfChannels:delegate:` with the Now Playing source PID, fed to `MPCAudioSpectrumAnalyzer`. Alcove never calls `AudioHardwareCreateProcessTap` itself; the aggregate device and IOProc live inside Apple's MediaPlaybackCore | STATIC (internals INFERRED) |
| Live waveform bands | **6 bands** by default (clamped 1–6); edges 20 · 81 · 170 · 527 · 1500 · 4500 · 10000 Hz, hand-tuned roughly log spacing; 5-band variant drops the 81 Hz edge. Note the fake waveform has 5 bars, the live one 6 | STATIC |
| Live waveform cadence and mapping | Analyzer refresh **20 Hz**; level per band from `averagePowerOfFrequencyBandAtIndex:` clamped to 0–1, no extra smoothing in Alcove; bar height = clamp(amplitudeHeight × level, 2 pt, amplitudeHeight), pixel-rounded; 0.08 s Core Animation tween per update, CAFrameRateRange 5–48 | STATIC |
| Live waveform FFT size, dB range, attack/release | Inside Apple's private analyzer, not in Alcove | UNVERIFIED |
| Live waveform permission | `TCCAccessPreflight`/`TCCAccessRequest(kTCCServiceAudioCapture)`, fallback opens `Privacy_AudioCapture` in System Settings. On the VM preflight returns denied without prompting | STATIC + OBSERVED |
| Haptics | One debounced wrapper over `NSHapticFeedbackManager.defaultPerformer`, always `.now`. `.levelChange` for HUD steps (volume/brightness); `.generic` for notch click, vertical swipe, track-skip swipe and cycle-activity swipe | STATIC (triggers INFERRED from enclosing functions) |
| Brightness HUD gate | Registers only if `DisplayServicesCanChangeBrightness` returns true (plus `CGDisplayIsBuiltin` checks). The VM's virtual display returns false, which is why no brightness HUD ever appeared | STATIC + OBSERVED |
| Brightness keys and HUD | Brightness keys 2/3, keyboard backlight 21/22; 1/16 step, 1/64 with Shift+Option. Same HUD view, settings and haptic path as volume, so volume HUD timings apply | STATIC (timings INFERRED) |
| Battery colours | Charging #8DEB92, low battery #FA6375 (from Assets.car); red at ≤ threshold (default 10%); no separate yellow threshold. Amber for Low Power Mode and an SF Symbol bolt are likely but unconfirmed | STATIC / INFERRED |
| Battery sounds and strings | `low-power.caf` 0.672 s, `low-battery.caf` 1.096 s; "Charging", "Low Battery", "Low Power"; shown 5 s | STATIC |
| AirPods art | 15 MP4s (not 3D models): H.264 96×96, 60 fps, 360 frames = 6.000 s, no audio, loop at the file boundary; mapped to product IDs (AirPods 3/4/Pro/Pro 2/Pro 3/Max × 10 colours) | OBSERVED (files) + STATIC (mapping) |
| Explicit badge | Driven by `kMRMediaRemoteNowPlayingInfoIsExplicitTrack` (Spotify Web API `explicit` as fallback); glyph SF Symbol `e.square.fill`. Size and placement unknown | STATIC; layout UNVERIFIED |
| notchAdjustedWidth/Height | The window geometry function never reads them; they only feed SwiftUI view padding, so they don't change the forced-simulated-notch size | STATIC (consumer INFERRED) |
| Swipe threshold literals | The six `NotchSwipes` fields exist, but their values come from registers at runtime; a debugger can't attach (hardened runtime, no get-task-allow, SIP on). Measured values in the gesture table stay the best numbers | BLOCKED |
| Real lock screen | A real lock was captured at 60 fps: 2 black frames (33 ms), then the lock screen is visible to capture (not blank); unlock crossfade ≈117 ms. Alcove's lock widget was not running on that VM, so widget layout and timing stay unverified. Uses `CGSSessionScreenIsLocked` polling, `lock.caf` 0.284 s / `unlock.caf` 0.270 s, LoginUIKit clock classes | OBSERVED (system) + STATIC; widget UNVERIFIED |

Correction to Part F: its section 8 wrote the expanded-size clamps as `min(...)`. The disassembly shows `max(...)`, as in Part E and the geometry table above.



---

# v3 live pass: live waveform, lock-screen widget, explicit badge, accessibility

_Evidence: `live_v3/` (findings.md, strips/, csv, scripts bars2.py) and `clips/live_waveform_*.mp4`, `clips/lock_widget.mp4`, `clips/explicit_expand.mp4`, `clips/rm_on_open_close.mp4`._

## Live waveform (now OBSERVED)

**How it was unblocked on the VM.**
1. In System Settings, go to Privacy & Security → Screen & System Audio Recording → **System Audio Recording Only**, click **+**, and add `/Applications/Alcove.app` (then Quit & Reopen). No in-app prompt appears.
2. In Alcove, turn on Settings → Now Playing → **Use live waveform**. A small grey glyph then appears next to the label.
3. The VM has no audio output device, so the tap only received silence and the bars sat flat (CoreAudio log: "Could not find default device"). The fix was `brew install blackhole-2ch`, then `sudo killall coreaudiod`, then setting the default output to "BlackHole 2ch".

**The audio path runs (OBSERVED, `live_v3/live_waveform_log.txt`).** Inside the Alcove process, MediaPlaybackCore `MPCProcessAudioTap` logs "ASBD for process tap", then "Starting processing audio queue" on a private aggregate device named `AudioTap-<UUID>`. It stops when the track ends. This confirms the static reading: a per-process tap on the source app, not a whole-system tap.

**Compact glyph geometry (OBSERVED, 1x display).**

| Property | Value |
|---|---|
| Bar count | 5 |
| Bar width | 2 px |
| Pitch | ~3.5 px |
| Minimum height (drawn as a dot) | 2 px |
| Maximum height | 12 px |
| Colour | Grey/white, same tint path as the synthetic glyph |

**Band mapping (OBSERVED, matches STATIC).** The test file had 2 s tones at 120 / 300 / 900 / 2600 / 7000 Hz, followed by a 20 Hz → 10 kHz log sweep:

| Bar | Band (Hz) | Lit by |
|---|---|---|
| 0 | 20–170 | 120 Hz |
| 1 | 170–527 | 300 Hz |
| 2 | 527–1500 | 900 Hz |
| 3 | 1500–4500 | 2.6 kHz |
| 4 | 4500–10000 | 7 kHz |

- Each tone lit exactly one bar, and the bars run from low frequencies on the left to high on the right.
- So the compact glyph uses the **5-band variant**, which drops the 81 Hz edge.
- The sweep peaks fall ~2.1 s apart, which is about ×3 in frequency per bar. They land on the geometric band centres (≈299 / 890 / 2598 / 6708 Hz).

**Dynamics (OBSERVED).**
- **Attack:** floor to max in 6–8 frames (100–133 ms). Example sequence: `2,6,6,10,10,10,12`.
- **Release:** max to floor in 6–9 frames (100–150 ms). Example sequence: `12,11,10,10,10,6,6,2`.
- **Steps:** heights change every ~2 frames (33 ms), in steps of about 4 px. Attack and release are symmetric, with no slow peak-hold or decay.
- **Interpretation (INFERRED):** this matches 20 Hz analyzer frames plus the 0.08 s ease-out Core Animation tween.

**Loudness mapping (OBSERVED bound, INFERRED curve).**
- A steady 0.8 FS sine pins its band at maximum height.
- On a linear 0 → 0.8 FS ramp, the bar reaches maximum within ~0.1–0.2 s, at roughly −34 to −28 dBFS.
- Inference: strong dB compression with a low floor. Real music will sit near the top unless it is quiet.
- The analyzer's dB floor and ceiling still live in Apple's private code. This empirical bound is the best value available.

**Clone recipe.** Use a per-process Core Audio tap on the now-playing app's PID. Compute 5 log bands (20/170/527/1500/4500/10000) at 20 Hz. Map dB to a 0–1 level with a low floor. Bars are 2 px wide, 2–12 px tall, and animate height with a 0.08 s ease-out.

## Lock-screen widget (now OBSERVED)

Real lock via `Ctrl+Cmd+Q`, recorded at 60 fps in `clips/lock_widget.mp4`; frame strips are in `live_v3/strips/`.

**Layout.**
- A translucent glass card, tinted from the artwork (green in this test), centred above the account avatar.
- **Top row:** artwork tile, title marquee, artist, and a live waveform glyph on the right.
- **Middle:** elapsed time, progress bar, remaining time.
- **Bottom:** shuffle, previous, play/pause, next.
- Separately, the notch shows a pill with a lock glyph while locked.

**Timing (OBSERVED).**
- The lock screen appears first; the widget stays absent for ~0.4 s.
- The widget then fades/scales in over ~100–200 ms.
- The marquee, progress and waveform keep animating while the Mac is locked.

**Unlock (OBSERVED).** Roughly two black frames (~33 ms), then a crossfade of about 117 ms.

## Explicit badge

- **Setting (OBSERVED):** Settings → Now Playing → badge picker is set to **Explicit**, the default.
- **Test (OBSERVED):** a local AAC file tagged `rtng=Explicit` with AtomicParsley. Music shows an **E** next to it in the library, but Alcove shows **no badge** in either the compact or expanded view.
- **Why (INFERRED):** Music only publishes `kMRMediaRemoteNowPlayingInfoIsExplicitTrack` for catalog (Apple Music/iTunes Store) items, so local files never trigger the badge. The Spotify path reads the `explicit` field from the Web API.
- **Badge visual:** still UNVERIFIED live. From the binary (STATIC): the glyph is the SF Symbol `e.square.fill`.

## Reduce Motion / Reduce Transparency

- **Reduce Motion: ignored (OBSERVED).**
  - With it on (NSWorkspace confirmed `true`), the open animation is unchanged: 140 → 378 peak at ~250 ms → 358 settled by ~450 ms. That is the same 9.2% overshoot as without it.
  - Close takes ~617 ms.
  - The binary has no reduce-motion references.
- **Reduce Transparency: no visible change in Settings (OBSERVED).** Screenshots of the Settings window are pixel-identical with it on and off.
  - The notch body is opaque black, so it is unaffected.
  - The lock-screen glass and the clear-glass HUD style were not tested with it on.

## Still UNVERIFIED after v3

- **Cycle-activity swipe threshold.** The VM can't hold two cyclable activities at once. The best value remains ~100 px, observed once.
- **Low Power Mode banner.** `pmset` reports "LowPowerMode not supported on AC Power". The static colours and sounds are in Part F.
- **Brightness HUD visuals, physical AirPods and battery.** These need hardware (Part F).



## Part G additions (uncovered areas, v3)

Summary of Part G. Full detail, addresses and evidence are in Part G (`children/G_v3/`).

| Item | Answer | Evidence |
|---|---|---|
| GameManager | Checks only the **frontmost app** against a fixed list: 4 Riot/League of Legends IDs, `com.nvidia.gfnpc.mall` (GeForce NOW), plus any bundle path containing `/application support/minecraft/runtime/`. It does not look at `LSApplicationCategoryType`, Game Mode, GPU load or fullscreen. With `hideWhileGaming` on, the notch hides and the volume HUD is suppressed while a listed app is in front. An app in the action-games category stayed visible | STATIC + OBSERVED (synthetic apps) |
| Sounds | All 13 measured (duration, rate, channels, peak/RMS) with waveform PNGs. Mapping: `alt-jingle` intro; `pad` About/intro ambience; `blips` license-screen UI; `chime` hourly chime; `directions` time-to-leave; `event` calendar events; `lock`/`unlock` lock screen; `sleep` Sleep Focus; `volume` volume feedback (follows the system "play feedback when volume is changed" pref); `low-power` laptop low battery (gated by `playSoundOnLowBattery`); `low-battery` low connected-device battery. Calendar, power and lock sounds play via `AudioServicesPlaySystemSound` | OBSERVED (files) + STATIC |
| `haptic.caf` | A 10.6 ms audible tick played while dragging the notch-width tuning slider. Not used for trackpad haptics, which go through `NSHapticFeedbackManager` | STATIC |
| `alcove://` | Only one route exists, and it is license-related (existence recorded only). No Settings, Now Playing or notch deep links. `alcove://`, `alcove://unknown`, `alcove://settings` do nothing | STATIC + OBSERVED |
| Vortex particles | Three call sites (About, update screen, intro), all the same drifting white `circle` field: 8.5/s for 3.5 s (intro 10/s for 4 s), speed −0.15 ±0.05, angle range π, damping 0.5, size 1 ±1 shrinking to 0.5, alpha 0→0→1→0. The `confetti`/`sparkle` assets ship inside the Vortex library but are never invoked. No weather or calendar particles | STATIC (motion not visually confirmed) |
| Updater | Custom, not Sparkle. `GET https://api.tryalcove.com/updates/latest` with `X-App-Version`, `X-App-Build`, `X-macOS-Version`, optional `X-Channel` (stable/trial/beta); 60 s timeout; checks every 6 h. Without a license the server returns 401 `{"message":"An active license is required for this channel."}`. Release model: id, tag_name, name, sections[{marker, items}], assets[{name, url}], prerelease, published_at, minimum_system_version, build_number. Install: the XPC helper unzips with `ditto`, swaps the `.app`, relaunches; no explicit signature check found in the helper | STATIC + OBSERVED (401 only) |
| AppleScript | `NSAppleScriptEnabled` is set, but there is no `.sdef`; only the generic Standard/Text suites. No custom commands | STATIC + OBSERVED |
| Performance (VM) | Idle 0.0% CPU, ~1 wakeup/s, ~64–66 MiB physical footprint. Four open/close cycles: mean 1.4%, peak 13.9%. Volume key loop: mean 4.9%, peak 33.5%. RSS 131 → 157 MiB over 20.5 min (mostly in the first 30 s); physical footprint only +1.6 MiB. Cold launch to first notch ≈1.02 s. GPU reads 0 in the VM, which says nothing about real hardware | OBSERVED (VM) |
| Performance, Now Playing (lead VM) | Music playing a 100 s pink-noise test file with live waveform on, 60 × 1 s `top` samples: mean 1.5% CPU (peak 1.9%), top power score 1.53 vs 0.05 idle, memory unchanged (55–56 MB). Bars were animating at the start of the window; the end screenshot showed them flat while Music still reported playing, so the waveform may not have run for the whole window. Files: `live_v3/perf/` | OBSERVED (VM) |
| Multiple displays | Display modes: built-in (`CGDisplayIsBuiltin`), main (`CGMainDisplayID`, i.e. the menu-bar display, not the focused app's screen), all displays, specific display (saved by UUID). Listens for screen-parameter, sleep/wake and Space changes. On a synthetic second display, every mode behaved as named. Unplugging the chosen display gave **no fallback**; replugging restored it even though its display ID changed | STATIC + OBSERVED (CGVirtualDisplay) |

Still UNVERIFIED after Part G: real-hardware GPU/energy, uncached (post-reboot) launch time, visible particle motion, and physical monitor unplug, lid-close and mirroring behaviour.


## Part H: v4 follow-ups (Low Power Mode, battery, explicit badge, cycle swipe, cold launch, mirroring, hardware script)

### H.1 Display mirroring, lid close, sleep/wake (STATIC)
- The only `isMirrored` in the binary is a Swift field on `ArtworkFrame`, `ArtworkTransition` and `ArtworkKey` (fields: identity, contentRevision, cornerRadius, isMirrored, isTransitionEnabled, opacity, blendMode). It is the horizontal mirror state of the artwork during the Y-axis flip, **not** display mirroring. STATIC (`live_v4/fieldmd.txt`).
- No `CGDisplayIsInMirrorSet`, `CGDisplayMirrorsDisplay`, `CGDisplayPrimaryDisplay` or `AppleClamshellState` import/string exists. Display-related imports are only `CGDisplayIsBuiltin`, `CGDisplayCreateUUIDFromDisplayID`, `NSScreen`, and the workspace sleep/wake notifications (`NSWorkspaceWillSleep`, `DidWake`, `ScreensDidSleep`, `ScreensDidWake`). STATIC.
- `handleWillSleep` / `handleDidWake` are ObjC selectors on `MediaManager` only (4-byte and 20-byte bodies, i.e. a stub and a thunk). STATIC.
- So mirroring and lid close have no dedicated code path. Alcove just re-reads `NSScreen.screens` on a screen-parameter change and re-applies the display-selection rule (built-in / main / all / UUID). INFERRED: lid close with an external display on "Built-in" leaves no notch, the same as the observed unplug case (Part G).

### H.2 Battery and Low Power Mode on the VM (OBSERVED + STATIC): not obtainable without a real battery
- Built `live_v4/fakebatt` (Swift, `IOPSCreatePowerSource` / `IOPSSetPowerSourceDetails`, live stdin updates). It works unprivileged: `pmset -g batt` lists `InternalBattery-0 8%; discharging; 0:24 remaining`. OBSERVED.
- But macOS still reports `Now drawing from 'AC Power'`, `pmset -g cap` has no `lowpowermode` capability, and `pmset -a|-c lowpowermode 1` / `powermode 1` all return `LowPowerMode not supported on AC Power`. `ProcessInfo.isLowPowerModeEnabled` stays `false`. OBSERVED.
- Alcove showed nothing for charging on, switch to battery, or 8% (clip `live_v4/v4_fakebatt.mp4`, crops `fb_*.png`). OBSERVED.
- Why (STATIC, `E_hw/evidence/ev/dis/f_battery_helper_open_1001527c0.txt`): `BatteryHelper.open` does `IOServiceGetMatchingService(IOServiceNameMatching("AppleSmartBattery"))`; on 0 it branches (`cbz w0`) to `swift_allocError` / `serviceNotFound` and never installs the `IOPSNotificationCreateRunLoopSource`. A fake IOPS source doesn't create an `AppleSmartBattery` IORegistry node (`ioreg -rc AppleSmartBattery` is empty), and creating one needs a kext. So the battery and Low Power Mode UI only exist on a real MacBook. Clone note: a competitor that listens to IOPS directly (instead of opening AppleSmartBattery first) would also work on UPS-powered desktops.
- Use `live_v4/alcove_hw_perf.sh` on a real MacBook (battery phase) to capture it.

### H.3 Explicit badge: Spotify shows it, third-party now-playing sources do not (OBSERVED)
- Built `live_v4/NowPlayingProbe.app`. Alcove takes it as the now-playing source (compact artwork + waveform, expanded "Probe Explicit Track / devin" with a working progress bar).
- Attempt 1: added `kMRMediaRemoteNowPlayingInfoIsExplicitTrack = true` (dlsym-resolved value is the same string) to `MPNowPlayingInfoCenter.nowPlayingInfo`. No badge (`np_attempt1_expanded.png`).
- Attempt 2: MediaPlayer exports no `MPNowPlayingInfoProperty*Explicit*` constant, so a public API can't set it.
- Attempt 3: private `MRMediaRemoteSetNowPlayingInfo` with the explicit key. The call returns, but there's no badge (`np_attempt3_expanded.png`). INFERRED: on macOS 15.4+ mediaremoted ignores now-playing writes from unentitled apps, and MPNowPlayingInfoCenter drops unknown keys.
- Combined with Part G/v3 (a local Music file tagged `rtng=Explicit` shows "E" in Music but not in Alcove): the badge only shows when Apple's own player publishes the flag (Apple Music catalog tracks) or through the Spotify fallback (`explicit` field). The Spotify route was then tested live (Part I): **the badge appears for Spotify explicit tracks** (OBSERVED).
- Glyph `e.square.fill`, about 11×11 px including anti-aliasing (9×9 solid), fill #747478 with the "e" knocked out, 5–6 px after the title, aligned to cap height. OBSERVED.
- Shown only in expanded Now Playing (including the Now Playing + Calendar split layout) and in the lock-screen widget (same size, white fill). Never in compact, hover or Quick Peek. OBSERVED.
- No animation of its own: it crossfades with the title over 4–6 frames on track change. A clean control track has no badge. OBSERVED.
- Spotify's AppleScript has no explicit property, so the flag reaches Alcove through MediaRemote or Alcove's Spotify Web API fallback (`explicit`). Which of the two is UNVERIFIED.

### H.4 Launch time (OBSERVED)
Measured from `open -a Alcove` to the first 60 fps frame showing the notch, 5 runs each. Data: [live_v4/cold_launch.csv](live_v4/cold_launch.csv), clips `live_v4/launch_warm_0N.mp4` and `live_v4/launch_cachecold_0N.mp4`.

| Condition | Runs (ms) | Mean | Median | Min | Max |
|---|---|---|---|---|---|
| Warm (process killed, files cached) | 1150, 787, 1070, 901, 885 | 958.6 | 901 | 787 | 1150 |
| Page-cache cold (`sudo purge` before each run) | 3498, 2946, 2787, 2724, 2792 | 2949.4 | 2792 | 2724 | 3498 |

A launch right after a reboot was not measured (UNVERIFIED). Expect it to be close to the page-cache-cold number or slower, because launch services and the dyld cache are also cold.

### H.5 Display mirroring live test (UNVERIFIED, blocked by the VM)
The test used a virtual second display, with Alcove set to All Displays. Turning mirroring on with `CGConfigureDisplayMirrorOfDisplay` dropped the VM's remote connection both times, right after the switch (`main_display_id=0`, `active_display_ids=[]` immediately after; see [live_v4/mirror_states.log](live_v4/mirror_states.log), [live_v4/mirror_main_transition.mp4](live_v4/mirror_main_transition.mp4)). No post-mirror state could be captured, so mirroring behaviour rests on H.1 (STATIC): Alcove has no mirroring-specific code, and it rebuilds its windows from the NSScreen list on screen-parameter changes. Expected behaviour (INFERRED): a mirror set shows up as one NSScreen, so the notch appears once, on the mirror-set primary. Confirm this on real hardware with the script below.

### H.6 Hardware measurement script
[live_v4/alcove_hw_perf.sh](live_v4/alcove_hw_perf.sh): run it on a real Mac with Alcove open (bash script; from fish run `bash alcove_hw_perf.sh`; asks for sudo once for `powermetrics`). It records system and battery info, then CPU, GPU, energy and memory across idle, open/close, Now Playing, volume-key and battery phases, into `~/alcove_hw_perf/`.

### H.7 Cycle-activity and other swipe thresholds (OBSERVED, see Part I)
Synthetic continuous scroll-phase gestures, swept from 20 to 160 px in 5 px steps, 3 repeats per step, recorded at 60 fps. Two activities were active: Now Playing and a Calendar countdown.

| State | Gesture | Effect | Reliable (3/3) | Flaky | Never |
|---|---|---|---|---|---|
| Compact, two activities | Up | Hide the visible activity and show the other one (the "cycle") | ≥ 40 px | 35 px (2/3) | ≤ 30 px |
| Compact, two activities | Down | Bring back the hidden activity (or expand if none is hidden) | ≥ 40 px | 35 px | ≤ 30 px |
| Compact | Horizontal | Skip track | 75 px | 70 px (2/3) | |
| Expanded | Up | Close | ≥ 110 px | | |
| Expanded | Down | Switch page (Now Playing to Calendar) | ≥ 80 px | | |
| Expanded | Right | Next track | ≥ 40 px | | |

- Reset: reversing by about 15–20 px mid-gesture cancels it. Reversing after the threshold is crossed does not cancel. OBSERVED.
- Cycle transition: 7-frame fade-out, 28 empty frames, 12-frame fade-in (about 0.8 s), 0% overshoot. OBSERVED.
- Expanded left (previous track): UNVERIFIED, because Spotify's "previous" restarts the current track.


---

# Part A: static reverse engineering

_Source: `children/A_static/alcove_static_re.md`. Evidence lives in `children/A_static/`._

## Alcove 1.7.7 (build 199) — Static Reverse Engineering Report (arm64 slice + AlcoveHelper.xpc)

Scope: `/Applications/Alcove.app/Contents/MacOS/Alcove` (arm64 slice thinned to `bin/Alcove.arm64`) and `AlcoveHelper.xpc` (`bin/AlcoveHelper.arm64`). Tooling: radare2 6.2.4 (`aaa`), custom Python Mach-O parsers (chained fixups, `__swift5_types/fieldmd/proto`), `xcrun swift-demangle`. Nothing license/trial related is covered beyond the public endpoints listed in NOTES.md.

Labels: **STATIC** = read from binary/resources (address given); **OBSERVED** = seen live on the VM (from lead NOTES.md / `defaults read`); **INFERRED** = deduction. Hardware not present on this VM (real notch, battery, AirPods, Touch ID, multiple displays): behaviour marked **UNVERIFIED**.

The binary is symbol-stripped: Swift function names are not available. Contexts were recovered two ways: (a) **STATIC** xrefs from a function to Swift field descriptors of a class (`field.class.Alcove.X`), and (b) **INFERRED** "nearest preceding `View.body` getter" using the 95 `SwiftUI.View` conformance witness tables recovered from `__swift5_proto` (`view_bodies.json`); SwiftUI closures are emitted directly after their body function, so this heuristic is usually right but not guaranteed. Note: hits on `MediaProgressLayerTrackView` and `LicenseManager` in column (a) are **noise** (radare2 flag collisions on shared addresses) and should be ignored.

Evidence files referenced below are in the attached zip (`alcove_static_re_evidence.zip`).

---

### 1. Animation constants

#### 1.1 Method
- Call sites: `axt` on every SwiftUI animation import (`anim_xrefs.txt`, `anim_xrefs2.txt`): 578 `Animation.spring(response:dampingFraction:blendDuration:)` / `Spring(duration:bounce:)` / `Animation.spring(_:blendDuration:)` sites, 40 `easeOut`, 2 `easeInOut`, 1 `easeIn`, 2 `linear`, 14 `delay`, 2 `repeatForever`, 228 `withAnimation`, 13 `Transaction.animation`, 9 `PhaseAnimator`, 5 `TimelineView`, 8 `Clock.sleep`, 51 `Duration.seconds`.
- Constants: `parse_consts.py` walks the 28–90 instructions before each `bl`, materialising `mov/movk → fmov dN, xN`, `fmov dN, #imm`, `movi`, and literal-pool `ldr dN,[addr]` loads (read from the file). `?` = value comes from a register/variable (e.g. a Defaults speed setting) and could not be resolved statically.
- Full table (723 rows): **Appendix A** (`anim_table.md`).

#### 1.2 Headline findings (STATIC unless noted)
| Context | API | Parameters | Address(es) | Confidence |
|---|---|---|---|---|
| Global default used everywhere (settings panes, HUD content, lists) | `Animation.spring(response:dampingFraction:blendDuration:)` | response **0.2**, damping **1.0**, blend 0 | 59+ sites (e.g. 0x100016888, 0x100028898, 0x1003a790c) | high |
| Second most common | same | response **0.25 / 0.3 / 0.4 / 0.5**, damping 1.0 | 28 / 17 / 26 / 22 sites | high |
| Notch open/close main transition (`NotchView.body` region, fn 0x1001eb370 with xrefs to `NotchController`, `MediaManager`) | `Spring(duration:bounce:)` + `Animation.spring(_:blendDuration:0)` | duration **0.5**, bounce **0.375** (≈ response 0.5, dampingFraction 0.625) | 0x1001eb5a0, 0x1001eb644 | high (matches OBSERVED ~517 ms open with ~5.6 % overshoot in NOTES.md) |
| Media player / expanded content swap (`MediaPlayer.body`, xrefs `NotchController`) | `Spring(duration:bounce:)` | duration **0.3**, bounce **0.25** | 0x1000e5c78, 0x1000e7a7c | high |
| Media control strip buttons | `Spring(duration:bounce:)`; `.delay(0.1)`; spring(response 0.3) | duration **0.35**, bounce **0.4**; delay 0.1 | 0x1000e9604, 0x1000e963c, 0x1000e9664 | high |
| Live activities container (`NotchLiveActivitiesView.body`) | spring(response:) | response 0.5 and 0.3, damping 1 | 0x1001f0df4, 0x1001f1098 | high |
| Notifications (`NotchNotificationsView.body`) | spring(response:) | response 0.5, damping 1 | 0x1002aa890 | high |
| HUD/first view (`DummyNotch` region) | spring + Spring(duration:bounce:) | response **0.4875**, damping 1 (6 sites); Spring(duration ?, bounce **-0.2**) (overdamped, 9 sites) | 0x100002a14 … | medium |
| Bouncy variants | `Spring(duration:bounce:)` | (0.6, 0.4) ×9, (0.6, 0.35) ×9, (0.45, 0.4) ×5, (0.4, 0.35) ×4, (0.35, 0.3) ×13, (0.3, 0.25) ×3, (0.35, -0.2) ×5 | see Appendix A | high |
| Underdamped springs with damping<1 | spring(response:dampingFraction:) | (0.3, 0.325), (0.35,?), (?, 0.375) | 0x1000ba908 area | medium |
| Small opacity/scale toggles (`MissionControlManager`-referencing views, sliders) | `Animation.easeOut(duration:)` | **0.1** (31 sites); 0.15 (0x100354438, 0x10035d23c); 0.4 (0x1001cf2c4); 0.55 (0x1002c794c); 0.6 (0x1002b396c) | | high |
| | `Animation.easeInOut(duration:)` | 0.2 | 0x10014b880, 0x1002a2ef0 | high |
| | `Animation.easeIn(duration:)` | 0.15 | 0x1002c799c | high |
| Vortex / shimmer loop | `Animation.linear(duration:)` 1.5 + `.delay(0.25)` + `.repeatForever` | 1.5 s, delay 0.25 | 0x100444374/80/98 | high |
| Staggered reveals | `.delay` | 0.05, 0.075, 0.1, 0.3 | 0x1000e4740, 0x10017b494, 0x1000e0bb4, 0x1002b3980 | high |
| Waveform (`NSWaveformView`, fn 0x1003a350c / 0x1003a4360) | `CABasicAnimation` + `CAMediaTimingFunction(easeOut)`, `CASpringAnimation` | duration **0.08 s** (0x3fb47ae147ae147b), fillMode, `fmov 0.5`, bar count/size constants 5.0 and 24.0, Float 2.0 | 0x1003a3870–0x1003a395c, 0x1003a44b0–0x1003a480c | high (values) / medium (which property) |
| MarqueeText (`NSMarqueeTextView`, fn 0x10031f3d8) | `CABasicAnimation` (easeOut, 0.1 s = 0x3fb999999999999a) grouped in `CAAnimationGroup`; `CATransaction` | fade 0.1 s; scroll fn 0x10031db8c constants: 2.0, 4.5, 0.5, 24.0, 30.0 (pts/s speed), 1.25 (pause s), `CATextLayer` | 0x10031f4e4, 0x10031dd38–0x10031df14 | medium |
| MediaProgress slider layer (fn 0x1003b1098) | `CASpringAnimation` + `CABasicAnimation` with `kCAMediaTimingFunctionLinear` | linear progress tween; constants 1.0, 1e-4 (0x3f1a36e2eb1c432d), 0x409b… (≈1700–1800, likely stiffness/`Double.greatestFiniteMagnitude` guard 0x7fefffffffffffff present), 0x4054… (≈80, damping?) | 0x1003b1250–0x1003b14a8 | medium |
| AppKit HUD/panel fades | `CAMediaTimingFunction(kCAMediaTimingFunctionEaseIn)` dur 0x3fd6… ≈ 0.35; `EaseInEaseOut` dur 0x3fc9… ≈ 0.2 | | 0x10021a478, 0x10024b7dc | medium |
| `NSAnimationContext` groups | duration computed (not literal) | 0x10021a2a8 (uses -0.5 offset), 0x10024b134 (alphaValue 1.0), 0x100279b44 | medium |
| Timeline-driven waveform/particles | `AnimationTimelineSchedule(minimumInterval:)` / `TimelineView` | interval = 1.0/fps variable (fdiv) | 0x10040acdc, 0x10040c2b0 (`Vortex.VortexView.body`) | medium |

**`Task.sleep` durations (STATIC)** — all `Task.sleep(for:)` is compiled to `Clock.sleep(until:tolerance:)` (8 sites, `sleep_funcs.txt`); the durations are built with `Duration.seconds(Double)` (51 sites, `dur_dis.txt`, `dur_consts.json`): 0.02, 0.05, 0.1, 0.15 ×2, 0.2 ×3, 0.25 ×2, 0.275, 0.35 ×5, 0.45 ×2, 0.475, 0.5 ×6, 0.8, 1.5, 2.0, 4.75 ×2, 1e-10 ×2 (yield), remaining 15 are variables (Defaults durations such as `peekDuration`, `batteryDuration`). No `DispatchQueue.asyncAfter` / `swift_task_sleep(nanoseconds)` imports exist; debounces are `Task`s stored in the `*Debounce`/`*Task` fields of `NotchController` (see §7).

Fields named in the brief: `alignmentSpringStiffness/Damping/Mass`, `alignmentAnimationDuration`, `symbolAppearanceAnimationDuration`, `settlingDuration` are **STATIC** field names present in `__swift5_reflstr` (`bin_strings.txt`), but they belong to stored properties set at runtime; their numeric initialisers are among the `?` rows (register-sourced) and could not be pinned to literals without symbols — **UNVERIFIED** values.

### 2. Notch geometry

- **`NotchShape`** (STATIC, `fieldmd`): `struct NotchShape { let style: Style (.notch | .pill); var topCornerRadius: Double; var bottomCornerRadius: Double }`, animatable.
- **Path construction** (STATIC, `shape_funcs_annot.txt`, fn **0x1002670fc** = `NotchShape.path(in:)` for `.notch`): there are *no* `addQuadCurve`/`addArc` calls; the shape is three `Path.addRoundedRect(in:cornerRadii:style:.continuous)` calls:
  1. `r = min(bottomCornerRadius, 24.0, rect.height − …)` clamped (constants `fmov 0.5`, `24.0` at 0x1002671dc; `min(width/2, height)` guard) and stored at `self+8`; the main body rect uses `RectangleCornerRadii(topLeading: 0, bottomLeading: r, bottomTrailing: r, topTrailing: 0)` (0x100267234 → 0x1002672ac).
  2./3. Two shoulder "ears" of size `2r` (`fadd d12, d0, d0` at 0x100267218) placed at `minX − 2r` and `maxX`, filled with the inverse radii so the concave join between notch and menu bar is a continuous (superellipse) curve (0x100267380, 0x1002674a4). Max shoulder/bottom radius is therefore **24 pt**; `topCornerRadius` feeds the ear radius.
  - `.pill` style = fn **0x100267564**: single `addRoundedRect(cornerSize: min(w,h)/2, .continuous)` (capsule).
  - Fn **0x1001d1368** draws a rounded rect (cornerSize) + rounded-corner overlay for the HUD/background; the `RoundedTriangle`-style shape 0x1001789b0 (three `addArc(tangent1End:tangent2End:radius:)`) is a caret/play glyph, not the notch.
- **Sizes** (STATIC fields): `NotchController._notchWidth/_notchHeight/_notchExpandedWidth/_notchExpandedHeight: Double`, `_notchAdjustedWidth/_notchAdjustedHeight` (Defaults, default **0.0** = "use detected size"). `NotchView` keeps `_cutoutScale`, `_cutoutWidthProgress`, `_cutoutContentWidthProgress`, `_cutoutScaleAnchor` for the expand animation.
- **Real-notch detection / menu-bar height** (STATIC): `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea` are called from ~100 functions (`geo_xrefs.txt`), the cluster 0x1000b853c–0x1000b9564 being the screen-geometry helpers (ScreenManager): a real notch is assumed when both auxiliary areas are non-nil; notch width = screen width − leftArea.width − rightArea.width, height = leftArea.height (= menu-bar height). `forceSimulatedNotch` (Bool, default false) switches to the simulated size. The simulated closed size measured live was ≈140 px wide (OBSERVED, NOTES.md); the exact default constant lives in a register-initialised field and is **UNVERIFIED** statically.
- **Corner radius tasks**: `expandedCornerRadiusTask`, `expandedTransitionTask`, `progressiveBlurTransitionTask`, `backdropLumaTransitionTask` are `Task` fields on `NotchController` (STATIC) — radius changes are driven by async tasks, not a single `withAnimation`.

### 3. Gesture and timing thresholds

- STATIC fields of `struct NotchSwipes` (`fieldmd_demangled.txt`): `verticalSwipeSuccessThreshold`, `verticalSwipeResetThreshold`, `cycleActivitySwipeSuccessThreshold`, `cycleActivitySwipeResetThreshold`, `horizontalSwipeSuccessThreshold`, `horizontalSwipeResetThreshold` (all `Double`), plus flags `enableHaptics, swipeToSkip, enableNowPlaying, enableQuickPeek, enableCalendarQuickPeek, swipeToDismiss, swipeToCycleActivity, swipeToToggle`. `NotchSwipeMonitor` holds the scroll-wheel event monitor; a `CGEventTapCreate` call exists at 0x100134380 (fn 0x100134354, `eventtap_func.txt`) used only when Accessibility is granted (`AXIsProcessTrustedWithOptions` imported).
- The threshold literals are initialised in the `NotchSwipes` memberwise init from registers → values **UNVERIFIED** (not recoverable without symbols in the time available).
- Debounce/task fields on `NotchController` (STATIC): `notificationSwapDebounce, notificationCloseDebounce, notificationRestoreDebounce, liveActivitySwapDebounce, quickPeekDebounce, adjustDebounce, progressDebounce, swipeResetDebounce, quickPeekResetDebounce, visibilityDebounce, hoverDebounce (NotchView)`. Their sleeps are the `Duration.seconds` constants in §1.2 (0.05–0.5 s cluster; 0.275 and 0.475 are the odd ones at 0x1001e10bc / 0x100357370, both inside NotchController-adjacent code).
- `hoverDuration` Defaults key default **0.0** s (STATIC); `expandNotchOnHover` default **false**.
- Duration defaults driving auto-dismiss (STATIC, §5): `peekDuration` 2 s, `calendarPeekDuration` 4 s, `idleDuration` 3 s, `hideIdleDuration` 10 s, `batteryDuration` 5, `connectivityDuration` 5, `focusDuration` 5, `brightnessDuration` 1.5, `volumeDuration` 1.5, `timeToLeaveDuration` 8 (min), `timeToLeaveBuffer` 10 (min), `timeBeforeEvent` 15 (min).

### 4. Windowing (STATIC, `win_funcs_annot.txt`, `space_funcs_annot.txt`)

Three `NSPanel` subclasses (ObjC method flags `method.Alcove.{LockPanel,NotchPanel,NotchBackdropPanel}.initWithContentRect:styleMask:backing:defer:` and `canBecomeKeyWindow`), all configured identically in their Swift designated inits:

| Property | NotchPanel (0x100267c44) | NotchBackdropPanel (0x100267fa4) | LockPanel (0x1000efe04) |
|---|---|---|---|
| styleMask (from callers 0x1001b1028 / 0x100233070) | **0x8080** = `.nonactivatingPanel | .fullSizeContentView` (borderless) | same | same |
| backing / defer | 2 (buffered) / false | | |
| hasShadow | false | false | false |
| backgroundColor / isOpaque | `.clear` / false | `.clear` / false; `colorSpace = extendedSRGB` | `.clear` / false |
| isMovable | false | false | false |
| isReleasedWhenClosed | false | false | – |
| canBecomeVisibleWithoutLogin | **true** | false | **true** |
| animationBehavior | 2 (`.none`) | 2 | 2 |
| level | `NSWindow.Level(rawValue: CGShieldingWindowLevel() + k)` computed via helper 0x10026817c | `CGShieldingWindowLevel()` | `CGShieldingWindowLevel()` (raw, =2147483630) |
| collectionBehavior | **0x151** = `.canJoinAllSpaces(1) | .stationary(0x10) | .ignoresCycle(0x40) | .fullScreenAuxiliary(0x100)` | 0x151 | 0x151 |
| ignoresMouseEvents | default (hit-tested by SwiftUI content) | **true**, `acceptsMouseMovedEvents=false` | – |
| canBecomeKeyWindow | overridden (property flag) | | |
| sharingType | `setSharingType:` with arg `(~hideFromScreenCapture) & 1` → `.none` when "Hide from screen capture" is on, else `.readOnly` (0x10023327c, 0x100233418, also 0x1002358e8/0x100241270) | | |

Windows are hosted in `NSWindowController`s (`windowController`, `backdropWindowController` fields) and positioned with `setFrame:display:NO` then `orderFrontRegardless`.

**Private CGS spaces (`SpaceManager`, fields `_space`)**: `CGSSpaceCreate(CGSMainConnectionID(), 1, options)` → `CGSSpaceSetAbsoluteLevel(cid, space, level)` → `CGSShowSpaces(cid, [space])` (0x100128d0c); teardown `CGSHideSpaces` + `CGSSpaceDestroy` (0x100128e24); windows moved with `CGSRemoveWindowsFromSpaces`/`CGSAddWindowsToSpaces` (0x100128f18); `CGSCopyManagedDisplaySpaces`, `CGSGetActiveSpace`, `CGSSpaceGetType` used to detect full-screen/Mission Control spaces (0x100127f4c, 0x100128054). INFERRED: this is how the notch and the lock-screen widgets stay above the login window (combined with `canBecomeVisibleWithoutLogin` and shielding level). Lock-screen behaviour itself **UNVERIFIED** live.

### 5. Defaults keys (sindresorhus/Defaults)

Method (STATIC): every `Defaults.Key` static initialiser calls `objc_msgSend$standardUserDefaults` (stub `fcn.100452a60`); its 136 callers (`stdud_xrefs.txt` → `defkeys_all.txt`) were parsed by `defkeys_parse.py`: the key name is a C string or an inline 15-byte Swift string, and the default value is the payload stored at `+0x10` of the captured box allocated just before the `Key` object. Bool defaults are exact; for 8-byte payloads the type is inferred (Double shown decoded; raw 0 is ambiguous between `0.0`, `0`, and the first enum case; non-zero small ints are enum raw values / Ints, e.g. `musicApp = 2` which `defaults read` shows as `system`).

Cross-check (OBSERVED, `defaults_after_settings.txt`): `enableBrightness=1, enableCalendar=1, forceSimulatedNotch=1, idleActivity=calendar, isFirstLaunch=0, musicApp=system, playSoundOnLowConnectBattery=1, warnOnLowConnectBattery=1, hasPrompted*=1` — all consistent with keys found statically (the OBSERVED values differ from defaults because the lead toggled them). Full table: **Appendix B** (`defaults_keys.md`).

Additional non-Defaults persistence: Keychain + `NSUbiquitousKeyValueStore` imports for settings sync (STATIC, NOTES.md).

### 6. Subsystems

- **MediaRemote via XPC helper** (STATIC, `helper_classes.txt`, `helper_strings.txt`): `AlcoveHelper.MediaRemoteHelper` (bundle id spoofed as `com.apple.controlcenter.AlcoveHelper` so `MRMediaRemote*` entitled calls succeed). NSXPC protocol selectors: `playPause, previousTrack, nextTrack, getSeekerPosition:, setPlayerPosition:, setPlaybackRate:, setShuffleMode:, setRepeatMode:, getIsPlaying:, getNowPlayingInfo:, getNowPlayingInfoForBundleIdentifier:reply:, getNowPlayingSource:, getNowPlayingBundle:, checkSupportedCommands:, checkSupportedCommandsForBundleIdentifier:reply:, startNowPlayingObservation, stopNowPlayingObservation, postLockScreenWidgetIsShown, postLockScreenWidgetIsHidden, installUpdateWithZipPath:appBundlePath:reply:`. Helper stored keys: `audioTierKey, audioRenderingModeKey, isLosslessKey, isDolbyAtmosKey, sourceBundleIdentifierKey, sourceClientBundleIdentifierKey, sourceParentBundleIdentifierKey, sourceDisplayNameKey, sourceProcessIdentifierKey`. Main app additionally imports `MediaRemote` directly for notifications and uses `ScriptingBridge` for Music/Spotify (`musicApp` key).
- **Audio waveform** (STATIC): `AudioManager` creates an aggregate device via `AudioHardwareCreateAggregateDevice` (fn 0x1003cfa70, dictionary keys `uid`, `name`, `subdevice…`, `master…`; failure string "Failed creating aggregate device…") and listens with `AudioObjectAddPropertyListener`; levels are published through `WaveformSpectrumCenter` → `WaveformSpectrumSession { views: NSHashTable<NSWaveformView>, bandCount: Int, lastLevels: [CGFloat], isUpdateScheduled }` driven by `WaveformAnimationClock/Source`. No vDSP/FFT import exists → band levels are time-domain RMS per band (INFERRED). `NSWaveformView` animates bars with 0.08 s easeOut `CABasicAnimation`s (§1). `useLiveWaveform` default false, `disableWaveform` false.
- **CIKernel** (STATIC): `kernel vec4 brightenDarkPixels(__sample s, float threshold, float boost)` (string in binary) applied to artwork; `CIFilter` imported. Artwork dominant colour extraction is a Swift routine (no third-party DominantColors symbols survived stripping).
- **Blur**: `ProgressiveBlurEffect` (View), `ProgressiveBlurView`, `VariableBlurEngine` types; `MaterialBackdropLumaReader` samples backdrop luminance (`backdropLumaTransitionTask`). `progressiveBlur` default true.
- **Vortex**: bundled `Vortex_Vortex.bundle`; `Vortex.VortexView.body` at 0x10040c294 with a `TimelineView` schedule (interval from fps division).
- **Haptics**: `HapticFeedback` type + `NSHapticFeedbackManager` import, gated by `enableHaptics` (default true).
- **Sounds** (resources): `chime.caf, directions.caf, event.caf, haptic.caf, lock.caf, low-battery.caf, low-power.caf, sleep.caf, unlock.caf, volume.caf, alt-jingle.m4a, blips.m4a, pad.m4a`, played with `AVAudioPlayer` (`SoundManager`), keys `playSoundOn*`, `playHourlyChime`.
- **AirPods videos**: `airpods-*.mp4` (14 models/colours) — AirPods UI **UNVERIFIED**.
- **MapKit / time-to-leave**: `MKDirectionsRequest`/`MKDirections` ETA with `defaultTransportType`, `notifyWhenTimeToLeave`, `timeToLeaveBuffer` 10 min, `timeToLeaveDuration` 8 min, `pendingLocationPermissionTarget`. **WeatherKit** via `WeatherManager`, `cachedWeather`, `showWeatherOnEmptyDay`, `weatherStyle`.
- **BetterDisplay**: helper type `Helper.BetterDisplayIntegrationRequestData` (brightness on external displays).
- **Updates**: `https://api.tryalcove.com/updates/latest` (+ `earlyBirdUpdates`, `automaticallyCheckForUpdates`), zip installed by helper `installUpdateWithZipPath:appBundlePath:reply:` using `/usr/bin/ditto` (`UpdateHelper`).
- **URL scheme**: `alcove://` registered (Info.plist); other public URLs: `buy.tryalcove.com`, `discord.tryalcove.com`, `recover.tryalcove.com`, `tryalcove.com/faqs`, `music.apple.com/api/oembed?url=`.

### 7. Swift type / field map

Complete dump: `fieldmd_demangled.txt` (561 field descriptors, 549 types), `types_list.txt`, `conformances.txt` (993 conformances). Key types (STATIC):

- `class NotchController`: `_space: SpaceManager`, `windowController`, `backdropWindowController: NSWindowController`, `topEdgeGlobalMouseMonitor`, `topEdgeLocalMouseMonitor`, `swipeMonitor: NotchSwipeMonitor?`, debounces/tasks listed in §3, Defaults-backed `_hideFromScreenCapture, _forceSimulatedNotch, _notchAdjustedWidth, _notchAdjustedHeight, _enableFocus, _enableBrightness, _enableVolume, _enableCalendarQuickPeek, _showWeatherOnEmptyDay, _enableNowPlaying, _hideWhileSourceIsActive, _hideWhileInFullscreen, _enableQuickPeek, _enableLockScreen, _enableHaptics, _allowNowPlayingWidgetWhenLocked, _mostRecentActivity, _idleActivity: ExpandedActivity, _forceEnableActivity, _swipeToCycleActivity, _swipeToDismiss, _swipeToSkip, _swipeToToggle`, sizes `_notchWidth, _notchHeight, _notchExpandedWidth, _notchExpandedHeight`.
- `struct NotchView`: `notchController`, `_hoverDuration`, `_notchAdjustedWidth/Height`, `_expandNotchOnHover`, `_swipeToToggle/Dismiss/Skip`, `_contrastOutline`, `_hoverDebounce`, `_cutoutScale`, `_cutoutWidthProgress`, `_cutoutContentWidthProgress`, `_cutoutScaleAnchor`.
- `struct NotchShape` (§2), `struct NotchSwipes` (§3), `class NotchSwipeMonitor`, `class NotchPanel/NotchBackdropPanel/LockPanel: NSPanel` (`canBecomeKeyWindow` override), `class SpaceManager`, `class ScreenManager`, `HapticFeedback`, `SoundManager`, `WaveformSpectrumCenter/Session`, `WaveformAnimationClock/Source`, `NSWaveformView`, `NSMarqueeTextView`, `MediaProgressLayerTrackView`, `HUDSpeed`, `AudioManager.AudioFrequencyBand`, `ProgressiveBlurView`, `VariableBlurEngine`, `MaterialBackdropLumaReader`, `ClearGlassEffectView`, `ClearGlassBorderEffectView`, `MissionControlManager`, `CalendarManager`, `WeatherManager`, `MediaManager`, `VolumeManager`.
- Views with recovered `body` addresses (95): `DummyNotch` 0x100005dc0, `NotchView` (body 0x1001e426c), `NotchLiveActivitiesView`, `NotchNotificationsView`, `MediaPlayer`, `MediaControlStrip`, `MediaProgressSlider`, `ProgressSlider`, `Waveform`, `MarqueeText`, `SliderPicker`, `CircularProgress`, settings panes… (`view_bodies.json`).

### 8. Reproduction scripts (in zip)
`chained.py` (chained-fixup binds/rebases → `fixups.json`), `swift_meta.py` (`__swift5_types/fieldmd` → `fieldmd.json`, `fieldmd_dump.txt`), `proto_meta.py` (`__swift5_proto` → `conformances.txt`, `view_bodies.json`), `parse_consts.py` (FP immediates before call sites), `build_table.py` (Appendix A), `defkeys_parse.py` (Appendix B), `annot.py` (annotates `objc_msgSend$sel` stubs from `stubs.txt`), radare2 scripts `*.r2` and their outputs `*_dis.txt`, `*_funcs*.txt`, `*_xrefs.txt`.

### 9. Not recoverable / UNVERIFIED
Literal values for `NotchSwipes` thresholds, `alignmentSpring*`, simulated-notch default size, `seekerPollingInterval`, and the exact `CASpringAnimation` mass/stiffness/damping (register-sourced after stripping); real-notch, battery, AirPods, Touch ID, multi-display and lock-screen behaviours (hardware absent on VM).

---
### Appendix A — all animation call sites (STATIC)
| address | enclosing fn | API | parameters | context (STATIC fieldmd xrefs | INFERRED nearest View.body) |
|---|---|---|---|---|
| 0x1000029b8 | sym.func.10000264c | Spring(duration:bounce:) | duration=0.35 bounce=-0.2 | near ?.body |
| 0x1000029c4 | sym.func.10000264c | Animation.spring(_:blendDuration:) | blend=0 | near ?.body |
| 0x100002a14 | sym.func.10000264c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4875 damping=1 blend=0 | near ?.body |
| 0x100004bb0 | sym.func.100004af8 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | near ?.body |
| 0x10000b0bc | sym.func.10000af24 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | LicenseManager | near FileTraySettingsView.body |
| 0x10000b770 | sym.func.10000b6f4 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | LicenseManager | near FileTraySettingsView.body |
| 0x10000b84c | sym.func.10000b6f4 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | LicenseManager | near FileTraySettingsView.body |
| 0x10000f3b4 | sym.func.10000f2e0 | Animation.easeOut(duration:) | d0=0.1 | MissionControlManager | near FileTraySettingsView.body |
| 0x10000f654 | sym.func.10000f580 | Animation.easeOut(duration:) | d0=0.1 | MissionControlManager | near FileTraySettingsView.body |
| 0x1000129c4 | sym.func.1000124f0 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | LicenseManager, _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near FileTraySettingsView.body |
| 0x1000143e4 | sym.func.100013a00 | Animation.easeOut(duration:) | d0=0.1 | near FileTraySettingsView.body |
| 0x100014d34 | sym.func.100014b20 | Animation.easeOut(duration:) | d0=0.1 | MissionControlManager | near FileTraySettingsView.body |
| 0x100015084 | sym.func.100014f84 | Animation.easeOut(duration:) | d0=0.1 | near FileTraySettingsView.body |
| 0x100015e08 | sym.func.100015c48 | Animation.easeOut(duration:) | d0=0.1 | MissionControlManager | near FileTraySettingsView.body |
| 0x100016888 | sym.func.100016844 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | near FileTraySettingsView.body |
| 0x1000168d4 | sym.func.100016844 | Animation.easeOut(duration:) | d0=0.1 d1=? | near FileTraySettingsView.body |
| 0x100016a34 | sym.func.100016918 | Animation.easeOut(duration:) | d0=? | near FileTraySettingsView.body |
| 0x100016adc | sym.func.100016918 | Animation.easeOut(duration:) | d0=? | near FileTraySettingsView.body |
| 0x100017134 | sym.func.100016f30 | Animation.easeOut(duration:) | d0=0.1 | MissionControlManager | near FileTraySettingsView.body |
| 0x100017440 | sym.func.100017330 | Animation.easeOut(duration:) | d0=0.1 | near FileTraySettingsView.body |
| 0x1000180ac | sym.func.100018078 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.6 damping=1 blend=0 | near FileTraySettingsView.body |
| 0x100018220 | sym.func.1000181ec | Animation.spring(response:dampingFraction:blendDuration:) | response=0.6 damping=1 blend=0 | near FileTraySettingsView.body |
| 0x1000183b4 | sym.func.100018360 | Spring(duration:bounce:) | duration=0.4 bounce=0.35 | near FileTraySettingsView.body |
| 0x1000183c0 | sym.func.100018360 | Animation.spring(_:blendDuration:) | blend=0 | near FileTraySettingsView.body |
| 0x100018554 | sym.func.100018520 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.6 damping=1 blend=0 | near FileTraySettingsView.body |
| 0x1000186c8 | sym.func.100018694 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.6 damping=1 blend=0 | near FileTraySettingsView.body |
| 0x100018864 | sym.func.100018808 | Spring(duration:bounce:) | duration=0.4 bounce=0.35 | near FileTraySettingsView.body |
| 0x100018870 | sym.func.100018808 | Animation.spring(_:blendDuration:) | blend=0 | near FileTraySettingsView.body |
| 0x1000210b0 | sym.func.100021088 | Duration.seconds(_:) | seconds=0.15 | near LicenseSettingsView.body |
| 0x100021234 | sym.func.100021198 | Duration.seconds(_:) | seconds=0.35 | near LicenseSettingsView.body |
| 0x100021350 | sym.func.1000212a8 | Duration.seconds(_:) | seconds=0.35 | near LicenseSettingsView.body |
| 0x100021bb8 | sym.func.1000219a4 | Spring(duration:bounce:) | duration=0.35 bounce=0.3 | VolumeManager | near LicenseSettingsView.body |
| 0x100021bc4 | sym.func.1000219a4 | Animation.spring(_:blendDuration:) | blend=0 | VolumeManager | near LicenseSettingsView.body |
| 0x10002264c | sym.func.100022440 | Spring(duration:bounce:) | duration=0.35 bounce=0.3 | VolumeManager | near LicenseSettingsView.body |
| 0x100022658 | sym.func.100022440 | Animation.spring(_:blendDuration:) | blend=0 | VolumeManager | near LicenseSettingsView.body |
| 0x100028898 | sym.func.100026634 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | AudioManager | near Snapshot.body |
| 0x10002c1cc | sym.func.10002bf1c | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near Snapshot.body |
| 0x10002c208 | sym.func.10002bf1c | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near Snapshot.body |
| 0x10002d8c0 | sym.func.10002d7c8 | Task.sleep(for:) via Clock.sleep(until:tolerance:) | d0=? | near Snapshot.body |
| 0x10002d9a0 | sym.func.10002d960 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | near Snapshot.body |
| 0x10002dadc | sym.func.10002da90 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | near Snapshot.body |
| 0x10003f098 | sym.func.10003ec48 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | LicenseManager | near FocusSettingsView.body |
| 0x10003f7b0 | sym.func.10003f780 | Animation.easeOut(duration:) | d0=0.1 | near FocusSettingsView.body |
| 0x10003fc00 | sym.func.10003fbc8 | Animation.easeOut(duration:) | d0=0.1 | near FocusSettingsView.body |
| 0x10003fd0c | sym.func.10003fcec | Duration.seconds(_:) | seconds=0.5 | near FocusSettingsView.body |
| 0x10003feb4 | sym.func.10003fdf4 | Animation.easeOut(duration:) | d0=0.1 | near FocusSettingsView.body |
| 0x10003ffd4 | sym.func.10003ff08 | Animation.easeOut(duration:) | d0=0.1 | near FocusSettingsView.body |
| 0x100049fc8 | sym.func.100049c34 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView, CalendarManager, MissionControlManager | near AboutSettingsView.body |
| 0x10004ed38 | sym.func.10004ea1c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView, LicenseManager, WeatherManager | near AboutSettingsView.body |
| 0x10005ccec | sym.func.10005cbbc | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | near anon.FakeClearGlassPreview.body |
| 0x10006c658 | sym.func.10006c614 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | near anon.WindowBackgroundDragExclusion.body |
| 0x100073d84 | sym.func.100073d64 | Duration.seconds(_:) | seconds=? | near ClearGlassBorderEffectView.body |
| 0x100082d88 | sym.func.1000823c4 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | ConnectivityManager | near SettingsWindowView.body |
| 0x1000831bc | sym.func.1000823c4 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | ConnectivityManager | near SettingsWindowView.body |
| 0x10008af68 | sym.func.10008ac34 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | near ConnectivitySettingsView.body |
| 0x10008cd9c | sym.func.10008ca90 | Animation.easeOut(duration:) | d0=0.1 | near ListToggle.body |
| 0x10008e16c | sym.func.10008e05c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | near SoundPreview.body |
| 0x100091ef8 | sym.func.100091d68 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | near SoundPreview.body |
| 0x1000935a4 | sym.func.1000934ac | Task.sleep(for:) via Clock.sleep(until:tolerance:) | d0=? | near SoundPreview.body |
| 0x100093688 | sym.func.100093644 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | near SoundPreview.body |
| 0x10009385c | sym.func.10009380c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | near SoundPreview.body |
| 0x10009bcd4 | sym.func.10009aee0 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near SoundSettingsView.body |
| 0x10009bd70 | sym.func.10009aee0 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near SoundSettingsView.body |
| 0x10009c278 | sym.func.10009aee0 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.45 damping=1 blend=0 | _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near SoundSettingsView.body |
| 0x10009c98c | sym.func.10009aee0 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near SoundSettingsView.body |
| 0x10009c9cc | sym.func.10009aee0 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near SoundSettingsView.body |
| 0x10009d784 | sym.func.10009d064 | Spring(duration:bounce:) | duration=0.35 bounce=0.3 | near SoundSettingsView.body |
| 0x10009d790 | sym.func.10009d064 | Animation.spring(_:blendDuration:) | blend=0 | near SoundSettingsView.body |
| 0x10009e0b8 | sym.func.10009dabc | Spring(duration:bounce:) | duration=0.35 bounce=0.3 | near SoundSettingsView.body |
| 0x10009e0c4 | sym.func.10009dabc | Animation.spring(_:blendDuration:) | blend=0 | near SoundSettingsView.body |
| 0x10009e744 | sym.func.10009e458 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.15 damping=1 blend=0 | near SoundSettingsView.body |
| 0x10009fecc | sym.func.10009fd18 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.15 damping=1 blend=0 | near SoundSettingsView.body |
| 0x1000a0404 | sym.func.1000a0118 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.15 damping=1 blend=0 | near SoundSettingsView.body |
| 0x1000a089c | sym.func.1000a0818 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.15 damping=1 blend=0 | near SoundSettingsView.body |
| 0x1000a66c4 | sym.func.1000a5440 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | CalendarManager, LicenseManager, WeatherManager | near VerticalVolumeSlider.body |
| 0x1000a779c | sym.func.1000a73c8 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | CalendarManager, MissionControlManager | near VerticalVolumeSlider.body |
| 0x1000a9838 | sym.func.1000a91d4 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | WeatherManager | near VerticalVolumeSlider.body |
| 0x1000ac614 | sym.func.1000ac264 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | near VerticalVolumeSlider.body |
| 0x1000ba908 | sym.func.1000ba2dc | Animation.spring(response:dampingFraction:blendDuration:) | response=0.3 damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000bac00 | sym.func.1000ba2dc | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000bae58 | sym.func.1000ba2dc | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000bb01c | sym.func.1000ba2dc | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000bb25c | sym.func.1000ba2dc | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000bb2f0 | sym.func.1000ba2dc | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000bb6b8 | sym.func.1000bb4e0 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000bc030 | sym.func.1000bb968 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | CalendarManager, MissionControlManager | near CalendarSettingsView.body |
| 0x1000bca10 | sym.func.1000bc94c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000bcb34 | sym.func.1000bc94c | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000bcb5c | sym.func.1000bc94c | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000bcf64 | sym.func.1000bcc7c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000bd0c4 | sym.func.1000bcc7c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.3 damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000be734 | sym.func.1000be59c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000c10e8 | sym.func.1000c0c38 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near CalendarSettingsView.body |
| 0x1000c11a8 | sym.func.1000c0c38 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near CalendarSettingsView.body |
| 0x1000c1784 | sym.func.1000c0c38 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near CalendarSettingsView.body |
| 0x1000c192c | sym.func.1000c0c38 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near CalendarSettingsView.body |
| 0x1000c2a64 | sym.func.1000c2134 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000c2a9c | sym.func.1000c2134 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000c2df8 | sym.func.1000c2134 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000c2f70 | sym.func.1000c2134 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000c2fa8 | sym.func.1000c2134 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000c342c | sym.func.1000c2134 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000c3d1c | sym.func.1000c3b9c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000c44a4 | sym.func.1000c42f0 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000c46d0 | sym.func.1000c4504 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000c5678 | sym.func.1000c5004 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000c6018 | sym.func.1000c5d84 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000c6068 | sym.func.1000c5d84 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000c60e0 | sym.func.1000c5d84 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000c6174 | sym.func.1000c5d84 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000c68a0 | sym.func.1000c634c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000c77f4 | sym.func.1000c7620 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000c7810 | sym.func.1000c7620 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near CalendarSettingsView.body |
| 0x1000cf7f4 | sym.func.1000cefbc | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | near AppIcon.body |
| 0x1000d0848 | sym.func.1000d051c | Spring(duration:bounce:) | duration=0.6 bounce=0.4 | MediaManager | near AppIcon.body |
| 0x1000d0854 | sym.func.1000d051c | Animation.spring(_:blendDuration:) | blend=0 | MediaManager | near AppIcon.body |
| 0x1000d1960 | sym.func.1000d09f0 | Spring(duration:bounce:) | duration=? bounce=0.4 | MediaManager | near AppIcon.body |
| 0x1000d196c | sym.func.1000d09f0 | Animation.spring(_:blendDuration:) | blend=0 | MediaManager | near AppIcon.body |
| 0x1000d48b0 | sym.func.1000d45cc | Spring(duration:bounce:) | duration=0.5 bounce=0.45 | MediaManager, FocusManager | near AppIcon.body |
| 0x1000d48bc | sym.func.1000d45cc | Animation.spring(_:blendDuration:) | blend=0 | MediaManager, FocusManager | near AppIcon.body |
| 0x1000d49b4 | sym.func.1000d45cc | Animation.spring(response:dampingFraction:blendDuration:) | response=0.3 damping=1 blend=0 | MediaManager, FocusManager | near AppIcon.body |
| 0x1000dca3c | sym.func.1000dc610 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MediaManager, MissionControlManager, NotchController | near MediaPlayer.body |
| 0x1000dcab0 | sym.func.1000dc610 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MediaManager, MissionControlManager, NotchController | near MediaPlayer.body |
| 0x1000dcb88 | sym.func.1000dc610 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MediaManager, MissionControlManager, NotchController | near MediaPlayer.body |
| 0x1000dcc00 | sym.func.1000dc610 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MediaManager, MissionControlManager, NotchController | near MediaPlayer.body |
| 0x1000de5b0 | sym.func.1000de37c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | MediaManager, _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near MediaPlayer.body |
| 0x1000df208 | sym.func.1000def5c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | MediaManager | near MediaPlayer.body |
| 0x1000df438 | sym.func.1000def5c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | MediaManager | near MediaPlayer.body |
| 0x1000df724 | sym.func.1000def5c | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MediaManager | near MediaPlayer.body |
| 0x1000df784 | sym.func.1000def5c | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MediaManager | near MediaPlayer.body |
| 0x1000dfb0c | sym.func.1000def5c | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MediaManager | near MediaPlayer.body |
| 0x1000dfb64 | sym.func.1000def5c | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MediaManager | near MediaPlayer.body |
| 0x1000e00fc | sym.func.1000e00d0 | Duration.seconds(_:) | seconds=0.45 | near MediaPlayer.body |
| 0x1000e0904 | sym.func.1000e0394 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MediaManager | near MediaPlayer.body |
| 0x1000e0b7c | sym.func.1000e0394 | Spring(duration:bounce:) | duration=0.35 bounce=0.7 | MediaManager | near MediaPlayer.body |
| 0x1000e0b88 | sym.func.1000e0394 | Animation.spring(_:blendDuration:) | blend=0 | MediaManager | near MediaPlayer.body |
| 0x1000e0bb4 | sym.func.1000e0394 | Animation.delay(_:) | d0=0.1 d1=? | MediaManager | near MediaPlayer.body |
| 0x1000e0be0 | sym.func.1000e0394 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | MediaManager | near MediaPlayer.body |
| 0x1000e111c | sym.func.1000e10fc | Duration.seconds(_:) | seconds=0.25 | near MediaPlayer.body |
| 0x1000e20c4 | sym.func.1000e20a4 | Duration.seconds(_:) | seconds=0.25 | near MediaPlayer.body |
| 0x1000e24c8 | sym.func.1000e2138 | Spring(duration:bounce:) | duration=0.3 bounce=0.25 | MediaManager | near MediaPlayer.body |
| 0x1000e24d4 | sym.func.1000e2138 | Animation.spring(_:blendDuration:) | blend=0 | MediaManager | near MediaPlayer.body |
| 0x1000e3db0 | sym.func.1000e3d90 | Duration.seconds(_:) | seconds=0.5 | near MediaPlayer.body |
| 0x1000e4700 | sym.func.1000e4690 | Spring(duration:bounce:) | duration=0.3 bounce=0.45 | near MediaPlayer.body |
| 0x1000e470c | sym.func.1000e4690 | Animation.spring(_:blendDuration:) | blend=0 | near MediaPlayer.body |
| 0x1000e4740 | sym.func.1000e4690 | Animation.delay(_:) | d0=0.05 d1=? | near MediaPlayer.body |
| 0x1000e4ee0 | sym.func.1000e4d8c | Spring(duration:bounce:) | duration=0.6 bounce=0.35 | MissionControlManager, NotchController | near MediaPlayer.body |
| 0x1000e4eec | sym.func.1000e4d8c | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near MediaPlayer.body |
| 0x1000e5084 | sym.func.1000e4d8c | Spring(duration:bounce:) | duration=0.6 bounce=0.35 | MissionControlManager, NotchController | near MediaPlayer.body |
| 0x1000e5090 | sym.func.1000e4d8c | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near MediaPlayer.body |
| 0x1000e5190 | sym.func.1000e4d8c | Spring(duration:bounce:) | duration=0.4 bounce=0.35 | MissionControlManager, NotchController | near MediaPlayer.body |
| 0x1000e519c | sym.func.1000e4d8c | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near MediaPlayer.body |
| 0x1000e5c78 | sym.func.1000e5664 | Spring(duration:bounce:) | duration=0.3 bounce=0.25 | MissionControlManager, NotchController, _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near MediaPlayer.body |
| 0x1000e5c84 | sym.func.1000e5664 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near MediaPlayer.body |
| 0x1000e6cf0 | sym.func.1000e6b9c | Spring(duration:bounce:) | duration=0.6 bounce=0.35 | MissionControlManager, NotchController | near MediaPlayer.body |
| 0x1000e6cfc | sym.func.1000e6b9c | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near MediaPlayer.body |
| 0x1000e6e90 | sym.func.1000e6b9c | Spring(duration:bounce:) | duration=0.6 bounce=0.35 | MissionControlManager, NotchController | near MediaPlayer.body |
| 0x1000e6e9c | sym.func.1000e6b9c | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near MediaPlayer.body |
| 0x1000e6f9c | sym.func.1000e6b9c | Spring(duration:bounce:) | duration=0.4 bounce=0.35 | MissionControlManager, NotchController | near MediaPlayer.body |
| 0x1000e6fa8 | sym.func.1000e6b9c | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near MediaPlayer.body |
| 0x1000e7a7c | sym.func.1000e7470 | Spring(duration:bounce:) | duration=0.3 bounce=0.25 | MissionControlManager, NotchController, _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near MediaPlayer.body |
| 0x1000e7a88 | sym.func.1000e7470 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near MediaPlayer.body |
| 0x1000e9604 | sym.func.1000e90b0 | Spring(duration:bounce:) | duration=0.35 bounce=0.4 | MediaManager, _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near MediaControlStrip.body |
| 0x1000e9610 | sym.func.1000e90b0 | Animation.spring(_:blendDuration:) | blend=0 | MediaManager, _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near MediaControlStrip.body |
| 0x1000e963c | sym.func.1000e90b0 | Animation.delay(_:) | d0=0.1 d1=? | MediaManager, _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near MediaControlStrip.body |
| 0x1000e9664 | sym.func.1000e90b0 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.3 damping=1 blend=0 | MediaManager, _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near MediaControlStrip.body |
| 0x1000e9b68 | sym.func.1000e90b0 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.3 damping=1 blend=0 | MediaManager, _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near MediaControlStrip.body |
| 0x1000e9b98 | sym.func.1000e90b0 | Spring(duration:bounce:) | duration=0.35 bounce=0.4 | MediaManager, _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near MediaControlStrip.body |
| 0x1000e9ba4 | sym.func.1000e90b0 | Animation.spring(_:blendDuration:) | blend=0 | MediaManager, _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near MediaControlStrip.body |
| 0x1000e9bd0 | sym.func.1000e90b0 | Animation.delay(_:) | d0=0.1 d1=? | MediaManager, _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near MediaControlStrip.body |
| 0x1000f14b0 | sym.func.1000f1318 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.45 damping=1 blend=0 | near LoopingVideoRepresented.body |
| 0x1000f415c | sym.func.1000f3bb4 | Spring(duration:bounce:) | duration=0.35 bounce=0.3 | near PlainTextField.body |
| 0x1000f4168 | sym.func.1000f3bb4 | Animation.spring(_:blendDuration:) | blend=0 | near PlainTextField.body |
| 0x1000f4550 | sym.func.1000f44f0 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | near PlainTextField.body |
| 0x1000ff50c | sym.func.1000ff1dc | Animation.spring(response:dampingFraction:blendDuration:) | response=0.3 damping=1 blend=0 | FocusManager | near anon.CheckboxMark.body |
| 0x1000ff68c | sym.func.1000ff1dc | Animation.spring(response:dampingFraction:blendDuration:) | response=0.3 damping=1 blend=0 | FocusManager | near anon.CheckboxMark.body |
| 0x1000ff7f4 | sym.func.1000ff1dc | Animation.spring(response:dampingFraction:blendDuration:) | response=0.3 damping=1 blend=0 | FocusManager | near anon.CheckboxMark.body |
| 0x1000ffd88 | sym.func.1000ff1dc | Animation.spring(response:dampingFraction:blendDuration:) | response=0.3 damping=1 blend=0 | FocusManager | near anon.CheckboxMark.body |
| 0x10010a878 | sym.func.10010a84c | Animation.spring(response:dampingFraction:blendDuration:) | response=1.2 damping=1 blend=0 | near anon.CheckboxMark.body |
| 0x10011419c | sym.func.100114168 | Duration.seconds(_:) | seconds=0.8 | near CalendarPermissionView.body |
| 0x1001141b8 | sym.func.100114168 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4875 damping=1 blend=0 | near CalendarPermissionView.body |
| 0x1001141e4 | sym.func.100114168 | Spring(duration:bounce:) | duration=0.35 bounce=-0.2 | near CalendarPermissionView.body |
| 0x1001141f0 | sym.func.100114168 | Animation.spring(_:blendDuration:) | blend=0 | near CalendarPermissionView.body |
| 0x1001143c8 | sym.func.1001142d0 | Task.sleep(for:) via Clock.sleep(until:tolerance:) | d0=? | near CalendarPermissionView.body |
| 0x1001146c4 | sym.func.100114470 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | near CalendarPermissionView.body |
| 0x100114a64 | sym.func.10011480c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | near CalendarPermissionView.body |
| 0x100114cc8 | sym.func.100114be4 | Duration.seconds(_:) | seconds=0.35 | near CalendarPermissionView.body |
| 0x100114e34 | sym.func.100114d40 | Duration.seconds(_:) | seconds=0.35 | near CalendarPermissionView.body |
| 0x100119e0c | sym.func.100119c80 | Spring(duration:bounce:) | duration=0.35 bounce=0.3 | MissionControlManager, BrightnessManager | near AccessibilityView.body |
| 0x100119e18 | sym.func.100119c80 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, BrightnessManager | near AccessibilityView.body |
| 0x10011cf00 | sym.func.10011ce10 | Spring(duration:bounce:) | duration=0.35 bounce=0.3 | BrightnessManager | near AccessibilityView.body |
| 0x10011cf0c | sym.func.10011ce10 | Animation.spring(_:blendDuration:) | blend=0 | BrightnessManager | near AccessibilityView.body |
| 0x10012fc8c | sym.func.10012fc6c | Duration.seconds(_:) | seconds=0.5 | near GlassEffectView.body |
| 0x1001304a8 | sym.func.10013047c | Duration.seconds(_:) | seconds=0.2 | near GlassEffectView.body |
| 0x10013554c | sym.func.100135418 | Task.sleep(for:) via Clock.sleep(until:tolerance:) | d0=? | near GlassEffectView.body |
| 0x10013d670 | sym.func.10013cae0 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near GlassEffectView.body |
| 0x10013d74c | sym.func.10013cae0 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near GlassEffectView.body |
| 0x10014168c | sym.func.100141648 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | near GlassEffectView.body |
| 0x100142a44 | sym.func.100142a08 | Animation.easeOut(duration:) | d0=0.1 | near GlassEffectView.body |
| 0x100149a14 | sym.func.100149890 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | CalendarManager, MissionControlManager | near ValueAdjuster.body |
| 0x100149b68 | sym.func.100149890 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | CalendarManager, MissionControlManager | near ValueAdjuster.body |
| 0x10014ab68 | sym.func.10014a920 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.3 damping=1 blend=0 | CalendarManager, MissionControlManager | near ValueAdjuster.body |
| 0x10014b234 | sym.func.10014a920 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | CalendarManager, MissionControlManager | near ValueAdjuster.body |
| 0x10014b880 | sym.func.10014b4d8 | Animation.easeInOut(duration:) | d0=0.2 | CalendarManager, MissionControlManager | near ValueAdjuster.body |
| 0x10014d304 | sym.func.10014ce94 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | near ValueAdjuster.body |
| 0x100157780 | sym.func.100157688 | Task.sleep(for:) via Clock.sleep(until:tolerance:) | d0=? | near PreviewWallpaperBackground.body |
| 0x10015d73c | sym.func.10015d6bc | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | near PreviewWallpaperBackground.body |
| 0x10015e27c | sym.func.10015e234 | Duration.seconds(_:) | seconds=? | near PreviewWallpaperBackground.body |
| 0x10015f69c | sym.func.10015f5b8 | Duration.seconds(_:) | seconds=? | near PreviewWallpaperBackground.body |
| 0x10015f8a0 | sym.func.10015f7a8 | Task.sleep(for:) via Clock.sleep(until:tolerance:) | d0=? | near PreviewWallpaperBackground.body |
| 0x10015fa04 | sym.func.10015f940 | Duration.seconds(_:) | seconds=? | near PreviewWallpaperBackground.body |
| 0x1001733c8 | sym.func.1001732d8 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near PreviewWallpaperBackground.body |
| 0x1001733d4 | sym.func.1001732d8 | Animation.delay(_:) | d0=? d1=? | near PreviewWallpaperBackground.body |
| 0x100173400 | sym.func.1001732d8 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near PreviewWallpaperBackground.body |
| 0x10017340c | sym.func.1001732d8 | Animation.delay(_:) | d0=? d1=? | near PreviewWallpaperBackground.body |
| 0x10017661c | sym.func.1001763e8 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | MediaManager | near PreviewWallpaperBackground.body |
| 0x100179d14 | sym.func.100179b48 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | BatteryManager, ConnectivityManager, FocusManager | near TriangleShape.body |
| 0x100179dec | sym.func.100179b48 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | BatteryManager, ConnectivityManager, FocusManager | near TriangleShape.body |
| 0x100179e84 | sym.func.100179b48 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | BatteryManager, ConnectivityManager, FocusManager | near TriangleShape.body |
| 0x100179f60 | sym.func.100179b48 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | BatteryManager, ConnectivityManager, FocusManager | near TriangleShape.body |
| 0x10017a108 | sym.func.100179b48 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | BatteryManager, ConnectivityManager, FocusManager | near TriangleShape.body |
| 0x10017a428 | sym.func.10017a238 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | ConnectivityManager, BatteryManager, FocusManager | near TriangleShape.body |
| 0x10017a598 | sym.func.10017a238 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | ConnectivityManager, BatteryManager, FocusManager | near TriangleShape.body |
| 0x10017a678 | sym.func.10017a238 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | ConnectivityManager, BatteryManager, FocusManager | near TriangleShape.body |
| 0x10017a710 | sym.func.10017a238 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | ConnectivityManager, BatteryManager, FocusManager | near TriangleShape.body |
| 0x10017a788 | sym.func.10017a238 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | ConnectivityManager, BatteryManager, FocusManager | near TriangleShape.body |
| 0x10017a904 | sym.func.10017a238 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | ConnectivityManager, BatteryManager, FocusManager | near TriangleShape.body |
| 0x10017a9d8 | sym.func.10017a238 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | ConnectivityManager, BatteryManager, FocusManager | near TriangleShape.body |
| 0x10017aa38 | sym.func.10017a238 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | ConnectivityManager, BatteryManager, FocusManager | near TriangleShape.body |
| 0x10017aaf0 | sym.func.10017a238 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | ConnectivityManager, BatteryManager, FocusManager | near TriangleShape.body |
| 0x10017abdc | sym.func.10017a238 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | ConnectivityManager, BatteryManager, FocusManager | near TriangleShape.body |
| 0x10017b0e0 | sym.func.10017a238 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | ConnectivityManager, BatteryManager, FocusManager | near TriangleShape.body |
| 0x10017b1b4 | sym.func.10017a238 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | ConnectivityManager, BatteryManager, FocusManager | near TriangleShape.body |
| 0x10017b45c | sym.func.10017b354 | Spring(duration:bounce:) | duration=0.6 bounce=0.3 | MediaManager | near TriangleShape.body |
| 0x10017b468 | sym.func.10017b354 | Animation.spring(_:blendDuration:) | blend=0 | MediaManager | near TriangleShape.body |
| 0x10017b494 | sym.func.10017b354 | Animation.delay(_:) | d0=0.075 d1=? | MediaManager | near TriangleShape.body |
| 0x10017b5bc | sym.func.10017b354 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | MediaManager | near TriangleShape.body |
| 0x10017b5e4 | sym.func.10017b354 | Spring(duration:bounce:) | duration=0.6 bounce=0.3 | MediaManager | near TriangleShape.body |
| 0x10017b5f0 | sym.func.10017b354 | Animation.spring(_:blendDuration:) | blend=0 | MediaManager | near TriangleShape.body |
| 0x10018120c | sym.func.100180cfc | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | BatteryManager | near TriangleShape.body |
| 0x100182190 | sym.func.100181f58 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | near TriangleShape.body |
| 0x100183888 | sym.func.100183520 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | near TriangleShape.body |
| 0x1001844e4 | sym.func.100183f68 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | WeatherManager | near TriangleShape.body |
| 0x1001845b4 | sym.func.100183f68 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | WeatherManager | near TriangleShape.body |
| 0x1001849bc | sym.func.100183f68 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | WeatherManager | near TriangleShape.body |
| 0x100185a04 | sym.func.100185814 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | near TriangleShape.body |
| 0x10018ccd8 | sym.func.10018c9f4 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | near LockView.body |
| 0x100195858 | sym.func.100195738 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near NotchExpandedView.body |
| 0x100195868 | sym.func.100195738 | Animation.delay(_:) | d0=? d1=? | near NotchExpandedView.body |
| 0x1001958a8 | sym.func.100195738 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near NotchExpandedView.body |
| 0x1001958b4 | sym.func.100195738 | Animation.delay(_:) | d0=? d1=? | near NotchExpandedView.body |
| 0x1001958e0 | sym.func.100195738 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near NotchExpandedView.body |
| 0x1001958ec | sym.func.100195738 | Animation.delay(_:) | d0=? d1=? | near NotchExpandedView.body |
| 0x10019c648 | sym.func.10019c570 | Animation.easeOut(duration:) | d0=0.1 | LicenseManager | near BatterySettingsView.body |
| 0x1001a5b8c | sym.func.1001a5208 | Animation.easeOut(duration:) | d0=0.1 | near BatterySettingsView.body |
| 0x1001a63c8 | sym.func.1001a61b4 | Animation.easeOut(duration:) | d0=0.1 | MissionControlManager | near BatterySettingsView.body |
| 0x1001a6718 | sym.func.1001a6618 | Animation.easeOut(duration:) | d0=0.1 | near BatterySettingsView.body |
| 0x1001a8fd0 | sym.func.1001a8ebc | Spring(duration:bounce:) | duration=0.35 bounce=0.3 | LicenseManager, MissionControlManager | near BatterySettingsView.body |
| 0x1001a8fdc | sym.func.1001a8ebc | Animation.spring(_:blendDuration:) | blend=0 | LicenseManager, MissionControlManager | near BatterySettingsView.body |
| 0x1001a98d8 | sym.func.1001a989c | Animation.easeOut(duration:) | d0=0.1 | near BatterySettingsView.body |
| 0x1001a9a74 | sym.func.1001a9a40 | Animation.easeOut(duration:) | d0=0.1 | MissionControlManager | near BatterySettingsView.body |
| 0x1001a9fec | sym.func.1001a9fa8 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | near BatterySettingsView.body |
| 0x1001aa038 | sym.func.1001a9fa8 | Animation.easeOut(duration:) | d0=0.1 d1=? | near BatterySettingsView.body |
| 0x1001aa198 | sym.func.1001aa07c | Animation.easeOut(duration:) | d0=? | near BatterySettingsView.body |
| 0x1001aa240 | sym.func.1001aa07c | Animation.easeOut(duration:) | d0=? | near BatterySettingsView.body |
| 0x1001aa4cc | sym.func.1001aa49c | Animation.easeOut(duration:) | d0=0.1 | near BatterySettingsView.body |
| 0x1001aa988 | sym.func.1001aa61c | Animation.easeOut(duration:) | d0=0.1 | MissionControlManager | near BatterySettingsView.body |
| 0x1001aab88 | sym.func.1001aaa78 | Animation.easeOut(duration:) | d0=0.1 | near BatterySettingsView.body |
| 0x1001aae5c | sym.func.1001aad9c | Spring(duration:bounce:) | duration=0.35 bounce=0.3 | near BatterySettingsView.body |
| 0x1001aae68 | sym.func.1001aad9c | Animation.spring(_:blendDuration:) | blend=0 | near BatterySettingsView.body |
| 0x1001ab244 | sym.func.1001ab210 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.6 damping=1 blend=0 | near BatterySettingsView.body |
| 0x1001ab374 | sym.func.1001ab340 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.6 damping=1 blend=0 | near BatterySettingsView.body |
| 0x1001ab4c4 | sym.func.1001ab470 | Spring(duration:bounce:) | duration=0.4 bounce=0.35 | near BatterySettingsView.body |
| 0x1001ab4d0 | sym.func.1001ab470 | Animation.spring(_:blendDuration:) | blend=0 | near BatterySettingsView.body |
| 0x1001ab620 | sym.func.1001ab5ec | Animation.spring(response:dampingFraction:blendDuration:) | response=0.6 damping=1 blend=0 | near BatterySettingsView.body |
| 0x1001ab750 | sym.func.1001ab71c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.6 damping=1 blend=0 | near BatterySettingsView.body |
| 0x1001ab8a8 | sym.func.1001ab84c | Spring(duration:bounce:) | duration=0.4 bounce=0.35 | near BatterySettingsView.body |
| 0x1001ab8b4 | sym.func.1001ab84c | Animation.spring(_:blendDuration:) | blend=0 | near BatterySettingsView.body |
| 0x1001b31f0 | sym.func.1001b30e0 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | near LicenseView.body |
| 0x1001b6a40 | sym.func.1001b6914 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | near LicenseView.body |
| 0x1001b6fec | sym.func.1001b6ef4 | Task.sleep(for:) via Clock.sleep(until:tolerance:) | d0=? | near LicenseView.body |
| 0x1001bcb40 | sym.func.1001bc57c | Animation.easeOut(duration:) | d0=? | near DisplaySettingsView.body |
| 0x1001bcc50 | sym.func.1001bc57c | Animation.easeOut(duration:) | d0=? | near DisplaySettingsView.body |
| 0x1001c0a40 | sym.func.1001c0a20 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | NotchController, MissionControlManager | near InfoView.body |
| 0x1001c0a8c | sym.func.1001c0a20 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | NotchController, MissionControlManager | near InfoView.body |
| 0x1001c0e98 | sym.func.1001c0d78 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c0ee4 | sym.func.1001c0d78 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c1510 | sym.func.1001c14b4 | Spring(duration:bounce:) | duration=0.45 bounce=0.4 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c151c | sym.func.1001c14b4 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c1e84 | sym.func.1001c19c8 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | MissionControlManager, NotchController, MediaManager | near InfoView.body |
| 0x1001c1f64 | sym.func.1001c19c8 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | MissionControlManager, NotchController, MediaManager | near InfoView.body |
| 0x1001c2068 | sym.func.1001c19c8 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | MissionControlManager, NotchController, MediaManager | near InfoView.body |
| 0x1001c2628 | sym.func.1001c2608 | Duration.seconds(_:) | seconds=? | near InfoView.body |
| 0x1001c2778 | sym.func.1001c2710 | Spring(duration:bounce:) | duration=? bounce=0.4 | near InfoView.body |
| 0x1001c2784 | sym.func.1001c2710 | Animation.spring(_:blendDuration:) | blend=0 | near InfoView.body |
| 0x1001c27d4 | sym.func.1001c2710 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near InfoView.body |
| 0x1001c2814 | sym.func.1001c2710 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | near InfoView.body |
| 0x1001c28e8 | sym.func.1001c2870 | Spring(duration:bounce:) | duration=? bounce=0.4 | near InfoView.body |
| 0x1001c28f4 | sym.func.1001c2870 | Animation.spring(_:blendDuration:) | blend=0 | near InfoView.body |
| 0x1001c2948 | sym.func.1001c2870 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near InfoView.body |
| 0x1001c2988 | sym.func.1001c2870 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | near InfoView.body |
| 0x1001c2e8c | sym.func.1001c2e10 | Spring(duration:bounce:) | duration=? bounce=0.4 | NotchController, MissionControlManager | near InfoView.body |
| 0x1001c2e98 | sym.func.1001c2e10 | Animation.spring(_:blendDuration:) | blend=0 | NotchController, MissionControlManager | near InfoView.body |
| 0x1001c2eec | sym.func.1001c2e10 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | NotchController, MissionControlManager | near InfoView.body |
| 0x1001c2f2c | sym.func.1001c2e10 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | NotchController, MissionControlManager | near InfoView.body |
| 0x1001c35b4 | sym.func.1001c3080 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | MissionControlManager, NotchController, MediaManager | near InfoView.body |
| 0x1001c36a0 | sym.func.1001c3080 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | MissionControlManager, NotchController, MediaManager | near InfoView.body |
| 0x1001c374c | sym.func.1001c3080 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | MissionControlManager, NotchController, MediaManager | near InfoView.body |
| 0x1001c4d78 | sym.func.1001c4094 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | MissionControlManager, NotchController, MediaManager | near InfoView.body |
| 0x1001c5c88 | sym.func.1001c5c44 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.35 damping=1 blend=0 | near InfoView.body |
| 0x1001c5e70 | sym.func.1001c5e14 | Spring(duration:bounce:) | duration=0.45 bounce=0.4 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c5e7c | sym.func.1001c5e14 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c6cd4 | sym.func.1001c613c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | MissionControlManager, NotchController, CalendarManager | near InfoView.body |
| 0x1001c6f1c | sym.func.1001c613c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | MissionControlManager, NotchController, CalendarManager | near InfoView.body |
| 0x1001c7e54 | sym.func.1001c7e04 | Spring(duration:bounce:) | duration=? bounce=0.3 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c7e60 | sym.func.1001c7e04 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c7e84 | sym.func.1001c7e04 | Spring(duration:bounce:) | duration=? bounce=0 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c7e90 | sym.func.1001c7e04 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c80b8 | sym.func.1001c8080 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near InfoView.body |
| 0x1001c81c4 | sym.func.1001c81a4 | Duration.seconds(_:) | seconds=? | near InfoView.body |
| 0x1001c82f8 | sym.func.1001c82ac | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c8434 | sym.func.1001c83d8 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c8708 | sym.func.1001c869c | Spring(duration:bounce:) | duration=? bounce=0.3 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c8714 | sym.func.1001c869c | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c8738 | sym.func.1001c869c | Spring(duration:bounce:) | duration=? bounce=0 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c8744 | sym.func.1001c869c | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c8918 | sym.func.1001c869c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.55 damping=1 blend=0 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c8944 | sym.func.1001c869c | Spring(duration:bounce:) | duration=0.4 bounce=-0.2 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c8950 | sym.func.1001c869c | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c8ba4 | sym.func.1001c869c | Spring(duration:bounce:) | duration=? bounce=0.3 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c8bb0 | sym.func.1001c869c | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c8be0 | sym.func.1001c869c | Spring(duration:bounce:) | duration=? bounce=-0.2 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c8bec | sym.func.1001c869c | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001c8f00 | sym.func.1001c8ebc | Animation.spring(response:dampingFraction:blendDuration:) | response=0.35 damping=1 blend=0 | near InfoView.body |
| 0x1001c93b4 | sym.func.1001c9350 | Spring(duration:bounce:) | duration=? bounce=0.4 | MissionControlManager | near InfoView.body |
| 0x1001c93c0 | sym.func.1001c9350 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager | near InfoView.body |
| 0x1001c9414 | sym.func.1001c9350 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MissionControlManager | near InfoView.body |
| 0x1001c9700 | sym.func.1001c96d4 | Duration.seconds(_:) | seconds=0.45 | near InfoView.body |
| 0x1001cdf50 | sym.func.1001cdbc8 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001ce0e8 | sym.func.1001cdbc8 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MissionControlManager, NotchController | near InfoView.body |
| 0x1001cf2c4 | sym.func.1001cf294 | Animation.easeOut(duration:) | d0=0.4 | near NotchBackdropView.body |
| 0x1001d89fc | sym.func.1001d7f48 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.35 damping=1 blend=0 | NotchController, MissionControlManager | near NotchProgressiveBlurView.body |
| 0x1001e1044 | sym.func.1001e0d10 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | near NotchProgressiveBlurView.body |
| 0x1001e1084 | sym.func.1001e0d10 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | near NotchProgressiveBlurView.body |
| 0x1001e10bc | sym.func.1001e0d10 | Duration.seconds(_:) | seconds=0.275 | near NotchProgressiveBlurView.body |
| 0x1001e1384 | sym.func.1001e12e4 | Spring(duration:bounce:) | duration=? bounce=0.35 | near NotchProgressiveBlurView.body |
| 0x1001e1390 | sym.func.1001e12e4 | Animation.spring(_:blendDuration:) | blend=0 | near NotchProgressiveBlurView.body |
| 0x1001e13e0 | sym.func.1001e12e4 | Duration.seconds(_:) | seconds=? | near NotchProgressiveBlurView.body |
| 0x1001e1540 | sym.func.1001e14d4 | Spring(duration:bounce:) | duration=? bounce=0.325 | near NotchProgressiveBlurView.body |
| 0x1001e154c | sym.func.1001e14d4 | Animation.spring(_:blendDuration:) | blend=0 | near NotchProgressiveBlurView.body |
| 0x1001e1598 | sym.func.1001e14d4 | Spring(duration:bounce:) | duration=? bounce=0.25 | near NotchProgressiveBlurView.body |
| 0x1001e15a4 | sym.func.1001e14d4 | Animation.spring(_:blendDuration:) | blend=0 | near NotchProgressiveBlurView.body |
| 0x1001e169c | sym.func.1001e161c | Spring(duration:bounce:) | duration=? bounce=0.325 | near NotchProgressiveBlurView.body |
| 0x1001e16a8 | sym.func.1001e161c | Animation.spring(_:blendDuration:) | blend=0 | near NotchProgressiveBlurView.body |
| 0x1001e16f8 | sym.func.1001e161c | Spring(duration:bounce:) | duration=? bounce=0.25 | near NotchProgressiveBlurView.body |
| 0x1001e1704 | sym.func.1001e161c | Animation.spring(_:blendDuration:) | blend=0 | near NotchProgressiveBlurView.body |
| 0x1001e1884 | sym.func.1001e17f0 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | near NotchProgressiveBlurView.body |
| 0x1001e1994 | sym.func.1001e18f0 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | near NotchProgressiveBlurView.body |
| 0x1001e2ec8 | sym.func.1001e1b5c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.35 damping=1 blend=0 | MissionControlManager, NotchController, MediaManager | near NotchProgressiveBlurView.body |
| 0x1001e2f0c | sym.func.1001e1b5c | Spring(duration:bounce:) | duration=0.35 bounce=? | MissionControlManager, NotchController, MediaManager | near NotchProgressiveBlurView.body |
| 0x1001e2f18 | sym.func.1001e1b5c | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, MediaManager | near NotchProgressiveBlurView.body |
| 0x1001e30e8 | sym.func.1001e3084 | Duration.seconds(_:) | seconds=? | near NotchProgressiveBlurView.body |
| 0x1001e3564 | sym.func.1001e3440 | Spring(duration:bounce:) | duration=0.6 bounce=0.35 | MissionControlManager, NotchController | near NotchProgressiveBlurView.body |
| 0x1001e3570 | sym.func.1001e3440 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near NotchProgressiveBlurView.body |
| 0x1001e37d0 | sym.func.1001e36a8 | Spring(duration:bounce:) | duration=0.6 bounce=0.35 | MissionControlManager, NotchController | near NotchProgressiveBlurView.body |
| 0x1001e37dc | sym.func.1001e36a8 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near NotchProgressiveBlurView.body |
| 0x1001eb5a0 | sym.func.1001eb370 | Spring(duration:bounce:) | duration=0.5 bounce=0.375 | MissionControlManager, NotchController, MediaManager | near NotchView.body |
| 0x1001eb5ac | sym.func.1001eb370 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, MediaManager | near NotchView.body |
| 0x1001eb644 | sym.func.1001eb370 | Spring(duration:bounce:) | duration=0.5 bounce=0.375 | MissionControlManager, NotchController, MediaManager | near NotchView.body |
| 0x1001eb650 | sym.func.1001eb370 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, MediaManager | near NotchView.body |
| 0x1001ec7dc | sym.func.1001ec300 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MissionControlManager, NotchController, CalendarManager | near NotchView.body |
| 0x1001ec8bc | sym.func.1001ec300 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MissionControlManager, NotchController, CalendarManager | near NotchView.body |
| 0x1001edbe4 | sym.func.1001edb2c | Spring(duration:bounce:) | duration=0.5 bounce=0.375 | MediaManager | near NotchLiveActivitiesView.body |
| 0x1001edbf4 | sym.func.1001edb2c | Animation.spring(_:blendDuration:) | blend=0 | MediaManager | near NotchLiveActivitiesView.body |
| 0x1001edcd4 | sym.func.1001edb2c | Spring(duration:bounce:) | duration=0.5 bounce=0.375 | MediaManager | near NotchLiveActivitiesView.body |
| 0x1001edce0 | sym.func.1001edb2c | Animation.spring(_:blendDuration:) | blend=0 | MediaManager | near NotchLiveActivitiesView.body |
| 0x1001edf8c | sym.func.1001edb2c | Spring(duration:bounce:) | duration=? bounce=0.375 | MediaManager | near NotchLiveActivitiesView.body |
| 0x1001edf98 | sym.func.1001edb2c | Animation.spring(_:blendDuration:) | blend=0 | MediaManager | near NotchLiveActivitiesView.body |
| 0x1001ee15c | sym.func.1001edb2c | Spring(duration:bounce:) | duration=? bounce=0.375 | MediaManager | near NotchLiveActivitiesView.body |
| 0x1001ee168 | sym.func.1001edb2c | Animation.spring(_:blendDuration:) | blend=0 | MediaManager | near NotchLiveActivitiesView.body |
| 0x1001efc30 | sym.func.1001ef310 | Spring(duration:bounce:) | duration=0.5 bounce=0.45 | MissionControlManager, NotchController, CalendarManager | near NotchLiveActivitiesView.body |
| 0x1001efc3c | sym.func.1001ef310 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, CalendarManager | near NotchLiveActivitiesView.body |
| 0x1001efd5c | sym.func.1001ef310 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MissionControlManager, NotchController, CalendarManager | near NotchLiveActivitiesView.body |
| 0x1001efdd4 | sym.func.1001ef310 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MissionControlManager, NotchController, CalendarManager | near NotchLiveActivitiesView.body |
| 0x1001f0df4 | sym.func.1001f05d4 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | CalendarManager, _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView, MissionControlManager | near NotchLiveActivitiesView.body |
| 0x1001f1098 | sym.func.1001f05d4 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.3 damping=1 blend=0 | CalendarManager, _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView, MissionControlManager | near NotchLiveActivitiesView.body |
| 0x1001f17a8 | sym.func.1001f1510 | Spring(duration:bounce:) | duration=0.6 bounce=0.4 | MediaManager | near NotchLiveActivitiesView.body |
| 0x1001f17b4 | sym.func.1001f1510 | Animation.spring(_:blendDuration:) | blend=0 | MediaManager | near NotchLiveActivitiesView.body |
| 0x1001f26b8 | sym.func.1001f1944 | Spring(duration:bounce:) | duration=? bounce=0.4 | MediaManager | near NotchLiveActivitiesView.body |
| 0x1001f26c4 | sym.func.1001f1944 | Animation.spring(_:blendDuration:) | blend=0 | MediaManager | near NotchLiveActivitiesView.body |
| 0x1001f314c | sym.func.1001f2ed8 | Spring(duration:bounce:) | duration=0.5 bounce=0.375 | FocusManager, MissionControlManager, NotchController | near NotchLiveActivitiesView.body |
| 0x1001f3158 | sym.func.1001f2ed8 | Animation.spring(_:blendDuration:) | blend=0 | FocusManager, MissionControlManager, NotchController | near NotchLiveActivitiesView.body |
| 0x1001f3244 | sym.func.1001f2ed8 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.3 damping=1 blend=0 | FocusManager, MissionControlManager, NotchController | near NotchLiveActivitiesView.body |
| 0x1001f3468 | sym.func.1001f2ed8 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | FocusManager, MissionControlManager, NotchController | near NotchLiveActivitiesView.body |
| 0x1001f3550 | sym.func.1001f2ed8 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | FocusManager, MissionControlManager, NotchController | near NotchLiveActivitiesView.body |
| 0x1001f8418 | sym.func.1001f8074 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | near NotchLiveActivitiesView.body |
| 0x1001f93a8 | sym.func.1001f8e24 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | MissionControlManager, CalendarManager, NotchController | near NotchLiveActivitiesView.body |
| 0x1001f9630 | sym.func.1001f94d4 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | MissionControlManager, NotchController | near NotchLiveActivitiesView.body |
| 0x1001fa8f4 | sym.func.1001fa7d4 | Spring(duration:bounce:) | duration=0.4 bounce=0.3 | MissionControlManager | near NotchLiveActivitiesView.body |
| 0x1001fa900 | sym.func.1001fa7d4 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager | near NotchLiveActivitiesView.body |
| 0x1001fabec | sym.func.1001fabbc | Duration.seconds(_:) | seconds=1e-10 | near NotchLiveActivitiesView.body |
| 0x1001faff0 | sym.func.1001faed0 | Spring(duration:bounce:) | duration=0.4 bounce=0.3 | MissionControlManager | near NotchLiveActivitiesView.body |
| 0x1001faffc | sym.func.1001faed0 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager | near NotchLiveActivitiesView.body |
| 0x1001fb3ac | sym.func.1001fb37c | Duration.seconds(_:) | seconds=1e-10 | near NotchLiveActivitiesView.body |
| 0x1001fe730 | sym.func.1001fe654 | Animation.easeOut(duration:) | d0=0.1 | MissionControlManager | near NotchLiveActivitiesView.body |
| 0x100208888 | sym.func.100208868 | Duration.seconds(_:) | seconds=0.5 | near ListButton.body |
| 0x10020a5f0 | sym.func.10020a3e4 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MissionControlManager | near ListButton.body |
| 0x10020a6f0 | sym.func.10020a3e4 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MissionControlManager | near ListButton.body |
| 0x10020af00 | sym.func.10020ac4c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | MissionControlManager | near ListButton.body |
| 0x1002130e0 | sym.func.1002129b0 | Animation.easeOut(duration:) | d0=0.1 d1=? | MissionControlManager, _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView, CalendarManager | near ProgressSlider.body |
| 0x10021a34c | sym.func.10021a2a8 | NSAnimationContext_GOT | d0=? d1=? | near anon.SettingsSectionBadge.body |
| 0x10021a4a8 | sym.func.10021a478 | kCAMediaTimingFunction* | d0=? | near anon.SettingsSectionBadge.body |
| 0x10021a4b4 | sym.func.10021a478 | CAMediaTimingFunction_GOT | d0=? | near anon.SettingsSectionBadge.body |
| 0x10021a9bc | sym.func.10021a830 | Spring(duration:bounce:) | duration=0.35 bounce=0.3 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10021a9c8 | sym.func.10021a830 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10021a9f8 | sym.func.10021a830 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.15 damping=1 blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10021aa18 | sym.func.10021a830 | Spring(duration:bounce:) | duration=0.3 bounce=? | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10021aa24 | sym.func.10021a830 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10021bd40 | sym.func.10021ba1c | Spring(duration:bounce:) | duration=0.35 bounce=? | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10021bd4c | sym.func.10021ba1c | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10021cc64 | sym.func.10021c974 | Spring(duration:bounce:) | duration=0.45 bounce=? | MissionControlManager, NotchController, LockManager | near anon.SettingsSectionBadge.body |
| 0x10021cc70 | sym.func.10021c974 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, LockManager | near anon.SettingsSectionBadge.body |
| 0x10021cca0 | sym.func.10021c974 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MissionControlManager, NotchController, LockManager | near anon.SettingsSectionBadge.body |
| 0x10021d9f4 | sym.func.10021c974 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MissionControlManager, NotchController, LockManager | near anon.SettingsSectionBadge.body |
| 0x10021db94 | sym.func.10021c974 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | MissionControlManager, NotchController, LockManager | near anon.SettingsSectionBadge.body |
| 0x10021dc34 | sym.func.10021c974 | Spring(duration:bounce:) | duration=? bounce=0.3 | MissionControlManager, NotchController, LockManager | near anon.SettingsSectionBadge.body |
| 0x10021dc40 | sym.func.10021c974 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, LockManager | near anon.SettingsSectionBadge.body |
| 0x10021dc68 | sym.func.10021c974 | Spring(duration:bounce:) | duration=? bounce=0 | MissionControlManager, NotchController, LockManager | near anon.SettingsSectionBadge.body |
| 0x10021dc74 | sym.func.10021c974 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, LockManager | near anon.SettingsSectionBadge.body |
| 0x10021e800 | sym.func.10021e724 | Spring(duration:bounce:) | duration=? bounce=0.3 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10021e80c | sym.func.10021e724 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10021e84c | sym.func.10021e724 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10021e86c | sym.func.10021e724 | Spring(duration:bounce:) | duration=0.3 bounce=? | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10021e878 | sym.func.10021e724 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10021f468 | sym.func.10021f344 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10021f490 | sym.func.10021f344 | Spring(duration:bounce:) | duration=? bounce=-0.2 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10021f49c | sym.func.10021f344 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10021fa20 | sym.func.10021f344 | Spring(duration:bounce:) | duration=? bounce=0.3 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10021fa2c | sym.func.10021f344 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10021fa6c | sym.func.10021f344 | Spring(duration:bounce:) | duration=? bounce=-0.2 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10021fa78 | sym.func.10021f344 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10021ffd0 | sym.func.10021f344 | Spring(duration:bounce:) | duration=? bounce=0.3 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10021ffdc | sym.func.10021f344 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10022001c | sym.func.10021f344 | Spring(duration:bounce:) | duration=? bounce=-0.2 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100220028 | sym.func.10021f344 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100223964 | sym.func.100223660 | Spring(duration:bounce:) | duration=0.35 bounce=? | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100223970 | sym.func.100223660 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x1002249e0 | sym.func.1002244f4 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.3 damping=1 blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100224c18 | sym.func.100224a94 | Spring(duration:bounce:) | duration=0.45 bounce=0.4 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100224c24 | sym.func.100224a94 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100224e44 | sym.func.100224c88 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4875 damping=1 blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100224e78 | sym.func.100224c88 | Spring(duration:bounce:) | duration=0.35 bounce=-0.2 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100224e84 | sym.func.100224c88 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100225144 | sym.func.100224c88 | Spring(duration:bounce:) | duration=? bounce=0.3 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100225150 | sym.func.100224c88 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100225190 | sym.func.100224c88 | Spring(duration:bounce:) | duration=? bounce=-0.2 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10022519c | sym.func.100224c88 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100225a68 | sym.func.100225730 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MissionControlManager, NotchController, ConnectivityManager | near anon.SettingsSectionBadge.body |
| 0x100225a90 | sym.func.100225730 | Spring(duration:bounce:) | duration=? bounce=-0.2 | MissionControlManager, NotchController, ConnectivityManager | near anon.SettingsSectionBadge.body |
| 0x100225a9c | sym.func.100225730 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, ConnectivityManager | near anon.SettingsSectionBadge.body |
| 0x10022665c | sym.func.100225730 | Spring(duration:bounce:) | duration=? bounce=0.3 | MissionControlManager, NotchController, ConnectivityManager | near anon.SettingsSectionBadge.body |
| 0x100226668 | sym.func.100225730 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, ConnectivityManager | near anon.SettingsSectionBadge.body |
| 0x1002266a8 | sym.func.100225730 | Spring(duration:bounce:) | duration=? bounce=-0.2 | MissionControlManager, NotchController, ConnectivityManager | near anon.SettingsSectionBadge.body |
| 0x1002266b4 | sym.func.100225730 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, ConnectivityManager | near anon.SettingsSectionBadge.body |
| 0x1002269bc | sym.func.100225730 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MissionControlManager, NotchController, ConnectivityManager | near anon.SettingsSectionBadge.body |
| 0x1002269e8 | sym.func.100225730 | Spring(duration:bounce:) | duration=? bounce=-0.2 | MissionControlManager, NotchController, ConnectivityManager | near anon.SettingsSectionBadge.body |
| 0x1002269f4 | sym.func.100225730 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, ConnectivityManager | near anon.SettingsSectionBadge.body |
| 0x100227100 | sym.func.100225730 | Spring(duration:bounce:) | duration=? bounce=0.3 | MissionControlManager, NotchController, ConnectivityManager | near anon.SettingsSectionBadge.body |
| 0x10022710c | sym.func.100225730 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, ConnectivityManager | near anon.SettingsSectionBadge.body |
| 0x10022714c | sym.func.100225730 | Spring(duration:bounce:) | duration=? bounce=-0.2 | MissionControlManager, NotchController, ConnectivityManager | near anon.SettingsSectionBadge.body |
| 0x100227158 | sym.func.100225730 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, ConnectivityManager | near anon.SettingsSectionBadge.body |
| 0x1002287c4 | sym.func.1002287a4 | Duration.seconds(_:) | seconds=? | near anon.SettingsSectionBadge.body |
| 0x100229ea4 | sym.func.100229e84 | Duration.seconds(_:) | seconds=? | near anon.SettingsSectionBadge.body |
| 0x10022a968 | sym.func.10022a848 | Spring(duration:bounce:) | duration=0.6 bounce=0.35 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10022a974 | sym.func.10022a848 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10022ab3c | sym.func.10022a9d4 | Spring(duration:bounce:) | duration=0.6 bounce=0.35 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10022ab48 | sym.func.10022a9d4 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10022c07c | sym.func.10022bf60 | Spring(duration:bounce:) | duration=0.6 bounce=0.35 | near anon.SettingsSectionBadge.body |
| 0x10022c088 | sym.func.10022bf60 | Animation.spring(_:blendDuration:) | blend=0 | near anon.SettingsSectionBadge.body |
| 0x10022cf90 | sym.func.10022cf70 | Duration.seconds(_:) | seconds=? | near anon.SettingsSectionBadge.body |
| 0x10022d184 | sym.func.10022d078 | Spring(duration:bounce:) | duration=? bounce=0.3 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10022d190 | sym.func.10022d078 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10022d1b4 | sym.func.10022d078 | Spring(duration:bounce:) | duration=? bounce=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10022d1c0 | sym.func.10022d078 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10022d460 | sym.func.10022d348 | Spring(duration:bounce:) | duration=? bounce=0.3 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10022d46c | sym.func.10022d348 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10022d490 | sym.func.10022d348 | Spring(duration:bounce:) | duration=? bounce=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10022d49c | sym.func.10022d348 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10022d87c | sym.func.10022d84c | Duration.seconds(_:) | seconds=0.02 | near anon.SettingsSectionBadge.body |
| 0x10022dbf8 | sym.func.10022dbd8 | Duration.seconds(_:) | seconds=? | near anon.SettingsSectionBadge.body |
| 0x10022e004 | sym.func.10022df8c | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10022e13c | sym.func.10022e118 | Duration.seconds(_:) | seconds=? | near anon.SettingsSectionBadge.body |
| 0x10022eadc | sym.func.10022eabc | Duration.seconds(_:) | seconds=? | near anon.SettingsSectionBadge.body |
| 0x10022fbf0 | sym.func.10022f8b0 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4875 damping=1 blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10022fc1c | sym.func.10022f8b0 | Spring(duration:bounce:) | duration=0.35 bounce=-0.2 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10022fc28 | sym.func.10022f8b0 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10022fec0 | sym.func.10022f8b0 | Spring(duration:bounce:) | duration=? bounce=0.3 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10022fecc | sym.func.10022f8b0 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10022ff00 | sym.func.10022f8b0 | Spring(duration:bounce:) | duration=? bounce=-0.2 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10022ff0c | sym.func.10022f8b0 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100230088 | sym.func.10022f8b0 | Spring(duration:bounce:) | duration=? bounce=0.3 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100230094 | sym.func.10022f8b0 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x1002300b8 | sym.func.10022f8b0 | Spring(duration:bounce:) | duration=? bounce=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x1002300c4 | sym.func.10022f8b0 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x1002309b8 | sym.func.100230980 | Duration.seconds(_:) | seconds=? | near anon.SettingsSectionBadge.body |
| 0x100230ce0 | sym.func.100230aa0 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4875 damping=1 blend=0 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x100230d08 | sym.func.100230aa0 | Spring(duration:bounce:) | duration=0.35 bounce=-0.2 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x100230d14 | sym.func.100230aa0 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x100230f90 | sym.func.100230aa0 | Spring(duration:bounce:) | duration=? bounce=0.3 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x100230f9c | sym.func.100230aa0 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x100230fc8 | sym.func.100230aa0 | Spring(duration:bounce:) | duration=? bounce=-0.2 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x100230fd4 | sym.func.100230aa0 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x100231208 | sym.func.100230aa0 | Spring(duration:bounce:) | duration=? bounce=0.3 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x100231214 | sym.func.100230aa0 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x100231238 | sym.func.100230aa0 | Spring(duration:bounce:) | duration=? bounce=0 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x100231244 | sym.func.100230aa0 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x100231688 | sym.func.100231430 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4875 damping=1 blend=0 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x1002316b0 | sym.func.100231430 | Spring(duration:bounce:) | duration=0.35 bounce=-0.2 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x1002316bc | sym.func.100231430 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x100231938 | sym.func.100231430 | Spring(duration:bounce:) | duration=? bounce=0.3 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x100231944 | sym.func.100231430 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x100231970 | sym.func.100231430 | Spring(duration:bounce:) | duration=? bounce=-0.2 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x10023197c | sym.func.100231430 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x100231bb0 | sym.func.100231430 | Spring(duration:bounce:) | duration=? bounce=0.3 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x100231bbc | sym.func.100231430 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x100231be0 | sym.func.100231430 | Spring(duration:bounce:) | duration=? bounce=0 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x100231bec | sym.func.100231430 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, MediaManager | near anon.SettingsSectionBadge.body |
| 0x100232100 | sym.func.100231dd8 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100232308 | sym.func.1002322e8 | Duration.seconds(_:) | seconds=? | near anon.SettingsSectionBadge.body |
| 0x100232478 | sym.func.1002323f0 | Spring(duration:bounce:) | duration=0.45 bounce=0.4 | near anon.SettingsSectionBadge.body |
| 0x100232484 | sym.func.1002323f0 | Animation.spring(_:blendDuration:) | blend=0 | near anon.SettingsSectionBadge.body |
| 0x100232594 | sym.func.100232500 | Spring(duration:bounce:) | duration=0.45 bounce=0.4 | near anon.SettingsSectionBadge.body |
| 0x1002325a0 | sym.func.100232500 | Animation.spring(_:blendDuration:) | blend=0 | near anon.SettingsSectionBadge.body |
| 0x100235640 | sym.func.100235270 | Spring(duration:bounce:) | duration=? bounce=? | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10023564c | sym.func.100235270 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100235670 | sym.func.100235270 | Spring(duration:bounce:) | duration=? bounce=? | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10023567c | sym.func.100235270 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100235a04 | sym.func.100235988 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.3 damping=1 blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100235af0 | sym.func.100235988 | Spring(duration:bounce:) | duration=0.3 bounce=0.35 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100235afc | sym.func.100235988 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100235d08 | sym.func.100235cdc | Duration.seconds(_:) | seconds=0.05 | near anon.SettingsSectionBadge.body |
| 0x10023624c | sym.func.100236148 | Task.sleep(for:) via Clock.sleep(until:tolerance:) | d0=? | near anon.SettingsSectionBadge.body |
| 0x10023c22c | sym.func.10023b888 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10023c24c | sym.func.10023b888 | Spring(duration:bounce:) | duration=? bounce=? | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10023c258 | sym.func.10023b888 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10023e2b4 | sym.func.10023de08 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MissionControlManager, NotchController, LockManager | near anon.SettingsSectionBadge.body |
| 0x10023e2d4 | sym.func.10023de08 | Spring(duration:bounce:) | duration=? bounce=? | MissionControlManager, NotchController, LockManager | near anon.SettingsSectionBadge.body |
| 0x10023e2e0 | sym.func.10023de08 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, LockManager | near anon.SettingsSectionBadge.body |
| 0x10023e594 | sym.func.10023de08 | Spring(duration:bounce:) | duration=? bounce=? | MissionControlManager, NotchController, LockManager | near anon.SettingsSectionBadge.body |
| 0x10023e5a0 | sym.func.10023de08 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, LockManager | near anon.SettingsSectionBadge.body |
| 0x10023e5c0 | sym.func.10023de08 | Spring(duration:bounce:) | duration=? bounce=? | MissionControlManager, NotchController, LockManager | near anon.SettingsSectionBadge.body |
| 0x10023e5cc | sym.func.10023de08 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController, LockManager | near anon.SettingsSectionBadge.body |
| 0x100242030 | sym.func.1002416f0 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100242050 | sym.func.1002416f0 | Spring(duration:bounce:) | duration=? bounce=? | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10024205c | sym.func.1002416f0 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100242314 | sym.func.1002416f0 | Spring(duration:bounce:) | duration=? bounce=? | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100242320 | sym.func.1002416f0 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100242354 | sym.func.1002416f0 | Spring(duration:bounce:) | duration=? bounce=? | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100242360 | sym.func.1002416f0 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100243010 | sym.func.100242abc | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10024302c | sym.func.100242abc | Spring(duration:bounce:) | duration=? bounce=? | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100243038 | sym.func.100242abc | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x1002440e4 | sym.func.100243a7c | Spring(duration:bounce:) | duration=? bounce=? | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x1002440f0 | sym.func.100243a7c | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100244134 | sym.func.100243a7c | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100244148 | sym.func.100243a7c | Spring(duration:bounce:) | duration=? bounce=? | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x100244154 | sym.func.100243a7c | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager, NotchController | near anon.SettingsSectionBadge.body |
| 0x10024b1dc | sym.func.10024b134 | NSAnimationContext_GOT | d0=? | LoginWindowContainerView | near anon.SettingsSectionBadge.body |
| 0x10024b810 | sym.func.10024b7dc | kCAMediaTimingFunction* | d0=? | near anon.SettingsSectionBadge.body |
| 0x10024b81c | sym.func.10024b7dc | CAMediaTimingFunction_GOT | d0=? | near anon.SettingsSectionBadge.body |
| 0x1002515bc | sym.func.100251294 | Spring(duration:bounce:) | duration=0.35 bounce=0.3 | near anon.SettingsSectionBadge.body |
| 0x1002515c8 | sym.func.100251294 | Animation.spring(_:blendDuration:) | blend=0 | near anon.SettingsSectionBadge.body |
| 0x100251770 | sym.func.10025170c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | near anon.SettingsSectionBadge.body |
| 0x10025202c | sym.func.100251e14 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | near anon.SettingsSectionBadge.body |
| 0x100252588 | sym.func.100252454 | Spring(duration:bounce:) | duration=0.35 bounce=0.3 | near anon.SettingsSectionBadge.body |
| 0x100252594 | sym.func.100252454 | Animation.spring(_:blendDuration:) | blend=0 | near anon.SettingsSectionBadge.body |
| 0x10025cc70 | sym.func.10025cc3c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | MediaManager | near AnimatableProgress.body |
| 0x10025cda8 | sym.func.10025cd74 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | near AnimatableProgress.body |
| 0x100264834 | sym.func.1002644d4 | Spring(duration:bounce:) | duration=0.6 bounce=0.4 | MissionControlManager | near AnimatableProgress.body |
| 0x100264840 | sym.func.1002644d4 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager | near AnimatableProgress.body |
| 0x1002649b4 | sym.func.100264994 | Duration.seconds(_:) | seconds=4.75 | near AnimatableProgress.body |
| 0x100264af8 | sym.func.100264a9c | Spring(duration:bounce:) | duration=0.6 bounce=0.4 | near AnimatableProgress.body |
| 0x100264b04 | sym.func.100264a9c | Animation.spring(_:blendDuration:) | blend=0 | near AnimatableProgress.body |
| 0x100264be4 | sym.func.100264b7c | Spring(duration:bounce:) | duration=0.6 bounce=0.4 | near AnimatableProgress.body |
| 0x100264bf0 | sym.func.100264b7c | Animation.spring(_:blendDuration:) | blend=0 | near AnimatableProgress.body |
| 0x100279ba0 | sym.func.100279b44 | NSAnimationContext_GOT | d0=? | near NotchShape.body |
| 0x100291a6c | sym.func.100291918 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | UpdateManager, MissionControlManager | near Section.body |
| 0x100291ab8 | sym.func.100291918 | Spring(duration:bounce:) | duration=0.35 bounce=0.3 | UpdateManager, MissionControlManager | near Section.body |
| 0x100291ac4 | sym.func.100291918 | Animation.spring(_:blendDuration:) | blend=0 | UpdateManager, MissionControlManager | near Section.body |
| 0x100291c0c | sym.func.100291918 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | UpdateManager, MissionControlManager | near Section.body |
| 0x100291e88 | sym.func.100291d20 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | UpdateManager, MissionControlManager | near Section.body |
| 0x100291ed8 | sym.func.100291d20 | Spring(duration:bounce:) | duration=0.35 bounce=0.3 | UpdateManager, MissionControlManager | near Section.body |
| 0x100291ee4 | sym.func.100291d20 | Animation.spring(_:blendDuration:) | blend=0 | UpdateManager, MissionControlManager | near Section.body |
| 0x10029202c | sym.func.100291d20 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | UpdateManager, MissionControlManager | near Section.body |
| 0x100292b68 | sym.func.1002929cc | Animation.spring(response:dampingFraction:blendDuration:) | response=0.8 damping=1 blend=0 | UpdateManager | near Section.body |
| 0x1002932e4 | sym.func.1002932b4 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | near UpdateView.body |
| 0x1002a1438 | sym.func.1002a116c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.3 damping=1 blend=0 | MissionControlManager, NotchController | near MusicView.body |
| 0x1002a2000 | sym.func.1002a1e04 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.3 damping=1 blend=0 | BrightnessManager | near MusicView.body |
| 0x1002a2048 | sym.func.1002a1e04 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | BrightnessManager | near MusicView.body |
| 0x1002a20cc | sym.func.1002a1e04 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | BrightnessManager | near MusicView.body |
| 0x1002a22cc | sym.func.1002a2178 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near MusicView.body |
| 0x1002a2334 | sym.func.1002a2178 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near MusicView.body |
| 0x1002a2ef0 | sym.func.1002a2b7c | Animation.easeInOut(duration:) | d0=0.2 | MissionControlManager, NotchController, BatteryManager | near MusicView.body |
| 0x1002a376c | sym.func.1002a35b0 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near MusicView.body |
| 0x1002a37b4 | sym.func.1002a35b0 | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near MusicView.body |
| 0x1002a39c8 | sym.func.1002a385c | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near MusicView.body |
| 0x1002a3a30 | sym.func.1002a385c | Animation.spring(response:dampingFraction:blendDuration:) | response=? damping=1 blend=0 | near MusicView.body |
| 0x1002a3c00 | sym.func.1002a3ad4 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.3 damping=1 blend=0 | ConnectivityManager | near MusicView.body |
| 0x1002a4e00 | sym.func.1002a44f8 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.3 damping=1 blend=0 | FocusManager, MissionControlManager, NotchController | near NotchNotificationsView.body |
| 0x1002a91ec | sym.func.1002a8fbc | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | BrightnessManager | near NotchNotificationsView.body |
| 0x1002a9528 | sym.func.1002a8fbc | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | BrightnessManager | near NotchNotificationsView.body |
| 0x1002a9a88 | sym.func.1002a9884 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.25 damping=1 blend=0 | VolumeManager | near NotchNotificationsView.body |
| 0x1002a9dc4 | sym.func.1002a9884 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | VolumeManager | near NotchNotificationsView.body |
| 0x1002aa890 | sym.func.1002aa4d4 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | CalendarManager, _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView, MissionControlManager | near NotchNotificationsView.body |
| 0x1002aeae0 | sym.func.1002ae780 | Spring(duration:bounce:) | duration=0.6 bounce=0.4 | MissionControlManager | near NotchNotificationsView.body |
| 0x1002aeaec | sym.func.1002ae780 | Animation.spring(_:blendDuration:) | blend=0 | MissionControlManager | near NotchNotificationsView.body |
| 0x1002aec60 | sym.func.1002aec40 | Duration.seconds(_:) | seconds=4.75 | near NotchNotificationsView.body |
| 0x1002aeda4 | sym.func.1002aed48 | Spring(duration:bounce:) | duration=0.6 bounce=0.4 | near NotchNotificationsView.body |
| 0x1002aedb0 | sym.func.1002aed48 | Animation.spring(_:blendDuration:) | blend=0 | near NotchNotificationsView.body |
| 0x1002aee90 | sym.func.1002aee28 | Spring(duration:bounce:) | duration=0.6 bounce=0.4 | near NotchNotificationsView.body |
| 0x1002aee9c | sym.func.1002aee28 | Animation.spring(_:blendDuration:) | blend=0 | near NotchNotificationsView.body |
| 0x1002b0d44 | sym.func.1002b0630 | Spring(duration:bounce:) | duration=1.5 bounce=? | near NotchNotificationsView.body |
| 0x1002b0d50 | sym.func.1002b0630 | Animation.spring(_:blendDuration:) | blend=0 | near NotchNotificationsView.body |
| 0x1002b11a0 | sym.func.1002b0630 | Spring(duration:bounce:) | duration=1.5 bounce=? | near NotchNotificationsView.body |
| 0x1002b11ac | sym.func.1002b0630 | Animation.spring(_:blendDuration:) | blend=0 | near NotchNotificationsView.body |
| 0x1002b21a4 | sym.func.1002b1b54 | Spring(duration:bounce:) | duration=1.5 bounce=? | near NotchNotificationsView.body |
| 0x1002b21b0 | sym.func.1002b1b54 | Animation.spring(_:blendDuration:) | blend=0 | near NotchNotificationsView.body |
| 0x1002b27d4 | sym.func.1002b1b54 | Spring(duration:bounce:) | duration=1.5 bounce=? | near NotchNotificationsView.body |
| 0x1002b27e0 | sym.func.1002b1b54 | Animation.spring(_:blendDuration:) | blend=0 | near NotchNotificationsView.body |
| 0x1002b396c | sym.func.1002b3184 | Animation.easeOut(duration:) | d0=0.6 | near NotchNotificationsView.body |
| 0x1002b3980 | sym.func.1002b3184 | Animation.delay(_:) | d0=0.3 | near NotchNotificationsView.body |
| 0x1002b3d94 | sym.func.1002b3184 | Spring(duration:bounce:) | duration=1 bounce=0.4 | near NotchNotificationsView.body |
| 0x1002b3da0 | sym.func.1002b3184 | Animation.spring(_:blendDuration:) | blend=0 | near NotchNotificationsView.body |
| 0x1002b4efc | sym.func.1002b4ed0 | Animation.spring(response:dampingFraction:blendDuration:) | response=4 damping=1 blend=0 | near NotchNotificationsView.body |
| 0x1002b5060 | sym.func.1002b5034 | Animation.spring(response:dampingFraction:blendDuration:) | response=2 damping=1 blend=0 | near NotchNotificationsView.body |
| 0x1002b51c4 | sym.func.1002b5198 | Animation.spring(response:dampingFraction:blendDuration:) | response=2 damping=1 blend=0 | near NotchNotificationsView.body |
| 0x1002b5328 | sym.func.1002b52fc | Animation.spring(response:dampingFraction:blendDuration:) | response=1.5 damping=1 blend=0 | near NotchNotificationsView.body |
| 0x1002b5494 | sym.func.1002b5460 | Animation.spring(response:dampingFraction:blendDuration:) | response=1.5 damping=1 blend=0 | near NotchNotificationsView.body |
| 0x1002b7a80 | sym.func.1002b7910 | Animation.easeOut(duration:) | d0=0.1 | near IntroView.body |
| 0x1002b8004 | sym.func.1002b7ce4 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.5 damping=1 blend=0 | near IntroView.body |
| 0x1002b8720 | sym.func.1002b8588 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | near IntroView.body |
| 0x1002bdb34 | sym.func.1002bdadc | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | near SegmentedPickerWallpaperBackground.body |
| 0x1002bf95c | sym.func.1002bf8b8 | Animation.easeOut(duration:) | d0=0.1 | near SegmentedPickerWallpaperBackground.body |
| 0x1002c78f0 | sym.func.1002c7890 | Spring(duration:bounce:) | duration=0.275 bounce=0.375 | near ArtworkCutoutBackdrop.body |
| 0x1002c78fc | sym.func.1002c7890 | Animation.spring(_:blendDuration:) | blend=0 | near ArtworkCutoutBackdrop.body |
| 0x1002c794c | sym.func.1002c7930 | Animation.easeOut(duration:) | d0=0.55 | near ArtworkCutoutBackdrop.body |
| 0x1002c7964 | sym.func.1002c7930 | Animation.delay(_:) | d0=0.05 | near ArtworkCutoutBackdrop.body |
| 0x1002c799c | sym.func.1002c7988 | Animation.easeIn(duration:) | d0=0.15 | near ArtworkCutoutBackdrop.body |
| 0x1002e0afc | sym.func.1002e0adc | Duration.seconds(_:) | seconds=? | near anon.VibrancyEffectRepresentable.body |
| 0x1002e4590 | sym.func.1002e4570 | Duration.seconds(_:) | seconds=? | near anon.VibrancyEffectRepresentable.body |
| 0x100316960 | sym.func.100316940 | Duration.seconds(_:) | seconds=0.5 | near anon.VibrancyEffectRepresentable.body |
| 0x10031de00 | sym.func.10031db8c | CABasicAnimation_classref_GOT | d0=? d1=? | NSMarqueeTextView | near MarqueeText.body |
| 0x10031df2c | sym.func.10031db8c | CAAnimationGroup_GOT | d0=? d1=? | NSMarqueeTextView | near MarqueeText.body |
| 0x10031f48c | sym.func.10031f3d8 | CABasicAnimation_classref_GOT | d0=? | NSMarqueeTextView | near MarqueeText.body |
| 0x10031f49c | sym.func.10031f3d8 | CAMediaTimingFunction_GOT | d0=? | NSMarqueeTextView | near MarqueeText.body |
| 0x10031f4c8 | sym.func.10031f3d8 | kCAMediaTimingFunction* | d0=? | NSMarqueeTextView | near MarqueeText.body |
| 0x10031f5d8 | sym.func.10031f3d8 | CAAnimationGroup_GOT | d0=? | NSMarqueeTextView | near MarqueeText.body |
| 0x100352354 | sym.func.100351c84 | Spring(duration:bounce:) | duration=0.35 bounce=0.3 | LockManager, MissionControlManager | near GeneralSettingsView.body |
| 0x100352360 | sym.func.100351c84 | Animation.spring(_:blendDuration:) | blend=0 | LockManager, MissionControlManager | near GeneralSettingsView.body |
| 0x100352988 | sym.func.100352960 | Duration.seconds(_:) | seconds=0.35 | near GeneralSettingsView.body |
| 0x100354438 | sym.func.100353c68 | Animation.easeOut(duration:) | d0=0.15 | LockManager, MissionControlManager, LicenseManager | near GeneralSettingsView.body |
| 0x100354728 | sym.func.1003546fc | Duration.seconds(_:) | seconds=0.2 | near GeneralSettingsView.body |
| 0x100355760 | sym.func.100355734 | Duration.seconds(_:) | seconds=0.2 | near GeneralSettingsView.body |
| 0x100357370 | sym.func.100357348 | Duration.seconds(_:) | seconds=0.475 | near GeneralSettingsView.body |
| 0x100358d3c | sym.func.100358d14 | Duration.seconds(_:) | seconds=0.15 | near GeneralSettingsView.body |
| 0x10035a6b8 | sym.func.10035a698 | Duration.seconds(_:) | seconds=2 | near GeneralSettingsView.body |
| 0x10035d23c | sym.func.10035d128 | Animation.easeOut(duration:) | d0=0.15 | LockManager, MissionControlManager | near GeneralSettingsView.body |
| 0x100365198 | sym.func.100364dc8 | Spring(duration:bounce:) | duration=0.3 bounce=? | MediaManager, MissionControlManager | near GeneralSettingsView.body |
| 0x1003651a4 | sym.func.100364dc8 | Animation.spring(_:blendDuration:) | blend=0 | MediaManager, MissionControlManager | near GeneralSettingsView.body |
| 0x100365cf4 | sym.func.100365b44 | Spring(duration:bounce:) | duration=0.3 bounce=? | MediaManager | near GeneralSettingsView.body |
| 0x100365d00 | sym.func.100365b44 | Animation.spring(_:blendDuration:) | blend=0 | MediaManager | near GeneralSettingsView.body |
| 0x100365dd4 | sym.func.100365b44 | Spring(duration:bounce:) | duration=0.3 bounce=? | MediaManager | near GeneralSettingsView.body |
| 0x100365de0 | sym.func.100365b44 | Animation.spring(_:blendDuration:) | blend=0 | MediaManager | near GeneralSettingsView.body |
| 0x1003662c4 | sym.func.100365f64 | Spring(duration:bounce:) | duration=0.3 bounce=? | MediaManager, MissionControlManager | near GeneralSettingsView.body |
| 0x1003662d0 | sym.func.100365f64 | Animation.spring(_:blendDuration:) | blend=0 | MediaManager, MissionControlManager | near GeneralSettingsView.body |
| 0x100366350 | sym.func.100365f64 | Spring(duration:bounce:) | duration=0.3 bounce=0.2 | MediaManager, MissionControlManager | near GeneralSettingsView.body |
| 0x10036635c | sym.func.100365f64 | Animation.spring(_:blendDuration:) | blend=0 | MediaManager, MissionControlManager | near GeneralSettingsView.body |
| 0x1003674f8 | sym.func.1003672fc | Spring(duration:bounce:) | duration=0.6 bounce=0.4 | MediaManager, MissionControlManager, NotchController | near GeneralSettingsView.body |
| 0x100367504 | sym.func.1003672fc | Animation.spring(_:blendDuration:) | blend=0 | MediaManager, MissionControlManager, NotchController | near GeneralSettingsView.body |
| 0x100368778 | sym.func.1003686d4 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | MediaManager | near GeneralSettingsView.body |
| 0x10036a184 | sym.func.100369640 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | MediaManager, MissionControlManager | near GeneralSettingsView.body |
| 0x10036a544 | sym.func.100369640 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | MediaManager, MissionControlManager | near GeneralSettingsView.body |
| 0x10036ac14 | sym.func.100369640 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | MediaManager, MissionControlManager | near GeneralSettingsView.body |
| 0x10036b248 | sym.func.100369640 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | MediaManager, MissionControlManager | near GeneralSettingsView.body |
| 0x10036b4d0 | sym.func.100369640 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | MediaManager, MissionControlManager | near GeneralSettingsView.body |
| 0x100377940 | sym.func.100377914 | Duration.seconds(_:) | seconds=0.1 | near GeneralSettingsView.body |
| 0x100377d84 | sym.func.100377d00 | Duration.seconds(_:) | seconds=? | near GeneralSettingsView.body |
| 0x10037831c | sym.func.1003782f0 | Duration.seconds(_:) | seconds=? | near GeneralSettingsView.body |
| 0x100379814 | sym.func.100379124 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | MediaManager, MissionControlManager | near GeneralSettingsView.body |
| 0x100379970 | sym.func.100379124 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | MediaManager, MissionControlManager | near GeneralSettingsView.body |
| 0x100383624 | sym.func.100382d74 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.4 damping=1 blend=0 | MediaManager, MissionControlManager | near GeneralSettingsView.body |
| 0x100383680 | sym.func.100382d74 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | MediaManager, MissionControlManager | near GeneralSettingsView.body |
| 0x100388fa0 | sym.func.100388f80 | Duration.seconds(_:) | seconds=1.5 | near GeneralSettingsView.body |
| 0x10038a128 | sym.func.10038a098 | Spring(duration:bounce:) | duration=0.3 bounce=? | MediaManager | near GeneralSettingsView.body |
| 0x10038a134 | sym.func.10038a098 | Animation.spring(_:blendDuration:) | blend=0 | MediaManager | near GeneralSettingsView.body |
| 0x10038a210 | sym.func.10038a1b0 | Spring(duration:bounce:) | duration=0.3 bounce=? | near GeneralSettingsView.body |
| 0x10038a21c | sym.func.10038a1b0 | Animation.spring(_:blendDuration:) | blend=0 | near GeneralSettingsView.body |
| 0x10038adec | sym.func.10038ad18 | Spring(duration:bounce:) | duration=0.3 bounce=? | MediaManager | near GeneralSettingsView.body |
| 0x10038adf8 | sym.func.10038ad18 | Animation.spring(_:blendDuration:) | blend=0 | MediaManager | near GeneralSettingsView.body |
| 0x10038af30 | sym.func.10038ae6c | Spring(duration:bounce:) | duration=0.3 bounce=0.2 | MediaManager | near GeneralSettingsView.body |
| 0x10038af3c | sym.func.10038ae6c | Animation.spring(_:blendDuration:) | blend=0 | MediaManager | near GeneralSettingsView.body |
| 0x1003a3858 | sym.func.1003a350c | kCAMediaTimingFunction* | d0=? | MediaManager, NSWaveformView | near Waveform.body |
| 0x1003a395c | sym.func.1003a350c | CABasicAnimation_classref_GOT | d0=? | MediaManager, NSWaveformView | near Waveform.body |
| 0x1003a3a00 | sym.func.1003a350c | CAMediaTimingFunction_GOT | d0=? | MediaManager, NSWaveformView | near Waveform.body |
| 0x1003a44b0 | sym.func.1003a4360 | kCAMediaTimingFunction* | d0=? | MediaManager, NSWaveformView | near Waveform.body |
| 0x1003a44e0 | sym.func.1003a4360 | CAMediaTimingFunction_GOT | d0=? | MediaManager, NSWaveformView | near Waveform.body |
| 0x1003a480c | sym.func.1003a4360 | CABasicAnimation_classref_GOT | d0=? | MediaManager, NSWaveformView | near Waveform.body |
| 0x1003a790c | sym.func.1003a7604 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | MediaManager | near Waveform.body |
| 0x1003ace14 | sym.func.1003ac898 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView, MediaManager | near SliderPicker.body |
| 0x1003ad1e8 | sym.func.1003ac898 | Animation.spring(response:dampingFraction:blendDuration:) | response=0.45 damping=1 blend=0 | _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView, MediaManager | near SliderPicker.body |
| 0x1003af210 | sym.func.1003aef3c | Animation.spring(response:dampingFraction:blendDuration:) | response=0.2 damping=1 blend=0 | _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView | near SliderPicker.body |
| 0x1003b14f0 | sym.func.1003b1098 | CABasicAnimation_classref_GOT | d0=? | _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView, MediaManager | near MediaProgressSlider.body |
| 0x1003b1564 | sym.func.1003b1098 | kCAMediaTimingFunction* | d0=? | _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView, MediaManager | near MediaProgressSlider.body |
| 0x1003b1570 | sym.func.1003b1098 | CAMediaTimingFunction_GOT | d0=? | _CCE779E1FB76C4FB8F13B4772C7887B3.MediaProgressLayerTrackView, MediaManager | near MediaProgressSlider.body |
| 0x10040abfc | sym.func.10040aba4 | AnimationTimelineSchedule(minimumInterval:paused:) | d0=? | near ModalWindowView.body |
| 0x10040acdc | sym.func.10040aba4 | AnimationTimelineSchedule(minimumInterval:paused:) | d0=? d1=1 | near ModalWindowView.body |
| 0x10040c2b0 | sym.func.10040c294 | AnimationTimelineSchedule(minimumInterval:paused:) | d0=? | near Vortex.VortexView.body |
| 0x100444374 | sym.func.100444364 | Animation.linear(duration:) | d0=1.5 d1=? | near Defaults.Defaults.Toggle.body |
| 0x100444380 | sym.func.100444364 | Animation.delay(_:) | d0=0.25 d1=? | near Defaults.Defaults.Toggle.body |
| 0x100444398 | sym.func.100444364 | Animation.repeatForever(autoreverses:) | d0=? | near Defaults.Defaults.Toggle.body |
| 0x100445328 | sym.func.1004452b4 | Animation.linear(duration:) | d0=? | near Defaults.Defaults.Toggle.body |
| 0x100445334 | sym.func.1004452b4 | Animation.delay(_:) | d0=? | near Defaults.Defaults.Toggle.body |
| 0x10044534c | sym.func.1004452b4 | Animation.repeatForever(autoreverses:) | d0=? | near Defaults.Defaults.Toggle.body |

### Appendix B — Defaults keys (STATIC)
| key | inferred type | default (STATIC, from Key init box) | key initializer fn |
|---|---|---|---|
| ?stp | Double|Int|enum(raw 0) | 0 / 0.0 / first case | sym.func.1003319d0 |
| None | ? | ? | sym.func.100021f2c |
| None | ? | ? | sym.func.1003593b4 |
| allowBatteryWhenFocused | Bool | true | sym.func.1003395ac |
| allowBatteryWhenLocked | Bool | true | sym.func.100343e98 |
| allowBatteryWidgetWhenLocked | Bool | true | sym.func.100344f60 |
| allowBrightnessWhenFocused | Bool | true | sym.func.100339b44 |
| allowBrightnessWhenLocked | Bool | true | sym.func.1003446fc |
| allowCalendarWidgetWhenLocked | Bool | false | sym.func.100346548 |
| allowConnectivityWhenFocused | Bool | true | sym.func.100339878 |
| allowConnectivityWhenLocked | Bool | true | sym.func.100344164 |
| allowConnectivityWidgetWhenLocked | Bool | true | sym.func.10034522c |
| allowFocusWhenLocked | Bool | true | sym.func.100344430 |
| allowFocusWidgetWhenLocked | Bool | true | sym.func.1003454f8 |
| allowNowPlayingWidgetWhenLocked | Bool | true | sym.func.1003457c4 |
| allowVolumeWhenFocused | Bool | true | sym.func.100339e10 |
| allowVolumeWhenLocked | Bool | true | sym.func.1003449c8 |
| allowWeatherWidgetWhenLocked | Bool | false | sym.func.100346ad8 |
| alwaysShowMonthView | Bool | false | sym.func.1003409f8 |
| automaticMusicApp | Bool | true | sym.func.10033e8d0 |
| automaticallyCheckForUpdates | Bool | true | sym.func.1003477bc |
| batteryDuration | Double | 5 | sym.func.100336060 |
| beforeEventStarts | Bool | false | sym.func.100342574 |
| brightnessDuration | Double | 1.5 | sym.func.10033a66c |
| brightnessProgressStyle | Bool | false | sym.func.10033a938 |
| brightnessSpeed | Bool | true | sym.func.10033ab8c |
| cachedWeather | ? | ? | sym.func.100347370 |
| calendarDisplayModes | enum/other | '?x21' | sym.func.100341fdc |
| calendarPeekDuration | Double | 4 | sym.func.100342b08 |
| connectivityDuration | Double | 5 | sym.func.100337988 |
| connectivityModel | Bool | false | sym.func.1003384b0 |
| contrastOutline | Bool | true | sym.func.1003333e8 |
| controlChoice | Bool | true | sym.func.10033e670 |
| defaultTransportType | Bool | false | sym.func.100341abc |
| disableActivityDuringEvents | Bool | false | sym.func.1003401a0 |
| disableAlbumArtFlip | Bool | false | sym.func.10033d61c |
| disableWaveform | Bool | false | sym.func.10033d0f0 |
| earlyBirdUpdates | Bool | false | sym.func.1003474f4 |
| enableBattery | Bool | true | sym.func.100335d8c |
| enableBrightness | Bool | false | sym.func.10033a0dc |
| enableCalendar | Bool | false | sym.func.10033f668 |
| enableCalendarQuickPeek | Bool | true | sym.func.1003422a8 |
| enableConnectivity | Bool | true | sym.func.1003373f4 |
| enableFocus | Bool | true | sym.func.100338704 |
| enableHaptics | Bool | true | sym.func.10033417c |
| enableLockScreen | Bool | true | sym.func.1003430a0 |
| enableNowPlaying | Bool | true | sym.func.10033c5bc |
| enableQuickPeek | Bool | true | sym.func.10033edf0 |
| enableVolume | Bool | false | sym.func.10033b37c |
| excludedCalendars | enum/other | '?x21' | sym.func.100341d10 |
| expandNotchOnHover | Bool | false | sym.func.100334450 |
| focusDuration | Double | 5 | sym.func.1003389d4 |
| forceEnableActivity | Bool | false | sym.func.100333eb4 |
| forceSimulatedNotch | Bool | false | sym.func.1003322ec |
| hasPromptedAccessibilityPermission | Bool | false | sym.func.10033a3a4 |
| hasPromptedAudioPermission | Bool | false | sym.func.10033ce28 |
| hasPromptedBluetoothPermission | Bool | false | sym.func.1003376c0 |
| hasPromptedCalendarPermission | Bool | false | sym.func.100346810 |
| hasPromptedLocationPermission | Bool | false | sym.func.100346ff8 |
| hideBatteryLabel | Bool | false | sym.func.100336b98 |
| hideBatteryPercentage | Bool | false | sym.func.100336e60 |
| hideBrightnessLabel | Bool | false | sym.func.10033b0b4 |
| hideFromScreenCapture | Bool | false | sym.func.100332024 |
| hideIdleDuration | Double | 10 | sym.func.100345cec |
| hideLabel | Bool | false | sym.func.1003392e4 |
| hideMenuBarIcon | Bool | false | sym.func.100331d54 |
| hideSongTitleExtras | Bool | false | sym.func.10033e3a8 |
| hideVolumeLabel | Bool | false | sym.func.10033c2ec |
| hideWhileGaming | Bool | false | sym.func.10033de78 |
| hideWhileInFullscreen | Bool | true | sym.func.10033dbac |
| hideWhileInMissionControl | Bool | true | sym.func.1003325b4 |
| hideWhileSourceIsActive | Bool | false | sym.func.10033d8e4 |
| hoverDuration | Double|Int|enum(raw 0) | 0 / 0.0 / first case | sym.func.100334718 |
| idleActivity | Bool | true | sym.func.100333c58 |
| idleDuration | Double | 3 | sym.func.10033c888 |
| isFirstLaunch | Bool | true | sym.func.1003315fc |
| keepAwake | Double|Int|enum(raw 0) | 0 / 0.0 / first case | sym.func.10034336c |
| launchAtLogin | Bool | false | sym.func.100331a84 |
| licenseName | String/Array/Optional | empty/nil | sym.func.1003318d0 |
| lockScreenWidgetOrder | enum/other | '?x21' | sym.func.100344c94 |
| lowBatteryThreshold | Double | 10 | sym.func.1003368cc |
| lowConnectBatteryThreshold | Double | 20 | sym.func.100337f1c |
| mostRecentActivity | Bool | false | sym.func.100333990 |
| musicApp | Bool | 2 | sym.func.10033eb9c |
| naturalMovement | Bool | false | sym.func.1003349e8 |
| notchAdjustedHeight | Double|Int|enum(raw 0) | 0 / 0.0 / first case | sym.func.100335ac4 |
| notchAdjustedWidth | Double|Int|enum(raw 0) | 0 / 0.0 / first case | sym.func.1003357fc |
| notifyOnLowPowerMode | Bool | true | sym.func.100336334 |
| notifyWhenTimeToLeave | Bool | false | sym.func.100340f90 |
| nowPlayingStyle | Bool | false | sym.func.100345a90 |
| nowPlayingWidgetOffset | Double|Int|enum(raw 0) | 0 / 0.0 / first case | sym.func.100346280 |
| peekDuration | Double | 2 | sym.func.10033f398 |
| pendingLocationPermissionTarget | Bool | 3 | sym.func.1003472c0 |
| playHourlyChime | Bool | false | sym.func.100340cc0 |
| playSoundOnCalendarEvent | Bool | true | sym.func.10033fc0c |
| playSoundOnLock | Bool | false | sym.func.1003438fc |
| playSoundOnLowBattery | Bool | true | sym.func.100337128 |
| playSoundOnLowConnectBattery | Bool | false | sym.func.1003381e8 |
| playSoundOnSleepFocus | Bool | false | sym.func.100338ca8 |
| playSoundOnTimeToLeave | Bool | true | sym.func.1003417f0 |
| playSoundOnUnlock | Bool | true | sym.func.100343bcc |
| progressStyle | Bool | false | sym.func.10033d3c0 |
| progressiveBlur | Bool | true | sym.func.1003336bc |
| replaceWaveformDuringFocus | Bool | false | sym.func.100338f70 |
| replaceWaveformDuringFocusModeIdentifier | String/Array/Optional | empty/nil | sym.func.100339238 |
| showBrightnessPercentage | Bool | false | sym.func.10033adec |
| showOnDisplay | Bool | true | sym.func.100332880 |
| showOnDisplayName | String/Array/Optional | empty/nil | sym.func.100332b8c |
| showOnDisplaySymbol | String/Array/Optional | 34165590552963428 | sym.func.100332e4c |
| showOnDisplayUUID | String/Array/Optional | empty/nil | sym.func.100332ae0 |
| showOnScreenSaver | Bool | false | sym.func.100343634 |
| showRemainingTime | Bool | true | sym.func.10033311c |
| showVolumeControl | Bool | false | sym.func.100345fb8 |
| showVolumePercentage | Bool | false | sym.func.10033c024 |
| showWeatherOnEmptyDay | Bool | false | sym.func.100340468 |
| songTitleBadge | Bool | true | sym.func.10033e148 |
| swipeToCycleActivity | Bool | true | sym.func.100334f8c |
| swipeToDismiss | Bool | true | sym.func.100335258 |
| swipeToSkip | Bool | true | sym.func.10033552c |
| swipeToToggle | Bool | true | sym.func.100334cb8 |
| timeBeforeEvent | Double | 15 | sym.func.10033f938 |
| timeToLeaveBuffer | Double | 10 | sym.func.100341258 |
| timeToLeaveDuration | Double | 8 | sym.func.100341524 |
| useCalendarColor | Bool | false | sym.func.10033fed8 |
| useColoredCalendarIndicator | Bool | true | sym.func.100342dd4 |
| useEventIndicators | Bool | false | sym.func.100340730 |
| useLiveWaveform | Bool | false | sym.func.10033cb58 |
| volumeDuration | Double | 1.5 | sym.func.10033b8a0 |
| volumeOutputDevice | Bool | true | sym.func.10033b648 |
| volumeProgressStyle | Bool | false | sym.func.10033bb74 |
| volumeSpeed | Bool | true | sym.func.10033bdc8 |
| warnOnLowBattery | Bool | true | sym.func.100336600 |
| warnOnLowConnectBattery | Bool | false | sym.func.100337c54 |
| weatherStyle | Bool | false | sym.func.100346da0 |
| whenEventIsStarting | Bool | true | sym.func.10034283c |
| whenSongChanges | Bool | true | sym.func.10033f0c4 |


---

# Part B: runtime inner workings

_Source: `children/B_runtime/alcove_runtime.md`. Evidence lives in `children/B_runtime/`._

## Alcove 1.7.7 (build 199) – runtime inner workings, observed from outside

Scope: observe the *running* app on a macOS VM (macOS 26.6.2 / 25G83, arm64, 1600×1200 @1×, no physical notch,
no battery, no AirPods, no Touch ID, single "Apple Virtual" display). The app was installed from
`https://download.tryalcove.com/Alcove.dmg`, onboarded, trial started, and **Force simulated notch** turned on.
Nothing license/trial related was bypassed, patched, replayed or reverse‑engineered; only the public endpoints
and the fact that a trial exists are described.

Labels used on every claim:
* **OBSERVED** – seen live on this VM (file/line/screenshot given).
* **STATIC** – read from the bundle on disk (Info.plist etc.).
* **INFERRED** – my interpretation of observations; verify before relying on it.
* **UNVERIFIED** – needs hardware this VM lacks (real notch, battery, AirPods, Touch ID, 2nd display).

Evidence root in the zip: `ev/` (`scripts/`, `windows/`, `shots/`, `defaults/`, `logs/`, `proc/`, `net/`, `tcc/`, `media/`).
`ev/lead_NOTES.md` is the lead session's static‑analysis notes (not mine, kept for cross‑reference).

---

### 0. TL;DR for the clone author

| Topic | Finding (label) |
|---|---|
| Window model | Exactly **two** always‑on‑screen windows, both **624×320 px, fixed**, top‑centred on the display (x=488 on a 1600‑wide screen), `alpha=1.0`, at CGWindowLevels **2147483628** and **2147483629** (= `kCGMaximumWindowLevel‑19/‑18`, i.e. above everything incl. menu bar). All visual states (idle notch, hover, expanded, HUD, Now Playing) are drawn *inside* these fixed panels; the windows never move or resize. **OBSERVED** (`windows/states.txt`). The two‑window split is **INFERRED** to be backdrop + content (names are empty at the CG level). |
| Visible geometry inside the panel | idle notch 144×29 at x=728..871; hover 156×33; Sound HUD 332×29 at x=634..965; expanded Calendar 369×175; expanded Now Playing 375×175; compact Now Playing 222×29 (details §1.3). **OBSERVED** |
| Hide from screen capture | Flips `kCGWindowSharingState` of both panels 1→0 (`NSWindow.sharingType = .none`); `screencapture` then shows the wallpaper where the notch was. Works live, no relaunch. **OBSERVED** |
| Persistence | Plain `UserDefaults` in `~/Library/Preferences/com.henrikruscon.Alcove.plist`; ~100 keys, camelCase, enums as lowercase strings; **keys are not written until the user changes them** (registered defaults). No iCloud KVS activity seen. **OBSERVED** (§2) |
| Helper | `AlcoveHelper.xpc` (bundle id `com.apple.controlcenter.AlcoveHelper`, `ServiceType=Application`) is spawned **within 1 s of launch**, lives for the whole session, 2–4 threads, ~3 MB. It is the process that talks to `MediaRemote` (NowPlaying notifications, `getNowPlayingInfoForBundleIdentifier:` XPC). **OBSERVED/STATIC** (§4) |
| Idle cost | Alcove 0.0–0.1 % CPU, ~71–73 MB RSS, 8–10 threads, ≈1.6 CPU‑ms/s, ≈6 wake‑ups/s, Energy Impact 0.16 – *same* idle vs. expanded‑with‑waveform in `powermetrics` samples. **OBSERVED** (§4.3) |
| Network | Only app host: `api.tryalcove.com` (Cloudflare, HTTP/3 alt‑svc). Also WeatherKit via Apple's `com.apple.weatherkit.authservice` + CoreLocation at launch. `/changelog` is public JSON (200); `/updates/latest` answers **401 "An active license is required for this channel."** on an un‑licensed GET. **OBSERVED** (§5) |
| TCC | Requests Calendar, BluetoothAlways, Accessibility (and prompts Location once). With Accessibility revoked **and relaunched**, media keys no longer produce Alcove's HUD (volume still changes via the system); re‑granting in System Settings restores the HUD **without relaunch** (it re‑checks trust at runtime). **OBSERVED** (§6) |
| Media keys | Synthetic `NX_SYSDEFINED` key events (`CGEvent.post(.cghidEventTap)`) → Alcove HUD. `osascript set volume` → volume changes, **no** Alcove HUD. Brightness keys → nothing visible on this VM. **OBSERVED**; OSD suppression on real hardware **UNVERIFIED** (the VM has no `OSDUIHelper` at all). (§7) |

---

### 1. Windows (`CGWindowListCopyWindowInfo`)

Scripts: `scripts/winlist.py` (one‑shot dump: wid, layer, bounds, alpha, sharing, on‑screen, name),
`scripts/winsample.py` (20 Hz sampler that prints whenever the window set changes),
`scripts/osd_check.py` (lists OSDUIHelper/BezelUIServer/Alcove windows), `scripts/measure_bbox.py`
(bounding box of near‑black pixels in a screenshot = visible notch/HUD body).

#### 1.1 Inventory – identical in every state (OBSERVED, `windows/states.txt`)

First process (pid 2607, launched through onboarding):

```
wid  layer       x    y  w     h    alpha sharing onscreen name
43   0           0    0  1600  30   1.0   1       F        ''
44   0           0    0  1600  30   1.0   1       F        ''
45   0           0    0  1600  30   1.0   1       F        ''
46   0           0    0  1600  30   1.0   1       F        ''
115  2147483628  488  0  624   320  1.0   1       T        ''
116  2147483629  488  0  624   320  1.0   1       T        ''
```

After relaunch (pids 8594 and 10160) only the two high‑level panels exist (wids 221/222, then 250/251, same geometry).
→ the four layer‑0, 1600×30, off‑screen windows are **INFERRED** leftovers of the first‑run/onboarding flow
(or menu‑bar extras created once), not part of the steady‑state notch UI.

States sampled with the sampler running (no change in count, bounds, alpha or sharing between them):
idle‑closed, hovered, expanded (Calendar), expanded (Now Playing), Sound HUD (vol‑up, mute), Now Playing compact,
QuickTime playing/paused, Settings window open (adds the normal `General`/`About` NSWindow at layer 0),
Safari fullscreen attempt, Mission Control attempt, hideFromScreenCapture on/off (sharing flips, see 1.4).

Key facts (OBSERVED):
* Window count in steady state: **2** (plus a normal titled Settings window when open; plus the onboarding windows in the first process).
* Bounds **never change**: `(488, 0, 624, 320)` on a 1600×1200 display → horizontally centred (1600/2 − 624/2 = 488), anchored to the top edge.
  Clone: one centred 624×320 (or display‑relative) transparent panel is enough; animate the *content*, not the window.
* `kCGWindowAlpha` always `1.0` – fading is done in layers inside, not with window alpha.
* `kCGWindowName` empty, `kCGWindowOwnerName` = `Alcove`.
* Levels 2147483628/2147483629 = `CGWindowLevelKey.maximum` − 19/−18 (above `kCGScreenSaverWindowLevel`=1000 and the menu bar); this is why the notch body covers the menu bar region.
* Settings window: ordinary `NSWindow` (layer 0, title "General"/"About"/…), Liquid‑Glass sidebar, 11 sidebar items (General; Notifications: Battery(disabled on VM), Connectivity, Focus, Display, Sound; Live Activities: Now Playing, Calendar, File Tray(“Soon”, disabled), Lock Screen; Alcove: License(“Trial” badge), About) – `shots/settings_about_check_updates.png`.

#### 1.2 What is *not* observable from CGWindowList
Panel class names (NotchPanel / NotchBackdropPanel / lock panel) are **not** exposed (names empty). Lock‑screen and
screensaver panels: **UNVERIFIED** (locking the VM session kills the remote display; not attempted).

#### 1.3 Visible geometry per state (near‑black bbox in 1× screenshots, OBSERVED, `windows/bbox_measurements.txt`, `windows/stop_burst_bbox.txt`)

| State | x range (px) | width | y range | height | screenshot |
|---|---|---|---|---|---|
| Idle simulated notch | 728..871 | **144** | 0..28 | **29** | `shots/state_relaunch_ax_revoked_volup.png` (HUD suppressed, so pure idle) |
| Hover (expandNotchOnHover=false) | 722..877 | 156 | 0..32 | 33 | `shots/state_hover.png` |
| Expanded – Calendar idle activity | 616..984 | 369 | 0..174 | 175 | `shots/state_expanded.png` |
| Sound HUD (vol up) | 634..965 | 332 | 0..28 | 29 | `shots/state_hud_volup_mediakey.png` |
| Sound HUD (mute) | 634..965 | 332 | 0..28 | 29 | `shots/state_hud_mute_mediakey.png` |
| Now Playing expanded (QuickTime) | 613..987 | 375 | 0..174 | 175 | `shots/state_nowplaying_qt_expanded.png`, `zoom_nowplaying_expanded.png` |
| Now Playing compact (playing) | 613..987 | 375 | 0..~59 | ~60 (crop) | `shots/state_nowplaying_qt_compact.png` |
| Now Playing compact after mouse leave / paused | 689..910 | 222 | 0..28 | 29 | `shots/state_nowplaying_after_mouse_leave.png`, `peek_burst_*.png` |

Notes: the idle notch is symmetric about x=800 (centre of a 1600‑px display); the HUD grows symmetrically (±94 px each side);
expanded states grow to ≈370 px wide and 175 px tall. Heights of 29 px for the closed shapes include the 1‑px dark
edge of the menu bar region, so treat as 28–29 px. Timing (open/close animation) is in the lead's `measure.py`
clips, not re‑measured here.

#### 1.4 Hide from screen capture (OBSERVED, `windows/states.txt` + `shots/capture_hfsc_off.png` / `capture_hfsc_on.png`)
`defaults write com.henrikruscon.Alcove hideFromScreenCapture -bool true` (the app observes the key live):
both panels go `sharing 1 → 0`; `screencapture -x -R` of the notch region then contains **no dark pixels**
(wallpaper shows through); setting it back to false restores `sharing=1`. Windows stay in the list, bounds unchanged.
Clone: `window.sharingType = .none` toggled from the preference.

#### 1.5 Hide in fullscreen / Mission Control (PARTIALLY OBSERVED)
With `hideWhileInFullscreen=1` and Safari sent to fullscreen via AppleScript/keyboard, the two Alcove windows **remained in
the CGWindow list with unchanged bounds/alpha** (`windows/states.txt` "fullscreen_*"). Visually the automation did not
reliably produce a true fullscreen Space in the VM, so whether Alcove hides by ordering out, by alpha on its layers
or by moving to another Space is **UNVERIFIED**. Mission Control (`shots/state_mission_control.png`): same – inventory unchanged.

#### 1.6 Display selection (OBSERVED, `defaults/`)
Settings ▸ General ▸ Display popup: *Main display* → `showOnDisplay=mainScreen`; *All displays* → `allDisplays`;
picking the concrete display ("Apple Virtual") → `showOnDisplay=specificDisplay` plus
`showOnDisplayName="Apple Virtual"`, `showOnDisplaySymbol="display"`, `showOnDisplayUUID=<CGDisplay UUID>`.
Multi‑display behaviour and the menu‑bar **Display** submenu: **UNVERIFIED** (one virtual display).

---

### 2. Persistence

#### 2.1 Where
* `~/Library/Preferences/com.henrikruscon.Alcove.plist` – all settings (OBSERVED).
* `~/Library/Caches/com.henrikruscon.Alcove/Cache.db{,-shm,-wal}` – NSURLCache; contains one cached response keyed
  `https://api.tryalcove.com/trial/<UUID>` (trial status cache; not inspected further) (OBSERVED, `net/cache_db_urls.txt`).
* `~/Library/HTTPStorages/com.henrikruscon.Alcove/httpstorages.sqlite` – only an `alt_services` row:
  `api.tryalcove.com:443 → h3` (OBSERVED, `net/alt_services.txt`).
* **No** `~/Library/Application Support/com.henrikruscon.Alcove`, **no** `~/Library/Containers/…` (not sandboxed),
  **no** LaunchAgents plist (OBSERVED).
* Login item: `SMAppService` main‑app login item registered with BackgroundTaskManagement
  (`sfltool dumpbtm`: Name Alcove, Team `287NUTSP69`, Identifier `2.com.henrikruscon.Alcove`,
  Disposition `[disabled, allowed, notified]` while `launchAtLogin=false`). The launch log shows
  `[com.apple.libxpc.SMAppService:all] Unregister (<private>) error: 1` at startup (it unregisters when the
  setting is off) (OBSERVED, `logs/launch_interesting.txt`). *Note:* the repeated "Login Item Added" banner on the VM
  coincided with my own `sudo sfltool dumpbtm` calls, not with Alcove actions.
* Keychain: `security dump-keychain | grep -i alcove` → no item names matched (OBSERVED; absence in this query only).
* iCloud KVS: no `NSUbiquitousKeyValueStore`/ubiquity log lines in 1 h of debug logging; VM has no iCloud account → **UNVERIFIED**.
* The TCC rows and `hasPrompted{Bluetooth,Calendar,Location}Permission` keys are the only onboarding state (OBSERVED).

#### 2.2 Behaviour
* Keys appear in the plist **only after first change** (sweep diffs show `(None, value)` for untouched keys) → the app
  uses `UserDefaults.register(defaults:)`/`@AppStorage` defaults in code. Defaults listed below were therefore
  taken from the UI's initial state and from the restored final plist (`defaults/99_final_state_typed.txt`).
* Changes written by `defaults write` from outside are picked up live (hideFromScreenCapture) – KVO/`@AppStorage`.
* Sliders write **Double** (`connectivityDuration 5.5`, `brightnessDuration 2.0`), steppers/percent sliders write
  Double too (`lowConnectBatteryThreshold 30.0`), ints only for `keepAwake`, `nowPlayingWidgetOffset`, `hideIdleDuration`, `timeBeforeEvent`.

#### 2.3 Key table (UI label → key → type → default → example values) – all OBSERVED via `defaults/toggle_sweep_run1.txt`, `defaults/general_*.txt`, `defaults/99_final_state_typed.txt`

**General**

| UI label | key | type | default | values seen |
|---|---|---|---|---|
| Launch at login | `launchAtLogin` | Bool | false | true/false (also drives SMAppService register/unregister) |
| Hide in fullscreen | `hideWhileInFullscreen` | Bool | true | |
| Hide in Mission Control | `hideWhileInMissionControl` | Bool | true | |
| Hide while gaming | `hideWhileGaming` | Bool | false | |
| Hide from screen capture | `hideFromScreenCapture` | Bool | false | flips window sharingState |
| Force simulated notch | `forceSimulatedNotch` | Bool | false | true on this VM |
| Idle Activity popup | `idleActivity` | String | `calendar` (as shipped here) | `none`, `nowPlaying`, `calendar`, `duo` |
| Most Recent | `mostRecentActivity` | Bool | false | |
| Display popup | `showOnDisplay` | String | `mainScreen` | `mainScreen`, `allDisplays`, `specificDisplay` (+ `showOnDisplayName/Symbol/UUID`) |
| Contrast outline | `contrastOutline` | Bool | true | |
| Progressive blur | `progressiveBlur` | Bool | true | |
| Haptic feedback | `enableHaptics` | Bool | true | |
| Expand on hover | `expandNotchOnHover` | Bool | false | |
| Natural movement | `naturalMovement` | Bool | false | |
| Swipe to toggle open | `swipeToToggle` | Bool | true | |
| Swipe to cycle activity | `swipeToCycleActivity` | Bool | true | |
| Swipe to dismiss activity | `swipeToDismiss` | Bool | true | |
| Swipe to skip media | `swipeToSkip` | Bool | true | |
| (internal) | `isFirstLaunch` | Bool | – | false after onboarding |
| (internal) | `hasPromptedBluetoothPermission`, `hasPromptedCalendarPermission`, `hasPromptedLocationPermission` | Bool | – | true |
| (AppKit) | `NSStatusItem VisibleCC Alcove` | Bool | – | true |

**Connectivity**

| UI label | key | type | default | values |
|---|---|---|---|---|
| Connectivity (enable) | `enableConnectivity` | Bool | true | |
| Duration | `connectivityDuration` | Double | 5 | 5.5 |
| Warn on low battery | `warnOnLowConnectBattery` | Bool | true | |
| Low battery threshold | `lowConnectBatteryThreshold` | Double | 20 | 30 |
| Play sound on low battery | `playSoundOnLowConnectBattery` | Bool | true | |
| Model segmented (3D / AirPods Pro symbol…) | `connectivityModel` | String | `threeDimensional` | `symbol` |

**Focus**

| UI label | key | type | default |
|---|---|---|---|
| Focus (enable) | `enableFocus` | Bool | true |
| Duration | `focusDuration` | Double | 5 |
| Play sound on sleep focus | `playSoundOnSleepFocus` | Bool | false |
| Replace waveform during focus | `replaceWaveformDuringFocus` | Bool | false |
| Hide label | `hideLabel` | Bool | false |
| Allow while focused: Battery / Connectivity / Display / Sound | `allowBatteryWhenFocused`, `allowConnectivityWhenFocused`, `allowBrightnessWhenFocused`, `allowVolumeWhenFocused` | Bool | true |

**Display (brightness HUD)**

| UI label | key | type | default | values |
|---|---|---|---|---|
| Display (enable) | `enableBrightness` | Bool | true | |
| Duration | `brightnessDuration` | Double | 1.5 | 2.0 |
| Progress style segmented | `brightnessProgressStyle` | String | `white` | `accent`, … |
| Show percentage | `showBrightnessPercentage` | Bool | false | |
| Hide label | `hideBrightnessLabel` | Bool | false | |
| Speed segmented | `brightnessSpeed` | String | `fast` | |

**Sound (volume HUD)**

| UI label | key | type | default | values |
|---|---|---|---|---|
| Sound (enable) | `enableVolume` | Bool | true | |
| Duration | `volumeDuration` | Double | 1.5 | |
| Progress style | `volumeProgressStyle` | String | `white` | |
| Show percentage | `showVolumePercentage` | Bool | false | |
| Hide label | `hideVolumeLabel` | Bool | false | |
| Speed | `volumeSpeed` | String | `fast` | |
| Output device label | `volumeOutputDevice` | String | `device` | |

**Now Playing**

| UI label | key | type | default | values |
|---|---|---|---|---|
| Now Playing (enable) | `enableNowPlaying` | Bool | true | |
| Idle duration | `idleDuration` | Double | 3 | |
| Song title badge | `songTitleBadge` | String | `explicit` | |
| Progress style | `progressStyle` | String | `mono` | |
| Disable waveform | `disableWaveform` | Bool | false | |
| Disable album art flip | `disableAlbumArtFlip` | Bool | false | |
| Hide while source is active | `hideWhileSourceIsActive` | Bool | false | |
| Hide song title extras | `hideSongTitleExtras` | Bool | false | |
| Control choice | `controlChoice` | String | `shuffle` | |
| Automatic music app | `automaticMusicApp` | Bool | false | |
| Music app | `musicApp` | String | `system` | |
| Quick Peek (enable) | `enableQuickPeek` | Bool | true | |
| When song changes | `whenSongChanges` | Bool | true | |
| Peek duration | `peekDuration` | Double | 2 | |

**Calendar**

| UI label | key | type | default |
|---|---|---|---|
| Calendar (enable) | `enableCalendar` | Bool | true |
| Time before event | `timeBeforeEvent` | Int | 15 |
| Play sound on calendar event | `playSoundOnCalendarEvent` | Bool | true |
| Play hourly chime | `playHourlyChime` | Bool | false |
| Use calendar color | `useCalendarColor` | Bool | false |
| Disable activity during events | `disableActivityDuringEvents` | Bool | false |
| Use event indicators | `useEventIndicators` | Bool | false |
| Always show month view | `alwaysShowMonthView` | Bool | false |
| Quick Peek (enable) | `enableCalendarQuickPeek` | Bool | true |
| Before event starts | `beforeEventStarts` | Bool | false |
| When event is starting | `whenEventIsStarting` | Bool | true |
| Peek duration | `calendarPeekDuration` | Double | 4 |
| Colored calendar indicator | `useColoredCalendarIndicator` | Bool | true |
| (internal) excluded calendars | `excludedCalendars` | Array | [] |
| (internal) | `calendarDisplayModes` | – | seen in sweep |

**Lock Screen**

| UI label | key | type | default |
|---|---|---|---|
| Lock Screen (enable) | `enableLockScreen` | Bool | true |
| Keep awake | `keepAwake` | Int | 0 |
| Show on screen saver | `showOnScreenSaver` | Bool | false |
| Play sound on lock / unlock | `playSoundOnLock` / `playSoundOnUnlock` | Bool | false / true |
| Widgets when locked: Battery/Connectivity/Focus/Calendar/Now Playing | `allowBatteryWidgetWhenLocked`, `allowConnectivityWidgetWhenLocked`, `allowFocusWidgetWhenLocked`, `allowCalendarWidgetWhenLocked`, `allowNowPlayingWidgetWhenLocked` | Bool | true (Calendar false) |
| Now Playing style | `nowPlayingStyle` | String | `glass` |
| Hide idle duration | `hideIdleDuration` | Int | 10 |
| Show volume control | `showVolumeControl` | Bool | false |
| Now Playing widget offset | `nowPlayingWidgetOffset` | Int | 0 |
| HUDs when locked: Battery/Connectivity/Focus/Display/Sound | `allowBatteryWhenLocked`, `allowConnectivityWhenLocked`, `allowFocusWhenLocked`, `allowBrightnessWhenLocked`, `allowVolumeWhenLocked` | Bool | true |

**About**

| UI label | key | type | default |
|---|---|---|---|
| Automatically check for updates | `automaticallyCheckForUpdates` | Bool | true |

Battery pane: disabled on this VM (no battery) → its keys **UNVERIFIED** (lead's `settings_ax/general.txt` lists them statically).

---

### 3. Unified logging

Command used (kept within the requested predicate, plus tccd lines mentioning Alcove):
```
log stream --style compact --level debug --predicate 'process == "Alcove" OR process == "AlcoveHelper" OR subsystem CONTAINS "henrikruscon" OR (process == "tccd" AND eventMessage CONTAINS "Alcove")'
```
Files: `logs/logstream_launch.txt` (launch → onboarding → first minutes), `logs/logstream_features.txt` (settings sweep,
HUDs, QuickTime, TCC experiments), counts in `logs/*_subsystem_counts.txt`, extracts in `logs/launch_interesting.txt`,
`logs/mediaremote_msgs.txt`, `logs/helper_msgs_features.txt`.

**There is no `henrikruscon` subsystem** – Alcove emits no `os_log` of its own at debug level (OBSERVED, 0 matches).
Everything below is framework logging attributed to the Alcove/AlcoveHelper processes.

| Subsystem:category (process) | Triggered by | Representative message |
|---|---|---|
| `com.apple.defaults:User Defaults` | every settings change; constant polling of CFPrefs | ~200 k lines; shows the app reads prefs very frequently |
| `com.apple.CFBundle:strings/resources` | UI rendering | localised strings lookups |
| `com.apple.amp.mediaremote:MediaRemote` (**AlcoveHelper**) | QuickTime play/pause/metadata | `_MRMediaRemotePlayerNowPlayingInfoDidChangeNotification`, `…PlaybackStateDidChange…`, `…IsPlayingDidChange…`, `…SupportedCommandsDidChange…`, `_kMRNowPlayingPlaybackQueueChangedNotification`, `_MRMediaRemoteApplicationDisplayNameDidChangeNotification` for `com.apple.QuickTimePlayerX` |
| `com.apple.amp.mediaremote:NowPlaying` (helper) | same | now‑playing info fetch |
| `com.apple.xpc.transaction:all` (helper) | main app asks helper | `getNowPlayingInfoForBundleIdentifier:reply:`, `getNowPlayingSource:`, `getIsPlaying:` |
| `com.apple.CFBundle:loading/plugin` (Alcove, launch) | startup | `dlopen …/PrivateFrameworks/MediaRemote.framework` |
| `com.apple.FrontBoard:Common` (Alcove, launch) | startup | `Reconnecting scene com.apple.controlcenter:<UUID>` / `…-Aux[1]-NSStatusItem…` (scene id uses the `com.apple.controlcenter` prefix, consistent with the helper's bundle id) |
| `com.apple.locationd.Core:Client`, `(CoreLocation) CL: CLLocationManager` | startup | `initWithEffectiveBundleIdentifier…`, `locationManagerDidChangeAuthorization` |
| `com.apple.weather:AuthService`, `com.apple.weather:WeatherDataService` | startup | `This is a 3rd party process so authenticate via com.apple.weatherkit.authservice`; `Sending request with User Agent=WeatherKit_Alcove_macOS_Version 26.6.2 (Build 25G83)` |
| `com.apple.libxpc.SMAppService:all` | startup | `Unregister (<private>) error: 1` |
| `com.apple.TCC:access` (Alcove) | startup | `TCCAccessRequest, service=kTCCServiceScreenCapture` (a ScreenCapture *check* at 10:03:08; no prompt appeared) |
| `com.apple.TCC:access` (tccd) | each media‑key event | `Handling access request to kTCCServicePostEvent, from Sub:{com.henrikruscon.Alcove}` – i.e. the app **posts** HID events (needed to swallow/replace the key) |
| `com.apple.TCC:events` (tccd) | `tccutil reset` | `TCCDEvent: type=Delete, service=kTCCServiceAccessibility, identifier=com.henrikruscon.Alcove` |
| `com.apple.DisplayServicesClient:default` | brightness paths | `key=DisplayServicesCanChangeBrightness display=1` |
| `com.apple.coreaudio:AMCP` | volume keys | `HALB_Logging.cpp:72 LogVolumeChangeForClientSide from AudioObjectSetPropertyData` – Alcove sets the volume itself through CoreAudio |
| `com.apple.network:quic/boringssl/connection`, `com.apple.CFNetwork:Default` | launch, trial check | HTTP/3 to `api.tryalcove.com` |
| `com.apple.coremedia:player/…`, `com.apple.coreaudio:AQ*` | launch / sounds | AVPlayer/AudioQueue (sound effects, waveform) |
| `com.apple.sidecar:core` | launch | Sidecar/display enumeration |
| `com.apple.AppKit:Animation/Window`, `com.apple.SkyLight:processes` | UI | `SLSSetFrontProcessWithInfo` |
| `com.apple.securityd:*`, `com.apple.launchservices:*`, `com.apple.corespotlight:*` | launch | framework noise |

Anything with `<private>` was left redacted; no payloads were captured.

---

### 4. Processes & IPC

#### 4.1 AlcoveHelper (STATIC: `proc/helper_info_plist.txt`; OBSERVED: `proc/relaunch_helper_timing.txt`)
* Path `Alcove.app/Contents/XPCServices/AlcoveHelper.xpc/Contents/MacOS/AlcoveHelper`, `CFBundleIdentifier =
  com.apple.controlcenter.AlcoveHelper`, `CFBundlePackageType = XPC!`, `XPCService.ServiceType = Application`,
  `LSMinimumSystemVersion 15.0`, built with Xcode 27.0 / SDK macOS 27.0 (`DTPlatformVersion 27.0`).
* Lifecycle: present **≤1 s after `open -a Alcove`**, persists for the life of the app (same pid for >1 h), killed with the app
  (`killall Alcove` → both gone). Launched by launchd as an XPC service child of the app (standard NSXPCConnection
  to an embedded XPC service; it never appears in `launchctl list` as a user agent).
* Role (OBSERVED from its log lines): it owns the `MediaRemote` client (NowPlaying notifications), and answers the
  main app's XPC requests `getNowPlayingInfoForBundleIdentifier:reply:`, `getNowPlayingSource:`, `getIsPlaying:`.
  The main app itself also `dlopen`s MediaRemote at launch.
* Threads: 2 (idle) – 4 (during playback); ~46–48 Mach ports.

#### 4.2 Main app
* `ps`: `/Applications/Alcove.app/Contents/MacOS/Alcove`, not sandboxed, no LaunchAgent.
* Threads 8–10: `com.apple.main-thread`, `com.apple.NSEventThread`, `caulk.messenger.shared:17`/`:high`,
  `caulk::deferred_logger`, `com.apple.coremedia.imagequeue.coreanimation.common` (`proc/sample_*.txt`).
  → audio engine (`caulk` = CoreAudio) is running even when idle; the imagequeue thread belongs to AVFoundation/CoreMedia.
* `lsof`: frameworks, the preference plist, Cache.db, httpstorages.sqlite; no sockets open while idle (`proc/lsof_*.txt`).
* Linked frameworks seen in the process image (STATIC via `sample`): AVFAudio, CoreAudio, CoreLocation, CoreMotion,
  EventKit, IOBluetooth, SwiftUI/SwiftUICore, WeatherKit, CoreBrightness, DisplayServices, MediaRemote, SkyLight.

#### 4.3 Resource usage (OBSERVED, `proc/top_*.txt`, `proc/footprint_*.txt`, `proc/powermetrics_raw_*.txt`)

| State | Alcove CPU | Alcove RSS | threads | Helper CPU / RSS | powermetrics (Alcove) |
|---|---|---|---|---|---|
| Idle, notch closed | 0.0 % | 71–72 MB | 8–9 | 0.0 % / 3.0–3.5 MB | 1.60 CPU ms/s, 5.90 wake‑ups/s, Energy Impact 0.16 |
| Expanded + QuickTime playing (live waveform) | 0.1 % | 71–73 MB | 9–10 | 0.0 % / 3.4 MB | 1.56 CPU ms/s, 6.59 wake‑ups/s, Energy Impact 0.16 |
| footprint | phys 71 MB, peak 108 MB (helper 2.9 / 3.0 MB) | | | | |

Takeaway: the waveform is cheap; whatever drives it does not change CPU measurably at 10‑s granularity. Peak 108 MB
occurred during onboarding/settings.

#### 4.4 Now Playing behaviour (OBSERVED)
* Source detection via MediaRemote works for QuickTime Player; title/artist from my m4a tags were **not** shown
  ("No Title" + waveform + progress bar) – QuickTime does not publish them to NowPlaying; Music/Spotify UNVERIFIED.
* After QuickTime **quit**, the compact Now Playing (222×29, paused) stayed for >60 s (`windows/stop_burst_bbox.txt`) –
  the app keeps the last MediaRemote source until it gets a new one.
* `hideWhileSourceIsActive`, Quick Peek on song change: a 20‑shot burst at 2 Hz after `next` is in `shots/peek_burst_*.png`.

---

### 5. Network (OBSERVED, `net/`)

Hosts:
| Host | When | Evidence |
|---|---|---|
| `api.tryalcove.com` (Cloudflare) | launch (trial status; cached under `/trial/<uuid>`), Check Updates, changelog | `net/cache_db_urls.txt`, `net/alt_services.txt` (h3), quic log lines |
| Apple WeatherKit (`com.apple.weatherkit.authservice` → Apple hosts) | launch | `logs/launch_interesting.txt` |
| 17.253.31.138:443 (Apple CDN) | one TCP SYN at 10:29:38 during the Settings‑open window; attribution to Alcove **INFERRED/weak** | `net/tcpdump_syn.txt` |

* Opening Settings: no new sockets (`net/lsof_poll.txt`, 0.5 s polling).
* **Check Updates…** (About pane): a busy indicator spins briefly; no new TCP SYN was captured in the following 10 s.
  Because `api.tryalcove.com` advertises HTTP/3 (`alt_services`), the request most likely went over the existing QUIC/UDP
  flow → **INFERRED**. On a trial the outcome is consistent with the `/updates/latest` 401 below; no dialog appeared.
* No mitmproxy was used (TLS pinning/licence traffic would have been in scope otherwise).

Public endpoints (plain `curl`, no auth, `net/resp_*.json`, `net/public_endpoints.txt`):

`GET https://api.tryalcove.com/changelog` → **200** `application/json`, 46 031 bytes, cache‑control present, `server: cloudflare`.
Shape:
```json
{ "updated": "<string>",
  "entries": [ { "version": "1.7", "description": "...",
                 "minors": [ { "version": "1.7.7", "date": "...", "note": "...", "features": [...], "fixes": [...] } ] } ] }
```
`GET https://api.tryalcove.com/updates/latest` → **401** `{"message":"An active license is required for this channel."}`
(the app presumably sends a licence credential; not examined).

---

### 6. Permissions / TCC (OBSERVED, `tcc/`)

System TCC.db rows for `com.henrikruscon.Alcove` after onboarding:
```
kTCCServiceCalendar         auth_value=2 (allowed) auth_reason=2 (user consent)   17:04:30
kTCCServiceBluetoothAlways  auth_value=2           auth_reason=2                  17:04:44
kTCCServiceAccessibility    auth_value=2           auth_reason=4 (System Settings) 17:05:37
```
Requested in onboarding order: AppleEvents targets (Music, Spotify, System Events; Safari, Chrome, Dia – these are
*described* in onboarding, actual AppleEvent prompts only fire when a target app is scripted – UNVERIFIED), Calendar,
Bluetooth, Accessibility. Location (`hasPromptedLocationPermission=true`, CLLocationManager at launch for WeatherKit)
– no TCC row was created on the VM. `kTCCServiceScreenCapture` is *queried* at launch (log) but never prompted.
`kTCCServicePostEvent` requests appear in tccd for every media‑key event the app handles.

Revocation experiment (`tcc/revoke_log_lines.txt`, `tcc/system_tcc_after_*.txt`, `shots/state_*ax_*`):
1. `tccutil reset Accessibility com.henrikruscon.Alcove` while running → row deleted; **the HUD keeps working**
   (existing event tap survives the reset; volume 43→55, HUD 332 px).
2. Relaunch with Accessibility denied: no prompt/onboarding shown; TCC row re‑created with `auth_value=0` at launch
   (the app checks `AXIsProcessTrusted` at startup); media keys now change volume through the **system** path (63) and
   Alcove shows **no HUD** (bbox stays idle 144 px). No system OSD either – this VM has no `OSDUIHelper` process at all,
   so OSD suppression on real hardware is **UNVERIFIED**.
3. Re‑enable the toggle in System Settings ▸ Privacy & Security ▸ Accessibility (password prompt) → `auth_value=2`
   and **within ~10 s, without relaunch,** media keys produce the Alcove HUD again (polls/observes trust and installs the tap).
Swipe gestures were not exercised in the denied state (no trackpad on the VM) – UNVERIFIED.

---

### 7. Media keys / HUD paths (OBSERVED, `scripts/mediakey.swift`, `shots/state_hud_*`)

| Path | Volume changes? | Alcove HUD? | Notes |
|---|---|---|---|
| `osascript -e 'set volume output volume 30'` | yes | **no** | CoreAudio property change only; Alcove does not watch the HAL volume property for its HUD |
| Synthetic `NX_SYSDEFINED` subtype 8, `NX_KEYTYPE_SOUND_UP/DOWN/MUTE`, posted with `CGEvent.post(.cghidEventTap)` | yes (Alcove sets it: `LogVolumeChangeForClientSide` from the Alcove process) | **yes** – Sound HUD 332×29 with speaker glyph, "Sound" label, white bar; mute shows slashed speaker | tccd logs `kTCCServicePostEvent` for Alcove → it consumes the key via a CGEvent tap and posts/handles itself |
| Synthetic `NX_KEYTYPE_BRIGHTNESS_UP/DOWN` | n/a (virtual display) | no | `DisplayServicesCanChangeBrightness display=1` lines appear; real‑panel brightness HUD UNVERIFIED |
| `NX_KEYTYPE_PLAY/NEXT/PREV` | – | Now Playing reacts (QuickTime) | see peek bursts |

System OSD: `OSDUIHelper` never ran on this VM, so "Alcove suppresses the OSD" is **UNVERIFIED** here; the mechanism
implied by the TCC log (Accessibility‑gated event tap that swallows the key and re‑posts) is **INFERRED**.

---

### 8. UNVERIFIED on this VM (hardware‑dependent)
Real notch geometry/alignment, Battery pane & low‑battery HUD, AirPods/Bluetooth connect card, Touch ID, multiple
displays & menu‑bar Display submenu, lock‑screen/screensaver panels, haptics, trackpad swipes, brightness HUD,
real fullscreen‑Space hiding, Music/Spotify metadata & album art, iCloud KVS.

---

### 9. Evidence index
* `scripts/` – winlist.py, winsample.py, osd_check.py, measure_bbox.py, mediakey.swift (+ compiled `mediakey`), netpoll.sh
* `windows/` – states.txt (all CGWindow dumps), hud_osd.txt, bbox_measurements.txt, stop_burst_bbox.txt
* `shots/` – every screenshot referenced above, settings_*.png / crop_*.png per pane, peek_burst_*/stop_burst_* series
* `defaults/` – numbered before/after snapshots, toggle_sweep_run1.txt (every control pressed with the resulting key diff), 99_final_state{.plist,_typed.txt}
* `logs/` – logstream_launch.txt, logstream_features.txt, *_subsystem_counts.txt, launch_interesting.txt, mediaremote_msgs.txt, helper_msgs_features.txt
* `proc/` – top_*, footprint_*, sample_*, powermetrics_raw_*, lsof_*, helper_info_plist.txt, relaunch_helper_timing.txt
* `net/` – public_endpoints.txt, resp_changelog.json, resp_updates_latest.json, cache_db_urls.txt, alt_services.txt, lsof_poll.txt, tcpdump_syn.txt
* `tcc/` – TCC.db extracts before/after revoke and regrant, revoke_log_lines.txt
* `media/` – tone1.m4a, tone2.m4a (tagged test tracks used with QuickTime)


---

# Part C: media, HUDs and gestures (pass 1)

_Source: `children/C_media/alcove_media_hud_gestures.md`. Evidence lives in `children/C_media/`._

## Alcove 1.7.7 (199): Now Playing, HUDs, Quick Peek, swipe gestures. Live feature + animation timing

Scope: live behaviour of the Now Playing activity, volume/brightness HUDs, Quick Peek and all notch gestures, measured on a macOS VM (1600x1200 @1x, no real notch, "Force simulated notch" ON, trial started through the normal onboarding). Every claim is tagged **OBSERVED** (seen live, with clip/frame evidence), **STATIC** (binary strings/disassembly), **INFERRED** (my reading of the evidence) or **UNVERIFIED** (could not be exercised on this VM). Evidence files are in the accompanying zip (`clips/*.mp4` 60 fps screen recordings, `clips/*_strip.png` frame strips, `clips/*.csv` per-frame notch bbox, `clips/*.actions` wall-clock action logs, `swipe_scan_*.txt` gesture scans, `tools/evt.swift` input synthesiser, `*.py` measurement scripts, `r2_*.txt` disassembly).

Measurement conventions
- Recorder: `rec.sh` -> ffmpeg avfoundation, 60 fps, full screen 1600x1200. All frame numbers below are 0-based frames of the named clip; `t_ms = frame * 16.667`.
- `measure2.py <clip> <y> <h>`: for every frame finds the near-black (max channel < 22) run on row 2 within the top-centre ROI => `left,right,width`; `hmax` = lowest dark row over sampled columns (= panel height), `inner_lum` = mean luminance inside the panel (content opacity proxy).
- `probe.py`: one-shot screencapture of the top strip and the same bbox measure (used for the gesture threshold scans; it is not frame accurate, it is a yes/no state read ~0.8 s after the gesture).
- Caveat on absolute latencies: `rec-start` in the `.actions` logs is printed before ffmpeg actually starts capturing; ffmpeg startup is ~0.45 s (calibrated in `hover_expand.mp4`: the mouse-enter and mouse-leave logs both precede the first frame of motion by 0.44-0.47 s), so action -> frame mapping is only good to roughly +-0.3 s unless stated. Durations measured *within* a clip (first-motion to settle) are frame accurate (+-1 frame = 16.7 ms).
- Geometry baseline (OBSERVED, `np_compact_state.png`, `gestures.csv` f0): simulated notch with no activity = 140 x 28 px (same as the lead's calendar baseline); the display is 1600 px wide so the notch is centred at x=800.

### 1. Geometry of every Now Playing state (OBSERVED)

| State | Width px | Height px | Evidence |
|---|---|---|---|
| Empty notch (no activity, nothing playing or activity dismissed) | 140 | 28 | `gestures.csv`, `probe.py` after dismiss (`swipe_scan_vertical.txt`: `width=152` = 140 + hover grow) |
| Compact Now Playing (playing) | 216-218 | 28-29 | `np_compact_state.png`, `pause_idle.csv` f0, probe after launch |
| Compact Now Playing, cursor hovering (Expand on hover OFF) | 234-236 | 33 | `gestures.csv` f104-f111, every `probe.py` line taken with the cursor over the notch |
| Compact, idle (paused > 3 s): artwork+waveform faded out, then panel shrinks | 216 -> 140 | 28 | `pause_idle.csv` |
| Expanded media player | 362 settled (373 peak during open) | 120 | `np_expand.csv`, `gestures.csv` f213-f229, `np_expanded_state.png`, `np_expanded_f400.png` |
| Volume HUD (compact, replaces/overlays activity) | 326 | 28 | `hud_vol_keys2.csv` |

Compact layout (OBSERVED, `np_compact_state.png`, `artflip.py`, `waveform.py`): the 216 px panel is the 140 px notch plus two 38 px wings. Left wing: square artwork ~22 x 22 px with ~5 px corner radius centred vertically (artwork pixels occupy x 696..724, y 3..26 in the 1600 px frame). Right wing: 5 waveform bars. Bars are 2 px wide on a 4 px pitch at x = 882-883, 886-887, 889-891 (centre bar measures 3 px because of anti-aliasing), 893-894, 896-897 i.e. 16 px wide group right-aligned ~10 px from the panel edge; bar heights oscillate 2..12 px, centred vertically (y centre ~14). Bars are drawn in the artwork's dominant colour (pink for the generated test artwork; teal/green after the track with the teal artwork started, see artwork flip), so the waveform tint is derived from the artwork (OBSERVED colour follows artwork in `artflip_distinct.mp4`; INFERRED: average/dominant colour extraction).

Expanded layout (OBSERVED, `np_expanded_state.png`, `np_expanded_f400.png`; 362 x 120 panel, x 618..980): artwork ~56 x 56 px with ~10 px radius at top-left (inset ~14 px); title (bold, ~13 pt, white) and artist (regular, ~11 pt, grey) to the right of the artwork, both in a marquee container; waveform group (same 5 bars, larger: ~3 px bars on 5 px pitch, heights up to ~20 px) at top-right; progress track full width under that (thin ~4 px rounded track, filled part white, remainder dark grey) with elapsed time left and remaining time right (`-m:ss`, ~10 pt monospaced digits); bottom row centred controls: extra button (Shuffle in default config), previous, play/pause (larger), next. Explicit badge and Favorite/Repeat/Copy variants: UNVERIFIED (not exercised, see section 8).

### 2. Now Playing animations (OBSERVED unless stated)

#### 2.1 Activity appearance (play starts, closed notch 140 -> 216) and disappearance
Clip `np_start.mp4`, `np_start.csv`, strips `np_start_open_strip.png`, `np_start_close_strip.png`, `np_start_strip.png`.
Appear: f148 144, f149 148, f150 153, f151 160, f152 167, f153 172, f154 177, f155 183, f156 187, f157 192, f159 197, f160 200, f162 204, f164 208, f166 210, f167 212, f170 213, f173 214, f175 216 (settled). 27 frames = 450 ms, ease-out, **no overshoot** (never exceeds 216), height fixed at 28. Artwork + waveform fade in from f154 (inner_lum 0.2, i.e. 100 ms after first motion, when the wings are ~60% grown) and reach full opacity around f170-f175 (~350-450 ms), so content opacity tracks the width progress with a ~100 ms delay.
Disappear (stop): f711 213 ... f740 140: 29 frames = 483 ms, same ease-out, no overshoot; content fades out during the first ~7 frames (inner_lum 1.7 -> 0.0 by f718, ~120 ms). Model (INFERRED): same overdamped spring as the collapse in 2.3.

#### 2.2 Expand (compact -> expanded player) by click or swipe
Clip `gestures.mp4` (swipe open; click open in `np_expand.mp4` is identical within 1 frame), strip `gesture_swipeopen_strip.png` (f201..f232 every frame).

| frame | t from first motion (ms) | width | height |
|---|---|---|---|
| 202 | -17 | 246 (rubber-banded compact, see 4.3) | 42 |
| 203 | 0 | 250 | 47 |
| 204 | 17 | 259 | 57 |
| 205 | 33 | 270 | 71 |
| 206 | 50 | 284 | 87 |
| 207 | 67 | 298 | 103 |
| 208 | 83 | 310 | 118 |
| 209 | 100 | 322 | 120 (height saturates first) |
| 211 | 133 | 345 | 120 |
| 213 | 167 | 365 | 120 (crosses rest width 362) |
| 215 | 200 | 370 | |
| 218 | 250 | 373 = peak (+11 px, +3.0% of 362; +8.7% of the 127 px travel) | |
| 222 | 317 | 370 | |
| 225 | 350 | 366 | |
| 229 | 433 | 362 = settled (within 1 px thereafter) | |

Total ~430 ms first motion -> settle, one overshoot, no visible second bounce (undershoot < 1 px). Height 28 -> 120 completes in 100 ms with no overshoot (it is clamped by the panel content), width is the springy axis. Fitted model (INFERRED): a critically-ish damped spring; from overshoot 8.7% of travel => damping ratio zeta = -ln(0.087)/sqrt(pi^2 + ln(0.087)^2) ~= 0.61, half period (first motion to peak) 250 ms => damped period 500 ms => omega_d = 12.6 rad/s, omega_n = omega_d/sqrt(1-zeta^2) ~= 15.9 rad/s => SwiftUI `Spring(response: 2*pi/omega_n ~= 0.40 s, dampingFraction ~= 0.6)`, which is equivalent to `Spring(duration: 0.4, bounce: 0.4)` (bounce = 1 - zeta). STATIC cross-check: the binary passes `(duration 0.4, bounce 0.35)` 6x and `(0.45, 0.4)` 5x to SwiftUI spring initialisers (`spring_constants.txt`, `r2_dump.txt`); either matches the observed curve within measurement error. The lead's calendar open (517 ms, +5.6%) is the same family but looked slower because the calendar panel travels further and was measured to a tighter settle.

Content: during expansion the compact artwork/waveform cross-fade into the large layout; title/artist/controls fade in between ~f209 and ~f222 (inner_lum 7 -> 14.6 in `gestures.csv`), i.e. ~100-320 ms after first motion.

#### 2.3 Collapse (expanded -> compact) on mouse exit
Clip `gestures.mp4` f647..f674, strip `gesture_mouseexit_close_strip.png`. Mouse left the panel at ~f646. Width 362 -> 216, height 120 -> 28:

f647 358, f648 350, f649 333, f650 322, f651 305, f652 294, f653 282, f654 270, f655 261, f656 253, f657 248, f658 242, f659 238, f660 234, f661 230, f662 228, f663 226, f664 224, f665 222, f666 221, f667 220, f670 220, f671 218, f672 217, f674 216 (settled).

27 frames = 450 ms, monotonic, no overshoot (ease-out, fastest in the first 100 ms: 362->305 in 4 frames). Height 120 -> 28 follows the same curve (f647 120 ... f653 95, f660 46, f666 34, f674 28). Fitted model (INFERRED): overdamped spring / `Spring(duration ~0.45, bounce <= 0)`; STATIC candidates `(0.35, -0.2)` 6x in the binary. Compare the lead's calendar close 583 ms (longer travel 358 -> 140). The close starts immediately on exit (<= 1 frame after the cursor left the panel), there is no exit debounce visible at 60 fps; STATIC strings `hoverDebounce`, `hoverDuration` exist but their values were not recovered.

#### 2.4 Hover: grow (Expand on hover OFF, default) and hover-expand (Expand on hover ON)
Expand on hover OFF: clip `gestures.mp4` f104-f111, strips `hover_in_strip.png`, `hover_out_strip.png`, `hover_plain.csv`. Cursor entering the compact panel: width 216 -> 236 and height 28 -> 33 in 7 frames (~117 ms), ~1 frame latency, slight overshoot to 236 then 234 (1 px). Leaving: back to 216/28 in ~130 ms. INFERRED: a scale-up of ~1.08 (both axes grow ~8%) i.e. a `scaleEffect` hover affordance, not a layout change.

Expand on hover ON (toggled in Settings > General > Behaviour, screenshot `settings_general_after_toggle.png`): clip `hover_expand.mp4`, `hover_expand.csv`, strips `hover_expand_open_strip.png` (f94..f125), `hover_expand_close_strip.png` (f339..f370).
- Hover delay: mouse-enter log precedes first motion by 0.468 s and mouse-leave precedes close first motion by 0.440 s; the difference (~30 ms, 1-2 frames) is the whole hover delay. OBSERVED: hover-expand starts within ~2 frames of the cursor entering the 216 px panel, there is no deliberate hover delay (`hoverDuration` STATIC string notwithstanding; `probe.py` 0.2 s after the move already read 377 x 120 mid-overshoot).
- Open: f96 217/30, f97 237/51, f99 268/83, f101 301/117, f104 330/120, f107 361, f108 370, f110 374, f113 **376 peak** (+14 px, +3.9% of 362, +9.6% of travel), f116 370, f121 366, f124 **362 settled**: 28 frames = 467 ms. Same spring as the click/swipe open (2.2) but starting from the un-hovered 216 px (travel 146 px) instead of the rubber-banded 246 px, hence the slightly larger overshoot. Height 28 -> 120 in 5 frames (83 ms). Content fades in from f101 to f107 (inner_lum 11 -> 25).
- Close on exit: f341 337, f344 305, f345 282, f348 262, f349 248, f351 237, f354 230, f356 226, f357 222, f359 220, f363 218, f366 216: 25 frames = 417 ms, no overshoot (identical curve to 2.3 within 2 frames).

#### 2.5 Pause -> idle -> collapse
Clip `pause_idle.mp4`, `pause_idle.csv`, strips `pause_idle_fade_strip.png`, `pause_idle_collapse_strip.png`. `pause` AppleScript sent at 1.53 s after actions-begin (`pause_idle.actions`), i.e. at clip ~2.2-2.5 s. Artwork+waveform fade out from f140 (2333 ms) to f155 (2583 ms): 15 frames = 250 ms linear-ish opacity fade; the panel keeps its 216 px for the whole idle period. Panel collapse 216 -> 140 starts f320 (5333 ms) = 3.0 s after the fade started (matches "Now Playing idle duration = 3 s" in Settings, OBSERVED) and finishes f348: 28 frames = 467 ms, monotonic, no overshoot (same ease-out as 2.3). So: pause -> ~0.1-0.3 s -> 250 ms content fade -> 3.0 s hold at full width (black) -> 467 ms shrink to 140.

#### 2.6 Artwork flip on track change
Clip `artflip_distinct.mp4` (play a different local track with different artwork, command at ~clip 2.5 s), strip `artflip_distinct_strip.png` (40 frames, f140..f179 every frame, compact artwork cell x650..700 cropped and 4x zoomed), per-frame data `artflip.py` (lit-pixel count and mean colour of the artwork cell):

- f140-f163: old (pink) artwork, mean colour drifting (title/colour cross-fade starting).
- f164 -> f171 (133 ms): artwork's lit area 426 -> 67 px: the square compresses horizontally to a ~2 px vertical line (3-D Y-axis flip, first half).
- f172-f173: nothing visible (edge-on).
- f174 -> f181 (133 ms): new (teal) artwork grows back from the line to the full square (second half of the flip), mean colour now (67,156,165).
- Total flip ~300 ms (f164..f181), symmetric, no overshoot; the waveform bars change tint to the new dominant colour in the same window.

INFERRED: `rotation3DEffect` about the Y axis 0 -> 90 -> 0 with the image swapped at 90 deg, ~0.3 s total. Setting "Disable artwork flip" (default off) presumably replaces this with a cross-fade: UNVERIFIED. A same-artwork track change (`artchange_same_strip.png`, `track_change2.mp4`) shows only an opacity dip, no flip (OBSERVED), so the flip is gated on artwork actually changing (INFERRED).

#### 2.7 Marquee (long title) scroll
Clips `np_expand.mp4`, `marquee_long.mp4`; tracking `marquee.py`, output `np_expand_marquee.txt`, `marquee_long.txt`. Title "A Very Long Song Title That Should Definitely Overflow The Marquee Label" in the expanded player. Local cross-correlation of the title row gives a steady -5.5 +-0.5 px/frame = ~330 px/s (OBSERVED, over f330..f830 of `np_expand.mp4`, cumulative -344 px over 500 frames, direction right-to-left). The text is drawn twice with a gap and wraps continuously (re-anchor jumps in the tracker every time the duplicate passes). An end pause was not detected within the 8 s observed window: the scroll looks continuous (OBSERVED for a single-line overflow title; the artist line was short and static). STATIC: classes `MarqueeText`, `NSMarqueeTextView` exist. Caveat: 330 px/s is faster than typical Apple marquees; tracker outliers were excluded manually, treat as +-10%.

#### 2.8 Waveform animation
`waveform.py` on `pause_idle.mp4` f10..f129 (compact, playing, "Use live waveform" OFF because audio capture had not been unblocked at record time): 5 bars; bar heights change in 2 px steps on 34 of 119 frame pairs = a new target roughly every 3.5 frames (~17 Hz) with the in-between frames holding, each bar moving independently between 2 and 12 px; looks like a per-bar random walk / looping fake spectrum (INFERRED: `WaveformAnimationClock` + `WaveformSpectrumSession` STATIC symbols; the animation is not synced to audio). The compact waveform fades with the artwork on pause (2.5). Live waveform (`useLiveWaveform` STATIC string, Settings toggle): not measured; after installing the BlackHole virtual output device macOS exposed an audio device but the live-waveform recording was not completed: UNVERIFIED. "Disable compact waveform": UNVERIFIED.

#### 2.9 Quick Peek (media change while closed)
STATIC: `QuickPeek`, `NotchQuickPeekView`, `quickPeekDebounce`, `quickPeekResetDebounce`, `quickPeekGeneration`, `peekDuration`; Settings: Quick Peek enabled, duration 2 s (lead's `settings_ax/general.txt`). Attempts `quickpeek_next*.mp4` / `track_change*.mp4`: track changes made via Music AppleScript while the panel was closed produced the compact artwork flip (2.6) and a ~0.3 s title colour cross-fade but no transient expansion of the panel in any of 5 attempts (`track_change.csv`, `track_change2.csv`: width stays 216). INFERRED: Quick Peek either requires a change in the media *source* (different app) or is suppressed while the same compact activity is already showing; or Music's unreliable `next track` on this VM (AppleScript error -1728 half the time) never produced a "did change" event Alcove considered peek-worthy. Peek timing is therefore UNVERIFIED; the 2 s default is from the Settings UI only.

### 3. HUDs

#### 3.1 Volume HUD via media keys (OBSERVED)
Trigger: `tools/evt key sound_down 3 300` (NX_KEYTYPE_SOUND_DOWN system-defined events, 3 presses 300 ms apart), then `sound_up 3 300`. Clip `hud_vol_keys2.mp4`, `hud_vol_keys2.csv`, strips `hud_vol_open_strip.png`, `hud_vol_close_strip.png`, states `hud_vol_keys_f165.png`, `hud_vol_keys_f440.png`, `hud_vol_state_f200.png`, `hud_vol_state_f360.png`. (Audio device: BlackHole 2ch installed to give the VM an output device; before that `set volume` returned `missing value` but the key HUD still showed.)

Open (first key press): width 140 -> 326, height stays 28 (compact HUD, no vertical growth):
f327 148, f328 157, f329 173, f330 192, f331 224, f333 236, f334 252, f336 272, f338 288, f340 300, f342 308, f344 314, f347 320, f350 322, f351 324, f356 325, f357 326 (settled). 30 frames = 500 ms, ease-out, no overshoot (0 px). Content (speaker symbol left, "Sound" label, white bar, 'inner_lum' 0 -> 22) fades in from f331 to ~f357, i.e. starts ~70 ms after the width starts moving and lands with it.
Hold: the HUD stays at 326 until f454; with 3 presses 300 ms apart the HUD dismissed 1.5 s (+-0.1 s, limited by the rec-start caveat) after the *last* key event: Settings "HUD duration 1.5 s" is measured from the last value change, each new press restarts the timer (OBSERVED: no dismissal between presses 300 ms apart).
Dismiss: f454 324, f455 312, f456 296, f457 281, f458 261, f459 248, f460 232, f461 221, f462 208, f465 184, f470 158, f476 148, f480 144, f490 140. 36 frames = 600 ms, monotonic ease-out, no overshoot; content fades out during the first ~8 frames (inner_lum 22 -> 0.1 by f462, ~130 ms) then the empty panel keeps shrinking.
Value change: the bar fill animates between presses (OBSERVED visually in `hud_vol_keys_f165.png` vs `hud_vol_keys_f440.png`); fill tween duration was not isolated because the fill is only ~1 px different per press on a 326 px HUD at 60 fps: UNVERIFIED (Speed setting Smooth/Fast/Instant, which per the Settings copy controls this tween, not measured).
Layout (OBSERVED, `hud_vol_state_f200.png`): 326 x 28 black pill; SF speaker glyph (speaker.wave.2/3 variant following the level) at the left wing centre, "Sound" label in ~11 pt grey to its right, white progress bar (~4 px tall, rounded, ~110 px long) on the right wing. Styles White (default) only; Accent/Decibel/Glow, "Show percentage", "Hide label", "Show device" glyph: UNVERIFIED (Settings exist, see lead's `settings_ax/general.txt`; not exercised in this session).

#### 3.2 Volume via AppleScript `set volume output volume N` (OBSERVED: no HUD)
Clip `hud_vol_osa.mp4`: `set volume output volume 30` then `60` 0.9 s later. No pixel changed in the top band for the following 2.3 s (`hud_vol_osa.csv`, per-frame diff scan): Alcove does not show the Sound HUD for programmatic volume changes, only for key-driven ones (the panel briefly shrank 216 -> 140 at the clip's very end, f524-f539, which was the media activity hiding, unrelated to volume). INFERRED: Alcove listens for the media-key / OSD events (replacing the system OSD, `OSDUIHelper` is referenced in `helper_strings.txt`) rather than observing the CoreAudio volume property.

#### 3.3 Brightness HUD
`tools/evt key bright_up` on this VM: the VM has no backlight-capable display, so brightness keys do nothing and no HUD appeared. UNVERIFIED. STATIC: `brightnessDuration`, Display HUD styles White/Accent/Glow in Settings.

### 4. Gestures (swipe thresholds measured empirically)

#### 4.1 Method
`tools/evt.swift` (compiled `tools/evt`), command `swipeseq X Y "dx:dy,dx:dy,..." msPerStep`: moves the cursor to (X,Y) = (800,14) over the notch, then posts one continuous trackpad-style gesture with `CGEvent(scrollWheelEvent2Source:units:.pixel,wheelCount:2,...)`, `kCGScrollWheelEventIsContinuous = 1`, `scrollWheelEventScrollPhase` = MayBegin(128) -> Began(1) on the first step -> Changed(2) -> Ended(4) with zero delta, momentum phase 0, `FixedPtDeltaAxis1/2` and `PointDeltaAxis1/2` set to the per-step deltas (axis1 = vertical dy, axis2 = horizontal dx; negative dy = fingers moving up on a natural-scrolling trackpad is what AppKit reports as `scrollingDeltaY < 0`). 8 steps 16 ms apart unless stated. `scan.sh` wraps one gesture + `probe.py` read-out + moving the cursor away. Logs: `swipe_scan_vertical.txt`, `swipe_scan_vertical_fine.txt`, `swipe_scan_horizontal*.txt`, `swipe_scan_close.txt`, `swipe_scan_close_dismiss.txt`. Settings during the scans: Swipe to toggle open / cycle activity / dismiss / skip media all ON, Natural movement OFF, Expand on hover OFF (lead's defaults).

Units: all thresholds below are the *net accumulated* scroll delta of one gesture in scroll pixel units (sum of FixedPtDelta over the gesture, as `NSEvent.scrollingDeltaY/X` would report).

#### 4.2 Results (OBSERVED)

| Gesture (state before) | Direction | No trigger up to | Triggers from | Threshold (STATIC name) | Reset / reversal |
|---|---|---|---|---|---|
| Toggle open (compact Now Playing -> expanded) | dy negative (scroll up / fingers up) | -34 | -36 | **35 px** (`verticalSwipeSuccessThreshold`, INFERRED = 35.0) | Reversal does not reset: -30,+20,-25 (net -35) opened; -30,+5,-5,-5 (net -35) opened. Threshold applies to the net sum. |
| Dismiss activity (compact Now Playing -> empty 140 px notch; Music keeps playing) | dy positive | +34 | +36 | **35 px** (same magnitude as toggle) | Not tested beyond net sum |
| Toggle closed (expanded -> compact) | dy positive | +100 | +110 | **~105 px** (100 < T <= 110) | - |
| Toggle open while already expanded | dy negative up to -80 | no-op | - | - | - |
| Skip media (compact Now Playing) | dx | +75 / -70 | +80 / -80 | **~80 px** (`horizontalSwipeSuccessThreshold`, 75 < T <= 80) | see caveat |
| Cycle activity | - | - | - | `cycleActivitySwipeSuccessThreshold` | UNVERIFIED: only one activity (Now Playing) was ever present; the idle "calendar" activity never showed on this VM so there was nothing to cycle to. |

Notes
- Trigger timing (OBSERVED): the gesture resolves on the **Ended** phase, not when the threshold is crossed: a Began(-40) step held for 2 s left the panel in the rubber-banded compact state (`probe` at +1.2 s: 234 x 33), and it opened only after Ended was posted (`swipe_scan_horizontal.txt` first two blocks). Number of steps and speed do not matter: -40 in 1 step, 2 steps, 8 steps or 24 slow steps all opened; -34 in 8 steps never did.
- Haptics: `NSHapticFeedbackManager` cannot be observed on this VM: UNVERIFIED. (STATIC: the binary imports AppKit haptics, see lead `imports.txt`; whether `perform(.alignment/.generic)` is called on swipe success is unknown.)
- Reset thresholds (`verticalSwipeResetThreshold` etc., STATIC names): I could not provoke a reset by reversing within a gesture (table above), so if a reset threshold exists it is either larger than the 20 px reversal tested or it operates across gestures (`swipeResetDebounce` STATIC string suggests a time-based reset of accumulated delta between gestures). INFERRED: progress is accumulated per gesture (Began..Ended) and discarded on Ended.
- Skip caveat (OBSERVED inconsistency): with Music's "repeat one" a +80 px swipe restarted the current track (position 115 s -> 1 s = next/prev on a 1-track loop); later -80/-120/-200 restarted it (repeat all) while +76..+120 did nothing, and in a final repeat-one run neither +-60..90 did anything. Music.app's MediaRemote next/prev handling was flaky all session (AppleScript `next track` intermittently errored -1728), so the sign-to-command mapping (which direction is next vs previous) and the exact threshold are lower confidence than the vertical numbers; what is solid: nothing ever fired below |dx| = 76 and fires were only seen at |dx| >= 80. No visual feedback (no arrow/chevron overlay, no stretch) appeared in the notch for a horizontal swipe; in `gestures.mp4` the -96 px horizontal swipe at ~f500 was made on the expanded panel and changed nothing (width stayed 362, Music position unchanged).

#### 4.3 Follow-finger / rubber band during a vertical swipe (OBSERVED)
Clip `gestures.mp4` f136..f202, strip `gesture_rubberband_strip.png` (f150..f201 every 2nd frame): a slow -40 px swipe (20 steps of -2 px every 50 ms, 1.0 s) over the hovered compact panel (234 x 33) grows it progressively to 246 x 42 by the last step: +12 px width and +9 px height for 40 px of accumulated delta, i.e. ~0.3 px/px horizontally and ~0.22 px/px vertically, roughly linear in the accumulated delta (f152 234/34, f165 240/37, f179 244/40, f191 246/42). The stretch is released into the full open animation on Ended (2.2). For a sub-threshold gesture the panel springs back to 234 x 33 (`probe` after -34). Horizontal swipes produce no visible stretch (OBSERVED on the expanded panel; compact not recorded at 60 fps).

#### 4.4 Natural movement (OBSERVED, `swipe_scan_natural.txt`)
Toggled ON in Settings > General > Gestures (AX click; the keys are not plain `defaults`, writing `naturalMovement`/`expandOnHover` had no effect). With Natural movement ON and Expand on hover OFF, over the compact Now Playing:
- dy = -40 (8 steps): **still opens** (365 x 120). Vertical toggle-open direction is NOT inverted by Natural movement.
- dy = +40 (8 steps): **no longer dismisses** (panel stayed 234 x 33 compact, activity kept) whereas with Natural movement OFF +36..+40 dismissed every time (4.2).
- expanded, dy = +120: **still closes** (365 -> 234).
- dy = -120 posted 0.3 s after that closing gesture: did **not** open (234). Single observation; INFERRED: a short inter-gesture reset/debounce (`swipeResetDebounce` STATIC string) ignores a new gesture that starts within well under a second of the previous one. All the threshold scans in 4.2 left >= 1.5 s between gestures.
- Horizontal skip and the inverted dismiss direction (does +dy become open and -dy dismiss for some state?) were not re-scanned with Natural movement ON: UNVERIFIED. The toggle was restored to OFF afterwards (`settings_general_restored.png`).

Expand on hover: see 2.4 (no measurable hover delay, 467 ms open, 417 ms close on exit).

### 5. Idle / other activities
"Idle activity = calendar" is set (`defaults`), but no calendar activity ever appeared in the simulated notch even with an event created 9 minutes ahead (`Calendar` AppleScript, probe stayed 218 px Now Playing). UNVERIFIED on this VM.

### 6. STATIC spring constants (for the clone)
From `r2_springs.txt`/`r2_dump.txt`/`spring_constants.txt`: SwiftUI `Spring(duration:bounce:)` calls with constants (count): (0.35,0.3) x15, (0.3,0.25) x10, (0.6,0.4) x9, (0.6,0.35) x9, (0.35,-0.2) x6, (0.4,0.35) x6, (0.45,0.4) x5, plus singles (0.5,0.45) (0.35,0.4) (0.6,0.3) (0.4,0.3) (0.3,1.0) (0.35,0.7) (0.3,0.45) (1.0,0.4) (0.275,0.375) (0.3,0.2) (0.3,0.1953). Mapping to observed animations (INFERRED): expand = (0.4,0.35)/(0.45,0.4); collapse/HUD dismiss/idle shrink = (0.35,-0.2) or similar bounce <= 0; hover grow = (0.3,0.25); HUD open = (0.6,0.35) family (500 ms no overshoot would be bounce ~0); artwork flip ~0.3 s = (0.3,0.2)-ish.

### 7. Quick reference numbers for the clone
- Closed notch 140x28; compact media 216x28 (38 px wings); hover scale ~1.08 in ~120 ms; expanded 362x120.
- Expand: ~430 ms, +3% width overshoot at 250 ms, height done in 100 ms. Collapse: 450 ms ease-out, no overshoot, starts <= 16 ms after mouse exit.
- Pause: 250 ms content fade, 3.0 s hold, 467 ms shrink to 140.
- Artwork flip: 300 ms Y-flip, image swap at 150 ms. Marquee ~330 px/s right-to-left, continuous.
- Waveform: 5 bars, 2 px on 4 px pitch, heights 2..12 px, new target ~every 3-4 frames (~17 Hz), tinted from artwork.
- Sound HUD: 326x28, open 500 ms ease-out (content fades in from +70 ms), hold 1.5 s after last key, dismiss 600 ms ease-out (content gone in 130 ms); only media keys trigger it, not `set volume`.
- Swipes: resolve on gesture end; open at net -35 px; dismiss at net +35 px (Natural movement OFF); close expanded at ~+105 px; skip at ~|80| px; reversal within a gesture does not reset; ~sub-second inter-gesture debounce; rubber band ~0.3 px per scroll px.
- Hover (Expand on hover ON): no hover delay (<= 2 frames), open 467 ms with +3.9% overshoot, close 417 ms on exit.

### 8. Not covered / UNVERIFIED list
Brightness HUD; HUD Speed Smooth/Fast/Instant tween; HUD styles Accent/Decibel/Glow, Show percentage, Hide label, Show device; Now Playing Format Monochrome/Colored/Gradient; Explicit badge variants; extra button Favorite/Repeat/Copy; Hide while source app is active; Hide media title extras; Source Automatic/System; Spotify/Safari sources; live waveform; Disable artwork flip; Quick Peek timing; cycle-activity threshold; Natural movement effect on skip direction; haptics; real notch geometry (all measurements are on the simulated notch at 1x).


---

# Part C2: media, HUDs and gestures (pass 2)

_Source: `children/C_media/alcove_media_hud_gestures_v2.md`. Evidence lives in `children/C_media/`._

## Alcove 1.7.7 (199) – Now Playing / HUD / Quick Peek / Gestures – report v2 (follow-up pass)

This v2 supplements the v1 report `alcove_media_hud_gestures.md` (all v1 measurements still stand; nothing here contradicts them except where noted). Only the section-8 follow-up items are covered: Sound HUD speed/style variants, Now Playing formats + colour derivation, Explicit badge + Extra buttons, Quick Peek, live waveform, cycle activity. Brightness HUD is owned by another session and was not touched.

Environment: same VM as v1 (1600x1200 @1x, Force simulated notch ON, Alcove 1.7.7 build 199, trial active, Music.app with local tracks in playlist `AlcoveTest`: "Short" (no artwork, artist Shorty), "Long Title Track Number One For Marquee Scrolling Test" (blue/green checker artwork, artist Two), "A Very Long Song Title ..." (pink/blue artwork)). Clips are 60 fps ffmpeg/avfoundation (`rec.sh`/`clip.sh`), frame numbers below are 60 fps frame indices in the named clip (1 frame = 16.7 ms). Settings were changed through Alcove's own Settings window via Accessibility (`ax_click.sh X Y` clicks the control at AX position X,Y; `ax_list.sh` dumps controls). Every claim is tagged OBSERVED / STATIC / INFERRED / UNVERIFIED.

Evidence paths in this document are relative to the incremental zip `alcove_media_hud_gestures_evidence_v2.zip` (new files only; v1 zip unchanged).

---

### 1. Sound HUD: Speed (Smooth / Fast / Instant), styles, label/percentage, glyph

#### 1.1 Settings pane facts (OBSERVED, `settings_sound.png`, `ax_list.sh` dump)
Sound pane controls (AX positions): enable toggle (1039,195); Duration slider 1.5 s; Progress style segmented buttons White (743,316) / Accent (860,316) / Decibel (977,316); Show percentage (1039,399, default off); Hide label (1039,441, default off); Speed segmented Smooth (743,485) / Fast (860,485) / Instant (977,485); glyph buttons Show symbol (743,569) / Show device (919,569).
Defaults as found on this install: style **White**, speed **Fast**, glyph **Show device**, percentage off, label shown. (Note: v1's HUD clips were therefore recorded with Speed = Fast.)

#### 1.2 Protocol
For each speed: `set volume output volume 50` (AppleScript, does not show the HUD), then clip `hud_speed_<Speed>.mp4` (8 s): one synthesized NX_KEYTYPE_SOUND_UP press at ~1 s, then 6 presses 75 ms apart ("held key" auto-repeat emulation) at ~3.6 s. Then clip `hud_tween_<Speed>.mp4` (7 s): three single presses 1.5 s apart so the 2nd press lands while the HUD is already fully open (isolates the fill tween from the open animation).
Bar fill is measured per frame as the horizontal extent of pixels with min(R,G,B) > 180 inside x 820–970, y 4–24 (`barfill.py`; per-clip output `hud_speed_<Speed>.barfill.txt`, summary `hud_speed_scan.txt`, `hud_tween_scan.txt`). Notch bbox per frame is in `hud_speed_<Speed>.csv` (`measure2.py`).

#### 1.3 Bar geometry (OBSERVED)
- Filled length at 50 % = 36–38 px; at 87.5 % (after 6 presses of 1/16) = 63–64 px → full track ≈ 73 px (INFERRED: length = 73 px × volume). Track sits in the right wing of the 326 px HUD, label "Sound" + glyph in the left wing (see `shots/hud_style_white_device.png`).
- One key press = +1/16 volume = +4.5–4.6 px of fill.

#### 1.4 Fill tween per speed (OBSERVED, `hud_tween_scan.txt`; press #2 while HUD open)
| Speed | frames of fill change for one press (38 → 43 px) | duration |
|---|---|---|
| Smooth | f189→f194 (`hud_tween_Smooth.mp4`) | 5 frames ≈ 83 ms |
| Fast | f195→f201 (`hud_tween_Fast.mp4`) | 6 frames ≈ 100 ms |
| Instant | f199→f203 (`hud_tween_Instant.mp4`) | 4 frames ≈ 67 ms |

With 6 presses 75 ms apart (`hud_speed_*.barfill.txt`), the fill advanced 1–2 px every frame in all three modes (no plateaus/steps), i.e. each new press retargets the running tween rather than restarting from the old value (INFERRED from the monotonic 38→64 px ramp over 24–26 frames for all three speeds: Smooth f278→f305, Fast f274→f298, Instant f277→f296).
Conclusion (OBSERVED): the Speed setting has **no measurable effect on the volume-bar fill tween** at 60 fps (all ≈ 70–100 ms, within ±1 frame of each other). The fill is a short ease (≈ 5 frames) whatever the setting.

#### 1.5 What Speed does change: the HUD open/close choreography (OBSERVED, `hud_speed_*.csv`)
When a key arrives while Now Playing is compact (216 px), Alcove first shrinks the media capsule to the bare notch (216→144 px) and then grows the HUD (144→326 px); on dismiss it shrinks 326→~150 and regrows to 216. Width-change frames:
| Speed | shrink 216→144 | grow 144→326 | total appear | dismiss 326→152 | regrow →216 |
|---|---|---|---|---|---|
| Smooth | f102–f122 (20 fr, 333 ms) | f124–f158 (34 fr, 567 ms) | 56 fr ≈ 930 ms | f248–f262 (14 fr, 233 ms) | f262–f296 (34 fr, 567 ms) |
| Fast | f102–f118 (16 fr, 267 ms) | f120–f150 (30 fr, 500 ms) | 48 fr ≈ 800 ms | f244–f259 (15 fr, 250 ms) | f263–f291 (28 fr, 467 ms) |
| Instant | f102–f114 (12 fr, 200 ms) | f117–f142 (25 fr, 417 ms) | 40 fr ≈ 667 ms | f237–f257 (20 fr, 333 ms) | f260–f289 (29 fr, 483 ms) |
Appear curves are monotonic with no overshoot (same as v1). INFERRED: Speed scales the HUD panel transition (Smooth ≈ 1.17×, Instant ≈ 0.83× of Fast), not the bar fill. The bar is drawn only once the capsule is ≥ ~250 px wide (first bright bar pixels at f142/f136/f130 respectively, i.e. ~18 frames after growth starts).
Hold: bar visible from f142 to f248 (Smooth) = 106 frames ≈ 1.77 s after the single press; i.e. Duration 1.5 s is counted from when the HUD has finished opening (INFERRED: 1.5 s + ~0.27 s).

#### 1.6 Progress styles / label / percentage / glyph (OBSERVED, screenshots in `shots/`, montage `shots/hud_styles_montage.png`; all captured 0.75 s after one SOUND_UP press from 50 %)
- `hud_style_white_device.png` – White: light-grey filled track (≈ 200/255 grey), dark unfilled track, glyph = **speaker symbol** even with "Show device" selected (no external device on the VM; INFERRED: "Show device" draws the connected output device glyph, e.g. AirPods, and falls back to the speaker symbol). Label "Sound" in white, SF rounded ~12 pt, left of the glyph.
- `hud_style_accent.png` – Accent: filled track in the system accent colour (blue on this VM, (11,36,115)-ish gradient-free solid), everything else identical.
- `hud_style_decibel.png` – Decibel: track replaced by a row of short vertical ticks (bar-graph) that fill left→right; same width.
- `hud_white_showpercentage.png` – Show percentage: numeric "56%" (right-aligned, same font as label) appears right of the bar; bar shortened accordingly.
- `hud_white_hidelabel.png` – Hide label: left "Sound" text removed, glyph stays; bar gains the freed width.
- `hud_white_showpercentage_hidelabel.png` – both.
- `hud_white_showsymbol.png` – Show symbol: identical to Show device on this VM (speaker glyph).
UNVERIFIED: device glyph artwork (AirPods etc.), Decibel style's reaction to muted/0 %.

---

### 2. Now Playing formats Monochrome / Colored / Gradient + colour derivation

#### 2.1 Where the format applies (OBSERVED)
The Format segmented control (Now Playing pane, AX (743|860|977, 401)) only changes the **fill of the expanded player's scrubber/progress bar**. The compact view, the artwork, the waveform tint, title/artist and controls are identical across the three formats.
Evidence: `shots/np_art_formats_montage.png` (columns = Monochrome / Colored / Gradient; top = compact, bottom = expanded, track with blue/green checker artwork) and `shots/np_art_compact_*.png`, `shots/np_art_player_*.png`. Measured scrubber fill colour (mean RGB of the filled part, 8 rows at x 680–720 of the screen):
| Format | filled part | unfilled part |
|---|---|---|
| Monochrome | (44,44,46)…(86,86,89) grey | (26,26,28) |
| Colored | (11,36,115) solid blue | (26,26,28) |
| Gradient | (17,34,72) at the left, lighter toward the playhead (horizontal gradient) | (26,26,28) |
With the placeholder artwork ("Short", no artwork): all three formats render the grey Monochrome bar (`shots/np_player_formats_montage.png`), i.e. no colour is extracted from the grey placeholder.
Settings thumbnails (`settings_livewave_hover.png`) preview the same idea: grey / teal / teal→orange bars.

#### 2.2 Colour derivation (STATIC + OBSERVED)
- STATIC: the binary embeds the Swift package **DominantColors** (classes `_TtC14DominantColors14DominantColors`, `…12AverageColor`, `…14ColorFrequency`, `…11ImageFilter`; strings `DominantColorAlgorithm`, `DominantColorQuality`, `CIKMeans`, `kMeansClustering`, `DominantColor extract colors: `). That package offers k-means / CIKMeans / area-average extraction with a quality setting; `ColorFrequency` is its result type (colour + frequency). Strings `colorSaturateFilter`, `setSaturation:`, `colorWithHue:saturation:brightness:alpha:` are present next to it.
- STATIC: gradient drawing uses `CAGradientLayer` (`So15CAGradientLayerC`), `gradientStops`, `linearGradientFilter`, `smoothLinearGradientFilter`, `usesGradientFill`, `disableGradient`; the format key is `settings.nowPlaying.colorStyle.gradient`.
- OBSERVED: for the blue/green checker artwork the Colored fill is pure blue (11,36,115) – the most frequent cluster of the artwork, not its average (the average of a 50/50 blue/green checker would be teal). The compact waveform and the expanded waveform glyph are tinted with the same hue family in every format (v1 already reported the waveform tint; `np_art_formats_montage.png` shows blue/green bars).
- INFERRED: Colored = darkened primary dominant colour (k-means) of the artwork; Gradient = linear gradient from the primary to a secondary dominant colour; Monochrome = fixed grey. Exact darkening/saturation factors not recovered.

---

### 3. Explicit badge variants and Extra buttons

#### 3.1 Explicit badge (OBSERVED settings only, rendering UNVERIFIED)
Segmented control AX (743|860|977, 316): **None** (⊘ icon), **Explicit** (boxed "E", default), **Format** (a lossless/format glyph). Localisation keys: none found beyond the pane text. The badge is driven by track metadata (explicit flag / audio format); the local test files carry neither, so no badge was rendered in any state. UNVERIFIED: badge glyph size/position. INFERRED from control art: badge is a small rounded square next to the title in the expanded player.

#### 3.2 Expanded player layout reference (OBSERVED, `shots/np_expanded_full_zoom.png`, 3× zoom of a 400×150 crop at x 600)
Row 1 (y≈18–72): artwork 50×50 rounded (x 647–697), title (bold 15 pt) + artist (regular 13 pt grey) from x 720, waveform glyph top-right (x≈925–948).
Row 2 (y≈92): elapsed "0:01" at x 650, scrubber 4 px tall from x 680 to 915, remaining "-0:01" right-aligned to x 950.
Row 3 (y≈135): **extra button** (left slot, x≈670), previous ⏮ (x≈735), play/pause (x≈800, white, larger), next ⏭ (x≈865), **output/volume button** (speaker-on-stand icon, x≈931). Button hit areas ≈ 36×36.

#### 3.3 Extra button behaviour (OBSERVED, Music.app state read back over AppleScript; `shots/xb_*_before/after/after2.png`, montage `shots/xb_buttons_montage.png`)
| Setting | Icon in left slot | Click 1 | Click 2 | Click 3 |
|---|---|---|---|---|
| Favorite | star outline | `favorited of current track` → true; star becomes filled with a rounded highlighted background | → false (outline again) | – |
| Shuffle (default) | shuffle arrows | `shuffle enabled` → true (icon highlighted) | → false | – |
| Repeat | repeat arrows | `song repeat` → **all** | → **one** (icon gains "1") | → **off** |
| Copy | link/copy glyph | clipboard unchanged (local file: no link) | unchanged | – |
STATIC: `menu.media.copyLink` = "Copy Link", `copyLink`, `setLoved:`/`setFavorited:`, `setShuffleEnabled:`/`setShuffleMode:`, `setRepeatMode:`, `pendingMusicLoved`, `pendingMusicRepeatMode`, `pendingMusicShuffleEnabled`, `SpotifyRepeatMode`, `pendingSpotifyLoved` → the button sends the matching Music/Spotify scripting command (the `pending…` keys suggest optimistic UI with a pending flag until the app confirms). INFERRED: Copy copies the Apple Music/Spotify share link of the current item and is a no-op for local files.
Right-slot speaker button (OBSERVED, `shots/xb_rightbutton_after.png`): clicking it expands the panel downward by one row showing a **volume slider** (speaker-low icon, 170 px track, speaker-high icon) under the transport row; the panel grows from 120 px to ≈ 150 px tall; the button gets a rounded highlighted background while the row is open. Clicking again hides it. This is the "Source"/output row the lead listed; "Source" in Settings is a separate section (Automatic ∙ Music / System) that selects which app Alcove follows, not a button.

---

### 4. Quick Peek (media change)

#### 4.1 Trigger conditions (OBSERVED)
- Same-source track changes while the compact Now Playing is on screen do **not** peek (v1).
- Quick Peek fires when a media change happens while the Now Playing activity is **not currently displayed** – e.g. after pause → 3 s idle → collapse to the empty notch, then play a different track. Clip `quickpeek_hidden.mp4` (`.csv`, strips `quickpeek_hidden_strip.png`, `quickpeek_hidden_open_strip.png` (f414–f444 every frame), `quickpeek_hidden_close_strip.png` (f544–f570), `quickpeek_hidden_peekframes.png` (f480, f720 at 3×)).
- Source change (Music → QuickTime) while another activity (Calendar countdown) owned the compact left slot: `quickpeek_qt.mp4` – the left slot flipped from the calendar glyph to the new source's artwork and stayed as long as QuickTime played; it is a source hand-over, not a timed peek (see 4.3).

#### 4.2 Peek geometry and timing (OBSERVED, `quickpeek_hidden.csv` columns width/hmax)
Peek layout: a two-row compact capsule, **width 233–237 px, height 70 px** (vs 216×28 normal compact): row 1 = artwork (28 px) left + waveform right exactly as the compact; row 2 = centred "♪ Title · Artist" in ~11 pt grey/white (long titles are clipped, not marqueed, within the ~2 s).
Peek #1 (play "Short" from the empty notch, command at ≈ f416):
- f419 first motion (≈ 3 frames / 50 ms after the AppleScript `play` returned).
- Width 140→237 peak at f432 then settles 233 at f442; height 28→72 peak at f435, settles 70 by f441 → open ≈ 16–23 frames = **270–380 ms**, overshoot +4 px width (1.7 %), +2 px height (2.9 %) (same spring family as the v1 expansion).
- Hold at 233×70 from f441 to f546 = 105 frames = **1.75 s**; total from first motion to start of collapse f419→f546 = 127 frames = **2.12 s** ≈ Peek duration 2.0 s + open.
- Collapse to 216×28: f546→f565/f571 = 19–25 frames = **320–420 ms**, monotonic, no overshoot. Lands in the normal compact (the activity stays).
Peek #2 (switch to "A Very Long Song…" while compact, command ≈ f665): first motion f668, 216→234 width / 28→70 height by f678–f682 (10–14 frames = 170–230 ms, no overshoot measured), hold to f788 (106 frames = 1.77 s), collapse f788→f807/f812 (19–24 frames = 320–400 ms). Artwork flips to the new art inside the peek (f690–f720 in the strip).
INFERRED timing model: peekDuration (2 s) timer starts at trigger; the hold is 2.0 s minus the open animation; open ≈ Spring(duration 0.4, bounce ~0.3) interrupted at settle; close = v1 collapse curve (~400 ms, no bounce).
Also OBSERVED in the same clip: pause → fade 250 ms → 3.0 s idle → collapse f288–f317 (29 frames = 483 ms) 216→140, matching v1.

#### 4.3 Source hand-over Music → QuickTime (OBSERVED, `quickpeek_qt.mp4`, `quickpeek_qt_leftslot.txt`, strip `quickpeek_qt_strip.png`)
State before: Music playing, Calendar event due in 20 s → compact shows calendar glyph left + "20s" countdown right. QuickTime `play` issued ≈ f100 (±15 frames recorder offset):
- f109–f121 (200 ms): left slot Y-flips calendar glyph → Music artwork (lit width 18→22 px; the peeked artwork is rendered 22 px vs the 18 px glyph).
- f135–f142 (117 ms) flip out to an 8 px edge, f142–f153 (183 ms) flip in to QuickTime's grey placeholder, f160–f175 cross-fade to the final music-note placeholder tint. I.e. two consecutive 300 ms flips: first the current Now Playing (Music) is surfaced, then the new source (QuickTime) replaces it.
- Holds while QuickTime plays; QuickTime `pause` ≈ f410 → f416–f426 (170 ms) flip back to the calendar glyph.
- Capsule width stayed 216 px throughout; only the left slot changed. Right slot (countdown) untouched.

---

### 5. Live waveform (UNVERIFIED – could not be enabled)
- Now Playing pane row "Use live waveform": toggle (AX 1039,484) plus a **crossed-out microphone** button (AX 1015,484) left of it (`settings_livewave_hover.png`). OBSERVED: clicking the toggle leaves it at 0 (`ax_click.sh` reports value 0; `settings_livewave_click.png`), clicking the microphone button opens nothing (no sheet, no System Settings launch, `full_after_unblock.png`), setting the AX value to 1 is refused. No TCC row for `com.henrikruscon.Alcove` under kTCCServiceAudioCapture/Microphone/ScreenCapture was ever created (`sqlite3 TCC.db`), so the app did not even request capture.
- Audio devices present: BlackHole 2ch (installed in v1) and the VM's ParrotAudioPlugin driver; CoreAudio was restarted (`sudo killall coreaudiod`).
- STATIC: capture stack is SimplyCoreAudio + an aggregate device ("Failed creating aggregate device with error: %d.", `SimplyCoreAudio.defaultOutputDeviceChanged`, …) feeding `WaveformSpectrumSession`/`WaveformSpectrumCenter`/`NSWaveformView` (v1 list). INFERRED: the microphone-slash icon indicates the capture backend is unavailable on this VM (no real output device / aggregate creation fails), so the "unblock" flow never starts; on real hardware it should present the macOS audio-capture permission prompt. Bar count, update rate and amplitude mapping of the live spectrum remain UNVERIFIED. The static 5-bar compact waveform behaviour from v1 is unchanged.

---

### 6. Second activity (Calendar) and "cycle activity"

#### 6.1 Getting a second activity (OBSERVED)
Calendar events created with `osascript` into the first writable calendar (`make new event … start date (current date)+480/600`) become a Calendar activity as soon as they are ≤ 15 min away (Alcove had Calendar TCC = allowed; v1's attempt failed only because that event was outside the window at capture time). States seen:
- Playing + upcoming event: **merged compact** 218×29: artwork left with a small red clock badge at its bottom-right corner, right slot = red **countdown ring** (animated arc; `shots/np_compact_two_activities_zoom.png`), which later switches to a red minutes text ("7m", "5m", then seconds "20s"…"8s" in the last 20 s; `cycle_merged_strip.png`, `quickpeek_qt_strip.png`). The waveform is not shown while the countdown occupies the right slot. OBSERVED once (`shots/cyc4_montage.png`): the right slot showed the waveform with no clock badge after a +100 px swipe, see 6.3.
- Expanded while merged: 362–365×120 panel split into Now Playing (left) and the calendar "upcoming" card (right) – `shots/np_expanded_two_activities.png`; during an in-progress event the expanded panel showed the calendar day view instead of the player (`shots/exp_cyc_montage.png`, `xb_*` first run).
- Paused Music + event: after the 3 s idle the compact becomes the pure Calendar activity: red calendar glyph left, countdown ring / "Nm" right (`shots/paused_swipes_montage.png`, `cycle_down_scan.mp4`).

#### 6.2 Vertical swipes with two activities (OBSERVED)
- Localised help strings (STATIC `localizable.txt`): `swipeToCycleActivity.info` = "Swipe down to cycle activity"; `swipeToDismiss.info` = "Swipe vertically to toggle activity".
- Swipe **down** on a single visible activity hides it; swipe **up** (−40 px) on the then-empty notch brings it back (`cycle_down_scan.mp4`/`.csv`: Calendar compact 216 → +25 nothing, +40 dismiss (f248–f267, 232→152, 19 frames ≈ 320 ms), +60 on empty nothing, −40 re-show (f578–f608, 153→233, 30 frames = 500 ms), +90 dismiss again). Thresholds for the Calendar activity: +20 no / +30 yes (`cycle_scan5.txt`), i.e. 25–30 px vs the 35 px measured for Now Playing in v1 (INFERRED: same constant, difference due to the hovered capsule height 33 vs 29 px changing the pixel scale, or a separate reset threshold – low confidence).
- With Now Playing + in-progress event merged, +40 dismisses the whole merged capsule to the empty notch and Now Playing does not return by itself (not on pause/play, not on next track, only after `swipe up` or an app restart) – `cycle_scan4.txt`, `shots/after_next.png`.
- Expanded (two activities): +40/+60/+80/+100 produce no change in content (`shots/exp_cyc_montage.png`, `exp_cyc_*.png`); close still needs >100 px (v1).

#### 6.3 Cycle threshold (PARTIALLY OBSERVED, low confidence)
On the merged compact (Now Playing + upcoming event, Swipe to skip media temporarily OFF so horizontal swipes could not be consumed – horizontal −40…−200 and +40…+200 px never changed anything, `cycle_scan2.txt`, `cycle_scan3.txt`), a downward scan gave (`cycle_scan6.txt`, `shots/cyc4_montage.png`): +50 → unchanged (ring), +70 → right slot shows "7m" text, +100 → right slot shows the **Now Playing waveform and the clock badge disappears** (i.e. the capsule cycled to the Now Playing-only presentation), +140 → dismissed to the empty notch. A 60 fps repeat 1 min later (`cycle_merged.mp4`, strip `cycle_merged_strip.png`, `.csv`) with +70 then +100 showed only the hover growth (216→236→216) and no content change, while the ring→"5m" switch happened on its own 6 s into the clip, before any swipe. Therefore: the ring ↔ minutes alternation is autonomous (not swipe driven); the one waveform appearance after +100 px is the only candidate cycle event. INFERRED cycle threshold: between 70 and 100 px accumulated downward scroll, below the ~105 px needed to close an expanded panel and above the 30–35 px dismiss threshold; the gesture seems to require a pending idle activity (`pendingCycleIdleActivity`, `_cycleSwipeReadyOnRelease` STATIC) and resolves on release. UNVERIFIED: reset threshold, haptic (`_hasTriggeredCycleThresholdHaptic` STATIC), behaviour with a Focus activity.

---

### 7. Settings restored
After the pass: Sound HUD White / Fast / Show device, percentage off, label on; Now Playing Format Monochrome, Extra button Shuffle, Explicit badge "Explicit"; Swipe to skip media back ON; live waveform off (never enabled); Music shuffle off, repeat off; test calendar events deleted.

### 8. Still open
Explicit/Format badge rendering (needs explicit/lossless metadata), live waveform (capture backend unavailable on VM), cycle-activity confirmation with a third activity type (Focus/battery), device glyphs for Show device, Spotify/Apple-Music "Copy Link" result.

### 9. New tools in this pass
- `ax_list.sh` – dumps class/value/position of every control in the frontmost Alcove Settings window.
- `ax_click.sh X Y` – AX-clicks the control at that position (needed because `defaults write` of guessed keys does not change runtime settings).
- `barfill.py clip x0 x1 y0 y1 fa fb [thr]` – per-frame HUD bar extent/brightness.
- Scan logs: `hud_speed_scan.txt`, `hud_tween_scan.txt`, `cycle_scan1..6.txt`.


---

# Part D: calendar, focus, connectivity, lock screen and settings UI

_Source: `children/D_calendar/alcove_calendar_focus_lock_ui.md`. Evidence lives in `children/D_calendar/`._

## Alcove 1.7.7 (199) — Calendar, Focus, Connectivity/Battery, Lock Screen, Onboarding & Settings UI

Session scope: live feature + animation timing for Calendar, Focus, Connectivity/Battery, Lock Screen, onboarding/settings window, contrast outline / progressive blur. Companion to the lead `NOTES.md` (not repeated here).

Legend: **OBSERVED** = seen live on the VM (frame numbers refer to 60 fps `clips/*.mp4`, `fps=60` CFR tick index as produced by `measure2.py`; 1 frame = 16.7 ms). **STATIC** = from the bundle (binary / resources). **INFERRED** = my interpretation. **UNVERIFIED** = VM lacks the hardware/state.

Environment (OBSERVED): macOS 26 VM, 1600x1200 @1x (1 px = 1 pt), no notch, no battery, no Bluetooth audio, no Touch ID, single display. Alcove installed to /Applications, onboarding completed normally, trial active (License pane shows a `2d 23h 22m` countdown and a `Trial` badge in the sidebar; license internals NOT touched). `Force simulated notch` = ON for everything below unless stated. All coordinates are display px with origin top-left; "notch crop" images are `screencapture -R 488,0,624,120` so x_notch = x_display - 488. Alcove's notch panel and its backdrop panel are both 624x320 windows at (488,0) (OBSERVED via AX).

Evidence root (zip): `clips/` (mp4 + per-frame csv + strips), `shots/` (screenshots), `airpods/` (stills/strips from bundled mp4s), `ax_settings_*.txt` (AX geometry dumps of every settings pane), scripts (`measure2.py`, `framediff.py`, `rec_top.sh`, `sched_rec.sh`, `axdump.applescript`, `mkevents.applescript`), `NOTES_mine.md` (raw running notes).

---

### 0. Global notch geometry seen in this session (OBSERVED)

| State | Width x height (px) | Where |
|---|---|---|
| Closed, no activity | 140 x 28 | lead; also `peek_before_1116.csv` f0 (140x28) |
| Idle calendar activity / Focus notification / lock-screen glyph | 216 x 28 (top-flare bbox 220) | `cal_idle_to_event1.csv`, `focus_dnd2.csv`, `lockscreen1.csv` |
| Quick Peek (2-row) | 233 x 70 (flare bbox 238-240) | `cal_idle_to_event1.csv` f16370+, `peek_before_1116.csv` f1541+ |
| Expanded calendar (with events) | settled 362 x 175 at centre row; opaque body 345 wide (x 628..972), top flare 371, peak during open 375-377 | `cal_expand_colors.csv`, `frame_expanded_colors_on.png` |

Expanded panel bottom corners: black extent per row over the last 40 rows goes 229→279 (left) / 571→521 (right) in `expanded_outline1_blur0_finder_zoom.png` ⇒ corner radius ≈ 32-34 px. Quick Peek bottom corners: rows 60-69 narrow 202→218 ⇒ radius ≈ 14 px. Closed notch: lead measured.

---

### 1. Calendar

#### 1.1 Test data (OBSERVED, created with `mkevents.applescript` via Calendar.app)
Calendars: `Calendar` (blue), `Work` (blue), `Personal` (green), `Birthdays` (system, grey). Events on 2026-10-11: `Launch day` (all-day, Personal), `Alex Birthday's 36th Birthday` (Birthdays; the contact already existed - the AppleScript birthday write returned `missing value`, so this row comes from the pre-existing contact), `Design sync` 10:12-10:42 (Calendar), `Budget review` 10:16, `1:1 Sam` 10:27 (overlapping), `Dentist` 11:31-12:31 (Personal), plus future-day events (14, 21 Oct) used for indicator dots.

#### 1.2 Idle calendar activity (OBSERVED)
* Appears only when the next event starts within `Time before event` (default 15 m). Before T-15 m the notch is the plain closed 140x28 (`peek_before_1116.csv` f0-1512). At exactly T-15 m (11:16:00.2 for an 11:31 event; f1513 = 25.2 s after the 11:15:35 recording start) the Quick-Peek-before fires and the notch then stays at the 216x28 activity size.
* Layout (`shots/notch_idle_calendar_5m.png`, `idle_calcolor_on.png`): left lobe = `calendar` SF-style glyph (rose `AlcoveRoseColor` 244,63,94 by default; becomes the event's calendar colour when **Use calendar color** is ON - blue for `Design sync`, green for `Dentist`); right lobe = countdown text (`15m` … `5m`, then seconds `46s` under one minute), ~13 pt semibold, same colour as the glyph. Once the event is running the right lobe becomes a progress **ring** (stroke in the same colour, arc = elapsed fraction; `notch_event_inprogress_ring*.png`).
* Only ONE event is tracked: while `Design sync` was in progress, the overlapping `Budget review` (10:16) and `1:1 Sam` (10:27) produced **no** peek and no width change (`cal_event2_budget.csv`, `cal_event3_sam.csv` constant 216). INFERRED: the activity follows the "current/next" event only; overlapping events are not announced.
* Menu-bar menu during an event (`shots/menubar_menu_during_event.png`): `Open in Calendar`, `Dismiss Event`, separator, `Display ▸`, `Version 1.7.7` (disabled), `Settings… ⌘,`, `Quit Alcove ⌘Q`.

#### 1.3 Expanded view - day + month grid (OBSERVED)
Trigger: click the notch. Two variants were captured:
* Default (`Always show month view` OFF, day has events): left column `SUNDAY` (rose caps, ~11 pt bold, letter-spaced) / `11` (white, ~34 pt bold) / event list rows (`Launch day` all-day with green glyph pill, `Alex Birthday's 36th Birthday` grey, `Design sync 10:12 AM – 10:42 AM` with blue 3 px bar). Right column: header `SUNDAY, 11 OCT` + upcoming events list **instead of** the month grid (`clips/frame_expanded_events.png`, `shots/full_expanded_calendar_events.png`). With no events the right column is the month grid (lead).
* `Always show month view` ON + `Use event indicators` ON + `Use calendar color` ON (`clips/frame_expanded_colors_on.png`, `shots/expanded_outline*_finder_zoom.png`): left column keeps `SUNDAY / 11`, then a `2 all-day events` pill with the two calendars' coloured glyphs, then the next timed event (`Dentist`, green bar, `11:31 AM – 12:31 PM`), then `3 more events` with coloured bars; right column = `OCTOBER` (rose, ~11 pt bold) + weekday letters `M T W T F S S` (grey, Monday-first) + 5 week rows.
  * Grid metrics (in `frame_expanded_colors_on.png`, crop origin 488): day-number rows at y = 43, 62, 82, 102, 122, 142 (**row pitch 20 px**, 7 px glyph height ⇒ ~10 pt bold); columns M..F at x = 325, 346, 367, 388, 409 (**column pitch 21 px**), S S at 430, 451 drawn grey (~55 % white); header `OCTOBER` rows 13-26; weekday letters row 28.
  * Today = filled rose circle (~16 px) with white number; **event indicator** = 2 px dot centred under the day number (seen under 14 and 21, and under 11); with `Use calendar color` the dots/bars take the calendar colour, otherwise rose/white (INFERRED from the toggle names; both ON in the capture).
* Panel body 345 x 175 (x 628..972), flare 371, bottom radius ≈ 32 px, soft outer shadow ≈ 6 px (grey ramp 179→191 at the sides, 155→167 below) — see §6.

#### 1.4 Expanded open/close timing (OBSERVED, `cal_idle_to_event1.csv`, `cal_expand_colors.csv`)
* OPEN (from 216x28 activity): onset f755 → 220 w; f757 244; f760 291; f763 334; f766 362 (target); **peak 375 x 187 at f770 (+13 px / +3.6 % overshoot, 250 ms)**; back to 362 by ~f782 (450 ms); fully still ~f790 (580 ms). Height rises 28→187 over the same 15 frames (12 at the centre column is the flare notch). Earlier run: f2493→peak 377 @ f2508→settle f2521 (470 ms). ⇒ **underdamped spring, ≈ 0.25 s to peak, ≈ 0.45-0.5 s to settle, overshoot 4-6 %** (matches lead's 378/358 = 5.6 %). Lead's `alignmentSpringStiffness/Damping/Mass` STATIC properties are the likely knobs.
* CLOSE (click outside): f3381 → 216 x 28 within ~33 frames (**550 ms**), no overshoot, fast-out (lead: 583-600 ms). Strips: `strip_expand_open.png`, `strip_expand_close.png`.

#### 1.5 Quick Peek (OBSERVED)
Settings → Calendar → Extension: `Quick Peek` ON, `Before event starts` OFF (default), `When event is starting` ON, `Peek duration 4.0 s`, `Use colored calendar indicator` ON.
* **At event start** (`cal_idle_to_event1.mp4` f16356, Design sync 10:12): 216x28 → **233x70 in 12 frames (200 ms)**, no overshoot; held to f16603 (**4.07 s** from onset, i.e. the 4 s "Peek duration" measured from onset incl. the open animation); collapse ≈ 30 frames (500 ms) back to 216x28. Content: row 1 calendar glyph (left) + ring (right); row 2 centred: 3 px bar in the calendar colour, title `Design sync` (white 13 pt), `hourglass` glyph + `29m` remaining (grey). Frame `clips/frame_event1_peek_full.png`, strips `strip_event1_peek_open/close.png`, `shots/event1_peek_t0..t8.png`.
* **Before event starts** (toggle ON; `peek_before_1116.mp4`, fires at T-15 m = 11:16:00.2): from the CLOSED 140x28 → **233x70 in 28 frames (470 ms)** ease-out, no overshoot (f1513: 144x30, f1520: 191x50, f1526: 216x62, f1541: 233x70); held to f1762 (**4.15 s** from onset); closes 233x70 → **216x28** (idle activity, not 140) in 23 frames (**380 ms**). Content (`clips/frame_peek_before_1116.png`, notch-crop coords): calendar glyph green (Personal) x 212-264 y 10-25; countdown `15m` green, right-aligned x 390-414 y 12-21; row 2: green bar x 262-264 y 44-55, `Dentist` white, `clock` glyph + `1h` (event duration) grey x 271-361 y 15-24 relative to row. Sampled green ≈ (90,234,88) ⇒ Apple Calendar "green" calendar colour, not Alcove's palette.
* The 140→233 ramp spends its first 7 frames widening with the height lagging (144x30, 157x36, 172x42, 191x50) — width and height are two springs with similar durations, both settle at f1541.

#### 1.6 Event notification, sounds, hourly chime
* The "event notification" at start IS the Quick Peek at start (above). `Play sound on calendar event` ON by default; `event.caf` STATIC: 1.743 s, mono 44.1 kHz s16. I could not record system audio (no loopback device) ⇒ playback UNVERIFIED by ear; the setting and asset exist.
* Hourly chime: `Play hourly chime` toggled ON at 10:32; `chime.caf` STATIC 4.237 s mono 44.1 kHz. The 11:00 recording was lost (ffmpeg capture hung after a screen-lock; see §4) — rescheduled for 12:00, result appended in §8 if available. Any visual at the top of the hour is therefore UNVERIFIED so far.

#### 1.7 Calendar settings pane (OBSERVED, `ax_settings_Calendar*.txt`, `shots/settings_pane_Calendar*.png`)
Rows (label x = 742, toggle 44x20 at x = 1039, row pitch 42 px): `Calendar` (pane header toggle ON) · `Time before event` slider 340 x 16 (value 15, unit `m`, value shown as a small inline text field) · `Play sound on calendar event` ON (ⓘ) · `Play hourly chime` OFF (ⓘ) · `Use calendar color` OFF · `Disable activity during events` OFF · `Show weather on empty day` OFF (⚠ icon 13x15 → requires Location; weather UNVERIFIED, WeatherKit entitlement STATIC) · `Use event indicators` OFF · `Always show month view` OFF · `Notify when time to leave` OFF (⚠ icon → Location; UNVERIFIED) · section `Calendars`: one row per calendar with a checkbox tinted in the calendar colour (`Calendar`, `Work`, `Personal`, `Birthdays` with gift icon) and a 56x24 popup button; popup menu items (native NSMenu, `shots/settings_pane_Calendar_popup_open.png`): **`Both` (checked), separator, `Live Activity`, `Expanded View`** — i.e. per-calendar routing is Activity / Expanded / Both (not "Notification") · section `Extension`: `Quick Peek` ON, `Before event starts` OFF, `When event is starting` ON, `Peek duration` slider (4.0 s), `Use colored calendar indicator` ON.
Not exercised: `Disable activity during events` (toggle only). Birthdays calendar: shows as a grey row with a gift glyph in the expanded list (OBSERVED).

---

### 2. Focus (OBSERVED unless noted)
Settings → Focus: `Focus` ON · `Duration` slider 340x16 = 5.0 s · `Play sound on sleep focus` OFF (ⓘ; `sleep.caf` STATIC 3.002 s mono 48 kHz s24) · `Replace waveform during focus` OFF · `Hide label` OFF · `Allowed Notifications`: Battery / Connectivity / Display / Sound all ON (`ax_settings_Focus.txt`).
* Trigger used: Control Center → Focus → `Do Not Disturb` (the VM offers only DND; Sleep/Work/Personal modes UNVERIFIED, so per-mode icon/colour UNVERIFIED beyond DND).
* Notification (`shots/focus_dnd_on_notch_zoom.png`): width stays **216x28**; left lobe `moon.fill` glyph in indigo (`AlcoveIndigoColor` 99,102,241 STATIC palette; sampled ≈ purple-indigo), right lobe label **`On`** in the same indigo, ~13 pt semibold. Turning DND off shows the same layout with a grey glyph and **`Off`** (`focus_dnd_off_notch_zoom.png`). `Hide label` ON ⇒ glyph only, right lobe empty, width unchanged (`focus_dnd_on_hidelabel_zoom.png`, `clips/frame_focus_on_hidelabel.png`).
* Timing (`focus_dnd2.csv`, idle calendar activity present): content swap is done by **shrinking to the closed size and re-growing**: 216 → 144 over f556-576 (**333 ms**, ease-out: 211,204,196,189,184,177,172,168,164,161,157,156,153,152,149,148,145,144) then 144 → 216 over f576-604 (**470 ms**, ease-out) while the moon glyph fades in. Off-transition starts at f916 = **6.0 s after onset ⇒ 5.0 s hold after the 0.8 s in-transition**, same shrink/grow back to the calendar content. The DND-off notification at f1882 repeats the identical pattern. Strip `clips/strip_focus_on_hidelabel.png`. No overshoot anywhere in this transition (width never exceeds 216).
* `Replace waveform during focus` needs Now Playing audio ⇒ UNVERIFIED (toggle only).

---

### 3. Connectivity / Battery
* VM has no battery and no Bluetooth audio ⇒ live connectivity and low-battery notifications **UNVERIFIED**. Battery pane is disabled/greyed in the sidebar (no battery) - `shots/settings_pane_Battery.png`.
* Connectivity pane (OBSERVED, `ax_settings_Connectivity.txt`, `settings_pane_Connectivity.png`): `Connectivity` ON · `Duration` 5.0 s · `Low battery warning` ON · `Low battery threshold` slider = 20 % · `Play sound on low battery` ON (`low-battery.caf` STATIC 1.096 s mono 48 kHz) · style segmented picker `3D models` (selected) / `Symbols` as 76x50 preview cards, pitch 88 px.
* STATIC AirPods assets (`/Applications/Alcove.app/Contents/Resources/*.mp4`, 15 files: airpods-3, airpods-4, airpods-pro, airpods-pro-2, airpods-pro-3, airpods-max-{blue,green,midnight,orange,purple,red,silver,sky-blue,space-gray,starlight}): every file **96x96, H.264, 60 fps, 6.000 s, 360 frames, no audio**, alpha-less black background (so they are composited on the black notch). Stills `airpods/<name>_f0.png` and 12-frame strips `airpods/<name>_strip.png`: a slow turntable rotation; first and last frames match ⇒ seamless loop (class `LoopingVideoPlayback` STATIC). INFERRED: shown in the left lobe at ~1x (96 px ≈ 3x the 28 px closed height ⇒ the notch grows for the connectivity card; size UNVERIFIED).
* Sounds STATIC (ffprobe): `event.caf` 1.743 s mono 44.1k s16 · `chime.caf` 4.237 s mono 44.1k s16 · `sleep.caf` 3.002 s mono 48k s24 · `lock.caf` 0.284 s stereo 48k s24 · `unlock.caf` 0.270 s mono 44.1k s16 · `low-battery.caf` 1.096 s mono 48k s16.

---

### 4. Lock Screen
Settings → Lock Screen (OBSERVED, `ax_settings_Lock_Screen.txt`, `settings_pane_Lock_Screen.png`): `Lock Screen` ON · `Keep awake` slider = 0 m · `Show on screen saver` OFF · `Play sound on lock` OFF · `Play sound on unlock` ON · Widgets: `Battery` ON, `Connectivity` ON, `Focus` ON, `Now Playing` ON, `Calendar` OFF · `Material` segmented cards `Glass` (selected) / `Clear` / `Frosted` (76x50 preview cards).
* Live (OBSERVED, lock via ⌃⌘Q keystroke at 10:37:22 and 10:38:02; `clips/lockscreen1.mp4`, `shots/lockscreen_full.png`, `lockscreen_notch_zoom.png`): Alcove's panel **is rendered above the macOS lock screen** (lead's STATIC CGS private-space calls). It shows a white `lock.fill` glyph in the left lobe, nothing on the right. In `lockscreen1.mp4` the lock-screen notch is **216x28** (same as the activity size); 12 s into the second lock the zoom showed a ~140-wide closed notch with the glyph ⇒ INFERRED it may collapse to closed after a few seconds (two observations disagree; UNVERIFIED).
* LOCK transition (`lockscreen1.csv`, `strip_lock1_lock.png`): calendar glyph+ring blur/fade out while width 216 → 144 (f295-315, **350 ms**, ease-out), then lock glyph fades in while width returns 144 → 216 (f316-344, **470 ms**). Same shrink/grow "content swap" pattern as Focus.
* UNLOCK (`strip_lock1_unlock.png`): glyph fades (f745), one frame with no notch (macOS unlock cross-fade, f746), notch re-appears at 134x24 and reaches 140x28 by f765 (~120 ms), holds ~200 ms, then grows 140 → 216 over f777-804 (**450 ms**) with the calendar content fading in.
* Widgets (Battery/Connectivity/Focus/Now Playing/Calendar) had nothing to show on this VM ⇒ widget rendering, Glass/Clear/Frosted materials, screen-saver mode, `lock.caf`/`unlock.caf` playback: **UNVERIFIED**. `pmset displaysleepnow` not used (display sleep would have blanked the capture).
* Operational note: ffmpeg avfoundation captures started while the screen was locked (and later ones while a hung one existed) never produced frames; this cost the 11:00 chime and the first DND recording.

---

### 5. Onboarding & Settings window
#### 5.1 Onboarding (OBSERVED, not reset; captured during the normal first run: `shots/onb*.png`, `clips/onb_accessibility_preview.mp4`, `onb_get_started.mp4`)
Steps as in lead notes. The Accessibility step preview loops a Display↔Sound HUD pill animation (`onb_accessibility_preview_strip.png`). `Get Started` closes the card and the black notch appears top-centre.

#### 5.2 Settings window geometry (OBSERVED via AX, `ax_settings_*.txt`)
* Window **620 x 687**, non-resizable (no resize observed), titlebar-less toolbar 620x66 with traffic lights at x 508/531/554, y +18 (16x16). Opens at (490,131) first time; remembers position. **Hides when Alcove is deactivated** (clicking the desktop makes it vanish; AX still lists it; menu-bar `Settings…` brings it back).
* Window appear animation (`settings_open_from_menu.mp4`): grows from a 640x490 bbox anchored at the window's bottom to the full 620x687 over ~22-33 frames (**≈ 400-550 ms**, ease-out; capture had duplicate frames).
* Sidebar: x 490..~715 (**≈ 225 px incl. divider**), buttons **200 x 38** at x = 502 (12 px inset), vertical pitch **38 px** inside a group, section header text (`Notifications`, `Live Activities`, `Alcove`) 16 px tall at x = 510 with 19 px above / 5 px below; first button at y = 53 from window top. Pane icon 20x20 rounded-square tinted (Battery amber, Connectivity green, Focus indigo, Display purple, Sound pink, Now Playing rose, Calendar rose "11", File Tray grey + `Soon` badge, Lock Screen black, License teal + `Trial` badge, About grey). Selected row: light grey rounded (radius ≈ 10) fill.
* Content: `AXScrollArea` **395 x 637** at x = 715, y = 50; pane title row (icon 17x14 + title 16 px) at y 65; rows: label x = 742 (27 px inset), **toggle 44 x 20** at x = 1039 (27 px right inset), **row pitch 42 px** (16 px label + 26 px padding), grouped in rounded sections (radius ≈ 12) with 1 px separators; section captions (`Idle Activity`, `Behaviour`, `Calendars`, `Extension`, `Allowed Notifications`) 16 px tall at x = 739.
* Sliders (`SliderPicker`): 340 x 16 track at x = 743, value indicator 20x16; the numeric value sits at the right of the label row as an editable text (`15`/`5.0`/`4.0`) with a unit label (`m`, `s`) 9 px wide at x = 1065.
* Segmented preview cards (`SegmentedPicker`): **76 x 50** cards, pitch 88 px (12 px gap), selected card has a 2 px teal (`AccentColor` 45,212,191) rounded border and bold caption; idle-activity cards `None / Playing / Calendar / Duo` with animated/static mini previews (Playing = rose play tile, Calendar = rose "11" tile, Duo = both).
* Popup (`DropdownPicker`): 56 x 24 button, e.g. `Both`; `Display on` row has a `Main display` popup with up/down chevrons (`shots/settings_pane_General.png`).
* Toggle animation (`settings_toggles.mp4`): knob centroid travels 15 px (bright core; 44-20 = 24 px full travel) over **15 frames = 250 ms**, ease-in-out, no overshoot; track tint fades grey → teal in the same window.
* **Pane switch: no transition** - content and sidebar highlight swap in a single frame (`settings_pane_switch.mp4` f208, f1827; `framediff.py`).
* Luminare comparison (for the lead's note that this is a prefix-stripped Luminare fork): Luminare defaults are sidebar width 260, main 390, window 650 wide, sidebar/section corner radius 12, compact button height 34, "regular" 50. Alcove here: content 395 ≈ Luminare 390; sidebar ≈ 225 (narrower than 260); window 620 (vs 650); row height 42 and sidebar button 38 (between Luminare compact 34 and regular 50); section radius ≈ 12 matches. (Luminare numbers from its public README; INFERRED mapping.)
* Fonts (INFERRED from AX glyph heights at 1x): labels 16 px tall ⇒ 13 pt system (SF Pro Text regular); pane title 19 px ⇒ ~16 pt semibold; sidebar section captions 13 pt semibold grey; badges (`Soon`, `Trial`) ~10 pt in a 1 px grey capsule.
* Colours sampled: window material light grey ≈ (236,236,238) over the Tahoe wallpaper (NSVisualEffect), section fill ≈ (246,246,247), toggle-on teal (45,212,191) = `AccentColor`, sidebar selection ≈ (210,210,212).
* Panes captured: General, Battery (disabled), Connectivity, Focus, Display, Sound, Now Playing, Calendar (3 scroll positions), File Tray (Soon), Lock Screen, License (Trial countdown, key field, Recover/Buy), About (icon, version 1.7.7 (199), links) - `shots/settings_pane_*.png`, AX dumps `ax_settings_*.txt`.

#### 5.3 Menu bar
Icon: a monochrome display/notch glyph (menu bar x ≈ 1347 at 1600 wide). Menu: see §1.2 (adds `Open in Calendar` / `Dismiss Event` while a calendar event is active; otherwise `Display ▸`, `Version 1.7.7`, `Settings…`, `Quit Alcove`).

---

### 6. Contrast outline & Progressive blur (General → Behaviour; both ON by default)
Method: closed/idle notch (216x28 calendar activity) captured over solid Black and solid Silver (231,231,231) wallpapers with outline ON/OFF, via three independent paths (`screencapture` CLI, ffmpeg avfoundation frame, harness 1:1 zoom) - `shots/notch_black_outline{0,1}_blur1_zoom.png`, `shots/notch_black_outline1_blur1_late2.png`, `clips/frame_outline{0,1}_black_test.png`, `clips/frame_outline1_silver_test.png`, `shots/notch_silver_outline1_blur1_zoom.png`, plus `clips/frame_dentist_1131.png` (black wallpaper, 10 min after the wallpaper change). Expanded panel over a white Finder list: `shots/expanded_outline1_blur0_finder_zoom.png` vs `expanded_outline0_blur1_finder_zoom.png`.

**Contrast outline (OBSERVED):**
* Over **black**, outline ON: a thin light stroke hugs the capsule everywhere except the flush top edge. Profile (grey level 0-255, zoom + video + screencapture agree within ±1): bottom edge at x = 260/312/380: notch body ends at y = 28, then **y 29 = 24, y 30 = 12-13**, y 31 = 0 ⇒ ≈ 1.5 px wide, peak **24/255 ≈ 9 % white** (rgb (24,24,24) pure grey, so the stroke is white at ~0.09 alpha over black, or `#181818`). Side edge: row 16 x 205 = 15, x 206 = 1; row 22 x 205 = 10, x 206 = 23, x 207 = 4 (stroke follows the curved shoulder; the rounded bottom corner rows 26-30 move the stroke inward 208→215). Nothing on rows 0-4 (top is flush with the display edge). 504 px differ between ON and OFF, bbox x 205-421, y 6-30 (`notch_black_outline1_blur1_zoom.png` vs `_outline0_`).
* Over **black**, outline OFF: hard edge 0→0, identical to a plain black capsule (both video and zoom).
* Over **silver (231)**, outline ON: **no stroke** - the edge is a plain anti-aliased step (row 16: 231,21,0; bottom: 0 → 231) ⇒ the outline is luminance-gated: drawn only when the sampled backdrop under the notch is dark. (STATIC class names `NotchContrastOutlineLuminanceState`, `MaterialLuminanceAggregator`, `WallpaperChangeMonitor`, `CGWindowListCreateImage` match this.)
* **Latency**: captures taken 2-12 s after a wallpaper change or after toggling the switch showed no stroke (`notch_black_outline1_blur1.png`, `_late.png` = zero diff); captures ≥ 20 s later show it. INFERRED: the backdrop luminance is re-sampled on a debounce/timer of roughly 10-20 s (not on the toggle itself).
* On a real notch the stroke would sit around the physical cut-out ⇒ exact appearance there UNVERIFIED.

**Progressive blur (OBSERVED/UNVERIFIED):**
* Closed state: ON vs OFF pixel-identical over both wallpapers (no content under the closed notch to blur).
* Expanded over white Finder window: edge is a hard black→background step in both states; only a ≈ 6 px soft outer shadow (sides 179→191, bottom 155→167) is present in both; with blur ON the bottom ramp is marginally flatter (158,158,158,157,155 vs 155,158,161,164,167) - noise-level. The lead saw "progressive blur visible under panel on window beneath" on first run; I could not reproduce a measurable blur on this VM (STATIC `ProgressiveBlurView`, `VariableBlurEngine`, `NotchBackdropPanel` 624x320 window exist). Blur radius / gradient extent therefore **UNVERIFIED** - may require the 20 s re-sample above or a real-notch display.
* OBSERVED side-result: with `Force simulated notch` OFF on this notchless display the notch rendering disappears entirely (`notch_*_SIMNOTCH_OFF_*.png`).

---

### 7. Animation summary table (OBSERVED)

| Animation | From → to (px) | Onset→peak | Overshoot | Settle (ms) | Curve |
|---|---|---|---|---|---|
| Expanded open | 216x28 → 362x175 | 250 ms (peak 375-377) | +13-15 px (4 %) | 450-580 | underdamped spring |
| Expanded close | 362x175 → 216x28 | - | none | 550 | fast ease-out |
| Quick Peek open (at start) | 216x28 → 233x70 | - | none | 200 | ease-out |
| Quick Peek open (before start) | 140x28 → 233x70 | - | none | 470 | ease-out (2 springs w/h) |
| Quick Peek hold | - | - | - | 4070-4150 from onset | timer 4 s |
| Quick Peek close | 233x70 → 216x28 | - | none | 380-500 | ease-out |
| Focus swap-in | 216 → 144 → 216 | 333 shrink | none | +470 grow (800 total) | ease-out both legs |
| Focus hold | - | - | - | 5000 after settle | timer 5 s |
| Lock swap | 216 → 144 → 216 (lock glyph) | 350 shrink | none | +470 grow | ease-out |
| Unlock | 0 → 140x28 → 216x28 | 120 + 200 hold | none | +450 | ease-out |
| Settings toggle | knob 24 px | - | none | 250 | ease-in-out |
| Settings window appear | scale-in from bottom | - | none | 400-550 | ease-out |
| Settings pane switch | - | - | - | 0 (1 frame) | none |


---

### 8. Late captures

#### 8.1 Quick Peek at start for a non-overlapping event (`Dentist` 11:31, OBSERVED, `clips/dentist_1131.mp4`, wallpaper was solid black so the panel outline is not measurable - content bbox used instead, `frame_dentist_1131.png`, `strip_dentist_peek_open.png`)
* Idle activity content (glyph + countdown) occupies x 704-896, y 8-21 before the event.
* Peek onset f1748 (= 11:31:00.0 ± 0.1 s): row-2 content appears and grows y 24 → 55 over f1748-1755 (**7 frames ≈ 120 ms** for the content fade/slide; the panel grow itself is ~200 ms as in §1.5), hold until f1991, row 2 gone by f1994 ⇒ **4.05 s from onset to collapse start**, identical to the 10:12 event. Content: green calendar glyph + ring (right), `Dentist` + `hourglass 1h` row.

---

### 9. Not covered / UNVERIFIED summary
* Battery, Connectivity (AirPods) live notifications, lock-screen widgets + Glass/Clear/Frosted materials, screen-saver mode, lock/unlock/event/chime/sleep sound playback: no hardware / no audio loopback on the VM (settings-level documentation only; another session covers the hardware paths).
* Focus modes other than Do Not Disturb (Sleep/Work/Personal icons & colours), `Replace waveform during focus` (needs Now Playing audio), `Play sound on sleep focus`.
* Calendar: `Show weather on empty day`, `Notify when time to leave` (Location Services unavailable on the VM; both rows show a warning icon), `Disable activity during events` (not exercised), `Use calendar color` vs default colours in the expanded view were captured only with the toggle ON.
* Progressive blur radius/extent (no measurable difference reproduced, see §6); contrast outline over a real notch.
* Onboarding was not re-run (reset not allowed); only the first-run captures from this session exist.
* Exact font faces/weights are inferred from glyph heights (no font introspection).

#### 8.2 Hourly chime at 12:00 (OBSERVED, `clips/chime_1200.mp4`, 11:59:30 → 12:01:01, `Play hourly chime` ON, Dentist event in progress so the idle activity showed glyph + ring)
* Notch bbox constant **216 x 29** for the whole clip (`chime_1200.csv`: only a 1 px jitter at f24-25). Region change detector on the notch interior (`framediff.py`, threshold 1.0): `frames 5399;` - i.e. **no visual change at the top of the hour**; the chime is audio-only (`chime.caf` 4.24 s). Audio playback itself UNVERIFIED (no loopback capture). INFERRED: chime fires at the exact hour and the ring-progress frames are the only content updates.


---

# Part E: hardware-dependent features

_Source: `children/E_hw/alcove_hardware_re.md`. Evidence lives in `children/E_hw/`._

## Alcove 1.7.7 (199): hardware-dependent behavior

### Scope, confidence, and how to use this report

**OBSERVED:** This investigation used Alcove 1.7.7, build 199, on macOS 26.6.2 (25G83), arm64, with one 1600×1200, 1× virtual display. The analyzed arm64 executable SHA-256 is `14520b5dd7b91b6e248122194dc206634173fb014d105a308d824974d4f653ec`. Evidence: `ev/logs/environment.txt`.

**OBSERVED:** The VM has no physical notch, internal battery, paired AirPods, keyboard illumination hardware, or second display. Onboarding and ordinary Accessibility permission were completed; the application displayed its normal simulated notch. No executable modification, licensing bypass, or activation reverse engineering was performed. No external posts or repository changes were made.

**STATIC** means directly recovered from executable instructions, metadata, imports, or resources. Addresses are unslid arm64 virtual addresses, not file offsets. **OBSERVED** means a recorded local result, or an explicitly identified observation supplied by the lead. **INFERRED** means an interpretation that goes beyond the direct evidence. **UNVERIFIED** identifies a missing test or unresolved interpretation. A status at the beginning of a paragraph or table row applies to that entire paragraph or row. Function names assigned to stripped functions are descriptive, not recovered source declarations.

**INFERRED:** Confidence is 8/10 for the core geometry, model classifier, battery APIs, and event swallowing; lower for exact end-to-end presentation timing on unavailable hardware. This is an implementation-oriented evidence report, **not a claim of complete pixel/timing equivalence**. Unknowns are retained rather than filled with conventional macOS behavior.

#### Highest-value conclusions

| Status | Finding | Evidence |
|---|---|---|
| STATIC | Real notch width is screen width minus the widths of both auxiliary top areas; height is safe-area top. | `ev/dis/f_notchgeom_100238df8.txt` |
| STATIC / OBSERVED | Simulated geometry is 140 points wide; visible-menu-bar height minus 1 gives 29 points here. Its full dark shoulder bounds are 144×29 pixels. | geometry function; `ev/logs/screen_geometry.json`, `screenshot_bboxes.json` |
| STATIC | AirPods model identity comes from a CoreAudio model UID, not a recovered Apple BLE advertisement decoder. Battery values come from private IOBluetooth selectors. | `f_bt_10031b0c8.txt`, `coreaudio_model_property.txt`, `f_bt_10031a974.txt` |
| STATIC | Successful media-key handling returns a null event to suppress downstream handling. This is positively established, not merely implied by an active tap. | `f_mediakey_100136eac.txt`, 0x100137194–0x100137198 |
| STATIC | Fine adjustment is **Shift + Option together**, mask 0xa0000. Brightness fallback increments are 1/16 and 1/64. | 0x100137140–0x10013714c; `f_bright_increment_100122f0c.txt` |
| STATIC / OBSERVED | The Mac-battery threshold initializer is 10.0. The supplied live 20% setting belongs to **Connectivity**, not the disabled Battery pane. | `f_default_lowBatteryThreshold.txt`; lead `settings_ax/general.txt`, lines 5–6 |
| OBSERVED | Synthetic `screenLockUIIsShown` widened the top notch; raw `screenIsLocked` alone did not visibly show lock widgets. | `ev/clips/hardware_matrix.mp4`; matching screenshots |
| UNVERIFIED | No brightness or volume HUD appeared from the synthetic key run. No physical-device result or successful native OSD suppression is claimed. | runtime matrix and clip |

### 1. Notch detection, geometry, and display targeting

#### Source → parsing → state

**STATIC:** The real-notch predicate checks `NSScreen.safeAreaInsets.top > 0`, non-nil `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`, and nonempty rectangles for both. Examples are 0x100238df8, 0x1001ebcd8, 0x1001109f0, and 0x10034bf7c. Do not replace this with a machine-model-name test or `CGDisplayIsBuiltin` alone. Evidence: `ev/dis/f_notchgeom_100238df8.txt`, `f_notchgeom_1001ebcd8.txt`, `f_notchgeom_1001109f0.txt`, `f_displaylist_10034bf7c.txt`.

**STATIC:** Geometry function 0x100238df8 receives a screen and a fallback/simulation flag, returning four floating-point values. Caller 0x100233518 stores them into the `NotchController` fields `_notchWidth`, `_notchHeight`, `_notchExpandedWidth`, `_notchExpandedHeight`; its explicit field relocations establish the return ordering. It compares old/new values and emits observable mutations only on differences. Evidence: `ev/dis/f_notchgeom_caller_100233518.txt`, particularly 0x1002335a4 onward.

#### Exact base formulas

**STATIC:** Let `W = screen.frame.width`, `L/R = auxiliaryTopLeftArea/RightArea.width`, `S = safeAreaInsets.top`, and `M = frame.maxY - visibleFrame.maxY`. These are AppKit logical points, not physical Retina pixels.

| Status | Branch | Closed width | Closed height | Base expanded width | Base expanded height |
|---|---|---:|---:|---:|---:|
| STATIC | Valid real-notch screen | `W-L-R` | `S` | `max(W-L-R+160,345)` | `max(S+142,175)` |
| STATIC | No real notch, simulation enabled | 140 | `M-1` when top menu-bar difference is positive; otherwise 24 | 345 | 175 |
| STATIC | No real notch, compact fallback | 74 | `M-5.5` when top menu-bar difference is positive; otherwise 19.5 | 321 | 175 |

**STATIC:** Real-branch arithmetic is at 0x100239018–0x10023906c. The 140 constant is present as the assembled floating-point value `0x4061800000000000`; searching only for a standalone 64-bit literal missed it in early scratch analysis. The compact 74-point size must not be confused with the forced simulated notch.

**OBSERVED:** On this VM, frame is `(0,0,1600,1200)`, visible frame `(0,82,1600,1088)`, safe top 0, scale 1. Thus `M=30`, predicting 140×29. In `ev/shots/ready.png`, thresholding the top-center black region gives inclusive bounds x=728…871, y=0…28: **144×29 including shoulders/antialiasing**, centered at x=799.5. The nominal central width and full shoulder bounds are different measurements. Evidence: `ev/logs/screen_geometry.json`, `screenshot_bboxes.json`.

**INFERRED:** Use these as base metrics, not fixed final content bounds. Calendar, notifications, outline, cutout shoulders, and animation can change the rendered width. The prior lead report measured an expanded Calendar width around 358 pixels even though this base function supplies 345. Source: supplied `NOTES.md` and static report.

#### Adjusted width/height and additional offsets

**STATIC:** `notchAdjustedWidth` and `notchAdjustedHeight` are Defaults-backed settings with zero initial values and are referenced by the notch controller and views. The core geometry-return/store path above does not add them. The earlier static report's interpretation “zero means use detected size” is a useful hypothesis, not enough to establish whether nonzero values are offsets, overrides, or branch-specific tuning.

**OBSERVED:** Controlled preference experiments set width=20/height=0 and width=0/height=10, restarting Alcove between changes. The simulated closed notch stayed at dark bounds 144×29 in both screenshots. Both values were restored to zero. Evidence: `ev/scripts/runtime_matrix.py`, `ev/logs/runtime_matrix.json`, `ev/shots/adjusted_width20.png`, `adjusted_height10.png`, `adjusted_restored.png`.

**UNVERIFIED:** Those experiments do **not** prove the settings are ignored globally. Their exact consumer formula, real-notch applicability, and any constraints on accepted values remain unresolved. Do not implement `closedWidth += adjustedWidth` as a recovered fact.

**STATIC:** Separate layout getters contain 74, 28, and 12-point quantities. 0x10021b0f4 can yield 74, 46 (=74−28), 62 (=74−12), or 0 depending on state and real-notch checks. 0x10021b394 contains another 74/12 adjustment. They are conditional content-layout contributions, not the 140-point simulated size. Evidence: `ev/dis/f_geom_10021b0f4.txt`, `f_geom_10021b394.txt`.

#### Multiple displays and screen changes

**STATIC:** `DisplayType` has `builtInDisplay`, `mainScreen`, `allDisplays`, `specificDisplay`. Screen IDs are obtained using `NSScreen.deviceDescription` and display UUID-related helpers; 0x10021b83c selects a target screen from available screens using stored display selection. The chooser list builder 0x10034bf7c uses `CGDisplayIsBuiltin`, the real-notch predicate, and backlight probes, and selects symbols including `macbook`, `laptopcomputer`, and `display`. Evidence: `ev/dis/fieldmd_hw.txt`, `f_screenchooser_10021b83c.txt`, `f_display_uuid_10020beec.txt`, `f_display_uuid2_10023f6e0.txt`, `f_displaylist_10034bf7c.txt`.

**STATIC:** Backlight-capability probing tries `AppleARMBacklight`, `AppleBacklightDisplay`, then a service named `backlight` at 0x10020cd28 and an inlined chooser path. `NSApplicationDidChangeScreenParametersNotification` is subscribed to in the lock/display integration at 0x10034fec4. Evidence: corresponding disassembly and `ev/dis/relocs_lock_nc_names.txt`.

**OBSERVED, lead:** General settings offered Main display; menu-bar menu offered a Display submenu. **UNVERIFIED:** actual all-display window multiplicity, hotplug fallback when a selected UUID disappears, mixed-scale geometry, and display migration animation. Only one screen was present.

#### Requested model-size predictions

| Status | Machine | Defensible prediction |
|---|---|---|
| UNVERIFIED | 14-inch MacBook Pro | `(frame.width-leftAux.width-rightAux.width) × safeAreaInsets.top` on the actual selected display mode |
| UNVERIFIED | 16-inch MacBook Pro | Same formula; no model-specific literal recovered |
| UNVERIFIED | 13-inch MacBook Air with notch | Same formula; requires actual auxiliary rectangles and safe inset |
| UNVERIFIED | 15-inch MacBook Air with notch | Same formula; requires actual auxiliary rectangles and safe inset |

**INFERRED:** Model names/diagonal sizes alone do not provide the API inputs, especially under scaled display modes. Consequently a numeric table would be invented. For illustration only, an API result of width gap 220 and safe top 32 would yield 220×32 closed, 380×175 base expanded; that is **not** a measured or asserted value for any listed model.

**STATIC / UNVERIFIED:** Geometry refresh is change-driven; no geometry-specific sound was located. Common notch animation/shape behavior is in the supplied static report, not independently assigned to each hardware presentation here.

### 2. Mac battery and Low Power Mode

#### Data sources and keys

**STATIC:** Helper open at 0x1001527c0 matches `AppleSmartBattery`, opens the IOKit service, and creates an `IOPSNotificationCreateRunLoopSource` installed on the current run loop in default mode. Failure has an explicit “Opening (AppleSmartBattery) service failed” path. The state reader at 0x100152488 calls `IOPSCopyPowerSourcesInfo`, `IOPSCopyPowerSourcesList`, then `IOPSGetPowerSourceDescription` for each source, filtering `Type == InternalBattery`. Evidence: `f_battery_helper_open_1001527c0.txt`, `f_battery_iops_100152488.txt`.

| Status | Key | Source / purpose / address |
|---|---|---|
| STATIC | `Type`, `InternalBattery` | IOPS source filtering at 0x100152488 |
| STATIC | `Current Capacity` | IOPS dictionary, key-index 7 requested by 0x1001522ac |
| STATIC | `ExternalConnected` | AppleSmartBattery registry, 0x1001521f0 and 0x10012de20; negated to derive on-battery state |
| STATIC | `IsCharging` | Registry boolean, 0x100151f84 |
| STATIC | `CurrentCapacity`, `MaxCapacity` | Registry capacity state, 0x100151f84 |
| STATIC | `FullyCharged` | Recovered in helper state/key paths around 0x1001528c8 |
| STATIC | `AvgTimeToEmpty`, `AvgTimeToFull` | Registry remaining-time integer readers, 0x10015238c/0x1001523a0 → 0x1001523b4 |
| UNVERIFIED | `Is Charging`, `Power Source State` | Requested candidate IOPS keys, but no specific read was established in this analysis. Do not substitute these spaced keys for the positively identified registry keys. |

**STATIC:** IOPS and registry key spellings differ: `Current Capacity` versus `CurrentCapacity`; `IsCharging` is not the same string as `Is Charging`. Evidence: `ev/dis/f_bat_get_1001522ac.txt`, `f_bat_regprops_100151f84.txt`, `f_batteryhelper_state_1001528c8.txt`.

#### Parsing, state, edge triggers, and time

**STATIC:** Battery refresh 0x10012e4f8 reads connection and capacity state, normalizes reported integer level with division by 100.0, and stores `_batteryLevel`. Unavailable level falls back to zero in the decoded path. It stores `_wasOnBattery` from `!ExternalConnected` and compares level with the configured threshold divided by 100. Comparisons occur at 0x10012e7d0 and 0x10012e9e0. Evidence: `f_battery_10012e4f8.txt`.

**STATIC:** State fields include `_hasPassedThreshold`, `_hasRecentlyChangedPowerSource`, `_isLowPowerModeEnabled`, `_remainingTime`, `_warnOnLowBattery`, `_notifyOnLowPowerMode`, `_playSoundOnLowBattery`, `_allowBatteryWhenFocused`, and `_allowBatteryWhenLocked`. At 0x10012f148 the manager subscribes to custom notification `powersourcechanged` and `NSProcessInfoPowerStateDidChangeNotification`; the latter is received on the main run loop. The low-power handler 0x10012f82c reads `NSProcessInfo.isLowPowerModeEnabled`, compares prior state, and schedules main-actor work. Evidence: `fieldmd_hw.txt`, `f_battery_10012f148.txt`, `f_battery_lowpower_10012f82c.txt`.

**INFERRED:** `_hasPassedThreshold` provides threshold-crossing latching rather than repeated warning for every percentage sample. `_hasRecentlyChangedPowerSource` provides a guard around plugging/unplugging. **UNVERIFIED:** exact equality edge, re-arm rules, ordering of simultaneous source/low-power changes, and complete branch-to-notification mapping. A clone should keep these as distinct state inputs rather than one generic “battery changed” event.

**STATIC:** Async continuations contain waits of 0.5 seconds at 0x10012fc88 and 0.2 seconds at 0x100130498–0x1001304a8. **UNVERIFIED:** which full plug/unplug/low-power edge each wait belongs to; they are not proven global debounce durations. Evidence: `f_battery_timer_10012fc6c.txt`, `f_battery_timer_10013047c.txt`.

#### Threshold discrepancy, UI, sound

**STATIC:** The default-key initializer at 0x1003368cc stores `0x4024000000000000` = **Double 10.0** at 0x100336940/0x10033695c for `lowBatteryThreshold`.

**OBSERVED, lead:** `settings_ax/general.txt` line 5 explicitly says the Battery pane is disabled because there is no battery; line 6 reports **Connectivity** low-battery threshold 20%. **UNVERIFIED:** the assignment's “Mac battery default 20%” is not supported by that live artifact. The binary default is 10; a physical Mac's displayed or migrated preference is untested. This resolves the apparent evidence mix-up without silently changing the request's assumption.

**STATIC:** Localized battery strings are `notification.battery.charging → Charging`, `.lowBattery → Low Battery`, `.lowPower → Low Power`, referenced in the notification view at 0x1002a116c. The battery display duration default is 5 seconds in the supplied static defaults analysis. Remaining-time logic is refreshed via 0x10012ee58. Evidence: `localizable.txt`, `f_battery_notif_view_1002a116c.txt`, `f_battery_10012ee58.txt`.

**STATIC:** BatteryManager init 0x10012e1ec preloads `low-power.caf`. ConnectivityManager, separately, preloads `low-battery.caf` at 0x10030e3c8. The latter must not automatically be assigned to Mac-battery alerts. Sound playback references occur in the BatteryManager 0x10013132c region and ConnectivityManager 0x100315408 region. Evidence: sound-preload and manager disassembly; audio metadata in §7.

**UNVERIFIED:** exact separate “plugged”, “unplugged”, and charging UI state transitions, all icon/color variants, low-power-on versus low-power-off presentation, animation curves, and sound trigger conditions are not fully recovered. Only the above strings, state fields, and paths are established.

**OBSERVED:** `sudo -n pmset -a lowpowermode 1` exited zero but printed **“LowPowerMode not supported on AC Power”**. The subsequent `… lowpowermode 0` succeeded; battery-only low-power configuration was also reset to zero. No Alcove battery/low-power overlay appeared. Exit zero here does **not** mean Low Power Mode engaged. Evidence: runtime matrix t=9.207/11.369/13.526 and screenshots `lowpower_on/off.png`.

### 3. AirPods, Bluetooth, and audio routes

#### Source and model parsing

**STATIC:** CoreBluetooth delegate metadata exists, but only state-update implementations were found; `didDiscoverPeripheral` occurs in protocol metadata rather than a recovered discovery implementation. CoreBluetooth construction in onboarding at 0x10010a1b4 supports permission/power-state handling. **UNVERIFIED:** no direct Apple manufacturer-data decoder for company 0x004C/type 0x07, or `kCBAdvDataManufacturerData` parsing, was found. Absence from this analysis is not a universal proof of absence.

**STATIC:** The audio-device classifier 0x10031b0c8 calls CoreAudio property getter 0x1003c48b0. Its property tuple at 0x100475b50 decodes to selector **`muid`**, scope **`glob`** (model UID/global). It splits the resulting string on ASCII space and uses its first component. This is the source of strings such as `200e`, not a recovered `IOBluetoothDevice.productID` selector. Evidence: `f_helper_1003c48b0.txt`, `coreaudio_model_property.txt`, `f_coreaudio_modelgetter_1003c4994.txt`, `f_bt_10031b0c8.txt`.

**STATIC:** Device matching separately enumerates `IOBluetoothDevice.pairedDevices`, checks `isConnected`, and compares lowercased normalized `addressString` values against the audio device. CoreAudio route handling also distinguishes `BuiltInHeadphoneOutput` and `BuiltInSpeakerDevice`. Evidence: 0x10031a62c and 0x100312328, respective disassembly.

#### Exact model classifier and resource correspondence

**STATIC:** 0x10031a2c4 compares the following lowercase four-character strings; its result packs model tag in the high byte and state/color payload in the low byte. Unknown model returns 0xff00. The three arithmetic string constructions are decoded directly: `packed("202d")+0xfe0000="200e"`; `packed("2014")+0x10000="2024"`; `packed("200f")+0x10000="201f"`.

| Status | Model UID first component | Tag / model | Corresponding bundled video |
|---|---|---|---|
| STATIC | `2002` | 0, AirPods | No dedicated first-generation MP4 found |
| STATIC | `200f` | 1, AirPods 2 | No dedicated second-generation MP4 found |
| STATIC | `2013` | 2, AirPods 3 | `airpods-3.mp4` |
| STATIC | `201b`, `2019` | 3, AirPods 4 | `airpods-4.mp4` |
| STATIC | `200e` | 4, AirPods Pro | `airpods-pro.mp4` |
| STATIC | `2014`, `2024` | 5, AirPods Pro 2 | `airpods-pro-2.mp4` |
| STATIC | `2027` | 6, AirPods Pro 3 | `airpods-pro-3.mp4` |
| STATIC | `200a` | 7, AirPods Max | Color-specific `airpods-max-*.mp4` |
| STATIC | `201f`, `202d` | 8, AirPods Max 2 | Color-specific `airpods-max-*.mp4` |

**INFERRED:** Model names follow the recovered enum ordering and resource names; the table's resource column identifies the corresponding existing asset, not a proof that every UI state uses that asset. **UNVERIFIED:** first/second-generation AirPods fallback artwork and exact left-only/right-only resource reuse. Evidence: `f_bt_namemap_10031a2c4.txt`, `namemap_condensed.txt`, `fieldmd_hw.txt`, `logs/media_inventory.json`.

**STATIC:** Private `colorID` is read at 0x10031b1ac and 0x1003149a4. Mapper 0x10031a290 masks to six bits, subtracts 2, bounds-checks 0…20, and looks up table 0x1004715b6. An unavailable-value high byte of 0x100, or out-of-range value, returns enum zero.

| Status | Masked color ID | Color enum / asset suffix |
|---|---:|---|
| STATIC | 2 | red |
| STATIC | 3 | skyBlue / sky-blue |
| STATIC | 4…15 | spaceGray / space-gray |
| STATIC | 16 | silver |
| STATIC | 17 | green |
| STATIC | 18 | midnight |
| STATIC | 19 | starlight |
| STATIC | 20 | blue |
| STATIC | 21 | orange |
| STATIC | 22 | purple |
| STATIC | missing/out-of-range | spaceGray / space-gray |

**STATIC:** All ten Max-color videos actually exist; an early scratch note claiming only five existed was incorrect. The five newer-color references in 0x100108c18 are only part of the asset set. All fifteen AirPods MP4 resources are H.264, 96×96, 60fps, 360 frames, six seconds, with no audio stream. A 32×32 point frame occurs in the Max view at 0x100108c18. Evidence: `f_airpodsmax_view_100108c18.txt`, `f_maxcolor_10031a290.txt`, `maxcolor_table.txt`, `media_inventory.json`.

#### Battery state and presentation

**STATIC:** 0x10031a974 invokes private `batteryPercentLeft`, `batteryPercentRight`, and `batteryPercentSingle`. It validates integer percentages against bounds around 0…100 (0x65 exclusive upper bound), and carries separate availability/sentinel state. `AirPodsState` declares `leftOnly`, `rightOnly`, `both`; the decoded selection uses 0,1,2 respectively and an additional no-left/right path. **UNVERIFIED:** `batteryPercentSingle` must not be described as the case battery: no explicit case-battery selector or case-specific mapping was recovered.

**STATIC:** Connectivity state includes low-device-battery threshold/warning and percentage-hiding controls. 0x100314808 refreshes device state and contains `low-battery` playback. **OBSERVED, lead:** Connectivity settings: enabled, duration 5 seconds, low-battery warning on, threshold 20%, low-battery sound on, and choice of 3D models versus symbols. Evidence: `f_bt_100314808.txt`, lead settings line 6.

**INFERRED:** Route/device changes drive connect presentation, with paired-device data providing model, color, and battery payload. **UNVERIFIED:** exact connect/disconnect debounce, disconnection wording, simultaneous-device prioritization, battery polling cadence, animation start phase, and whether low-battery alerts replay after reconnect. No Bluetooth device was available, so no live device behavior is claimed.

#### Other device types

**STATIC:** Audio-class fallback at 0x10031b210 requires major class 4. Its table index is **minor−1** (not minor), in range 0…14. Minor 1/2/6 map to payload 5, minor 15 to payload 0, other table entries to 17; fallback result uses high-byte category 9. Do not confuse these payloads with the AirPods model tags above. Evidence: `f_bt_10031b0c8.txt`, `bt_minorclass_table.txt`.

**STATIC:** `VirtualDevice` metadata includes MacBook/MacStudio/iMac/MacMini/MacPro, headphones, HomePod/mini/2, pair/group variants, EarPods, Studio Display and Pro Display variants. HomePod audio-route records hold UID/name/groupID/subtype/modelID/configuredClusterSize/observedAt. Model checks include `AudioAccessory1,1`, `1,2`, `1,3`, `5,1`, `6,1`; there is also a lowercased `homepod` name test. Evidence: `fieldmd_hw.txt`, `f_bt_100317100.txt`, `f_bt_10031b7cc.txt`.

**UNVERIFIED:** Generic keyboard/mouse connect-notification support was not established. HID-keyboard detection elsewhere belongs to media-key routing; it is not evidence that Connectivity shows keyboard/mouse notifications. Exact SF Symbol mapping for every generic audio subtype remains unresolved.

### 4. Lock screen and screen saver

#### Sources, state, debounce

**STATIC:** LockManager initializer 0x10034f410 installs subscriptions through 0x10034fec4 to:

- `com.apple.screensaver.didstart` / `.didstop`
- `com.apple.screenLockUIIsShown` / `com.apple.screenLockUIIsHidden`
- `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`
- `NSWorkspaceScreensDidSleepNotification` / `NSWorkspaceScreensDidWakeNotification`
- `NSApplicationDidChangeScreenParametersNotification`

**STATIC:** Startup/resynchronization calls `CGSessionCopyCurrentDictionary` at 0x10035ccc8, extracts a value and attempts Bool conversion, returning false on the decoded unavailable path. The dictionary key is produced by another initializer; its exact cleartext was not recovered here. **UNVERIFIED:** a separate `NSWorkspace.sessionDidResignActive` observer is not established by the above evidence. See `f_lock_subs_10034fec4.txt`, `relocs_lock_nc_names.txt`, `f_lockdictionary_10035ccc8.txt`.

**STATIC:** State separates `_isLocked`, `_isVisible`, `_isSleeping`, `_isAwake`; tasks include lockDebounce, unlockDebounce, screensaverPresentationTask, hideDebounce, and sleepTask. Handler 0x100353c68 cancels prior work and starts main-actor tasks. It uses `withAnimation(.easeOut(duration:0.15))` at 0x100354438–0x100354454. Login preferences are fetched asynchronously via `fetchLoginPreferences()` on a checked continuation path at 0x10035d4c8. Metadata includes hasClock/hasMessage/hasAvatar/userAccountCount and wallpaper-luminance state. Evidence: lock-handler/task dumps and field metadata.

**UNVERIFIED:** cancellation is recovered, but exact lock versus unlock debounce wait, widget ordering, and all state-transition predicates are not. The 0.15-second animation is one handler transition, not a proven duration for all lock-screen motion.

#### Window/space mechanism and widgets

**STATIC, prior report plus current selector evidence:** LockPanel init 0x1000efe04 uses a clear nonopaque, shadowless NSPanel, `canBecomeVisibleWithoutLogin=true`, shielding-window level, no native window animation, and collection behavior 0x151 (all spaces, stationary, ignores cycle, fullscreen auxiliary). Related private space support creates/shows a CGS space at 0x100128d0c, moves windows with CGSAdd/RemoveWindowsFromSpaces at 0x100128f18, and destroys the space at 0x100128e24. Supplied `alcove_static_re.md` §4 gives the shared window contract; `ev/dis/x_stubs.txt` records current selector call sites.

**INFERRED:** The combination of private spaces, high window level, and visible-without-login makes presentation over login/lock UI possible. **UNVERIFIED:** this was not tested over a genuine authenticated lock session; posting an identically named distributed notification is not equivalent to locking the session.

**OBSERVED, lead:** Lock settings expose Battery, Connectivity, Focus, Now Playing widgets enabled; Calendar disabled; Glass/Clear/Frosted material choices; show volume control off; offset tuning 0 pixels; idle duration 10 minutes; show-on-screen-saver off; keep-awake 0 minutes; lock sound off and unlock sound on. Evidence: lead settings line 12.

**STATIC:** Battery-widget functions include 0x1002120cc and IOPS readers. Wallpaper/login integration contains `LoginWindowContainerView`, `WallpaperWindow`, `WallpaperManager.didChangeNotification`, `WallpaperChangeMonitor`, and `_isWallpaperNearlyWhite`. **UNVERIFIED:** exact per-widget frame, spacing, alignment to clock/avatar, material blur/vibrancy parameters, and idle animation are not recovered quantitatively. These settings are not enough to assert a pixel-accurate layout. The 10-minute lock widget idle setting must not be confused with the separate notch `idleDuration=3 seconds`.

#### Keep-awake and sounds

**STATIC:** 0x100358530 clears prior assertions using 0x100358a78, reads keep-awake duration, and on a positive value creates three assertions: `NoIdleSleepAssertion`, `NoDisplaySleepAssertion`, `PreventUserIdleDisplaySleep`, level 255. IDs are stored separately and released through `IOPMAssertionRelease`. A sleepTask is created. **INFERRED:** that task supplies expiry cleanup after the configured minute duration; exact task conversion/release ordering was not fully traced. Evidence: `f_lock_assertions_100358530.txt`, `f_lock_release_assertions_100358a78.txt`.

**STATIC:** LockManager preloads `lock.caf` and `unlock.caf` at 0x10034fa14/0x10034fa34. Durations are in §7. **UNVERIFIED:** recorded runtime clip has no audio track; audible playback was not validated.

#### Actual runtime results

**OBSERVED:** All six distributed notification posts returned success. `screenIsLocked` alone produced no visible widget transition in the sampled screenshot. `screenLockUIIsShown` widened the black top-center region to x=689…910, y=0…28 (**222×29**); `screenLockUIIsHidden` restored 144×29. No complete lock-widget dashboard was shown. Evidence: `synthetic_locked.png`, `synthetic_lockui.png`, `synthetic_unlockui.png` (other screenshots in the archive are JPEG re-encodes of the PNG originals; bounds were measured on the PNGs), clip, matrix t=13.546…20.051.

**OBSERVED:** The sampled synthetic screensaver-start screenshot no longer contains the black top notch; the stop screenshot contains it again. `open -a ScreenSaverEngine` returned success and replaced the desktop with a plain dark screen until Escape. `pmset displaysleepnow` returned success and produced a black screen; `caffeinate -u -t 2` restored the desktop. Evidence: corresponding screenshots and matrix t=22.205…32.047.

**OBSERVED:** `/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession` does not exist on this macOS image, so `CGSession -suspend` could not be run. **UNVERIFIED:** real lock-screen security context, password/Touch ID unlock, and lock widgets on a physical computer remain untested.

### 5. Brightness HUD

#### Complete recovered path and unresolved boundaries

**STATIC:** `BrightnessManager` stores observedDisplayID, actualBrightnessByDisplayID, localBrightnessTargetByDisplayID, localBrightnessCallbackSuppressionDeadlines, brightnessWriteTask, coalescing/suppression settings, fallbackNormalMediaKeyStep, fineMediaKeyStepScale, edgeDuration, currentBrightness, and shouldShowExternalDisplaySymbol. This separates hardware-reported state from optimistic local targets. Evidence: `fieldmd_hw.txt`, BrightnessManager at 0x10052fc78.

**STATIC:** Capability and observer setup at 0x1001197cc uses `DisplayServicesCanChangeBrightness` and `DisplayServicesRegisterForBrightnessChangeNotifications`. Reads occur at 0x100118d58, 0x100119b18, 0x10011cbb0. Set paths at 0x10011b7a0 and 0x10011be20 use `DisplayServicesSetBrightnessSmooth` and `DisplayServicesSetBrightness`. The decoded smooth path reads current brightness, clamps target to [0,1], attempts the smooth API, and has an ordinary-set fallback/error path. Task cancellation is checked. Evidence: `f_bright_register_1001197cc.txt`, `f_bright_set_10011b7a0.txt`, `f_bright_set2_10011be20.txt`.

**STATIC:** Step computation at 0x100122f0c asks `DisplayServicesGetBrightnessIncrement`. Successful positive values are used; otherwise normal step = 0.0625. Fine flag scales it by 0.25, hence fallback fine step = 0.015625. Actual hardware's reported increment takes precedence over hardcoded 1/16. Evidence: `f_bright_increment_100122f0c.txt`.

**STATIC:** Target preference enum includes explicit display, automatic, internal display, external display. Capability/target selection functions occur at 0x1001225e4, 0x1001228e4, 0x100122c40. **UNVERIFIED:** exact automatic target priority and behavior for non-DDC external screens.

**INFERRED:** Local target dictionaries and suppression deadlines prevent asynchronous brightness-change callbacks from fighting recent key writes. **UNVERIFIED:** exact coalescing delay, suppression interval, resampling count, and branch-to-Speed-setting mapping. Do not infer Smooth/Fast/Instant solely from whether an API name contains “Smooth”.

**STATIC / OBSERVED, lead:** `HUDSpeed` cases are smooth/fast/instant. Display settings expose duration 1.5 seconds, White/Accent/Glow styles, percentage off, label visible, and three speeds. A nearby view at 0x10013cae0 has critically damped SwiftUI spring response 0.2, damping 1, blend 0 at 0x10013d670 and 0x10013d74c. **UNVERIFIED:** this is not sufficient to assign those constants to all three brightness speed modes. Exact mode-specific progress and outer-notch curves are unresolved.

**OBSERVED:** Synthetic subtype-8 brightness key 2 (up), key 3 (down), and Shift+Option up events all posted successfully; no brightness HUD appeared in the capture or sampled screenshots. Volume and mute controls also produced no visible HUD, so their absence is not evidence that brightness decoding alone failed. A real DisplayServices-capable screen is still required to verify that path. No mock screen response or patched capability check was substituted.

**UNVERIFIED:** no brightness-specific sound was established. Shared `volume.caf` existence is not evidence that brightness plays it. Onboarding screenshots contain an animated example Display/Sound pill, but that is a demo, **not** a successful live brightness test.

### 6. Native OSD suppression, modifier keys, keyboard backlight

#### Event tap and exact swallowing

**STATIC:** At 0x100134354 Alcove creates `CGEventTapCreate(tap:1, place:0, options:0, mask:0x4c00, callback:0x1001368ac, userInfo:self)`: session event tap, head insertion, active/default option, listening for keyDown(10), keyUp(11), and systemDefined(14). It adds a run-loop source and enables the tap. The callback thunk enters 0x1001367fc, which re-enables a disabled tap after an `AXIsProcessTrusted` check. Evidence: `f_eventtap_create_100134354.txt`, `f_eventtap_callback_1001368ac.txt`, `f_eventtap_reenable_1001367fc.txt`.

**STATIC:** NX parsing at 0x100136eac:

1. Construct NSEvent and require subtype 8 (0x100136ef4–0x100136efc).
2. Read `data1`; key type is upper 16 bits, key state is the middle byte, repeat flag includes low bit. Handle 0x0a/0x0b down/up conventions.
3. Combine NSEvent flags, CGEvent flags, and current source flags.
4. Route through display/keyboard target preference and modifier logic.
5. Call handler 0x1001372b0.
6. At **0x100137194–0x100137198**, if handler result bit 0 is set, choose `xzr` instead of the original event pointer. Returning null swallows the event; otherwise return the original event.

**STATIC:** This establishes interception plus app-owned changes as the positive suppression mechanism. The active tap alone was only a clue; the conditional null return is the proof. **UNVERIFIED:** not every key/state is always swallowed; capability, modifier, and feature settings provide passthrough branches.

#### Key and modifier matrix

| Status | Input | Recovered handling |
|---|---|---|
| STATIC | 0 / 1 | sound up/down handler paths with normal ±1/16 and fine ±1/64 constants |
| STATIC | 2 / 3 | brightness up/down, target selection and DisplayServices increment path |
| STATIC | 7 | mute path |
| OBSERVED / UNVERIFIED | 21 / 22 | synthetic illumination-up/down posted; no visible response or actual keyboard light available |
| STATIC | Shift+Option | `(flags & 0xa0000)==0xa0000` computes fine adjustment, 0x100137140–0x10013714c |
| STATIC | Option without Shift | recognized volume/mute and brightness keys may open Sound or Displays preferences through 0x10013afbc |
| STATIC | Command | explicit passthrough branch at 0x100137074 |
| UNVERIFIED | Shift-only / Control combinations | additional feedback and target-selection branches exist; their complete user-facing semantics are not established |

**STATIC:** The Option handler contains `x-apple.systempreferences:com.apple.preference.sound` and `…displays` at 0x10013b070/0x10013b090. Do not reduce all Option-modified input to fine steps. Evidence: `f_optionkey_10013afbc.txt`.

#### Keyboard-origin and resampling machinery

**STATIC:** 0x100138cec enumerates `IOHIDDevice`, checks `PrimaryUsagePage`, and searches `HIDKeyboardLayoutValue` in the IOService plane. 0x100138fa0 examines keyboard identifiers including `internal keyboard`, `keyboard / trackpad`, `keyboard/trackpad`, `virtualhidkeyboard`, and `virtual hid keyboard`. These feed keyboard-origin/display-target logic. `KeyboardBrightnessResampleState` carries id, rawKeyCode, targetPreference, isFineAdjustment; related fields name a minimum apply interval, initial resample delay and interval. Evidence: `f_ioreg_100138cec.txt`, `f_ioreg_100138fa0.txt`, field metadata.

**UNVERIFIED:** these names do not prove a complete implementation of the physical keyboard-backlight actuator. Exact illumination API, key 21/22 swallowing policy, and numeric resampling intervals remain unresolved. In particular, “KeyboardBrightness” state may concern brightness keys originating from different keyboards, not only keyboard illumination.

#### BetterDisplay and OSDUIHelper

**STATIC:** Integration initializer 0x100132878 checks `pro.betterdisplay.BetterDisplay` and subscribes to `pro.betterdisplay.BetterDisplay.launched`, `.terminated`, `com.betterdisplay.BetterDisplay.osd`, and `.request`. A 0.075-second constant is present; its global debounce meaning is not proven. Evidence: `f_betterdisplay_100132878.txt`.

**STATIC:** Decodable OSD payload fields: systemIconID, value, maxValue, displayID/displayId/targetDisplayID, uuid/displayUUID/targetUUID. Request payload: uuid, commands `[String]`, parameters `[String:String?]`. **INFERRED:** this bridges external-display OSD events and integration commands to Alcove. Exact command names and request-response behavior are unverified. Evidence: `fieldmd_hw.txt`.

**STATIC, negative search:** Searches of supplied main/helper strings and imports found no `OSDUIHelper`, `launchctl`, or `killall` evidence supporting an OSD-helper-killing design. **UNVERIFIED:** absence of those strings does not exclude dynamically built/private IPC operations. The positively decoded event-swallowing path is sufficient to explain suppression without inventing a process-kill mechanism.

**OBSERVED:** OSDUIHelper was not running on this VM at baseline. No native HUD appeared during the synthetic key run. **UNVERIFIED:** this is not an A/B test of suppression. A proper follow-up needs a native OSD-capable Mac, identical keys with Alcove off/on, proof of volume/brightness changes, and key-up/repeat/modifier coverage.

### 7. Quantitative sound/media inventory

**STATIC:** Metadata measured with ffprobe, not estimated by listening. Evidence: `ev/logs/media_inventory.json`.

| Status | Resource | Duration | Encoding |
|---|---|---:|---|
| STATIC | lock.caf | 0.283938 s | PCM 24-bit LE, 48 kHz, stereo |
| STATIC | unlock.caf | 0.269728 s | PCM 16-bit LE, 44.1 kHz, mono |
| STATIC | low-power.caf | 0.672018 s | PCM 16-bit LE, 44.1 kHz, stereo |
| STATIC | low-battery.caf | 1.095875 s | PCM 16-bit LE, 48 kHz, mono |
| STATIC | volume.caf | 0.382426 s | PCM 16-bit LE, 44.1 kHz, mono |
| STATIC | Each of 15 AirPods videos | 6.000000 s | H.264, 96×96, 60fps, 360 frames, video only |

**STATIC:** SoundManager keeps reusable and per-name audio players and uses AVAudioPlayer. **UNVERIFIED:** trigger-to-audio latency, output gain, simultaneous-alert arbitration, and observed audible playback in this session.

### 8. Reproduction, evidence, and remaining validation

**OBSERVED:** `ev/scripts/runtime_matrix.py` records a 60fps-requested AVFoundation capture while posting hardware events and notifications, launches the screensaver, sleeps/wakes the display, and runs the adjusted-size experiments. `hwkeys.swift` encodes subtype 8 with `(key<<16)|((down?0xa:0xb)<<8)`, posts down then up 20 ms later, and spaces repeated pairs by 150 ms. Flags are optional hexadecimal; `a0000` is Shift+Option. `postnotif.swift` uses DistributedNotificationCenter with immediate delivery.

**OBSERVED:** Captured file `ev/clips/hardware_matrix.mp4` is 1600×1200, reports 60/1 rate, 2087 encoded frames, 35.916668-second duration, and has no audio track. Screen sleep/capture gaps mean it must not be treated as 60 unique samples per second throughout. Command timestamps in `runtime_matrix.json` are measured from script startup, not exact video PTS. Avoid assigning exact frame latency by multiplying those timestamps by 60.

**OBSERVED:** Important evidence files:

- `ev/logs/runtime_matrix.json`: commands, monotonic timings, exit status, output.
- `ev/logs/capture_metadata.json`: encoded capture metadata.
- `ev/logs/screenshot_bboxes.json`: simple dark-pixel bounds, not a semantic shape detector.
- `ev/logs/screen_geometry.json`, `environment.txt`: display and environment inputs.
- `ev/shots/`: named post-trigger full screenshots and adjusted-size experiments.
- `ev/dis/`: targeted disassembly, selector references, Swift hardware metadata, raw lookup tables.
- `ev/scripts/`: sources and executable helpers for reproducibility.
- `ev/notes_progress.md`: chronological scratch notes; **final corrections and this report supersede early hypotheses**.
- `lead_reference/`: supplied notes/settings/localization and earlier reports for provenance.
- `EVIDENCE_INDEX.txt` and `SHA256SUMS.txt`: packaged file inventory/integrity.

**UNVERIFIED:** Priority follow-up list, with no guessed answers:

1. Real notch plus mixed-scale/multiple-display selection; measure auxiliary rectangles on each requested Mac model.
2. Exact nonzero adjusted-width/height semantics and final view offsets.
3. Mac-battery source transitions, threshold equality/re-arm, low-power-on/off, actual battery UI and animation/sounds.
4. Physical AirPods left/right availability, case values, route reconnect and low-device-battery alerts; generic peripherals.
5. Actual locked-session LockPanel, all widget/material layouts, idle/keep-awake expiration, Touch ID.
6. DisplayServices-capable physical brightness changes; Smooth/Fast/Instant timing; callback coalescing.
7. Native OSD off/on A/B tests, keyboard illumination actuator, repeats and all modifier combinations, live BetterDisplay.

**INFERRED:** A clone can implement the recovered API adapters, model table, base geometry, state separation, and conditional key swallowing directly from these findings. It should not claim matching presentation or unsupported hardware behavior until the above missing tests are performed.


---

# Part F: gap-closing reverse engineering (v2)

_Source: `children/F_gaps/alcove_gaps_re.md`. Evidence lives in `children/F_gaps/`._

## Alcove 1.7.7 (build 199) — Gap-closing RE, area F (v2)

Binary: `/Applications/Alcove.app/Contents/MacOS/Alcove`, arm64 slice (`bin/Alcove.arm64`, SHA-256 `14520b5d…f653ec`), hardened runtime, Team `287NUTSP69`.
VM: macOS 26.6.2 (25G83), Apple Virtual display 1600×1200@1×, no notch / battery / AirPods / backlight / Touch ID.
Addresses are vmaddrs in the arm64 slice (same base as reports A/B/E). Tools: radare2 `aaa`, `otool -tvV` (full listing `ev/otool_text.txt`), custom `fieldmd.py` (Swift `__swift5_fieldmd` parser), `deobf.py` (obfuscated-string table decoder → `ev/deobf_strings.txt`, 276 records), ffmpeg/ffprobe, numpy, assetutil.

Evidence classes: **STATIC** (disassembly / metadata / resources), **OBSERVED** (seen on this VM), **INFERRED** (reasoned from static facts, not executed), **UNVERIFIED** (could not be established).

Overall VM caveat (OBSERVED): in this session Alcove never left onboarding — it is parked at the Accessibility step with a System Settings "Privacy & Security is trying to modify your system settings" auth sheet (`ev/lock/after_unlock.png`); `osascript` System Events returns `-25211 not allowed assistive access`, so neither the Accessibility toggle nor the Audio-Capture add-app flow could be scripted, and `defaults read com.henrikruscon.Alcove` shows only onboarding keys (`ev/shots/00_launch.png … 17_onb.png`). Everything "live" below is therefore bounded by that, exactly as instructed (document and move on, no retries).

---

### 1. Live waveform  (priority)

**Answer (STATIC, high confidence on everything Alcove-side; private-framework internals INFERRED):**

| Quantity | Value | Where |
|---|---|---|
| Analyzer/tap refresh rate (update cadence) | **20 Hz** (`fmov d0, #20.0`) | `0x1003602bc` in singleton builder `0x1003602a8` → `objc_allocWithZone(MPCAudioSpectrumAnalyzer)` then `initWithPlaybackEngine:refreshRate:` / `initWithPID:refreshRate:numberOfChannels:delegate:` (strings decoded in `ev/deobf_strings.txt`); result cached at `0x1005dab80` |
| Band count | **6 bands** default, clamped to 1…6 | band builder `0x1003a6e78`; count branch `0x1003a6ea4–0x1003a6eb0`; called from `0x1003a5744` @ `0x1003a57dc` |
| Band edges (Hz) | **20 · 81 · 170 · 527 · 1500 · 4500 · 10000** (float32 immediates `0x41a00000, 0x42a20000, 0x432a0000, 0x4403c000, 0x44bb8000, 0x458ca000, 0x461c4000`) | `0x1003a6ee8 … 0x1003a700c` (`ev/wv_1003a6e78.txt`) |
| Spacing | roughly **log-spaced** (ratios ≈4, 2.1, 3.1, 2.8, 3, 2.2); hand-tuned, not a formula | same |
| 5-band variant | drops the 81 Hz edge → 20–170, 170–527, 527–1500, 1500–4500, 4500–10000 | `0x1003a6f14–0x1003a6f34` |
| Per-band power read | `averagePowerOfFrequencyBandAtIndex:frequencyBand:` (decoded selector) → float stored per band | `0x100363d34` (`ev/wv_100363d34.txt`) |
| Level normalisation (Alcove side) | level clamped to **[0, 1]** (`fcsel` pair), no attack/release filter in Alcove | `0x1003a36b8–0x1003a36c4` in target-size fn `0x1003a350c` |
| Bar height mapping | `h = round_to_backing_scale( clamp( amplitudeHeight × level, **2 pt**, amplitudeHeight ) )`; backing-scale fallback 2.0 | mul `0x1003a36d8`, min/max `0x1003a36dc–0x1003a36f0`, rounding `0x1003a3778–0x1003a3784`, scale fallback `0x1003a375c`, size store `0x1003a3790` |
| Animation | CA bar-size animation **0.08 s** per update | constant `0x1003a386c–0x1003a387c`; CAFrameRateRange(5, 48) nearby `0x1003a3550–0x1003a3560` |
| Fan-out | `WaveformSpectrumSession.updateBlock` → `0x1003a5a60` → thunk `0x100074038` → `NSWaveformView.setLiveLevels` `0x1003a4a3c` (`liveLevels`, `lastLiveTargetSizes`) | `ev/wv_*.txt` |

Types (fieldmd): `Alcove.AudioManager` @`0x100535868` (`spectrumPID`, `spectrumAnalyzer`, `spectrumTap`, `activeSpectrumOwners`, `spectrumObservers`, audio-permission state + TCC fn pointers); `Alcove.NSWaveformView` @`0x100535fe8` (`amplitudeWidth/Height/Count/Spacing`, `duration`, `pauseDuration`, `usesLiveSpectrum`, `liveSpectrumBandCount`, `liveLevels`, `lastLiveTargetSizes`); `WaveformSpectrumSession` @`0x100536198` (`bandCount`, `updateBlock`, `lastLevels`, isActive/updateScheduled).

**Tap creation (STATIC → INFERRED):** Alcove does *not* call `AudioHardwareCreateProcessTap`/`CATapDescription` itself — neither symbol, class ref nor dlsym string exists. It uses the private MediaPlaybackCore/MediaCoreUI stack: `MPCProcessAudioTap` (`initWithPID:refreshRate:numberOfChannels:delegate:`), `MPCAudioSpectrumAnalyzer` (`setProcessAudioTap:`, `addFrequencyBand:`, `setOnUpdate:`, `start/stop`), `MPCAudioSpectrumObserver` (`addObserver:/removeObserver:`), plus `_createAudioTap` / `_shouldAttachAudioTap` (all decoded in `ev/deobf_strings.txt`; `rr_1003602a8.txt`, `am_100361500.txt`). The initializer is **PID-based → per-source-app tap (`spectrumPID` = the now-playing source), not whole-system**. Aggregate-device dictionary keys and the IOProc live inside MediaPlaybackCore, not Alcove → UNVERIFIED here (they are Apple's `MPCProcessAudioTap` implementation; Alcove only supplies PID, refreshRate = 20, channel count).
FFT/window size, dB floor/ceiling, attack/release: not present in Alcove; they are inside `MPCAudioSpectrumAnalyzer` → UNVERIFIED (INFERRED: the analyzer already returns a 0…1 "averagePower" per band, which is why Alcove only clamps).

**Permission flow (STATIC):** `AudioManager` holds dlsym'd `TCCAccessPreflight` / `TCCAccessRequest` for `kTCCServiceAudioCapture` (decoded strings). The crossed-mic "unblock" button → `TCCAccessRequest(kTCCServiceAudioCapture)`; if denied/not-determined-but-unpromptable it opens `x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture`. Why nothing happens on the VM (OBSERVED + INFERRED): the per-app audio-capture row only exists after a successful `MPCProcessAudioTap` preflight, and the VM's `AppleM2ScalerParavirtDriver`/virtual audio stack never produced a tappable process audio device; TCC db shows no `kTCCServiceAudioCapture` row for `com.henrikruscon.Alcove` (preflight returns denied without prompting). Plus, in this session the onboarding never completed so the toggle stayed disabled.

**Live attempt (OBSERVED → failed, bounded):** the System Settings › Screen & System Audio Recording › "System Audio Recording Only" › add-app flow could not be driven (AX automation blocked, `-25211`; Alcove parked at onboarding). No 60 fps live-waveform clip. Not retried per instruction.

Residual uncertainty: FFT/window/smoothing internals (Apple private), exact runtime value of `liveSpectrumBandCount` if a user setting ever selects the 5-band branch (no UI exposes it; INFERRED default 6).

### 2. Swipe thresholds

**Answer (STATIC partial, runtime BLOCKED):** The six `NotchSwipes` stored properties exist (fieldmd `0x100531924 verticalSwipeSuccessThreshold`, `0x100531930 verticalSwipeResetThreshold`, `0x10053193c cycleActivitySwipeSuccessThreshold`, `0x100531948 cycleActivitySwipeResetThreshold`, `0x100531954 horizontalSwipeSuccessThreshold`, `0x100531960 horizontalSwipeResetThreshold`; type descriptor `0x100517158`, metadata pointer stored at `0x100595790`, referenced only from data `0x10058bcf8`). No code ADRPs the descriptor (`grep` of `adrp 0x100517000` + `add #0x15x` in the full listing: none) → the struct is built by generic/inlined initialiser and the literals are **register-sourced from the caller as report A said**. The gesture-progress functions that consume them carry their own constants: `0x1001c4094` (12.0, 30.0, ×0.75) and `0x1001c613c` (12.0, 40.0) with `_gestureVerticalScroll` ivar `0x1005d3ed0`, `_isExpanded` `0x1005d3dc0` (`ev/sw_*.txt`). Measured (report B): toggle ≈35 px (−34 no / −36 yes), dismiss ≈35, close-expanded ≈105, skip ≈80, cycle once at +100 — consistent with "30 + hysteresis(12) ×0.75"-style maths but **the six exact literals remain UNVERIFIED**.
**Runtime read blocked:** `lldb -p <Alcove>` → `attach failed: Not allowed to attach to process`. Causes: CodeDirectory flags `0x10000(runtime)` (hardened runtime), no `com.apple.security.get-task-allow`, `csrutil status: enabled`. Re-signing/SIP-off would violate the no-bypass rule → not attempted.

### 3. Haptics

**Answer (STATIC):** one wrapper class `Alcove.HapticFeedback` (`0x10052eb28`, ivars `hasRecentlyTriggeredHaptic` @`0x100459640`, `debounceResetTask` @`0x100459648` → debounced), helper `0x1000739cc` → `NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime:)` (reloc `0x1005b2870`). Pattern enum: 0 `.generic`, 1 `.alignment`, 2 `.levelChange`; performanceTime 1 = `.now`.

| Call site | pattern | time | Trigger (from enclosing fn / strings) |
|---|---|---|---|
| `0x100014db0` (fn `0x100014b20`) | `.generic` | `.now` | notch click/open (NotchController mouse-up) |
| `0x10003fdf4`, `0x10003ff08` | `.generic` | `.now` | vertical swipe success / reset (two branches of same gesture fn) |
| `0x100141708` | **`.levelChange`** | `.now` | volume/brightness HUD step (scroll on HUD) |
| `0x1001a61b4` | `.generic` | `.now` | horizontal swipe (track skip) |
| `0x100291918`, `0x100291d20` | `.generic` | `.now` | cycle-activity swipe success / dismiss |
| `0x1000739cc` | pass-through | pass-through | wrapper |

(`ev/h_*.txt`, `ev/hc_*.txt`.) Residual: trigger column is INFERRED from the enclosing gesture functions' field accesses, not executed (no trackpad on VM).

### 4. Brightness HUD

**Answer (STATIC + OBSERVED):** Gate fn ≈`0x1001197cc`: display id → `DisplayServicesCanChangeBrightness` @`0x100119830`; `cbz w0 → 0x100119af8` (skip registration). Otherwise `DisplayServicesRegisterForBrightnessChangeNotifications` @`0x100119870`. `CGDisplayIsBuiltin` additionally gates at `0x10011970c`, `0x100118e70`, `0x10011aab0`, `0x10011cc2c`; display picker `0x1001226xx–0x100122f50` calls CanChangeBrightness per display and `DisplayServicesGetBrightnessIncrement` @`0x100122f50`. **Why no HUD on VM (OBSERVED):** Apple Virtual display is not built-in and `DisplayServicesCanChangeBrightness` returns 0 → the brightness observer is never registered. Keys (STATIC, report E + this pass): NX system-defined subtype 8, brightness up/down = keys **2/3**, keyboard-illumination up/down = **21/22**; step 1/16 (0.0625), Shift+Option fine step 1/64 (modifier mask `0xa0000`). Shared view (STATIC): the Display HUD is the same `HUD` progress view as Sound (settings "Display: duration 1.5 s, style White/Accent/Glow, Speed Smooth/Fast/Instant, show percentage, hide label" mirror Sound), `.levelChange` haptic path `0x100141708` is shared → **volume HUD timings transfer**. Bar step count: 16 steps (1/16) normal, 64 fine — matches macOS; INFERRED from the increment constants, no visual capture possible.

### 5. Battery / low-power UI

**Answer (STATIC, assets OBSERVED):** View struct `Alcove.Battery` (`0x1005187cc`; props `level`, `lowBatteryThreshold`, `showPercentage`, `isLowPowerMode`, `symbolReduction`) + `BatteryManager` (`0x1005cf2e8`; `_batteryDuration`, `_notifyOnLowPowerMode`, `_warnOnLowBattery`, `_lowBatteryThreshold` default **10.0**, `_playSoundOnLowBattery`, `_allowBatteryWhenFocused/Locked`, `_batteryLevel`, `_wasOnBattery`, `_isLowPowerModeEnabled`, `_hasPassedThreshold`, `_hasRecentlyChangedPowerSource`, `_remainingTime`) and `BatteryHelper` (IOKit `AppleSmartBattery`; errors `connectionAlreadyOpen`, `serviceNotFound`). Colours from `Assets.car` (`ev/assets_info.json`): **ChargingColor sRGB (0.553,0.922,0.573) ≈ #8DEB92**, **LowBatteryColor (0.980,0.388,0.459) ≈ #FA6375**, palette AlcoveGreen #4ADE80, AlcoveAmber #F59E0B, AlcoveAmberBright #FBC337, AlcoveOrange #FB923C, AlcoveRose #F43F5E, AlcoveCoral #F28C61, AlcoveEmerald #10B981. Thresholds: red when `level ≤ lowBatteryThreshold` (10 %), green while charging/full; **no separate yellow threshold literal found** (amber is used by low-power mode: INFERRED — `isLowPowerMode` is a Battery prop and AlcoveAmber is the only unexplained palette entry). Bolt: no bolt image in the catalog → SF Symbol (`bolt.fill`, `symbolReduction` prop controls symbol scaling) — INFERRED. Strings: "Charging", "Low Battery", "Low Power"; display duration 5 s; sounds `low-power.caf` 0.672 s, `low-battery.caf` 1.096 s. Layout/animation: UNVERIFIED (no battery on VM; SwiftUI body not statically recoverable). Asset renders: `ev/assets_info.json` + lock/swipe glyph PNGs in `ev/assets/`.

### 6. AirPods resources

**Answer (OBSERVED on files, mapping STATIC):** 15 bundled MP4s (no .usdz/.scn/.mov): `airpods-3`, `airpods-4`, `airpods-pro`, `airpods-pro-2`, `airpods-pro-3`, `airpods-max-{blue,green,midnight,orange,purple,red,silver,sky-blue,space-gray,starlight}`. Every file: H.264, **96×96, 60 fps, 360 frames = 6.000 s, no audio** (`ev/airpods/probe.txt`). Product-ID map (report E table): `2013`→airpods-3; `201b/2019`→airpods-4; `200e`→airpods-pro; `2014/2024`→airpods-pro-2; `2027`→airpods-pro-3; `200a/201f/202d`→airpods-max-<color> (colour chosen from device colour); `2002/200f` (AirPods 1/2) → no dedicated file, falls back to airpods-3 (INFERRED). Loop points (`ev/airpods/loop_analysis.txt`): no in-file loop markers; non-Max clips return closest to frame 0 at frame 359 → seamless file-boundary loop at 6.000 s; Max clips are ~symmetric about frame 180 (rotate out / back). Frame strips for all 15: `ev/airpods/*_strip.png`.

### 7. Explicit badge

**Answer (STATIC):** Key = **`kMRMediaRemoteNowPlayingInfoIsExplicitTrack`** (string @`0x10036d808`), plus Spotify Web-API fallback `content_ratings`/`explicit` (`0x10036d1d0`). Settings: Explicit badge None / Explicit / Format (default Explicit); glyph is SF Symbol **`e.square.fill`** (settings AX dump) — no catalog asset. Size/placement: UNVERIFIED (SwiftUI; not recoverable from constants with confidence). Live trigger: not attempted — Alcove never reached a configured state on this VM; `MRMediaRemoteSetNowPlayingInfo` is also hardened against third-party callers on macOS 26 → UNVERIFIED.

### 8. notchAdjustedWidth / notchAdjustedHeight

**Answer (STATIC):** Geometry fn `0x100238df8` (callers `0x100233518`@`0x1002335a4`, `0x10035ac84`@`0x10035ad84`) **does not read the adjusted values at all**. It only consults `NSScreen.auxiliaryTopLeftArea/auxiliaryTopRightArea` (`0x100238e28/e4c`, `CGRectIsEmpty` `0x100238ee8/ef8`) and returns 4 doubles:
- no notch areas (simulated-notch path): `d0=74, d1=19.5, d2=321, d3=175` @`0x100238fc4–0x100238ff0` (closed W×H 74×19.5? max W×H 321×175);
- real notch: `h = screen.maxY − aux.maxY − 5.5` (`0x100238f78`; −1 variant `0x100238f48`; alt fixed 24 @`0x100238f9c`), `maxW = min(345, gapWidth + 160)` @`0x100239018–3c`, `maxH = min(175, h + 142)` @`0x100239040–68` (alt +140 @`0x100238fbc`).
The `_notchAdjustedWidth/Height` ivars (NotchController offsets `0x1005d3cd8/ce0`, also on NotchView `0x100531c2c/38`, NotchLumaView, NotchQuickPeekView, NotchNotificationsView, NotchLiveActivitiesView, GeneralSettingsView) are only touched in property-sweep fns `0x100220714, 0x1002227bc, 0x10022bb24, 0x1002326ec, 0x1002348e0` (Published-wrapper retain/release) → they are plumbed into the views' SwiftUI padding, not into the window-size geometry. **Why no visible effect:** with "Force simulated notch" the fallback constant branch is taken and the adjusted values never modify window size; the views only apply them when a real notch (`auxiliaryTop*Area` non-empty) is present. Residual: the exact SwiftUI consumer is INFERRED.


> **Lead correction (STATIC, re-read of `ev/geom_100238df8_filtered.txt`):** the clamps are **max**, not min. Width: `fcmp d1(gap+160), d2(345)` then `fcsel d2, d2, d1, ls` picks 345 when gap+160 ≤ 345, else gap+160 → `max(gap+160, 345)`. Height: `fcmp d3(h+142), d4(175)`, `b.hi` keeps h+142 when it exceeds 175, else 175 → `max(h+142, 175)`. This matches Part E. Also, the constant branch (74 × 19.5, max 321 × 175) is the **no-notch compact** path (Part E), not the forced-simulated-notch path, which was measured live at 144 × 29 (Parts B/lead). The core finding stands: this function never reads `notchAdjustedWidth/Height`.

### 9. Lock screen live

**Answer (OBSERVED + STATIC):** Real lock executed twice (`ev/lock/`): attempt 1 with screenLock off → display slept, no lock UI (luma constant). Attempt 2 after `sysadminctl -screenLock immediate`: `pmset displaysleepnow` → at frame 533 (t≈8.88 s) **2 black frames (33 ms)**, then loginwindow lock screen is **fully captured** by avfoundation (not blank): LUI2 big clock + date, avatar, "Enter Password" (`locked_screen.png`, `locked_full.png`). `caffeinate -u` woke it, scripted password → unlock crossfade frames 952–959 (**≈117 ms**). **Alcove's lock widget was NOT present** (`locked_full_top.png` vs `after_unlock_top.png` both empty top-centre) because Alcove is stuck in onboarding on this VM (see caveat) — so widget layout/material/animation/sound timing remain UNVERIFIED live. Static recovery: `LockManager` polls `CGSSessionScreenIsLocked` (`0x10026a6d8`, `0x10034eed8`), preloads `lock.caf` (0.284 s) / `unlock.caf` (0.270 s) @`0x10034fa14/a34`; reads loginwindow's clock via private LoginUIKit `LUIClockSettingsManager.sharedClockSettingsManager / clockSettingsForUserWithGUID: / setClockSettings:` (fns `0x100245444–0x1002458a4`) and `batteryViewController` (`0x100245314`), classes `LUI2BigTimeViewController`, `LUI2DateViewController`, `LUI2VibrancyEffectView`, `LUI2UIController`, `LUI2NoAnimationLayer`. Settings: widgets Battery/Connectivity/Focus/Calendar(off)/Now Playing, material Glass/Clear/Frosted, idle 10 min, offset tuning px. Widget layout constants: UNVERIFIED (SwiftUI, no literals isolated).

---
### Evidence zip index (`alcove_gaps_evidence.zip`)
`ev/PROGRESS.md` (running log), `ev/deobf_strings.txt`, `ev/wv_*` (waveform fns), `ev/rr_1003602a8.txt`, `ev/am_100361500.txt`, `ev/h_*`/`hc_*` (haptics), `ev/sw_*` (swipes), `ev/geom_100238df8_filtered.txt`, `ev/airpods/` (probe, loop analysis, 15 strips), `ev/assets_info.json`, `ev/lock/` (2 clips @60 fps, frames, timings), `ev/shots/` (onboarding), scripts `fieldmd.py`, `deobf.py`. The 1.1 M-line `otool_text.txt` is omitted for size (regenerate: `otool -tvV Alcove.arm64`).


---

# Part G: uncovered areas (v3): games, sounds, URL scheme, particles, updater, AppleScript, performance, displays

_Source: `children/G_v3/alcove_uncovered_re.md`. Evidence lives in `children/G_v3/`._

## Alcove 1.7.7 (199): uncovered areas 7–14

Supplement to the supplied v2 teardown, not a replacement. Analysis date: 2026-10-11/12 UTC. Target: `com.henrikruscon.Alcove`, arm64 slice, macOS 26.6.2 (25G83) VirtualMac2,1. Installed universal executable SHA-256: `f8c83e2473d4ce9b9ba11f597cdbac6be84aeb127946fc55d12a449098bd032f`; analyzed arm64-slice SHA-256: `14520b5dd7b91b6e248122194dc206634173fb014d105a308d824974d4f653ec`. Addresses below are **unslid virtual addresses** in the main executable unless prefixed **helper**; actual process load addresses differ under ASLR.

### Evidence conventions and scope

- **OBSERVED:** measured from this VM, captured UI, endpoint response, or a tool execution.
- **STATIC:** directly recovered from this build's executable, metadata, or bundled resources.
- **INFERRED:** interpretation of static context, with the remaining ambiguity identified.
- **UNVERIFIED:** not demonstrated, including hardware and paths deliberately left alone.

Evidence paths refer to `children/G_v3/evidence/` in the teardown ZIP. Screen recordings and synthetic tests are not measurements of a physical notched Mac. No Alcove binary was modified. No probe sent a license key, explicitly invoked a license endpoint, or installed an update. Ordinary app startup/background network traffic was not comprehensively audited. Licensing internals and license-route execution are excluded. Separately assigned waveform rendering, explicit badges, lock-screen widgets, activity swipes, Low Power Mode UI, and reduced-motion/transparency behavior were not re-investigated.

### 7. GameManager

#### Answer

**STATIC:** This build's `GameManager` classifies the **frontmost application**, not every running game, using an explicit bundle-ID set plus a Minecraft bundle-path substring. Its initial observation reads `NSWorkspace.shared.frontmostApplication` at `0x100126f60`; its notification setup uses `NSWorkspaceDidActivateApplicationNotification` at `0x10012722c`. Classification is in `0x1001276f0`:

1. Read `NSRunningApplication.bundleIdentifier` (`0x100127774`) and test membership in the set initialized at `0x100126b00`.
2. If not matched, read `bundleURL` (`0x1001277e4`), lower-case the path, and test the Minecraft fragment.

The five IDs in the constant array at `0x100590950` are:

```text
com.riotgames.leagueoflegends
com.riotgames.leagueoflegends.gameclient
com.riotgames.leagueclient
com.riotgames.leagueclientux
com.nvidia.gfnpc.mall
```

The separate path match is `/application support/minecraft/runtime/` (lower-case). These are identities/path heuristics, not signatures that verify an app is genuinely a game.

**STATIC negative finding:** The recovered classifier does not inspect `LSApplicationCategoryType`, invoke a Game Mode API, measure GPU activity, or require fullscreen. This statement is about the recovered classifier, not a claim about every component of macOS.

**STATIC:** `hideWhileGaming` is the controlling preference; `hideWhileInFullscreen` and `hideWhileInMissionControl` are separate settings. `GameManager` exposes its gaming state to the notch/coordinator path. The behavior is hiding/suppressing the notch while the classified application is active, not pausing the game or changing system Game Mode.

#### Controlled live findings

**OBSERVED:** With Force simulated notch ON and Hide in fullscreen OFF:

| Synthetic control | Gaming setting | Result |
|---|---|---|
| `local.devin.alcove.synthetic-category`, category `public.app-category.action-games`, windowed or native fullscreen | ON | Notch remains visible |
| `com.nvidia.gfnpc.mall`, utilities category, windowed or native fullscreen | ON | Notch hides |
| Same listed-ID app, foreground | OFF | Notch returns |
| Same listed-ID app, repeated normal volume-up event | ON | Alcove Sound HUD suppressed |
| Same listed-ID app, same volume event | OFF | Alcove Sound HUD visible |

The volume test only became meaningful after configuring a working BlackHole output and correcting the **test helper's** normal media-key event flags. It does not demonstrate suppression of every possible activity. The application binary itself was unchanged.

**Evidence:** `live/02_category_fullscreen_notch_visible.png`, `04_listed_gaming_off_visible.png`, `05_listed_gaming_on_hidden.png`, `06_listed_fullscreen_hidden.png`, `11_sound_hud_gaming_off.png`, `12_sound_hud_gaming_on_suppressed.png`; game IDs/categories are visibly labeled by the synthetic app. The category-only versus listed-ID experiment isolates identity from category and fullscreen.

**Evidence:** `static/fn_100126b00.txt`, `static/fn_1001276f0.txt`, `static/game_strings.json`, scoped Swift metadata, synthetic helper source and app Info.plists in `live/`.

**Residual uncertainty:** The Minecraft runtime path and Riot IDs were not individually exercised. No claim is made that this short list recognizes Steam games generally. Fullscreen behavior on a physical notched display and OS Game Mode remain UNVERIFIED.

### 8. All 13 bundled sounds

#### Measurements

**OBSERVED, offline file measurement:** Samples were decoded to float32 PCM with FFmpeg. Peak is `20 log10(max(abs(samples)))`; RMS is `20 log10(sqrt(mean(samples²)))`, over the complete decoded file and all channels. These are **sample dBFS**, not LUFS, true-peak, calibrated SPL, or runtime playback level. Silence/tails are included. AAC container duration can differ from decoded sample duration due to encoder padding; both are retained in the JSON.

| File | Decoded duration (s) | Sample rate | Channels | Peak dBFS | RMS dBFS |
|---|---:|---:|---:|---:|---:|
| `alt-jingle.m4a` | 5.995646 | 48000 | 2 | -3.37 | -17.70 |
| `blips.m4a` | 6.741333 | 48000 | 2 | -4.12 | -23.03 |
| `chime.caf` | 4.237438 | 44100 | 1 | -20.04 | -43.77 |
| `directions.caf` | 1.475556 | 44100 | 1 | -14.02 | -33.03 |
| `event.caf` | 1.743084 | 44100 | 1 | -17.52 | -36.34 |
| `haptic.caf` | 0.010583 | 48000 | 1 | -8.53 | -25.21 |
| `lock.caf` | 0.283938 | 48000 | 2 | -10.67 | -38.31 |
| `low-battery.caf` | 1.095875 | 48000 | 1 | -0.00 | -20.75 |
| `low-power.caf` | 0.672018 | 44100 | 2 | -5.80 | -25.46 |
| `pad.m4a` | 6.058667 | 48000 | 2 | -3.95 | -22.45 |
| `sleep.caf` | 3.002417 | 48000 | 1 | -11.12 | -30.61 |
| `unlock.caf` | 0.269728 | 44100 | 1 | -11.91 | -39.89 |
| `volume.caf` | 0.382426 | 44100 | 1 | -7.00 | -30.40 |


Each waveform is `sounds/<stem>.png`; `sounds/inventory.json` includes exact frame counts, both durations, codec, rates, channels and levels. The per-file JSONs preserve FFprobe output. `scripts/audio_inventory.py` is the reproducible measurement script. Near-0 dBFS in a source file does not imply runtime clipping: playback gain and the output device are separate.

#### Events, call sites and gates

All rows below are **STATIC** unless explicitly marked INFERRED. “No dedicated gate identified” means exactly that, not that the sound is unconditionally audible in every app state.

| Asset | Recovered event/use | Call-site evidence | Settings gate / remaining ambiguity |
|---|---|---|---|
| `alt-jingle.m4a` | Intro/onboarding presentation sequence | `0x1002b47d8–0x1002b4800`, calls scheduled SoundManager play | Presentation lifecycle; no dedicated sound preference identified |
| `blips.m4a` | Celebratory audio in LicenseView / LicenseSettingsView UI | Audio-only snippets around `0x10001773c` and `0x1001a93a0` | Licensing branches deliberately not inspected or triggered; no behavioral claim beyond UI audio association |
| `pad.m4a` | About and Intro presentation ambience | Plays at `0x100264644`, `0x1002ae8f0`; named stops at `0x10026471c`, `0x1002ae9c8` | View lifecycle; no dedicated sound preference identified |
| `chime.caf` | Hourly calendar chime | `0x1002ddef8` calls AudioServicesPlaySystemSound | `playHourlyChime`; surrounding calendar/fullscreen eligibility also applies |
| `directions.caf` | Time-to-leave calendar notification | `0x1002ed554` | `playSoundOnTimeToLeave`, with `notifyWhenTimeToLeave` controlling the feature |
| `event.caf` | Calendar event notifications | `0x1002e69b4`, `0x1002e840c` | `playSoundOnCalendarEvent`; two event-notification code paths share the asset |
| `haptic.caf` | Audible tick while changing the notch-width tuning control | `0x10032c14c` callback → `0x100330360` → `0x10032c984`; play at `0x10032c9c8` | No physical-haptics check in the sound callback; see distinction below |
| `lock.caf` | Screen-lock sound | `0x100351a9c` | `playSoundOnLock` |
| `low-battery.caf` | Low connected-device battery warning | `0x100315440` | `playSoundOnLowConnectBattery` |
| `low-power.caf` | BatteryManager warning playback; low laptop battery association INFERRED from gate | `0x100131370`; gate read at `0x100130e4c` | `playSoundOnLowBattery` (BatteryManager field offset `0x98`), plus an enabled notch-controller guard; not simply a sound named after the Low Power Mode setting |
| `sleep.caf` | Sleep Focus notification | `0x100101c2c` | `playSoundOnSleepFocus` |
| `unlock.caf` | Screen-unlock sound | `0x100351c48` | `playSoundOnUnlock` |
| `volume.caf` | Volume-change feedback | Resource cached at `0x10001f9d8`; reusable play at `0x100022360` | System preference `com.apple.sound.beep.feedback`, read via UserDefaults at `0x100021f7c`; volume-manager state/eligibility guards also apply |

**STATIC implementation correction to baseline:** CAF notifications are not all ordinary `AVAudioPlayer.play()` calls. The listed calendar, power, lock and unlock call sites use `AudioServicesPlaySystemSound` with cached SystemSoundIDs. `SoundManager` also has immediate AVAudioPlayer playback (`0x1003089f4`), scheduled playback (`0x100306d88`, `deviceCurrentTime` / `playAtTime:`), and reusable-player playback for volume (`0x100307904`). Resources are found by name and extension in the main bundle. Error strings explicitly distinguish missing sound from AVAudioPlayer construction failure.

#### What `haptic.caf` actually is

**STATIC + OBSERVED offline:** A short, approximately 10.6 ms, **ordinary mono audio file**, not a haptic pattern file or an instruction to a Taptic Engine. GeneralSettingsView's `settings.general.tuning.notchWidth` control (`0x10032be78`) installs a Double-value-change callback (`0x10032c14c`); that callback ultimately plays `haptic.caf` through AVAudioPlayer (`0x10032c9c8`). This is audible calibration feedback.

**STATIC:** Physical haptics are a different implementation: `NSHapticFeedbackManager.defaultPerformer` and `performFeedbackPattern:performanceTime:` around `0x100073a50–0x100073aac`, governed by `enableHaptics`. Do not implement the tiny CAF as a substitute for every physical-haptic event, or assume disabling physical haptics necessarily mutes this tuning tick.

**Evidence:** `static/systemsound_*.txt`, `static/sound_detail_*.txt`, `static/haptic_context_10032c14c.txt`, `static/fn_100021f14.txt`, `static/fn_1000739ac.txt`, `static/swift_types_scoped.json`.

**Residual uncertainty:** Acoustic playback of every event, hardware battery paths, Focus transitions, and exact gain/scheduling during all UI sequences were not exhaustively tested. The measurement table describes the files, not a promise of those levels from speakers. The naming is counterintuitive: the recovered `low-power.caf` call is gated by `playSoundOnLowBattery`, while `low-battery.caf` is used by the connected-device path; do not infer event semantics from filenames alone. No license UI state was forced to play blips.

### 9. `alcove://` URL handling

**STATIC:** Info.plist registers one scheme, `alcove`. `application:openURLs:` at `0x10020354c` bridges the URL array and calls `0x100204448`. The handler walks each URL's `absoluteString`, checks the literal scheme prefix using `String.hasPrefix` (`0x10020453c–0x100204568`), and then dispatches its remaining string.

**STATIC:** The only recognized route found in that dispatcher is **license-related (`license`)**. Per scope, only its existence is recorded; parameters, payload handling, downstream logic and execution are intentionally omitted. There is no recovered non-license host/path/query route for Settings, About, Now Playing or notch control. This is not a broad deep-link API with an undocumented switch of feature routes.

**STATIC:** Safe unsupported inputs fall through rather than selecting a feature. A successful `open` exit code alone only proves Launch Services accepted a registered scheme; it does not prove Alcove recognized a route.

**OBSERVED safe negative controls:** `open 'alcove://'`, `open 'alcove://unknown'`, and `open 'alcove://settings'` were accepted by Launch Services but did not open settings or produce visible Alcove content changes. These are negative controls, not three supported routes. Screenshots: `live/07_url_root.png`, `08_url_unknown.png`, `09_url_settings_noop.png`. No license URL was called.

**Evidence:** `static/plist_scoped.json`, `static/url_dispatch_scoped.txt`. The excerpt includes the scheme gate and array-dispatch wrapper but deliberately omits license processing.

**Residual uncertainty:** No license route was called. Case, escaping and unusual URL payload behavior beyond the safe tests are UNVERIFIED; they are not useful supported clone features on the evidence available.

### 10. Vortex particles

#### Used configurations versus library contents

**STATIC:** Three **app-level direct custom VortexSystem construction sites** were found, all using `circle`, not three different rain/snow/confetti presets:

| App context | Constructor / call site | Birth rate | Lifespan |
|---|---|---:|---:|
| About presentation | `0x100264d34`; called at `0x100263660` | 8.5/s | 3.5 s |
| Update presentation | `0x10028ed6c`; called at `0x10028ec2c` | 8.5/s | 3.5 s |
| Intro presentation | `0x1002ad958`; called at `0x1002ac8a8` | 10/s | 4 s |

These constructors share the same floating white particle configuration. The linked Vortex library also contains preset implementation code. **Bundled preset code/assets do not establish that Alcove invokes those presets.** The recovered weather strings (`isRaining`, weather SF Symbols, etc.) are not sufficient evidence of a Vortex rain/snow call path. No app-level calendar celebration or weather precipitation trigger was established.

#### Recovered parameter values

**STATIC:** Property setter slots in VortexSystem metadata at `0x1005e0d70` were followed to actual ivar-offset references; this avoids guessing that every nearby number is a birth rate. Representative setter addresses and values:

| Property | Shared value | Setter / evidence |
|---|---|---|
| Image tag | `circle` | Constant tag arrays `0x10059c2d8`, `0x10059e150`, `0x10059e7b8` |
| Shape | `.point` (enum case 3) | `0x100405878`; Shape cases box, ellipse, ring, point |
| Position | normalized `(0.5, 0.5)` | Constructor constant arrays |
| Birth rate | 8.5 or 10 as above | `0x100405954` |
| Lifespan | 3.5 or 4 as above | `0x100405e30` |
| Lifespan variation | 0 | Initializer `0x100406c88` |
| Speed | −0.15 | `0x100405fc8` |
| Speed variation | 0.05 | `0x100406094` |
| Angle | 0 radians | Constructor stack argument and ivar store |
| Angle range | π radians | `0x10040622c` |
| Acceleration | `(0, 0)` | Constructor constant array |
| Damping factor | 0.5 | `0x100406570` |
| Angular speed / variation | zero vectors | Constructor constant arrays |
| Colors | white ramp with alpha stops `[0, 0, 1, 0]` | `0x1004067f0`; white RGBA constant `0x100478298` |
| Size | 1 | `0x100406998` |
| Size variation | 1 | `0x100406a64` |
| Size multiplier at death | 0.5 | `0x100406b30` |
| Secondary systems | empty | Constructor |
| Emission limit | nil | Constructor |
| Emission duration / idle duration | 1 / 0 seconds | Constructor |
| Burst count / variation | 100 / 0 | Constructor stack arguments |

**INFERRED:** In the UI, the shared settings produce a fading white drifting particle field, not gravity-driven confetti. Normalized speed and size are Vortex values; they must not be interpreted directly as screen pixels per second or pixel diameter without the view's image dimensions, scale and update implementation. Burst-count presence does not mean an explicit burst is triggered on every presentation.

**STATIC assets:** `Vortex_Vortex.bundle/Contents/Resources/Assets.car` contains named `circle`, `confetti` and `sparkle` image assets (plus catalog bookkeeping/packed storage). Asset presence alone is not a trigger. `static/vortex_assets.json` preserves the catalog inventory.

**OBSERVED UI / UNVERIFIED motion:** The separate **Alcove menu → About Alcove** presentation was opened, showing the purple app icon, large Alcove title and Version 1.7.7(199). This is **not** Settings → About, which is the updater/preferences pane. The white particle field was not conclusively resolved in the captured VM UI, so no measured particle trajectory or observed rain/confetti claim is made. Screenshot: `live/about_alcove_presentation.png`; the continuous recording covers its opening. Constructor values above remain STATIC, not values fitted from video.

**Evidence:** `static/vortex_caller_*.txt`, `static/vortex_slot_*.txt`, `static/fn_100406c88.txt`, `static/vortex_objc_fields.txt`, scoped Swift enum metadata.

**Residual uncertainty:** The three constructors are the direct app-level sites found in this build, not a formal proof that no additional indirect/reflection path can exist. Weather particle use, calendar confetti, runtime burst commands, and particles during successful update availability are UNVERIFIED. Onboarding was not reset simply to recapture its particle field.

### 11. Update mechanism

#### Request, response and interval

**STATIC:** Alcove's own UpdateManager/UpdateController and AlcoveHelper implement updating; the examined path is not Sparkle.

- URL: `https://api.tryalcove.com/updates/latest`, no query in the recovered request construction (`0x10027c980`).
- Method: `GET` (`0x10027cb78`).
- `Accept: application/json` (`0x10027cb8c`).
- General client headers: `X-App-Version`, `X-App-Build`, `X-macOS-Version` (builder around `0x100285d2c`).
- Channel support: `stable`, `trial`, `beta`; `X-Channel` is built for selected channels around `0x10027c8cc`. This does not establish the server's default channel contract.
- An authorization header exists in the app request path. Its credential acquisition/validation was not investigated and no such header was sent in this experiment.
- Request timeout constant: 60 seconds.
- Timer interval: **21,600 seconds (six hours)**, double constant loaded at `0x10027ba50` and passed to the timer publisher at `0x10027ba70`. This is a configured periodic interval, not proof of background execution while the Mac/app sleeps.

**OBSERVED read-only request:** A plain unauthenticated GET at 2026-10-11 23:42:50 UTC returned **HTTP 401**, Content-Type `application/json`, body:

```json
{"message":"An active license is required for this channel."}
```

No keys, tokens, alternate credential attempts, license endpoints, or update installation were involved. A minimal read-only reproduction is in `scripts/update_readonly.sh`; response headers/body are in `static/update_get_headers.txt` and `static/update_get_body.json`.

#### JSON model: static, not a successful server sample

**STATIC:** The release decoder and Swift reflection expose this field structure:

```text
Release
  id
  tag_name                -> tagName
  name
  sections[]              -> Section { marker, items }
  assets[]                -> Asset { name, url }
  prerelease
  published_at            -> publishedAt
  minimum_system_version  -> minimumSystemVersion
  build_number            -> buildNumber
Error response
  message
```

Model metadata accessors: Release `0x100284080`, Asset `0x100287b1c`, Section `0x1002884ac`. Key selection appears around `0x1002840a0`; JSONDecoder calls at `0x10027ce88` / `0x10027cfec`. The field set is recovered, but requiredness, nullability, date encoding and accepted numeric/string coercions are **not a validated external API schema**. The only observed response schema is the one-field error above.

#### UI, download, checks and installation

**STATIC:** Update availability states include `notChecked`, `available`, `unavailable`, `readyToRestart`; UI/controller fields include progress and changelog. Download-related code uses release asset URL/name information, ZIP assets, an `Alcove/Updates` cache path, a download delegate, and a second release/version check before installation. The end user is offered update/progress/restart states rather than an embedded Sparkle dialog.

**OBSERVED UI:** Settings → About showed `Check Updates…`, version 1.7.7 and the `Automatically check for updates` toggle (`live/10_about_updater_untouched.png`). No manual update check, download or installation was initiated; successful availability/progress/restart UI was not triggered.

**STATIC, helper binary:** XPC exposes `installUpdateWithZipPath:appBundlePath:reply:`. The helper:

1. Checks that the ZIP path exists (`helper 0x10000325c`), makes a temporary extraction directory (`0x10000331c`).
2. Runs `/usr/bin/ditto -xk <zip> <temporary-directory>` (`0x10000335c–0x10000343c`), waits, collects output and checks termination status (`0x100003a70`).
3. Enumerates the extracted directory (`0x100003afc`), finds an `.app`, reports “No .app found in update archive” if absent (`0x100003f68`), and uses the Foundation replacement operation in the installation path (`0x100003ed0`).
4. Removes temporary/download artifacts, resolves the updated bundle ID (`0x1000040a4`), handles existing running instances and asks NSWorkspace to relaunch it (`0x100004158`). Errors include missing ZIP, missing app, unresolved bundle ID and relaunch failure.

**STATIC negative finding / limitation:** The inspected helper path provides existence, extraction/process-status and bundle-resolution checks. No explicit cryptographic checksum or `SecCode`/`SecStaticCode` signature-verification step was identified in this helper's imports or recovered install path. **That is not proof of an exploitable updater or that macOS performs no signature checks.** The complete network-to-install verification contract and success behavior remain UNVERIFIED; no malicious archive or replacement was supplied and the installer was not exercised.

**Evidence:** scoped updater request/model/timer excerpts, `static/updater_helper_disassembly.txt`, `static/helper_imports_full.txt`, response files, UI capture if present in `live/`.

**Residual uncertainty:** HTTP 401 prevented an observed success release, download, progress or restart. Whether additional verification occurs in the main app or OS, exact rollback guarantees, and permissions when replacing an app outside writable `/Applications` remain UNVERIFIED.

### 12. AppleScript

**STATIC:** Info.plist has `NSAppleScriptEnabled=true`, but no `.sdef`, `.scriptSuite`, `.scriptTerminology`, or `NSScriptingDefinition` was found in the app bundle. No Alcove-specific `NSScriptCommand` subclass/handler was identified in the recovered ObjC/Swift metadata.

**OBSERVED:** `sdef` returns generic AppKit **Standard Suite**, **Text Suite**, **Type Definitions**, **Type Names**, not an Alcove custom suite. Thus `NSAppleScriptEnabled` is **not evidence of a documented notch-control scripting API**.

The generic dictionary advertises commands: `close`, `count`, `delete`, `duplicate`, `exists`, `get`, `make`, `move`, `open`, `print`, `quit`, `save`, `set`. Application properties: `frontmost`, `name`, `version`; inherited item properties: `class`, `properties`. Window properties: bounds, closeable, document, floating, id, index, miniaturizable, miniaturized, modal, name, resizable, titled, visible, zoomable, zoomed. Document properties: modified, name, path. Generic text classes expose color, font and size; attachment exposes file name. Full names, types and access flags are retained in `static/sdef_summary.json` and the original `static/sdef.txt`.

**OBSERVED:** Initial read-only script results:

| Test | Result |
|---|---|
| `get name` | Alcove |
| `get version` | 1.7.7 |
| `get frontmost` | true |
| `count windows` | 76:89: execution error: Alcove got an error: AppleEvent timed out. (-1712) |
| `get properties` | 80:90: execution error: Alcove got an error: AppleEvent timed out. (-1712) |
| `get properties of windows` | 80:90: execution error: Alcove got an error: AppleEvent timed out. (-1712) |
| `count documents` | 76:91: execution error: Alcove got an error: AppleEvent timed out. (-1712) |
| `exists window 1` | true |


**Scope of tests:** There are **zero recovered custom commands to test**. Generic read-only property/existence/count commands were used as a bounded smoke test, with a three-second AppleEvent timeout. Mutating generic commands such as delete/move/save/print and quit were not indiscriminately executed against the running evidence session. Advertising the AppKit dictionary does not prove all its document/text operations have meaningful implementations here.

**Evidence:** `static/plist_scoped.json`, `static/sdef.txt`, `static/sdef_summary.json`, `static/applescript_read_tests.json`.

**Residual uncertainty:** Generic AppleEvent timing depends on app/UI state and authorization. No custom feature automation was discovered; generic dictionary operations not exercised are UNVERIFIED rather than claimed supported.

### 13. Performance

#### Method and VM limits

**OBSERVED:** PID 3840 remained unchanged for all 42 samples over **1,230.007 seconds (20.5 minutes)**, from 2026-10-11 23:51:53.649 UTC to 2026-10-12 00:12:23.690 UTC. Initial process age was about 1m59 s, final age22m29 s. Collection used `ps` every 30 s and two-sample `top`, plus continuous ~1 s `top` / task `powermetrics` samples, and before/after `footprint`, `vmmap --summary`, `sample` snapshots.

This was a **mixed-workload run**, including game controls, Settings/About, virtual-display attach/detach, sound HUDs and a BlackHole/coreaudiod change around 17:00 PDT. Recording and measurement processes were active. It is neither a physical-Mac energy benchmark nor a controlled idle leak test. The bounded idle phase was collected after helpers were stopped and Main display restored.

#### Bounded workload table

**OBSERVED:** CPU is Alcove process CPU; powermetrics CPU ms/s divided by 10 approximates percent of one logical core. Energy Impact is the tool's relative score, **not watts**. `top MEM` is approximate rounded physical-footprint MiB, not `ps` RSS. Wakeups are process interrupt wakeups/s. Different tools have independent sample boundaries, so sample counts differ.

| State | Local PDT window | top / power samples | top CPU mean / peak % | CPU ms/s mean | top MEM median MiB | Interrupt wakeups/s mean | Energy Impact mean | GPU ms/s |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| Idle, closed notch | 17:11:03–17:11:51 | 48 / 48 | 0.00 / 0.0 | 0.17 | 65 | 1.01 | 0.016 | 0.00 |
| Four pointer open/close input cycles† | 17:11:51–17:12:56 | 64 / 63 | 1.43 / 13.9 | 15.09 | 66 | 10.34 | 1.508 | 0.00 |
| Volume keys, verified Sound-HUD baseline‡ | 17:03:21–17:03:50 | 28 / 29 | 4.94 / 33.5 | 49.30 | 64 | 35.86 | 4.929 | 0.00 |
| Now Playing / synthetic waveform active | Not established | — | UNVERIFIED | — | — | — | — | — |

† Four deliberate pointer input cycles plus tool/annotation latency, not continuous animation. This window measures those interactions; do not generalize it to a sustained animation loop. The real notch calendar panel was separately captured in `live/22_real_notch_calendar_open.png`. The final UI test confirmed Calendar opening on click and closing on pointer exit. A separate 2 Hz top-region audit shows four expanded intervals in raw segment 008 (around 104.5–106.5,109.5–111.5,114.5–116.5 and119.0 seconds), with the last crossing into segment 009 to about 1.0 s. See `live/pointer_phase_top_region_samples.json`; this supports the four-cycle log without treating the whole 65-second window as active animation.

‡ Earlier volume loop began17:03:20.569 PDT and lasted about 32 s; the table uses an inner29 s window. The Sound-HUD baseline is visible in screenshot 11. A later volume-input attempt17:13:49.583–17:14:21.194 did not conclusively establish a visible HUD; it is **not substituted for a verified HUD workload**. Its partial measurements are retained in `perf/summary.json` as `volume_inputs_unconfirmed_hud`.

**OBSERVED / limitation:** GPU ms/s and package-idle wakeups were0 in all these VM task samples. That does **not** prove Alcove consumes no GPU or package energy on real hardware. Process interrupt wakeups and CPU remain useful within this VM. top's idle0.0% is rounding: powermetrics still resolved0.166 CPU ms/s on average (~0.0166% of one core).

#### Memory growth and snapshots

**OBSERVED:** RSS rose131.20 →156.64 MiB (**+25.44 MiB**, +19.39%) in20.5 minutes; maximum157.33 MiB. Most of the first jump occurred in the first 30 s (to 148.47 MiB), and later workload steps were non-monotonic. This alone is **not evidence of a leak**. Process identity is stable, so the series is not stitched across restarts.

| Elapsed | UTC | RSS MiB |
|---:|---|---:|
| 0.0 min | 23:51:53 | 131.20 |
| 0.5 min | 23:52:23 | 148.47 |
| 5.0 min | 23:56:53 | 152.14 |
| 10.0 min | 00:01:53 | 150.61 |
| 15.0 min | 00:06:53 | 156.50 |
| 20.0 min | 00:11:53 | 156.17 |
| 20.5 min | 00:12:23 | 156.64 |

| Snapshot | Initial ~16:52 PDT | Final17:14 PDT |
|---|---:|---:|
| `vmmap` physical footprint | 64.3 MiB | 65.9 MiB |
| `vmmap` peak footprint | 68.0 MiB | 74.0 MiB |
| Writable regions resident | 55.0 MiB | 62.1 MiB |
| Writable regions written | 45.8 MiB | 52.9 MiB |
| `footprint` rounded total | 64 MB | 66 MB |
| `sample` physical footprint | 64.3 MiB | 65.8 MiB |

RSS, shared-library residency, physical footprint and malloc allocation are **different accounting views**. The apparent25 MiB RSS growth should not be conflated with the ~1.6 MiB before/after physical-footprint difference. `vmmap` totals also include shared mappings. Raw sample call graphs, including AppKit/CFRunLoop waits, are supplied; no single hot function was established from an idle snapshot.

`perf/growth_rss.png`, `growth.jsonl`, `growth_parsed.json`, `summary.json` and both original/extension workload logs preserve these measurements. `scripts/summarize_perf.py` computes the tables. Extensions overlap briefly; parsing de-duplicates per-second timestamps using the later collector. No outliers were silently deleted.

#### Launch latency

**OBSERVED:** After the 20.5-minute series and final snapshots completed, PID 3840 was quit and confirmed absent. A separate visible monotonic-clock helper issued one NSWorkspace launch request at **2026-10-12 00:19:29 UTC** (17:19:29 PDT), creating **PID 7236**. No onboarding reset or Alcove modification was involved.

| Measurement | Result | Evidence |
|---|---:|---|
| Process-cold, warm-filesystem request → first visible notch | **approximately 1.02 s** | Raw segment012 adjacent frames 3383/3384 |
| Last frame with no notch | Clock1.006 s, sourcePTS59.467 s | `live/cold_before_first_notch_3383.png` |
| First frame with notch | Clock1.021 s, sourcePTS59.483 s | `live/cold_first_notch_3384.png` |
| NSWorkspace open completion | 0.0580 s | `live/COLD_LAUNCH.log`; **not** visual launch latency |
| Reboot-cold / uncached launch | UNVERIFIED | No reboot/cache purge performed |

The source detector counts at least 20 pixels with gray<32 in x730..869,y0..31; frame 3383 has no notch and 3384 jumps to 4,001 dark pixels. Frame indices are zero-based passthrough decoder indices, not synthetic constant-rate duplicates. The adjacent visible-clock readings give an observed bracket of **1.006–1.021 s**, not a guarantee of sub-frame precision or an uncached-launch benchmark. Use actual sourcePTS: the recording contains timestamp gaps, so `frameIndex/60` is not a valid global time conversion. The helper timer and screen renderer also have scheduling latency. The initial incorrect duplicate-frame extraction was discarded; only passthrough-decoded3383/3384 evidence is included. See `live/COLD_FRAME_TRANSITIONS.json`, `live/LaunchClock.swift` and the final UI report.

**Residual uncertainty:** Now Playing-active performance was not established in this bounded session; the separate waveform investigation is not substituted for measurement here. No supported Now Playing producer was established and visibly confirmed in Alcove during the bounded setup, so a local audio process alone is not counted as that state. Real GPU power, battery drain, thermal throttling, >20.5 min leak trends and equivalent workload costs on a notched laptop remain UNVERIFIED. The table attributes CPU/energy only to Alcove, not all compositor or host-VM overhead.


### 14. Multiple displays

#### Static selection and lifecycle

**STATIC:** DisplayType cases are `builtInDisplay`, `mainScreen`, `allDisplays`, `specificDisplay`. Preferences are `showOnDisplay`, `showOnDisplayUUID`, with `showOnDisplayName` / `showOnDisplaySymbol` for display-picker presentation. Notch coordination uses a `controllersByDisplayUUID` collection.

**STATIC:** The resolver at `0x100244a10` implements the cases:

| Case | Recovered selection |
|---|---|
| Built-in | `0x10020c174` enumerates NSScreen.screens, obtains NSScreenNumber from deviceDescription, returns the screen satisfying `CGDisplayIsBuiltin` (`0x10020c340`) |
| Main | `0x10020c690` calls `CGMainDisplayID` (`0x10020c6b0`) and matches it to NSScreenNumber, rather than using the active window's screen |
| All displays | Enumerate NSScreen.screens (`0x100244ad0`) and create the UUID selection list |
| Specific | Read saved UUID and search current screens via `0x10020c8d8` (`0x100244d14`) |

The main-display choice is therefore based on the menu-bar/main-display identity; **it should not be implemented as “follow whichever app currently has focus”** on the evidence here. If a requested built-in/specific screen is missing, this resolver returns an empty result instead of visibly substituting another in this function; higher-level lifecycle behavior is checked separately below.

**STATIC:** ScreenManager subscribes to `NSApplicationDidChangeScreenParametersNotification` (`0x10020817c`), as well as screen sleep/wake and active-Space notifications. There is explicit screen/UUID synchronization, rather than a one-time hard-coded NSScreen.main lookup.

#### Synthetic second-display experiment

**OBSERVED:** A local Objective-C CGVirtualDisplay helper supplied a real second NSScreen to macOS; this is a synthetic display, not a physical monitor. The picker offered Main display, All displays, Apple Virtual, and Alcove Synthetic Display.

| Selection / lifecycle | Primary Apple Virtual | Synthetic secondary | Evidence |
|---|---|---|---|
| Main display | Notch present | No notch | `live/14_main_only_primary.png`, `14_main_only_secondary.png` |
| All displays | Notch present | Notch present | `live/15_all_primary.png`, `16_all_secondary.png` |
| Alcove Synthetic Display | No notch | Notch present | `live/17_specific_primary_absent.png`, `18_specific_secondary_visible.png` |
| Unplug while specific target selected | No fallback notch | Disconnected | `live/19_unplug_specific_no_fallback.png` |
| Replug same synthetic target | Still secondary selection | Notch recovers | `live/20_replug_id4_retains_target.png`, `21_replug_secondary_recovered.png` |

The transient display ID changed 3 → 4 on replug, while Alcove recovered the selected target. **INFERRED, supported by STATIC UUID code:** target persistence is not merely the transient CGDirectDisplayID. The first test helper exited during unplug because of its own NSWindow ownership bug; the helper was corrected, and the final disconnect cleanly reported one screen. This was not an Alcove crash. Main display was restored and helpers stopped before the bounded performance phases.

**Evidence:** `static/fn_100244a10.txt`, `static/fn_10020c174.txt`, `static/fn_10020c690.txt`, `static/fn_10020c8d8.txt`, `static/fn_100208000.txt`, `static/fn_10034bf7c.txt`, `live/VirtualDisplay.m` and lifecycle evidence.

**Residual uncertainty:** CGVirtualDisplay is a synthetic test surface, not a physical built-in notched panel. Physical unplug timing, sleep/lid closure, mirroring, mixed refresh rates, real notch exclusion geometry and three-or-more display behavior remain UNVERIFIED.

### Reproduction and archive map

- `static/`: scoped disassembly, field/asset inventories, plist/dictionary, updater response.
- `sounds/`: all 13 waveform PNGs and measurement JSONs.
- `live/`: test report, synthetic sources, screenshots, 60 fps clips/frame strips and event logs.
- `perf/`: raw top, powermetrics, footprint, vmmap, sample and long-run records, plus computed tables.
- `scripts/`: measurement and evidence-processing scripts; no credential-bearing scripts.

The archive deliberately excludes full app binaries, bulk licensing disassembly, account credentials, trial/license preference values, and license-route payload analysis. Excerpts preserve the addresses needed to reproduce the non-license findings from the public build.

### Evidence navigation and recording limits

The accompanying ZIP includes `README.md` and `MANIFEST.sha256`, scoped static dumps, every measured sound/resource/waveform, synthetic helper source/bundles, UI screenshots, raw performance logs and reproducible analysis scripts.

- `live/raw_capture_segments/`: **13 losslessly remuxed raw capture segments**, preserving the source video bitstream without visual re-encoding. Nominal rate 60 fps; 93,285 decoded frames across 1,586.934 seconds, about 58.78 fps over the full recording. Source frame-rate metadata alone is not proof of perfect 60 Hz capture; timestamp gaps exist, especially in the initial segment.
- `live/video_inventory.json`: original raw filenames/SHA-256 hashes, FFprobe counts/durations and sampled timestamps. The original Matroska containers were remuxed to MP4, not flattened to artificial constant-rate timing.
- `live/frame_strips/`: one four-frame contact strip per source segment, labelled with source clip and local seek time. Full-resolution pixels remain in the clips; strips are overview aids, not pixel-accurate measurement images.
- `live/01_...png` through `live/23_...png`: full uncropped desktop captures of key assertions. Secondary-screen captures are their own full synthetic desktop, not cropped primary screenshots.
- `perf/`: all measurements and computed summaries; `growth_rss.png` plots the full 20.5-minute RSS series.

A redundant separate FFmpeg/AVFoundation recorder stalled during startup and produced no usable parallel file. The successful primary recorder's raw source is retained in the MP4 segments above. Its annotated presentation may slow around test annotations; use **raw frame PTS and the visible launch clock**, not the annotated player's elapsed time, for timing claims. No audio track was captured in this screen recording; source-file audio measurements and playback call sites must not be mistaken for a live microphone/SPL test.


---

# Part I: v4 live tests: Spotify explicit badge and cycle-activity swipe thresholds

_Source: `children/H_v4/alcove_v4_spotify_cycle.md`. Evidence lives in `children/H_v4/`._

## Alcove v1.7.7 — Task A (Spotify explicit badge) and Task B (cycle-activity swipe threshold)

Labels: **OBSERVED** = seen live on this VM, **STATIC** = from the binary (given in the brief), **INFERRED** = derived from observations, **UNVERIFIED** = not established.

### 0. Setup notes (all OBSERVED unless noted)

| Item | Value |
|---|---|
| Alcove | 1.7.7, bundle `com.henrikruscon.Alcove`, trial started through the normal UI (License page: Trial, ~2 d remaining at 09:39). No purchase/patch/update. |
| Host | macOS 26.6.2 (25G83), arm64 VM, display 1600×1200 non-Retina (1 pt = 1 px), no physical notch. `forceSimulatedNotch = 1`. Wallpaper `/System/Library/Desktop Pictures/Solid Colors/Silver.png`. |
| Permissions | Accessibility (System Settings), Calendar, Automation for Spotify + Music (Alcove only started showing Now Playing after the Apple Events prompt was allowed and Alcove restarted). No sudo-only or Accessibility-API hacks beyond granting Alcove itself. |
| Alcove settings | Force simulated notch ON; Now Playing badge style "Explicit" selected (was the default/selected option). |
| Audio | `blackhole-2ch` + `switchaudio-osx`, output = `BlackHole 2ch`; playback progresses. |
| Spotify | `Spotify.dmg` is x86_64 only ("Bad CPU type", no Rosetta) → installed `https://download.scdn.co/SpotifyARM64.dmg` (arm64). Free account `nico.jaffer2@gmail.com` created in Safari; the user solved the reCAPTCHA; no e-mail code was requested afterwards. Password only in chat. Free tier plays ads (visible in B4/A4). |
| Second activity | Calendar events via AppleScript (`Alcove Bench Meeting` 10:05–10:50, then `Alcove Bench 40/70/100/130`, 20 min each). Alcove shows a red countdown (`15m…1m`, then `58s…`) when the next event is < ~15 min away and a red progress ring while an event is in progress. |
| Capture | `ffmpeg -f avfoundation -framerate 60 -capture_cursor 1 -i "0:none" -c:v libx264 -preset ultrafast -crf 18`. Clip↔gesture sync: the gesture CLI moves the pointer to the notch 150 ms before the first scroll event, so the cursor jump in the video marks each gesture (`cursor_notch` feature); residual error ≤ 1 frame. |
| Gesture CLI | `src/swipe.swift`: CGEvent scroll-wheel events, `kCGScrollWheelEventIsContinuous=1`, `scrollPhase` began/changed/ended, pixel deltas; optional reverse leg and third leg. Default 12 steps × 8 ms; "slow" variant 40 steps × 4 px × 40 ms. `src/mv.swift` parks/clicks the pointer. |

Coordinates below are screen pixels (origin top-left of the 1600×1200 display). Notch (compact, Now Playing) spans ≈ x 690–915, height ≈ 37 px.

### 1. Task A — explicit badge via Spotify

#### 1.1 Does the badge appear?

**Yes (OBSERVED).** With Spotify playing a track Spotify marks "E", Alcove renders a small filled square with a knocked-out "e" (SF Symbol `e.square.fill` per STATIC) immediately after the title. Explicit tracks observed with badge: HUMBLE., LUST., DNA., Not Like Us, goosebumps, Mask Off, United In Grief, The Box (Roddy Ricch). Clean control: Shape of You (Ed Sheeran) → **no badge (OBSERVED)**, same layout.

| State | Badge | Evidence |
|---|---|---|
| Compact notch (art left, waveform right) | **No** (OBSERVED) | `clips/A1_humble_states.mp4`, `frames/B1_ref/sheet2x.png` |
| Hover (pointer on compact notch) | **No** (OBSERVED) — hover does not change the compact content | A1 clip |
| Expanded Now Playing (click notch) | **Yes** (OBSERVED) | `frames/A1_exp/f0010.png`, `frames/badge_crop_1x.png`, `frames/badge_zoom6x.png`, `clips/A2_expanded_trackchanges.mp4` |
| Expanded split layout (Now Playing + Calendar side by side) | **Yes** (OBSERVED) | `frames/A3/split_humble_E.png` vs `frames/A3/split_shapeofyou_clean.png`, `frames/B1_ref/g100_down40_10fps.png` |
| Quick Peek (track change while Now Playing not on screen; "♪ HUMBLE. · Kendrick Lamar" text strip) | **No** (OBSERVED), text only, visible ≈ 3.0 s | `frames/A1_qp_humble/`, `frames/A1_qp_lust/`, `screens/qp_lust.png` |
| Lock-screen widget (Ctrl+Cmd+Q) | **Yes** (OBSERVED), white variant | `clips/A4_lockscreen.mp4` (t ≈ 12–29 s), `frames/A4/widget_sheet_2x.png`, `frames/A4/lockscreen_widget_badge_3x.png`, `screens/lockscreen_widget_computer.png` |

#### 1.2 Geometry and colour (expanded Now Playing, `frames/A1_exp/f0010.png`, crop origin screen x450,y0) — OBSERVED

| Measure | Value |
|---|---|
| Badge bounding box | x 785–796, y 31–42 → **11 × 11 px incl. anti-aliasing; solid core 9 × 9 px** (x 786–794, y 33–41) |
| Fill colour | (116,116,120) #747478 at all four interior corners; (117,117,122) on right edge; i.e. ~45 % grey, slightly blue |
| Glyph ("e") | knocked out to the panel background: centre pixel (31,31,33); background (0,0,0) |
| Horizontal position | 5–6 px right of the title's last glyph (title "HUMBLE." ends at x 779) |
| Vertical position | top aligned with the title's cap-top (title cap rows y 32–41, cap height 10 px); badge bottom 1 px below the baseline. Artist line ("Kendrick Lamar", grey (110,110,112)) starts 6 px below the badge bottom (y 48–57) |
| Title colour / weight | (252,252,252), ~13 pt semibold (INFERRED from cap height 10 px) |
| Scaling | title row is centred-left in the expanded panel; badge x follows the title width: 784 → 797 → 807 → 782 across four titles (template match, `csv/A2_badge_template_match.csv`) |

Lock-screen widget (`frames/A4/widget_t15.png`, crop origin 620,775; `csv/lock_badge_measure.txt`) — OBSERVED: badge **11 × 11 px**, fill **(252,252,252)** white (same as the title), glyph knocked out to the widget grey (164,164,164), **4 px** after the title's last glyph, top aligned to the title cap rows (y 812–822 screen). The badge therefore uses the label's foreground colour (grey secondary in the dark expanded panel, white on the lock screen) — INFERRED.

#### 1.3 Animation / timing on track change — OBSERVED (A2, 60 fps, template match NCC ≥ 0.75)

- The badge has no animation of its own; it is part of the title row and crossfades together with the title. Template match loses the badge for **5, 4 and 6 frames (67–100 ms)** at the three track changes (frames 515–519, 826–829, 1135–1140 of `clips/A2_expanded_trackchanges.mp4`) and it reappears at the new x position; no slide, scale or pop.
- Quick Peek shows no badge at any frame of the ~3 s strip.
- Lock-screen widget: title crossfade with a blur (visible at `frames/A4/widget_t19.png`), badge appears with the title.

#### 1.4 What Spotify exposes (OBSERVED)

- Spotify's AppleScript dictionary (`sdef /Applications/Spotify.app`) has **no explicit/content-rating property**; `track` exposes name, artist, album, `spotify url`, popularity, duration, track number, played count, starred, disc number, album artist, id, artwork url. `get properties of current track` fails with `-10000`; individual properties work (`csv/spotify_applescript_current_track.txt` shows the failure captured while an ad was the current track).
- Alcove still shows the badge, so it must obtain the flag another way (STATIC background: `kMRMediaRemoteNowPlayingInfoIsExplicitTrack` or Spotify Web API `explicit`); which of the two was active here is **UNVERIFIED**.
- The Spotify app itself shows "E" next to the same tracks (visible in the Spotify window in `frames/A4/lock_full.png` / screenshots).
- Caveat: "TORE UP" (Don Toliver) showed no badge on the lock screen but also had no artwork (incomplete metadata right after an ad) → **UNVERIFIED** for that track.

### 2. Task B — cycle-activity swipe threshold

#### 2.1 What the gestures do (compact notch, two activities: Now Playing + Calendar) — OBSERVED

Compact shows **one activity at a time** (Calendar: calendar glyph left + red countdown/ring right; Now Playing: artwork left + waveform right). Gesture model (INFERRED from 900+ logged gestures, consistent with every sweep):

| Gesture (compact) | Effect |
|---|---|
| Swipe **up** ≥ threshold | **dismisses the visible activity**; the other activity fades in → this is the activity cycle. If the other one is already dismissed the notch becomes empty and stays empty (Now Playing stayed hidden > 6 min). |
| Swipe **down** ≥ threshold, while an activity is dismissed | **restores the dismissed activity** (cycle back). |
| Swipe **down** ≥ threshold, nothing dismissed | **expands** the notch (split layout; auto-closes ≈ 0.2–0.5 s after the pointer leaves). |
| Swipe **left / right** | **previous / next track** (⏮ / ⏭ glyph flashes at the notch's left/right edge for ≈ 0.3–0.5 s), even while the Calendar activity is the one displayed. |
| Expanded panel, swipe **down** | switches the expanded content Now Playing → Calendar page (cycle inside the expanded view). |
| Expanded panel, swipe **up** | closes the panel. |
| Expanded panel, swipe **right** | next track. **left**: no visible change (Spotify "previous" restarts the current track when > 3 s in) → UNVERIFIED. |

#### 2.2 Threshold table

Fast gestures (12 steps × 8 ms ≈ 100 ms total) unless noted. "n/3" = successes out of 3 repeats.

| Gesture / state | Start state | 0/3 up to | Partial | 3/3 from (min reliable) | Source |
|---|---|---|---|---|---|
| **Cycle: up** (dismiss visible → other shown) | Calendar visible | 30 px | **35 px: 2/3** | **40 px** (3/3 at 40,45,50,55,60,65,70,80,100,120,160) | B2 `test_up` (OBSERVED) |
| Cycle: up, Now Playing visible | Now Playing visible | 35 px (0/3) | – | 40 px (fired on first try; later ups acted on an empty notch) | B1 (OBSERVED) |
| **Cycle back: down** (restore dismissed) | Now Playing visible, Calendar dismissed | 30 px | **35 px: 2/3** | **40 px** (3/3 at all 11 distances 40–160) | B2 `test_down` (OBSERVED) |
| Restore via down 120 px | same | – | – | 117/117 | B2/B3 `restore` (OBSERVED) |
| **Expand: down** (nothing dismissed) | Calendar visible | 30 px | 35 px: 1/3 | **40 px** (3/3 at every 5 px step 40–160) | B1 (OBSERVED) |
| **Track prev: left** | Calendar visible | 65 px | **70 px: 2/3** | **75 px** (3/3 at every 5 px step 75–160) | B1 (OBSERVED, `frames/B1_compact_left_skip_sheet.png`) |
| **Track next: right** | Calendar visible | 65 px | **70 px: 2/3** | **75 px** (3/3 at every 5 px step 75–160) | B1 (OBSERVED, `frames/B1_compact_right_skip_sheet.png`) |
| Slow-gesture fire point (4 px / 40 ms) | – | – | – | up/down: first visible fade at 40 px travelled; left ⏮ at 72–80 px; right ⏭ at 60–68 px (one 4 px step + 2–3 frames render latency resolution) | B3 `slow_*` (OBSERVED) |
| **Expanded: up (close)** | expanded | 100 px (0/2 each 20–100) | – | **110 px** (2/2 at 110–160, 10 px steps) | B4 (OBSERVED) |
| **Expanded: down (cycle page NP → Calendar)** | expanded | 70 px (0/2 each 20–70) | – | **80 px** (2/2 at 80–160) | B4 (OBSERVED) |
| **Expanded: right (next track)** | expanded | 30 px | – | **40 px** (2/2 at 40–160) | B4 (OBSERVED) |
| Expanded: left | expanded | – | – | no visible change 20–160 | B4 (UNVERIFIED, see 2.1) |

Unreliable band: **35 px** for cycle / cycle-back / expand (2/3, 2/3, 1/3); **70 px** for track skip (2/3 both directions). Everything ≥ 40 px (vertical) and ≥ 75 px (horizontal) fired 3/3 at every tested distance up to 160 px; no upper bound where the gesture stops firing was seen (OBSERVED).

Compared with STATIC background values: swipe-to-open 35 px / dismiss 35 px / close expanded ≈ 105 px / track skip ≈ 80 px — the live boundaries are 35→40, 35→40, 100→110 and 70→75 px respectively, so `cycleActivitySwipeSuccessThreshold` is **INFERRED to be the same ≈ 35–40 px value as the vertical dismiss/open thresholds in the compact notch**, and ≈ 70–80 px for the page switch inside the expanded view.

#### 2.3 Reset threshold (reversing mid-gesture) — OBSERVED (B3 `test_reset`, Calendar visible)

Gesture: up 30 px (sub-threshold) → reverse down R px → up 30 px again, all in one phase-began…ended gesture.

| R (px reversed) | 0 | 5 | 10 | 15 | 20 | 25 | 30 | 40 | 50 |
|---|---|---|---|---|---|---|---|---|---|
| cycled? | 3/3 | 3/3 | 3/3 | **1/3** | 0/3 | 0/3 | 0/3 | 0/3 | 0/3 |

Control: up 30 px alone → 0/3. Conclusion: reversing by **≥ 15–20 px resets the accumulated distance** (reset threshold ≈ 15 px, between 10 and 20) — INFERRED. A pure net-distance model is rejected (R = 15 would leave 45 px > 40 px and should fire 3/3).

Reversing **after** the threshold has been crossed does not undo the action: up 60 px then back 0–60 px → 27/27 cycled (B2 `test_rev`); the action fires mid-gesture as soon as the threshold is crossed (OBSERVED).

#### 2.4 Cycle transition timing (60 fps, `frames/B3_slow_up_r1_60fps.png`, `frames/cycle_transition_strip.png`) — OBSERVED

Slow up gesture (4 px per 2.4 frames), frame 0 = first scroll event:

| Phase | Frames | Time |
|---|---|---|
| Threshold crossed (40 px travelled) | 24 | 0.40 s |
| Old content fades out (opacity, slight shrink) | 24–31 (7 frames) | 117 ms |
| Empty notch (no content), notch width at the empty width | 32–59 (28 frames) | 467 ms |
| New content fades in | 60–71 (12 frames) | 200 ms |
| Settled | ≈ 72 | **≈ 48 frames / 0.80 s from fire to settled** |

Same numbers for the down (restore) direction (`frames/B3_slow_down_r1_60fps.png`, `frames/cycle_transition_strip_down.png`). Notch width goes Calendar 185 px → empty 151 px → Now Playing 169 px (and the reverse), i.e. shrink-then-grow through the empty width; **no spring overshoot was visible (0 % overshoot, width monotone in each half)** (OBSERVED; `csv/B3_reset_slow_timing.csv` columns `w_pre/w_extreme/w_post`). Fast (100 ms) gestures show the same fade/blank/fade sequence starting ≈ 0.4–0.6 s after the gesture (blank starts ≈ 43–48 frames after the pointer arrives, B2 `blank_start`).

Expanded page switch (down in expanded): content changes ≈ 0.5–1 s after the gesture; not frame-timed (UNVERIFIED timing).

#### 2.5 Distinguishing cycle from track-skip and expand/close — OBSERVED

- Cycle = vertical, compact, 40 px, visible as fade-out → empty notch → fade-in of the other activity, width changes to the other activity's width.
- Expand = vertical down, compact, 40 px, only when no activity is dismissed; panel grows to the 624×320 window (split layout); auto-closes after the pointer leaves.
- Track skip = horizontal, 75 px compact (40 px inside the expanded panel); ⏮/⏭ glyph flashes, artwork crossfades to the new track; no change of activity.
- Close = up 110 px inside the expanded panel.
- Hover alone never changed the compact content or expanded the notch; clicking the notch toggles expanded.

#### 2.6 Deviations from the requested protocol

- B1 ran the full grid (20–160 px, 5 px, 3×, 4 directions, compact) but without restoring state between gestures, so after the first successful up-dismiss the remaining up gestures acted on an empty notch. B2 therefore re-ran up/down with a state restore before every trial at 15 distances (20–70 in 5 px steps, then 80, 100, 120, 160; 3×). B4 (expanded) used 10 px steps × 2 repeats × 4 directions.
- Gestures were posted at (800,10) over the notch; in the expanded state at (800,60) inside the panel.

### 3. Evidence files (all under the zip root)

- `alcove_v4_spotify_cycle.md` — this report; `NOTES.md` — raw working notes with timestamps.
- Clips (60 fps, 1600×1200): `clips/A1_humble_states.mp4` (compact/hover/expanded/Quick Peek, 59 s), `clips/A2_expanded_trackchanges.mp4` (expanded, 3 track changes, 56 s), `clips/A3_clean_control.mp4` (Shape of You clean control + HUMBLE. in split layout, 141 s), `clips/A4_lockscreen.mp4` (lock-screen widget, 49 s), `clips/B0_explore.mp4` (4 exploratory 100 px gestures), `clips/B1_compact.mp4` (full compact grid, 348 gestures, 956 s), `clips/B2_cycle.mp4` (state-restored up/down + reverse tests, 279 gestures, 797 s), `clips/B3_reset_slow.mp4` (reset-threshold + slow gestures, 87 gestures, 295 s), `clips/B4_expanded.mp4` (expanded sweep, 120 gestures, 610 s).
- Key frames/strips: `frames/badge_crop_1x.png`, `frames/badge_zoom6x.png`, `frames/A1_exp/`, `frames/A1_qp_humble/`, `frames/A1_qp_lust/`, `frames/A2/`, `frames/A3/split_humble_E.png`, `frames/A3/split_shapeofyou_clean.png`, `frames/A4/widget_sheet_2x.png`, `frames/A4/lockscreen_widget_badge_3x.png`, `frames/A4/widget_t*.png`, `frames/A4/lock_full.png`, `frames/B0/*` (first semantics strips), `frames/B1_ref/sheet2x.png` (compact states reference), `frames/B1_ref/g100_down40_10fps.png` (expand), `frames/B1_compact_{up,down,left,right}_sheet.png` (pre/mid/post per gesture), `frames/B1_compact_{left,right}_skip_sheet.png`, `frames/B2_cycle_{test_up,test_down,test_rev,restore,prep_up}_sheet.png`, `frames/B3_reset_slow_*_sheet.png`, `frames/B3_slow_{up,down,left,right}_r1_60fps.png`, `frames/cycle_transition_strip.png`, `frames/cycle_transition_strip_down.png`, `frames/B4_expanded_{up,down,left,right}_sheet.png`.
- Screenshots: `screens/` (setup, Quick Peek, lock-screen widget, computer-tool zooms).
- CSV logs: `csv/B0_explore.csv`, `csv/B1_compact.csv`, `csv/B2_cycle.csv`, `csv/B3_reset_slow.csv`, `csv/B4_expanded.csv` (one row per gesture: wall time, phase/state, direction, distance, repeat, reverse leg, CLI echo), `csv/*_features*.csv` (per-frame notch features), `csv/*_gestures*.csv` (per-gesture windows, cursor-synced onsets), `csv/B3_reset_slow_timing.csv`, `csv/A2_badge_template_match.csv`, `csv/lock_badge_measure.txt`, `csv/spotify_applescript_current_track.txt`.
- Sources: `src/swipe.swift` (gesture CLI), `src/mv.swift` (pointer park/click), `src/winfo.swift` (Alcove window bounds), `src/sweep.sh`, `src/sweep2.sh`, `src/sweep3.sh`, `src/sweep4.sh` (drivers), `src/features.py`, `src/features2.py`, `src/analyze.py`, `src/analyze2.py`, `src/strips.py`, `src/hsheet.py`, `src/timing.py`, `src/marker.py` (analysis).
