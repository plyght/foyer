import csv, subprocess, numpy as np
from PIL import Image, ImageDraw
G=[r for r in csv.DictReader(open('csv/B1_compact_gestures2.csv')) if r['dir'] in ('left','right') and 45<=int(r['dist'])<=100]
offs=[6,12,18,24,36,48,72]
need={}
for g in G:
    t0=int(g['onset'])+9
    for o in offs: need.setdefault(t0+o,[]).append(g['idx'])
W,H=300,45
p=subprocess.Popen(['ffmpeg','-loglevel','error','-i','clips/B1_compact.mp4','-vf',f'crop={W}:{H}:650:0','-f','rawvideo','-pix_fmt','rgb24','-'],stdout=subprocess.PIPE,bufsize=10**7)
frames={}; f=0; mx=max(need)
while f<=mx:
    buf=p.stdout.read(W*H*3)
    if len(buf)<W*H*3: break
    if f in need: frames[f]=Image.frombytes('RGB',(W,H),buf)
    f+=1
p.kill()
for d in ('left','right'):
    gs=[g for g in G if g['dir']==d]
    sheet=Image.new('RGB',(len(offs)*(W+4), len(gs)*(H+14)),(40,40,40)); dr=ImageDraw.Draw(sheet)
    for r,g in enumerate(gs):
        t0=int(g['onset'])+9; y=r*(H+14)
        for k,o in enumerate(offs):
            im=frames.get(t0+o)
            if im: sheet.paste(im,(k*(W+4),y+14))
        dr.text((2,y+1),f"#{g['idx']} {d} {g['dist']}px r{g['rep']}  frames +{offs}",fill=(255,255,0))
    sheet.save(f'frames/B1_compact_{d}_skip_sheet.png'); print(d,len(gs))
