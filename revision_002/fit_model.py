import json,math,statistics
from pathlib import Path
import numpy as np
from scipy.optimize import nnls
ROOT=Path(__file__).parent
rows=json.loads((ROOT/'calibration.json').read_text())

def counts(shape,tile,resident):
 n=[math.ceil(a/b) for a,b in zip(shape,tile)];q=[b//16 for b in tile];g=n[0]*n[1];s=math.ceil(q[0]*q[1]/4);active=min(4,q[0]*q[1]);w=math.ceil(g/(170*resident));return n,q,g,s,active,w

def features(shape,tile,resident):
 n,q,g,s,active,w=counts(shape,tile,resident);steps=n[2];tc=steps*s*q[2];copy=steps*(q[0]+q[1])*q[2];short=steps*(q[2]==1)
 serial=[1,short,tc,copy,steps*(4/active-1),s]
 aggregate=[1,w*steps, g*steps/(170*resident),g*tc/(170*resident),g*tc/170,g*copy/170,g*short/170]
 return serial,aggregate
serial_rows=[r for r in rows if math.prod([math.ceil(a/b) for a,b in zip(r['shape'][:2],r['tile'][:2])])<=170*r['resident_ctas']]
aggregate_rows=[r for r in rows if r not in serial_rows]
def fit(data,part):
 X=np.array([features(r['shape'],r['tile'],r['resident_ctas'])[part] for r in data]);y=np.array([r['latency_ms_median'] for r in data]);coef,res=nnls(X/y[:,None],np.ones(len(y)));return coef
cs=fit(serial_rows,0);ca=fit(aggregate_rows,1)
# Resource envelope depends only on fragment slots and reduction-depth regime, not a full tile triple.
resources=json.loads((ROOT.parent/'domain_validation.json').read_text());envelope={}
for r in resources:
 bm,bn,bk=r['tile'];key=f'{math.ceil((bm//16)*(bn//16)/4)},{bk//16}';envelope[key]=max(envelope.get(key,0),r['registers_thread'])
def residency(tile):
 bm,bn,bk=tile;s=math.ceil((bm//16)*(bn//16)/4);reg=envelope[f'{s},{bk//16}'];allocated=128*8*math.ceil(reg/8);shared=4096+2*bk*(bm+bn)+1024;return min(12,65536//allocated,102400//shared)
records=[]
for r in rows:
 fs,fa=features(r['shape'],r['tile'],r['resident_ctas']);pred=max(np.dot(fs,cs),np.dot(fa,ca));records.append({'tile':r['tile'],'shape':r['shape'],'purpose':r['purpose'],'actual_residency':r['resident_ctas'],'predicted_ms':pred,'measured_ms':r['latency_ms_median'],'relative_error':abs(pred-r['latency_ms_median'])/r['latency_ms_median']})
model={'serial_coefficients':cs.tolist(),'aggregate_coefficients':ca.tolist(),'serial_features':['launch','short_K_stage','warp_tensor_steps','staged_operand_units','inactive_warp_dependency','epilogue_slots'],'aggregate_features':['launch','wave_stage_steps','resident_latency_steps','resident_tensor_steps','tensor_issue_work','operand_staging_work','short_K_stage_issue'],'register_envelope':envelope,'resource_policy':'conservative max compiler registers by fragment-slot count and K-depth; per-warp allocation granularity 256 words inferred and checked on original 144 compiler-resource observations','shared_reserved_bytes':1024,'shared_allocation_granularity':256,'register_allocation_words_warp':256,'sms':170,'l2_term':False,'memory_policy':'phase service rates are empirical for the unchanged hardware; requested bytes are not asserted to equal GDDR7 traffic','serial_calibration_rows':len(serial_rows),'aggregate_calibration_rows':len(aggregate_rows),'calibration_median_relative_error':statistics.median(r['relative_error'] for r in records),'calibration_predictions':records}
(ROOT/'model.json').write_text(json.dumps(model,indent=2));print(json.dumps({k:v for k,v in model.items() if k not in ['calibration_predictions','register_envelope']},indent=2))
