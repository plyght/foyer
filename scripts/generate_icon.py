#!/usr/bin/env python3
"""Generate Foyer's original app icon (all macOS AppIcon sizes).

Design: a dark smoked-glass rounded square (macOS Big Sur icon grid: 824 pt
tile on a 1024 canvas) with a soft top sheen, and a black "island" pill near
the top edge, rimmed and glowing in Foyer's accent blue rgb(92, 158, 255),
holding a small row of waveform bars.

Usage: python3 scripts/generate_icon.py [appiconset_dir]
Requires Pillow (pip install pillow) and numpy.
"""

import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ACCENT = (92, 158, 255)
MASTER = 1024
SS = 2  # supersampling factor for the master render

SIZES = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1),
    (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]


def rounded_mask(size, box, radius):
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask


def vertical_gradient(size, top, bottom):
    t = np.linspace(0, 1, size)[:, None, None]
    top = np.array(top, dtype=np.float64)[None, None, :]
    bottom = np.array(bottom, dtype=np.float64)[None, None, :]
    rows = top * (1 - t) + bottom * t
    arr = np.repeat(rows, size, axis=1)
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def render_master():
    s = MASTER * SS
    canvas = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    # Big Sur grid: 824x824 tile centred, corner radius ~185 (of 1024).
    inset = 100 * SS
    tile_box = (inset, inset, s - inset, s - inset)
    radius = 185 * SS

    # Drop shadow under the tile.
    shadow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (tile_box[0], tile_box[1] + 18 * SS, tile_box[2], tile_box[3] + 18 * SS),
        radius=radius, fill=(0, 0, 0, 120))
    shadow = shadow.filter(ImageFilter.GaussianBlur(22 * SS))
    canvas = Image.alpha_composite(canvas, shadow)

    # Tile body: deep blue-black smoked glass.
    body = vertical_gradient(s, (44, 50, 64, 255), (9, 10, 15, 255))
    # Subtle blue bloom from the top centre (light leaking from the island).
    yy, xx = np.mgrid[0:s, 0:s].astype(np.float64)
    cx, cy = s / 2, inset + 210 * SS
    d = np.sqrt(((xx - cx) / (430 * SS)) ** 2 + ((yy - cy) / (300 * SS)) ** 2)
    bloom = np.clip(1 - d, 0, 1) ** 2.2
    body_arr = np.asarray(body).astype(np.float64)
    for c in range(3):
        body_arr[..., c] += bloom * ACCENT[c] * 0.30
    body = Image.fromarray(np.clip(body_arr, 0, 255).astype(np.uint8), "RGBA")

    tile_mask = rounded_mask(s, tile_box, radius)
    tile = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    tile.paste(body, (0, 0), tile_mask)
    canvas = Image.alpha_composite(canvas, tile)

    # Glass sheen on the upper half, fading out smoothly toward the middle.
    rows = np.arange(s, dtype=np.float64)
    sheen_alpha = np.clip(1 - (rows - tile_box[1]) / (470 * SS), 0, 1) ** 1.6 * 30
    sheen_arr = np.zeros((s, s, 4), dtype=np.float64)
    sheen_arr[..., :3] = 255
    sheen_arr[..., 3] = sheen_alpha[:, None]
    sheen = Image.fromarray(sheen_arr.astype(np.uint8), "RGBA")
    sheen_layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    sheen_layer.paste(sheen, (0, 0), tile_mask)
    canvas = Image.alpha_composite(canvas, sheen_layer)

    # Hairline rim around the tile.
    rim = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(rim).rounded_rectangle(tile_box, radius=radius, outline=(255, 255, 255, 46), width=4 * SS)
    canvas = Image.alpha_composite(canvas, rim)

    # The island: a black pill hanging near the top of the tile.
    pill_w, pill_h = 470 * SS, 128 * SS
    pill_top = inset + 150 * SS
    pill_box = (s / 2 - pill_w / 2, pill_top, s / 2 + pill_w / 2, pill_top + pill_h)

    glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.rounded_rectangle(pill_box, radius=pill_h / 2, fill=ACCENT + (210,))
    glow = glow.filter(ImageFilter.GaussianBlur(46 * SS))
    glow_clip = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    glow_clip.paste(glow, (0, 0), tile_mask)
    canvas = Image.alpha_composite(canvas, glow_clip)

    pill = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    pd = ImageDraw.Draw(pill)
    pd.rounded_rectangle(pill_box, radius=pill_h / 2, fill=(2, 3, 6, 255))
    pd.rounded_rectangle(pill_box, radius=pill_h / 2, outline=ACCENT + (235,), width=5 * SS)
    canvas = Image.alpha_composite(canvas, pill)

    # Inside the island: a glowing dot on the left and waveform bars on the right.
    detail = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    dd = ImageDraw.Draw(detail)
    mid_y = pill_top + pill_h / 2
    dot_r = 26 * SS
    dot_cx = pill_box[0] + pill_h / 2 + 8 * SS
    dd.ellipse((dot_cx - dot_r, mid_y - dot_r, dot_cx + dot_r, mid_y + dot_r), fill=ACCENT + (255,))
    bar_w = 16 * SS
    pitch = 30 * SS
    heights = [30, 58, 42, 70, 36]
    right = pill_box[2] - pill_h / 2 + 6 * SS
    for i, h in enumerate(reversed(heights)):
        x1 = right - i * pitch
        x0 = x1 - bar_w
        hh = h * SS
        dd.rounded_rectangle((x0, mid_y - hh / 2, x1, mid_y + hh / 2), radius=bar_w / 2, fill=(236, 243, 255, 255))
    detail_glow = detail.filter(ImageFilter.GaussianBlur(10 * SS))
    canvas = Image.alpha_composite(canvas, detail_glow)
    canvas = Image.alpha_composite(canvas, detail)

    return canvas.resize((MASTER, MASTER), Image.LANCZOS)


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        root, "Foyer", "Resources", "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(out_dir, exist_ok=True)
    master = render_master()

    images = []
    for size, scale in SIZES:
        px = size * scale
        name = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
        img = master if px == MASTER else master.resize((px, px), Image.LANCZOS)
        if px <= 64:
            # Tiny sizes: a touch of sharpening keeps the island readable.
            img = img.filter(ImageFilter.UnsharpMask(radius=1, percent=60, threshold=0))
        img.save(os.path.join(out_dir, name), optimize=True)
        images.append({"filename": name, "idiom": "mac", "scale": f"{scale}x", "size": f"{size}x{size}"})
        print(f"{name:24s} {px}x{px}")

    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    with open(os.path.join(out_dir, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
