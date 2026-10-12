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
