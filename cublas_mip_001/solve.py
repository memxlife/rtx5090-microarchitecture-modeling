from pathlib import Path
import itertools,json,math,time,hashlib
import numpy as np
from scipy.optimize import milp,Bounds,LinearConstraint
import scipy
from scipy.optimize._highspy import _core
began=time.perf_counter()
P=Path(__file__).resolve().parent
M,N,K=192,768,3072
# Resource formulas are explicit hypotheses for a new multistage implementation.
params=dict(SMs=170,shared_per_SM=102400,shared_per_block=101376,register_words_per_SM=65536,max_warps=48,max_blocks=24,threads=128,warps=4,clock_cycles_per_us=2940,L2_bytes_per_us=3.444e6,operand_ready_cycles=340,HMMA_effective_result_cycles=64,HMMA_interval_cycles=8,schedulers=4,shared_bytes_per_cycle=128,launch_cycles=3346,workspace_limit=64*1024*1024,scalar_adds_per_SM_cycle=128)
contract={'workload':[M,N,K],'domain':{'tile_M':[32,64],'tile_N':[32,64],'tile_K':[32],'split_K':[1,2,4,8,16],'buffers':[1,2,3,4,6]},'parameters':params,'parameter_scope':'340 scalar-load composite transferred to tile arrival;64/II8 isolated-register surrogate transferred;3.444TB/s aggregate service prior;128B/cycle conflict-free shared service is architectural ideal;3346cy startup from older model, not measured CUDA launch.','register_estimate':'32 control words +ceil(tileM*tileN/128) accumulators +ceil(tileK*(tileM+tileN)/128) double operand buffers perthread; matches captured64tile96regs, unverified elsewhere.','cache_service':'Every logical staged input byte charged to warm L2; no inferred hit ratio or measured candidate runtime.','library_reference':'64x64x32 split8 buffers6,96regs,49152shared,4718592workspace, logical288tasks (captured grid384not modeled).','claim':'Structural optimistic timing proxy; no compiledcandidate/GPUvalidation orhardwareoptimality. Numerical GPU runtimes are absent from solver inputs.'}
(P/'frozen_contract.json').write_text(json.dumps(contract,indent=2))
configs=[]
for tm,tn,s,b in itertools.product([32,64],[32,64],[1,2,4,8,16],[1,2,3,4,6]):
 tk=32;stages=K//(s*tk);shared=2*tk*(tm+tn)*b;regs=32+math.ceil(tm*tn/128)+math.ceil(tk*(tm+tn)/128);workspace=0 if s==1 else 4*M*N*s
 resident=min(params['max_blocks'],params['max_warps']//4,params['register_words_per_SM']//(regs*128),params['shared_per_SM']//shared)
 if b>stages or shared>params['shared_per_block'] or resident<1 or workspace>params['workspace_limit']:continue
 tasks=(M//tm)*(N//tn)*s;active=min(170,tasks);perSM=math.ceil(tasks/170);concurrent=min(resident,perSM);waves=math.ceil(perSM/resident)
 bytes_stage=2*tk*(tm+tn);copy=bytes_stage*170*2940/params['L2_bytes_per_us']*concurrent
 hmma=2*tm*tn*tk/4096;compute=max(hmma*8/4*concurrent,2*64,bytes_stage/128*concurrent)
 period_bounds=[copy+compute] if b==1 else [copy,compute,340/(b-1)]
 startup=max(340,copy)+compute
 inputbytes=tasks*stages*bytes_stage
 globalcopy=inputbytes/params['L2_bytes_per_us']*(170/active)*2940
 workspacewrite=workspace/params['L2_bytes_per_us']*2940
 reduction=0 if s==1 else max((workspace+4*M*N)/params['L2_bytes_per_us']*2940,M*N*(s-1)/(170*128))
 record=dict(tile_M=tm,tile_N=tn,tile_K=tk,split_K=s,buffers=b,shared_bytes=shared,registers_per_thread=regs,resident_blocks_per_SM=resident,logical_tasks=tasks,stages_per_task=stages,workspace_bytes=workspace,waves=waves,period_bounds_cycles=period_bounds,startup_cycles=startup,global_copy_cycles=globalcopy,workspace_write_cycles=workspacewrite,reduction_cycles=reduction,extra_launch_cycles=3346 if s>1 else 0)
 configs.append(record)
n=len(configs);nv=2*n+3;main=2*n;red=main+1;total=main+2;H=1e7;rows=[];lo=[];hi=[]
def add(coeff,l=-np.inf,u=np.inf):
 row=np.zeros(nv)
 for i,v in coeff.items():row[i]=v
 rows.append(row);lo.append(l);hi.append(u)
add({i:1 for i in range(n)},1,1)
for j,r in enumerate(configs):
 p=n+j;add({p:1,j:-H},u=0)
 for bound in r['period_bounds_cycles']:add({p:1,j:-bound},0)
 # Conditional source-demand constraints, not measured runtime costs.
 add({main:1,p:-r['waves']*(r['stages_per_task']-1),j:-H},r['waves']*r['startup_cycles']+r['workspace_write_cycles']-H)
 add({main:1,j:-(r['global_copy_cycles']+r['workspace_write_cycles'])},0)
 add({red:1,j:-(r['reduction_cycles']+r['extra_launch_cycles'])},0)
add({total:1,main:-1,red:-1},3346)
c=np.zeros(nv);c[total]=1;integer=np.zeros(nv);integer[:n]=1;start=time.perf_counter();res=milp(c,integrality=integer,bounds=Bounds(np.zeros(nv),np.r_[np.ones(n),np.full(n+3,H)]),constraints=LinearConstraint(np.array(rows),lo,hi),options={'time_limit':30,'mip_rel_gap':0,'presolve':False});solve_seconds=time.perf_counter()-start
# Independent finite-domain evaluation of the same declared formulas.
def predict(r):return 3346+max(r['waves']*(r['startup_cycles']+(r['stages_per_task']-1)*max(r['period_bounds_cycles']))+r['workspace_write_cycles'],r['global_copy_cycles']+r['workspace_write_cycles'])+r['reduction_cycles']+r['extra_launch_cycles']
enum_start=time.perf_counter();values=[predict(r) for r in configs];enum_seconds=time.perf_counter()-enum_start;best=min(values);idx=int(np.argmax(res.x[:n])) if res.x is not None else None
result={'solver':{'API':'scipy.optimize.milp','SciPy':scipy.__version__,'HiGHS':_core._Highs().version(),'presolve':False},'solver_status':int(res.status),'solver_message':res.message,'solve_seconds':solve_seconds,'preparation_seconds':start-began,'enumeration_seconds':enum_seconds,'total_seconds_excluding_import_and_JSON_output':time.perf_counter()-began,'variables':nv,'binary_variables':n,'constraints':len(rows),'mip_gap':getattr(res,'mip_gap',None),'predicted_cycles':float(res.fun) if res.fun is not None else None,'predicted_us':float(res.fun)/2940 if res.fun is not None else None,'selected':configs[idx] if idx is not None else None,'independent_enumeration_min_cycles':best,'constraint_violation':float(max(0,np.max(np.asarray(lo)-np.array(rows)@res.x),np.max(np.array(rows)@res.x-np.asarray(hi)))) if res.x is not None else None,'enumeration_match':res.fun is not None and abs(res.fun-best)<1e-5,'enumeration_minimizers':[r for r,v in zip(configs,values) if abs(v-best)<1e-6],'reference_configurations':[dict(config=r,predicted_us=predict(r)/2940) for r in configs if (r['tile_M'],r['tile_N'],r['split_K'],r['buffers'])in[(32,32,1,1),(64,64,8,6)]],'source_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'contract_sha256':hashlib.sha256((P/'frozen_contract.json').read_bytes()).hexdigest(),'no_GPU_or_Verilog':True,'scope':contract['claim']};(P/'result.json').write_text(json.dumps(result,indent=2));(P/'derived_configurations.json').write_text(json.dumps(configs,indent=2));print(json.dumps({k:result[k] for k in ['solver_status','solve_seconds','predicted_us','selected','enumeration_match','mip_gap']},indent=2))
