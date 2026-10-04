"""Small real-device MILP demonstration; throughput is a coarse fixed-path proxy."""
import argparse,json,time,math,itertools,statistics
from pathlib import Path
from milp_core import Model
ROOT=Path(__file__).parent

def build(shape,limits=(6,6,4),padding=True,memory=True,capacity=True):
 M,N,K=shape;assert all(x%16==0 for x in shape)
 hw=json.loads((ROOT/'characterization.json').read_text());cal=json.loads((ROOT/'cold_64_64_32.json').read_text())
 bw=statistics.median(hw['copy_bandwidth_gbs_samples'])*1e9
 # Measured effective throughput of one frozen kernel, not theoretical Tensor Core peak.
 perf=2*math.prod(cal['shape'])/(statistics.median(cal['latency_ms_samples'])*1e-3)
 m=Model();q=[m.var('q'+d,1,u) for d,u in zip('MNK',limits)];counts=[];padded=[]
 for d,n,x in zip('MNK',shape,q):
  nc,covered=m.ceil_div_constant_numerator(n//16,x,'n'+d);counts.append(nc);padded.append(covered)
 mn=m.product(q[0],q[1],'qMqN');acc_slots=m.var('accumulator_slots',1,math.ceil(limits[0]*limits[1]/4))
 m.constraint({acc_slots:4,mn:-1},0,3)
 # Mapping-derived accumulator words, excluding operand/temporary compiler registers.
 acc=m.var('accumulator_register_words_per_thread',8,8*m.hi[acc_slots]);m.constraint({acc:1,acc_slots:-8},0,0)
 m.constraint({acc:1},hi=255)
 sumq=m.var('qM_plus_qN',2,limits[0]+limits[1]);m.constraint({sumq:1,q[0]:-1,q[1]:-1},0,0)
 footprint=m.product(q[2],sumq,'shared_units');shared=m.var('shared_bytes',4096+512*m.lo[footprint],4096+512*m.hi[footprint]);m.constraint({shared:1,footprint:-512},4096,4096)
 if capacity:m.constraint({shared:1},hi=hw['shared_cta_optin'])
 pmn=m.product(padded[0],padded[1],'padded_MN_units');work=m.product(pmn,padded[2],'executed_work_units')
 timevar=m.var('time_ms',0,1e5,False)
 if padding:m.constraint({timevar:1,work:-8192*1e3/perf},lo=0)
 else:m.constraint({timevar:1},lo=2*M*N*K*1e3/perf)
 # Masked global loads: each row of A is loaded nN times, each row of B nM times.
 # This is requested sector-aligned traffic with no cross-CTA cache reuse credit.
 if memory:m.constraint({timevar:1,counts[1]:-2*K*M*1e3/bw,counts[0]:-2*K*N*1e3/bw},lo=4*M*N*1e3/bw)
 return m,{'q':q,'counts':counts,'padded':padded,'work':work,'shared':shared,'time':timevar,'bw':bw,'perf':perf,'acc':acc}

def evaluate(shape,tile,bw,perf,padding=True,memory=True,capacity=True):
 M,N,K=shape;bm,bn,bk=tile;n=[math.ceil(a/b) for a,b in zip(shape,tile)]
 shared=4096+2*bk*(bm+bn)
 if capacity and shared>101376:return None
 if 8*math.ceil((bm//16)*(bn//16)/4)>255:return None
 w=2*math.prod([a*b for a,b in zip(n,tile)]) if padding else 2*M*N*K
 d=2*K*(n[1]*M+n[0]*N)+4*M*N
 return max(w*1e3/perf,d*1e3/bw if memory else 0)

def solve(shape,limits,seconds=60,ablation=None):
 flags=dict(padding=ablation!='padding',memory=ablation!='memory',capacity=ablation!='capacity');m,v=build(shape,limits,**flags)
 start=time.perf_counter();r=m.solve({v['time']:1},seconds);elapsed=time.perf_counter()-start
 result={'shape':shape,'limits_quotients':limits,'ablation':ablation,'status':int(r.status),'message':r.message,'solve_seconds':elapsed,'variables':len(m.names),'constraints':len(m.rows),'integer_variables':sum(m.integer),'mip_gap':getattr(r,'mip_gap',None),'mip_nodes':getattr(r,'mip_node_count',None),'objective_bound':getattr(r,'mip_dual_bound',None),'performance_model':'max(padded work / measured effective kernel throughput, requested bytes / measured copy bandwidth); no L2 term','effective_flops_s':v['perf'],'bandwidth_B_s':v['bw']}
 if r.x is None:return result
 residuals=[max(lo-sum(val*r.x[i] for i,val in row.items()),sum(val*r.x[i] for i,val in row.items())-hi,0) for row,lo,hi in zip(m.rows,m.lower,m.upper)]
 result['maximum_constraint_violation']=max(residuals)
 tile=[16*round(r.x[i]) for i in v['q']];pred=evaluate(shape,tile,v['bw'],v['perf'],**flags)
 result.update(tile=tile,predicted_ms=float(r.x[v['time']]),independently_recomputed_ms=pred,shared_bytes=round(r.x[v['shared']]),minimum_accumulator_register_words=round(r.x[v['acc']]))
 # Exhaustive arithmetic is an independent verifier; it never supplies solver candidates.
 start=time.perf_counter();rows=[]
 for qs in itertools.product(*[range(1,u+1) for u in limits]):
  t=[16*x for x in qs];score=evaluate(shape,t,v['bw'],v['perf'],**flags)
  if score is not None:rows.append((score,t))
 rows.sort();best=rows[0][0];compute_ms=(2*math.prod([math.ceil(a/b)*b for a,b in zip(shape,tile)]) if flags['padding'] else 2*math.prod(shape))*1e3/v['perf']
 result.update(independent_enumeration_seconds=time.perf_counter()-start,domain_triples=math.prod(limits),feasible_model_triples=len(rows),enumeration_optimum_ms=best,agrees_with_enumeration=abs(pred-best)<=1e-6,near_optimal_1pct=[{'tile':t,'predicted_ms':s} for s,t in rows if s<=best*1.01],active_bottleneck='compute' if abs(pred-compute_ms)<1e-6 else 'global_bandwidth')
 return result
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--shape',nargs=3,type=int,default=[1008,1008,1008]);p.add_argument('--limits',nargs=3,type=int,default=[6,6,4]);p.add_argument('--seconds',type=int,default=60);p.add_argument('--output',default='solution.json');p.add_argument('--ablation',choices=['padding','memory','capacity']);a=p.parse_args();r=solve(a.shape,a.limits,a.seconds,a.ablation);(ROOT/a.output).write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({k:v for k,v in r.items() if k!='near_optimal_1pct'},indent=2))
