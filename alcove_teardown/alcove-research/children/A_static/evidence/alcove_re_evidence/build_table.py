import json,re,bisect
vb=[(int(a,16),n) for a,n in json.load(open('view_bodies.json'))]; vaddrs=[a for a,_ in vb]
ctx=json.load(open('fn_ctx.json'))
def context(fn):
    a=int(fn.split('.')[-1],16)
    c=[x for x in ctx.get(fn,[]) if not x.startswith('s:')]
    i=bisect.bisect_right(vaddrs,a)-1
    near=vb[i][1] if i>=0 else '?'
    near=near.replace('Alcove.','')
    return (', '.join(c[:3])+' | ' if c else '')+'near '+near+'.body'
rows=[]
s1={o['addr']:o for o in json.load(open('spring_consts.json'))}
for o in json.load(open('spring_consts2.json')):
    if o['addr'] in s1:
        for k in ('d0','d1','d2'):
            if s1[o['addr']][k] in (None,'?','?call') and o[k] not in (None,'?','?call'): s1[o['addr']][k]=o[k]
def fmt(v): return '?' if v is None or (isinstance(v,str) and v.startswith('?')) else (('%g'%v) if isinstance(v,float) else str(v))
for o in s1.values():
    call=o['call']
    if 'response.dampingFraction' in call: api='Animation.spring(response:dampingFraction:blendDuration:)'; p=f"response={fmt(o['d0'])} damping={fmt(o['d1'])} blend={fmt(o['d2'])}"
    elif 'Spring.duration.bounce' in call: api='Spring(duration:bounce:)'; p=f"duration={fmt(o['d0'])} bounce={fmt(o['d1'])}"
    elif 'spring.blendDuration.Spring' in call: api='Animation.spring(_:blendDuration:)'; p=f"blend={fmt(o['d0'])}"
    else: api=call; p=f"{fmt(o['d0'])},{fmt(o['d1'])},{fmt(o['d2'])}"
    rows.append((o['addr'],o['fn'],api,p))
for o in json.load(open('other_consts.json')):
    t=o['tag']
    if t in ('withAnimation','Transaction.animation','Binding.animation','PhaseAnimator','TimelineView','contentTransition','default','AudioHardwareCreateAggregateDevice','CGSSpaceCreate___SetAbsoluteLevel___Shielding'): continue
    api={'easeInOut':'Animation.easeInOut(duration:)','easeIn':'Animation.easeIn(duration:)','easeOut':'Animation.easeOut(duration:)','linear':'Animation.linear(duration:)','delay':'Animation.delay(_:)','repeatForever':'Animation.repeatForever(autoreverses:)','Clock.sleep':'Task.sleep(for:) via Clock.sleep(until:tolerance:)','AnimationTimelineSchedule':'AnimationTimelineSchedule(minimumInterval:paused:)'}.get(t,t)
    rows.append((o['addr'],o['fn'],api,f"d0={fmt(o['d0'])}" + (f" d1={fmt(o['d1'])}" if o['d1'] not in (None,) else '')))
for o in json.load(open('dur_consts.json')):
    rows.append((o['addr'],o['fn'],'Duration.seconds(_:)',f"seconds={fmt(o['d0'])}"))
rows.sort(key=lambda r:int(r[0],16))
with open('anim_table.md','w') as w:
    w.write('| address | enclosing fn | API | parameters | context (STATIC fieldmd xrefs | INFERRED nearest View.body) |\n|---|---|---|---|---|\n')
    for a,fn,api,p in rows: w.write(f'| {a} | {fn} | {api} | {p} | {context(fn)} |\n')
print(len(rows))
