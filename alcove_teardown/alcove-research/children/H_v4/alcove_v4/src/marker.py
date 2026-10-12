#!/usr/bin/env python3
"""find first frame where cursor appears at bottom-right marker (1590,1190). usage: marker.py clip.mp4 [maxsec]"""
import sys, subprocess, numpy as np
clip = sys.argv[1]; maxs = float(sys.argv[2]) if len(sys.argv)>2 else 12
W,H=40,40
p = subprocess.Popen(['ffmpeg','-loglevel','error','-t',str(maxs),'-i',clip,'-vf',f'crop={W}:{H}:1560:1160','-f','rawvideo','-pix_fmt','rgb24','-'], stdout=subprocess.PIPE)
f=0; base=None
while True:
    buf=p.stdout.read(W*H*3)
    if len(buf)<W*H*3: break
    im=np.frombuffer(buf,np.uint8).reshape(H,W,3).astype(np.int16)
    if base is None: base=im
    d=int((np.abs(im-base).sum(axis=2)>60).sum())
    if d>40: print('marker_frame',f,'t',f/60); break
    f+=1
else: print('no marker found')
