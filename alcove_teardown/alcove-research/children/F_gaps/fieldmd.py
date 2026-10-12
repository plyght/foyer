#!/usr/bin/env python3
# Dump Swift 5 field descriptors (type name, kind, fields: name + mangled type) from an arm64 Mach-O.
import sys, struct, subprocess, re
path = sys.argv[1]
data = open(path,'rb').read()
# parse sections
def sections():
    off=0
    magic,cputype,cpusub,ft,ncmds,sizeofcmds,flags,res=struct.unpack_from('<IiiIIIII',data,0)
    off=32; secs={}
    for _ in range(ncmds):
        cmd,size=struct.unpack_from('<II',data,off)
        if cmd==0x19:
            segname=data[off+8:off+24].rstrip(b'\0').decode()
            nsects=struct.unpack_from('<I',data,off+64)[0]
            so=off+72
            for i in range(nsects):
                sn=data[so:so+16].rstrip(b'\0').decode(); sg=data[so+16:so+32].rstrip(b'\0').decode()
                addr,sz,fo=struct.unpack_from('<QQI',data,so+32)
                secs[(sg,sn)]=(addr,sz,fo)
                so+=80
        off+=size
    return secs
secs=sections()
segs={}
def va2off(va):
    for (sg,sn),(addr,sz,fo) in secs.items():
        if addr<=va<addr+sz: return fo+(va-addr)
    return None
def off2va(o):
    for (sg,sn),(addr,sz,fo) in secs.items():
        if fo<=o<fo+sz: return addr+(o-fo)
    return None
def cstr(o):
    e=data.index(b'\0',o); return data[o:e]
def rel(o):
    v=struct.unpack_from('<i',data,o)[0]; return o+v
def symname(mangled):
    return mangled

def ctx_name(desc_off):
    # context descriptor: flags, parent, name(rel)
    try:
        nm=rel(desc_off+8)
        parent=struct.unpack_from('<i',data,desc_off+4)[0]
        n=cstr(nm).decode('utf-8','replace')
        if parent:
            p=rel(desc_off+4)
            pf=struct.unpack_from('<I',data,p)[0]
            if (pf&0x1f)==0: # module
                n=cstr(rel(p+8)).decode('utf-8','replace')+'.'+n
            elif (pf&0x1f) in (16,17,18,19): # nominal type kinds 16..19 (class 16, struct 17, enum 18)
                n=ctx_name(p)+'.'+n
        return n
    except Exception as e:
        return '?'
def demangle_bytes(o):
    # read a mangled-name blob with symbolic refs, returning readable string
    out=b''; i=o
    while True:
        c=data[i]
        if c==0: break
        if 1<=c<=0x17:
            off=struct.unpack_from('<i',data,i+1)[0]
            tgt=i+1+off
            if c==1:
                out+=('{'+ctx_name(tgt)+'}').encode()
            elif c==2:
                # indirect: pointer at tgt (chained fixup -> treat low 32 bits as vmaddr offset?)
                ptr=struct.unpack_from('<Q',data,tgt)[0]
                tva=ptr&0xffffffffff
                toff=va2off(tva) if tva>0x100000000 else va2off(0x100000000+tva)
                if toff: out+=('{'+ctx_name(toff)+'}').encode()
                else: out+=b'{ind}'
            else:
                out+=b'{sym%d}'%c
            i+=5
        elif 0x18<=c<=0x1f:
            out+=b'{abs}'; i+=9
        else:
            out+=bytes([c]); i+=1
    return out.decode('utf-8','replace')

addr,sz,fo=secs[('__TEXT','__swift5_fieldmd')]
o=fo; end=fo+sz
kinds={0:'struct',1:'class',2:'enum',3:'multi-payload enum',4:'protocol',5:'class protocol',6:'objc protocol',7:'objc class'}
out=[]
while o<end:
    mtn=struct.unpack_from('<i',data,o)[0]
    sup=struct.unpack_from('<i',data,o+4)[0]
    kind,frs,nf=struct.unpack_from('<HHI',data,o+8)
    name=demangle_bytes(o+mtn) if mtn else ''
    supn=demangle_bytes(o+4+sup) if sup else ''
    fields=[]
    fo_=o+16
    for i in range(nf):
        flags=struct.unpack_from('<I',data,fo_)[0]
        mt=struct.unpack_from('<i',data,fo_+4)[0]
        fn=struct.unpack_from('<i',data,fo_+8)[0]
        mts=demangle_bytes(fo_+4+mt) if mt else ''
        fns=cstr(fo_+8+fn).decode('utf-8','replace') if fn else ''
        clean=mts
        fields.append((flags,fns,clean))
        fo_+=frs
    out.append((hex(off2va(o) or 0),name,kinds.get(kind,str(kind)),supn,fields))
    o=fo_
for va,name,kind,supn,fields in out:
    print(f"== {va} {kind} {name}" + (f" : {supn}" if supn else ""))
    for flags,fn,mt in fields:
        print(f"   {'var' if flags&2 else 'let' if not flags&1 else 'case'} {fn} : {mt}")
