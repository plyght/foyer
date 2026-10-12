#!/usr/bin/env python
"""Sample Alcove windows at ~20 Hz for N seconds; print a line whenever the set of
(wid, layer, bounds, alpha, sharing, onscreen) changes.  usage: winsample.py seconds label"""
import sys, time, Quartz as Q
secs=float(sys.argv[1]); label=sys.argv[2] if len(sys.argv)>2 else ""
def snap():
    on={w[Q.kCGWindowNumber] for w in Q.CGWindowListCopyWindowInfo(Q.kCGWindowListOptionOnScreenOnly,Q.kCGNullWindowID)}
    rows=[]
    for w in Q.CGWindowListCopyWindowInfo(Q.kCGWindowListOptionAll,Q.kCGNullWindowID):
        if "alcove" not in str(w.get(Q.kCGWindowOwnerName,"")).lower(): continue
        b=w[Q.kCGWindowBounds]
        rows.append((w[Q.kCGWindowNumber],w[Q.kCGWindowLayer],int(b["X"]),int(b["Y"]),int(b["Width"]),int(b["Height"]),w.get(Q.kCGWindowAlpha),w.get(Q.kCGWindowSharingState),w[Q.kCGWindowNumber] in on,w.get(Q.kCGWindowName,"")))
    return tuple(sorted(rows))
t0=time.time(); last=None
print(f"### sample {label} start {time.strftime('%H:%M:%S')}")
while time.time()-t0<secs:
    s=snap()
    if s!=last:
        print(f"t={time.time()-t0:6.3f}s n={len(s)}")
        for r in s: print("   wid=%d layer=%d xywh=(%d,%d,%d,%d) alpha=%s sharing=%s on=%s name=%r"%r)
        last=s
    time.sleep(0.05)
