import struct,json,pathlib
root=pathlib.Path('/Users/devin/alcove-uncovered');b=(root/'Alcove.arm64').read_bytes()
base=0x100000000
def u(p):return struct.unpack_from('<I',b,p)[0]
def rel(p):return p+struct.unpack_from('<i',b,p)[0]
def s(p):return b[p:b.find(b'\0',p)].decode(errors='replace')
sects={};p=32
for _ in range(u(16)):
    cmd,size=struct.unpack_from('<II',b,p)
    if cmd==0x19:
        for k in range(u(p+64)):
            q=p+72+80*k;name=b[q:q+16].split(b'\0')[0].decode();addr,n,off=struct.unpack_from('<QQI',b,q+32);sects[name]=(off,n)
    p+=size
out=[]
off,n=sects['__swift5_types']
for q in range(off,off+n,4):
    d=rel(q);kind=u(d)&31
    if kind not in (16,17,18):continue
    name=s(rel(d+8));access=rel(d+12);fd=rel(d+16);fields=[]
    if u(d+16):
        stride=struct.unpack_from('<H',b,fd+10)[0];count=u(fd+12)
        for i in range(min(count,200)):
            f=fd+16+i*stride;fields.append(s(rel(f+8)))
    out.append(dict(name=name,kind=kind,descriptor=hex(base+d),accessor=hex(base+access),fields=fields))
(root/'ev'/'swift_types.json').write_text(json.dumps(out,indent=2))
for t in out:
    if any(x in t['name'] for x in ['Vortex','Sound','Haptic','Game','Display','Screen','Update','Release','Onboarding','Welcome','Celebrat']):print(t)
