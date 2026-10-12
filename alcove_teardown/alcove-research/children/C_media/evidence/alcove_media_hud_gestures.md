# Alcove 1.7.7 (199): Now Playing, HUDs, Quick Peek, swipe gestures. Live feature + animation timing

Scope: live behaviour of the Now Playing activity, volume/brightness HUDs, Quick Peek and all notch gestures, measured on a macOS VM (1600x1200 @1x, no real notch, "Force simulated notch" ON, trial started through the normal onboarding). Every claim is tagged **OBSERVED** (seen live, with clip/frame evidence), **STATIC** (binary strings/disassembly), **INFERRED** (my reading of the evidence) or **UNVERIFIED** (could not be exercised on this VM). Evidence files are in the accompanying zip (`clips/*.mp4` 60 fps screen recordings, `clips/*_strip.png` frame strips, `clips/*.csv` per-frame notch bbox, `clips/*.actions` wall-clock action logs, `swipe_scan_*.txt` gesture scans, `tools/evt.swift` input synthesiser, `*.py` measurement scripts, `r2_*.txt` disassembly).

Measurement conventions
- Recorder: `rec.sh` -> ffmpeg avfoundation, 60 fps, full screen 1600x1200. All frame numbers below are 0-based frames of the named clip; `t_ms = frame * 16.667`.
- `measure2.py <clip> <y> <h>`: for every frame finds the near-black (max channel < 22) run on row 2 within the top-centre ROI => `left,right,width`; `hmax` = lowest dark row over sampled columns (= panel height), `inner_lum` = mean luminance inside the panel (content opacity proxy).
- `probe.py`: one-shot screencapture of the top strip and the same bbox measure (used for the gesture threshold scans; it is not frame accurate, it is a yes/no state read ~0.8 s after the gesture).
- Caveat on absolute latencies: `rec-start` in the `.actions` logs is printed before ffmpeg actually starts capturing; ffmpeg startup is ~0.45 s (calibrated in `hover_expand.mp4`: the mouse-enter and mouse-leave logs both precede the first frame of motion by 0.44-0.47 s), so action -> frame mapping is only good to roughly +-0.3 s unless stated. Durations measured *within* a clip (first-motion to settle) are frame accurate (+-1 frame = 16.7 ms).
- Geometry baseline (OBSERVED, `np_compact_state.png`, `gestures.csv` f0): simulated notch with no activity = 140 x 28 px (same as the lead's calendar baseline); the display is 1600 px wide so the notch is centred at x=800.

## 1. Geometry of every Now Playing state (OBSERVED)

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

## 2. Now Playing animations (OBSERVED unless stated)

### 2.1 Activity appearance (play starts, closed notch 140 -> 216) and disappearance
Clip `np_start.mp4`, `np_start.csv`, strips `np_start_open_strip.png`, `np_start_close_strip.png`, `np_start_strip.png`.
Appear: f148 144, f149 148, f150 153, f151 160, f152 167, f153 172, f154 177, f155 183, f156 187, f157 192, f159 197, f160 200, f162 204, f164 208, f166 210, f167 212, f170 213, f173 214, f175 216 (settled). 27 frames = 450 ms, ease-out, **no overshoot** (never exceeds 216), height fixed at 28. Artwork + waveform fade in from f154 (inner_lum 0.2, i.e. 100 ms after first motion, when the wings are ~60% grown) and reach full opacity around f170-f175 (~350-450 ms), so content opacity tracks the width progress with a ~100 ms delay.
Disappear (stop): f711 213 ... f740 140: 29 frames = 483 ms, same ease-out, no overshoot; content fades out during the first ~7 frames (inner_lum 1.7 -> 0.0 by f718, ~120 ms). Model (INFERRED): same overdamped spring as the collapse in 2.3.

### 2.2 Expand (compact -> expanded player) by click or swipe
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

### 2.3 Collapse (expanded -> compact) on mouse exit
Clip `gestures.mp4` f647..f674, strip `gesture_mouseexit_close_strip.png`. Mouse left the panel at ~f646. Width 362 -> 216, height 120 -> 28:

f647 358, f648 350, f649 333, f650 322, f651 305, f652 294, f653 282, f654 270, f655 261, f656 253, f657 248, f658 242, f659 238, f660 234, f661 230, f662 228, f663 226, f664 224, f665 222, f666 221, f667 220, f670 220, f671 218, f672 217, f674 216 (settled).

27 frames = 450 ms, monotonic, no overshoot (ease-out, fastest in the first 100 ms: 362->305 in 4 frames). Height 120 -> 28 follows the same curve (f647 120 ... f653 95, f660 46, f666 34, f674 28). Fitted model (INFERRED): overdamped spring / `Spring(duration ~0.45, bounce <= 0)`; STATIC candidates `(0.35, -0.2)` 6x in the binary. Compare the lead's calendar close 583 ms (longer travel 358 -> 140). The close starts immediately on exit (<= 1 frame after the cursor left the panel), there is no exit debounce visible at 60 fps; STATIC strings `hoverDebounce`, `hoverDuration` exist but their values were not recovered.

### 2.4 Hover: grow (Expand on hover OFF, default) and hover-expand (Expand on hover ON)
Expand on hover OFF: clip `gestures.mp4` f104-f111, strips `hover_in_strip.png`, `hover_out_strip.png`, `hover_plain.csv`. Cursor entering the compact panel: width 216 -> 236 and height 28 -> 33 in 7 frames (~117 ms), ~1 frame latency, slight overshoot to 236 then 234 (1 px). Leaving: back to 216/28 in ~130 ms. INFERRED: a scale-up of ~1.08 (both axes grow ~8%) i.e. a `scaleEffect` hover affordance, not a layout change.

Expand on hover ON (toggled in Settings > General > Behaviour, screenshot `settings_general_after_toggle.png`): clip `hover_expand.mp4`, `hover_expand.csv`, strips `hover_expand_open_strip.png` (f94..f125), `hover_expand_close_strip.png` (f339..f370).
- Hover delay: mouse-enter log precedes first motion by 0.468 s and mouse-leave precedes close first motion by 0.440 s; the difference (~30 ms, 1-2 frames) is the whole hover delay. OBSERVED: hover-expand starts within ~2 frames of the cursor entering the 216 px panel, there is no deliberate hover delay (`hoverDuration` STATIC string notwithstanding; `probe.py` 0.2 s after the move already read 377 x 120 mid-overshoot).
- Open: f96 217/30, f97 237/51, f99 268/83, f101 301/117, f104 330/120, f107 361, f108 370, f110 374, f113 **376 peak** (+14 px, +3.9% of 362, +9.6% of travel), f116 370, f121 366, f124 **362 settled**: 28 frames = 467 ms. Same spring as the click/swipe open (2.2) but starting from the un-hovered 216 px (travel 146 px) instead of the rubber-banded 246 px, hence the slightly larger overshoot. Height 28 -> 120 in 5 frames (83 ms). Content fades in from f101 to f107 (inner_lum 11 -> 25).
- Close on exit: f341 337, f344 305, f345 282, f348 262, f349 248, f351 237, f354 230, f356 226, f357 222, f359 220, f363 218, f366 216: 25 frames = 417 ms, no overshoot (identical curve to 2.3 within 2 frames).

### 2.5 Pause -> idle -> collapse
Clip `pause_idle.mp4`, `pause_idle.csv`, strips `pause_idle_fade_strip.png`, `pause_idle_collapse_strip.png`. `pause` AppleScript sent at 1.53 s after actions-begin (`pause_idle.actions`), i.e. at clip ~2.2-2.5 s. Artwork+waveform fade out from f140 (2333 ms) to f155 (2583 ms): 15 frames = 250 ms linear-ish opacity fade; the panel keeps its 216 px for the whole idle period. Panel collapse 216 -> 140 starts f320 (5333 ms) = 3.0 s after the fade started (matches "Now Playing idle duration = 3 s" in Settings, OBSERVED) and finishes f348: 28 frames = 467 ms, monotonic, no overshoot (same ease-out as 2.3). So: pause -> ~0.1-0.3 s -> 250 ms content fade -> 3.0 s hold at full width (black) -> 467 ms shrink to 140.

### 2.6 Artwork flip on track change
Clip `artflip_distinct.mp4` (play a different local track with different artwork, command at ~clip 2.5 s), strip `artflip_distinct_strip.png` (40 frames, f140..f179 every frame, compact artwork cell x650..700 cropped and 4x zoomed), per-frame data `artflip.py` (lit-pixel count and mean colour of the artwork cell):

- f140-f163: old (pink) artwork, mean colour drifting (title/colour cross-fade starting).
- f164 -> f171 (133 ms): artwork's lit area 426 -> 67 px: the square compresses horizontally to a ~2 px vertical line (3-D Y-axis flip, first half).
- f172-f173: nothing visible (edge-on).
- f174 -> f181 (133 ms): new (teal) artwork grows back from the line to the full square (second half of the flip), mean colour now (67,156,165).
- Total flip ~300 ms (f164..f181), symmetric, no overshoot; the waveform bars change tint to the new dominant colour in the same window.

INFERRED: `rotation3DEffect` about the Y axis 0 -> 90 -> 0 with the image swapped at 90 deg, ~0.3 s total. Setting "Disable artwork flip" (default off) presumably replaces this with a cross-fade: UNVERIFIED. A same-artwork track change (`artchange_same_strip.png`, `track_change2.mp4`) shows only an opacity dip, no flip (OBSERVED), so the flip is gated on artwork actually changing (INFERRED).

### 2.7 Marquee (long title) scroll
Clips `np_expand.mp4`, `marquee_long.mp4`; tracking `marquee.py`, output `np_expand_marquee.txt`, `marquee_long.txt`. Title "A Very Long Song Title That Should Definitely Overflow The Marquee Label" in the expanded player. Local cross-correlation of the title row gives a steady -5.5 +-0.5 px/frame = ~330 px/s (OBSERVED, over f330..f830 of `np_expand.mp4`, cumulative -344 px over 500 frames, direction right-to-left). The text is drawn twice with a gap and wraps continuously (re-anchor jumps in the tracker every time the duplicate passes). An end pause was not detected within the 8 s observed window: the scroll looks continuous (OBSERVED for a single-line overflow title; the artist line was short and static). STATIC: classes `MarqueeText`, `NSMarqueeTextView` exist. Caveat: 330 px/s is faster than typical Apple marquees; tracker outliers were excluded manually, treat as +-10%.

### 2.8 Waveform animation
`waveform.py` on `pause_idle.mp4` f10..f129 (compact, playing, "Use live waveform" OFF because audio capture had not been unblocked at record time): 5 bars; bar heights change in 2 px steps on 34 of 119 frame pairs = a new target roughly every 3.5 frames (~17 Hz) with the in-between frames holding, each bar moving independently between 2 and 12 px; looks like a per-bar random walk / looping fake spectrum (INFERRED: `WaveformAnimationClock` + `WaveformSpectrumSession` STATIC symbols; the animation is not synced to audio). The compact waveform fades with the artwork on pause (2.5). Live waveform (`useLiveWaveform` STATIC string, Settings toggle): not measured; after installing the BlackHole virtual output device macOS exposed an audio device but the live-waveform recording was not completed: UNVERIFIED. "Disable compact waveform": UNVERIFIED.

### 2.9 Quick Peek (media change while closed)
STATIC: `QuickPeek`, `NotchQuickPeekView`, `quickPeekDebounce`, `quickPeekResetDebounce`, `quickPeekGeneration`, `peekDuration`; Settings: Quick Peek enabled, duration 2 s (lead's `settings_ax/general.txt`). Attempts `quickpeek_next*.mp4` / `track_change*.mp4`: track changes made via Music AppleScript while the panel was closed produced the compact artwork flip (2.6) and a ~0.3 s title colour cross-fade but no transient expansion of the panel in any of 5 attempts (`track_change.csv`, `track_change2.csv`: width stays 216). INFERRED: Quick Peek either requires a change in the media *source* (different app) or is suppressed while the same compact activity is already showing; or Music's unreliable `next track` on this VM (AppleScript error -1728 half the time) never produced a "did change" event Alcove considered peek-worthy. Peek timing is therefore UNVERIFIED; the 2 s default is from the Settings UI only.

## 3. HUDs

### 3.1 Volume HUD via media keys (OBSERVED)
Trigger: `tools/evt key sound_down 3 300` (NX_KEYTYPE_SOUND_DOWN system-defined events, 3 presses 300 ms apart), then `sound_up 3 300`. Clip `hud_vol_keys2.mp4`, `hud_vol_keys2.csv`, strips `hud_vol_open_strip.png`, `hud_vol_close_strip.png`, states `hud_vol_keys_f165.png`, `hud_vol_keys_f440.png`, `hud_vol_state_f200.png`, `hud_vol_state_f360.png`. (Audio device: BlackHole 2ch installed to give the VM an output device; before that `set volume` returned `missing value` but the key HUD still showed.)

Open (first key press): width 140 -> 326, height stays 28 (compact HUD, no vertical growth):
f327 148, f328 157, f329 173, f330 192, f331 224, f333 236, f334 252, f336 272, f338 288, f340 300, f342 308, f344 314, f347 320, f350 322, f351 324, f356 325, f357 326 (settled). 30 frames = 500 ms, ease-out, no overshoot (0 px). Content (speaker symbol left, "Sound" label, white bar, 'inner_lum' 0 -> 22) fades in from f331 to ~f357, i.e. starts ~70 ms after the width starts moving and lands with it.
Hold: the HUD stays at 326 until f454; with 3 presses 300 ms apart the HUD dismissed 1.5 s (+-0.1 s, limited by the rec-start caveat) after the *last* key event: Settings "HUD duration 1.5 s" is measured from the last value change, each new press restarts the timer (OBSERVED: no dismissal between presses 300 ms apart).
Dismiss: f454 324, f455 312, f456 296, f457 281, f458 261, f459 248, f460 232, f461 221, f462 208, f465 184, f470 158, f476 148, f480 144, f490 140. 36 frames = 600 ms, monotonic ease-out, no overshoot; content fades out during the first ~8 frames (inner_lum 22 -> 0.1 by f462, ~130 ms) then the empty panel keeps shrinking.
Value change: the bar fill animates between presses (OBSERVED visually in `hud_vol_keys_f165.png` vs `hud_vol_keys_f440.png`); fill tween duration was not isolated because the fill is only ~1 px different per press on a 326 px HUD at 60 fps: UNVERIFIED (Speed setting Smooth/Fast/Instant, which per the Settings copy controls this tween, not measured).
Layout (OBSERVED, `hud_vol_state_f200.png`): 326 x 28 black pill; SF speaker glyph (speaker.wave.2/3 variant following the level) at the left wing centre, "Sound" label in ~11 pt grey to its right, white progress bar (~4 px tall, rounded, ~110 px long) on the right wing. Styles White (default) only; Accent/Decibel/Glow, "Show percentage", "Hide label", "Show device" glyph: UNVERIFIED (Settings exist, see lead's `settings_ax/general.txt`; not exercised in this session).

### 3.2 Volume via AppleScript `set volume output volume N` (OBSERVED: no HUD)
Clip `hud_vol_osa.mp4`: `set volume output volume 30` then `60` 0.9 s later. No pixel changed in the top band for the following 2.3 s (`hud_vol_osa.csv`, per-frame diff scan): Alcove does not show the Sound HUD for programmatic volume changes, only for key-driven ones (the panel briefly shrank 216 -> 140 at the clip's very end, f524-f539, which was the media activity hiding, unrelated to volume). INFERRED: Alcove listens for the media-key / OSD events (replacing the system OSD, `OSDUIHelper` is referenced in `helper_strings.txt`) rather than observing the CoreAudio volume property.

### 3.3 Brightness HUD
`tools/evt key bright_up` on this VM: the VM has no backlight-capable display, so brightness keys do nothing and no HUD appeared. UNVERIFIED. STATIC: `brightnessDuration`, Display HUD styles White/Accent/Glow in Settings.

## 4. Gestures (swipe thresholds measured empirically)

### 4.1 Method
`tools/evt.swift` (compiled `tools/evt`), command `swipeseq X Y "dx:dy,dx:dy,..." msPerStep`: moves the cursor to (X,Y) = (800,14) over the notch, then posts one continuous trackpad-style gesture with `CGEvent(scrollWheelEvent2Source:units:.pixel,wheelCount:2,...)`, `kCGScrollWheelEventIsContinuous = 1`, `scrollWheelEventScrollPhase` = MayBegin(128) -> Began(1) on the first step -> Changed(2) -> Ended(4) with zero delta, momentum phase 0, `FixedPtDeltaAxis1/2` and `PointDeltaAxis1/2` set to the per-step deltas (axis1 = vertical dy, axis2 = horizontal dx; negative dy = fingers moving up on a natural-scrolling trackpad is what AppKit reports as `scrollingDeltaY < 0`). 8 steps 16 ms apart unless stated. `scan.sh` wraps one gesture + `probe.py` read-out + moving the cursor away. Logs: `swipe_scan_vertical.txt`, `swipe_scan_vertical_fine.txt`, `swipe_scan_horizontal*.txt`, `swipe_scan_close.txt`, `swipe_scan_close_dismiss.txt`. Settings during the scans: Swipe to toggle open / cycle activity / dismiss / skip media all ON, Natural movement OFF, Expand on hover OFF (lead's defaults).

Units: all thresholds below are the *net accumulated* scroll delta of one gesture in scroll pixel units (sum of FixedPtDelta over the gesture, as `NSEvent.scrollingDeltaY/X` would report).

### 4.2 Results (OBSERVED)

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

### 4.3 Follow-finger / rubber band during a vertical swipe (OBSERVED)
Clip `gestures.mp4` f136..f202, strip `gesture_rubberband_strip.png` (f150..f201 every 2nd frame): a slow -40 px swipe (20 steps of -2 px every 50 ms, 1.0 s) over the hovered compact panel (234 x 33) grows it progressively to 246 x 42 by the last step: +12 px width and +9 px height for 40 px of accumulated delta, i.e. ~0.3 px/px horizontally and ~0.22 px/px vertically, roughly linear in the accumulated delta (f152 234/34, f165 240/37, f179 244/40, f191 246/42). The stretch is released into the full open animation on Ended (2.2). For a sub-threshold gesture the panel springs back to 234 x 33 (`probe` after -34). Horizontal swipes produce no visible stretch (OBSERVED on the expanded panel; compact not recorded at 60 fps).

### 4.4 Natural movement (OBSERVED, `swipe_scan_natural.txt`)
Toggled ON in Settings > General > Gestures (AX click; the keys are not plain `defaults`, writing `naturalMovement`/`expandOnHover` had no effect). With Natural movement ON and Expand on hover OFF, over the compact Now Playing:
- dy = -40 (8 steps): **still opens** (365 x 120). Vertical toggle-open direction is NOT inverted by Natural movement.
- dy = +40 (8 steps): **no longer dismisses** (panel stayed 234 x 33 compact, activity kept) whereas with Natural movement OFF +36..+40 dismissed every time (4.2).
- expanded, dy = +120: **still closes** (365 -> 234).
- dy = -120 posted 0.3 s after that closing gesture: did **not** open (234). Single observation; INFERRED: a short inter-gesture reset/debounce (`swipeResetDebounce` STATIC string) ignores a new gesture that starts within well under a second of the previous one. All the threshold scans in 4.2 left >= 1.5 s between gestures.
- Horizontal skip and the inverted dismiss direction (does +dy become open and -dy dismiss for some state?) were not re-scanned with Natural movement ON: UNVERIFIED. The toggle was restored to OFF afterwards (`settings_general_restored.png`).

Expand on hover: see 2.4 (no measurable hover delay, 467 ms open, 417 ms close on exit).

## 5. Idle / other activities
"Idle activity = calendar" is set (`defaults`), but no calendar activity ever appeared in the simulated notch even with an event created 9 minutes ahead (`Calendar` AppleScript, probe stayed 218 px Now Playing). UNVERIFIED on this VM.

## 6. STATIC spring constants (for the clone)
From `r2_springs.txt`/`r2_dump.txt`/`spring_constants.txt`: SwiftUI `Spring(duration:bounce:)` calls with constants (count): (0.35,0.3) x15, (0.3,0.25) x10, (0.6,0.4) x9, (0.6,0.35) x9, (0.35,-0.2) x6, (0.4,0.35) x6, (0.45,0.4) x5, plus singles (0.5,0.45) (0.35,0.4) (0.6,0.3) (0.4,0.3) (0.3,1.0) (0.35,0.7) (0.3,0.45) (1.0,0.4) (0.275,0.375) (0.3,0.2) (0.3,0.1953). Mapping to observed animations (INFERRED): expand = (0.4,0.35)/(0.45,0.4); collapse/HUD dismiss/idle shrink = (0.35,-0.2) or similar bounce <= 0; hover grow = (0.3,0.25); HUD open = (0.6,0.35) family (500 ms no overshoot would be bounce ~0); artwork flip ~0.3 s = (0.3,0.2)-ish.

## 7. Quick reference numbers for the clone
- Closed notch 140x28; compact media 216x28 (38 px wings); hover scale ~1.08 in ~120 ms; expanded 362x120.
- Expand: ~430 ms, +3% width overshoot at 250 ms, height done in 100 ms. Collapse: 450 ms ease-out, no overshoot, starts <= 16 ms after mouse exit.
- Pause: 250 ms content fade, 3.0 s hold, 467 ms shrink to 140.
- Artwork flip: 300 ms Y-flip, image swap at 150 ms. Marquee ~330 px/s right-to-left, continuous.
- Waveform: 5 bars, 2 px on 4 px pitch, heights 2..12 px, new target ~every 3-4 frames (~17 Hz), tinted from artwork.
- Sound HUD: 326x28, open 500 ms ease-out (content fades in from +70 ms), hold 1.5 s after last key, dismiss 600 ms ease-out (content gone in 130 ms); only media keys trigger it, not `set volume`.
- Swipes: resolve on gesture end; open at net -35 px; dismiss at net +35 px (Natural movement OFF); close expanded at ~+105 px; skip at ~|80| px; reversal within a gesture does not reset; ~sub-second inter-gesture debounce; rubber band ~0.3 px per scroll px.
- Hover (Expand on hover ON): no hover delay (<= 2 frames), open 467 ms with +3.9% overshoot, close 417 ms on exit.

## 8. Not covered / UNVERIFIED list
Brightness HUD; HUD Speed Smooth/Fast/Instant tween; HUD styles Accent/Decibel/Glow, Show percentage, Hide label, Show device; Now Playing Format Monochrome/Colored/Gradient; Explicit badge variants; extra button Favorite/Repeat/Copy; Hide while source app is active; Hide media title extras; Source Automatic/System; Spotify/Safari sources; live waveform; Disable artwork flip; Quick Peek timing; cycle-activity threshold; Natural movement effect on skip direction; haptics; real notch geometry (all measurements are on the simulated notch at 1x).
