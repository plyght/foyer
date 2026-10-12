#!/usr/bin/env python3
import sys, csv, numpy as np
from datetime import datetime, timezone
tag = sys.argv[1]
F = np.genfromtxt(f'csv/{tag}_features.csv', delimiter=',', names=True)
G = [r for r in csv.DictReader(open(f'csv/{tag}.csv')) if r['idx'] not in ('marker','done') and r['swipe_t0']]
t0s = np.array([datetime.strptime(r['swipe_t0'],'%Y-%m-%dT%H:%M:%S.%fZ').replace(tzinfo=timezone.utc).timestamp() for r in G])
cn = F['cursor_notch'] > 3
onsets = np.where(cn[1:] & ~cn[:-1])[0] + 1
onsets = [o for i,o in enumerate(onsets) if i==0 or o - onsets[i-1] > 60]
onset_t = np.array(onsets)/60.0
# gesture-> onset matching: find offset so that most (t0 - t0[0] + off) match an onset
rel = t0s - t0s[0]
best=None
for off in np.arange(0, 12, 0.01):
    d = np.abs(onset_t[None,:] - (rel[:,None]+off)).min(axis=1)
    sc = (d < 0.08).sum()
    if best is None or sc > best[0]: best=(sc,off,d.mean())
print('sync: matched', best[0], 'of', len(G), 'offset', round(best[1],3), 'mean err', round(best[2],3), file=sys.stderr)
off = best[1]
rows=[]
for i,r in enumerate(G):
    exp = rel[i] + off
    j = np.argmin(np.abs(onset_t - exp)); on = onsets[j] if abs(onset_t[j]-exp) < 0.08 else int(round(exp*60))
    pre = slice(max(on-25,0), on-3); win = slice(on, on+135); post = slice(on+105, on+135)
    def st(s):
        red = np.median(F['red_right'][s]); br = np.median(F['bright_right'][s]); bl = np.median(F['bright_left'][s])
        if red > 15: return 'cal'
        if br > 15 or bl > 30: return 'np'
        return 'none'
    content = F['red_right'][win] + F['bright_right'][win] + F['bright_left'][win]
    # blank run: consecutive frames with content < 5
    blank = content < 5
    runs=[]; k=0
    while k < len(blank):
        if blank[k]:
            m=k
            while m < len(blank) and blank[m]: m+=1
            runs.append((k,m-k)); k=m
        else: k+=1
    longest = max(runs, key=lambda x:x[1]) if runs else (0,0)
    rows.append(dict(idx=r['idx'], dir=r['dir'], dist=int(r['dist']), rep=r['rep'], onset=on, pre=st(pre), post=st(post),
        blank_start=longest[0], blank_len=longest[1], max_bl=int(F['bright_left'][win].max()), max_br=int(F['bright_right'][win].max()),
        max_exp=int(F['expanded_dark'][win].max()), pre_exp=int(F['expanded_dark'][pre].max()), max_red=int(F['red_right'][win].max()), max_mid=int(F['mid_dark'][win].max())))
w = csv.DictWriter(open(f'csv/{tag}_gestures.csv','w'), fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
for r in rows: print(','.join(str(v) for v in r.values()))
