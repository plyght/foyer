# Alcove 1.7.7 (build 199) – runtime inner workings, observed from outside

Scope: observe the *running* app on a macOS VM (macOS 26.6.2 / 25G83, arm64, 1600×1200 @1×, no physical notch,
no battery, no AirPods, no Touch ID, single "Apple Virtual" display). The app was installed from
`https://download.tryalcove.com/Alcove.dmg`, onboarded, trial started, and **Force simulated notch** turned on.
Nothing license/trial related was bypassed, patched, replayed or reverse‑engineered; only the public endpoints
and the fact that a trial exists are described.

Labels used on every claim:
* **OBSERVED** – seen live on this VM (file/line/screenshot given).
* **STATIC** – read from the bundle on disk (Info.plist etc.).
* **INFERRED** – my interpretation of observations; verify before relying on it.
* **UNVERIFIED** – needs hardware this VM lacks (real notch, battery, AirPods, Touch ID, 2nd display).

Evidence root in the zip: `ev/` (`scripts/`, `windows/`, `shots/`, `defaults/`, `logs/`, `proc/`, `net/`, `tcc/`, `media/`).
`ev/lead_NOTES.md` is the lead session's static‑analysis notes (not mine, kept for cross‑reference).

---

## 0. TL;DR for the clone author

| Topic | Finding (label) |
|---|---|
| Window model | Exactly **two** always‑on‑screen windows, both **624×320 px, fixed**, top‑centred on the display (x=488 on a 1600‑wide screen), `alpha=1.0`, at CGWindowLevels **2147483628** and **2147483629** (= `kCGMaximumWindowLevel‑19/‑18`, i.e. above everything incl. menu bar). All visual states (idle notch, hover, expanded, HUD, Now Playing) are drawn *inside* these fixed panels; the windows never move or resize. **OBSERVED** (`windows/states.txt`). The two‑window split is **INFERRED** to be backdrop + content (names are empty at the CG level). |
| Visible geometry inside the panel | idle notch 144×29 at x=728..871; hover 156×33; Sound HUD 332×29 at x=634..965; expanded Calendar 369×175; expanded Now Playing 375×175; compact Now Playing 222×29 (details §1.3). **OBSERVED** |
| Hide from screen capture | Flips `kCGWindowSharingState` of both panels 1→0 (`NSWindow.sharingType = .none`); `screencapture` then shows the wallpaper where the notch was. Works live, no relaunch. **OBSERVED** |
| Persistence | Plain `UserDefaults` in `~/Library/Preferences/com.henrikruscon.Alcove.plist`; ~100 keys, camelCase, enums as lowercase strings; **keys are not written until the user changes them** (registered defaults). No iCloud KVS activity seen. **OBSERVED** (§2) |
| Helper | `AlcoveHelper.xpc` (bundle id `com.apple.controlcenter.AlcoveHelper`, `ServiceType=Application`) is spawned **within 1 s of launch**, lives for the whole session, 2–4 threads, ~3 MB. It is the process that talks to `MediaRemote` (NowPlaying notifications, `getNowPlayingInfoForBundleIdentifier:` XPC). **OBSERVED/STATIC** (§4) |
| Idle cost | Alcove 0.0–0.1 % CPU, ~71–73 MB RSS, 8–10 threads, ≈1.6 CPU‑ms/s, ≈6 wake‑ups/s, Energy Impact 0.16 – *same* idle vs. expanded‑with‑waveform in `powermetrics` samples. **OBSERVED** (§4.3) |
| Network | Only app host: `api.tryalcove.com` (Cloudflare, HTTP/3 alt‑svc). Also WeatherKit via Apple's `com.apple.weatherkit.authservice` + CoreLocation at launch. `/changelog` is public JSON (200); `/updates/latest` answers **401 "An active license is required for this channel."** on an un‑licensed GET. **OBSERVED** (§5) |
| TCC | Requests Calendar, BluetoothAlways, Accessibility (and prompts Location once). With Accessibility revoked **and relaunched**, media keys no longer produce Alcove's HUD (volume still changes via the system); re‑granting in System Settings restores the HUD **without relaunch** (it re‑checks trust at runtime). **OBSERVED** (§6) |
| Media keys | Synthetic `NX_SYSDEFINED` key events (`CGEvent.post(.cghidEventTap)`) → Alcove HUD. `osascript set volume` → volume changes, **no** Alcove HUD. Brightness keys → nothing visible on this VM. **OBSERVED**; OSD suppression on real hardware **UNVERIFIED** (the VM has no `OSDUIHelper` at all). (§7) |

---

## 1. Windows (`CGWindowListCopyWindowInfo`)

Scripts: `scripts/winlist.py` (one‑shot dump: wid, layer, bounds, alpha, sharing, on‑screen, name),
`scripts/winsample.py` (20 Hz sampler that prints whenever the window set changes),
`scripts/osd_check.py` (lists OSDUIHelper/BezelUIServer/Alcove windows), `scripts/measure_bbox.py`
(bounding box of near‑black pixels in a screenshot = visible notch/HUD body).

### 1.1 Inventory – identical in every state (OBSERVED, `windows/states.txt`)

First process (pid 2607, launched through onboarding):

```
wid  layer       x    y  w     h    alpha sharing onscreen name
43   0           0    0  1600  30   1.0   1       F        ''
44   0           0    0  1600  30   1.0   1       F        ''
45   0           0    0  1600  30   1.0   1       F        ''
46   0           0    0  1600  30   1.0   1       F        ''
115  2147483628  488  0  624   320  1.0   1       T        ''
116  2147483629  488  0  624   320  1.0   1       T        ''
```

After relaunch (pids 8594 and 10160) only the two high‑level panels exist (wids 221/222, then 250/251, same geometry).
→ the four layer‑0, 1600×30, off‑screen windows are **INFERRED** leftovers of the first‑run/onboarding flow
(or menu‑bar extras created once), not part of the steady‑state notch UI.

States sampled with the sampler running (no change in count, bounds, alpha or sharing between them):
idle‑closed, hovered, expanded (Calendar), expanded (Now Playing), Sound HUD (vol‑up, mute), Now Playing compact,
QuickTime playing/paused, Settings window open (adds the normal `General`/`About` NSWindow at layer 0),
Safari fullscreen attempt, Mission Control attempt, hideFromScreenCapture on/off (sharing flips, see 1.4).

Key facts (OBSERVED):
* Window count in steady state: **2** (plus a normal titled Settings window when open; plus the onboarding windows in the first process).
* Bounds **never change**: `(488, 0, 624, 320)` on a 1600×1200 display → horizontally centred (1600/2 − 624/2 = 488), anchored to the top edge.
  Clone: one centred 624×320 (or display‑relative) transparent panel is enough; animate the *content*, not the window.
* `kCGWindowAlpha` always `1.0` – fading is done in layers inside, not with window alpha.
* `kCGWindowName` empty, `kCGWindowOwnerName` = `Alcove`.
* Levels 2147483628/2147483629 = `CGWindowLevelKey.maximum` − 19/−18 (above `kCGScreenSaverWindowLevel`=1000 and the menu bar); this is why the notch body covers the menu bar region.
* Settings window: ordinary `NSWindow` (layer 0, title "General"/"About"/…), Liquid‑Glass sidebar, 11 sidebar items (General; Notifications: Battery(disabled on VM), Connectivity, Focus, Display, Sound; Live Activities: Now Playing, Calendar, File Tray(“Soon”, disabled), Lock Screen; Alcove: License(“Trial” badge), About) – `shots/settings_about_check_updates.png`.

### 1.2 What is *not* observable from CGWindowList
Panel class names (NotchPanel / NotchBackdropPanel / lock panel) are **not** exposed (names empty). Lock‑screen and
screensaver panels: **UNVERIFIED** (locking the VM session kills the remote display; not attempted).

### 1.3 Visible geometry per state (near‑black bbox in 1× screenshots, OBSERVED, `windows/bbox_measurements.txt`, `windows/stop_burst_bbox.txt`)

| State | x range (px) | width | y range | height | screenshot |
|---|---|---|---|---|---|
| Idle simulated notch | 728..871 | **144** | 0..28 | **29** | `shots/state_relaunch_ax_revoked_volup.png` (HUD suppressed, so pure idle) |
| Hover (expandNotchOnHover=false) | 722..877 | 156 | 0..32 | 33 | `shots/state_hover.png` |
| Expanded – Calendar idle activity | 616..984 | 369 | 0..174 | 175 | `shots/state_expanded.png` |
| Sound HUD (vol up) | 634..965 | 332 | 0..28 | 29 | `shots/state_hud_volup_mediakey.png` |
| Sound HUD (mute) | 634..965 | 332 | 0..28 | 29 | `shots/state_hud_mute_mediakey.png` |
| Now Playing expanded (QuickTime) | 613..987 | 375 | 0..174 | 175 | `shots/state_nowplaying_qt_expanded.png`, `zoom_nowplaying_expanded.png` |
| Now Playing compact (playing) | 613..987 | 375 | 0..~59 | ~60 (crop) | `shots/state_nowplaying_qt_compact.png` |
| Now Playing compact after mouse leave / paused | 689..910 | 222 | 0..28 | 29 | `shots/state_nowplaying_after_mouse_leave.png`, `peek_burst_*.png` |

Notes: the idle notch is symmetric about x=800 (centre of a 1600‑px display); the HUD grows symmetrically (±94 px each side);
expanded states grow to ≈370 px wide and 175 px tall. Heights of 29 px for the closed shapes include the 1‑px dark
edge of the menu bar region, so treat as 28–29 px. Timing (open/close animation) is in the lead's `measure.py`
clips, not re‑measured here.

### 1.4 Hide from screen capture (OBSERVED, `windows/states.txt` + `shots/capture_hfsc_off.png` / `capture_hfsc_on.png`)
`defaults write com.henrikruscon.Alcove hideFromScreenCapture -bool true` (the app observes the key live):
both panels go `sharing 1 → 0`; `screencapture -x -R` of the notch region then contains **no dark pixels**
(wallpaper shows through); setting it back to false restores `sharing=1`. Windows stay in the list, bounds unchanged.
Clone: `window.sharingType = .none` toggled from the preference.

### 1.5 Hide in fullscreen / Mission Control (PARTIALLY OBSERVED)
With `hideWhileInFullscreen=1` and Safari sent to fullscreen via AppleScript/keyboard, the two Alcove windows **remained in
the CGWindow list with unchanged bounds/alpha** (`windows/states.txt` "fullscreen_*"). Visually the automation did not
reliably produce a true fullscreen Space in the VM, so whether Alcove hides by ordering out, by alpha on its layers
or by moving to another Space is **UNVERIFIED**. Mission Control (`shots/state_mission_control.png`): same – inventory unchanged.

### 1.6 Display selection (OBSERVED, `defaults/`)
Settings ▸ General ▸ Display popup: *Main display* → `showOnDisplay=mainScreen`; *All displays* → `allDisplays`;
picking the concrete display ("Apple Virtual") → `showOnDisplay=specificDisplay` plus
`showOnDisplayName="Apple Virtual"`, `showOnDisplaySymbol="display"`, `showOnDisplayUUID=<CGDisplay UUID>`.
Multi‑display behaviour and the menu‑bar **Display** submenu: **UNVERIFIED** (one virtual display).

---

## 2. Persistence

### 2.1 Where
* `~/Library/Preferences/com.henrikruscon.Alcove.plist` – all settings (OBSERVED).
* `~/Library/Caches/com.henrikruscon.Alcove/Cache.db{,-shm,-wal}` – NSURLCache; contains one cached response keyed
  `https://api.tryalcove.com/trial/<UUID>` (trial status cache; not inspected further) (OBSERVED, `net/cache_db_urls.txt`).
* `~/Library/HTTPStorages/com.henrikruscon.Alcove/httpstorages.sqlite` – only an `alt_services` row:
  `api.tryalcove.com:443 → h3` (OBSERVED, `net/alt_services.txt`).
* **No** `~/Library/Application Support/com.henrikruscon.Alcove`, **no** `~/Library/Containers/…` (not sandboxed),
  **no** LaunchAgents plist (OBSERVED).
* Login item: `SMAppService` main‑app login item registered with BackgroundTaskManagement
  (`sfltool dumpbtm`: Name Alcove, Team `287NUTSP69`, Identifier `2.com.henrikruscon.Alcove`,
  Disposition `[disabled, allowed, notified]` while `launchAtLogin=false`). The launch log shows
  `[com.apple.libxpc.SMAppService:all] Unregister (<private>) error: 1` at startup (it unregisters when the
  setting is off) (OBSERVED, `logs/launch_interesting.txt`). *Note:* the repeated "Login Item Added" banner on the VM
  coincided with my own `sudo sfltool dumpbtm` calls, not with Alcove actions.
* Keychain: `security dump-keychain | grep -i alcove` → no item names matched (OBSERVED; absence in this query only).
* iCloud KVS: no `NSUbiquitousKeyValueStore`/ubiquity log lines in 1 h of debug logging; VM has no iCloud account → **UNVERIFIED**.
* The TCC rows and `hasPrompted{Bluetooth,Calendar,Location}Permission` keys are the only onboarding state (OBSERVED).

### 2.2 Behaviour
* Keys appear in the plist **only after first change** (sweep diffs show `(None, value)` for untouched keys) → the app
  uses `UserDefaults.register(defaults:)`/`@AppStorage` defaults in code. Defaults listed below were therefore
  taken from the UI's initial state and from the restored final plist (`defaults/99_final_state_typed.txt`).
* Changes written by `defaults write` from outside are picked up live (hideFromScreenCapture) – KVO/`@AppStorage`.
* Sliders write **Double** (`connectivityDuration 5.5`, `brightnessDuration 2.0`), steppers/percent sliders write
  Double too (`lowConnectBatteryThreshold 30.0`), ints only for `keepAwake`, `nowPlayingWidgetOffset`, `hideIdleDuration`, `timeBeforeEvent`.

### 2.3 Key table (UI label → key → type → default → example values) – all OBSERVED via `defaults/toggle_sweep_run1.txt`, `defaults/general_*.txt`, `defaults/99_final_state_typed.txt`

**General**

| UI label | key | type | default | values seen |
|---|---|---|---|---|
| Launch at login | `launchAtLogin` | Bool | false | true/false (also drives SMAppService register/unregister) |
| Hide in fullscreen | `hideWhileInFullscreen` | Bool | true | |
| Hide in Mission Control | `hideWhileInMissionControl` | Bool | true | |
| Hide while gaming | `hideWhileGaming` | Bool | false | |
| Hide from screen capture | `hideFromScreenCapture` | Bool | false | flips window sharingState |
| Force simulated notch | `forceSimulatedNotch` | Bool | false | true on this VM |
| Idle Activity popup | `idleActivity` | String | `calendar` (as shipped here) | `none`, `nowPlaying`, `calendar`, `duo` |
| Most Recent | `mostRecentActivity` | Bool | false | |
| Display popup | `showOnDisplay` | String | `mainScreen` | `mainScreen`, `allDisplays`, `specificDisplay` (+ `showOnDisplayName/Symbol/UUID`) |
| Contrast outline | `contrastOutline` | Bool | true | |
| Progressive blur | `progressiveBlur` | Bool | true | |
| Haptic feedback | `enableHaptics` | Bool | true | |
| Expand on hover | `expandNotchOnHover` | Bool | false | |
| Natural movement | `naturalMovement` | Bool | false | |
| Swipe to toggle open | `swipeToToggle` | Bool | true | |
| Swipe to cycle activity | `swipeToCycleActivity` | Bool | true | |
| Swipe to dismiss activity | `swipeToDismiss` | Bool | true | |
| Swipe to skip media | `swipeToSkip` | Bool | true | |
| (internal) | `isFirstLaunch` | Bool | – | false after onboarding |
| (internal) | `hasPromptedBluetoothPermission`, `hasPromptedCalendarPermission`, `hasPromptedLocationPermission` | Bool | – | true |
| (AppKit) | `NSStatusItem VisibleCC Alcove` | Bool | – | true |

**Connectivity**

| UI label | key | type | default | values |
|---|---|---|---|---|
| Connectivity (enable) | `enableConnectivity` | Bool | true | |
| Duration | `connectivityDuration` | Double | 5 | 5.5 |
| Warn on low battery | `warnOnLowConnectBattery` | Bool | true | |
| Low battery threshold | `lowConnectBatteryThreshold` | Double | 20 | 30 |
| Play sound on low battery | `playSoundOnLowConnectBattery` | Bool | true | |
| Model segmented (3D / AirPods Pro symbol…) | `connectivityModel` | String | `threeDimensional` | `symbol` |

**Focus**

| UI label | key | type | default |
|---|---|---|---|
| Focus (enable) | `enableFocus` | Bool | true |
| Duration | `focusDuration` | Double | 5 |
| Play sound on sleep focus | `playSoundOnSleepFocus` | Bool | false |
| Replace waveform during focus | `replaceWaveformDuringFocus` | Bool | false |
| Hide label | `hideLabel` | Bool | false |
| Allow while focused: Battery / Connectivity / Display / Sound | `allowBatteryWhenFocused`, `allowConnectivityWhenFocused`, `allowBrightnessWhenFocused`, `allowVolumeWhenFocused` | Bool | true |

**Display (brightness HUD)**

| UI label | key | type | default | values |
|---|---|---|---|---|
| Display (enable) | `enableBrightness` | Bool | true | |
| Duration | `brightnessDuration` | Double | 1.5 | 2.0 |
| Progress style segmented | `brightnessProgressStyle` | String | `white` | `accent`, … |
| Show percentage | `showBrightnessPercentage` | Bool | false | |
| Hide label | `hideBrightnessLabel` | Bool | false | |
| Speed segmented | `brightnessSpeed` | String | `fast` | |

**Sound (volume HUD)**

| UI label | key | type | default | values |
|---|---|---|---|---|
| Sound (enable) | `enableVolume` | Bool | true | |
| Duration | `volumeDuration` | Double | 1.5 | |
| Progress style | `volumeProgressStyle` | String | `white` | |
| Show percentage | `showVolumePercentage` | Bool | false | |
| Hide label | `hideVolumeLabel` | Bool | false | |
| Speed | `volumeSpeed` | String | `fast` | |
| Output device label | `volumeOutputDevice` | String | `device` | |

**Now Playing**

| UI label | key | type | default | values |
|---|---|---|---|---|
| Now Playing (enable) | `enableNowPlaying` | Bool | true | |
| Idle duration | `idleDuration` | Double | 3 | |
| Song title badge | `songTitleBadge` | String | `explicit` | |
| Progress style | `progressStyle` | String | `mono` | |
| Disable waveform | `disableWaveform` | Bool | false | |
| Disable album art flip | `disableAlbumArtFlip` | Bool | false | |
| Hide while source is active | `hideWhileSourceIsActive` | Bool | false | |
| Hide song title extras | `hideSongTitleExtras` | Bool | false | |
| Control choice | `controlChoice` | String | `shuffle` | |
| Automatic music app | `automaticMusicApp` | Bool | false | |
| Music app | `musicApp` | String | `system` | |
| Quick Peek (enable) | `enableQuickPeek` | Bool | true | |
| When song changes | `whenSongChanges` | Bool | true | |
| Peek duration | `peekDuration` | Double | 2 | |

**Calendar**

| UI label | key | type | default |
|---|---|---|---|
| Calendar (enable) | `enableCalendar` | Bool | true |
| Time before event | `timeBeforeEvent` | Int | 15 |
| Play sound on calendar event | `playSoundOnCalendarEvent` | Bool | true |
| Play hourly chime | `playHourlyChime` | Bool | false |
| Use calendar color | `useCalendarColor` | Bool | false |
| Disable activity during events | `disableActivityDuringEvents` | Bool | false |
| Use event indicators | `useEventIndicators` | Bool | false |
| Always show month view | `alwaysShowMonthView` | Bool | false |
| Quick Peek (enable) | `enableCalendarQuickPeek` | Bool | true |
| Before event starts | `beforeEventStarts` | Bool | false |
| When event is starting | `whenEventIsStarting` | Bool | true |
| Peek duration | `calendarPeekDuration` | Double | 4 |
| Colored calendar indicator | `useColoredCalendarIndicator` | Bool | true |
| (internal) excluded calendars | `excludedCalendars` | Array | [] |
| (internal) | `calendarDisplayModes` | – | seen in sweep |

**Lock Screen**

| UI label | key | type | default |
|---|---|---|---|
| Lock Screen (enable) | `enableLockScreen` | Bool | true |
| Keep awake | `keepAwake` | Int | 0 |
| Show on screen saver | `showOnScreenSaver` | Bool | false |
| Play sound on lock / unlock | `playSoundOnLock` / `playSoundOnUnlock` | Bool | false / true |
| Widgets when locked: Battery/Connectivity/Focus/Calendar/Now Playing | `allowBatteryWidgetWhenLocked`, `allowConnectivityWidgetWhenLocked`, `allowFocusWidgetWhenLocked`, `allowCalendarWidgetWhenLocked`, `allowNowPlayingWidgetWhenLocked` | Bool | true (Calendar false) |
| Now Playing style | `nowPlayingStyle` | String | `glass` |
| Hide idle duration | `hideIdleDuration` | Int | 10 |
| Show volume control | `showVolumeControl` | Bool | false |
| Now Playing widget offset | `nowPlayingWidgetOffset` | Int | 0 |
| HUDs when locked: Battery/Connectivity/Focus/Display/Sound | `allowBatteryWhenLocked`, `allowConnectivityWhenLocked`, `allowFocusWhenLocked`, `allowBrightnessWhenLocked`, `allowVolumeWhenLocked` | Bool | true |

**About**

| UI label | key | type | default |
|---|---|---|---|
| Automatically check for updates | `automaticallyCheckForUpdates` | Bool | true |

Battery pane: disabled on this VM (no battery) → its keys **UNVERIFIED** (lead's `settings_ax/general.txt` lists them statically).

---

## 3. Unified logging

Command used (kept within the requested predicate, plus tccd lines mentioning Alcove):
```
log stream --style compact --level debug --predicate 'process == "Alcove" OR process == "AlcoveHelper" OR subsystem CONTAINS "henrikruscon" OR (process == "tccd" AND eventMessage CONTAINS "Alcove")'
```
Files: `logs/logstream_launch.txt` (launch → onboarding → first minutes), `logs/logstream_features.txt` (settings sweep,
HUDs, QuickTime, TCC experiments), counts in `logs/*_subsystem_counts.txt`, extracts in `logs/launch_interesting.txt`,
`logs/mediaremote_msgs.txt`, `logs/helper_msgs_features.txt`.

**There is no `henrikruscon` subsystem** – Alcove emits no `os_log` of its own at debug level (OBSERVED, 0 matches).
Everything below is framework logging attributed to the Alcove/AlcoveHelper processes.

| Subsystem:category (process) | Triggered by | Representative message |
|---|---|---|
| `com.apple.defaults:User Defaults` | every settings change; constant polling of CFPrefs | ~200 k lines; shows the app reads prefs very frequently |
| `com.apple.CFBundle:strings/resources` | UI rendering | localised strings lookups |
| `com.apple.amp.mediaremote:MediaRemote` (**AlcoveHelper**) | QuickTime play/pause/metadata | `_MRMediaRemotePlayerNowPlayingInfoDidChangeNotification`, `…PlaybackStateDidChange…`, `…IsPlayingDidChange…`, `…SupportedCommandsDidChange…`, `_kMRNowPlayingPlaybackQueueChangedNotification`, `_MRMediaRemoteApplicationDisplayNameDidChangeNotification` for `com.apple.QuickTimePlayerX` |
| `com.apple.amp.mediaremote:NowPlaying` (helper) | same | now‑playing info fetch |
| `com.apple.xpc.transaction:all` (helper) | main app asks helper | `getNowPlayingInfoForBundleIdentifier:reply:`, `getNowPlayingSource:`, `getIsPlaying:` |
| `com.apple.CFBundle:loading/plugin` (Alcove, launch) | startup | `dlopen …/PrivateFrameworks/MediaRemote.framework` |
| `com.apple.FrontBoard:Common` (Alcove, launch) | startup | `Reconnecting scene com.apple.controlcenter:<UUID>` / `…-Aux[1]-NSStatusItem…` (scene id uses the `com.apple.controlcenter` prefix, consistent with the helper's bundle id) |
| `com.apple.locationd.Core:Client`, `(CoreLocation) CL: CLLocationManager` | startup | `initWithEffectiveBundleIdentifier…`, `locationManagerDidChangeAuthorization` |
| `com.apple.weather:AuthService`, `com.apple.weather:WeatherDataService` | startup | `This is a 3rd party process so authenticate via com.apple.weatherkit.authservice`; `Sending request with User Agent=WeatherKit_Alcove_macOS_Version 26.6.2 (Build 25G83)` |
| `com.apple.libxpc.SMAppService:all` | startup | `Unregister (<private>) error: 1` |
| `com.apple.TCC:access` (Alcove) | startup | `TCCAccessRequest, service=kTCCServiceScreenCapture` (a ScreenCapture *check* at 10:03:08; no prompt appeared) |
| `com.apple.TCC:access` (tccd) | each media‑key event | `Handling access request to kTCCServicePostEvent, from Sub:{com.henrikruscon.Alcove}` – i.e. the app **posts** HID events (needed to swallow/replace the key) |
| `com.apple.TCC:events` (tccd) | `tccutil reset` | `TCCDEvent: type=Delete, service=kTCCServiceAccessibility, identifier=com.henrikruscon.Alcove` |
| `com.apple.DisplayServicesClient:default` | brightness paths | `key=DisplayServicesCanChangeBrightness display=1` |
| `com.apple.coreaudio:AMCP` | volume keys | `HALB_Logging.cpp:72 LogVolumeChangeForClientSide from AudioObjectSetPropertyData` – Alcove sets the volume itself through CoreAudio |
| `com.apple.network:quic/boringssl/connection`, `com.apple.CFNetwork:Default` | launch, trial check | HTTP/3 to `api.tryalcove.com` |
| `com.apple.coremedia:player/…`, `com.apple.coreaudio:AQ*` | launch / sounds | AVPlayer/AudioQueue (sound effects, waveform) |
| `com.apple.sidecar:core` | launch | Sidecar/display enumeration |
| `com.apple.AppKit:Animation/Window`, `com.apple.SkyLight:processes` | UI | `SLSSetFrontProcessWithInfo` |
| `com.apple.securityd:*`, `com.apple.launchservices:*`, `com.apple.corespotlight:*` | launch | framework noise |

Anything with `<private>` was left redacted; no payloads were captured.

---

## 4. Processes & IPC

### 4.1 AlcoveHelper (STATIC: `proc/helper_info_plist.txt`; OBSERVED: `proc/relaunch_helper_timing.txt`)
* Path `Alcove.app/Contents/XPCServices/AlcoveHelper.xpc/Contents/MacOS/AlcoveHelper`, `CFBundleIdentifier =
  com.apple.controlcenter.AlcoveHelper`, `CFBundlePackageType = XPC!`, `XPCService.ServiceType = Application`,
  `LSMinimumSystemVersion 15.0`, built with Xcode 27.0 / SDK macOS 27.0 (`DTPlatformVersion 27.0`).
* Lifecycle: present **≤1 s after `open -a Alcove`**, persists for the life of the app (same pid for >1 h), killed with the app
  (`killall Alcove` → both gone). Launched by launchd as an XPC service child of the app (standard NSXPCConnection
  to an embedded XPC service; it never appears in `launchctl list` as a user agent).
* Role (OBSERVED from its log lines): it owns the `MediaRemote` client (NowPlaying notifications), and answers the
  main app's XPC requests `getNowPlayingInfoForBundleIdentifier:reply:`, `getNowPlayingSource:`, `getIsPlaying:`.
  The main app itself also `dlopen`s MediaRemote at launch.
* Threads: 2 (idle) – 4 (during playback); ~46–48 Mach ports.

### 4.2 Main app
* `ps`: `/Applications/Alcove.app/Contents/MacOS/Alcove`, not sandboxed, no LaunchAgent.
* Threads 8–10: `com.apple.main-thread`, `com.apple.NSEventThread`, `caulk.messenger.shared:17`/`:high`,
  `caulk::deferred_logger`, `com.apple.coremedia.imagequeue.coreanimation.common` (`proc/sample_*.txt`).
  → audio engine (`caulk` = CoreAudio) is running even when idle; the imagequeue thread belongs to AVFoundation/CoreMedia.
* `lsof`: frameworks, the preference plist, Cache.db, httpstorages.sqlite; no sockets open while idle (`proc/lsof_*.txt`).
* Linked frameworks seen in the process image (STATIC via `sample`): AVFAudio, CoreAudio, CoreLocation, CoreMotion,
  EventKit, IOBluetooth, SwiftUI/SwiftUICore, WeatherKit, CoreBrightness, DisplayServices, MediaRemote, SkyLight.

### 4.3 Resource usage (OBSERVED, `proc/top_*.txt`, `proc/footprint_*.txt`, `proc/powermetrics_raw_*.txt`)

| State | Alcove CPU | Alcove RSS | threads | Helper CPU / RSS | powermetrics (Alcove) |
|---|---|---|---|---|---|
| Idle, notch closed | 0.0 % | 71–72 MB | 8–9 | 0.0 % / 3.0–3.5 MB | 1.60 CPU ms/s, 5.90 wake‑ups/s, Energy Impact 0.16 |
| Expanded + QuickTime playing (live waveform) | 0.1 % | 71–73 MB | 9–10 | 0.0 % / 3.4 MB | 1.56 CPU ms/s, 6.59 wake‑ups/s, Energy Impact 0.16 |
| footprint | phys 71 MB, peak 108 MB (helper 2.9 / 3.0 MB) | | | | |

Takeaway: the waveform is cheap; whatever drives it does not change CPU measurably at 10‑s granularity. Peak 108 MB
occurred during onboarding/settings.

### 4.4 Now Playing behaviour (OBSERVED)
* Source detection via MediaRemote works for QuickTime Player; title/artist from my m4a tags were **not** shown
  ("No Title" + waveform + progress bar) – QuickTime does not publish them to NowPlaying; Music/Spotify UNVERIFIED.
* After QuickTime **quit**, the compact Now Playing (222×29, paused) stayed for >60 s (`windows/stop_burst_bbox.txt`) –
  the app keeps the last MediaRemote source until it gets a new one.
* `hideWhileSourceIsActive`, Quick Peek on song change: a 20‑shot burst at 2 Hz after `next` is in `shots/peek_burst_*.png`.

---

## 5. Network (OBSERVED, `net/`)

Hosts:
| Host | When | Evidence |
|---|---|---|
| `api.tryalcove.com` (Cloudflare) | launch (trial status; cached under `/trial/<uuid>`), Check Updates, changelog | `net/cache_db_urls.txt`, `net/alt_services.txt` (h3), quic log lines |
| Apple WeatherKit (`com.apple.weatherkit.authservice` → Apple hosts) | launch | `logs/launch_interesting.txt` |
| 17.253.31.138:443 (Apple CDN) | one TCP SYN at 10:29:38 during the Settings‑open window; attribution to Alcove **INFERRED/weak** | `net/tcpdump_syn.txt` |

* Opening Settings: no new sockets (`net/lsof_poll.txt`, 0.5 s polling).
* **Check Updates…** (About pane): a busy indicator spins briefly; no new TCP SYN was captured in the following 10 s.
  Because `api.tryalcove.com` advertises HTTP/3 (`alt_services`), the request most likely went over the existing QUIC/UDP
  flow → **INFERRED**. On a trial the outcome is consistent with the `/updates/latest` 401 below; no dialog appeared.
* No mitmproxy was used (TLS pinning/licence traffic would have been in scope otherwise).

Public endpoints (plain `curl`, no auth, `net/resp_*.json`, `net/public_endpoints.txt`):

`GET https://api.tryalcove.com/changelog` → **200** `application/json`, 46 031 bytes, cache‑control present, `server: cloudflare`.
Shape:
```json
{ "updated": "<string>",
  "entries": [ { "version": "1.7", "description": "...",
                 "minors": [ { "version": "1.7.7", "date": "...", "note": "...", "features": [...], "fixes": [...] } ] } ] }
```
`GET https://api.tryalcove.com/updates/latest` → **401** `{"message":"An active license is required for this channel."}`
(the app presumably sends a licence credential; not examined).

---

## 6. Permissions / TCC (OBSERVED, `tcc/`)

System TCC.db rows for `com.henrikruscon.Alcove` after onboarding:
```
kTCCServiceCalendar         auth_value=2 (allowed) auth_reason=2 (user consent)   17:04:30
kTCCServiceBluetoothAlways  auth_value=2           auth_reason=2                  17:04:44
kTCCServiceAccessibility    auth_value=2           auth_reason=4 (System Settings) 17:05:37
```
Requested in onboarding order: AppleEvents targets (Music, Spotify, System Events; Safari, Chrome, Dia – these are
*described* in onboarding, actual AppleEvent prompts only fire when a target app is scripted – UNVERIFIED), Calendar,
Bluetooth, Accessibility. Location (`hasPromptedLocationPermission=true`, CLLocationManager at launch for WeatherKit)
– no TCC row was created on the VM. `kTCCServiceScreenCapture` is *queried* at launch (log) but never prompted.
`kTCCServicePostEvent` requests appear in tccd for every media‑key event the app handles.

Revocation experiment (`tcc/revoke_log_lines.txt`, `tcc/system_tcc_after_*.txt`, `shots/state_*ax_*`):
1. `tccutil reset Accessibility com.henrikruscon.Alcove` while running → row deleted; **the HUD keeps working**
   (existing event tap survives the reset; volume 43→55, HUD 332 px).
2. Relaunch with Accessibility denied: no prompt/onboarding shown; TCC row re‑created with `auth_value=0` at launch
   (the app checks `AXIsProcessTrusted` at startup); media keys now change volume through the **system** path (63) and
   Alcove shows **no HUD** (bbox stays idle 144 px). No system OSD either – this VM has no `OSDUIHelper` process at all,
   so OSD suppression on real hardware is **UNVERIFIED**.
3. Re‑enable the toggle in System Settings ▸ Privacy & Security ▸ Accessibility (password prompt) → `auth_value=2`
   and **within ~10 s, without relaunch,** media keys produce the Alcove HUD again (polls/observes trust and installs the tap).
Swipe gestures were not exercised in the denied state (no trackpad on the VM) – UNVERIFIED.

---

## 7. Media keys / HUD paths (OBSERVED, `scripts/mediakey.swift`, `shots/state_hud_*`)

| Path | Volume changes? | Alcove HUD? | Notes |
|---|---|---|---|
| `osascript -e 'set volume output volume 30'` | yes | **no** | CoreAudio property change only; Alcove does not watch the HAL volume property for its HUD |
| Synthetic `NX_SYSDEFINED` subtype 8, `NX_KEYTYPE_SOUND_UP/DOWN/MUTE`, posted with `CGEvent.post(.cghidEventTap)` | yes (Alcove sets it: `LogVolumeChangeForClientSide` from the Alcove process) | **yes** – Sound HUD 332×29 with speaker glyph, "Sound" label, white bar; mute shows slashed speaker | tccd logs `kTCCServicePostEvent` for Alcove → it consumes the key via a CGEvent tap and posts/handles itself |
| Synthetic `NX_KEYTYPE_BRIGHTNESS_UP/DOWN` | n/a (virtual display) | no | `DisplayServicesCanChangeBrightness display=1` lines appear; real‑panel brightness HUD UNVERIFIED |
| `NX_KEYTYPE_PLAY/NEXT/PREV` | – | Now Playing reacts (QuickTime) | see peek bursts |

System OSD: `OSDUIHelper` never ran on this VM, so "Alcove suppresses the OSD" is **UNVERIFIED** here; the mechanism
implied by the TCC log (Accessibility‑gated event tap that swallows the key and re‑posts) is **INFERRED**.

---

## 8. UNVERIFIED on this VM (hardware‑dependent)
Real notch geometry/alignment, Battery pane & low‑battery HUD, AirPods/Bluetooth connect card, Touch ID, multiple
displays & menu‑bar Display submenu, lock‑screen/screensaver panels, haptics, trackpad swipes, brightness HUD,
real fullscreen‑Space hiding, Music/Spotify metadata & album art, iCloud KVS.

---

## 9. Evidence index
* `scripts/` – winlist.py, winsample.py, osd_check.py, measure_bbox.py, mediakey.swift (+ compiled `mediakey`), netpoll.sh
* `windows/` – states.txt (all CGWindow dumps), hud_osd.txt, bbox_measurements.txt, stop_burst_bbox.txt
* `shots/` – every screenshot referenced above, settings_*.png / crop_*.png per pane, peek_burst_*/stop_burst_* series
* `defaults/` – numbered before/after snapshots, toggle_sweep_run1.txt (every control pressed with the resulting key diff), 99_final_state{.plist,_typed.txt}
* `logs/` – logstream_launch.txt, logstream_features.txt, *_subsystem_counts.txt, launch_interesting.txt, mediaremote_msgs.txt, helper_msgs_features.txt
* `proc/` – top_*, footprint_*, sample_*, powermetrics_raw_*, lsof_*, helper_info_plist.txt, relaunch_helper_timing.txt
* `net/` – public_endpoints.txt, resp_changelog.json, resp_updates_latest.json, cache_db_urls.txt, alt_services.txt, lsof_poll.txt, tcpdump_syn.txt
* `tcc/` – TCC.db extracts before/after revoke and regrant, revoke_log_lines.txt
* `media/` – tone1.m4a, tone2.m4a (tagged test tracks used with QuickTime)
