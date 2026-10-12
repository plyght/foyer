#!/usr/bin/env python3
"""features2.py clip.mp4 out.csv  -- crop real x600..1000,y0..140. columns:
frame,t,nl,nr,red,glyphL,glyphR,art,wave,black_below,cursor_notch"""
import sys, subprocess, numpy as np
clip,out=sys.argv[1],sys.argv[2]; W,H=400,140
p=subprocess.Popen(['ffmpeg','-loglevel','error','-i',clip,'-vf',f'crop={W}:{H}:600:0','-f','rawvideo','-pix_fmt','rgb24','-'],stdout=subprocess.PIPE,bufsize=10**7)
f=0
with open(out,'w') as fo:
    fo.write('frame,t,nl,nr,red,glyphL,glyphR,art,wave,black_below,cursor_notch\n')
    while True:
        buf=p.stdout.read(W*H*3)
        if len(buf)<W*H*3: break
        im=np.frombuffer(buf,np.uint8).reshape(H,W,3).astype(np.int16)
        r,g,b=im[...,0],im[...,1],im[...,2]; s=r+g+b
        row=s[16]; dark=row<40
        # notch extent around x=200
        nl=150
        while nl>0 and dark[nl-1]: nl-=1
        nr=250
        while nr<W-1 and dark[nr+1]: nr+=1
        band=(slice(2,32),)
        def cnt(mask,x0,x1): 
            x0=max(x0,nl); x1=min(x1,nr+1)
            return int(mask[2:32,x0:x1].sum()) if x1>x0 else 0
        white=(r>170)&(g>170)&(b>170)
        red=(r>120)&(g<90)&(b<110)
        colored=((np.abs(r-g)>25)|(np.abs(g-b)>25))&(s>90)&~red
        redc=cnt(red,260,340); gl=cnt(white,40,95); gr=cnt(white,300,345); art=cnt(colored|white,88,128); wave=cnt(white,240,300)
        black_below=int((s[60:130,200:400]<15).sum())
        cn=int((s[4:30,196:214]>690).sum())
        fo.write(f'{f},{f/60:.4f},{nl},{nr},{redc},{gl},{gr},{art},{wave},{black_below},{cn}\n'); f+=1
print('frames',f)
