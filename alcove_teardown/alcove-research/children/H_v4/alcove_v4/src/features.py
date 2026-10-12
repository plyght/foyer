#!/usr/bin/env python3
"""Extract per-frame notch features from a 60fps 1600x1200 capture.
usage: features.py clip.mp4 out.csv
Crop: x 600..1000, y 0..420 (real px). Columns: frame,t,red_right,bright_right,bright_left,left_mean,expanded_dark,cursor_notch,cursor_park,mid_dark
"""
import sys, subprocess, numpy as np
clip, out = sys.argv[1], sys.argv[2]
W, H = 400, 420
p = subprocess.Popen(['ffmpeg','-loglevel','error','-i',clip,'-vf',f'crop={W}:{H}:600:0','-f','rawvideo','-pix_fmt','rgb24','-'], stdout=subprocess.PIPE, bufsize=10**7)
f = 0
with open(out,'w') as fo:
    fo.write('frame,t,red_right,bright_right,bright_left,left_mean,expanded_dark,cursor_notch,cursor_park,mid_dark\n')
    while True:
        buf = p.stdout.read(W*H*3)
        if len(buf) < W*H*3: break
        im = np.frombuffer(buf, np.uint8).reshape(H,W,3).astype(np.int16)
        r,g,b = im[...,0],im[...,1],im[...,2]
        right = (slice(0,34), slice(230,330))
        red_right = int(((r[right]>140)&(g[right]<100)&(b[right]<110)).sum())
        bright_right = int(((r[right]>150)&(g[right]>150)&(b[right]>150)).sum())
        left = (slice(0,34), slice(70,130))
        bright_left = int(((r[left]>150)&(g[left]>150)&(b[left]>150)).sum())
        left_mean = float(im[left].mean())
        s = im.sum(axis=2)
        expanded_dark = int((s[90:300, 50:350] < 60).sum())
        mid_dark = int((s[40:80, 150:250] < 60).sum())
        cn = s[4:30, 196:214]; cursor_notch = int((cn > 690).sum())
        cp = s[396:420, 196:214]; cursor_park = int((cp > 690).sum())
        fo.write(f'{f},{f/60:.4f},{red_right},{bright_right},{bright_left},{left_mean:.1f},{expanded_dark},{cursor_notch},{cursor_park},{mid_dark}\n')
        f += 1
print('frames', f)
