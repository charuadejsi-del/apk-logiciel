import json,re,sys,os
sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from hs import book,get,find,norm
import content_v2 as C
OUT=sys.argv[1] if len(sys.argv)>1 else '/home/claude/work2/out'
os.makedirs(OUT,exist_ok=True)
quran=json.load(open('/home/claude/apk-logiciel/assets/data/quran.json'))
def vok(r):
    s,a=map(int,r.split(':')); return 1<=s<=114 and 1<=a<=len(quran[s-1]['ayat'])
BN={'bukhari':'صحيح البخاري','muslim':'صحيح مسلم','ibnmajah':'سنن ابن ماجه','abudawud':'سنن أبي داود','tirmidhi':'جامع الترمذي','nasai':'سنن النسائي','malik':'موطأ مالك','ahmad':'مسند أحمد'}
GR={'sahih':'صحيح','hasan':'حسن','hasan sahih':'حسن صحيح','hasan sahih isnaad':'حسن صحيح الإسناد','sahih isnaad':'صحيح الإسناد','hasan isnaad':'حسن الإسناد','sahih hadith':'صحيح','sahih muquf':'صحيح موقوف','sahih maqtu':'صحيح مقطوع','sahih isnaad mauquf':'صحيح الإسناد موقوف','sahih isnaad maqtu':'صحيح الإسناد مقطوع','sahih mutawatir':'صحيح متواتر','daif':'ضعيف','very daif':'ضعيف جداً','mawdu':'موضوع','munkar':'منكر','shadh':'شاذ'}
def grade(b,h):
    if b in('bukhari','muslim'): return 'صحيح (من أحاديث الصحيحين)'
    for g in h.get('grades',[]):
        if 'Albani' in g.get('name',''):
            raw=g['grade'].strip(); k=re.sub(r'[^a-z\' ]','',raw.lower()).strip()
            for key,ar in sorted(GR.items(),key=lambda x:-len(x[0])):
                if k.startswith(key): return f'{ar} — الألباني'
            return f'{raw} — الألباني'
    return ''
errs=[]; hadiths=[]; ids=set()
for (hid,cat,title,b,num,kw,refs,com) in C.H:
    assert hid not in ids, hid; ids.add(hid)
    for r in refs:
        if not vok(r): errs.append(f'{hid}: verset invalide {r}')
    if kw is None:
        m=C.MANUAL[hid]; text=m['text']; bk=m['book']; g=m['grade']; note=m.get('note','')
        url='https://dorar.net/hadith/search?q='+'فأعضوه'
    else:
        ov=getattr(C,'SOURCE_OVERRIDE',{}).get(hid)
        if ov and ov[0]=='hj':
            hj=json.load(open('/home/claude/dl/hadith/db/by_book/the_9_books/%s.json'%ov[1]))['hadiths']
            x=[y for y in hj if y['idInBook']==ov[2] and norm(ov[3]) in norm(y['arabic'])]
            h={'text':x[0]['arabic'],'grades':[]} if x else None
        elif ov:
            h=get(ov[1],ov[2],ov[3])
        else:
            h=get(b,num,kw)
        if not h:
            alt=find(b,kw,6); errs.append(f"{hid} {b}:{num} «{kw}» introuvable -> candidats {[x['num'] for x in alt]}"); continue
        text=re.sub(r'[‏‎]','',h['text']).strip(); bk=BN[b]; g=grade(b,h); note=''
        if b not in('bukhari','muslim') and (not g or any(w in g for w in('ضعيف','موضوع','منكر','شاذ'))):
            errs.append(f'{hid}: grade non retenu ({g or "sans grade"})')
        url=f'https://sunnah.com/{b}:{num}'
    hadiths.append(dict(id=hid,cat=cat,title=title,book=bk,bookKey=b,number=str(num),grade=g,text=text,refs=refs,comment=com,note=note,url=url,kw=kw or 'فأعضوه'))
hid_set={h['id'] for h in hadiths}
def chk(x,where):
    if re.match(r'^\d+:\d+$',x):
        if not vok(x): errs.append(f'{where}: verset invalide {x}')
    elif x not in hid_set: errs.append(f'{where}: hadith inconnu {x}')
for o in C.OBJECTIONS:
    for r in o[4]: chk(r,o[0])
for a in C.ARGUMENTS:
    for r in a[3]: chk(r,a[0])
contra=[]
for (cid,kind,title,A,B,ex) in C.CONTRA:
    for x in A+B: chk(x,cid)
    contra.append(dict(id=cid,kind=kind,title=title,a=A,b=B,text=ex))
chains=[]
for (sid,title,summ,steps,concl) in C.CHAINS:
    st=[]
    for (t,refs,note) in steps:
        for x in (refs or []): chk(x,sid)
        st.append(dict(type=t,refs=refs or [],note=note))
    chains.append(dict(id=sid,title=title,summary=summ,steps=st,conclusion=concl))
cases=[]
cids={c['id'] for c in contra}; sids={c['id'] for c in chains}; oids={o[0] for o in C.OBJECTIONS}
for (kid,title,desc,tags,claim,qv,hh,hq,ilzam,qs,replies,ch,obj) in C.CASES:
    for r,_ in qv:
        if not vok(r): errs.append(f'{kid}: verset {r}')
    for x in hh+hq:
        if x not in cids: errs.append(f'{kid}: contradiction {x}')
    for x in ch:
        if x not in sids: errs.append(f'{kid}: chaîne {x}')
    for x in obj:
        if x not in oids: errs.append(f'{kid}: objection {x}')
    cases.append(dict(id=kid,title=title,desc=desc,tags=tags,claim=claim,quran=[dict(ref=r,note=n) for r,n in qv],
                      hh=hh,hq=hq,either=ilzam[0],orr=ilzam[1],questions=qs,replies=[dict(q=q,a=a) for q,a in replies],chains=ch,objections=obj))
# rapporteurs : le Compagnon nommé le plus près du texte, dans la chaîne seulement
def narrator(text):
    t=norm(text)
    cut=len(t)
    for m in ['قال رسول الله','سمعت رسول الله','عن النبي','ان النبي','ان رسول الله','"','قالت']:
        i=t.find(m)
        if 0<i<cut: cut=i
    mm=re.search(r' قال(?! ?(حدثن|اخبرن|انبان|سمعت|قال|لي|لنا))',t)
    if mm and mm.start()<cut: cut=mm.start()
    pre=t[:cut]
    best=None
    for name,pats in C.NARRATORS:
        for pt in pats:
            i=pre.find(pt)
            if i>=0 and (best is None or i<best[0]): best=(i,name)
    return best[1] if best else ''
for h in hadiths:
    h['narrator']=narrator(h['text'])
fatwas=[]
for (fid,title,who,mad,src,quote,isq,refs,com,rel,url) in getattr(C,'FATWAS',[]):
    for r in refs+rel: chk(r,fid)
    fatwas.append(dict(id=fid,title=title,scholar=who,madhab=mad,source=src,quote=quote,isQuote=isq,refs=refs,comment=com,related=rel,url=url))
if errs:
    print('\n'.join(errs)); sys.exit(1)
content=dict(version=2,
  topics=[dict(id=i,title=t) for i,t in C.TOPICS],
  objections=[dict(id=i,topic=t,objection=o,answer=a,refs=r) for i,t,o,a,r in C.OBJECTIONS],
  arguments=[dict(id=i,title=t,text=x,refs=r) for i,t,x,r in C.ARGUMENTS],
  hadithCategories=[dict(id=i,title=t) for i,t in C.HCATS],
  hadiths=hadiths, contradictions=contra, chains=chains, cases=cases,
  timeline=[dict(h=a,g=b2,title=t,text=x) for a,b2,t,x in C.TIMELINE], fatwas=fatwas)
json.dump(content,open(f'{OUT}/content.json','w'),ensure_ascii=False,indent=0)
print('OK', {k:len(v) for k,v in content.items() if isinstance(v,list)})
