import subprocess, numpy as np, sys
clip=sys.argv[1]; x0,x1,y0,y1=[int(v) for v in sys.argv[2:6]]
w,h=x1-x0,y1-y0
p=subprocess.Popen(['ffmpeg','-v','error','-i',clip,'-vf',f'crop={w}:{h}:{x0}:{y0}','-f','rawvideo','-pix_fmt','gray','-'],stdout=subprocess.PIPE)
fr=[]
while True:
    b=p.stdout.read(w*h)
    if len(b)<w*h: break
    fr.append(np.frombuffer(b,np.uint8).reshape(h,w))
A=np.array(fr); bright=A>70
colany=bright.any(axis=(0,1))
cols=np.where(colany)[0]
groups=[];cur=[cols[0]]
for c in cols[1:]:
    if c-cur[-1]<=1: cur.append(c)
    else: groups.append(cur);cur=[c]
groups.append(cur)
print('bar column groups (clip x):',[(g[0]+x0,g[-1]+x0) for g in groups])
H=np.array([[bright[i][:,g].any(axis=1).sum() for g in groups] for i in range(len(A))])
np.savetxt('bars_heights.csv',H,fmt='%d',delimiter=',',header=','.join(f'bar{i}' for i in range(len(groups))))
act=np.where(H.max(axis=1)>H.min())[0]
print('frames',len(A),'active frames',act.min() if len(act) else None,act.max() if len(act) else None)
for j in range(len(groups)):
    pk=H[:,j].argmax(); print(f'bar{j}: min {H[:,j].min()} max {H[:,j].max()} peak_frame {pk} t={pk/60:.2f}s')
ch=np.where((np.diff(H,axis=0)!=0).any(axis=1))[0]+1
d=np.diff(ch); print('frames between changes: median',np.median(d) if len(d) else None,'hist',np.bincount(d)[:10] if len(d) else None)
