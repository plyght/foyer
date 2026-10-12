# Alcove 1.7.7 (199) — Calendar, Focus, Connectivity/Battery, Lock Screen, Onboarding & Settings UI

Session scope: live feature + animation timing for Calendar, Focus, Connectivity/Battery, Lock Screen, onboarding/settings window, contrast outline / progressive blur. Companion to the lead `NOTES.md` (not repeated here).

Legend: **OBSERVED** = seen live on the VM (frame numbers refer to 60 fps `clips/*.mp4`, `fps=60` CFR tick index as produced by `measure2.py`; 1 frame = 16.7 ms). **STATIC** = from the bundle (binary / resources). **INFERRED** = my interpretation. **UNVERIFIED** = VM lacks the hardware/state.

Environment (OBSERVED): macOS 26 VM, 1600x1200 @1x (1 px = 1 pt), no notch, no battery, no Bluetooth audio, no Touch ID, single display. Alcove installed to /Applications, onboarding completed normally, trial active (License pane shows a `2d 23h 22m` countdown and a `Trial` badge in the sidebar; license internals NOT touched). `Force simulated notch` = ON for everything below unless stated. All coordinates are display px with origin top-left; "notch crop" images are `screencapture -R 488,0,624,120` so x_notch = x_display - 488. Alcove's notch panel and its backdrop panel are both 624x320 windows at (488,0) (OBSERVED via AX).

Evidence root (zip): `clips/` (mp4 + per-frame csv + strips), `shots/` (screenshots), `airpods/` (stills/strips from bundled mp4s), `ax_settings_*.txt` (AX geometry dumps of every settings pane), scripts (`measure2.py`, `framediff.py`, `rec_top.sh`, `sched_rec.sh`, `axdump.applescript`, `mkevents.applescript`), `NOTES_mine.md` (raw running notes).

---

## 0. Global notch geometry seen in this session (OBSERVED)

| State | Width x height (px) | Where |
|---|---|---|
| Closed, no activity | 140 x 28 | lead; also `peek_before_1116.csv` f0 (140x28) |
| Idle calendar activity / Focus notification / lock-screen glyph | 216 x 28 (top-flare bbox 220) | `cal_idle_to_event1.csv`, `focus_dnd2.csv`, `lockscreen1.csv` |
| Quick Peek (2-row) | 233 x 70 (flare bbox 238-240) | `cal_idle_to_event1.csv` f16370+, `peek_before_1116.csv` f1541+ |
| Expanded calendar (with events) | settled 362 x 175 at centre row; opaque body 345 wide (x 628..972), top flare 371, peak during open 375-377 | `cal_expand_colors.csv`, `frame_expanded_colors_on.png` |

Expanded panel bottom corners: black extent per row over the last 40 rows goes 229→279 (left) / 571→521 (right) in `expanded_outline1_blur0_finder_zoom.png` ⇒ corner radius ≈ 32-34 px. Quick Peek bottom corners: rows 60-69 narrow 202→218 ⇒ radius ≈ 14 px. Closed notch: lead measured.

---

## 1. Calendar

### 1.1 Test data (OBSERVED, created with `mkevents.applescript` via Calendar.app)
Calendars: `Calendar` (blue), `Work` (blue), `Personal` (green), `Birthdays` (system, grey). Events on 2026-10-11: `Launch day` (all-day, Personal), `Alex Birthday's 36th Birthday` (Birthdays; the contact already existed - the AppleScript birthday write returned `missing value`, so this row comes from the pre-existing contact), `Design sync` 10:12-10:42 (Calendar), `Budget review` 10:16, `1:1 Sam` 10:27 (overlapping), `Dentist` 11:31-12:31 (Personal), plus future-day events (14, 21 Oct) used for indicator dots.

### 1.2 Idle calendar activity (OBSERVED)
* Appears only when the next event starts within `Time before event` (default 15 m). Before T-15 m the notch is the plain closed 140x28 (`peek_before_1116.csv` f0-1512). At exactly T-15 m (11:16:00.2 for an 11:31 event; f1513 = 25.2 s after the 11:15:35 recording start) the Quick-Peek-before fires and the notch then stays at the 216x28 activity size.
* Layout (`shots/notch_idle_calendar_5m.png`, `idle_calcolor_on.png`): left lobe = `calendar` SF-style glyph (rose `AlcoveRoseColor` 244,63,94 by default; becomes the event's calendar colour when **Use calendar color** is ON - blue for `Design sync`, green for `Dentist`); right lobe = countdown text (`15m` … `5m`, then seconds `46s` under one minute), ~13 pt semibold, same colour as the glyph. Once the event is running the right lobe becomes a progress **ring** (stroke in the same colour, arc = elapsed fraction; `notch_event_inprogress_ring*.png`).
* Only ONE event is tracked: while `Design sync` was in progress, the overlapping `Budget review` (10:16) and `1:1 Sam` (10:27) produced **no** peek and no width change (`cal_event2_budget.csv`, `cal_event3_sam.csv` constant 216). INFERRED: the activity follows the "current/next" event only; overlapping events are not announced.
* Menu-bar menu during an event (`shots/menubar_menu_during_event.png`): `Open in Calendar`, `Dismiss Event`, separator, `Display ▸`, `Version 1.7.7` (disabled), `Settings… ⌘,`, `Quit Alcove ⌘Q`.

### 1.3 Expanded view - day + month grid (OBSERVED)
Trigger: click the notch. Two variants were captured:
* Default (`Always show month view` OFF, day has events): left column `SUNDAY` (rose caps, ~11 pt bold, letter-spaced) / `11` (white, ~34 pt bold) / event list rows (`Launch day` all-day with green glyph pill, `Alex Birthday's 36th Birthday` grey, `Design sync 10:12 AM – 10:42 AM` with blue 3 px bar). Right column: header `SUNDAY, 11 OCT` + upcoming events list **instead of** the month grid (`clips/frame_expanded_events.png`, `shots/full_expanded_calendar_events.png`). With no events the right column is the month grid (lead).
* `Always show month view` ON + `Use event indicators` ON + `Use calendar color` ON (`clips/frame_expanded_colors_on.png`, `shots/expanded_outline*_finder_zoom.png`): left column keeps `SUNDAY / 11`, then a `2 all-day events` pill with the two calendars' coloured glyphs, then the next timed event (`Dentist`, green bar, `11:31 AM – 12:31 PM`), then `3 more events` with coloured bars; right column = `OCTOBER` (rose, ~11 pt bold) + weekday letters `M T W T F S S` (grey, Monday-first) + 5 week rows.
  * Grid metrics (in `frame_expanded_colors_on.png`, crop origin 488): day-number rows at y = 43, 62, 82, 102, 122, 142 (**row pitch 20 px**, 7 px glyph height ⇒ ~10 pt bold); columns M..F at x = 325, 346, 367, 388, 409 (**column pitch 21 px**), S S at 430, 451 drawn grey (~55 % white); header `OCTOBER` rows 13-26; weekday letters row 28.
  * Today = filled rose circle (~16 px) with white number; **event indicator** = 2 px dot centred under the day number (seen under 14 and 21, and under 11); with `Use calendar color` the dots/bars take the calendar colour, otherwise rose/white (INFERRED from the toggle names; both ON in the capture).
* Panel body 345 x 175 (x 628..972), flare 371, bottom radius ≈ 32 px, soft outer shadow ≈ 6 px (grey ramp 179→191 at the sides, 155→167 below) — see §6.

### 1.4 Expanded open/close timing (OBSERVED, `cal_idle_to_event1.csv`, `cal_expand_colors.csv`)
* OPEN (from 216x28 activity): onset f755 → 220 w; f757 244; f760 291; f763 334; f766 362 (target); **peak 375 x 187 at f770 (+13 px / +3.6 % overshoot, 250 ms)**; back to 362 by ~f782 (450 ms); fully still ~f790 (580 ms). Height rises 28→187 over the same 15 frames (12 at the centre column is the flare notch). Earlier run: f2493→peak 377 @ f2508→settle f2521 (470 ms). ⇒ **underdamped spring, ≈ 0.25 s to peak, ≈ 0.45-0.5 s to settle, overshoot 4-6 %** (matches lead's 378/358 = 5.6 %). Lead's `alignmentSpringStiffness/Damping/Mass` STATIC properties are the likely knobs.
* CLOSE (click outside): f3381 → 216 x 28 within ~33 frames (**550 ms**), no overshoot, fast-out (lead: 583-600 ms). Strips: `strip_expand_open.png`, `strip_expand_close.png`.

### 1.5 Quick Peek (OBSERVED)
Settings → Calendar → Extension: `Quick Peek` ON, `Before event starts` OFF (default), `When event is starting` ON, `Peek duration 4.0 s`, `Use colored calendar indicator` ON.
* **At event start** (`cal_idle_to_event1.mp4` f16356, Design sync 10:12): 216x28 → **233x70 in 12 frames (200 ms)**, no overshoot; held to f16603 (**4.07 s** from onset, i.e. the 4 s "Peek duration" measured from onset incl. the open animation); collapse ≈ 30 frames (500 ms) back to 216x28. Content: row 1 calendar glyph (left) + ring (right); row 2 centred: 3 px bar in the calendar colour, title `Design sync` (white 13 pt), `hourglass` glyph + `29m` remaining (grey). Frame `clips/frame_event1_peek_full.png`, strips `strip_event1_peek_open/close.png`, `shots/event1_peek_t0..t8.png`.
* **Before event starts** (toggle ON; `peek_before_1116.mp4`, fires at T-15 m = 11:16:00.2): from the CLOSED 140x28 → **233x70 in 28 frames (470 ms)** ease-out, no overshoot (f1513: 144x30, f1520: 191x50, f1526: 216x62, f1541: 233x70); held to f1762 (**4.15 s** from onset); closes 233x70 → **216x28** (idle activity, not 140) in 23 frames (**380 ms**). Content (`clips/frame_peek_before_1116.png`, notch-crop coords): calendar glyph green (Personal) x 212-264 y 10-25; countdown `15m` green, right-aligned x 390-414 y 12-21; row 2: green bar x 262-264 y 44-55, `Dentist` white, `clock` glyph + `1h` (event duration) grey x 271-361 y 15-24 relative to row. Sampled green ≈ (90,234,88) ⇒ Apple Calendar "green" calendar colour, not Alcove's palette.
* The 140→233 ramp spends its first 7 frames widening with the height lagging (144x30, 157x36, 172x42, 191x50) — width and height are two springs with similar durations, both settle at f1541.

### 1.6 Event notification, sounds, hourly chime
* The "event notification" at start IS the Quick Peek at start (above). `Play sound on calendar event` ON by default; `event.caf` STATIC: 1.743 s, mono 44.1 kHz s16. I could not record system audio (no loopback device) ⇒ playback UNVERIFIED by ear; the setting and asset exist.
* Hourly chime: `Play hourly chime` toggled ON at 10:32; `chime.caf` STATIC 4.237 s mono 44.1 kHz. The 11:00 recording was lost (ffmpeg capture hung after a screen-lock; see §4) — rescheduled for 12:00, result appended in §8 if available. Any visual at the top of the hour is therefore UNVERIFIED so far.

### 1.7 Calendar settings pane (OBSERVED, `ax_settings_Calendar*.txt`, `shots/settings_pane_Calendar*.png`)
Rows (label x = 742, toggle 44x20 at x = 1039, row pitch 42 px): `Calendar` (pane header toggle ON) · `Time before event` slider 340 x 16 (value 15, unit `m`, value shown as a small inline text field) · `Play sound on calendar event` ON (ⓘ) · `Play hourly chime` OFF (ⓘ) · `Use calendar color` OFF · `Disable activity during events` OFF · `Show weather on empty day` OFF (⚠ icon 13x15 → requires Location; weather UNVERIFIED, WeatherKit entitlement STATIC) · `Use event indicators` OFF · `Always show month view` OFF · `Notify when time to leave` OFF (⚠ icon → Location; UNVERIFIED) · section `Calendars`: one row per calendar with a checkbox tinted in the calendar colour (`Calendar`, `Work`, `Personal`, `Birthdays` with gift icon) and a 56x24 popup button; popup menu items (native NSMenu, `shots/settings_pane_Calendar_popup_open.png`): **`Both` (checked), separator, `Live Activity`, `Expanded View`** — i.e. per-calendar routing is Activity / Expanded / Both (not "Notification") · section `Extension`: `Quick Peek` ON, `Before event starts` OFF, `When event is starting` ON, `Peek duration` slider (4.0 s), `Use colored calendar indicator` ON.
Not exercised: `Disable activity during events` (toggle only). Birthdays calendar: shows as a grey row with a gift glyph in the expanded list (OBSERVED).

---

## 2. Focus (OBSERVED unless noted)
Settings → Focus: `Focus` ON · `Duration` slider 340x16 = 5.0 s · `Play sound on sleep focus` OFF (ⓘ; `sleep.caf` STATIC 3.002 s mono 48 kHz s24) · `Replace waveform during focus` OFF · `Hide label` OFF · `Allowed Notifications`: Battery / Connectivity / Display / Sound all ON (`ax_settings_Focus.txt`).
* Trigger used: Control Center → Focus → `Do Not Disturb` (the VM offers only DND; Sleep/Work/Personal modes UNVERIFIED, so per-mode icon/colour UNVERIFIED beyond DND).
* Notification (`shots/focus_dnd_on_notch_zoom.png`): width stays **216x28**; left lobe `moon.fill` glyph in indigo (`AlcoveIndigoColor` 99,102,241 STATIC palette; sampled ≈ purple-indigo), right lobe label **`On`** in the same indigo, ~13 pt semibold. Turning DND off shows the same layout with a grey glyph and **`Off`** (`focus_dnd_off_notch_zoom.png`). `Hide label` ON ⇒ glyph only, right lobe empty, width unchanged (`focus_dnd_on_hidelabel_zoom.png`, `clips/frame_focus_on_hidelabel.png`).
* Timing (`focus_dnd2.csv`, idle calendar activity present): content swap is done by **shrinking to the closed size and re-growing**: 216 → 144 over f556-576 (**333 ms**, ease-out: 211,204,196,189,184,177,172,168,164,161,157,156,153,152,149,148,145,144) then 144 → 216 over f576-604 (**470 ms**, ease-out) while the moon glyph fades in. Off-transition starts at f916 = **6.0 s after onset ⇒ 5.0 s hold after the 0.8 s in-transition**, same shrink/grow back to the calendar content. The DND-off notification at f1882 repeats the identical pattern. Strip `clips/strip_focus_on_hidelabel.png`. No overshoot anywhere in this transition (width never exceeds 216).
* `Replace waveform during focus` needs Now Playing audio ⇒ UNVERIFIED (toggle only).

---

## 3. Connectivity / Battery
* VM has no battery and no Bluetooth audio ⇒ live connectivity and low-battery notifications **UNVERIFIED**. Battery pane is disabled/greyed in the sidebar (no battery) - `shots/settings_pane_Battery.png`.
* Connectivity pane (OBSERVED, `ax_settings_Connectivity.txt`, `settings_pane_Connectivity.png`): `Connectivity` ON · `Duration` 5.0 s · `Low battery warning` ON · `Low battery threshold` slider = 20 % · `Play sound on low battery` ON (`low-battery.caf` STATIC 1.096 s mono 48 kHz) · style segmented picker `3D models` (selected) / `Symbols` as 76x50 preview cards, pitch 88 px.
* STATIC AirPods assets (`/Applications/Alcove.app/Contents/Resources/*.mp4`, 15 files: airpods-3, airpods-4, airpods-pro, airpods-pro-2, airpods-pro-3, airpods-max-{blue,green,midnight,orange,purple,red,silver,sky-blue,space-gray,starlight}): every file **96x96, H.264, 60 fps, 6.000 s, 360 frames, no audio**, alpha-less black background (so they are composited on the black notch). Stills `airpods/<name>_f0.png` and 12-frame strips `airpods/<name>_strip.png`: a slow turntable rotation; first and last frames match ⇒ seamless loop (class `LoopingVideoPlayback` STATIC). INFERRED: shown in the left lobe at ~1x (96 px ≈ 3x the 28 px closed height ⇒ the notch grows for the connectivity card; size UNVERIFIED).
* Sounds STATIC (ffprobe): `event.caf` 1.743 s mono 44.1k s16 · `chime.caf` 4.237 s mono 44.1k s16 · `sleep.caf` 3.002 s mono 48k s24 · `lock.caf` 0.284 s stereo 48k s24 · `unlock.caf` 0.270 s mono 44.1k s16 · `low-battery.caf` 1.096 s mono 48k s16.

---

## 4. Lock Screen
Settings → Lock Screen (OBSERVED, `ax_settings_Lock_Screen.txt`, `settings_pane_Lock_Screen.png`): `Lock Screen` ON · `Keep awake` slider = 0 m · `Show on screen saver` OFF · `Play sound on lock` OFF · `Play sound on unlock` ON · Widgets: `Battery` ON, `Connectivity` ON, `Focus` ON, `Now Playing` ON, `Calendar` OFF · `Material` segmented cards `Glass` (selected) / `Clear` / `Frosted` (76x50 preview cards).
* Live (OBSERVED, lock via ⌃⌘Q keystroke at 10:37:22 and 10:38:02; `clips/lockscreen1.mp4`, `shots/lockscreen_full.png`, `lockscreen_notch_zoom.png`): Alcove's panel **is rendered above the macOS lock screen** (lead's STATIC CGS private-space calls). It shows a white `lock.fill` glyph in the left lobe, nothing on the right. In `lockscreen1.mp4` the lock-screen notch is **216x28** (same as the activity size); 12 s into the second lock the zoom showed a ~140-wide closed notch with the glyph ⇒ INFERRED it may collapse to closed after a few seconds (two observations disagree; UNVERIFIED).
* LOCK transition (`lockscreen1.csv`, `strip_lock1_lock.png`): calendar glyph+ring blur/fade out while width 216 → 144 (f295-315, **350 ms**, ease-out), then lock glyph fades in while width returns 144 → 216 (f316-344, **470 ms**). Same shrink/grow "content swap" pattern as Focus.
* UNLOCK (`strip_lock1_unlock.png`): glyph fades (f745), one frame with no notch (macOS unlock cross-fade, f746), notch re-appears at 134x24 and reaches 140x28 by f765 (~120 ms), holds ~200 ms, then grows 140 → 216 over f777-804 (**450 ms**) with the calendar content fading in.
* Widgets (Battery/Connectivity/Focus/Now Playing/Calendar) had nothing to show on this VM ⇒ widget rendering, Glass/Clear/Frosted materials, screen-saver mode, `lock.caf`/`unlock.caf` playback: **UNVERIFIED**. `pmset displaysleepnow` not used (display sleep would have blanked the capture).
* Operational note: ffmpeg avfoundation captures started while the screen was locked (and later ones while a hung one existed) never produced frames; this cost the 11:00 chime and the first DND recording.

---

## 5. Onboarding & Settings window
### 5.1 Onboarding (OBSERVED, not reset; captured during the normal first run: `shots/onb*.png`, `clips/onb_accessibility_preview.mp4`, `onb_get_started.mp4`)
Steps as in lead notes. The Accessibility step preview loops a Display↔Sound HUD pill animation (`onb_accessibility_preview_strip.png`). `Get Started` closes the card and the black notch appears top-centre.

### 5.2 Settings window geometry (OBSERVED via AX, `ax_settings_*.txt`)
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

### 5.3 Menu bar
Icon: a monochrome display/notch glyph (menu bar x ≈ 1347 at 1600 wide). Menu: see §1.2 (adds `Open in Calendar` / `Dismiss Event` while a calendar event is active; otherwise `Display ▸`, `Version 1.7.7`, `Settings…`, `Quit Alcove`).

---

## 6. Contrast outline & Progressive blur (General → Behaviour; both ON by default)
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

## 7. Animation summary table (OBSERVED)

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

## 8. Late captures

### 8.1 Quick Peek at start for a non-overlapping event (`Dentist` 11:31, OBSERVED, `clips/dentist_1131.mp4`, wallpaper was solid black so the panel outline is not measurable - content bbox used instead, `frame_dentist_1131.png`, `strip_dentist_peek_open.png`)
* Idle activity content (glyph + countdown) occupies x 704-896, y 8-21 before the event.
* Peek onset f1748 (= 11:31:00.0 ± 0.1 s): row-2 content appears and grows y 24 → 55 over f1748-1755 (**7 frames ≈ 120 ms** for the content fade/slide; the panel grow itself is ~200 ms as in §1.5), hold until f1991, row 2 gone by f1994 ⇒ **4.05 s from onset to collapse start**, identical to the 10:12 event. Content: green calendar glyph + ring (right), `Dentist` + `hourglass 1h` row.

---

## 9. Not covered / UNVERIFIED summary
* Battery, Connectivity (AirPods) live notifications, lock-screen widgets + Glass/Clear/Frosted materials, screen-saver mode, lock/unlock/event/chime/sleep sound playback: no hardware / no audio loopback on the VM (settings-level documentation only; another session covers the hardware paths).
* Focus modes other than Do Not Disturb (Sleep/Work/Personal icons & colours), `Replace waveform during focus` (needs Now Playing audio), `Play sound on sleep focus`.
* Calendar: `Show weather on empty day`, `Notify when time to leave` (Location Services unavailable on the VM; both rows show a warning icon), `Disable activity during events` (not exercised), `Use calendar color` vs default colours in the expanded view were captured only with the toggle ON.
* Progressive blur radius/extent (no measurable difference reproduced, see §6); contrast outline over a real notch.
* Onboarding was not re-run (reset not allowed); only the first-run captures from this session exist.
* Exact font faces/weights are inferred from glyph heights (no font introspection).

### 8.2 Hourly chime at 12:00 (OBSERVED, `clips/chime_1200.mp4`, 11:59:30 → 12:01:01, `Play hourly chime` ON, Dentist event in progress so the idle activity showed glyph + ring)
* Notch bbox constant **216 x 29** for the whole clip (`chime_1200.csv`: only a 1 px jitter at f24-25). Region change detector on the notch interior (`framediff.py`, threshold 1.0): `frames 5399;` - i.e. **no visual change at the top of the hour**; the chime is audio-only (`chime.caf` 4.24 s). Audio playback itself UNVERIFIED (no loopback capture). INFERRED: chime fires at the exact hour and the ring-progress frames are the only content updates.
