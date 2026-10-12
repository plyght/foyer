import bisect,json,re,struct,sys,pathlib
root=pathlib.Path('/Users/devin/alcove-uncovered')
funcs=sorted(json.load(open(root/'functions.json')),key=lambda f:f['addr'])
starts=[f['addr'] for f in funcs]
lines=(root/'otool.txt').read_text().splitlines()
addrs=[];code=[]
for l in lines:
    if re.match('[0-9a-f]{16}\\s',l):
        addrs.append(int(l[:16],16));code.append(l)
b=(root/'Alcove.arm64').read_bytes()
selectors=json.load(open(root/'ev/objc_selector_map.json')) if (root/'ev/objc_selector_map.json').exists() else {}
def cstring(p):
    p=p-0x100000000
    if not 0<=p<len(b):return ''
    return b[p:b.find(b'\0',p)].decode(errors='replace')
def dump(addr,end=None):
    f=funcs[bisect.bisect_right(starts,addr)-1]
    a=f['addr'] if end is None else addr
    z=f['addr']+f['size'] if end is None else end
    regs={};out=[f"FUNCTION {f['name']} 0x{a:x}-0x{z:x}"]
    for l in code[bisect.bisect_left(addrs,a):bisect.bisect_left(addrs,z)]:
        m=re.search(r'\b(mov|movk)\s+[xw](\d+), #(-?0x[0-9a-f]+)(?:, lsl #(\d+))?',l)
        if m:
            op,r,v,shift=m.groups();v=int(v,16);shift=int(shift or 0)
            regs[r]=((regs.get(r,0)&~(0xffff<<shift))|(v<<shift)) if op=='movk' else v&((1<<64)-1)
            raw=regs[r].to_bytes(8,'little');s=raw.rstrip(b'\0')
            if len(s)>2 and all(32<=c<127 for c in s): l+=' ; SMALL '+repr(s.decode())
        l=re.sub(r'\b(?:bl|b)\s+(0x[0-9a-f]+)',lambda x:x[0]+(' ; objc '+selectors[x[1]] if x[1] in selectors else ''),l)
        out.append(l)
    return '\n'.join(out)+'\n'
if __name__=='__main__':
    for arg in sys.argv[1:]:
        x=arg.split(':');a=int(x[0],16);end=int(x[1],16) if len(x)>1 else None
        p=root/'ev'/('fn_'+x[0]+'.txt');p.write_text(dump(a,end));print(str(p))
