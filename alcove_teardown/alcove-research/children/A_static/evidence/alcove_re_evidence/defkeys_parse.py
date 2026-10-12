import re,json,sys,struct
def imm(s):
    s=s.strip(); neg=s.startswith('-'); v=int(s.lstrip('-'),16) if '0x' in s else int(s.lstrip('-'))
    return (-v)&0xffffffffffffffff if neg else v
funcs={}; cur=None
for l in open(sys.argv[1]):
    if l.startswith('FUNC '): cur=l.split()[1]; funcs[cur]=[]; continue
    if cur: funcs[cur].append(l.rstrip('\n') if '; 0x' in l and '"' in l else l.split(';')[0].rstrip())
keys=[]
for fn,lines in funcs.items():
    if not any('fcn.100452a60' in l for l in lines): continue
    key=None; closure=None; regs={}; default=None; allocs=0; dregs={}
    for l in lines:
        m=re.search(r'; 0x[0-9a-f]+ ; "([^"]+)"',l)
        if m and key is None and 'add x8' in l: key=m.group(1)
        m=re.search(r'add x8, x8, str\.(\S+)',l)
        if m and key is None: key=m.group(1)
        m=re.match(r'0x[0-9a-f]+\s+mov ([xw]\d+), (-?0x[0-9a-f]+|-?\d+)$',l)
        if m: regs[m.group(1).replace('w','x')]=imm(m.group(2))
        m=re.match(r'0x[0-9a-f]+\s+movk (x\d+), (0x[0-9a-f]+)(?:, lsl (\d+))?',l)
        if m and m.group(1) in regs:
            sh=int(m.group(3) or 0); v=regs[m.group(1)]&~(0xffff<<sh); regs[m.group(1)]=v|(int(m.group(2),16)<<sh)
        m=re.match(r'0x[0-9a-f]+\s+fmov (d\d+), ([0-9.\-]+)$',l)
        if m: dregs[m.group(1)]=float(m.group(2))
        m=re.match(r'0x[0-9a-f]+\s+fmov (d\d+), (x\d+)$',l)
        if m and m.group(2) in regs: dregs[m.group(1)]=struct.unpack('<d',struct.pack('<Q',regs[m.group(2)]))[0]
        m=re.match(r'0x[0-9a-f]+\s+adrp (x\d+), (0x[0-9a-f]+)',l)
        if m: regs['A'+m.group(1)]=int(m.group(2),16)
        m=re.match(r'0x[0-9a-f]+\s+add (x\d+), (x\d+), (0x[0-9a-f]+)',l)
        if m and 'A'+m.group(2) in regs: regs['C'+m.group(1)]=regs['A'+m.group(2)]+int(m.group(3),16)
        m=re.match(r'0x[0-9a-f]+\s+stp (x\d+), x\d+, \[x\d+, 0x28\]',l)
        if m and 'C'+m.group(1) in regs: closure=regs['C'+m.group(1)]
        if 'swift_allocObject' in l: allocs+=1
        m=re.match(r'0x[0-9a-f]+\s+(str|strb|strh|stur|stp) (\w+), (?:\w+, )?\[x0, 0x10\]',l)
        if m and allocs>=2 and default is None:
            r=m.group(2)
            if r in ('xzr','wzr'): default=0
            elif r.startswith('d'): default=dregs.get(r,'?'+r)
            else:
                r=r.replace('w','x'); default=regs.get(r,'?'+r)
            default=(m.group(1),default)
    if key is None:
        # inline string: find x24/x25-like pair stored at [x19,0x10]
        for l in lines:
            m=re.match(r'0x[0-9a-f]+\s+stp (x\d+), (x\d+), \[x\d+, 0x10\]',l)
            if m:
                a=regs.get(m.group(1),0); b=regs.get(m.group(2),0)
                raw=a.to_bytes(8,'little')+b.to_bytes(8,'little')
                n=raw[15]&0x0f
                if raw[15]&0xe0==0xe0 and n<=15: key='INLINE:'+raw[:n].decode('latin1')
                else: key='?stp %x %x'%(a,b)
                break
    keys.append(dict(fn=fn,key=key,closure=hex(closure) if closure else None,default=default))
json.dump(keys,open('defkeys_funcs.json','w'),indent=0)
for k in keys: print(k['fn'],k['key'],k['closure'],k['default'])
