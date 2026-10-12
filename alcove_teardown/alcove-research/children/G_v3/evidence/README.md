# Alcove uncovered evidence

Read `alcove_uncovered_re.md` first. It distinguishes OBSERVED, STATIC, INFERRED and UNVERIFIED claims, and identifies scope restrictions.

Target: Alcove 1.7.7 build 199, bundle ID com.henrikruscon.Alcove. Main-executable arm64 slice SHA-256: `14520b5dd7b91b6e248122194dc206634173fb014d105a308d824974d4f653ec`. Disassembly addresses are unslid virtual addresses with preferred image base 0x100000000; they are not file offsets or ASLR runtime addresses. Helper addresses are separate from main-app addresses.

## Layout

- `static/`: selected non-license disassembly, field metadata, asset inventory, URL prefix wrapper, generic scripting dictionary and updater evidence. Some snippets start/end inside a function to intentionally exclude unrelated branches.
- `sounds/`: decoded-file measurements, 13 waveform PNGs, FFprobe metadata and original individual sound resources. Sample-peak/RMS values are not LUFS or speaker SPL.
- `live/`: synthetic app source, UI report, recordings, screenshots and timing/lifecycle logs.
- `perf/`: raw tool logs, computed tables and long-run resident-memory plot. RSS and physical footprint are different metrics. The long run includes deliberate UI/device changes and is not an idle leak test.
- `scripts/`: scripts actually used for measurement and extraction, retained with their original VM paths. They require editing the root/source/output paths to run elsewhere. The binary inspection scripts additionally require the public application and a generated function index/otool dump; whole binaries and whole-app disassembly are intentionally not redistributed here.

All original captures are from a macOS virtual machine. Its synthetic screen and BlackHole audio device do not stand in for real battery, notch, speakers, AirPods, GPU-energy hardware counters or physical hot-unplug timing.

## Collection commands

Audio: FFprobe JSON and FFmpeg float32 PCM decoding; Python NumPy/Matplotlib. See `audio_inventory.py` and per-file JSONs.

Passive process collection used:

```text
top -l 900 -s 1 -pid 3840 -stats pid,command,cpu,mem,power,threads,time,idlew,csw
powermetrics --samplers tasks --show-process-gpu --show-process-energy -i 1000 -n 900
footprint 3840
vmmap --summary 3840
sample 3840 5 1
```

Powermetrics requires OS authorization; it was available on this VM. `perf_growth.py` collected `ps` and two-sample `top` observations every 30 seconds. The first top CPU sample is cumulative/startup and should not be treated as a one-second instantaneous observation. The workload summary uses explicit phase windows from the UI observer; no guessed workload labels are applied to the entire mixed session.

The updater reproduction script is a **plain, unauthenticated, read-only GET**. It does not send keys or access any license endpoint. The observed response was HTTP 401; no update was downloaded or installed.

`MANIFEST.sha256` inventories the completed package. No account password, license value, full license handler, or licensing bypass material is intentionally included.

## Video and synthetic probes

The primary capture's raw video was losslessly remuxed from 13 Matroska segments to MP4. Source hashes, probe data and sampled times are in `live/video_inventory.json`; overview strips are in `live/frame_strips/`. Capture was requested at 60 fps but has real timestamp gaps (58.78 fps aggregate). A redundant AVFoundation recorder failed; the primary raw stream remained intact. Annotated videos can slow down at checkpoints and are not the timing source.

SyntheticListedID intentionally uses a recognized game-service bundle identifier to isolate the classifier. The helpers were used only in this disposable VM, not installed over any genuine application. The display helper uses private CGVirtualDisplay interfaces; these results do not establish a production-supported display API or physical-monitor behavior. The launch clock is separate instrumentation; Alcove itself was not modified.

After extraction, `shasum -a256 -c MANIFEST.sha256` checks every packaged file. The manifest deliberately does not hash itself. `alcove_uncovered_re.md` is included inside the ZIP as well as delivered separately.
