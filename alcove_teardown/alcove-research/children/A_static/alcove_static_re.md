# Alcove 1.7.7 (build 199) — Static Reverse Engineering Report (arm64 slice + AlcoveHelper.xpc)

Scope: `/Applications/Alcove.app/Contents/MacOS/Alcove` (arm64 slice thinned to `bin/Alcove.arm64`) and `AlcoveHelper.xpc` (`bin/AlcoveHelper.arm64`). Tooling: radare2 6.2.4 (`aaa`), custom Python Mach-O parsers (chained fixups, `__swift5_types/fieldmd/proto`), `xcrun swift-demangle`. Nothing license/trial related is covered beyond the public endpoints listed in NOTES.md.

Labels: **STATIC** = read from binary/resources (address given); **OBSERVED** = seen live on the VM (from lead NOTES.md / `defaults read`); **INFERRED** = deduction. Hardware not present on this VM (real notch, battery, AirPods, Touch ID, multiple displays): behaviour marked **UNVERIFIED**.

The binary is symbol-stripped: Swift function names are not available. Contexts were recovered two ways: (a) **STATIC** xrefs from a function to Swift field descriptors of a class (`field.class.Alcove.X`), and (b) **INFERRED** "nearest preceding `View.body` getter" using the 95 `SwiftUI.View` conformance witness tables recovered from `__swift5_proto` (`view_bodies.json`); SwiftUI closures are emitted directly after their body function, so this heuristic is usually right but not guaranteed. Note: hits on `MediaProgressLayerTrackView` and `LicenseManager` in column (a) are **noise** (radare2 flag collisions on shared addresses) and should be ignored.

Evidence files referenced below are in the attached zip (`alcove_static_re_evidence.zip`).

---

## 1. Animation constants

### 1.1 Method
- Call sites: `axt` on every SwiftUI animation import (`anim_xrefs.txt`, `anim_xrefs2.txt`): 578 `Animation.spring(response:dampingFraction:blendDuration:)` / `Spring(duration:bounce:)` / `Animation.spring(_:blendDuration:)` sites, 40 `easeOut`, 2 `easeInOut`, 1 `easeIn`, 2 `linear`, 14 `delay`, 2 `repeatForever`, 228 `withAnimation`, 13 `Transaction.animation`, 9 `PhaseAnimator`, 5 `TimelineView`, 8 `Clock.sleep`, 51 `Duration.seconds`.
- Constants: `parse_consts.py` walks the 28–90 instructions before each `bl`, materialising `mov/movk → fmov dN, xN`, `fmov dN, #imm`, `movi`, and literal-pool `ldr dN,[addr]` loads (read from the file). `?` = value comes from a register/variable (e.g. a Defaults speed setting) and could not be resolved statically.
- Full table (723 rows): **Appendix A** (`anim_table.md`).

### 1.2 Headline findings (STATIC unless noted)
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

## 2. Notch geometry

- **`NotchShape`** (STATIC, `fieldmd`): `struct NotchShape { let style: Style (.notch | .pill); var topCornerRadius: Double; var bottomCornerRadius: Double }`, animatable.
- **Path construction** (STATIC, `shape_funcs_annot.txt`, fn **0x1002670fc** = `NotchShape.path(in:)` for `.notch`): there are *no* `addQuadCurve`/`addArc` calls; the shape is three `Path.addRoundedRect(in:cornerRadii:style:.continuous)` calls:
  1. `r = min(bottomCornerRadius, 24.0, rect.height − …)` clamped (constants `fmov 0.5`, `24.0` at 0x1002671dc; `min(width/2, height)` guard) and stored at `self+8`; the main body rect uses `RectangleCornerRadii(topLeading: 0, bottomLeading: r, bottomTrailing: r, topTrailing: 0)` (0x100267234 → 0x1002672ac).
  2./3. Two shoulder "ears" of size `2r` (`fadd d12, d0, d0` at 0x100267218) placed at `minX − 2r` and `maxX`, filled with the inverse radii so the concave join between notch and menu bar is a continuous (superellipse) curve (0x100267380, 0x1002674a4). Max shoulder/bottom radius is therefore **24 pt**; `topCornerRadius` feeds the ear radius.
  - `.pill` style = fn **0x100267564**: single `addRoundedRect(cornerSize: min(w,h)/2, .continuous)` (capsule).
  - Fn **0x1001d1368** draws a rounded rect (cornerSize) + rounded-corner overlay for the HUD/background; the `RoundedTriangle`-style shape 0x1001789b0 (three `addArc(tangent1End:tangent2End:radius:)`) is a caret/play glyph, not the notch.
- **Sizes** (STATIC fields): `NotchController._notchWidth/_notchHeight/_notchExpandedWidth/_notchExpandedHeight: Double`, `_notchAdjustedWidth/_notchAdjustedHeight` (Defaults, default **0.0** = "use detected size"). `NotchView` keeps `_cutoutScale`, `_cutoutWidthProgress`, `_cutoutContentWidthProgress`, `_cutoutScaleAnchor` for the expand animation.
- **Real-notch detection / menu-bar height** (STATIC): `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea` are called from ~100 functions (`geo_xrefs.txt`), the cluster 0x1000b853c–0x1000b9564 being the screen-geometry helpers (ScreenManager): a real notch is assumed when both auxiliary areas are non-nil; notch width = screen width − leftArea.width − rightArea.width, height = leftArea.height (= menu-bar height). `forceSimulatedNotch` (Bool, default false) switches to the simulated size. The simulated closed size measured live was ≈140 px wide (OBSERVED, NOTES.md); the exact default constant lives in a register-initialised field and is **UNVERIFIED** statically.
- **Corner radius tasks**: `expandedCornerRadiusTask`, `expandedTransitionTask`, `progressiveBlurTransitionTask`, `backdropLumaTransitionTask` are `Task` fields on `NotchController` (STATIC) — radius changes are driven by async tasks, not a single `withAnimation`.

## 3. Gesture and timing thresholds

- STATIC fields of `struct NotchSwipes` (`fieldmd_demangled.txt`): `verticalSwipeSuccessThreshold`, `verticalSwipeResetThreshold`, `cycleActivitySwipeSuccessThreshold`, `cycleActivitySwipeResetThreshold`, `horizontalSwipeSuccessThreshold`, `horizontalSwipeResetThreshold` (all `Double`), plus flags `enableHaptics, swipeToSkip, enableNowPlaying, enableQuickPeek, enableCalendarQuickPeek, swipeToDismiss, swipeToCycleActivity, swipeToToggle`. `NotchSwipeMonitor` holds the scroll-wheel event monitor; a `CGEventTapCreate` call exists at 0x100134380 (fn 0x100134354, `eventtap_func.txt`) used only when Accessibility is granted (`AXIsProcessTrustedWithOptions` imported).
- The threshold literals are initialised in the `NotchSwipes` memberwise init from registers → values **UNVERIFIED** (not recoverable without symbols in the time available).
- Debounce/task fields on `NotchController` (STATIC): `notificationSwapDebounce, notificationCloseDebounce, notificationRestoreDebounce, liveActivitySwapDebounce, quickPeekDebounce, adjustDebounce, progressDebounce, swipeResetDebounce, quickPeekResetDebounce, visibilityDebounce, hoverDebounce (NotchView)`. Their sleeps are the `Duration.seconds` constants in §1.2 (0.05–0.5 s cluster; 0.275 and 0.475 are the odd ones at 0x1001e10bc / 0x100357370, both inside NotchController-adjacent code).
- `hoverDuration` Defaults key default **0.0** s (STATIC); `expandNotchOnHover` default **false**.
- Duration defaults driving auto-dismiss (STATIC, §5): `peekDuration` 2 s, `calendarPeekDuration` 4 s, `idleDuration` 3 s, `hideIdleDuration` 10 s, `batteryDuration` 5, `connectivityDuration` 5, `focusDuration` 5, `brightnessDuration` 1.5, `volumeDuration` 1.5, `timeToLeaveDuration` 8 (min), `timeToLeaveBuffer` 10 (min), `timeBeforeEvent` 15 (min).

## 4. Windowing (STATIC, `win_funcs_annot.txt`, `space_funcs_annot.txt`)

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

## 5. Defaults keys (sindresorhus/Defaults)

Method (STATIC): every `Defaults.Key` static initialiser calls `objc_msgSend$standardUserDefaults` (stub `fcn.100452a60`); its 136 callers (`stdud_xrefs.txt` → `defkeys_all.txt`) were parsed by `defkeys_parse.py`: the key name is a C string or an inline 15-byte Swift string, and the default value is the payload stored at `+0x10` of the captured box allocated just before the `Key` object. Bool defaults are exact; for 8-byte payloads the type is inferred (Double shown decoded; raw 0 is ambiguous between `0.0`, `0`, and the first enum case; non-zero small ints are enum raw values / Ints, e.g. `musicApp = 2` which `defaults read` shows as `system`).

Cross-check (OBSERVED, `defaults_after_settings.txt`): `enableBrightness=1, enableCalendar=1, forceSimulatedNotch=1, idleActivity=calendar, isFirstLaunch=0, musicApp=system, playSoundOnLowConnectBattery=1, warnOnLowConnectBattery=1, hasPrompted*=1` — all consistent with keys found statically (the OBSERVED values differ from defaults because the lead toggled them). Full table: **Appendix B** (`defaults_keys.md`).

Additional non-Defaults persistence: Keychain + `NSUbiquitousKeyValueStore` imports for settings sync (STATIC, NOTES.md).

## 6. Subsystems

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

## 7. Swift type / field map

Complete dump: `fieldmd_demangled.txt` (561 field descriptors, 549 types), `types_list.txt`, `conformances.txt` (993 conformances). Key types (STATIC):

- `class NotchController`: `_space: SpaceManager`, `windowController`, `backdropWindowController: NSWindowController`, `topEdgeGlobalMouseMonitor`, `topEdgeLocalMouseMonitor`, `swipeMonitor: NotchSwipeMonitor?`, debounces/tasks listed in §3, Defaults-backed `_hideFromScreenCapture, _forceSimulatedNotch, _notchAdjustedWidth, _notchAdjustedHeight, _enableFocus, _enableBrightness, _enableVolume, _enableCalendarQuickPeek, _showWeatherOnEmptyDay, _enableNowPlaying, _hideWhileSourceIsActive, _hideWhileInFullscreen, _enableQuickPeek, _enableLockScreen, _enableHaptics, _allowNowPlayingWidgetWhenLocked, _mostRecentActivity, _idleActivity: ExpandedActivity, _forceEnableActivity, _swipeToCycleActivity, _swipeToDismiss, _swipeToSkip, _swipeToToggle`, sizes `_notchWidth, _notchHeight, _notchExpandedWidth, _notchExpandedHeight`.
- `struct NotchView`: `notchController`, `_hoverDuration`, `_notchAdjustedWidth/Height`, `_expandNotchOnHover`, `_swipeToToggle/Dismiss/Skip`, `_contrastOutline`, `_hoverDebounce`, `_cutoutScale`, `_cutoutWidthProgress`, `_cutoutContentWidthProgress`, `_cutoutScaleAnchor`.
- `struct NotchShape` (§2), `struct NotchSwipes` (§3), `class NotchSwipeMonitor`, `class NotchPanel/NotchBackdropPanel/LockPanel: NSPanel` (`canBecomeKeyWindow` override), `class SpaceManager`, `class ScreenManager`, `HapticFeedback`, `SoundManager`, `WaveformSpectrumCenter/Session`, `WaveformAnimationClock/Source`, `NSWaveformView`, `NSMarqueeTextView`, `MediaProgressLayerTrackView`, `HUDSpeed`, `AudioManager.AudioFrequencyBand`, `ProgressiveBlurView`, `VariableBlurEngine`, `MaterialBackdropLumaReader`, `ClearGlassEffectView`, `ClearGlassBorderEffectView`, `MissionControlManager`, `CalendarManager`, `WeatherManager`, `MediaManager`, `VolumeManager`.
- Views with recovered `body` addresses (95): `DummyNotch` 0x100005dc0, `NotchView` (body 0x1001e426c), `NotchLiveActivitiesView`, `NotchNotificationsView`, `MediaPlayer`, `MediaControlStrip`, `MediaProgressSlider`, `ProgressSlider`, `Waveform`, `MarqueeText`, `SliderPicker`, `CircularProgress`, settings panes… (`view_bodies.json`).

## 8. Reproduction scripts (in zip)
`chained.py` (chained-fixup binds/rebases → `fixups.json`), `swift_meta.py` (`__swift5_types/fieldmd` → `fieldmd.json`, `fieldmd_dump.txt`), `proto_meta.py` (`__swift5_proto` → `conformances.txt`, `view_bodies.json`), `parse_consts.py` (FP immediates before call sites), `build_table.py` (Appendix A), `defkeys_parse.py` (Appendix B), `annot.py` (annotates `objc_msgSend$sel` stubs from `stubs.txt`), radare2 scripts `*.r2` and their outputs `*_dis.txt`, `*_funcs*.txt`, `*_xrefs.txt`.

## 9. Not recoverable / UNVERIFIED
Literal values for `NotchSwipes` thresholds, `alignmentSpring*`, simulated-notch default size, `seekerPollingInterval`, and the exact `CASpringAnimation` mass/stiffness/damping (register-sourced after stripping); real-notch, battery, AirPods, Touch ID, multi-display and lock-screen behaviours (hardware absent on VM).

---
## Appendix A — all animation call sites (STATIC)
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

## Appendix B — Defaults keys (STATIC)
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
