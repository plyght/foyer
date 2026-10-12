import struct, json, sys, re, collections
exec(open('swift_meta.py').read().split('# types list')[0])
def relind_sym(o):
    r=i32(o)
    if r&1:
        t=o+(r&~1); va=off2va(t)
        if va in relocs: return relocs[va]
        if va in rebases: return desc_name(va2off(rebases[va]))
        return '?ind'
    return 'req@'+hex(off2va(o+r))
a,s,o=sections[('__TEXT','__swift5_proto')]
confs=[]
for p in range(o,o+s,4):
    d=rel(p)
    proto=relind_sym(d)
    flags=u32(d+12); tk=(flags>>3)&7
    tr=i32(d+4); tname='?'
    if tk==0: tname=desc_name(d+4+tr)
    elif tk==1:
        va=off2va(d+4+tr)
        if va in rebases: tname=desc_name(va2off(rebases[va]))
        elif va in relocs: tname=relocs[va]
    elif tk==2: tname='objc:'+cstr(d+4+tr)
    wt=d+8+i32(d+8) if i32(d+8) else None
    q=d+16
    ncond=(flags>>8)&0xff; q+=12*ncond
    npack=(flags>>24)&0xff
    if npack: q+=4+4*npack  # header+shapes (approx)
    wits=[]
    if flags&(1<<16):
        try:
            n=u32(q); q+=4
            if n<64:
              for k in range(n):
                req=relind_sym(q); impl=off2va(rel(q+4)) if i32(q+4) else None
                wits.append((req,hex(impl) if impl else None)); q+=8
        except Exception as e: wits.append(('ERR',str(e)))
    confs.append(dict(va=hex(off2va(d)),type=tname,proto=proto,wt=hex(off2va(wt)) if wt else None,wits=wits))
json.dump(confs,open('conformances.json','w'),indent=0)
with open('conformances.txt','w') as w:
    for c in confs:
        w.write(f"{c['va']} {c['type']} : {c['proto']} wt={c['wt']}\n")
        for r,i in c['wits']: w.write(f"     {i}  {r}\n")
views=[]
for c in confs:
    if c['proto']=='_$s7SwiftUI4ViewMp':
        for r,i in c['wits']:
            if r and '4body' in r and i: views.append((int(i,16),c['type']))
views.sort(); json.dump([(hex(a),n) for a,n in views],open('view_bodies.json','w'),indent=0)
print(len(confs),'confs',len(views),'view bodies')
for a,n in views[:15]: print(hex(a),n)
