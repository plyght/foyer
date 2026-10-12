#!/usr/bin/env python
"""List every on/off-screen window owned by Alcove (or any owner matching argv[1]).
usage: winlist.py [owner-substring] [label]
Prints: label, wid, layer, bounds(x,y,w,h), alpha, sharingState, name, memory, isOnscreen, pid"""
import sys, time, Quartz as Q
owner = sys.argv[1] if len(sys.argv) > 1 else "Alcove"
label = sys.argv[2] if len(sys.argv) > 2 else ""
opts = Q.kCGWindowListOptionAll  # include offscreen windows
wl = Q.CGWindowListCopyWindowInfo(opts, Q.kCGNullWindowID)
onscreen = {w[Q.kCGWindowNumber] for w in Q.CGWindowListCopyWindowInfo(Q.kCGWindowListOptionOnScreenOnly, Q.kCGNullWindowID)}
rows = []
for w in wl:
    if owner.lower() not in str(w.get(Q.kCGWindowOwnerName, "")).lower():
        continue
    b = w[Q.kCGWindowBounds]
    rows.append(dict(
        wid=w[Q.kCGWindowNumber], layer=w[Q.kCGWindowLayer],
        x=b["X"], y=b["Y"], w=b["Width"], h=b["Height"],
        alpha=w.get(Q.kCGWindowAlpha), sharing=w.get(Q.kCGWindowSharingState),
        name=w.get(Q.kCGWindowName, ""), mem=w.get(Q.kCGWindowMemoryUsage),
        onscreen=w[Q.kCGWindowNumber] in onscreen, pid=w[Q.kCGWindowOwnerPID],
        store=w.get(Q.kCGWindowStoreType), backing=w.get(Q.kCGWindowBackingLocationVideoMemory)))
rows.sort(key=lambda r: r["wid"])
print(f"### {label} @ {time.strftime('%H:%M:%S')}  ({len(rows)} windows, owner~'{owner}')")
print("wid    layer  x       y      w      h      alpha sharing on  name")
for r in rows:
    print(f"{r['wid']:<6} {r['layer']:<6} {r['x']:<7.0f} {r['y']:<6.0f} {r['w']:<6.0f} {r['h']:<6.0f} {r['alpha']:<5} {r['sharing']:<7} {str(r['onscreen'])[0]:<3} {r['name']!r}")
