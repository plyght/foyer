# Alcove 1.7.7 (build 199) — Gap-closing RE, area F (v2)

Binary: `/Applications/Alcove.app/Contents/MacOS/Alcove`, arm64 slice (`bin/Alcove.arm64`, SHA-256 `14520b5d…f653ec`), hardened runtime, Team `287NUTSP69`.
VM: macOS 26.6.2 (25G83), Apple Virtual display 1600×1200@1×, no notch / battery / AirPods / backlight / Touch ID.
Addresses are vmaddrs in the arm64 slice (same base as reports A/B/E). Tools: radare2 `aaa`, `otool -tvV` (full listing `ev/otool_text.txt`), custom `fieldmd.py` (Swift `__swift5_fieldmd` parser), `deobf.py` (obfuscated-string table decoder → `ev/deobf_strings.txt`, 276 records), ffmpeg/ffprobe, numpy, assetutil.

Evidence classes: **STATIC** (disassembly / metadata / resources), **OBSERVED** (seen on this VM), **INFERRED** (reasoned from static facts, not executed), **UNVERIFIED** (could not be established).

Overall VM caveat (OBSERVED): in this session Alcove never left onboarding — it is parked at the Accessibility step with a System Settings "Privacy & Security is trying to modify your system settings" auth sheet (`ev/lock/after_unlock.png`); `osascript` System Events returns `-25211 not allowed assistive access`, so neither the Accessibility toggle nor the Audio-Capture add-app flow could be scripted, and `defaults read com.henrikruscon.Alcove` shows only onboarding keys (`ev/shots/00_launch.png … 17_onb.png`). Everything "live" below is therefore bounded by that, exactly as instructed (document and move on, no retries).

---

## 1. Live waveform  (priority)

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

## 2. Swipe thresholds

**Answer (STATIC partial, runtime BLOCKED):** The six `NotchSwipes` stored properties exist (fieldmd `0x100531924 verticalSwipeSuccessThreshold`, `0x100531930 verticalSwipeResetThreshold`, `0x10053193c cycleActivitySwipeSuccessThreshold`, `0x100531948 cycleActivitySwipeResetThreshold`, `0x100531954 horizontalSwipeSuccessThreshold`, `0x100531960 horizontalSwipeResetThreshold`; type descriptor `0x100517158`, metadata pointer stored at `0x100595790`, referenced only from data `0x10058bcf8`). No code ADRPs the descriptor (`grep` of `adrp 0x100517000` + `add #0x15x` in the full listing: none) → the struct is built by generic/inlined initialiser and the literals are **register-sourced from the caller as report A said**. The gesture-progress functions that consume them carry their own constants: `0x1001c4094` (12.0, 30.0, ×0.75) and `0x1001c613c` (12.0, 40.0) with `_gestureVerticalScroll` ivar `0x1005d3ed0`, `_isExpanded` `0x1005d3dc0` (`ev/sw_*.txt`). Measured (report B): toggle ≈35 px (−34 no / −36 yes), dismiss ≈35, close-expanded ≈105, skip ≈80, cycle once at +100 — consistent with "30 + hysteresis(12) ×0.75"-style maths but **the six exact literals remain UNVERIFIED**.
**Runtime read blocked:** `lldb -p <Alcove>` → `attach failed: Not allowed to attach to process`. Causes: CodeDirectory flags `0x10000(runtime)` (hardened runtime), no `com.apple.security.get-task-allow`, `csrutil status: enabled`. Re-signing/SIP-off would violate the no-bypass rule → not attempted.

## 3. Haptics

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

## 4. Brightness HUD

**Answer (STATIC + OBSERVED):** Gate fn ≈`0x1001197cc`: display id → `DisplayServicesCanChangeBrightness` @`0x100119830`; `cbz w0 → 0x100119af8` (skip registration). Otherwise `DisplayServicesRegisterForBrightnessChangeNotifications` @`0x100119870`. `CGDisplayIsBuiltin` additionally gates at `0x10011970c`, `0x100118e70`, `0x10011aab0`, `0x10011cc2c`; display picker `0x1001226xx–0x100122f50` calls CanChangeBrightness per display and `DisplayServicesGetBrightnessIncrement` @`0x100122f50`. **Why no HUD on VM (OBSERVED):** Apple Virtual display is not built-in and `DisplayServicesCanChangeBrightness` returns 0 → the brightness observer is never registered. Keys (STATIC, report E + this pass): NX system-defined subtype 8, brightness up/down = keys **2/3**, keyboard-illumination up/down = **21/22**; step 1/16 (0.0625), Shift+Option fine step 1/64 (modifier mask `0xa0000`). Shared view (STATIC): the Display HUD is the same `HUD` progress view as Sound (settings "Display: duration 1.5 s, style White/Accent/Glow, Speed Smooth/Fast/Instant, show percentage, hide label" mirror Sound), `.levelChange` haptic path `0x100141708` is shared → **volume HUD timings transfer**. Bar step count: 16 steps (1/16) normal, 64 fine — matches macOS; INFERRED from the increment constants, no visual capture possible.

## 5. Battery / low-power UI

**Answer (STATIC, assets OBSERVED):** View struct `Alcove.Battery` (`0x1005187cc`; props `level`, `lowBatteryThreshold`, `showPercentage`, `isLowPowerMode`, `symbolReduction`) + `BatteryManager` (`0x1005cf2e8`; `_batteryDuration`, `_notifyOnLowPowerMode`, `_warnOnLowBattery`, `_lowBatteryThreshold` default **10.0**, `_playSoundOnLowBattery`, `_allowBatteryWhenFocused/Locked`, `_batteryLevel`, `_wasOnBattery`, `_isLowPowerModeEnabled`, `_hasPassedThreshold`, `_hasRecentlyChangedPowerSource`, `_remainingTime`) and `BatteryHelper` (IOKit `AppleSmartBattery`; errors `connectionAlreadyOpen`, `serviceNotFound`). Colours from `Assets.car` (`ev/assets_info.json`): **ChargingColor sRGB (0.553,0.922,0.573) ≈ #8DEB92**, **LowBatteryColor (0.980,0.388,0.459) ≈ #FA6375**, palette AlcoveGreen #4ADE80, AlcoveAmber #F59E0B, AlcoveAmberBright #FBC337, AlcoveOrange #FB923C, AlcoveRose #F43F5E, AlcoveCoral #F28C61, AlcoveEmerald #10B981. Thresholds: red when `level ≤ lowBatteryThreshold` (10 %), green while charging/full; **no separate yellow threshold literal found** (amber is used by low-power mode: INFERRED — `isLowPowerMode` is a Battery prop and AlcoveAmber is the only unexplained palette entry). Bolt: no bolt image in the catalog → SF Symbol (`bolt.fill`, `symbolReduction` prop controls symbol scaling) — INFERRED. Strings: "Charging", "Low Battery", "Low Power"; display duration 5 s; sounds `low-power.caf` 0.672 s, `low-battery.caf` 1.096 s. Layout/animation: UNVERIFIED (no battery on VM; SwiftUI body not statically recoverable). Asset renders: `ev/assets_info.json` + lock/swipe glyph PNGs in `ev/assets/`.

## 6. AirPods resources

**Answer (OBSERVED on files, mapping STATIC):** 15 bundled MP4s (no .usdz/.scn/.mov): `airpods-3`, `airpods-4`, `airpods-pro`, `airpods-pro-2`, `airpods-pro-3`, `airpods-max-{blue,green,midnight,orange,purple,red,silver,sky-blue,space-gray,starlight}`. Every file: H.264, **96×96, 60 fps, 360 frames = 6.000 s, no audio** (`ev/airpods/probe.txt`). Product-ID map (report E table): `2013`→airpods-3; `201b/2019`→airpods-4; `200e`→airpods-pro; `2014/2024`→airpods-pro-2; `2027`→airpods-pro-3; `200a/201f/202d`→airpods-max-<color> (colour chosen from device colour); `2002/200f` (AirPods 1/2) → no dedicated file, falls back to airpods-3 (INFERRED). Loop points (`ev/airpods/loop_analysis.txt`): no in-file loop markers; non-Max clips return closest to frame 0 at frame 359 → seamless file-boundary loop at 6.000 s; Max clips are ~symmetric about frame 180 (rotate out / back). Frame strips for all 15: `ev/airpods/*_strip.png`.

## 7. Explicit badge

**Answer (STATIC):** Key = **`kMRMediaRemoteNowPlayingInfoIsExplicitTrack`** (string @`0x10036d808`), plus Spotify Web-API fallback `content_ratings`/`explicit` (`0x10036d1d0`). Settings: Explicit badge None / Explicit / Format (default Explicit); glyph is SF Symbol **`e.square.fill`** (settings AX dump) — no catalog asset. Size/placement: UNVERIFIED (SwiftUI; not recoverable from constants with confidence). Live trigger: not attempted — Alcove never reached a configured state on this VM; `MRMediaRemoteSetNowPlayingInfo` is also hardened against third-party callers on macOS 26 → UNVERIFIED.

## 8. notchAdjustedWidth / notchAdjustedHeight

**Answer (STATIC):** Geometry fn `0x100238df8` (callers `0x100233518`@`0x1002335a4`, `0x10035ac84`@`0x10035ad84`) **does not read the adjusted values at all**. It only consults `NSScreen.auxiliaryTopLeftArea/auxiliaryTopRightArea` (`0x100238e28/e4c`, `CGRectIsEmpty` `0x100238ee8/ef8`) and returns 4 doubles:
- no notch areas (simulated-notch path): `d0=74, d1=19.5, d2=321, d3=175` @`0x100238fc4–0x100238ff0` (closed W×H 74×19.5? max W×H 321×175);
- real notch: `h = screen.maxY − aux.maxY − 5.5` (`0x100238f78`; −1 variant `0x100238f48`; alt fixed 24 @`0x100238f9c`), `maxW = min(345, gapWidth + 160)` @`0x100239018–3c`, `maxH = min(175, h + 142)` @`0x100239040–68` (alt +140 @`0x100238fbc`).
The `_notchAdjustedWidth/Height` ivars (NotchController offsets `0x1005d3cd8/ce0`, also on NotchView `0x100531c2c/38`, NotchLumaView, NotchQuickPeekView, NotchNotificationsView, NotchLiveActivitiesView, GeneralSettingsView) are only touched in property-sweep fns `0x100220714, 0x1002227bc, 0x10022bb24, 0x1002326ec, 0x1002348e0` (Published-wrapper retain/release) → they are plumbed into the views' SwiftUI padding, not into the window-size geometry. **Why no visible effect:** with "Force simulated notch" the fallback constant branch is taken and the adjusted values never modify window size; the views only apply them when a real notch (`auxiliaryTop*Area` non-empty) is present. Residual: the exact SwiftUI consumer is INFERRED.


> **Lead correction (STATIC, re-read of `ev/geom_100238df8_filtered.txt`):** the clamps are **max**, not min. Width: `fcmp d1(gap+160), d2(345)` then `fcsel d2, d2, d1, ls` picks 345 when gap+160 ≤ 345, else gap+160 → `max(gap+160, 345)`. Height: `fcmp d3(h+142), d4(175)`, `b.hi` keeps h+142 when it exceeds 175, else 175 → `max(h+142, 175)`. This matches Part E. Also, the constant branch (74 × 19.5, max 321 × 175) is the **no-notch compact** path (Part E), not the forced-simulated-notch path, which was measured live at 144 × 29 (Parts B/lead). The core finding stands: this function never reads `notchAdjustedWidth/Height`.

## 9. Lock screen live

**Answer (OBSERVED + STATIC):** Real lock executed twice (`ev/lock/`): attempt 1 with screenLock off → display slept, no lock UI (luma constant). Attempt 2 after `sysadminctl -screenLock immediate`: `pmset displaysleepnow` → at frame 533 (t≈8.88 s) **2 black frames (33 ms)**, then loginwindow lock screen is **fully captured** by avfoundation (not blank): LUI2 big clock + date, avatar, "Enter Password" (`locked_screen.png`, `locked_full.png`). `caffeinate -u` woke it, scripted password → unlock crossfade frames 952–959 (**≈117 ms**). **Alcove's lock widget was NOT present** (`locked_full_top.png` vs `after_unlock_top.png` both empty top-centre) because Alcove is stuck in onboarding on this VM (see caveat) — so widget layout/material/animation/sound timing remain UNVERIFIED live. Static recovery: `LockManager` polls `CGSSessionScreenIsLocked` (`0x10026a6d8`, `0x10034eed8`), preloads `lock.caf` (0.284 s) / `unlock.caf` (0.270 s) @`0x10034fa14/a34`; reads loginwindow's clock via private LoginUIKit `LUIClockSettingsManager.sharedClockSettingsManager / clockSettingsForUserWithGUID: / setClockSettings:` (fns `0x100245444–0x1002458a4`) and `batteryViewController` (`0x100245314`), classes `LUI2BigTimeViewController`, `LUI2DateViewController`, `LUI2VibrancyEffectView`, `LUI2UIController`, `LUI2NoAnimationLayer`. Settings: widgets Battery/Connectivity/Focus/Calendar(off)/Now Playing, material Glass/Clear/Frosted, idle 10 min, offset tuning px. Widget layout constants: UNVERIFIED (SwiftUI, no literals isolated).

---
## Evidence zip index (`alcove_gaps_evidence.zip`)
`ev/PROGRESS.md` (running log), `ev/deobf_strings.txt`, `ev/wv_*` (waveform fns), `ev/rr_1003602a8.txt`, `ev/am_100361500.txt`, `ev/h_*`/`hc_*` (haptics), `ev/sw_*` (swipes), `ev/geom_100238df8_filtered.txt`, `ev/airpods/` (probe, loop analysis, 15 strips), `ev/assets_info.json`, `ev/lock/` (2 clips @60 fps, frames, timings), `ev/shots/` (onboarding), scripts `fieldmd.py`, `deobf.py`. The 1.1 M-line `otool_text.txt` is omitted for size (regenerate: `otool -tvV Alcove.arm64`).
