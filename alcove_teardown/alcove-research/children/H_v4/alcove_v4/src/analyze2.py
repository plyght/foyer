#!/usr/bin/env python3
"""analyze2.py <tag> [features_csv]: classify each gesture window using features2 columns."""
import sys, csv, numpy as np
from datetime import datetime, timezone
tag=sys.argv[1]; fcsv=sys.argv[2] if len(sys.argv)>2 else f'csv/{tag}_features.csv'
F=np.genfromtxt(fcsv,delimiter=',',names=True)
G=[r for r in csv.DictReader(open(f'csv/{tag}.csv')) if r['idx'] not in ('marker','done') and r.get('swipe_t0')]
t0s=np.array([datetime.strptime(r['swipe_t0'],'%Y-%m-%dT%H:%M:%S.%fZ').replace(tzinfo=timezone.utc).timestamp() for r in G])
cn=F['cursor_notch']>3
onsets=np.where(cn[1:]&~cn[:-1])[0]+1
onsets=[o for i,o in enumerate(onsets) if i==0 or o-onsets[i-1]>60]
onset_t=np.array(onsets)/60.0; rel=t0s-t0s[0]
best=None
for off in np.arange(0,15,0.01):
    d=np.abs(onset_t[None,:]-(rel[:,None]+off)).min(axis=1); sc=(d<0.08).sum()
    if best is None or sc>best[0]: best=(sc,off,d.mean())
print('sync matched',best[0],'of',len(G),'offset',round(best[1],3),file=sys.stderr); off=best[1]
def state(s):
    red=np.median(F['red'][s]); wave=np.median(F['wave'][s]); art=np.median(F['art'][s]); bb=np.median(F['black_below'][s]); w=np.median(F['nr'][s]-F['nl'][s])
    if bb>8000: return 'expanded'
    if red>3: return 'cal'
    if wave>2 or art>8: return 'np'
    return 'empty'
rows=[]
for i,r in enumerate(G):
    exp=rel[i]+off; j=np.argmin(np.abs(onset_t-exp)); on=onsets[j] if abs(onset_t[j]-exp)<0.08 else int(round(exp*60))
    pre=slice(on-20,on-3); post=slice(on+95,on+118); win=slice(on,on+118)
    gl=F['glyphL'][win].max(); gr=F['glyphR'][win].max(); bbmax=F['black_below'][win].max()
    content=F['red'][win]+F['wave'][win]+F['art'][win]
    blank=content<2; k=0; runs=[]
    while k<len(blank):
        if blank[k]:
            m=k
            while m<len(blank) and blank[m]: m+=1
            runs.append((k,m-k)); k=m
        else: k+=1
    longest=max(runs,key=lambda x:x[1]) if runs else (-1,0)
    # first frame where state differs from pre-state content signature
    pre_red=np.median(F['red'][pre]); pre_wave=np.median(F['wave'][pre])
    ch=np.where((np.abs(F['red'][win]-pre_red)>4)|(np.abs(F['wave'][win]-pre_wave)>4)|(F['black_below'][win]>8000)|(F['glyphL'][win]>5)|(F['glyphR'][win]>5))[0]
    first_change=int(ch[0]) if len(ch) else -1
    rows.append(dict(idx=r['idx'],phase=r.get('phase',r.get('state')),dir=r['dir'],dist=int(r['dist']),rep=r['rep'],rev=r['reverseAt'],onset=on,pre=state(pre),post=state(post),first_change=first_change,blank_start=longest[0],blank_len=longest[1],glyphL=int(gl),glyphR=int(gr),expanded_max=int(bbmax),width_pre=int(np.median(F['nr'][pre]-F['nl'][pre]))))
w=csv.DictWriter(open(f'csv/{tag}_gestures2.csv','w'),fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
for r in rows: print(','.join(str(v) for v in r.values()))
