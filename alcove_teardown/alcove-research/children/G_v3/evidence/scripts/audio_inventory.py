import pathlib,subprocess,json,numpy as np,matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
root=pathlib.Path('/Users/devin/alcove-uncovered/ev')
dest=root/'sounds';dest.mkdir(exist_ok=True)
src=pathlib.Path('/Volumes/Alcove/Alcove.app/Contents/Resources')
out=[]
for p in sorted([*src.glob('*.caf'),*src.glob('*.m4a')]):
    probe=json.loads(subprocess.check_output(['ffprobe','-v','quiet','-show_format','-show_streams','-of','json',str(p)]))
    (dest/(p.name+'.json')).write_text(json.dumps(probe,indent=2))
    s=probe['streams'][0];sr=int(s['sample_rate']);ch=int(s['channels'])
    pcm=subprocess.check_output(['ffmpeg','-v','error','-i',str(p),'-f','f32le','-'])
    a=np.frombuffer(pcm,dtype='<f4').reshape(-1,ch)
    peak=float(np.max(np.abs(a)));rms=float(np.sqrt(np.mean(a.astype(float)**2)))
    row=dict(file=p.name,codec=s['codec_name'],container_duration=float(probe['format']['duration']),decoded_duration=len(a)/sr,sample_rate=sr,channels=ch,peak_dbfs=float(20*np.log10(peak)),rms_dbfs=float(20*np.log10(rms)),frames=len(a))
    out.append(row)
    fig,axs=plt.subplots(ch,1,figsize=(12,2*ch),squeeze=False)
    for n in range(ch):
        step=max(1,len(a)//12000);ax=axs[n,0]
        ax.plot(np.arange(0,len(a),step)/sr,a[::step,n],linewidth=.35)
        ax.set(xlabel='Seconds',ylabel='Amplitude',ylim=(-1,1),title=f'{p.name} · channel {n+1} · {sr} Hz')
        ax.grid(alpha=.2)
    fig.tight_layout();fig.savefig(dest/(p.stem+'.png'),dpi=120);plt.close(fig)
(dest/'inventory.json').write_text(json.dumps(out,indent=2))
for r in out:print(f"{r['file']:18} {r['decoded_duration']:.6f} {r['sample_rate']} {r['channels']} {r['peak_dbfs']:.2f} {r['rms_dbfs']:.2f}")
