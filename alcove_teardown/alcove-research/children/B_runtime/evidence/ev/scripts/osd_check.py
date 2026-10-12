import Quartz as Q,sys,time
# list on-screen windows of OSDUIHelper (system volume/brightness bezel) and Alcove
for w in Q.CGWindowListCopyWindowInfo(Q.kCGWindowListOptionOnScreenOnly,Q.kCGNullWindowID):
    o=str(w.get(Q.kCGWindowOwnerName,""))
    if o in ("OSDUIHelper","Alcove","BezelUIServer"):
        b=w[Q.kCGWindowBounds]; print(time.strftime('%H:%M:%S'),o,w[Q.kCGWindowNumber],w[Q.kCGWindowLayer],int(b["X"]),int(b["Y"]),int(b["Width"]),int(b["Height"]),w.get(Q.kCGWindowAlpha))
