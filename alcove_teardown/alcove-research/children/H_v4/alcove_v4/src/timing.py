#!/usr/bin/env python3
"""timing.py <tag> [gestures_csv]: per gesture: effect (pre/post diff), motion start/end (frames after gesture t0), blank frames, width series overshoot.
Decodes crop real x650..950, y0..45 (300x45). Cursor box (real x790..816,y0..32) is masked."""
import sys, csv, subprocess, numpy as np
tag=sys.argv[1]; gcsv=sys.argv[2] if len(sys.argv)>2 else f'csv/{tag}_gestures2.csv'
G=list(csv.DictReader(open(gcsv)))
W,H=300,45
p=subprocess.Popen(['ffmpeg','-loglevel','error','-i',f'clips/{tag}.mp4','-vf',f'crop={W}:{H}:650:0','-f','rawvideo','-pix_fmt','gray','-'],stdout=subprocess.PIPE,bufsize=10**7)
frames=[]
while True:
    buf=p.stdout.read(W*H)
    if len(buf)<W*H: break
    frames.append(np.frombuffer(buf,np.uint8).reshape(H,W))
V=np.stack(frames).astype(np.int16); N=len(V)
mask=np.ones((H,W),bool); mask[0:34,138:168]=False  # cursor box
row=V[:,16,:]
def extent(r):
    nl=100
    while nl>0 and r[nl-1]<40: nl-=1
    nr=200
    while nr<W-1 and r[nr+1]<40: nr+=1
    return nl,nr
out=[]
for g in G:
    on=int(g['onset']); t0=on+9  # gesture begins ~150 ms after cursor arrives
    if t0+140>=N: continue
    pre=V[on-20:on-3].mean(axis=0); post=V[t0+100:t0+125].mean(axis=0)
    effect=float(np.abs(post-pre)[mask].mean())
    seg=V[t0:t0+130]
    motion=np.array([np.abs(seg[k+1]-seg[k])[mask].mean() for k in range(len(seg)-1)])
    mv=np.where(motion>0.6)[0]
    start=int(mv[0]) if len(mv) else -1; end=int(mv[-1])+1 if len(mv) else -1
    content=np.array([ (f[mask]>60).sum() for f in seg])
    blank=int((content<3).sum())
    widths=np.array([ (lambda e: e[1]-e[0])(extent(seg[k,16,:])) for k in range(len(seg))])
    w0=int(np.median(widths[:5])); w1=int(np.median(widths[-15:]))
    ext=int(widths.max()) if w1>w0 else int(widths.min())
    over=0.0 if w1==w0 else round(100*(ext-w1)/(w1-w0),1)
    out.append(dict(idx=g['idx'],phase=g.get('phase',''),dir=g['dir'],dist=g['dist'],rep=g['rep'],rev=g.get('rev',''),effect=round(effect,2),motion_start=start,motion_end=end,blank_frames=blank,w_pre=w0,w_post=w1,w_extreme=ext,overshoot_pct=over))
w=csv.DictWriter(open(f'csv/{tag}_timing.csv','w'),fieldnames=list(out[0].keys())); w.writeheader(); w.writerows(out)
for r in out: print(','.join(str(v) for v in r.values()))
