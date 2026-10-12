import struct,sys
# dump __objc_selrefs -> selector names for a thin arm64 Mach-O (chained fixups: low 32 bits = vm offset)
p=sys.argv[1]; d=open(p,'rb').read()
magic,cputype,cpusub,ft,ncmds,sz,flags,res=struct.unpack_from('<IiiIIIII',d,0)
off=32; secs={}
for _ in range(ncmds):
    cmd,csz=struct.unpack_from('<II',d,off)
    if cmd in (0x19,):
        segname=d[off+8:off+24].rstrip(b'\0').decode()
        vmaddr,vmsize,fileoff,filesize=struct.unpack_from('<QQQQ',d,off+24)
        nsects=struct.unpack_from('<I',d,off+64)[0]
        so=off+72
        for i in range(nsects):
            sn=d[so:so+16].rstrip(b'\0').decode(); sg=d[so+16:so+32].rstrip(b'\0').decode()
            addr,size,foff=struct.unpack_from('<QQI',d,so+32)
            secs[(sg,sn)]=(addr,size,foff); so+=80
    off+=csz
def vm2off(a):
    for (sg,sn),(addr,size,foff) in secs.items():
        if addr<=a<addr+size: return foff+(a-addr)
    return None
addr,size,foff=[v for k,v in secs.items() if k[1]=='__objc_selrefs'][0]
for i in range(0,size,8):
    v=struct.unpack_from('<Q',d,foff+i)[0]
    tgt=0x100000000+(v&0xffffffff)
    o=vm2off(tgt)
    if o is None: continue
    e=d.index(b'\0',o)
    print(f"0x{addr+i:x} 0x{tgt:x} {d[o:e].decode(errors='replace')}")
