import json
import pathlib
import re
import subprocess
import sys

clip = pathlib.Path(sys.argv[1]).resolve()
run_id = sys.argv[2]
output_dir = clip.parent
frame_size = 140 * 32

raw = subprocess.run(
    [
        "/opt/homebrew/bin/ffmpeg",
        "-v", "error",
        "-i", str(clip),
        "-vf", "crop=140:32:730:0,format=gray",
        "-f", "rawvideo",
        "-pix_fmt", "gray",
        "pipe:1",
    ],
    check=True,
    stdout=subprocess.PIPE,
).stdout
frame_count = len(raw) // frame_size
dark_counts = [
    sum(value < 32 for value in raw[index * frame_size:(index + 1) * frame_size])
    for index in range(frame_count)
]
transition = next(
    ((index, count) for index, count in enumerate(dark_counts) if count >= 20),
    None,
)
if transition is None:
    raise SystemExit("No frame reached the existing notch threshold (>=20 gray<32 pixels).")

frame_index, dark_pixel_count = transition
if frame_index == 0:
    raise SystemExit(
        f"Threshold already met in frame 0 ({dark_pixel_count} pixels); "
        "check cursor/background before counting this run."
    )

images = []
for label, index in (("prev", frame_index - 1), ("first", frame_index)):
    image = output_dir / f"{run_id}_{label}.png"
    subprocess.run(
        [
            "/opt/homebrew/bin/ffmpeg",
            "-y",
            "-v", "error",
            "-i", str(clip),
            "-vf", f"select=eq(n\\,{index})",
            "-fps_mode", "passthrough",
            "-frames:v", "1",
            str(image),
        ],
        check=True,
    )
    images.append((label, index, image))

ocr = subprocess.run(
    [
        str(output_dir / "launch_clock_ocr"),
        *(str(image) for _, _, image in images),
    ],
    check=True,
    text=True,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
elapsed = re.findall(r"Launch elapsed:\s*([0-9]+(?:\.[0-9]+)?)", ocr.stdout)
if len(elapsed) != 2:
    raise SystemExit(f"Expected previous/first elapsed readings; OCR output was:\n{ocr.stdout}")

result = {
    "clip": str(clip),
    "frames": frame_count,
    "previous_frame": images[0][1],
    "previous_dark_pixels": dark_counts[images[0][1]],
    "previous_clock_s": float(elapsed[0]),
    "first_notch_frame": frame_index,
    "first_notch_dark_pixels": dark_pixel_count,
    "first_notch_clock_s": float(elapsed[1]),
    "latency_ms": round(float(elapsed[1]) * 1000),
    "previous_frame_png": str(images[0][2]),
    "first_notch_frame_png": str(images[1][2]),
}
print(json.dumps(result, indent=2))
if ocr.stderr:
    print(ocr.stderr, file=sys.stderr, end="")
