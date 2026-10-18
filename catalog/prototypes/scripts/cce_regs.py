import re,gzip,json,collections
V={1947:'catalogofcopyrig3134libr',1948:'catalogofcopyrig3234libr',1949:'catalogofcopyrig3334libr',1950:'catalogofcopyrig3434libr'}
ren=json.load(gzip.open('.cache/cce_drama_renewals.json.gz','rt'))
renreg=collections.defaultdict(set)
for r in ren:
    m=re.match(r'([CD])[UP]?(\d+)',r['reg'] or '')
    if m: renreg[r['orig_year']].add((m.group(1),int(m.group(2))))
TOK=re.compile(r'\b([CD])\s*(?:(unp|pub)[.,]?\s*|([UP])\s*)(\d{2,6})(?:\s*-\s*(\d{1,6}))?')
out={}
for y,v in V.items():
    t=open(f'.cache/cce_drama/{v}_djvu.txt',encoding='utf-8',errors='replace').read()
    regs={}; cur_radio=False; curhead=''
    for b in re.split(r'\n\s*\n',t):
        head=b.strip().split('\n')[0] if b.strip() else ''
        if re.match(r"^[A-Z][A-Z0-9 ,.'&()-]{3,}$",head.strip()):
            cur_radio = bool(re.search(r'radio',b,re.I)); curhead=head.strip()
        isr = cur_radio or bool(re.search(r'radio',b,re.I))
        for m in TOK.finditer(b):
            a=int(m.group(4)); e=m.group(5)
            bnd=a
            if e:
                bnd=int(e) if len(e)>=len(m.group(4)) else int(m.group(4)[:len(m.group(4))-len(e)]+e)
                if bnd<a or bnd-a>200: bnd=a
            for n in range(a,bnd+1):
                k=(m.group(1),n)
                pub = (m.group(2)=='pub' or m.group(3)=='P')
                if k not in regs or isr: regs[k]=(isr,pub,curhead,b.strip()[:160])
    rr=renreg[y]
    radio=[k for k,v in regs.items() if v[0]]
    out[y]=dict(regs=len(regs),D=sum(k[0]=='D' for k in regs),C=sum(k[0]=='C' for k in regs),radio=len(radio),
       renewals=len(rr),renewed=sum(k in rr for k in regs),radio_renewed=sum(k in rr for k in radio),
       radio_D=sum(k[0]=='D' for k in radio))
    print(y,out[y])
    if y==1947:
        heads=collections.Counter(regs[k][2] for k in radio)
        print(heads.most_common(25))
