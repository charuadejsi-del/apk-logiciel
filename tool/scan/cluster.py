import json,re,collections
cand=json.load(open('/home/claude/work3/candidates.json'))
RANK={'bukhari':0,'muslim':1,'abudawud':2,'tirmidhi':3,'nasai':4,'ibnmajah':5}
def matn(s):
    # partie après la dernière mention du Prophète, sinon fin du texte
    i=max(s.rfind('عليه وسلم'),s.rfind('قال'))
    t=s[i:] if i>0 and len(s)-i>40 else s[-160:]
    return re.sub(r'[^ء-ي ]','',t)
def sh(t):
    w=t.split(); return {' '.join(w[i:i+3]) for i in range(max(1,len(w)-2))}
out={}; totc=0
for th,l in cand.items():
    l=sorted(l,key=lambda x:(RANK[x['book']],x['num']))
    cl=[]
    for x in l:
        s=sh(matn(x['snip']))
        for c in cl:
            inter=len(s&c['sh'])/max(1,min(len(s),len(c['sh'])))
            if inter>0.45: c['items'].append(x); break
        else: cl.append({'sh':s,'items':[x]})
    out[th]=[[ (i['book'],i['num']) for i in c['items']] for c in cl]
    totc+=len(cl); print(f'{th}: {len(l)} → {len(cl)} textes distincts')
print('TOTAL distincts', totc)
json.dump(out,open('/home/claude/work3/clusters.json','w'),ensure_ascii=False)
