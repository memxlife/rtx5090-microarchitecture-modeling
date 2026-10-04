import json,re
from pathlib import Path
p=Path(__file__).resolve().parent
f=p/'three_way_comparison.json';d=json.loads(f.read_text())
for r in d['rows']:
 shape='_'.join(map(str,r['shape']))
 for folder in ('connected_large','cpp_small'):
  q=p/folder/(shape+'_result.json')
  if not q.exists():continue
  z=json.loads(q.read_text())
  if z['exit_code']!=0:continue
  assert z['shape']==r['shape']
  r['implementation_cycles']=z['cycles']
  r['implementation_us']=z['predicted_us_at2940']
  r['implementation_error_percent']=100*(r['implementation_us']/r['repeat_measured_us']-1)
  r['implementation_receipt']=str(q.relative_to(p))
n=sum(r['implementation_cycles'] is not None for r in d['rows'])
d['state']=f'{n} C++ model rows complete; {6-n} pending'
f.write_text(json.dumps(d,indent=2)+'\n')
f=p/'comparison_report.md';s=f.read_text()
s=re.sub(r'(One|Two|Three|Four|Five|Six|[0-6]) C\+\+ model rows? (?:is|are) complete;[^.]*\.',f'{n} C++ model rows are complete; {6-n} remain pending.',s,count=1)
start=s.index('| Matrix shape M×N×K |');end=s.index('\n\n',start)
t='| Matrix shape M×N×K | Implementation tested | High-level performance model | Implementation prediction | Fresh GPU time | High-level error | Implementation error |\n|---|---|---:|---:|---:|---:|---:|\n'
for r in d['rows']:
 v=r['implementation_us'];e=r['implementation_error_percent'];vs=f'{v:.3f}' if v is not None else 'Pending';es=f'{e:+.2f}%' if e is not None else 'Pending'
 t+=f"| {'×'.join(map(str,r['shape']))} | C++ model | {r['predicted_hlm_us']:.3f} | {vs} | {r['repeat_measured_us']:.3f} | {r['repeat_hlm_error_percent']:+.2f}% | {es} |\n"
s=s[:start]+t.rstrip()+s[end:]
s=re.sub(r'Three cases remain pending\.',f'{6-n} cases remain pending.',s)
f.write_text(s)
print(d['state'])
for r in d['rows']:print(r['shape'],r['implementation_us'],r['implementation_error_percent'])
