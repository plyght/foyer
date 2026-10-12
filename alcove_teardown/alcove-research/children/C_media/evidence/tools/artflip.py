import subprocess, numpy as np, sys
# per-frame: in the compact artwork cell (x0..x1, y0..y1) count non-black columns and mean colour; detects 3D flip (width shrink) and fades
f, x0, x1, y0, y1, fa, fb = sys.argv[1], *map(int, sys.argv[2:8])
W, H = 1600, 1200
raw = subprocess.run(["ffmpeg","-v","error","-i",f,"-f","rawvideo","-pix_fmt","rgb24","-"],capture_output=True).stdout
n = len(raw)//(W*H*3)
a = np.frombuffer(raw, np.uint8).reshape(n, H, W, 3)
prev=None
for i in range(fa, min(fb, n)):
    c = a[i, y0:y1, x0:x1].astype(int)
    lit = c.max(axis=2) > 40
    cols = np.where(lit.any(axis=0))[0]
    w = (cols.max()-cols.min()+1) if len(cols) else 0
    mean = c[lit].mean(axis=0) if lit.any() else np.zeros(3)
    print(f"{i},{i*1000/60:.1f},{w},{lit.sum()},{mean[0]:.0f},{mean[1]:.0f},{mean[2]:.0f}")
