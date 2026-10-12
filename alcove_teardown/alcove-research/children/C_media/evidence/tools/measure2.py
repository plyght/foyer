import sys, subprocess, numpy as np, json
# usage: measure2.py clip.mp4 [thr] [y1] -> per-frame notch bbox in top-centre ROI (x 400..1200, y 0..y1)
# width: dark run on row 2 ; height: for columns in centre band, longest contiguous dark run from top -> max,median ; also bottom-most dark row within bbox columns
path=sys.argv[1]; thr=int(sys.argv[2]) if len(sys.argv)>2 else 24; y1=int(sys.argv[3]) if len(sys.argv)>3 else 400
W,H=map(int,subprocess.check_output(['ffprobe','-v','error','-select_streams','v:0','-show_entries','stream=width,height','-of','csv=p=0',path]).decode().strip().split(','))
x0,x1=W//4,3*W//4
p=subprocess.Popen(['ffmpeg','-v','error','-i',path,'-vf',f'crop={x1-x0}:{y1}:{x0}:0','-f','rawvideo','-pix_fmt','rgb24','-'],stdout=subprocess.PIPE)
fw,fh=x1-x0,y1; n=0
rows=[]
while True:
    b=p.stdout.read(fw*fh*3)
    if len(b)<fw*fh*3: break
    a=np.frombuffer(b,np.uint8).reshape(fh,fw,3).astype(int)
    dark=(a.max(axis=2)<thr)
    cols=np.where(dark[2])[0]
    if len(cols)==0:
        rows.append((n,-1,-1,0,0,0)); n+=1; continue
    L,R=cols.min(),cols.max()
    # contiguous dark run from top for each column in [L,R]
    sub=dark[:,L:R+1]
    # first non-dark row per column
    notdark=~sub
    first=np.where(notdark.any(axis=0), notdark.argmax(axis=0), fh)
    hmax=int(first.max()); hmed=int(np.median(first))
    # mean luminance of interior (to detect content)
    inner=a[4:max(5,hmed-4), L+8:R-8].mean() if hmed>12 and R-L>20 else 0
    rows.append((n,L+x0,R+x0,R-L+1,hmax,hmed,round(float(inner),1)))
    n+=1
print('frame,t_ms,left,right,width,hmax,hmed,inner_lum')
prev=None
for r in rows:
    key=r[1:6]
    if key!=prev: print(','.join(str(x) for x in [r[0],f'{r[0]*1000/60:.1f}']+list(r[1:])))
    prev=key
print('total_frames',n)
