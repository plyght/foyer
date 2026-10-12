import r2pipe,re,struct,sys
data=open('bin/Alcove.arm64','rb').read()
segs=[(0x100000000,0,0x448000),(0x100588000,5799936,0x30000),(0x1005b8000,5996544,0x40000)]
# better: parse LCs
import subprocess
out=subprocess.check_output(['otool','-l','bin/Alcove.arm64']).decode()
segs=[]
cur={}
for l in out.splitlines():
    l=l.strip()
    if l.startswith('segname '): cur={'n':l.split()[1]}
    elif l.startswith('vmaddr ') and 'n' in cur: cur['va']=int(l.split()[1],16)
    elif l.startswith('vmsize ') and 'n' in cur: cur['sz']=int(l.split()[1],16)
    elif l.startswith('fileoff ') and 'n' in cur:
        cur['fo']=int(l.split()[1]); segs.append((cur['va'],cur['fo'],cur['sz'])); cur={}
def va2off(va):
    for s,o,sz in segs:
        if s<=va<s+sz: return o+va-s
    raise ValueError(hex(va))
M=(1<<64)-1
def decode(arr_va,key):
    off=va2off(arr_va)
    count=struct.unpack_from('<Q',data,off+0x10)[0]
    b=data[off+0x20:off+0x20+count]
    s=key if key else 0x6a09e667f3bcc909
    o=bytearray()
    for c in b:
        s=(s*0x5851f42d4c957f2d+0x14057b7ef767814f)&M
        s^=s>>33; s=(s*0xff51afd7ed558ccd)&M; s^=s>>29
        o.append(c^((s>>24)&0xff))
    return bytes(o)
r2=r2pipe.open('bin/Alcove.arm64',flags=['-e','bin.cache=true','-2'])
calls=[]
for line in open('ev/deobf_xrefs.txt'):
    m=re.search(r'(sym\.\S+|fcn\.\S+)?\s*(0x[0-9a-f]+) \[CALL',line)
    if m: calls.append((m.group(1),int(m.group(2),16)))
print(len(calls),'call sites',file=sys.stderr)
res=[]
for fn,ca in calls:
    dis=r2.cmd('pd -14 @ 0x%x'%ca)
    x0=None; key=0; regs={}
    page=None
    for l in dis.splitlines():
        mm=re.search(r'\s(adrp|add|mov|movk|movz)\s+(x\d+|w\d+),\s*(.*)$',l)
        if not mm: continue
        op,rd,rest=mm.groups()
        rest=rest.split(';')[0].strip()
        if op=='adrp':
            hx=re.findall(r'0x[0-9a-f]+',l)
            regs[rd]=int(hx[-1],16) if hx else 0
        elif op=='add':
            p=rest.split(',')
            if len(p)==2 and p[0].strip()==rd and p[1].strip().startswith('0x'):
                regs[rd]=regs.get(rd,0)+int(p[1],16)
        elif op in('mov','movz'):
            try: regs[rd]=int(rest,0)&M
            except: pass
        elif op=='movk':
            p=rest.split(',')
            v=int(p[0],16); sh=int(p[1].strip().split()[1]) if len(p)>1 else 0
            regs[rd]=(regs.get(rd,0)&~(0xffff<<sh))|(v<<sh)
    try:
        s=decode(regs['x0'],regs.get('x1',0)&M)
        txt=s.decode('utf-8','replace')
    except Exception as e:
        txt='<ERR %s regs=%s>'%(e,{k:hex(v) for k,v in regs.items()})
    res.append((ca,fn,regs.get('x0'),regs.get('x1',0),txt))
    print('0x%x %-28s arr=%s key=%016x  %r'%(ca,fn,hex(regs['x0']) if 'x0' in regs else None,regs.get('x1',0)&M,txt))
