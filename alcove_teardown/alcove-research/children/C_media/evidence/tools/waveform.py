import subprocess, numpy as np, sys
# waveform region analysis: per-frame bar columns (lit column runs), bar heights, and whether frame differs from previous
f, x0, x1, y0, y1, fa, fb = sys.argv[1], *map(int, sys.argv[2:8])
W, H = 1600, 1200
raw = subprocess.run(["ffmpeg","-v","error","-i",f,"-f","rawvideo","-pix_fmt","rgb24","-"],capture_output=True).stdout
n = len(raw)//(W*H*3)
a = np.frombuffer(raw, np.uint8).reshape(n, H, W, 3)
prev=None; changes=0; total=0
for i in range(fa, min(fb, n)):
    c = a[i, y0:y1, x0:x1].astype(int)
    lit = c.max(axis=2) > 60
    colmask = lit.any(axis=0)
    # runs of lit columns = bars
    runs=[]; start=None
    for x,v in enumerate(colmask):
        if v and start is None: start=x
        if not v and start is not None: runs.append((start,x-1)); start=None
    if start is not None: runs.append((start,len(colmask)-1))
    heights=[int(lit[:,r0:r1+1].any(axis=1).sum()) for r0,r1 in runs]
    diff = 0 if prev is None else int((np.abs(c-prev).max(axis=2)>30).sum())
    if prev is not None:
        total+=1; changes += diff>5
    prev=c
    print(f"{i},{i*1000/60:.1f},bars={len(runs)},runs={runs},h={heights},diffpx={diff}")
print(f"frames_with_change {changes}/{total}")
