# Alcove 1.7.7 (199): uncovered areas 7–14

Supplement to the supplied v2 teardown, not a replacement. Analysis date: 2026-10-11/12 UTC. Target: `com.henrikruscon.Alcove`, arm64 slice, macOS 26.6.2 (25G83) VirtualMac2,1. Installed universal executable SHA-256: `f8c83e2473d4ce9b9ba11f597cdbac6be84aeb127946fc55d12a449098bd032f`; analyzed arm64-slice SHA-256: `14520b5dd7b91b6e248122194dc206634173fb014d105a308d824974d4f653ec`. Addresses below are **unslid virtual addresses** in the main executable unless prefixed **helper**; actual process load addresses differ under ASLR.

## Evidence conventions and scope

- **OBSERVED:** measured from this VM, captured UI, endpoint response, or a tool execution.
- **STATIC:** directly recovered from this build's executable, metadata, or bundled resources.
- **INFERRED:** interpretation of static context, with the remaining ambiguity identified.
- **UNVERIFIED:** not demonstrated, including hardware and paths deliberately left alone.

Evidence paths refer to the root of the accompanying ZIP. Screen recordings and synthetic tests are not measurements of a physical notched Mac. No Alcove binary was modified. No probe sent a license key, explicitly invoked a license endpoint, or installed an update. Ordinary app startup/background network traffic was not comprehensively audited. Licensing internals and license-route execution are excluded. Separately assigned waveform rendering, explicit badges, lock-screen widgets, activity swipes, Low Power Mode UI, and reduced-motion/transparency behavior were not re-investigated.

## 7. GameManager

### Answer

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

### Controlled live findings

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

## 8. All 13 bundled sounds

### Measurements

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

### Events, call sites and gates

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

### What `haptic.caf` actually is

**STATIC + OBSERVED offline:** A short, approximately 10.6 ms, **ordinary mono audio file**, not a haptic pattern file or an instruction to a Taptic Engine. GeneralSettingsView's `settings.general.tuning.notchWidth` control (`0x10032be78`) installs a Double-value-change callback (`0x10032c14c`); that callback ultimately plays `haptic.caf` through AVAudioPlayer (`0x10032c9c8`). This is audible calibration feedback.

**STATIC:** Physical haptics are a different implementation: `NSHapticFeedbackManager.defaultPerformer` and `performFeedbackPattern:performanceTime:` around `0x100073a50–0x100073aac`, governed by `enableHaptics`. Do not implement the tiny CAF as a substitute for every physical-haptic event, or assume disabling physical haptics necessarily mutes this tuning tick.

**Evidence:** `static/systemsound_*.txt`, `static/sound_detail_*.txt`, `static/haptic_context_10032c14c.txt`, `static/fn_100021f14.txt`, `static/fn_1000739ac.txt`, `static/swift_types_scoped.json`.

**Residual uncertainty:** Acoustic playback of every event, hardware battery paths, Focus transitions, and exact gain/scheduling during all UI sequences were not exhaustively tested. The measurement table describes the files, not a promise of those levels from speakers. The naming is counterintuitive: the recovered `low-power.caf` call is gated by `playSoundOnLowBattery`, while `low-battery.caf` is used by the connected-device path; do not infer event semantics from filenames alone. No license UI state was forced to play blips.

## 9. `alcove://` URL handling

**STATIC:** Info.plist registers one scheme, `alcove`. `application:openURLs:` at `0x10020354c` bridges the URL array and calls `0x100204448`. The handler walks each URL's `absoluteString`, checks the literal scheme prefix using `String.hasPrefix` (`0x10020453c–0x100204568`), and then dispatches its remaining string.

**STATIC:** The only recognized route found in that dispatcher is **license-related (`license`)**. Per scope, only its existence is recorded; parameters, payload handling, downstream logic and execution are intentionally omitted. There is no recovered non-license host/path/query route for Settings, About, Now Playing or notch control. This is not a broad deep-link API with an undocumented switch of feature routes.

**STATIC:** Safe unsupported inputs fall through rather than selecting a feature. A successful `open` exit code alone only proves Launch Services accepted a registered scheme; it does not prove Alcove recognized a route.

**OBSERVED safe negative controls:** `open 'alcove://'`, `open 'alcove://unknown'`, and `open 'alcove://settings'` were accepted by Launch Services but did not open settings or produce visible Alcove content changes. These are negative controls, not three supported routes. Screenshots: `live/07_url_root.png`, `08_url_unknown.png`, `09_url_settings_noop.png`. No license URL was called.

**Evidence:** `static/plist_scoped.json`, `static/url_dispatch_scoped.txt`. The excerpt includes the scheme gate and array-dispatch wrapper but deliberately omits license processing.

**Residual uncertainty:** No license route was called. Case, escaping and unusual URL payload behavior beyond the safe tests are UNVERIFIED; they are not useful supported clone features on the evidence available.

## 10. Vortex particles

### Used configurations versus library contents

**STATIC:** Three **app-level direct custom VortexSystem construction sites** were found, all using `circle`, not three different rain/snow/confetti presets:

| App context | Constructor / call site | Birth rate | Lifespan |
|---|---|---:|---:|
| About presentation | `0x100264d34`; called at `0x100263660` | 8.5/s | 3.5 s |
| Update presentation | `0x10028ed6c`; called at `0x10028ec2c` | 8.5/s | 3.5 s |
| Intro presentation | `0x1002ad958`; called at `0x1002ac8a8` | 10/s | 4 s |

These constructors share the same floating white particle configuration. The linked Vortex library also contains preset implementation code. **Bundled preset code/assets do not establish that Alcove invokes those presets.** The recovered weather strings (`isRaining`, weather SF Symbols, etc.) are not sufficient evidence of a Vortex rain/snow call path. No app-level calendar celebration or weather precipitation trigger was established.

### Recovered parameter values

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

## 11. Update mechanism

### Request, response and interval

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

### JSON model: static, not a successful server sample

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

### UI, download, checks and installation

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

## 12. AppleScript

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

## 13. Performance

### Method and VM limits

**OBSERVED:** PID 3840 remained unchanged for all 42 samples over **1,230.007 seconds (20.5 minutes)**, from 2026-10-11 23:51:53.649 UTC to 2026-10-12 00:12:23.690 UTC. Initial process age was about 1m59 s, final age22m29 s. Collection used `ps` every 30 s and two-sample `top`, plus continuous ~1 s `top` / task `powermetrics` samples, and before/after `footprint`, `vmmap --summary`, `sample` snapshots.

This was a **mixed-workload run**, including game controls, Settings/About, virtual-display attach/detach, sound HUDs and a BlackHole/coreaudiod change around 17:00 PDT. Recording and measurement processes were active. It is neither a physical-Mac energy benchmark nor a controlled idle leak test. The bounded idle phase was collected after helpers were stopped and Main display restored.

### Bounded workload table

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

### Memory growth and snapshots

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

### Launch latency

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


## 14. Multiple displays

### Static selection and lifecycle

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

### Synthetic second-display experiment

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

## Reproduction and archive map

- `static/`: scoped disassembly, field/asset inventories, plist/dictionary, updater response.
- `sounds/`: all 13 waveform PNGs and measurement JSONs.
- `live/`: test report, synthetic sources, screenshots, 60 fps clips/frame strips and event logs.
- `perf/`: raw top, powermetrics, footprint, vmmap, sample and long-run records, plus computed tables.
- `scripts/`: measurement and evidence-processing scripts; no credential-bearing scripts.

The archive deliberately excludes full app binaries, bulk licensing disassembly, account credentials, trial/license preference values, and license-route payload analysis. Excerpts preserve the addresses needed to reproduce the non-license findings from the public build.

## Evidence navigation and recording limits

The accompanying ZIP includes `README.md` and `MANIFEST.sha256`, scoped static dumps, every measured sound/resource/waveform, synthetic helper source/bundles, UI screenshots, raw performance logs and reproducible analysis scripts.

- `live/raw_capture_segments/`: **13 losslessly remuxed raw capture segments**, preserving the source video bitstream without visual re-encoding. Nominal rate 60 fps; 93,285 decoded frames across 1,586.934 seconds, about 58.78 fps over the full recording. Source frame-rate metadata alone is not proof of perfect 60 Hz capture; timestamp gaps exist, especially in the initial segment.
- `live/video_inventory.json`: original raw filenames/SHA-256 hashes, FFprobe counts/durations and sampled timestamps. The original Matroska containers were remuxed to MP4, not flattened to artificial constant-rate timing.
- `live/frame_strips/`: one four-frame contact strip per source segment, labelled with source clip and local seek time. Full-resolution pixels remain in the clips; strips are overview aids, not pixel-accurate measurement images.
- `live/01_...png` through `live/23_...png`: full uncropped desktop captures of key assertions. Secondary-screen captures are their own full synthetic desktop, not cropped primary screenshots.
- `perf/`: all measurements and computed summaries; `growth_rss.png` plots the full 20.5-minute RSS series.

A redundant separate FFmpeg/AVFoundation recorder stalled during startup and produced no usable parallel file. The successful primary recorder's raw source is retained in the MP4 segments above. Its annotated presentation may slow around test annotations; use **raw frame PTS and the visible launch clock**, not the annotated player's elapsed time, for timing claims. No audio track was captured in this screen recording; source-file audio measurements and playback call sites must not be mistaken for a live microphone/SPL test.
