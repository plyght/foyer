import sys, subprocess, numpy as np
# usage: measure2.py clip.mp4 [x0 x1 y1] -> per-frame bbox of near-black notch region: left/right at row 2, max dark extent (any column) and height at centre column + max contiguous height over all columns
path=sys.argv[1]
W,H=map(int,subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=width,height','-of','csv=p=0',path]).decode().strip().split(','))
x0,x1,y1=(int(a) for a in sys.argv[2:5]) if len(sys.argv)>4 else (W//4,3*W//4,min(H,300))
thr=int(sys.argv[5]) if len(sys.argv)>5 else 22
p=subprocess.Popen(['ffmpeg','-v','error','-i',path,'-vf',f'crop={x1-x0}:{y1}:{x0}:0','-f','rawvideo','-pix_fmt','rgb24','-'],stdout=subprocess.PIPE)
fw,fh=x1-x0,y1; n=0; prev=None
print('frame,t_ms,left,right,width,height_centre,height_max,maxwidth_row')
while True:
    b=p.stdout.read(fw*fh*3)
    if len(b)<fw*fh*3: break
    a=np.frombuffer(b,np.uint8).reshape(fh,fw,3).astype(int)
    dark=(a.max(axis=2)<thr)
    # contiguous-from-top mask per column
    cont=np.cumprod(dark,axis=0).astype(bool)
    colh=cont.sum(axis=0)
    cols=np.where(cont[2])[0]
    if len(cols)==0: L=R=-1; Hc=Hm=0; mw=0
    else:
        L,R=cols.min()+x0,cols.max()+x0
        Hc=int(colh[fw//2]); Hm=int(colh.max())
        mw=int(cont.sum(axis=1).max())
    cur=(L,R,Hc,Hm,mw)
    if cur!=prev: print(f'{n},{n*1000/60:.1f},{L},{R},{R-L+1 if L>=0 else 0},{Hc},{Hm},{mw}')
    prev=cur; n+=1
print('total_frames',n)
