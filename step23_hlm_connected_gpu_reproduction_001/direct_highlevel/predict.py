from pathlib import Path
import json,re,math
O=Path(__file__).resolve().parent;R=O.parents[1];d=json.loads((O/'frozen_contract.json').read_text());p=d['parameters']
lines=(R/'step6_data_path_mip_001/direct.sass').read_text().splitlines();control=[];ops=[]
for line in lines:
 m=re.search(r'/\*([0-9a-f]{4})\*/\s+(.*)',line)
 if not m:continue
 pc=int(m[1],16);text=m[2]
 if not 0x320<=pc<=0x6f0:continue
 ops.append((pc,text))
 if not any(x in text for x in ['LD.E','MOVM','HMMA']):control.append(pc)
c=len(control);stage=2*(p['global_batch_ready_cycles']+p['MOVM_ready_cycles']+p['effective_HMMA_result_use_cycles']+p['HMMA_initiation_cycles'])+c*p['ready_instruction_issue_cycles'];rows=[]
for k in [1024,2048,3072]:
 s=k//32;service=144*s*128*32/(p['L2_service_TB_per_second']*1e6)
 rows.append({'K':k,'compiled_control_instructions_per_stage':c,'prior_stage_cycles':stage,'L2_service_bound_us':service,'prior_prediction_us':p['fixed_us_original_HLM']+max(s*stage/2940,service)})
print(json.dumps(rows,indent=2));(O/'predictions.json').write_text(json.dumps({'new_adaptation_not_blind_holdout':True,'rows':rows,'compiled_stage_instruction_count':len(ops),'compiled_control_PCs':[hex(pc)for pc in control]},indent=2))
