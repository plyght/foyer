import subprocess, numpy as np, sys
# per-frame HUD bar fill: in the crop (x0..x1,y0..y1) count pixels brighter than thr and report leftmost/rightmost bright column (bar extent) + bright count
f, x0, x1, y0, y1, fa, fb = sys.argv[1], *map(int, sys.argv[2:8])
thr = int(sys.argv[8]) if len(sys.argv) > 8 else 180
W, H = 1600, 1200
raw = subprocess.run(["ffmpeg","-v","error","-i",f,"-f","rawvideo","-pix_fmt","rgb24","-"],capture_output=True).stdout
n = len(raw)//(W*H*3)
a = np.frombuffer(raw, np.uint8).reshape(n, H, W, 3)
prev=None
for i in range(fa, min(fb, n)):
    c = a[i, y0:y1, x0:x1]
    bright = c.min(axis=2) > thr
    cols = np.where(bright.any(axis=0))[0]
    ext = (int(cols.min())+x0, int(cols.max())+x0) if len(cols) else (0,0)
    cnt = int(bright.sum())
    mean = c.reshape(-1,3).mean(axis=0)
    line=f"{i},{i*1000/60:.1f},bright={cnt},bar_x={ext[0]}-{ext[1]},barlen={ext[1]-ext[0]+1 if cnt else 0},mean=({mean[0]:.0f},{mean[1]:.0f},{mean[2]:.0f})"
    if prev != (cnt, ext): print(line)
    prev = (cnt, ext)
