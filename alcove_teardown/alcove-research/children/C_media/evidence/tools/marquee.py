import subprocess,numpy as np,sys
# usage: marquee.py clip x y w h f0 f1  -> cumulative horizontal text shift (px) per frame via template tracking
f,x0,y0,w,h,f0,f1=sys.argv[1],*map(int,sys.argv[2:8])
fw,fh=1600,1200
p=subprocess.Popen(['ffmpeg','-v','error','-i',f,'-f','rawvideo','-pix_fmt','gray','-'],stdout=subprocess.PIPE)
n=0;tmpl=None;cum=0;prevs=0;out=[]
T0,TW=w//2-40,80
while True:
    b=p.stdout.read(fw*fh)
    if len(b)<fw*fh: break
    if f0<=n<=f1:
        prof=np.frombuffer(b,np.uint8).reshape(fh,fw)[y0:y0+h,x0:x0+w].astype(float).mean(axis=0)
        if tmpl is None:
            tmpl=prof[T0:T0+TW]-prof[T0:T0+TW].mean(); out.append((n,0)); n+=1; continue
        best=(0,-1e9)
        for s in range(-45,46):
            a=T0+s
            if a<0 or a+TW>w: continue
            seg=prof[a:a+TW]-prof[a:a+TW].mean()
            c=(seg*tmpl).sum()/(np.linalg.norm(seg)*np.linalg.norm(tmpl)+1e-9)
            if c>best[1]: best=(s,c)
        s,c=best
        if abs(s)>=35 or c<0.6:
            cum+=s; tmpl=prof[T0+s:T0+s+TW]-prof[T0+s:T0+s+TW].mean(); 
            # re-anchor: template now at T0 after shifting by s
            tmpl=prof[T0:T0+TW]-prof[T0:T0+TW].mean(); base=cum; prevs=0
        out.append((n,cum+s,round(c,2)))
    n+=1
for r in out: print(*r)
