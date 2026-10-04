"""Read-only control-field and dependency audit; no hardware-fit parameters."""
from pathlib import Path
import re,json,collections,hashlib
P=Path(__file__).resolve().parent;S=P.parent
source=S/'step21_memory_path_ablation_001/anchor_gemm_only.sass'
rows=json.loads((S/'step23_hlm_connected_gpu_reproduction_001/staging_cpp_repair/producer_path.json').read_text())['rows']
lines=source.read_text().splitlines();raw={}
for i,line in enumerate(lines):
 m=re.search(r'/\*([0-9a-f]+)\*/.*?/\* 0x([0-9a-f]+) \*/',line)
 if m:
  hi=int(re.search(r'0x([0-9a-f]+)',lines[i+1])[1],16);pc=int(m[1],16);raw[pc]=(int(m[2],16),hi)
detail=[];byop=collections.defaultdict(lambda:dict(count=0,field_sum=0,extra_over_one=0,fields=collections.Counter()))
for row in rows:
 lo,hi=raw[row['pc']];field=(hi>>41)&15;label=re.search(r'\?(?:trans|WAIT)(\d+)',row['text']);assert label and int(label[1])==field
 op=row['opcode'].split('.')[0];d=byop[op];d['count']+=1;d['field_sum']+=field;d['extra_over_one']+=max(0,field-1);d['fields'][field]+=1
 detail.append({'index':len(detail),'pc':hex(row['pc']),'opcode':row['opcode'],'opcode_low16':hex(lo&65535),'field':field,'raw_high':hex(hi),'req':row['req'],'wr':row['wr'],'rd':row['rd']})
def timeline(mode):
 ready=[0]*64;release=[0]*64;tag=[0]*6;events=[];last=-1;gap=1;parent={};nodes={};critical=None
 for j,(row,d)in enumerate(zip(rows,detail)):
  constraints=[(0,None,'initial'),(last+gap,j-1 if j else None,'prior issue spacing')]
  for r in row['src']:constraints.append((ready[r][0] if isinstance(ready[r],tuple)else ready[r],ready[r][1]if isinstance(ready[r],tuple)else None,f'source R{r}'))
  for r in row['dst']:
   for arr,kind in [(ready,'prior writer'),(release,'read ownership')]:constraints.append((arr[r][0]if isinstance(arr[r],tuple)else arr[r],arr[r][1]if isinstance(arr[r],tuple)else None,f'{kind} R{r}'))
  for b in range(6):
   if row['req']>>b&1:constraints.append((tag[b][0]if isinstance(tag[b],tuple)else tag[b],tag[b][1]if isinstance(tag[b],tuple)else None,f'wait tag {b}'))
  t,prev,why=max(constraints,key=lambda x:x[0]);due=t+(340 if row['kind']==1 else 1)
  for r in row['src']:release[r]=(t+1,j)
  for r in row['dst']:ready[r]=(due,j)
  for b,at in [(row['wr'],due),(row['rd'],t+1)]:
   if b>=0 and at>=(tag[b][0]if isinstance(tag[b],tuple)else tag[b]):tag[b]=(at,j)
  gap=max(1,d['field'])if mode=='all_fields_conditional'else max(1,d['field'])if mode=='tested_classes_conditional'and d['opcode_low16']in('0x7810','0x7235')else 1
  parent[j]=prev;nodes[j]={'index':j,'pc':d['pc'],'opcode':d['opcode'],'issue':t,'ready':due,'binding':why,'gap_after':gap};events.append(nodes[j]);last=t
 end=max(events,key=lambda x:x['ready']);chain=[];a=end['index']
 while a is not None:chain.append(nodes[a]);a=parent[a]
 return {'completion_lower_estimate':end['ready'],'chain':list(reversed(chain)),'events':events,'scope':'One warp earliest dependency timeline with floor340 and ALU/capture1; no cache, issue competition or service durations. Entire-control mode is unvalidated ablation.'}
result={'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'producer_instructions_per_warp':len(rows),'per_warp_encoded_field_sum':sum(d['field']for d in detail),'per_warp_extra_over_one':sum(max(0,d['field']-1)for d in detail),'opcode_distribution':dict(byop),'details':detail,'timelines':{mode:timeline(mode)for mode in ['one_cycle_baseline','tested_classes_conditional','all_fields_conditional']},'claim_boundary':'Raw upper bits41..44 exactly agree with disassembler trans/WAIT numeric labels. Only ready-GPR IADD3 opcode7810 and register-registerIADD64 opcode7235 differential2to4 were independently tested. Absolute-field interpretation and other opcodes remain hypotheses. Fields are per-warp cooldown, not instruction-result latency or additive full-chip runtime.'}
(P/'producer_control_audit.json').write_text(json.dumps(result,indent=2)+'\n')
print('FIELDS',result['per_warp_encoded_field_sum'],result['per_warp_extra_over_one']);print({k:v['completion_lower_estimate']for k,v in result['timelines'].items()});print(dict(byop))
