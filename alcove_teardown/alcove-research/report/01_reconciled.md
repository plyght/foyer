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
