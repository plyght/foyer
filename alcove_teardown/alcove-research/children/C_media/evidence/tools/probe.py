import subprocess,numpy as np,sys,time
# prints current notch bbox from a live screen grab of the top-centre region
subprocess.run(['screencapture','-x','-R','500,0,600,120','/tmp/probe.png'],check=True)
raw=subprocess.run(['ffmpeg','-v','error','-i','/tmp/probe.png','-f','rawvideo','-pix_fmt','rgb24','-'],capture_output=True).stdout
a=np.frombuffer(raw,np.uint8).reshape(120,600,3)
dark=a.max(axis=2)<22
cols=np.where(dark[2])[0]
if len(cols)==0: print('nonotch'); sys.exit()
l,r=cols.min(),cols.max(); mid=(l+r)//2
hs=[np.where(dark[:,c])[0].max() for c in range(l+10,r-10,8) if dark[:,c].any()]
print(f'{time.time():.3f} width={r-l+1} left={l+500} height={max(hs)+1}')
