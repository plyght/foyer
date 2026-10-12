
---

# v3 live pass: live waveform, lock-screen widget, explicit badge, accessibility

_Evidence: `live_v3/` (findings.md, strips/, csv, scripts bars2.py) and `clips/live_waveform_*.mp4`, `clips/lock_widget.mp4`, `clips/explicit_expand.mp4`, `clips/rm_on_open_close.mp4`._

## Live waveform (now OBSERVED)

**How it was unblocked on the VM.**
1. In System Settings, go to Privacy & Security → Screen & System Audio Recording → **System Audio Recording Only**, click **+**, and add `/Applications/Alcove.app` (then Quit & Reopen). No in-app prompt appears.
2. In Alcove, turn on Settings → Now Playing → **Use live waveform**. A small grey glyph then appears next to the label.
3. The VM has no audio output device, so the tap only received silence and the bars sat flat (CoreAudio log: "Could not find default device"). The fix was `brew install blackhole-2ch`, then `sudo killall coreaudiod`, then setting the default output to "BlackHole 2ch".

**The audio path runs (OBSERVED, `live_v3/live_waveform_log.txt`).** Inside the Alcove process, MediaPlaybackCore `MPCProcessAudioTap` logs "ASBD for process tap", then "Starting processing audio queue" on a private aggregate device named `AudioTap-<UUID>`. It stops when the track ends. This confirms the static reading: a per-process tap on the source app, not a whole-system tap.

**Compact glyph geometry (OBSERVED, 1x display).**

| Property | Value |
|---|---|
| Bar count | 5 |
| Bar width | 2 px |
| Pitch | ~3.5 px |
| Minimum height (drawn as a dot) | 2 px |
| Maximum height | 12 px |
| Colour | Grey/white, same tint path as the synthetic glyph |

**Band mapping (OBSERVED, matches STATIC).** The test file had 2 s tones at 120 / 300 / 900 / 2600 / 7000 Hz, followed by a 20 Hz → 10 kHz log sweep:

| Bar | Band (Hz) | Lit by |
|---|---|---|
| 0 | 20–170 | 120 Hz |
| 1 | 170–527 | 300 Hz |
| 2 | 527–1500 | 900 Hz |
| 3 | 1500–4500 | 2.6 kHz |
| 4 | 4500–10000 | 7 kHz |

- Each tone lit exactly one bar, and the bars run from low frequencies on the left to high on the right.
- So the compact glyph uses the **5-band variant**, which drops the 81 Hz edge.
- The sweep peaks fall ~2.1 s apart, which is about ×3 in frequency per bar. They land on the geometric band centres (≈299 / 890 / 2598 / 6708 Hz).

**Dynamics (OBSERVED).**
- **Attack:** floor to max in 6–8 frames (100–133 ms). Example sequence: `2,6,6,10,10,10,12`.
- **Release:** max to floor in 6–9 frames (100–150 ms). Example sequence: `12,11,10,10,10,6,6,2`.
- **Steps:** heights change every ~2 frames (33 ms), in steps of about 4 px. Attack and release are symmetric, with no slow peak-hold or decay.
- **Interpretation (INFERRED):** this matches 20 Hz analyzer frames plus the 0.08 s ease-out Core Animation tween.

**Loudness mapping (OBSERVED bound, INFERRED curve).**
- A steady 0.8 FS sine pins its band at maximum height.
- On a linear 0 → 0.8 FS ramp, the bar reaches maximum within ~0.1–0.2 s, at roughly −34 to −28 dBFS.
- Inference: strong dB compression with a low floor. Real music will sit near the top unless it is quiet.
- The analyzer's dB floor and ceiling still live in Apple's private code. This empirical bound is the best value available.

**Clone recipe.** Use a per-process Core Audio tap on the now-playing app's PID. Compute 5 log bands (20/170/527/1500/4500/10000) at 20 Hz. Map dB to a 0–1 level with a low floor. Bars are 2 px wide, 2–12 px tall, and animate height with a 0.08 s ease-out.

## Lock-screen widget (now OBSERVED)

Real lock via `Ctrl+Cmd+Q`, recorded at 60 fps in `clips/lock_widget.mp4`; frame strips are in `live_v3/strips/`.

**Layout.**
- A translucent glass card, tinted from the artwork (green in this test), centred above the account avatar.
- **Top row:** artwork tile, title marquee, artist, and a live waveform glyph on the right.
- **Middle:** elapsed time, progress bar, remaining time.
- **Bottom:** shuffle, previous, play/pause, next.
- Separately, the notch shows a pill with a lock glyph while locked.

**Timing (OBSERVED).**
- The lock screen appears first; the widget stays absent for ~0.4 s.
- The widget then fades/scales in over ~100–200 ms.
- The marquee, progress and waveform keep animating while the Mac is locked.

**Unlock (OBSERVED).** Roughly two black frames (~33 ms), then a crossfade of about 117 ms.

## Explicit badge

- **Setting (OBSERVED):** Settings → Now Playing → badge picker is set to **Explicit**, the default.
- **Test (OBSERVED):** a local AAC file tagged `rtng=Explicit` with AtomicParsley. Music shows an **E** next to it in the library, but Alcove shows **no badge** in either the compact or expanded view.
- **Why (INFERRED):** Music only publishes `kMRMediaRemoteNowPlayingInfoIsExplicitTrack` for catalog (Apple Music/iTunes Store) items, so local files never trigger the badge. The Spotify path reads the `explicit` field from the Web API.
- **Badge visual:** still UNVERIFIED live. From the binary (STATIC): the glyph is the SF Symbol `e.square.fill`.

## Reduce Motion / Reduce Transparency

- **Reduce Motion: ignored (OBSERVED).**
  - With it on (NSWorkspace confirmed `true`), the open animation is unchanged: 140 → 378 peak at ~250 ms → 358 settled by ~450 ms. That is the same 9.2% overshoot as without it.
  - Close takes ~617 ms.
  - The binary has no reduce-motion references.
- **Reduce Transparency: no visible change in Settings (OBSERVED).** Screenshots of the Settings window are pixel-identical with it on and off.
  - The notch body is opaque black, so it is unaffected.
  - The lock-screen glass and the clear-glass HUD style were not tested with it on.

## Still UNVERIFIED after v3

- **Cycle-activity swipe threshold.** The VM can't hold two cyclable activities at once. The best value remains ~100 px, observed once.
- **Low Power Mode banner.** `pmset` reports "LowPowerMode not supported on AC Power". The static colours and sounds are in Part F.
- **Brightness HUD visuals, physical AirPods and battery.** These need hardware (Part F).
