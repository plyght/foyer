import sys, subprocess, numpy as np
# usage: framediff.py clip x y w h [thr] -> frames where region changes (mean abs diff vs prev frame)
path=sys.argv[1]; x,y,w,h=map(int,sys.argv[2:6]); thr=float(sys.argv[6]) if len(sys.argv)>6 else 0.5
p=subprocess.Popen(['ffmpeg','-v','error','-i',path,'-vf',f'fps=60,crop={w}:{h}:{x}:{y}','-f','rawvideo','-pix_fmt','gray','-'],stdout=subprocess.PIPE)
n=0; prev=None; run=None
while True:
    b=p.stdout.read(w*h)
    if len(b)<w*h: break
    a=np.frombuffer(b,np.uint8).astype(np.int16)
    if prev is not None:
        d=float(np.abs(a-prev).mean())
        if d>thr:
            if run is None: run=[n,n,d]
            else: run[1]=n; run[2]=max(run[2],d)
        elif run is not None and n-run[1]>6:
            print(f'change frames {run[0]}-{run[1]} ({(run[1]-run[0]+1)*1000/60:.0f} ms) maxdiff {run[2]:.1f}')
            run=None
    prev=a; n+=1
if run: print(f'change frames {run[0]}-{run[1]} ({(run[1]-run[0]+1)*1000/60:.0f} ms) maxdiff {run[2]:.1f}')
print('frames',n)
