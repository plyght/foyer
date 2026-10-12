import sys, subprocess, numpy as np
# usage: measure.py clip.mp4 [x0 x1 y1]  -> per-frame bbox of near-black notch region in top-center ROI
path=sys.argv[1]
W,H=map(int,subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=width,height','-of','csv=p=0',path]).decode().strip().split(','))
x0,x1,y1=(int(a) for a in sys.argv[2:5]) if len(sys.argv)>4 else (W//4,3*W//4,H//2)
p=subprocess.Popen(['ffmpeg','-v','error','-i',path,'-vf',f'crop={x1-x0}:{y1}:{x0}:0','-f','rawvideo','-pix_fmt','rgb24','-'],stdout=subprocess.PIPE)
fw,fh=x1-x0,y1; n=0; prev=None
print('frame,t_ms,left,right,width,height')
while True:
    b=p.stdout.read(fw*fh*3)
    if len(b)<fw*fh*3: break
    a=np.frombuffer(b,np.uint8).reshape(fh,fw,3).astype(int)
    dark=(a.max(axis=2)<22)
    cols=np.where(dark[2])[0]          # row 2 = just below top edge
    rows=np.where(dark[:,fw//2])[0]     # centre column
    if len(cols)==0: L=R=Hh=-1
    else:
        L,R=cols.min()+x0,cols.max()+x0
        # contiguous dark run from top in centre col
        Hh=0
        for r in range(fh):
            if dark[r,fw//2]: Hh=r+1
            else: break
    cur=(L,R,Hh)
    if cur!=prev: print(f'{n},{n*1000/60:.1f},{L},{R},{R-L+1 if L>=0 else 0},{Hh}')
    prev=cur; n+=1
print('total_frames',n)
