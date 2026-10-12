# Alcove native live test log

Completed the bounded native GUI procedure on macOS 26.6.2 (25G83), Alcove 1.7.7 (199), using the normally installed `/Applications/Alcove.app`, a simulated notch, and explicitly labeled local synthetic controls. This was reverse-engineering/runtime testing, not app implementation or licensing inspection.

## Limitations and unexpected behavior

- **Specific-display unplug has no visible primary fallback.** With only the synthetic display selected, removing that display left the primary notch absent and the picker without a selected available target. Reconnecting the same synthetic identity restored targeting, despite its numeric display ID changing from 3 to 4. This is observed behavior, not an undocumented fallback guarantee.
- **First display-helper attempt exited during unplug.** This was the temporary test helper, not Alcove. Setting its ARC-owned NSWindows' `releasedWhenClosed` to false allowed the final disconnect to report `NSScreen count: 1` normally. The recovered target was verified after relaunching the helper; do not describe that first attempt as an uninterrupted same-helper cycle.
- **Redundant parallel ffmpeg recorder stalled before stream initialization.** It produced no MP4 and was stopped. The primary recording tool's own ffmpeg source was intact: 13 completed segments, 93,285 decoded frames over 1,586.934 seconds, nominal 60 fps and approximately **58.78 average captured fps**, with an initial gap. Do not call this perfect constant-60-fps capture, and do not use the erroneous Matroska `avg_frame_rate=30000` metadata.
- **Sound HUD was established earlier, but the final isolated volume workload screenshot did not visibly establish a HUD.** The earlier gaming-OFF Sound overlay and gaming-ON suppression are verified. The later phase is a timestamped media-key workload, not a separately verified continuous-HUD performance phase.
- **About Alcove presentation was reached and recorded; white-circle particle emission remains visually inconclusive.** Settings > About is a distinct updater pane. Native Now Playing and its performance phase were not established; no retry was made.
- Normal Accessibility prompting resurfaced after the URL sequence. Opening the normal System Settings pane showed Alcove enabled. The cause of the repeat notice was not established.
- The four Riot identifiers and Minecraft-path fallback were not individually live-triggered. Their broader list/path behavior remains the lead's static evidence; live identification proof here uses only the requested synthetic GeForce-ID control.
- No reboot-cold launch, physical-notch/physical-monitor assertion, waveform correctness, physical haptics, low-power/reduced-motion, lock-screen, badge, or cycle-swipe testing is claimed.

## Assertions

- **Passed:** Neutral identifier `local.devin.alcove.synthetic-category` with category `public.app-category.action-games` retained a visible notch in windowed and native-fullscreen states while fullscreen hiding was OFF and gaming hiding was ON.
- **Passed:** Synthetic `com.nvidia.gfnpc.mall`, category utilities, hid the notch when frontmost with gaming hiding ON; OFF restored it.
- **Passed:** Switching foreground between the neutral category helper and listed-ID helper restored/hid the notch respectively. Listed-ID native fullscreen remained hidden with fullscreen hiding OFF.
- **Passed:** With gaming hiding OFF, ordinary media-key events produced Alcove's Sound bar; pointer input changed the overlay state. With gaming hiding ON and the listed helper frontmost, Alcove's notch/Sound bar were absent while the macOS fallback volume indicator appeared.
- **Passed:** `alcove://`, `alcove://unknown`, and `alcove://settings` did not navigate to a Settings/deep-link content surface. No license URL was invoked.
- **Passed:** Settings > About exposed version/updater controls without pressing Check Updates, changing auto-update, sending feedback/keys, purchasing, or installing anything.
- **Passed:** General > Display on offered Main display, All displays, Apple Virtual, and Alcove Synthetic Display.
- **Passed:** Main display rendered the notch only on the primary; All displays rendered it on both; specific synthetic targeting rendered it only on the secondary. Both screen captures were checked.
- **Passed with setup interruption noted above:** Unplug removed the synthetic picker choice; reconnecting the same synthetic identity restored the specific target. Final disconnect returned to one screen.
- **Passed:** Pointer clicks opened the actual Calendar notch; pointer exit closed it. Four repeated cycles were captured.
- **Passed:** One authorized process-cold launch after the lead's passive monitor completed replaced PID 3840 with PID 7236 and returned the simulated notch without onboarding.
- **Inconclusive:** White-circle particles in the separate About Alcove view.
- **Untested:** Native Now Playing performance phase; individual remaining game identifiers/path fallback; reboot-cold latency.

## Primary evidence

The single annotated recording is **92.15 seconds**:

`/Users/devin/screencasts/alcove-live-primary/alcove-live-primary-edited.mp4`

Full source export, preserving captured frames and local timing rather than forcing constant-rate frame duplication:

`/Users/devin/alcove-uncovered/ev/live/primary_raw_60fps.mp4`

Source segment manifest:

`/Users/devin/alcove-uncovered/ev/live/RAW_MANIFEST.json`

Native source segments:

`/Users/devin/screencasts/alcove-live-primary/alcove-live-primary-raw-000.mkv` through `alcove-live-primary-raw-012.mkv`.

The annotated video's timing is edited/compressed and must not be used for latency measurement. The raw segments' frame PTS and visible clock are authoritative.

### Gaming identification comparison

| Neutral game-category control: fullscreen, notch visible | Fixed-ID control: gaming ON, notch hidden |
| --- | --- |
| ![Neutral category fullscreen](https://app.devin.ai/attachments/f0e2b246-63e6-4d20-9c9c-eec324fd9db9/02_category_fullscreen_notch_visible.png) | ![Listed-ID hiding](https://app.devin.ai/attachments/8d1f7df5-41a5-4f5d-b23c-f740e21c249f/05_listed_gaming_on_hidden.png) |

### Sound HUD before/after gaming hiding

| 🔴 Before: gaming hiding OFF, Alcove Sound bar | 🟢 After: gaming hiding ON, Alcove HUD suppressed |
| --- | --- |
| ![Sound HUD with gaming OFF](https://app.devin.ai/attachments/4e86c25e-7d5b-4c13-a071-147f3fe77356/11_sound_hud_gaming_off.png) | ![Gaming ON suppression and native fallback](https://app.devin.ai/attachments/87c894c6-a3a1-4cf0-ae2f-139f78b2e6ff/12_sound_hud_gaming_on_suppressed.png) |

### All displays

| Primary: notch visible | Secondary: notch visible |
| --- | --- |
| ![All displays primary](https://app.devin.ai/attachments/08e74ff7-ae74-4411-85ea-82f119abc34d/15_all_primary.png) | ![All displays secondary](https://app.devin.ai/attachments/09cba337-54d0-448a-9d63-dabbea03de2b/16_all_secondary.png) |

### Specific display

| Primary: notch absent | Selected secondary: notch visible |
| --- | --- |
| ![Specific target primary absent](https://app.devin.ai/attachments/683274b1-eece-4d61-a02d-a16c0756f3ce/17_specific_primary_absent.png) | ![Specific target secondary visible](https://app.devin.ai/attachments/355f984f-0aaf-4c5a-8014-e7fb43f22583/18_specific_secondary_visible.png) |

### Distinct About presentations

| Settings > About: updater pane, untouched | Menu > About Alcove: separate presentation |
| --- | --- |
| ![Untouched updater pane](https://app.devin.ai/attachments/03c06a61-066b-4ca0-a7d6-b9646375214c/10_about_updater_untouched.png) | ![Separate About Alcove](https://app.devin.ai/attachments/3d6cd52a-a618-4c22-901b-3a7236bd448d/ss_160dff90.png) |

The separate presentation is also visible in source segment 008, including sampled frames 0 and 480, saved as `about_source_01.png` and `about_source_02.png`. The presentation remained open across these samples; no white-particle motion is claimed from them.

## Process-cold timing

One process-cold launch was authorized only after the lead confirmed the 20.5-minute monitor and final snapshots were complete. This is **warm filesystem cache**, not a reboot-cold measurement, and one VM observation, not a benchmark series.

- Old PID 3840 was quit through the native Quit Alcove command and confirmed absent at 17:19:13 PDT.
- A local native one-shot clock helper launched the installed app through NSWorkspace at **2026-10-12T00:19:29Z / 17:19:29 PDT**.
- NSWorkspace completion returned new PID 7236 after 58 ms. That is **not** the first-notch latency.
- In raw segment 012, zero-based frame **3383**, PTS **59.467 s**, the notch was absent and the visible monotonic launch clock read **1.006 s**.
- Adjacent frame **3384**, PTS **59.483 s**, first showed the notch and the clock read **1.021 s**.
- Observed clock bracket: **1.006–1.021 s**, approximately **1.02 s request-to-first-notch**, subject to timer/display/capture refresh granularity. No tighter precision is claimed.

| 🔴 Before: frame 3383, no notch, clock 1.006 s | 🟢 After: frame 3384, first notch, clock 1.021 s |
| --- | --- |
| ![Last frame without notch](https://app.devin.ai/attachments/312cd174-397e-408f-b465-854b86dc19c9/cold_before_first_notch_3383.png) | ![First frame with notch](https://app.devin.ai/attachments/141cf0e0-7492-4f5f-b91c-44e07aa623a5/cold_first_notch_3384.png) |

Frame extraction decoded with `-fps_mode passthrough` so VFR gaps did not introduce duplicate-frame index errors. Supporting files: `COLD_FRAME_TRANSITIONS.json`, `COLD_LAUNCH.log`, `LaunchClock.swift`, and `export_evidence.py`.

## Workload timestamps for the lead

These are inputs/scenarios only; no CPU, memory, power, or benchmark tooling was run by this agent.

| Phase | PDT start | PDT end | Coverage |
| --- | --- | --- | --- |
| Earlier volume/Sound HUD workload | 17:03:20.569 | 17:03:52.259 | Sound HUD established, with pointer interaction near the end |
| Idle, Settings closed | 17:11:03 | 17:11:51 | Closed notch, helpers stopped |
| Repeated open/close window | 17:11:51 | 17:12:56 | Four cycles; window includes tool/annotation overhead, not continuous inputs for all 65 seconds |
| Final media-key workload | 17:13:49.583 | 17:14:21.194 | 60 alternating key pairs; final screenshot did not establish a visible HUD |
| Now Playing | — | — | Unverified, not established |

The earlier volume phase occurred while the growth monitor was running; the final volume phase was later. Use the original `PHASES.log` rather than inferring timing from the speed-edited video.

## Setup and leave-behind

Normal installation/onboarding and Calendar/Bluetooth/Accessibility GUI permissions were used. The sidebar showed Trial; no license route, license data inspection, signing modification, binary patch, or activation bypass occurred. An initial mounted-volume duplicate was stopped before the configured Applications instance became the test process.

BlackHole 2ch and SwitchAudioSource were installed normally through Homebrew; coreaudiod was refreshed once through an available noninteractive authorized command, and output was selected as BlackHole 2ch. Earlier media-key attempts did not show a HUD; the functioning temporary event helper uses standard system-defined subtype 8 key-down/up flags `0xA00`/`0xB00`.

At handoff:

- `/Applications/Alcove.app/Contents/MacOS/Alcove` **PID 7236** is running.
- Last configured state: Force simulated notch ON; Hide while gaming OFF; Hide in fullscreen OFF; Main display.
- The fresh process visibly restored its simulated notch without onboarding. General toggles were not reopened after the final launch.
- Settings/About and notch content are closed; all synthetic game/display/clock helpers are stopped.
- Output device remains **BlackHole 2ch**; no local playback/Now Playing is left active.
- Native open/close recipe: click the top-center simulated notch (approximately 512, 10 in the tool's 1024×768 coordinate space), then move the pointer outside to close. The opened surface was Calendar.
- Volume trigger recipe, verified earlier: `/Users/devin/alcove-uncovered/ev/live/VolumeKey up` or `down`. A later phase was visually inconclusive, so do not assume every invocation produces the HUD.

Helper sources/bundles are retained under `/Users/devin/alcove-uncovered/ev/live` for reproducibility. They are clearly synthetic test tools, not GeForce NOW or real games.

## Remaining delivery items

- Suggested PR comment: **none**. This is a native app RE task, not an open PR.
- SKILL.md suggestion: `/Users/devin/alcove-uncovered/MACOS_CAPTURE_UPDATE.SKILL.md`, proposed update to existing macOS VM capture guidance.
- Blueprint: no organization-wide blueprint exists; the evidence directory is not a resolvable repository checkout. Suggested optional native-test knowledge/setup: existing Xcode command-line tools and ffmpeg, on-demand BlackHole/SwitchAudioSource output configuration, single-owner AVFoundation recording, and explicit synthetic helper lifecycle cleanup. Do not make device/permission changes unconditional for all repositories.
- Still needed from user: **none** for the bounded pass. Remaining unverified items above must not be represented as completed.
