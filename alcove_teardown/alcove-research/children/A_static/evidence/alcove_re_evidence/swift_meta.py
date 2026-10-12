import struct, json, sys, re
f=open(sys.argv[1],'rb').read()
magic,cputype,cpusub,ft,ncmds,sizeofcmds,flags,res=struct.unpack('<IiiIIIII',f[:32])
off=32; sections={}
for i in range(ncmds):
    cmd,size=struct.unpack('<II',f[off:off+8])
    if cmd==0x19:
        nsects=struct.unpack('<I',f[off+64:off+68])[0]; so=off+72
        for j in range(nsects):
            sn=f[so:so+16].rstrip(b'\0').decode(); sg=f[so+16:so+32].rstrip(b'\0').decode()
            addr,sz,offs=struct.unpack('<QQI',f[so+32:so+52]); sections[(sg,sn)]=(addr,sz,offs); so+=80
    off+=size
def off2va(o):
    for (sg,sn),(a,s,oo) in sections.items():
        if oo<=o<oo+s: return a+(o-oo)
def rel(o):
    r=struct.unpack('<i',f[o:o+4])[0]; return o+r
def relind(o):
    r=struct.unpack('<i',f[o:o+4])[0]
    if r&1:
        t=o+(r&~1)
        p=struct.unpack('<Q',f[t:t+8])[0]
        for cand in (p, p&0xffffffffff, (p&0xffffffff)+0x100000000, (p&0xfffffffff)+0x100000000):
            fo=va2off(cand)
            if fo is not None: return fo
        return None
    return o+r
def i32(o): return struct.unpack('<i',f[o:o+4])[0]
def u32(o): return struct.unpack('<I',f[o:o+4])[0]
def cstr(o):
    e=f.index(b'\0',o); return f[o:e].decode('latin1')
KINDS={0:'module',1:'extension',2:'anonymous',3:'protocol',4:'opaque',16:'class',17:'struct',18:'enum'}
def desc_name(d, depth=0):
    """context descriptor at file offset d -> qualified name"""
    if d is None or depth>8: return '?'
    flags=u32(d); kind=flags&0x1f
    parent=relind(d+4) if i32(d+4) else None
    if kind in (16,17,18,3,0):
        try: name=cstr(rel(d+8))
        except Exception: name='?'
        if len(name)>120: name='?'

    elif kind==1:
        name='ext(%s)'%mangled(rel(d+8))
    elif kind==2:
        name='anon'
    else:
        name='k%d'%kind
    if parent is not None and kind!=0:
        return desc_name(parent,depth+1)+'.'+name
    return name
def mangled(o):
    out=''; i=o
    while f[i]!=0:
        b=f[i]
        if b==1:
            out+='{%s}'%desc_name(rel(i+1)); i+=5
        elif b==2:
            tgt=rel(i+1); 
            # indirect: pointer to descriptor (in __DATA/__got). try resolve
            va=off2va(tgt)
            if va in relocs: out+='{%s}'%relocs[va]
            elif va in rebases:
                fo=va2off(rebases[va]); out+='{%s}'%(desc_name(fo) if fo else hex(rebases[va]))
            else:
                try:
                    p=struct.unpack('<Q',f[tgt:tgt+8])[0]
                    fo=None
                    for cand in (p, p&0xffffffffff, (p&0xffffffff)+0x100000000):
                        fo=va2off(cand)
                        if fo: break
                    out+='{*%s}'%(desc_name(fo) if fo else hex(p))
                except Exception: out+='{*?}'
            i+=5
        elif 3<=b<=0x17: out+='<SYM%02x>'%b; i+=5
        elif 0x18<=b<=0x1f: out+='<SYM%02x>'%b; i+=9
        else: out+=chr(b); i+=1
    return out
def va2off(va):
    for (sg,sn),(a,s,o) in sections.items():
        if a<=va<a+s: return va-a+o
_fx=json.load(open('fixups.json'))
relocs={int(k,16):v for k,v in _fx['binds'].items()}
rebases={int(k,16):int(v,16) for k,v in _fx['rebases'].items()}
import subprocess
def demangle(n):
    return n
# types list
a,s,o=sections[('__TEXT','__swift5_types')]
types={}
for p in range(o,o+s,4):
    d=rel(p); types[d]=desc_name(d)
# fieldmd
a,s,o=sections[('__TEXT','__swift5_fieldmd')]
end=o+s; p=o; out=[]
FK={0:'struct',1:'class',2:'enum',3:'multipayload enum',4:'protocol',5:'classprotocol',6:'objcprotocol',7:'objcclass'}
while p<end:
    mtn=rel(p) if i32(p) else None; sup=rel(p+4) if i32(p+4) else None
    kind,recsize=struct.unpack('<HH',f[p+8:p+12]); nf=u32(p+12)
    tn=mangled(mtn) if mtn else ''; sn=mangled(sup) if sup else ''
    fields=[]; q=p+16
    for k in range(nf):
        fl=u32(q); ftn=rel(q+4) if i32(q+4) else None; fnm=rel(q+8) if i32(q+8) else None
        fields.append(dict(flags=fl,type=mangled(ftn) if ftn else '',name=cstr(fnm) if fnm else ''))
        q+=recsize
    out.append(dict(va=hex(off2va(p)),kind=FK.get(kind,kind),name=tn,super=sn,fields=fields)); p=q
json.dump(out,open('fieldmd.json','w'),indent=1)
with open('fieldmd_dump.txt','w') as w:
    for t in out:
        w.write(f"## {t['name']} [{t['kind']}] super={t['super']} @{t['va']}\n")
        for fd in t['fields']:
            kw = 'case' if 'enum' in t['kind'] else ('var' if fd['flags']&2 else 'let')
            w.write(f"   {kw} {fd['name']}: {fd['type']}\n")
with open('types_list.txt','w') as w:
    for d,n in sorted(types.items(), key=lambda x:x[1]): w.write(f"{hex(off2va(d))} {n}\n")
print(len(out),'field descriptors;',len(types),'types')
