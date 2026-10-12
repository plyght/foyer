import re,struct,collections
blocks=open('r2_dump.txt').read().split('### ')[1:]
out=collections.Counter(); rows=[]
for b in blocks:
    lines=b.strip().split('\n'); hdr=lines[0]
    regs={}; d={}
    for ln in lines[1:]:
        m=re.match(r'0x[0-9a-f]+\s+(\w+)\s+(.*)',ln.strip())
        if not m: continue
        op,args=m.group(1),m.group(2)
        if op in('movz','mov') and re.match(r'x\d+, 0x',args):
            r,v=args.split(', '); regs[r]=int(v,16)
        elif op=='movk':
            mm=re.match(r'(x\d+), (0x[0-9a-f]+)(?:, lsl (\d+))?',args)
            if mm:
                r=mm.group(1); v=int(mm.group(2),16); sh=int(mm.group(3) or 0)
                regs[r]=(regs.get(r,0) & ~(0xffff<<sh)) | (v<<sh)
        elif op=='fmov':
            mm=re.match(r'(d\d), (x\d+)',args)
            if mm and mm.group(2) in regs:
                d[mm.group(1)]=struct.unpack('<d',struct.pack('<Q',regs[mm.group(2)]&0xffffffffffffffff))[0]
            mm=re.match(r'(d\d), ([0-9.\-]+)',args)
            if mm: d[mm.group(1)]=float(mm.group(2))
    sec='Spring' if 'Spring' in hdr else ('AnimSpring' if 'Animation' in hdr else 'other')
    key=(sec,round(d.get('d0',float('nan')),4),round(d.get('d1',float('nan')),4))
    out[key]+=1; rows.append((hdr.strip(),key))
for k,v in sorted(out.items(),key=lambda x:-x[1]): print(v,k)
print('---')
for h,k in rows: print(h,k)
