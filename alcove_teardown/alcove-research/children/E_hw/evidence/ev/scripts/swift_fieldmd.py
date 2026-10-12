# Dump Swift field descriptors (__swift5_fieldmd) from an arm64 Mach-O: type name -> [(field name, mangled type)]
import sys, struct
path=sys.argv[1]
data=open(path,'rb').read()
magic,cputype,cpusub,filetype,ncmds,sizeofcmds,flags,res=struct.unpack_from('<IiiIIIII',data,0)
off=32; segs={}; sects={}
for _ in range(ncmds):
    cmd,size=struct.unpack_from('<II',data,off)
    if cmd==0x19:
        segname=data[off+8:off+24].rstrip(b'\0').decode()
        vmaddr,vmsize,fileoff,filesize=struct.unpack_from('<QQQQ',data,off+24)
        nsects=struct.unpack_from('<I',data,off+64)[0]
        segs[segname]=(vmaddr,fileoff,filesize)
        so=off+72
        for _ in range(nsects):
            sn=data[so:so+16].rstrip(b'\0').decode(); sg=data[so+16:so+32].rstrip(b'\0').decode()
            addr,sz,foff=struct.unpack_from('<QQI',data,so+32)
            sects[(sg,sn)]=(addr,sz,foff); so+=80
    off+=size
def va2off(va):
    for name,(vmaddr,fileoff,filesize) in segs.items():
        if vmaddr<=va<vmaddr+filesize: return va-vmaddr+fileoff
    return None
def cstr(off):
    e=data.index(b'\0',off); return data[off:e].decode('utf-8','replace')
def rel32(off):
    return struct.unpack_from('<i',data,off)[0]
def ctx_name(cva):
    # nominal type context descriptor: flags@0, parent@4, name@8 (relative), ...
    o=va2off(cva)
    if o is None: return '?ctx'
    name_rel=rel32(o+8)
    nm=cstr(va2off(cva+8+name_rel)) if name_rel else '?'
    par_rel=rel32(o+4)
    parts=[nm]
    while par_rel:
        pva=cva+4+par_rel; po=va2off(pva)
        if po is None: break
        flags=struct.unpack_from('<I',data,po)[0]
        kind=flags&0x1f
        nr=rel32(po+8) if kind in (0,16,17,18) and kind!=0 or kind==0 else 0
        if kind==0:  # module
            pr=rel32(po+8); parts.append(cstr(va2off(pva+8+pr))); break
        if kind in (16,17,18):
            pr=rel32(po+8); parts.append(cstr(va2off(pva+8+pr)))
            cva=pva; par_rel=rel32(po+4); continue
        parts.append('<anon>'); cva=pva; par_rel=rel32(po+4)
    return '.'.join(reversed(parts))
def symname(nva):
    o=va2off(nva)
    if o is None: return '?'
    b=data[o]
    if b==1:
        return ctx_name(nva+1+rel32(o+1))
    if b==2:
        ptr=struct.unpack_from('<Q',data,va2off(nva+1+rel32(o+1)))[0] & 0xffffffffff
        return ctx_name(ptr)
    return cstr(o)
addr,sz,foff=sects[('__TEXT','__swift5_fieldmd')]
p=foff; end=foff+sz; out={}
while p<end:
    mangled_rel,super_rel=struct.unpack_from('<ii',data,p)
    kind,frs,nf=struct.unpack_from('<HHI',data,p+8)
    va=addr+(p-foff)
    tn=symname(va+mangled_rel) if mangled_rel else '?'
    fields=[]
    fp=p+16
    for i in range(nf):
        flags,tr,nr=struct.unpack_from('<Iii',data,fp)
        fva=addr+(fp-foff)
        ty=cstr(va2off(fva+4+tr)) if tr else ''
        nm=cstr(va2off(fva+8+nr)) if nr else ''
        fields.append((nm,ty,flags))
        fp+=frs
    out.setdefault(tn,[]).append((hex(va),kind,fields))
    p=fp
import json
for tn,descs in out.items():
    for va,kind,fields in descs:
        print(f"== {tn} @{va} kind={kind}")
        for nm,ty,fl in fields:
            print(f"   {nm} : {ty}  (flags={fl})")
