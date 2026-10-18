import sys,glob,collections,json,random,re,difflib
sys.path.insert(0,sys.argv[1]); import radio_parse as P
files=sorted(glob.glob('*.txt'))
tot=collections.Counter(); per=[]; stubs=[]; allsp=[]; allother=[]; aliasn=0; singles=0; rolesN=[]; castN=0; cast_match=[]
for f in files:
    raw=open(f,encoding='utf-8',errors='replace').read()
    h,cast,items=P.parse(raw)
    c=collections.Counter(i['t'] for i in items)
    n=sum(c.values())
    if c['speech']<20: stubs.append((f,h['series'],h['title'],dict(c),len(raw))); continue
    tot.update(c); per.append(c['speech']/n)
    roles=collections.Counter(i['role'] for i in items if i['t']=='speech')
    rolesN.append(len(roles))
    big=[r for r,k in roles.items() if k>=3]
    for r,k in roles.items():
        if k<=2:
            singles+=1
            if difflib.get_close_matches(r,big,1,0.75) or any(r!=b and (b.startswith(r) or r.startswith(b)) for b in big): aliasn+=1
    if cast:
        castN+=1
        cs=[re.sub(r'[^A-Z ]','',x.upper()) for x in cast]
        hit=sum(1 for r in big if any(r in x or any(w==r for w in x.split()) for x in cs))
        cast_match.append(hit/max(1,len(big)))
    for i in items:
        if i['t']=='speech': allsp.append((f,i['role'],i['text'][:90]))
        if i['t']=='other': allother.append((f,i['text'][:110]))
print('files',len(files),'parsed',len(per),'stubs(<20 speeches)',len(stubs))
print('blocks',dict(tot),'speech share mean',round(sum(per)/len(per),3),'median',sorted(per)[len(per)//2], 'p10',sorted(per)[len(per)//10])
print('roles per script median',sorted(rolesN)[len(rolesN)//2],'max',max(rolesN))
print('rare roles (<=2 lines)',singles,'of which look like alias/typo of a frequent role',aliasn)
print('scripts with a CAST header',castN,'mean share of frequent roles found in it',round(sum(cast_match)/max(1,len(cast_match)),2))
random.seed(7)
json.dump({'sp':random.sample(allsp,60),'other':random.sample(allother,60),'stubs':stubs[:40]},open(sys.argv[2],'w'),indent=0)
