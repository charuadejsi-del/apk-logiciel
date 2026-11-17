import json,re,sys
E='/home/claude/dl/fh/editions/ara-%s.min.json'
def norm(s):
    s=re.sub(r'[ً-ْٰـ‏‎]','',s)
    return re.sub(r'[أإآٱ]','ا',s).replace('ة','ه').replace('ى','ي')
_c={}
def book(b):
    if b not in _c:
        hs=json.load(open(E%b))['hadiths']
        for h in hs:
            h['num']=int(str(h.get('arabicnumber','0')).split('.')[0] or 0) if b=='muslim' else h['hadithnumber']
            h['n']=norm(h['text'])
        _c[b]=hs
    return _c[b]
def find(b,kw,lim=5):
    k=norm(kw); return [h for h in book(b) if k in h['n']][:lim]
def get(b,num,kw):
    k=norm(kw); c=[h for h in book(b) if h['num']==num]
    m=[h for h in c if k in h['n']]
    return m[0] if m else None
if __name__=='__main__':
    for q in sys.argv[1:]:
        b,kw=q.split(':',1); r=find(b,kw)
        print(f"{b}«{kw}»:", ' '.join(str(h['num']) for h in r) or '—')
