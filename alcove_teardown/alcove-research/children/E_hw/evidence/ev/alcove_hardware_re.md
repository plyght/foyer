# Alcove 1.7.7 (199): hardware-dependent behavior

## Scope, confidence, and how to use this report

**OBSERVED:** This investigation used Alcove 1.7.7, build 199, on macOS 26.6.2 (25G83), arm64, with one 1600×1200, 1× virtual display. The analyzed arm64 executable SHA-256 is `14520b5dd7b91b6e248122194dc206634173fb014d105a308d824974d4f653ec`. Evidence: `ev/logs/environment.txt`.

**OBSERVED:** The VM has no physical notch, internal battery, paired AirPods, keyboard illumination hardware, or second display. Onboarding and ordinary Accessibility permission were completed; the application displayed its normal simulated notch. No executable modification, licensing bypass, or activation reverse engineering was performed. No external posts or repository changes were made.

**STATIC** means directly recovered from executable instructions, metadata, imports, or resources. Addresses are unslid arm64 virtual addresses, not file offsets. **OBSERVED** means a recorded local result, or an explicitly identified observation supplied by the lead. **INFERRED** means an interpretation that goes beyond the direct evidence. **UNVERIFIED** identifies a missing test or unresolved interpretation. A status at the beginning of a paragraph or table row applies to that entire paragraph or row. Function names assigned to stripped functions are descriptive, not recovered source declarations.

**INFERRED:** Confidence is 8/10 for the core geometry, model classifier, battery APIs, and event swallowing; lower for exact end-to-end presentation timing on unavailable hardware. This is an implementation-oriented evidence report, **not a claim of complete pixel/timing equivalence**. Unknowns are retained rather than filled with conventional macOS behavior.

### Highest-value conclusions

| Status | Finding | Evidence |
|---|---|---|
| STATIC | Real notch width is screen width minus the widths of both auxiliary top areas; height is safe-area top. | `ev/dis/f_notchgeom_100238df8.txt` |
| STATIC / OBSERVED | Simulated geometry is 140 points wide; visible-menu-bar height minus 1 gives 29 points here. Its full dark shoulder bounds are 144×29 pixels. | geometry function; `ev/logs/screen_geometry.json`, `screenshot_bboxes.json` |
| STATIC | AirPods model identity comes from a CoreAudio model UID, not a recovered Apple BLE advertisement decoder. Battery values come from private IOBluetooth selectors. | `f_bt_10031b0c8.txt`, `coreaudio_model_property.txt`, `f_bt_10031a974.txt` |
| STATIC | Successful media-key handling returns a null event to suppress downstream handling. This is positively established, not merely implied by an active tap. | `f_mediakey_100136eac.txt`, 0x100137194–0x100137198 |
| STATIC | Fine adjustment is **Shift + Option together**, mask 0xa0000. Brightness fallback increments are 1/16 and 1/64. | 0x100137140–0x10013714c; `f_bright_increment_100122f0c.txt` |
| STATIC / OBSERVED | The Mac-battery threshold initializer is 10.0. The supplied live 20% setting belongs to **Connectivity**, not the disabled Battery pane. | `f_default_lowBatteryThreshold.txt`; lead `settings_ax/general.txt`, lines 5–6 |
| OBSERVED | Synthetic `screenLockUIIsShown` widened the top notch; raw `screenIsLocked` alone did not visibly show lock widgets. | `ev/clips/hardware_matrix.mp4`; matching screenshots |
| UNVERIFIED | No brightness or volume HUD appeared from the synthetic key run. No physical-device result or successful native OSD suppression is claimed. | runtime matrix and clip |

## 1. Notch detection, geometry, and display targeting

### Source → parsing → state

**STATIC:** The real-notch predicate checks `NSScreen.safeAreaInsets.top > 0`, non-nil `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`, and nonempty rectangles for both. Examples are 0x100238df8, 0x1001ebcd8, 0x1001109f0, and 0x10034bf7c. Do not replace this with a machine-model-name test or `CGDisplayIsBuiltin` alone. Evidence: `ev/dis/f_notchgeom_100238df8.txt`, `f_notchgeom_1001ebcd8.txt`, `f_notchgeom_1001109f0.txt`, `f_displaylist_10034bf7c.txt`.

**STATIC:** Geometry function 0x100238df8 receives a screen and a fallback/simulation flag, returning four floating-point values. Caller 0x100233518 stores them into the `NotchController` fields `_notchWidth`, `_notchHeight`, `_notchExpandedWidth`, `_notchExpandedHeight`; its explicit field relocations establish the return ordering. It compares old/new values and emits observable mutations only on differences. Evidence: `ev/dis/f_notchgeom_caller_100233518.txt`, particularly 0x1002335a4 onward.

### Exact base formulas

**STATIC:** Let `W = screen.frame.width`, `L/R = auxiliaryTopLeftArea/RightArea.width`, `S = safeAreaInsets.top`, and `M = frame.maxY - visibleFrame.maxY`. These are AppKit logical points, not physical Retina pixels.

| Status | Branch | Closed width | Closed height | Base expanded width | Base expanded height |
|---|---|---:|---:|---:|---:|
| STATIC | Valid real-notch screen | `W-L-R` | `S` | `max(W-L-R+160,345)` | `max(S+142,175)` |
| STATIC | No real notch, simulation enabled | 140 | `M-1` when top menu-bar difference is positive; otherwise 24 | 345 | 175 |
| STATIC | No real notch, compact fallback | 74 | `M-5.5` when top menu-bar difference is positive; otherwise 19.5 | 321 | 175 |

**STATIC:** Real-branch arithmetic is at 0x100239018–0x10023906c. The 140 constant is present as the assembled floating-point value `0x4061800000000000`; searching only for a standalone 64-bit literal missed it in early scratch analysis. The compact 74-point size must not be confused with the forced simulated notch.

**OBSERVED:** On this VM, frame is `(0,0,1600,1200)`, visible frame `(0,82,1600,1088)`, safe top 0, scale 1. Thus `M=30`, predicting 140×29. In `ev/shots/ready.png`, thresholding the top-center black region gives inclusive bounds x=728…871, y=0…28: **144×29 including shoulders/antialiasing**, centered at x=799.5. The nominal central width and full shoulder bounds are different measurements. Evidence: `ev/logs/screen_geometry.json`, `screenshot_bboxes.json`.

**INFERRED:** Use these as base metrics, not fixed final content bounds. Calendar, notifications, outline, cutout shoulders, and animation can change the rendered width. The prior lead report measured an expanded Calendar width around 358 pixels even though this base function supplies 345. Source: supplied `NOTES.md` and static report.

### Adjusted width/height and additional offsets

**STATIC:** `notchAdjustedWidth` and `notchAdjustedHeight` are Defaults-backed settings with zero initial values and are referenced by the notch controller and views. The core geometry-return/store path above does not add them. The earlier static report's interpretation “zero means use detected size” is a useful hypothesis, not enough to establish whether nonzero values are offsets, overrides, or branch-specific tuning.

**OBSERVED:** Controlled preference experiments set width=20/height=0 and width=0/height=10, restarting Alcove between changes. The simulated closed notch stayed at dark bounds 144×29 in both screenshots. Both values were restored to zero. Evidence: `ev/scripts/runtime_matrix.py`, `ev/logs/runtime_matrix.json`, `ev/shots/adjusted_width20.png`, `adjusted_height10.png`, `adjusted_restored.png`.

**UNVERIFIED:** Those experiments do **not** prove the settings are ignored globally. Their exact consumer formula, real-notch applicability, and any constraints on accepted values remain unresolved. Do not implement `closedWidth += adjustedWidth` as a recovered fact.

**STATIC:** Separate layout getters contain 74, 28, and 12-point quantities. 0x10021b0f4 can yield 74, 46 (=74−28), 62 (=74−12), or 0 depending on state and real-notch checks. 0x10021b394 contains another 74/12 adjustment. They are conditional content-layout contributions, not the 140-point simulated size. Evidence: `ev/dis/f_geom_10021b0f4.txt`, `f_geom_10021b394.txt`.

### Multiple displays and screen changes

**STATIC:** `DisplayType` has `builtInDisplay`, `mainScreen`, `allDisplays`, `specificDisplay`. Screen IDs are obtained using `NSScreen.deviceDescription` and display UUID-related helpers; 0x10021b83c selects a target screen from available screens using stored display selection. The chooser list builder 0x10034bf7c uses `CGDisplayIsBuiltin`, the real-notch predicate, and backlight probes, and selects symbols including `macbook`, `laptopcomputer`, and `display`. Evidence: `ev/dis/fieldmd_hw.txt`, `f_screenchooser_10021b83c.txt`, `f_display_uuid_10020beec.txt`, `f_display_uuid2_10023f6e0.txt`, `f_displaylist_10034bf7c.txt`.

**STATIC:** Backlight-capability probing tries `AppleARMBacklight`, `AppleBacklightDisplay`, then a service named `backlight` at 0x10020cd28 and an inlined chooser path. `NSApplicationDidChangeScreenParametersNotification` is subscribed to in the lock/display integration at 0x10034fec4. Evidence: corresponding disassembly and `ev/dis/relocs_lock_nc_names.txt`.

**OBSERVED, lead:** General settings offered Main display; menu-bar menu offered a Display submenu. **UNVERIFIED:** actual all-display window multiplicity, hotplug fallback when a selected UUID disappears, mixed-scale geometry, and display migration animation. Only one screen was present.

### Requested model-size predictions

| Status | Machine | Defensible prediction |
|---|---|---|
| UNVERIFIED | 14-inch MacBook Pro | `(frame.width-leftAux.width-rightAux.width) × safeAreaInsets.top` on the actual selected display mode |
| UNVERIFIED | 16-inch MacBook Pro | Same formula; no model-specific literal recovered |
| UNVERIFIED | 13-inch MacBook Air with notch | Same formula; requires actual auxiliary rectangles and safe inset |
| UNVERIFIED | 15-inch MacBook Air with notch | Same formula; requires actual auxiliary rectangles and safe inset |

**INFERRED:** Model names/diagonal sizes alone do not provide the API inputs, especially under scaled display modes. Consequently a numeric table would be invented. For illustration only, an API result of width gap 220 and safe top 32 would yield 220×32 closed, 380×175 base expanded; that is **not** a measured or asserted value for any listed model.

**STATIC / UNVERIFIED:** Geometry refresh is change-driven; no geometry-specific sound was located. Common notch animation/shape behavior is in the supplied static report, not independently assigned to each hardware presentation here.

## 2. Mac battery and Low Power Mode

### Data sources and keys

**STATIC:** Helper open at 0x1001527c0 matches `AppleSmartBattery`, opens the IOKit service, and creates an `IOPSNotificationCreateRunLoopSource` installed on the current run loop in default mode. Failure has an explicit “Opening (AppleSmartBattery) service failed” path. The state reader at 0x100152488 calls `IOPSCopyPowerSourcesInfo`, `IOPSCopyPowerSourcesList`, then `IOPSGetPowerSourceDescription` for each source, filtering `Type == InternalBattery`. Evidence: `f_battery_helper_open_1001527c0.txt`, `f_battery_iops_100152488.txt`.

| Status | Key | Source / purpose / address |
|---|---|---|
| STATIC | `Type`, `InternalBattery` | IOPS source filtering at 0x100152488 |
| STATIC | `Current Capacity` | IOPS dictionary, key-index 7 requested by 0x1001522ac |
| STATIC | `ExternalConnected` | AppleSmartBattery registry, 0x1001521f0 and 0x10012de20; negated to derive on-battery state |
| STATIC | `IsCharging` | Registry boolean, 0x100151f84 |
| STATIC | `CurrentCapacity`, `MaxCapacity` | Registry capacity state, 0x100151f84 |
| STATIC | `FullyCharged` | Recovered in helper state/key paths around 0x1001528c8 |
| STATIC | `AvgTimeToEmpty`, `AvgTimeToFull` | Registry remaining-time integer readers, 0x10015238c/0x1001523a0 → 0x1001523b4 |
| UNVERIFIED | `Is Charging`, `Power Source State` | Requested candidate IOPS keys, but no specific read was established in this analysis. Do not substitute these spaced keys for the positively identified registry keys. |

**STATIC:** IOPS and registry key spellings differ: `Current Capacity` versus `CurrentCapacity`; `IsCharging` is not the same string as `Is Charging`. Evidence: `ev/dis/f_bat_get_1001522ac.txt`, `f_bat_regprops_100151f84.txt`, `f_batteryhelper_state_1001528c8.txt`.

### Parsing, state, edge triggers, and time

**STATIC:** Battery refresh 0x10012e4f8 reads connection and capacity state, normalizes reported integer level with division by 100.0, and stores `_batteryLevel`. Unavailable level falls back to zero in the decoded path. It stores `_wasOnBattery` from `!ExternalConnected` and compares level with the configured threshold divided by 100. Comparisons occur at 0x10012e7d0 and 0x10012e9e0. Evidence: `f_battery_10012e4f8.txt`.

**STATIC:** State fields include `_hasPassedThreshold`, `_hasRecentlyChangedPowerSource`, `_isLowPowerModeEnabled`, `_remainingTime`, `_warnOnLowBattery`, `_notifyOnLowPowerMode`, `_playSoundOnLowBattery`, `_allowBatteryWhenFocused`, and `_allowBatteryWhenLocked`. At 0x10012f148 the manager subscribes to custom notification `powersourcechanged` and `NSProcessInfoPowerStateDidChangeNotification`; the latter is received on the main run loop. The low-power handler 0x10012f82c reads `NSProcessInfo.isLowPowerModeEnabled`, compares prior state, and schedules main-actor work. Evidence: `fieldmd_hw.txt`, `f_battery_10012f148.txt`, `f_battery_lowpower_10012f82c.txt`.

**INFERRED:** `_hasPassedThreshold` provides threshold-crossing latching rather than repeated warning for every percentage sample. `_hasRecentlyChangedPowerSource` provides a guard around plugging/unplugging. **UNVERIFIED:** exact equality edge, re-arm rules, ordering of simultaneous source/low-power changes, and complete branch-to-notification mapping. A clone should keep these as distinct state inputs rather than one generic “battery changed” event.

**STATIC:** Async continuations contain waits of 0.5 seconds at 0x10012fc88 and 0.2 seconds at 0x100130498–0x1001304a8. **UNVERIFIED:** which full plug/unplug/low-power edge each wait belongs to; they are not proven global debounce durations. Evidence: `f_battery_timer_10012fc6c.txt`, `f_battery_timer_10013047c.txt`.

### Threshold discrepancy, UI, sound

**STATIC:** The default-key initializer at 0x1003368cc stores `0x4024000000000000` = **Double 10.0** at 0x100336940/0x10033695c for `lowBatteryThreshold`.

**OBSERVED, lead:** `settings_ax/general.txt` line 5 explicitly says the Battery pane is disabled because there is no battery; line 6 reports **Connectivity** low-battery threshold 20%. **UNVERIFIED:** the assignment's “Mac battery default 20%” is not supported by that live artifact. The binary default is 10; a physical Mac's displayed or migrated preference is untested. This resolves the apparent evidence mix-up without silently changing the request's assumption.

**STATIC:** Localized battery strings are `notification.battery.charging → Charging`, `.lowBattery → Low Battery`, `.lowPower → Low Power`, referenced in the notification view at 0x1002a116c. The battery display duration default is 5 seconds in the supplied static defaults analysis. Remaining-time logic is refreshed via 0x10012ee58. Evidence: `localizable.txt`, `f_battery_notif_view_1002a116c.txt`, `f_battery_10012ee58.txt`.

**STATIC:** BatteryManager init 0x10012e1ec preloads `low-power.caf`. ConnectivityManager, separately, preloads `low-battery.caf` at 0x10030e3c8. The latter must not automatically be assigned to Mac-battery alerts. Sound playback references occur in the BatteryManager 0x10013132c region and ConnectivityManager 0x100315408 region. Evidence: sound-preload and manager disassembly; audio metadata in §7.

**UNVERIFIED:** exact separate “plugged”, “unplugged”, and charging UI state transitions, all icon/color variants, low-power-on versus low-power-off presentation, animation curves, and sound trigger conditions are not fully recovered. Only the above strings, state fields, and paths are established.

**OBSERVED:** `sudo -n pmset -a lowpowermode 1` exited zero but printed **“LowPowerMode not supported on AC Power”**. The subsequent `… lowpowermode 0` succeeded; battery-only low-power configuration was also reset to zero. No Alcove battery/low-power overlay appeared. Exit zero here does **not** mean Low Power Mode engaged. Evidence: runtime matrix t=9.207/11.369/13.526 and screenshots `lowpower_on/off.png`.

## 3. AirPods, Bluetooth, and audio routes

### Source and model parsing

**STATIC:** CoreBluetooth delegate metadata exists, but only state-update implementations were found; `didDiscoverPeripheral` occurs in protocol metadata rather than a recovered discovery implementation. CoreBluetooth construction in onboarding at 0x10010a1b4 supports permission/power-state handling. **UNVERIFIED:** no direct Apple manufacturer-data decoder for company 0x004C/type 0x07, or `kCBAdvDataManufacturerData` parsing, was found. Absence from this analysis is not a universal proof of absence.

**STATIC:** The audio-device classifier 0x10031b0c8 calls CoreAudio property getter 0x1003c48b0. Its property tuple at 0x100475b50 decodes to selector **`muid`**, scope **`glob`** (model UID/global). It splits the resulting string on ASCII space and uses its first component. This is the source of strings such as `200e`, not a recovered `IOBluetoothDevice.productID` selector. Evidence: `f_helper_1003c48b0.txt`, `coreaudio_model_property.txt`, `f_coreaudio_modelgetter_1003c4994.txt`, `f_bt_10031b0c8.txt`.

**STATIC:** Device matching separately enumerates `IOBluetoothDevice.pairedDevices`, checks `isConnected`, and compares lowercased normalized `addressString` values against the audio device. CoreAudio route handling also distinguishes `BuiltInHeadphoneOutput` and `BuiltInSpeakerDevice`. Evidence: 0x10031a62c and 0x100312328, respective disassembly.

### Exact model classifier and resource correspondence

**STATIC:** 0x10031a2c4 compares the following lowercase four-character strings; its result packs model tag in the high byte and state/color payload in the low byte. Unknown model returns 0xff00. The three arithmetic string constructions are decoded directly: `packed("202d")+0xfe0000="200e"`; `packed("2014")+0x10000="2024"`; `packed("200f")+0x10000="201f"`.

| Status | Model UID first component | Tag / model | Corresponding bundled video |
|---|---|---|---|
| STATIC | `2002` | 0, AirPods | No dedicated first-generation MP4 found |
| STATIC | `200f` | 1, AirPods 2 | No dedicated second-generation MP4 found |
| STATIC | `2013` | 2, AirPods 3 | `airpods-3.mp4` |
| STATIC | `201b`, `2019` | 3, AirPods 4 | `airpods-4.mp4` |
| STATIC | `200e` | 4, AirPods Pro | `airpods-pro.mp4` |
| STATIC | `2014`, `2024` | 5, AirPods Pro 2 | `airpods-pro-2.mp4` |
| STATIC | `2027` | 6, AirPods Pro 3 | `airpods-pro-3.mp4` |
| STATIC | `200a` | 7, AirPods Max | Color-specific `airpods-max-*.mp4` |
| STATIC | `201f`, `202d` | 8, AirPods Max 2 | Color-specific `airpods-max-*.mp4` |

**INFERRED:** Model names follow the recovered enum ordering and resource names; the table's resource column identifies the corresponding existing asset, not a proof that every UI state uses that asset. **UNVERIFIED:** first/second-generation AirPods fallback artwork and exact left-only/right-only resource reuse. Evidence: `f_bt_namemap_10031a2c4.txt`, `namemap_condensed.txt`, `fieldmd_hw.txt`, `logs/media_inventory.json`.

**STATIC:** Private `colorID` is read at 0x10031b1ac and 0x1003149a4. Mapper 0x10031a290 masks to six bits, subtracts 2, bounds-checks 0…20, and looks up table 0x1004715b6. An unavailable-value high byte of 0x100, or out-of-range value, returns enum zero.

| Status | Masked color ID | Color enum / asset suffix |
|---|---:|---|
| STATIC | 2 | red |
| STATIC | 3 | skyBlue / sky-blue |
| STATIC | 4…15 | spaceGray / space-gray |
| STATIC | 16 | silver |
| STATIC | 17 | green |
| STATIC | 18 | midnight |
| STATIC | 19 | starlight |
| STATIC | 20 | blue |
| STATIC | 21 | orange |
| STATIC | 22 | purple |
| STATIC | missing/out-of-range | spaceGray / space-gray |

**STATIC:** All ten Max-color videos actually exist; an early scratch note claiming only five existed was incorrect. The five newer-color references in 0x100108c18 are only part of the asset set. All fifteen AirPods MP4 resources are H.264, 96×96, 60fps, 360 frames, six seconds, with no audio stream. A 32×32 point frame occurs in the Max view at 0x100108c18. Evidence: `f_airpodsmax_view_100108c18.txt`, `f_maxcolor_10031a290.txt`, `maxcolor_table.txt`, `media_inventory.json`.

### Battery state and presentation

**STATIC:** 0x10031a974 invokes private `batteryPercentLeft`, `batteryPercentRight`, and `batteryPercentSingle`. It validates integer percentages against bounds around 0…100 (0x65 exclusive upper bound), and carries separate availability/sentinel state. `AirPodsState` declares `leftOnly`, `rightOnly`, `both`; the decoded selection uses 0,1,2 respectively and an additional no-left/right path. **UNVERIFIED:** `batteryPercentSingle` must not be described as the case battery: no explicit case-battery selector or case-specific mapping was recovered.

**STATIC:** Connectivity state includes low-device-battery threshold/warning and percentage-hiding controls. 0x100314808 refreshes device state and contains `low-battery` playback. **OBSERVED, lead:** Connectivity settings: enabled, duration 5 seconds, low-battery warning on, threshold 20%, low-battery sound on, and choice of 3D models versus symbols. Evidence: `f_bt_100314808.txt`, lead settings line 6.

**INFERRED:** Route/device changes drive connect presentation, with paired-device data providing model, color, and battery payload. **UNVERIFIED:** exact connect/disconnect debounce, disconnection wording, simultaneous-device prioritization, battery polling cadence, animation start phase, and whether low-battery alerts replay after reconnect. No Bluetooth device was available, so no live device behavior is claimed.

### Other device types

**STATIC:** Audio-class fallback at 0x10031b210 requires major class 4. Its table index is **minor−1** (not minor), in range 0…14. Minor 1/2/6 map to payload 5, minor 15 to payload 0, other table entries to 17; fallback result uses high-byte category 9. Do not confuse these payloads with the AirPods model tags above. Evidence: `f_bt_10031b0c8.txt`, `bt_minorclass_table.txt`.

**STATIC:** `VirtualDevice` metadata includes MacBook/MacStudio/iMac/MacMini/MacPro, headphones, HomePod/mini/2, pair/group variants, EarPods, Studio Display and Pro Display variants. HomePod audio-route records hold UID/name/groupID/subtype/modelID/configuredClusterSize/observedAt. Model checks include `AudioAccessory1,1`, `1,2`, `1,3`, `5,1`, `6,1`; there is also a lowercased `homepod` name test. Evidence: `fieldmd_hw.txt`, `f_bt_100317100.txt`, `f_bt_10031b7cc.txt`.

**UNVERIFIED:** Generic keyboard/mouse connect-notification support was not established. HID-keyboard detection elsewhere belongs to media-key routing; it is not evidence that Connectivity shows keyboard/mouse notifications. Exact SF Symbol mapping for every generic audio subtype remains unresolved.

## 4. Lock screen and screen saver

### Sources, state, debounce

**STATIC:** LockManager initializer 0x10034f410 installs subscriptions through 0x10034fec4 to:

- `com.apple.screensaver.didstart` / `.didstop`
- `com.apple.screenLockUIIsShown` / `com.apple.screenLockUIIsHidden`
- `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked`
- `NSWorkspaceScreensDidSleepNotification` / `NSWorkspaceScreensDidWakeNotification`
- `NSApplicationDidChangeScreenParametersNotification`

**STATIC:** Startup/resynchronization calls `CGSessionCopyCurrentDictionary` at 0x10035ccc8, extracts a value and attempts Bool conversion, returning false on the decoded unavailable path. The dictionary key is produced by another initializer; its exact cleartext was not recovered here. **UNVERIFIED:** a separate `NSWorkspace.sessionDidResignActive` observer is not established by the above evidence. See `f_lock_subs_10034fec4.txt`, `relocs_lock_nc_names.txt`, `f_lockdictionary_10035ccc8.txt`.

**STATIC:** State separates `_isLocked`, `_isVisible`, `_isSleeping`, `_isAwake`; tasks include lockDebounce, unlockDebounce, screensaverPresentationTask, hideDebounce, and sleepTask. Handler 0x100353c68 cancels prior work and starts main-actor tasks. It uses `withAnimation(.easeOut(duration:0.15))` at 0x100354438–0x100354454. Login preferences are fetched asynchronously via `fetchLoginPreferences()` on a checked continuation path at 0x10035d4c8. Metadata includes hasClock/hasMessage/hasAvatar/userAccountCount and wallpaper-luminance state. Evidence: lock-handler/task dumps and field metadata.

**UNVERIFIED:** cancellation is recovered, but exact lock versus unlock debounce wait, widget ordering, and all state-transition predicates are not. The 0.15-second animation is one handler transition, not a proven duration for all lock-screen motion.

### Window/space mechanism and widgets

**STATIC, prior report plus current selector evidence:** LockPanel init 0x1000efe04 uses a clear nonopaque, shadowless NSPanel, `canBecomeVisibleWithoutLogin=true`, shielding-window level, no native window animation, and collection behavior 0x151 (all spaces, stationary, ignores cycle, fullscreen auxiliary). Related private space support creates/shows a CGS space at 0x100128d0c, moves windows with CGSAdd/RemoveWindowsFromSpaces at 0x100128f18, and destroys the space at 0x100128e24. Supplied `alcove_static_re.md` §4 gives the shared window contract; `ev/dis/x_stubs.txt` records current selector call sites.

**INFERRED:** The combination of private spaces, high window level, and visible-without-login makes presentation over login/lock UI possible. **UNVERIFIED:** this was not tested over a genuine authenticated lock session; posting an identically named distributed notification is not equivalent to locking the session.

**OBSERVED, lead:** Lock settings expose Battery, Connectivity, Focus, Now Playing widgets enabled; Calendar disabled; Glass/Clear/Frosted material choices; show volume control off; offset tuning 0 pixels; idle duration 10 minutes; show-on-screen-saver off; keep-awake 0 minutes; lock sound off and unlock sound on. Evidence: lead settings line 12.

**STATIC:** Battery-widget functions include 0x1002120cc and IOPS readers. Wallpaper/login integration contains `LoginWindowContainerView`, `WallpaperWindow`, `WallpaperManager.didChangeNotification`, `WallpaperChangeMonitor`, and `_isWallpaperNearlyWhite`. **UNVERIFIED:** exact per-widget frame, spacing, alignment to clock/avatar, material blur/vibrancy parameters, and idle animation are not recovered quantitatively. These settings are not enough to assert a pixel-accurate layout. The 10-minute lock widget idle setting must not be confused with the separate notch `idleDuration=3 seconds`.

### Keep-awake and sounds

**STATIC:** 0x100358530 clears prior assertions using 0x100358a78, reads keep-awake duration, and on a positive value creates three assertions: `NoIdleSleepAssertion`, `NoDisplaySleepAssertion`, `PreventUserIdleDisplaySleep`, level 255. IDs are stored separately and released through `IOPMAssertionRelease`. A sleepTask is created. **INFERRED:** that task supplies expiry cleanup after the configured minute duration; exact task conversion/release ordering was not fully traced. Evidence: `f_lock_assertions_100358530.txt`, `f_lock_release_assertions_100358a78.txt`.

**STATIC:** LockManager preloads `lock.caf` and `unlock.caf` at 0x10034fa14/0x10034fa34. Durations are in §7. **UNVERIFIED:** recorded runtime clip has no audio track; audible playback was not validated.

### Actual runtime results

**OBSERVED:** All six distributed notification posts returned success. `screenIsLocked` alone produced no visible widget transition in the sampled screenshot. `screenLockUIIsShown` widened the black top-center region to x=689…910, y=0…28 (**222×29**); `screenLockUIIsHidden` restored 144×29. No complete lock-widget dashboard was shown. Evidence: `synthetic_locked.png`, `synthetic_lockui.png`, `synthetic_unlockui.png` (other screenshots in the archive are JPEG re-encodes of the PNG originals; bounds were measured on the PNGs), clip, matrix t=13.546…20.051.

**OBSERVED:** The sampled synthetic screensaver-start screenshot no longer contains the black top notch; the stop screenshot contains it again. `open -a ScreenSaverEngine` returned success and replaced the desktop with a plain dark screen until Escape. `pmset displaysleepnow` returned success and produced a black screen; `caffeinate -u -t 2` restored the desktop. Evidence: corresponding screenshots and matrix t=22.205…32.047.

**OBSERVED:** `/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession` does not exist on this macOS image, so `CGSession -suspend` could not be run. **UNVERIFIED:** real lock-screen security context, password/Touch ID unlock, and lock widgets on a physical computer remain untested.

## 5. Brightness HUD

### Complete recovered path and unresolved boundaries

**STATIC:** `BrightnessManager` stores observedDisplayID, actualBrightnessByDisplayID, localBrightnessTargetByDisplayID, localBrightnessCallbackSuppressionDeadlines, brightnessWriteTask, coalescing/suppression settings, fallbackNormalMediaKeyStep, fineMediaKeyStepScale, edgeDuration, currentBrightness, and shouldShowExternalDisplaySymbol. This separates hardware-reported state from optimistic local targets. Evidence: `fieldmd_hw.txt`, BrightnessManager at 0x10052fc78.

**STATIC:** Capability and observer setup at 0x1001197cc uses `DisplayServicesCanChangeBrightness` and `DisplayServicesRegisterForBrightnessChangeNotifications`. Reads occur at 0x100118d58, 0x100119b18, 0x10011cbb0. Set paths at 0x10011b7a0 and 0x10011be20 use `DisplayServicesSetBrightnessSmooth` and `DisplayServicesSetBrightness`. The decoded smooth path reads current brightness, clamps target to [0,1], attempts the smooth API, and has an ordinary-set fallback/error path. Task cancellation is checked. Evidence: `f_bright_register_1001197cc.txt`, `f_bright_set_10011b7a0.txt`, `f_bright_set2_10011be20.txt`.

**STATIC:** Step computation at 0x100122f0c asks `DisplayServicesGetBrightnessIncrement`. Successful positive values are used; otherwise normal step = 0.0625. Fine flag scales it by 0.25, hence fallback fine step = 0.015625. Actual hardware's reported increment takes precedence over hardcoded 1/16. Evidence: `f_bright_increment_100122f0c.txt`.

**STATIC:** Target preference enum includes explicit display, automatic, internal display, external display. Capability/target selection functions occur at 0x1001225e4, 0x1001228e4, 0x100122c40. **UNVERIFIED:** exact automatic target priority and behavior for non-DDC external screens.

**INFERRED:** Local target dictionaries and suppression deadlines prevent asynchronous brightness-change callbacks from fighting recent key writes. **UNVERIFIED:** exact coalescing delay, suppression interval, resampling count, and branch-to-Speed-setting mapping. Do not infer Smooth/Fast/Instant solely from whether an API name contains “Smooth”.

**STATIC / OBSERVED, lead:** `HUDSpeed` cases are smooth/fast/instant. Display settings expose duration 1.5 seconds, White/Accent/Glow styles, percentage off, label visible, and three speeds. A nearby view at 0x10013cae0 has critically damped SwiftUI spring response 0.2, damping 1, blend 0 at 0x10013d670 and 0x10013d74c. **UNVERIFIED:** this is not sufficient to assign those constants to all three brightness speed modes. Exact mode-specific progress and outer-notch curves are unresolved.

**OBSERVED:** Synthetic subtype-8 brightness key 2 (up), key 3 (down), and Shift+Option up events all posted successfully; no brightness HUD appeared in the capture or sampled screenshots. Volume and mute controls also produced no visible HUD, so their absence is not evidence that brightness decoding alone failed. A real DisplayServices-capable screen is still required to verify that path. No mock screen response or patched capability check was substituted.

**UNVERIFIED:** no brightness-specific sound was established. Shared `volume.caf` existence is not evidence that brightness plays it. Onboarding screenshots contain an animated example Display/Sound pill, but that is a demo, **not** a successful live brightness test.

## 6. Native OSD suppression, modifier keys, keyboard backlight

### Event tap and exact swallowing

**STATIC:** At 0x100134354 Alcove creates `CGEventTapCreate(tap:1, place:0, options:0, mask:0x4c00, callback:0x1001368ac, userInfo:self)`: session event tap, head insertion, active/default option, listening for keyDown(10), keyUp(11), and systemDefined(14). It adds a run-loop source and enables the tap. The callback thunk enters 0x1001367fc, which re-enables a disabled tap after an `AXIsProcessTrusted` check. Evidence: `f_eventtap_create_100134354.txt`, `f_eventtap_callback_1001368ac.txt`, `f_eventtap_reenable_1001367fc.txt`.

**STATIC:** NX parsing at 0x100136eac:

1. Construct NSEvent and require subtype 8 (0x100136ef4–0x100136efc).
2. Read `data1`; key type is upper 16 bits, key state is the middle byte, repeat flag includes low bit. Handle 0x0a/0x0b down/up conventions.
3. Combine NSEvent flags, CGEvent flags, and current source flags.
4. Route through display/keyboard target preference and modifier logic.
5. Call handler 0x1001372b0.
6. At **0x100137194–0x100137198**, if handler result bit 0 is set, choose `xzr` instead of the original event pointer. Returning null swallows the event; otherwise return the original event.

**STATIC:** This establishes interception plus app-owned changes as the positive suppression mechanism. The active tap alone was only a clue; the conditional null return is the proof. **UNVERIFIED:** not every key/state is always swallowed; capability, modifier, and feature settings provide passthrough branches.

### Key and modifier matrix

| Status | Input | Recovered handling |
|---|---|---|
| STATIC | 0 / 1 | sound up/down handler paths with normal ±1/16 and fine ±1/64 constants |
| STATIC | 2 / 3 | brightness up/down, target selection and DisplayServices increment path |
| STATIC | 7 | mute path |
| OBSERVED / UNVERIFIED | 21 / 22 | synthetic illumination-up/down posted; no visible response or actual keyboard light available |
| STATIC | Shift+Option | `(flags & 0xa0000)==0xa0000` computes fine adjustment, 0x100137140–0x10013714c |
| STATIC | Option without Shift | recognized volume/mute and brightness keys may open Sound or Displays preferences through 0x10013afbc |
| STATIC | Command | explicit passthrough branch at 0x100137074 |
| UNVERIFIED | Shift-only / Control combinations | additional feedback and target-selection branches exist; their complete user-facing semantics are not established |

**STATIC:** The Option handler contains `x-apple.systempreferences:com.apple.preference.sound` and `…displays` at 0x10013b070/0x10013b090. Do not reduce all Option-modified input to fine steps. Evidence: `f_optionkey_10013afbc.txt`.

### Keyboard-origin and resampling machinery

**STATIC:** 0x100138cec enumerates `IOHIDDevice`, checks `PrimaryUsagePage`, and searches `HIDKeyboardLayoutValue` in the IOService plane. 0x100138fa0 examines keyboard identifiers including `internal keyboard`, `keyboard / trackpad`, `keyboard/trackpad`, `virtualhidkeyboard`, and `virtual hid keyboard`. These feed keyboard-origin/display-target logic. `KeyboardBrightnessResampleState` carries id, rawKeyCode, targetPreference, isFineAdjustment; related fields name a minimum apply interval, initial resample delay and interval. Evidence: `f_ioreg_100138cec.txt`, `f_ioreg_100138fa0.txt`, field metadata.

**UNVERIFIED:** these names do not prove a complete implementation of the physical keyboard-backlight actuator. Exact illumination API, key 21/22 swallowing policy, and numeric resampling intervals remain unresolved. In particular, “KeyboardBrightness” state may concern brightness keys originating from different keyboards, not only keyboard illumination.

### BetterDisplay and OSDUIHelper

**STATIC:** Integration initializer 0x100132878 checks `pro.betterdisplay.BetterDisplay` and subscribes to `pro.betterdisplay.BetterDisplay.launched`, `.terminated`, `com.betterdisplay.BetterDisplay.osd`, and `.request`. A 0.075-second constant is present; its global debounce meaning is not proven. Evidence: `f_betterdisplay_100132878.txt`.

**STATIC:** Decodable OSD payload fields: systemIconID, value, maxValue, displayID/displayId/targetDisplayID, uuid/displayUUID/targetUUID. Request payload: uuid, commands `[String]`, parameters `[String:String?]`. **INFERRED:** this bridges external-display OSD events and integration commands to Alcove. Exact command names and request-response behavior are unverified. Evidence: `fieldmd_hw.txt`.

**STATIC, negative search:** Searches of supplied main/helper strings and imports found no `OSDUIHelper`, `launchctl`, or `killall` evidence supporting an OSD-helper-killing design. **UNVERIFIED:** absence of those strings does not exclude dynamically built/private IPC operations. The positively decoded event-swallowing path is sufficient to explain suppression without inventing a process-kill mechanism.

**OBSERVED:** OSDUIHelper was not running on this VM at baseline. No native HUD appeared during the synthetic key run. **UNVERIFIED:** this is not an A/B test of suppression. A proper follow-up needs a native OSD-capable Mac, identical keys with Alcove off/on, proof of volume/brightness changes, and key-up/repeat/modifier coverage.

## 7. Quantitative sound/media inventory

**STATIC:** Metadata measured with ffprobe, not estimated by listening. Evidence: `ev/logs/media_inventory.json`.

| Status | Resource | Duration | Encoding |
|---|---|---:|---|
| STATIC | lock.caf | 0.283938 s | PCM 24-bit LE, 48 kHz, stereo |
| STATIC | unlock.caf | 0.269728 s | PCM 16-bit LE, 44.1 kHz, mono |
| STATIC | low-power.caf | 0.672018 s | PCM 16-bit LE, 44.1 kHz, stereo |
| STATIC | low-battery.caf | 1.095875 s | PCM 16-bit LE, 48 kHz, mono |
| STATIC | volume.caf | 0.382426 s | PCM 16-bit LE, 44.1 kHz, mono |
| STATIC | Each of 15 AirPods videos | 6.000000 s | H.264, 96×96, 60fps, 360 frames, video only |

**STATIC:** SoundManager keeps reusable and per-name audio players and uses AVAudioPlayer. **UNVERIFIED:** trigger-to-audio latency, output gain, simultaneous-alert arbitration, and observed audible playback in this session.

## 8. Reproduction, evidence, and remaining validation

**OBSERVED:** `ev/scripts/runtime_matrix.py` records a 60fps-requested AVFoundation capture while posting hardware events and notifications, launches the screensaver, sleeps/wakes the display, and runs the adjusted-size experiments. `hwkeys.swift` encodes subtype 8 with `(key<<16)|((down?0xa:0xb)<<8)`, posts down then up 20 ms later, and spaces repeated pairs by 150 ms. Flags are optional hexadecimal; `a0000` is Shift+Option. `postnotif.swift` uses DistributedNotificationCenter with immediate delivery.

**OBSERVED:** Captured file `ev/clips/hardware_matrix.mp4` is 1600×1200, reports 60/1 rate, 2087 encoded frames, 35.916668-second duration, and has no audio track. Screen sleep/capture gaps mean it must not be treated as 60 unique samples per second throughout. Command timestamps in `runtime_matrix.json` are measured from script startup, not exact video PTS. Avoid assigning exact frame latency by multiplying those timestamps by 60.

**OBSERVED:** Important evidence files:

- `ev/logs/runtime_matrix.json`: commands, monotonic timings, exit status, output.
- `ev/logs/capture_metadata.json`: encoded capture metadata.
- `ev/logs/screenshot_bboxes.json`: simple dark-pixel bounds, not a semantic shape detector.
- `ev/logs/screen_geometry.json`, `environment.txt`: display and environment inputs.
- `ev/shots/`: named post-trigger full screenshots and adjusted-size experiments.
- `ev/dis/`: targeted disassembly, selector references, Swift hardware metadata, raw lookup tables.
- `ev/scripts/`: sources and executable helpers for reproducibility.
- `ev/notes_progress.md`: chronological scratch notes; **final corrections and this report supersede early hypotheses**.
- `lead_reference/`: supplied notes/settings/localization and earlier reports for provenance.
- `EVIDENCE_INDEX.txt` and `SHA256SUMS.txt`: packaged file inventory/integrity.

**UNVERIFIED:** Priority follow-up list, with no guessed answers:

1. Real notch plus mixed-scale/multiple-display selection; measure auxiliary rectangles on each requested Mac model.
2. Exact nonzero adjusted-width/height semantics and final view offsets.
3. Mac-battery source transitions, threshold equality/re-arm, low-power-on/off, actual battery UI and animation/sounds.
4. Physical AirPods left/right availability, case values, route reconnect and low-device-battery alerts; generic peripherals.
5. Actual locked-session LockPanel, all widget/material layouts, idle/keep-awake expiration, Touch ID.
6. DisplayServices-capable physical brightness changes; Smooth/Fast/Instant timing; callback coalescing.
7. Native OSD off/on A/B tests, keyboard illumination actuator, repeats and all modifier combinations, live BetterDisplay.

**INFERRED:** A clone can implement the recovered API adapters, model table, base geometry, state separation, and conditional key swallowing directly from these findings. It should not claim matching presentation or unsupported hardware behavior until the above missing tests are performed.
