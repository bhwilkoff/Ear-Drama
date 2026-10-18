import re,json,gzip,collections,sys
V={1947:'catalogofcopyrig3134libr',1948:'catalogofcopyrig3234libr',1949:'catalogofcopyrig3334libr',1950:'catalogofcopyrig3434libr'}
LATE=['catalogofcop197332734libr','catalogofcopyrig32834libr','catalogofcopyrig32934libr','catalogofcopyrig33034libr','1977dramasjandec33134libr']
MON={m:i for i,m in enumerate('Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec'.split(),1)}
def norm(s): return re.sub(r'[^A-Z0-9]','',re.sub(r'^THE ','',s.upper().replace('&','AND')))
HEAD=re.compile(r"^([A-Z][A-Z0-9 ,.'’&!:-]{3,60}?)\s*(?:\.|\((?:Radio|radio|RADIO)[^)]*\)?(?:\s*Cont'd\.?)?|Cont'd\.?)?\s*$")
DATE_RUN=re.compile(r"((?:(?:Jan|Feb|Mar|Apr|May|June?|July?|Aug|Sept?|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s*(?:\d{1,2},?\s*)*(?:&\s*\d{1,2},?\s*)?)+)(19[2-5]\d)")
def dates_in(txt):
    out=set()
    for m in DATE_RUN.finditer(txt):
        run,yr=m.group(1),int(m.group(2)); mon=None
        for tok in re.findall(r"(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?|(\d{1,2})",run):
            if tok[0]: mon=MON[tok[0][:3]]
            elif mon and 1<=int(tok[1])<=31: out.add(f"{yr}-{mon:02d}-{int(tok[1]):02d}")
    return out
regs=collections.defaultdict(lambda: collections.defaultdict(set))  # series -> date -> regs
regtxt={}
for y,v in V.items():
    t=open(f'.cache/cce_drama/{v}_djvu.txt',encoding='utf-8',errors='replace').read()
    lines=t.split('\n'); cur=None; buf=[]
    def flush():
        if cur and buf:
            b=' '.join(buf)
            if re.search(r'radio',b,re.I):
                for d in dates_in(b):
                    regs[norm(cur)][d].add(y)
                regtxt.setdefault(norm(cur),[]).append((y,b[:300]))
    for l in lines:
        s=l.strip()
        m=HEAD.match(s)
        if m and m.group(1).upper()==m.group(1) and len(m.group(1))>4 and not re.search(r'\d{3,}',s) and not s.startswith(('CATALOG OF','DRAMAS AND')):
            nc=m.group(1).strip(' .')
            if cur and norm(nc)==norm(cur): continue
            flush(); cur=nc; buf=[s]
        elif cur: buf.append(s)
    flush()
late=' '.join(open(f'.cache/cce_drama/{v}_djvu.txt',encoding='utf-8',errors='replace').read() for v in LATE)
lateU=re.sub(r'\s+',' ',late.upper())
ren=json.load(gzip.open('.cache/cce_drama_renewals.json.gz','rt'))
grw=json.load(open('.cache/grw/scripts.json'))['scripts']
res=collections.Counter(); hits=[]
ser_in=collections.Counter()
for s in grw:
    d=s['date']
    if not d or not ('1946-10-01'<=d<='1950-12-31'): continue
    res['grw 1946-10..1950']+=1
    k=norm(s['series'])
    if k in regs:
        ser_in[s['series']]+=1
        if d in regs[k]:
            res['exact series+airdate registration']+=1
            nm=re.sub(r'^THE ','',s['series'].upper())
            renewed_late = nm in lateU
            ren_rows=[r for r in ren if r['orig_year'] in (1946,1947,1948,1949,1950) and nm in ((r.get('text') or '').upper())]
            hits.append((s['series'],d,s['title'],sorted(regs[k][d]),'series name in 1973-77 OCR' if renewed_late else 'not in 1973-77 OCR',len(ren_rows)))
print(dict(res)); print(ser_in.most_common(40))
for h in sorted(hits): print(h)
json.dump(hits,open(sys.argv[1],'w'))
