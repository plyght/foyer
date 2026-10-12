import re, struct, sys, json
# usage: parse_consts.py dis.txt out.json
f=open('bin/Alcove.arm64','rb').read()
# section map for literal loads
secs=[]
ncmds=struct.unpack('<I',f[16:20])[0]; off=32
for i in range(ncmds):
    cmd,size=struct.unpack('<II',f[off:off+8])
    if cmd==0x19:
        nsects=struct.unpack('<I',f[off+64:off+68])[0]; so=off+72
        for j in range(nsects):
            addr,sz,offs=struct.unpack('<QQI',f[so+32:so+52]); secs.append((addr,sz,offs)); so+=80
    off+=size
def rd(va):
    for a,s,o in secs:
        if a<=va<a+s: return struct.unpack('<d',f[va-a+o:va-a+o+8])[0]
def u2d(u): return struct.unpack('<d',struct.pack('<Q',u&0xffffffffffffffff))[0]
def parse_imm(s):
    s=s.strip()
    if s.startswith('0x'): return int(s,16)
    if s.startswith('-0x'): return -int(s[1:],16)
    return int(s)
sites=[]; cur=None
for line in open(sys.argv[1]):
    line=line.rstrip('\n')
    if line.startswith('SITE'):
        _,tag,fn,addr=line.split(); cur=dict(tag=tag,fn=fn,addr=addr,ins=[]); sites.append(cur); continue
    m=re.match(r'(0x[0-9a-f]+)\s+(.*)',line)
    if m and cur: cur['ins'].append((int(m.group(1),16), m.group(2).split(';')[0].strip()))
def resolve(site):
    """walk forward tracking x-reg immediates and d-reg values until the call addr"""
    xr={}; dr={}; target=int(site['addr'],16)
    for a,ins in site['ins']:
        if a>target: break
        if a==target: break
        m=re.match(r'mov (x\d+|w\d+), (-?0x[0-9a-f]+|-?\d+)$',ins)
        if m: xr[m.group(1).replace('w','x')]=parse_imm(m.group(2))&0xffffffffffffffff; continue
        m=re.match(r'movk (x\d+), (0x[0-9a-f]+)(?:, lsl (\d+))?',ins)
        if m and m.group(1) in xr:
            sh=int(m.group(3) or 0); v=xr[m.group(1)]; v&=~(0xffff<<sh); v|=int(m.group(2),16)<<sh; xr[m.group(1)]=v; continue
        m=re.match(r'fmov (d\d+), (x\d+)$',ins)
        if m: dr[m.group(1)]=u2d(xr[m.group(2)]) if m.group(2) in xr else '?'; continue
        m=re.match(r'fmov (d\d+), ([0-9.\-]+)$',ins)
        if m: dr[m.group(1)]=float(m.group(2)); continue
        m=re.match(r'fmov (d\d+), xzr',ins)
        if m: dr[m.group(1)]=0.0; continue
        m=re.match(r'movi v(\d+)\.2d, 0+$',ins)
        if m: dr['d'+m.group(1)]=0.0; continue
        m=re.match(r'movi d(\d+), 0+$',ins)
        if m: dr['d'+m.group(1)]=0.0; continue
        m=re.match(r'ldr (d\d+), \[?(0x[0-9a-f]+)\]?',ins)
        if m: dr[m.group(1)]=rd(int(m.group(2),16)); continue
        m=re.match(r'ldr (d\d+), \[(x\d+), (0x[0-9a-f]+|\d+)\]',ins)
        if m:
            base=xr.get(m.group(2))
            dr[m.group(1)]=rd(base+parse_imm(m.group(3))) if base else '?mem'; continue
        m=re.match(r'adrp (x\d+), (0x[0-9a-f]+)',ins)
        if m: xr[m.group(1)]=int(m.group(2),16); continue
        m=re.match(r'add (x\d+), (x\d+), (0x[0-9a-f]+|\d+)$',ins)
        if m and m.group(2) in xr: xr[m.group(1)]=xr[m.group(2)]+parse_imm(m.group(3)); continue
        m=re.match(r'(fmov|fsub|fadd|fmul|fdiv|fneg|fcsel|fcvt|scvtf|ucvtf|fabs|fmax|fmin|fsqrt|fnmul|fmadd|fmsub|ldp|ldur) (d\d+)',ins)
        if m: dr[m.group(2)]='?'+m.group(1); continue
        m=re.match(r'ldp (d\d+), (d\d+)',ins)
        if m: dr[m.group(1)]='?ldp'; dr[m.group(2)]='?ldp'; continue
        if re.match(r'bl? ',ins):
            # a call clobbers d0.. (return in d0) -> mark unknown for d0-d7 unless set later
            for k in list(dr): 
                if k in ('d0','d1','d2','d3','d4','d5','d6','d7'): dr[k]='?call'
            xr={k:v for k,v in xr.items() if int(k[1:])>=19}
    return dr
out=[]
for s in sites:
    d=resolve(s); call=s['ins'][-1][1] if s['ins'] else ''
    out.append(dict(tag=s['tag'],fn=s['fn'],addr=s['addr'],call=call,d0=d.get('d0'),d1=d.get('d1'),d2=d.get('d2')))
json.dump(out,open(sys.argv[2],'w'),indent=0)
for o in out: print(o['addr'],o['fn'],o['tag'],o['d0'],o['d1'],o['d2'])
