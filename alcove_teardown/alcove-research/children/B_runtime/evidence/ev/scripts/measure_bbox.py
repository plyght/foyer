#!/usr/bin/env python
"""Bounding box of near-black pixels (the notch/HUD body) in a screenshot crop.
usage: measure_bbox.py file.png [x_offset y_offset]  -> prints bbox in screen px (1x display)"""
import sys, numpy as np, Quartz as Q
f=sys.argv[1]; ox=int(sys.argv[2]) if len(sys.argv)>2 else 0; oy=int(sys.argv[3]) if len(sys.argv)>3 else 0
src=Q.CGImageSourceCreateWithURL(Q.CFURLCreateWithFileSystemPath(None,f,0,False),None)
img=Q.CGImageSourceCreateImageAtIndex(src,0,None)
w,h=Q.CGImageGetWidth(img),Q.CGImageGetHeight(img); bpr=Q.CGImageGetBytesPerRow(img)
a=np.frombuffer(Q.CGDataProviderCopyData(Q.CGImageGetDataProvider(img)),dtype=np.uint8).reshape(h,bpr//4,4)[:,:w,:3]
dark=(a.max(axis=2)<40)
ys,xs=np.where(dark)
if len(xs)==0: print(f,"no dark px"); sys.exit()
x0,x1,y0,y1=xs.min(),xs.max(),ys.min(),ys.max()
# per-row width profile (first/last dark x) for a few rows to show corner radius
rows={y:(int(np.where(dark[y])[0].min()),int(np.where(dark[y])[0].max())) for y in range(y0,y1+1) if dark[y].any()}
print(f"{f}: dark bbox screen x={x0+ox}..{x1+ox} (w={x1-x0+1}) y={y0+oy}..{y1+oy} (h={y1-y0+1}) darkpx={len(xs)}")
for y in list(rows)[:4]+list(rows)[-4:]: print(f"   row y={y+oy}: x={rows[y][0]+ox}..{rows[y][1]+ox} w={rows[y][1]-rows[y][0]+1}")
