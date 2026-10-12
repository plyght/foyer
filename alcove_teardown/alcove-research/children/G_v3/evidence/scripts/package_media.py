import concurrent.futures
import hashlib
import json
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw

root = Path('/Users/devin/alcove-uncovered/alcove_uncovered_evidence/live')
source = Path('/Users/devin/screencasts/alcove-live-primary')
clips = root / 'raw_capture_segments'
strips = root / 'frame_strips'
clips.mkdir(exist_ok=True)
strips.mkdir(exist_ok=True)


def collect(path):
    probe = json.loads(subprocess.check_output([
        'ffprobe', '-v', 'error', '-select_streams', 'v:0', '-count_frames',
        '-show_entries', 'stream=codec_name,width,height,r_frame_rate,avg_frame_rate,nb_read_frames:format=duration',
        '-of', 'json', str(path)]))
    target = clips / (path.stem + '.mp4')
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', str(path), '-map', '0:v:0',
                    '-c', 'copy', '-movflags', '+faststart', str(target)], check=True)
    duration = float(probe['format']['duration'])
    times = [0.5, duration / 3, duration * 2 / 3, max(0.5, duration - 1)]
    sheet = Image.new('RGB', (1600, 1260), 'white')
    draw = ImageDraw.Draw(sheet)
    for index, second in enumerate(times):
        frame = strips / (path.stem + f'-sample-{index}.png')
        subprocess.run(['ffmpeg', '-v', 'error', '-y', '-ss', str(second), '-i',
                        str(target), '-frames:v', '1', '-vf', 'scale=800:-1',
                        str(frame)], check=True)
        if frame.exists():
            with Image.open(frame) as image:
                sheet.paste(image.convert('RGB'), ((index % 2) * 800, (index // 2) * 630 + 30))
            frame.unlink()
        draw.text(((index % 2) * 800 + 8, (index // 2) * 630 + 8),
                  f'{target.name} | seek t={second:.3f}s', fill='black')
    sheet.save(strips / (path.stem + '-strip.jpg'), quality=92)
    return dict(source_name=path.name, source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                archived_clip=str(target.relative_to(root)), source_probe=probe,
                frame_strip_seek_seconds=times)


with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
    entries = list(pool.map(collect, sorted(source.glob('*-raw-*.mkv'))))
(root / 'video_inventory.json').write_text(json.dumps(entries, indent=2))
print('Losslessly remuxed and sampled', len(entries), 'raw video segments')
