import subprocess, numpy as np, sys
clip=sys.argv[1]; x0,x1,y0,y1=876,904,3,27
w,h=x1-x0,y1-y0
p=subprocess.Popen(['ffmpeg','-v','error','-i',clip,'-vf',f'crop={w}:{h}:{x0}:{y0}','-f','rawvideo','-pix_fmt','gray','-'],stdout=subprocess.PIPE)
fr=[]
while True:
    b=p.stdout.read(w*h)
    if len(b)<w*h: break
    fr.append(np.frombuffer(b,np.uint8).reshape(h,w).astype(int))
A=np.array(fr)[:int(sys.argv[3])] if len(sys.argv)>3 else np.array(fr)
colsum=A.sum(axis=1)            # frames x cols : brightness mass per column
prof=colsum.max(axis=0)
print('col max-mass profile:',' '.join(f'{x0+i}:{v}' for i,v in enumerate(prof)))
pk=[i for i in range(1,w-1) if prof[i]>=prof[i-1] and prof[i]>prof[i+1] and prof[i]>prof.max()*0.25]
print('peak cols',[x0+i for i in pk])
H=(A[:,:,pk]>60).sum(axis=1)
np.savetxt(sys.argv[2],H,fmt='%d',delimiter=',',header=','.join(f'bar{j}' for j in range(len(pk))))
for j in range(len(pk)):
    print(f'bar{j} x={x0+pk[j]} min {H[:,j].min()} max {H[:,j].max()} peak t={H[:,j].argmax()/60:.2f}s')
ch=np.where((np.diff(H,axis=0)!=0).any(axis=1))[0]+1
d=np.diff(ch); print('frames between changes hist',np.bincount(d)[:12].tolist(),'median',np.median(d))
