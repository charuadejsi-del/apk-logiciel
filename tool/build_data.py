import os
import json,re,sys
sys.path.insert(0,os.path.dirname(__file__))
from content_src import *
import os; D=os.environ['HADITH_DIR']; Q=os.environ['TANZIL_DIR']
def norm(s):
    s=re.sub(r'[ً-ْٰـ]','',s)
    return s.replace('أ','ا').replace('إ','ا').replace('آ','ا').replace('ة','ه').replace('ى','ي')
uth=json.load(open(Q+'simple.json')); cle=json.load(open(Q+'simple-clean.json')); ch=json.load(open(Q+'chapters.json'))['chapters']
quran=[{"n":c['id'],"name":c['name'],"type":c['type'],"ayat":[v['text'] for v in uth[str(c['id'])]],"clean":[v['text'] for v in cle[str(c['id'])]]} for c in ch]
for q in quran:
    if q['n'] not in (1,9):
        assert q['clean'][0].startswith('بسم الله الرحمن الرحيم '), q['n']
        q['ayat'][0]=q['ayat'][0].split(' ',4)[4]; q['clean'][0]=q['clean'][0].split(' ',4)[4]
assert sum(len(s['ayat']) for s in quran)==6236
def verse(r):
    s,a=map(int,r.split(':')); return quran[s-1]['ayat'][a-1]
allrefs=set()
for o in OBJECTIONS: allrefs|=set(o[4])
for a in ARGUMENTS: allrefs|=set(a[3])
for h in HADITHS: allrefs|=set(h[6])
mode=sys.argv[1] if len(sys.argv)>1 else 'check'
if mode=='verses':
    for r in sorted(allrefs,key=lambda x:tuple(map(int,x.split(':')))):
        print(r, quran[int(r.split(':')[0])-1]['clean'][int(r.split(':')[1])-1][:70])
    sys.exit()
BN={'bukhari':'صحيح البخاري','muslim':'صحيح مسلم','ibnmajah':'سنن ابن ماجه','abudawud':'سنن أبي داود','tirmidhi':'جامع الترمذي'}
cache={}
def book(b):
    if b not in cache: cache[b]=json.load(open(D+b+'.json'))
    return cache[b]
out=[]
for (hid,cat,title,b,num,did,refs,com) in HADITHS:
    bk=book(b); hs=bk['hadiths']
    if did is None:
        did=[h for h in hs if norm('لا تكتبوا عني') in norm(h['arabic'])][0]['idInBook']
    h=[x for x in hs if x['idInBook']==did][0]
    chap=[c for c in bk['chapters'] if c['id']==h['chapterId']]
    chname=chap[0]['arabic'] if chap else ''
    off=int(re.sub(r'\D','',num))-did
    if mode=='check': print(f"{hid} {b} off/x={off if b!='muslim' else round(did/int(num),2)} [{chname}] :: {norm(h['arabic'])[-150:]}\n")
    out.append({"id":hid,"cat":cat,"title":title,"book":BN[b],"bookKey":b,"number":num,"chapter":chname,"text":h['arabic'].strip(),"refs":refs,"comment":com,
                "url":f"https://sunnah.com/{b}:{num}"})
if mode=='write':
    content={"topics":[{"id":i,"title":t} for i,t in TOPICS],
      "objections":[{"id":i,"topic":t,"objection":o,"answer":a,"refs":r} for i,t,o,a,r in OBJECTIONS],
      "arguments":[{"id":i,"title":t,"text":x,"refs":r} for i,t,x,r in ARGUMENTS],
      "hadithCategories":[{"id":i,"title":t} for i,t in HCATS],"hadiths":out}
    json.dump(content,open('assets/data/content.json','w'),ensure_ascii=False,indent=1)
    json.dump([{k:s[k] for k in ('n','name','type','ayat','clean')} for s in quran],open('assets/data/quran.json','w'),ensure_ascii=False,separators=(',',':'))
    print('ok',len(out))
