import sys, subprocess, numpy as np
# usage: track.py clip.mp4 x y w h f0 f1 [mode]
# mode=shift : per-frame horizontal shift (px) of ROI content vs previous frame via 1D cross-correlation of column brightness profiles (marquee speed)
# mode=diff  : per-frame mean abs diff vs previous frame + mean brightness (waveform/update-rate detection)
# mode=cols  : per-frame list of bright column runs (waveform bar count/positions)
path=sys.argv[1]; x,y,w,h,f0,f1=map(int,sys.argv[2:8]); mode=sys.argv[8] if len(sys.argv)>8 else 'shift'
p=subprocess.Popen(['ffmpeg','-v','error','-i',path,'-vf',f"select='between(n,{f0},{f1})',crop={w}:{h}:{x}:{y}",'-fps_mode','passthrough','-f','rawvideo','-pix_fmt','gray','-'],stdout=subprocess.PIPE)
prev=None; n=f0
while True:
    b=p.stdout.read(w*h)
    if len(b)<w*h: break
    a=np.frombuffer(b,np.uint8).reshape(h,w).astype(float)
    if mode=='shift':
        prof=a.mean(axis=0); prof=prof-prof.mean()
        if prev is not None:
            best=None
            for s in range(-12,13):
                if s>=0: c=(prof[s:]*prev[:w-s]).sum()/(w-s)
                else: c=(prof[:w+s]*prev[-s:]).sum()/(w+s)
                if best is None or c>best[1]: best=(s,c)
            print(f'{n},{best[0]},{a.mean():.1f}')
        prev=prof
    elif mode=='diff':
        d=np.abs(a-prev).mean() if prev is not None else 0
        print(f'{n},{d:.2f},{a.mean():.1f}')
        prev=a
    elif mode=='cols':
        bright=(a.max(axis=0)>60)
        runs=[];start=None
        for i,v in enumerate(bright):
            if v and start is None: start=i
            if not v and start is not None: runs.append((start,i-1)); start=None
        if start is not None: runs.append((start,w-1))
        heights=[int((a[:,s:e+1].max(axis=1)>60).sum()) for s,e in runs]
        print(f'{n},{len(runs)},{runs},{heights}')
    n+=1
