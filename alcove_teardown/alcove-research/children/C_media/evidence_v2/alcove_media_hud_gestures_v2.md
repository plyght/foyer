# Alcove 1.7.7 (199) – Now Playing / HUD / Quick Peek / Gestures – report v2 (follow-up pass)

This v2 supplements the v1 report `alcove_media_hud_gestures.md` (all v1 measurements still stand; nothing here contradicts them except where noted). Only the section-8 follow-up items are covered: Sound HUD speed/style variants, Now Playing formats + colour derivation, Explicit badge + Extra buttons, Quick Peek, live waveform, cycle activity. Brightness HUD is owned by another session and was not touched.

Environment: same VM as v1 (1600x1200 @1x, Force simulated notch ON, Alcove 1.7.7 build 199, trial active, Music.app with local tracks in playlist `AlcoveTest`: "Short" (no artwork, artist Shorty), "Long Title Track Number One For Marquee Scrolling Test" (blue/green checker artwork, artist Two), "A Very Long Song Title ..." (pink/blue artwork)). Clips are 60 fps ffmpeg/avfoundation (`rec.sh`/`clip.sh`), frame numbers below are 60 fps frame indices in the named clip (1 frame = 16.7 ms). Settings were changed through Alcove's own Settings window via Accessibility (`ax_click.sh X Y` clicks the control at AX position X,Y; `ax_list.sh` dumps controls). Every claim is tagged OBSERVED / STATIC / INFERRED / UNVERIFIED.

Evidence paths in this document are relative to the incremental zip `alcove_media_hud_gestures_evidence_v2.zip` (new files only; v1 zip unchanged).

---

## 1. Sound HUD: Speed (Smooth / Fast / Instant), styles, label/percentage, glyph

### 1.1 Settings pane facts (OBSERVED, `settings_sound.png`, `ax_list.sh` dump)
Sound pane controls (AX positions): enable toggle (1039,195); Duration slider 1.5 s; Progress style segmented buttons White (743,316) / Accent (860,316) / Decibel (977,316); Show percentage (1039,399, default off); Hide label (1039,441, default off); Speed segmented Smooth (743,485) / Fast (860,485) / Instant (977,485); glyph buttons Show symbol (743,569) / Show device (919,569).
Defaults as found on this install: style **White**, speed **Fast**, glyph **Show device**, percentage off, label shown. (Note: v1's HUD clips were therefore recorded with Speed = Fast.)

### 1.2 Protocol
For each speed: `set volume output volume 50` (AppleScript, does not show the HUD), then clip `hud_speed_<Speed>.mp4` (8 s): one synthesized NX_KEYTYPE_SOUND_UP press at ~1 s, then 6 presses 75 ms apart ("held key" auto-repeat emulation) at ~3.6 s. Then clip `hud_tween_<Speed>.mp4` (7 s): three single presses 1.5 s apart so the 2nd press lands while the HUD is already fully open (isolates the fill tween from the open animation).
Bar fill is measured per frame as the horizontal extent of pixels with min(R,G,B) > 180 inside x 820–970, y 4–24 (`barfill.py`; per-clip output `hud_speed_<Speed>.barfill.txt`, summary `hud_speed_scan.txt`, `hud_tween_scan.txt`). Notch bbox per frame is in `hud_speed_<Speed>.csv` (`measure2.py`).

### 1.3 Bar geometry (OBSERVED)
- Filled length at 50 % = 36–38 px; at 87.5 % (after 6 presses of 1/16) = 63–64 px → full track ≈ 73 px (INFERRED: length = 73 px × volume). Track sits in the right wing of the 326 px HUD, label "Sound" + glyph in the left wing (see `shots/hud_style_white_device.png`).
- One key press = +1/16 volume = +4.5–4.6 px of fill.

### 1.4 Fill tween per speed (OBSERVED, `hud_tween_scan.txt`; press #2 while HUD open)
| Speed | frames of fill change for one press (38 → 43 px) | duration |
|---|---|---|
| Smooth | f189→f194 (`hud_tween_Smooth.mp4`) | 5 frames ≈ 83 ms |
| Fast | f195→f201 (`hud_tween_Fast.mp4`) | 6 frames ≈ 100 ms |
| Instant | f199→f203 (`hud_tween_Instant.mp4`) | 4 frames ≈ 67 ms |

With 6 presses 75 ms apart (`hud_speed_*.barfill.txt`), the fill advanced 1–2 px every frame in all three modes (no plateaus/steps), i.e. each new press retargets the running tween rather than restarting from the old value (INFERRED from the monotonic 38→64 px ramp over 24–26 frames for all three speeds: Smooth f278→f305, Fast f274→f298, Instant f277→f296).
Conclusion (OBSERVED): the Speed setting has **no measurable effect on the volume-bar fill tween** at 60 fps (all ≈ 70–100 ms, within ±1 frame of each other). The fill is a short ease (≈ 5 frames) whatever the setting.

### 1.5 What Speed does change: the HUD open/close choreography (OBSERVED, `hud_speed_*.csv`)
When a key arrives while Now Playing is compact (216 px), Alcove first shrinks the media capsule to the bare notch (216→144 px) and then grows the HUD (144→326 px); on dismiss it shrinks 326→~150 and regrows to 216. Width-change frames:
| Speed | shrink 216→144 | grow 144→326 | total appear | dismiss 326→152 | regrow →216 |
|---|---|---|---|---|---|
| Smooth | f102–f122 (20 fr, 333 ms) | f124–f158 (34 fr, 567 ms) | 56 fr ≈ 930 ms | f248–f262 (14 fr, 233 ms) | f262–f296 (34 fr, 567 ms) |
| Fast | f102–f118 (16 fr, 267 ms) | f120–f150 (30 fr, 500 ms) | 48 fr ≈ 800 ms | f244–f259 (15 fr, 250 ms) | f263–f291 (28 fr, 467 ms) |
| Instant | f102–f114 (12 fr, 200 ms) | f117–f142 (25 fr, 417 ms) | 40 fr ≈ 667 ms | f237–f257 (20 fr, 333 ms) | f260–f289 (29 fr, 483 ms) |
Appear curves are monotonic with no overshoot (same as v1). INFERRED: Speed scales the HUD panel transition (Smooth ≈ 1.17×, Instant ≈ 0.83× of Fast), not the bar fill. The bar is drawn only once the capsule is ≥ ~250 px wide (first bright bar pixels at f142/f136/f130 respectively, i.e. ~18 frames after growth starts).
Hold: bar visible from f142 to f248 (Smooth) = 106 frames ≈ 1.77 s after the single press; i.e. Duration 1.5 s is counted from when the HUD has finished opening (INFERRED: 1.5 s + ~0.27 s).

### 1.6 Progress styles / label / percentage / glyph (OBSERVED, screenshots in `shots/`, montage `shots/hud_styles_montage.png`; all captured 0.75 s after one SOUND_UP press from 50 %)
- `hud_style_white_device.png` – White: light-grey filled track (≈ 200/255 grey), dark unfilled track, glyph = **speaker symbol** even with "Show device" selected (no external device on the VM; INFERRED: "Show device" draws the connected output device glyph, e.g. AirPods, and falls back to the speaker symbol). Label "Sound" in white, SF rounded ~12 pt, left of the glyph.
- `hud_style_accent.png` – Accent: filled track in the system accent colour (blue on this VM, (11,36,115)-ish gradient-free solid), everything else identical.
- `hud_style_decibel.png` – Decibel: track replaced by a row of short vertical ticks (bar-graph) that fill left→right; same width.
- `hud_white_showpercentage.png` – Show percentage: numeric "56%" (right-aligned, same font as label) appears right of the bar; bar shortened accordingly.
- `hud_white_hidelabel.png` – Hide label: left "Sound" text removed, glyph stays; bar gains the freed width.
- `hud_white_showpercentage_hidelabel.png` – both.
- `hud_white_showsymbol.png` – Show symbol: identical to Show device on this VM (speaker glyph).
UNVERIFIED: device glyph artwork (AirPods etc.), Decibel style's reaction to muted/0 %.

---

## 2. Now Playing formats Monochrome / Colored / Gradient + colour derivation

### 2.1 Where the format applies (OBSERVED)
The Format segmented control (Now Playing pane, AX (743|860|977, 401)) only changes the **fill of the expanded player's scrubber/progress bar**. The compact view, the artwork, the waveform tint, title/artist and controls are identical across the three formats.
Evidence: `shots/np_art_formats_montage.png` (columns = Monochrome / Colored / Gradient; top = compact, bottom = expanded, track with blue/green checker artwork) and `shots/np_art_compact_*.png`, `shots/np_art_player_*.png`. Measured scrubber fill colour (mean RGB of the filled part, 8 rows at x 680–720 of the screen):
| Format | filled part | unfilled part |
|---|---|---|
| Monochrome | (44,44,46)…(86,86,89) grey | (26,26,28) |
| Colored | (11,36,115) solid blue | (26,26,28) |
| Gradient | (17,34,72) at the left, lighter toward the playhead (horizontal gradient) | (26,26,28) |
With the placeholder artwork ("Short", no artwork): all three formats render the grey Monochrome bar (`shots/np_player_formats_montage.png`), i.e. no colour is extracted from the grey placeholder.
Settings thumbnails (`settings_livewave_hover.png`) preview the same idea: grey / teal / teal→orange bars.

### 2.2 Colour derivation (STATIC + OBSERVED)
- STATIC: the binary embeds the Swift package **DominantColors** (classes `_TtC14DominantColors14DominantColors`, `…12AverageColor`, `…14ColorFrequency`, `…11ImageFilter`; strings `DominantColorAlgorithm`, `DominantColorQuality`, `CIKMeans`, `kMeansClustering`, `DominantColor extract colors: `). That package offers k-means / CIKMeans / area-average extraction with a quality setting; `ColorFrequency` is its result type (colour + frequency). Strings `colorSaturateFilter`, `setSaturation:`, `colorWithHue:saturation:brightness:alpha:` are present next to it.
- STATIC: gradient drawing uses `CAGradientLayer` (`So15CAGradientLayerC`), `gradientStops`, `linearGradientFilter`, `smoothLinearGradientFilter`, `usesGradientFill`, `disableGradient`; the format key is `settings.nowPlaying.colorStyle.gradient`.
- OBSERVED: for the blue/green checker artwork the Colored fill is pure blue (11,36,115) – the most frequent cluster of the artwork, not its average (the average of a 50/50 blue/green checker would be teal). The compact waveform and the expanded waveform glyph are tinted with the same hue family in every format (v1 already reported the waveform tint; `np_art_formats_montage.png` shows blue/green bars).
- INFERRED: Colored = darkened primary dominant colour (k-means) of the artwork; Gradient = linear gradient from the primary to a secondary dominant colour; Monochrome = fixed grey. Exact darkening/saturation factors not recovered.

---

## 3. Explicit badge variants and Extra buttons

### 3.1 Explicit badge (OBSERVED settings only, rendering UNVERIFIED)
Segmented control AX (743|860|977, 316): **None** (⊘ icon), **Explicit** (boxed "E", default), **Format** (a lossless/format glyph). Localisation keys: none found beyond the pane text. The badge is driven by track metadata (explicit flag / audio format); the local test files carry neither, so no badge was rendered in any state. UNVERIFIED: badge glyph size/position. INFERRED from control art: badge is a small rounded square next to the title in the expanded player.

### 3.2 Expanded player layout reference (OBSERVED, `shots/np_expanded_full_zoom.png`, 3× zoom of a 400×150 crop at x 600)
Row 1 (y≈18–72): artwork 50×50 rounded (x 647–697), title (bold 15 pt) + artist (regular 13 pt grey) from x 720, waveform glyph top-right (x≈925–948).
Row 2 (y≈92): elapsed "0:01" at x 650, scrubber 4 px tall from x 680 to 915, remaining "-0:01" right-aligned to x 950.
Row 3 (y≈135): **extra button** (left slot, x≈670), previous ⏮ (x≈735), play/pause (x≈800, white, larger), next ⏭ (x≈865), **output/volume button** (speaker-on-stand icon, x≈931). Button hit areas ≈ 36×36.

### 3.3 Extra button behaviour (OBSERVED, Music.app state read back over AppleScript; `shots/xb_*_before/after/after2.png`, montage `shots/xb_buttons_montage.png`)
| Setting | Icon in left slot | Click 1 | Click 2 | Click 3 |
|---|---|---|---|---|
| Favorite | star outline | `favorited of current track` → true; star becomes filled with a rounded highlighted background | → false (outline again) | – |
| Shuffle (default) | shuffle arrows | `shuffle enabled` → true (icon highlighted) | → false | – |
| Repeat | repeat arrows | `song repeat` → **all** | → **one** (icon gains "1") | → **off** |
| Copy | link/copy glyph | clipboard unchanged (local file: no link) | unchanged | – |
STATIC: `menu.media.copyLink` = "Copy Link", `copyLink`, `setLoved:`/`setFavorited:`, `setShuffleEnabled:`/`setShuffleMode:`, `setRepeatMode:`, `pendingMusicLoved`, `pendingMusicRepeatMode`, `pendingMusicShuffleEnabled`, `SpotifyRepeatMode`, `pendingSpotifyLoved` → the button sends the matching Music/Spotify scripting command (the `pending…` keys suggest optimistic UI with a pending flag until the app confirms). INFERRED: Copy copies the Apple Music/Spotify share link of the current item and is a no-op for local files.
Right-slot speaker button (OBSERVED, `shots/xb_rightbutton_after.png`): clicking it expands the panel downward by one row showing a **volume slider** (speaker-low icon, 170 px track, speaker-high icon) under the transport row; the panel grows from 120 px to ≈ 150 px tall; the button gets a rounded highlighted background while the row is open. Clicking again hides it. This is the "Source"/output row the lead listed; "Source" in Settings is a separate section (Automatic ∙ Music / System) that selects which app Alcove follows, not a button.

---

## 4. Quick Peek (media change)

### 4.1 Trigger conditions (OBSERVED)
- Same-source track changes while the compact Now Playing is on screen do **not** peek (v1).
- Quick Peek fires when a media change happens while the Now Playing activity is **not currently displayed** – e.g. after pause → 3 s idle → collapse to the empty notch, then play a different track. Clip `quickpeek_hidden.mp4` (`.csv`, strips `quickpeek_hidden_strip.png`, `quickpeek_hidden_open_strip.png` (f414–f444 every frame), `quickpeek_hidden_close_strip.png` (f544–f570), `quickpeek_hidden_peekframes.png` (f480, f720 at 3×)).
- Source change (Music → QuickTime) while another activity (Calendar countdown) owned the compact left slot: `quickpeek_qt.mp4` – the left slot flipped from the calendar glyph to the new source's artwork and stayed as long as QuickTime played; it is a source hand-over, not a timed peek (see 4.3).

### 4.2 Peek geometry and timing (OBSERVED, `quickpeek_hidden.csv` columns width/hmax)
Peek layout: a two-row compact capsule, **width 233–237 px, height 70 px** (vs 216×28 normal compact): row 1 = artwork (28 px) left + waveform right exactly as the compact; row 2 = centred "♪ Title · Artist" in ~11 pt grey/white (long titles are clipped, not marqueed, within the ~2 s).
Peek #1 (play "Short" from the empty notch, command at ≈ f416):
- f419 first motion (≈ 3 frames / 50 ms after the AppleScript `play` returned).
- Width 140→237 peak at f432 then settles 233 at f442; height 28→72 peak at f435, settles 70 by f441 → open ≈ 16–23 frames = **270–380 ms**, overshoot +4 px width (1.7 %), +2 px height (2.9 %) (same spring family as the v1 expansion).
- Hold at 233×70 from f441 to f546 = 105 frames = **1.75 s**; total from first motion to start of collapse f419→f546 = 127 frames = **2.12 s** ≈ Peek duration 2.0 s + open.
- Collapse to 216×28: f546→f565/f571 = 19–25 frames = **320–420 ms**, monotonic, no overshoot. Lands in the normal compact (the activity stays).
Peek #2 (switch to "A Very Long Song…" while compact, command ≈ f665): first motion f668, 216→234 width / 28→70 height by f678–f682 (10–14 frames = 170–230 ms, no overshoot measured), hold to f788 (106 frames = 1.77 s), collapse f788→f807/f812 (19–24 frames = 320–400 ms). Artwork flips to the new art inside the peek (f690–f720 in the strip).
INFERRED timing model: peekDuration (2 s) timer starts at trigger; the hold is 2.0 s minus the open animation; open ≈ Spring(duration 0.4, bounce ~0.3) interrupted at settle; close = v1 collapse curve (~400 ms, no bounce).
Also OBSERVED in the same clip: pause → fade 250 ms → 3.0 s idle → collapse f288–f317 (29 frames = 483 ms) 216→140, matching v1.

### 4.3 Source hand-over Music → QuickTime (OBSERVED, `quickpeek_qt.mp4`, `quickpeek_qt_leftslot.txt`, strip `quickpeek_qt_strip.png`)
State before: Music playing, Calendar event due in 20 s → compact shows calendar glyph left + "20s" countdown right. QuickTime `play` issued ≈ f100 (±15 frames recorder offset):
- f109–f121 (200 ms): left slot Y-flips calendar glyph → Music artwork (lit width 18→22 px; the peeked artwork is rendered 22 px vs the 18 px glyph).
- f135–f142 (117 ms) flip out to an 8 px edge, f142–f153 (183 ms) flip in to QuickTime's grey placeholder, f160–f175 cross-fade to the final music-note placeholder tint. I.e. two consecutive 300 ms flips: first the current Now Playing (Music) is surfaced, then the new source (QuickTime) replaces it.
- Holds while QuickTime plays; QuickTime `pause` ≈ f410 → f416–f426 (170 ms) flip back to the calendar glyph.
- Capsule width stayed 216 px throughout; only the left slot changed. Right slot (countdown) untouched.

---

## 5. Live waveform (UNVERIFIED – could not be enabled)
- Now Playing pane row "Use live waveform": toggle (AX 1039,484) plus a **crossed-out microphone** button (AX 1015,484) left of it (`settings_livewave_hover.png`). OBSERVED: clicking the toggle leaves it at 0 (`ax_click.sh` reports value 0; `settings_livewave_click.png`), clicking the microphone button opens nothing (no sheet, no System Settings launch, `full_after_unblock.png`), setting the AX value to 1 is refused. No TCC row for `com.henrikruscon.Alcove` under kTCCServiceAudioCapture/Microphone/ScreenCapture was ever created (`sqlite3 TCC.db`), so the app did not even request capture.
- Audio devices present: BlackHole 2ch (installed in v1) and the VM's ParrotAudioPlugin driver; CoreAudio was restarted (`sudo killall coreaudiod`).
- STATIC: capture stack is SimplyCoreAudio + an aggregate device ("Failed creating aggregate device with error: %d.", `SimplyCoreAudio.defaultOutputDeviceChanged`, …) feeding `WaveformSpectrumSession`/`WaveformSpectrumCenter`/`NSWaveformView` (v1 list). INFERRED: the microphone-slash icon indicates the capture backend is unavailable on this VM (no real output device / aggregate creation fails), so the "unblock" flow never starts; on real hardware it should present the macOS audio-capture permission prompt. Bar count, update rate and amplitude mapping of the live spectrum remain UNVERIFIED. The static 5-bar compact waveform behaviour from v1 is unchanged.

---

## 6. Second activity (Calendar) and "cycle activity"

### 6.1 Getting a second activity (OBSERVED)
Calendar events created with `osascript` into the first writable calendar (`make new event … start date (current date)+480/600`) become a Calendar activity as soon as they are ≤ 15 min away (Alcove had Calendar TCC = allowed; v1's attempt failed only because that event was outside the window at capture time). States seen:
- Playing + upcoming event: **merged compact** 218×29: artwork left with a small red clock badge at its bottom-right corner, right slot = red **countdown ring** (animated arc; `shots/np_compact_two_activities_zoom.png`), which later switches to a red minutes text ("7m", "5m", then seconds "20s"…"8s" in the last 20 s; `cycle_merged_strip.png`, `quickpeek_qt_strip.png`). The waveform is not shown while the countdown occupies the right slot. OBSERVED once (`shots/cyc4_montage.png`): the right slot showed the waveform with no clock badge after a +100 px swipe, see 6.3.
- Expanded while merged: 362–365×120 panel split into Now Playing (left) and the calendar "upcoming" card (right) – `shots/np_expanded_two_activities.png`; during an in-progress event the expanded panel showed the calendar day view instead of the player (`shots/exp_cyc_montage.png`, `xb_*` first run).
- Paused Music + event: after the 3 s idle the compact becomes the pure Calendar activity: red calendar glyph left, countdown ring / "Nm" right (`shots/paused_swipes_montage.png`, `cycle_down_scan.mp4`).

### 6.2 Vertical swipes with two activities (OBSERVED)
- Localised help strings (STATIC `localizable.txt`): `swipeToCycleActivity.info` = "Swipe down to cycle activity"; `swipeToDismiss.info` = "Swipe vertically to toggle activity".
- Swipe **down** on a single visible activity hides it; swipe **up** (−40 px) on the then-empty notch brings it back (`cycle_down_scan.mp4`/`.csv`: Calendar compact 216 → +25 nothing, +40 dismiss (f248–f267, 232→152, 19 frames ≈ 320 ms), +60 on empty nothing, −40 re-show (f578–f608, 153→233, 30 frames = 500 ms), +90 dismiss again). Thresholds for the Calendar activity: +20 no / +30 yes (`cycle_scan5.txt`), i.e. 25–30 px vs the 35 px measured for Now Playing in v1 (INFERRED: same constant, difference due to the hovered capsule height 33 vs 29 px changing the pixel scale, or a separate reset threshold – low confidence).
- With Now Playing + in-progress event merged, +40 dismisses the whole merged capsule to the empty notch and Now Playing does not return by itself (not on pause/play, not on next track, only after `swipe up` or an app restart) – `cycle_scan4.txt`, `shots/after_next.png`.
- Expanded (two activities): +40/+60/+80/+100 produce no change in content (`shots/exp_cyc_montage.png`, `exp_cyc_*.png`); close still needs >100 px (v1).

### 6.3 Cycle threshold (PARTIALLY OBSERVED, low confidence)
On the merged compact (Now Playing + upcoming event, Swipe to skip media temporarily OFF so horizontal swipes could not be consumed – horizontal −40…−200 and +40…+200 px never changed anything, `cycle_scan2.txt`, `cycle_scan3.txt`), a downward scan gave (`cycle_scan6.txt`, `shots/cyc4_montage.png`): +50 → unchanged (ring), +70 → right slot shows "7m" text, +100 → right slot shows the **Now Playing waveform and the clock badge disappears** (i.e. the capsule cycled to the Now Playing-only presentation), +140 → dismissed to the empty notch. A 60 fps repeat 1 min later (`cycle_merged.mp4`, strip `cycle_merged_strip.png`, `.csv`) with +70 then +100 showed only the hover growth (216→236→216) and no content change, while the ring→"5m" switch happened on its own 6 s into the clip, before any swipe. Therefore: the ring ↔ minutes alternation is autonomous (not swipe driven); the one waveform appearance after +100 px is the only candidate cycle event. INFERRED cycle threshold: between 70 and 100 px accumulated downward scroll, below the ~105 px needed to close an expanded panel and above the 30–35 px dismiss threshold; the gesture seems to require a pending idle activity (`pendingCycleIdleActivity`, `_cycleSwipeReadyOnRelease` STATIC) and resolves on release. UNVERIFIED: reset threshold, haptic (`_hasTriggeredCycleThresholdHaptic` STATIC), behaviour with a Focus activity.

---

## 7. Settings restored
After the pass: Sound HUD White / Fast / Show device, percentage off, label on; Now Playing Format Monochrome, Extra button Shuffle, Explicit badge "Explicit"; Swipe to skip media back ON; live waveform off (never enabled); Music shuffle off, repeat off; test calendar events deleted.

## 8. Still open
Explicit/Format badge rendering (needs explicit/lossless metadata), live waveform (capture backend unavailable on VM), cycle-activity confirmation with a third activity type (Focus/battery), device glyphs for Show device, Spotify/Apple-Music "Copy Link" result.

## 9. New tools in this pass
- `ax_list.sh` – dumps class/value/position of every control in the frontmost Alcove Settings window.
- `ax_click.sh X Y` – AX-clicks the control at that position (needed because `defaults write` of guessed keys does not change runtime settings).
- `barfill.py clip x0 x1 y0 y1 fa fb [thr]` – per-frame HUD bar extent/brightness.
- Scan logs: `hud_speed_scan.txt`, `hud_tween_scan.txt`, `cycle_scan1..6.txt`.
