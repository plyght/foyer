import re,json,sys
stub={}; cur=None
for l in open('stubs.txt'):
    m=re.match(r'\d+: (fcn\.1004[45][0-9a-f]+)',l)
    if m: cur=m.group(1); continue
    if cur and 'ldr x1' in l:
        m=re.search(r'"([^"]+)"',l) or re.search(r'reloc\.fixup\.(\S+)',l) or re.search(r'reloc\.(\S+)',l)
        if m: stub[cur]=m.group(1)
        cur=None
json.dump(stub,open('stub_map.json','w'),indent=0)
def annot(src,dst):
    out=[]
    for l in open(src):
        m=re.search(r'bl (fcn\.1004[45][0-9a-f]+)',l)
        if m and m.group(1) in stub: l=l.rstrip('\n')+'   ; objc_msgSend$'+stub[m.group(1)]+'\n'
        out.append(l)
    open(dst,'w').write(''.join(out))
if __name__=='__main__':
    print(len(stub))
    for s in sys.argv[1:]: annot(s,s.replace('.txt','_annot.txt'))
