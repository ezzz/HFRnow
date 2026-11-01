import json,re
from state import *
rows={r['lot']:r for r in json.load(open('lots.json'))}
def n(l): return int(l.split('-')[1])
def L(*nums): return ['LOT-%03d'%x for x in nums]
M1=set(L(0,1,2,3,4,5,10,11,12,13,14,20,21,22,24,25,30,33,34,36,37,40,41,42,43,44,45,48,65,71,80,81,82,83,84,119,160,161,169,170,137))
M2=set(L(87,106,107,108,109,110,111,112,113,114,117,136,  85,86,88,89,100,101,102,103,104,105,151,152,153,155,  124,125,143,  126,127,128,171,  116,142,115,138,139))
APP=lambda r:r['module']=='App'
M3=set(l for l,r in rows.items() if r['sec'].startswith('Phase 3') and l not in M1)
M4=set(l for l in rows if l not in M1|M2|M3)
assert not (M1&M2 or M1&M3 or M2&M3)
def deps(r):
    return ['LOT-%s'%d for d in re.findall(r'\b(\d{3})\b',r['deps'])]
def done(l): return rows[l]['issue'] in CLOSED
def flavor(r):
    f=[]
    f.append('🍎 Mac' if r['module']=='App' else '☁️ cloud')
    if r['issue'] in EXTERNAL: f.append('🤝 external')
    if 'FEAT-' in r['audit']: f.append('💡 '+re.search(r'FEAT-\d+',r['audit']).group(0))
    if r['prio']=='high': f.append('🔥 high')
    return ' · '.join(f)
def short(s,k=70):
    s=re.sub(r'\[([^\]]+)\]\([^)]+\)',r'\1',s); s=s.replace('|','/')
    return s if len(s)<=k else s[:k-1].rsplit(' ',1)[0]+'…'
def state(l):
    r=rows[l]
    if done(l): return 'done',('✅ merged'+(f' (#{MERGED_PR[l]})' if l in MERGED_PR else ''))
    if l in PRS:
        pr,st,rev=PRS[l]; return 'ongoing',(f'🛠️ draft · PR #{pr}' if st=='draft' else f'🔍 review wanted ({rev}) · PR #{pr}')
    if r['issue'] in CLAIMED: return 'ongoing','🙋 claimed'
    if r['issue'] in READY: return 'todo','🟦 ready'
    if r['issue'] in CAPTURE: return 'todo','📸 waits on capture '+CAPTURE[r['issue']]
    miss=[d for d in deps(r) if d in rows and not done(d)]
    if not miss: return 'todo','🟨 deps done, still `blocked` → triage'
    if len(miss)>6: return 'todo',f'⛔ waits on {len(miss)} lots'
    return 'todo','⛔ waits on '+', '.join(x[4:] for x in miss)
def table(ls,cols):
    out=['| '+' | '.join(cols)+' |','|'+'---|'*len(cols)]
    for l in sorted(ls,key=n):
        r=rows[l]; st=state(l)[1]
        line={'Lot':f"{l} #{r['issue']}",'Scope':short(r['scope']),'State':st,'Flavor':flavor(r),'Routing':r['model'],'Theme':(r['sub'] or r['sec'].split('—')[-1]).split('(')[0].replace('app: ','').strip()}
        out.append('| '+' | '.join(line[c] for c in cols)+' |')
    return '\n'.join(out)
def board(ms):
    b={'todo':[],'ongoing':[],'done':[]}
    for l in ms: b[state(l)[0]].append(l)
    return b
def counts(ms):
    b=board(ms); return len(b['done']),len(b['ongoing']),len(b['todo']),len(ms)
def bar(d,t,w=20):
    k=round(w*d/t) if t else 0; return '🟩'*k+'⬜'*(w-k)
if __name__=='__main__':
    for name,ms in (('M1',M1),('M2',M2),('M3',M3),('M4',M4)):
        d,o,t,tot=counts(ms); print(name,tot,'done',d,'ongoing',o,'todo',t)
    json.dump({k:sorted(v,key=n) for k,v in dict(M1=M1,M2=M2,M3=M3,M4=M4).items()},open('milestones.json','w'))
