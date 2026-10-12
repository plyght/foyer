# Alcove v1.7.7 — Task A (Spotify explicit badge) and Task B (cycle-activity swipe threshold)

Labels: **OBSERVED** = seen live on this VM, **STATIC** = from the binary (given in the brief), **INFERRED** = derived from observations, **UNVERIFIED** = not established.

## 0. Setup notes (all OBSERVED unless noted)

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

## 1. Task A — explicit badge via Spotify

### 1.1 Does the badge appear?

**Yes (OBSERVED).** With Spotify playing a track Spotify marks "E", Alcove renders a small filled square with a knocked-out "e" (SF Symbol `e.square.fill` per STATIC) immediately after the title. Explicit tracks observed with badge: HUMBLE., LUST., DNA., Not Like Us, goosebumps, Mask Off, United In Grief, The Box (Roddy Ricch). Clean control: Shape of You (Ed Sheeran) → **no badge (OBSERVED)**, same layout.

| State | Badge | Evidence |
|---|---|---|
| Compact notch (art left, waveform right) | **No** (OBSERVED) | `clips/A1_humble_states.mp4`, `frames/B1_ref/sheet2x.png` |
| Hover (pointer on compact notch) | **No** (OBSERVED) — hover does not change the compact content | A1 clip |
| Expanded Now Playing (click notch) | **Yes** (OBSERVED) | `frames/A1_exp/f0010.png`, `frames/badge_crop_1x.png`, `frames/badge_zoom6x.png`, `clips/A2_expanded_trackchanges.mp4` |
| Expanded split layout (Now Playing + Calendar side by side) | **Yes** (OBSERVED) | `frames/A3/split_humble_E.png` vs `frames/A3/split_shapeofyou_clean.png`, `frames/B1_ref/g100_down40_10fps.png` |
| Quick Peek (track change while Now Playing not on screen; "♪ HUMBLE. · Kendrick Lamar" text strip) | **No** (OBSERVED), text only, visible ≈ 3.0 s | `frames/A1_qp_humble/`, `frames/A1_qp_lust/`, `screens/qp_lust.png` |
| Lock-screen widget (Ctrl+Cmd+Q) | **Yes** (OBSERVED), white variant | `clips/A4_lockscreen.mp4` (t ≈ 12–29 s), `frames/A4/widget_sheet_2x.png`, `frames/A4/lockscreen_widget_badge_3x.png`, `screens/lockscreen_widget_computer.png` |

### 1.2 Geometry and colour (expanded Now Playing, `frames/A1_exp/f0010.png`, crop origin screen x450,y0) — OBSERVED

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

### 1.3 Animation / timing on track change — OBSERVED (A2, 60 fps, template match NCC ≥ 0.75)

- The badge has no animation of its own; it is part of the title row and crossfades together with the title. Template match loses the badge for **5, 4 and 6 frames (67–100 ms)** at the three track changes (frames 515–519, 826–829, 1135–1140 of `clips/A2_expanded_trackchanges.mp4`) and it reappears at the new x position; no slide, scale or pop.
- Quick Peek shows no badge at any frame of the ~3 s strip.
- Lock-screen widget: title crossfade with a blur (visible at `frames/A4/widget_t19.png`), badge appears with the title.

### 1.4 What Spotify exposes (OBSERVED)

- Spotify's AppleScript dictionary (`sdef /Applications/Spotify.app`) has **no explicit/content-rating property**; `track` exposes name, artist, album, `spotify url`, popularity, duration, track number, played count, starred, disc number, album artist, id, artwork url. `get properties of current track` fails with `-10000`; individual properties work (`csv/spotify_applescript_current_track.txt` shows the failure captured while an ad was the current track).
- Alcove still shows the badge, so it must obtain the flag another way (STATIC background: `kMRMediaRemoteNowPlayingInfoIsExplicitTrack` or Spotify Web API `explicit`); which of the two was active here is **UNVERIFIED**.
- The Spotify app itself shows "E" next to the same tracks (visible in the Spotify window in `frames/A4/lock_full.png` / screenshots).
- Caveat: "TORE UP" (Don Toliver) showed no badge on the lock screen but also had no artwork (incomplete metadata right after an ad) → **UNVERIFIED** for that track.

## 2. Task B — cycle-activity swipe threshold

### 2.1 What the gestures do (compact notch, two activities: Now Playing + Calendar) — OBSERVED

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

### 2.2 Threshold table

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

### 2.3 Reset threshold (reversing mid-gesture) — OBSERVED (B3 `test_reset`, Calendar visible)

Gesture: up 30 px (sub-threshold) → reverse down R px → up 30 px again, all in one phase-began…ended gesture.

| R (px reversed) | 0 | 5 | 10 | 15 | 20 | 25 | 30 | 40 | 50 |
|---|---|---|---|---|---|---|---|---|---|
| cycled? | 3/3 | 3/3 | 3/3 | **1/3** | 0/3 | 0/3 | 0/3 | 0/3 | 0/3 |

Control: up 30 px alone → 0/3. Conclusion: reversing by **≥ 15–20 px resets the accumulated distance** (reset threshold ≈ 15 px, between 10 and 20) — INFERRED. A pure net-distance model is rejected (R = 15 would leave 45 px > 40 px and should fire 3/3).

Reversing **after** the threshold has been crossed does not undo the action: up 60 px then back 0–60 px → 27/27 cycled (B2 `test_rev`); the action fires mid-gesture as soon as the threshold is crossed (OBSERVED).

### 2.4 Cycle transition timing (60 fps, `frames/B3_slow_up_r1_60fps.png`, `frames/cycle_transition_strip.png`) — OBSERVED

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

### 2.5 Distinguishing cycle from track-skip and expand/close — OBSERVED

- Cycle = vertical, compact, 40 px, visible as fade-out → empty notch → fade-in of the other activity, width changes to the other activity's width.
- Expand = vertical down, compact, 40 px, only when no activity is dismissed; panel grows to the 624×320 window (split layout); auto-closes after the pointer leaves.
- Track skip = horizontal, 75 px compact (40 px inside the expanded panel); ⏮/⏭ glyph flashes, artwork crossfades to the new track; no change of activity.
- Close = up 110 px inside the expanded panel.
- Hover alone never changed the compact content or expanded the notch; clicking the notch toggles expanded.

### 2.6 Deviations from the requested protocol

- B1 ran the full grid (20–160 px, 5 px, 3×, 4 directions, compact) but without restoring state between gestures, so after the first successful up-dismiss the remaining up gestures acted on an empty notch. B2 therefore re-ran up/down with a state restore before every trial at 15 distances (20–70 in 5 px steps, then 80, 100, 120, 160; 3×). B4 (expanded) used 10 px steps × 2 repeats × 4 directions.
- Gestures were posted at (800,10) over the notch; in the expanded state at (800,60) inside the panel.

## 3. Evidence files (all under the zip root)

- `alcove_v4_spotify_cycle.md` — this report; `NOTES.md` — raw working notes with timestamps.
- Clips (60 fps, 1600×1200): `clips/A1_humble_states.mp4` (compact/hover/expanded/Quick Peek, 59 s), `clips/A2_expanded_trackchanges.mp4` (expanded, 3 track changes, 56 s), `clips/A3_clean_control.mp4` (Shape of You clean control + HUMBLE. in split layout, 141 s), `clips/A4_lockscreen.mp4` (lock-screen widget, 49 s), `clips/B0_explore.mp4` (4 exploratory 100 px gestures), `clips/B1_compact.mp4` (full compact grid, 348 gestures, 956 s), `clips/B2_cycle.mp4` (state-restored up/down + reverse tests, 279 gestures, 797 s), `clips/B3_reset_slow.mp4` (reset-threshold + slow gestures, 87 gestures, 295 s), `clips/B4_expanded.mp4` (expanded sweep, 120 gestures, 610 s).
- Key frames/strips: `frames/badge_crop_1x.png`, `frames/badge_zoom6x.png`, `frames/A1_exp/`, `frames/A1_qp_humble/`, `frames/A1_qp_lust/`, `frames/A2/`, `frames/A3/split_humble_E.png`, `frames/A3/split_shapeofyou_clean.png`, `frames/A4/widget_sheet_2x.png`, `frames/A4/lockscreen_widget_badge_3x.png`, `frames/A4/widget_t*.png`, `frames/A4/lock_full.png`, `frames/B0/*` (first semantics strips), `frames/B1_ref/sheet2x.png` (compact states reference), `frames/B1_ref/g100_down40_10fps.png` (expand), `frames/B1_compact_{up,down,left,right}_sheet.png` (pre/mid/post per gesture), `frames/B1_compact_{left,right}_skip_sheet.png`, `frames/B2_cycle_{test_up,test_down,test_rev,restore,prep_up}_sheet.png`, `frames/B3_reset_slow_*_sheet.png`, `frames/B3_slow_{up,down,left,right}_r1_60fps.png`, `frames/cycle_transition_strip.png`, `frames/cycle_transition_strip_down.png`, `frames/B4_expanded_{up,down,left,right}_sheet.png`.
- Screenshots: `screens/` (setup, Quick Peek, lock-screen widget, computer-tool zooms).
- CSV logs: `csv/B0_explore.csv`, `csv/B1_compact.csv`, `csv/B2_cycle.csv`, `csv/B3_reset_slow.csv`, `csv/B4_expanded.csv` (one row per gesture: wall time, phase/state, direction, distance, repeat, reverse leg, CLI echo), `csv/*_features*.csv` (per-frame notch features), `csv/*_gestures*.csv` (per-gesture windows, cursor-synced onsets), `csv/B3_reset_slow_timing.csv`, `csv/A2_badge_template_match.csv`, `csv/lock_badge_measure.txt`, `csv/spotify_applescript_current_track.txt`.
- Sources: `src/swipe.swift` (gesture CLI), `src/mv.swift` (pointer park/click), `src/winfo.swift` (Alcove window bounds), `src/sweep.sh`, `src/sweep2.sh`, `src/sweep3.sh`, `src/sweep4.sh` (drivers), `src/features.py`, `src/features2.py`, `src/analyze.py`, `src/analyze2.py`, `src/strips.py`, `src/hsheet.py`, `src/timing.py`, `src/marker.py` (analysis).
