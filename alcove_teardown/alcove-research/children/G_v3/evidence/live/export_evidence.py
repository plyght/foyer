from pathlib import Path
import subprocess, json, re

root = Path("/Users/devin/alcove-uncovered/ev/live")
source = Path("/Users/devin/screencasts/alcove-live-primary")
files = sorted(source.glob("*-raw-*.mkv"))
manifest = []
offset = 0.0
concat = []
for path in files:
    data = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
        "-show_entries", "stream=width,height,r_frame_rate,nb_read_frames:format=start_time,duration",
        "-of", "json", str(path)]))
    start = float(data["format"].get("start_time", 0))
    duration = float(data["format"]["duration"]) - start
    manifest.append(dict(file=str(path), raw_mp4_offset=offset, first_pts=start,
                         content_duration=duration, **data["streams"][0]))
    concat.extend([f"file '{path}'", f"duration {duration:.6f}"])
    offset += duration
(root / "raw_concat.txt").write_text("\n".join(concat) + "\n")
(root / "RAW_MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-f", "concat",
                "-safe", "0", "-i", str(root / "raw_concat.txt"), "-c", "copy",
                "-movflags", "+faststart", str(root / "primary_raw_60fps.mp4")], check=True)

# Cold-launch onset: source segment 012, top-center black geometry.
path = files[-1]
pts_text = subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0",
    "-show_entries", "frame=best_effort_timestamp_time", "-of", "csv=p=0", str(path)]).decode()
pts = [float(line.split(",")[0]) for line in pts_text.splitlines()
       if re.match(r"^\d+\.\d+", line)]
proc = subprocess.Popen(["ffmpeg", "-v", "error", "-i", str(path), "-vf",
    "crop=140:32:730:0,format=gray", "-fps_mode", "passthrough",
    "-f", "rawvideo", "pipe:1"], stdout=subprocess.PIPE)
table = bytes(1 if n < 32 else 0 for n in range(256))
states = []
i = 0
last = None
while True:
    block = proc.stdout.read(140 * 32)
    if len(block) != 140 * 32:
        break
    count = block.translate(table).count(b"\1")
    state = count >= 20
    if state != last:
        states.append(dict(frame=i, pts=pts[i], black_pixels=count, notch_present=state))
        last = state
    i += 1
proc.wait()
(root / "COLD_FRAME_TRANSITIONS.json").write_text(json.dumps(
    {"source": str(path), "threshold": ">=20 gray<32 pixels in x730..869,y0..31",
     "transitions": states}, indent=2) + "\n")
print(json.dumps(states, indent=2))
for entry in states:
    if entry["notch_present"] and entry["frame"] > 0:
        n = entry["frame"]
        for frame, label in [(n - 1, "cold_before_first_notch"), (n, "cold_first_notch")]:
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(path), "-vf",
                f"select=eq(n\\,{frame})", "-frames:v", "1", "-fps_mode", "vfr",
                str(root / f"{label}_{frame}.png")], check=True)
print(f"Raw content duration: {offset:.3f}s; source frames: {sum(int(m['nb_read_frames']) for m in manifest)}")
