import re, json, sys
src = sys.argv[1]
lines = open(src, encoding='utf-8').read().split('\n')
i = next(k for k, l in enumerate(lines) if l.startswith('#META#Header#End#'))
heads, paras, path = [], [], {}
cur = None
def flush():
    global cur
    if cur and cur['t'].strip(): paras.append(cur)
    cur = None
for l in lines[i+1:]:
    if l.startswith('### '):
        flush()
        m = re.match(r'### (\|+)\s*(.*)', l)
        if not m: continue
        lvl = len(m.group(1)); t = m.group(2).strip()
        t = re.sub(r'^\$?\s*', '', t).replace('PARATEXT|','').strip(' []|')
        if not t or t == 'PARATEXT': continue
        path = {k: v for k, v in path.items() if k < lvl}; path[lvl] = t
        heads.append(' › '.join(path[k] for k in sorted(path)))
        continue
    if l.startswith('# '):
        flush(); cur = {'h': len(heads) - 1, 't': l[2:]}
    elif l.startswith('~~') and cur:
        cur['t'] += ' ' + l[2:]
    elif cur and l.strip() and not l.startswith('#'):
        cur['t'] += ' ' + l
flush()
# Pages : le repère PageVxxPyyy marque la FIN de la page yyy.
pm = re.compile(r'PageV(\d+)P(\d+)')
out = []
pending = []
for p in paras:
    pending.append(p)
    ms = pm.findall(p['t'])
    if ms:
        v, pg = map(int, ms[0])
        for q in pending:
            q['v'], q['p'] = v, pg
        pending = []
for q in pending:
    q['v'], q['p'] = paras[-1].get('v', 11), paras[-1].get('p', 0)
for p in paras:
    t = pm.sub(' ', p['t'])
    t = re.sub(r'\bms\d+\b', ' ', t)
    t = re.sub(r'@\w+@|~~|\$+|\|', ' ', t)
    t = re.sub(r'\s+', ' ', t).strip()
    if len(t) < 15: continue
    out.append([p['v'], p['p'], max(p['h'], 0), t])
json.dump({'h': heads, 'r': out}, open(sys.argv[2], 'w', encoding='utf-8'), ensure_ascii=False, separators=(',', ':'))
print(len(heads), 'titres;', len(out), 'récits; volumes', sorted({r[0] for r in out})[:3], '…', max(r[0] for r in out))
import statistics; L=[len(r[3]) for r in out]; print('longueur médiane', statistics.median(L), 'max', max(L))
