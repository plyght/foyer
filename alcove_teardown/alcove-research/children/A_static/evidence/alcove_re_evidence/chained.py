import struct, json, sys
f=open(sys.argv[1],'rb').read()
ncmds=struct.unpack('<I',f[16:20])[0]; off=32
segs=[]; fix=None
for i in range(ncmds):
    cmd,size=struct.unpack('<II',f[off:off+8])
    if cmd==0x19:
        segname=f[off+8:off+24].rstrip(b'\0').decode()
        vmaddr,vmsize,fileoff,filesize=struct.unpack('<QQQQ',f[off+24:off+56]); segs.append((segname,vmaddr,vmsize,fileoff,filesize))
    if cmd==0x80000034:
        fix=struct.unpack('<II',f[off+8:off+16])
    off+=size
base=[s for s in segs if s[0]=='__TEXT'][0][1]
dataoff,datasize=fix
h=f[dataoff:dataoff+datasize]
ver,starts_off,imports_off,symbols_off,imports_count,imports_format,symbols_format=struct.unpack('<7I',h[:28])
imports=[]
for i in range(imports_count):
    if imports_format==1:
        v=struct.unpack('<I',h[imports_off+4*i:imports_off+4*i+4])[0]; lib=v&0xff; weak=(v>>8)&1; name_off=v>>9; addend=0
    elif imports_format==2:
        v,addend=struct.unpack('<Iq',h[imports_off+12*i:imports_off+12*i+12]); lib=v&0xff; weak=(v>>8)&1; name_off=v>>9
    else:
        lo,hi,addend=struct.unpack('<IIq',h[imports_off+16*i:imports_off+16*i+16]); lib=lo&0xffff; weak=(lo>>16)&1; name_off=lo>>17 | (hi<<15)  # 64-bit variant approx
    s=symbols_off+name_off; e=h.index(b'\0',s); imports.append((h[s:e].decode('latin1'),lib,addend))
seg_count=struct.unpack('<I',h[starts_off:starts_off+4])[0]
got={}; rebases={}
for si in range(seg_count):
    so=struct.unpack('<I',h[starts_off+4+4*si:starts_off+8+4*si])[0]
    if so==0: continue
    p=starts_off+so
    size,page_size,pfmt=struct.unpack('<IHH',h[p:p+8]); seg_offset,max_valid,page_count=struct.unpack('<QIH',h[p+8:p+22])
    for pi in range(page_count):
        ps=struct.unpack('<H',h[p+22+2*pi:p+24+2*pi])[0]
        if ps==0xffff: continue
        addr=seg_offset+pi*page_size+ps  # file offset (segment_offset is from mach header)
        while True:
            v=struct.unpack('<Q',f[addr:addr+8])[0]
            bind=v>>63; nxt=(v>>51)&0xfff
            va=base+addr  # file offset == vm offset for these segs (no PAGEZERO offset diff) -> compute properly
            # find segment for file offset
            for sn,vma,vms,fo,fs in segs:
                if fo<=addr<fo+fs: va=vma+(addr-fo); break
            if bind:
                ordinal=v&0xffffff; addend=(v>>24)&0xff
                if ordinal<len(imports): got[va]=imports[ordinal][0]
            else:
                if pfmt in (2,):  # DYLD_CHAINED_PTR_64
                    target=v&0xfffffffff; high8=(v>>36)&0xff; rebases[va]=target|(high8<<56)
                elif pfmt==6: # 64_OFFSET
                    target=v&0xfffffffff; rebases[va]=base+target
            if nxt==0: break
            addr+=nxt*4
print('pfmt',pfmt,'imports',len(imports),'binds',len(got),'rebases',len(rebases), file=sys.stderr)
json.dump({'binds':{hex(k):v for k,v in got.items()},'rebases':{hex(k):hex(v) for k,v in rebases.items()}},open(sys.argv[2],'w'))
