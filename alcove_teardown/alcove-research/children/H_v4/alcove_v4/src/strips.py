#!/usr/bin/env python3
"""strips.py <tag> : per-direction contact sheet; each gesture = frames onset-5 | onset+30 | onset+130 (300x60 notch crop)"""
import sys, csv, subprocess, numpy as np
from PIL import Image, ImageDraw
tag=sys.argv[1]; gcsv=sys.argv[2] if len(sys.argv)>2 else f'csv/{tag}_gestures.csv'; keycol=sys.argv[3] if len(sys.argv)>3 else 'dir'
G=list(csv.DictReader(open(gcsv)))
need={}
for g in G:
    on=int(g['onset'])
    for k,o in (('pre',-5),('mid',30),('post',130)): need.setdefault(on+o,[]).append((g['idx'],k))
W,H=300,60
p=subprocess.Popen(['ffmpeg','-loglevel','error','-i',f'clips/{tag}.mp4','-vf',f'crop={W}:{H}:650:0','-f','rawvideo','-pix_fmt','rgb24','-'],stdout=subprocess.PIPE,bufsize=10**7)
frames={}; f=0; mx=max(need)
while f<=mx:
    buf=p.stdout.read(W*H*3)
    if len(buf)<W*H*3: break
    if f in need: frames[f]=Image.frombytes('RGB',(W,H),buf)
    f+=1
p.kill()
for d in sorted(set(g[keycol] for g in G)):
    gs=[g for g in G if g[keycol]==d]
    rows=(len(gs)+2)//3
    sheet=Image.new('RGB',(9*W+8*4, rows*(H+14)),(40,40,40)); dr=ImageDraw.Draw(sheet)
    for i,g in enumerate(gs):
        r,c=divmod(i,3); on=int(g['onset'])
        for k,o in enumerate((-5,30,130)):
            x=(c*3+k)*(W+4); y=r*(H+14)
            im=frames.get(on+o)
            if im: sheet.paste(im,(x,y+14))
        dr.text(((c*3)*(W+4)+2,y+1),f"#{g['idx']} {d} {g['dir']} {g['dist']}px r{g['rep']} rev{g.get('rev','0')} pre|mid|post",fill=(255,255,0))
    sheet.save(f'frames/{tag}_{d}_sheet.png'); print('saved',d,len(gs))
