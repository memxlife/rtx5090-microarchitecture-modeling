"""Independent tile variables with empirical phase bounds and exact scheduling counts."""
import json,math,sys,time,itertools
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent.parent))
from milp_core import Model
ROOT=Path(__file__).parent

def residency(tile,model):
 bm,bn,bk=tile;s=math.ceil((bm//16)*(bn//16)/4);reg=model['register_envelope'][f'{s},{bk//16}'];return min(12,65536//(128*8*math.ceil(reg/8)),102400//(4096+2*bk*(bm+bn)+1024))
def evaluate(shape,tile,model):
 n=[math.ceil(a/b) for a,b in zip(shape,tile)];q=[b//16 for b in tile];g=n[0]*n[1];s=math.ceil(q[0]*q[1]/4);r=residency(tile,model);w=math.ceil(g/(170*r));tc=n[2]*s*q[2];copy=n[2]*(q[0]+q[1])*q[2];short=n[2]*(q[2]==1);active=min(4,q[0]*q[1]);fs=[1,short,tc,copy,n[2]*(4/active-1),s];fa=[1,w*n[2],g*n[2]/(170*r),g*tc/(170*r),g*tc/170,g*copy/170,g*short/170]
 serial=sum(a*b for a,b in zip(fs,model['serial_coefficients']));aggregate=sum(a*b for a,b in zip(fa,model['aggregate_coefficients']));return {'predicted_ms':max(serial,aggregate),'serial_ms':serial,'aggregate_ms':aggregate,'resident_ctas':r,'grid_ctas':g,'waves':w,'slots':s}

def build(shape,model):
 assert all(x%16==0 for x in shape)
 m=Model();q=[m.var('q'+d,1,u) for d,u in zip('MNK',(6,6,4))];n=[];pad=[]
 for d,a,x in zip('MNK',shape,q):nc,p=m.ceil_div_constant_numerator(a//16,x,'n'+d);n.append(nc);pad.append(p)
 fragments=m.product(q[0],q[1],'fragment_count');slots=m.var('fragment_slots_per_warp',1,9);m.constraint({slots:4,fragments:-1},0,3)
 qsum=m.var('qM_plus_qN',2,12);m.constraint({qsum:1,q[0]:-1,q[1]:-1},0,0)
 shared_units=m.product(q[2],qsum,'staged_shared_units');shared=m.var('shared_allocated_with_reservation',6144,29696);m.constraint({shared:1,shared_units:-512},5120,5120)
 # Resource regimes are (fragment slots, K depth), not complete tile triples.
 regimes=[]
 for key,reg in model['register_envelope'].items():
  s,k=map(int,key.split(','));z=m.var(f'resource_regime_{s}_{k}',0,1);regimes.append((z,s,k,128*8*math.ceil(reg/8)))
 m.constraint({z:1 for z,_,_,_ in regimes},1,1);m.constraint({slots:1,**{z:-s for z,s,_,_ in regimes}},0,0);m.constraint({q[2]:1,**{z:-k for z,_,k,_ in regimes}},0,0)
 allocated=m.var('allocated_register_words_cta',min(v for *_,v in regimes),max(v for *_,v in regimes));m.constraint({allocated:1,**{z:-a for z,_,_,a in regimes}},0,0)
 rs=[];r=m.var('resident_ctas',1,12)
 for level in range(1,13):
  o=m.var('residency_'+str(level),0,1);rs.append((o,level));bigreg=13*m.hi[allocated];bigshared=13*m.hi[shared]
  m.constraint({allocated:level,o:bigreg},hi=65536+bigreg);m.constraint({shared:level,o:bigshared},hi=102400+bigshared)
  if level<12:
   cr=m.var('reg_bottleneck_'+str(level),0,1);cs=m.var('shared_bottleneck_'+str(level),0,1)
   m.constraint({cr:1,o:-1},hi=0);m.constraint({cs:1,o:-1},hi=0);m.constraint({cr:1,cs:1,o:-1},lo=0)
   m.constraint({allocated:level+1,cr:-bigreg},lo=65537-bigreg);m.constraint({shared:level+1,cs:-bigshared},lo=102401-bigshared)
 m.constraint({o:1 for o,_ in rs},1,1);m.constraint({r:1,**{o:-v for o,v in rs}},0,0)
 grid=m.product(n[0],n[1],'grid_ctas');waves=m.var('block_waves',1,math.ceil(m.hi[grid]/170));wr=m.product(waves,r,'waves_times_residency');m.constraint({wr:170,grid:-1},lo=0);m.constraint({wr:170,r:-170,grid:-1},hi=-1)
 tc=m.product(pad[2],slots,'tensor_fragment_steps');copy=m.product(pad[2],qsum,'staged_operand_units');short_flag=m.var('short_K_stage',0,1);m.constraint({short_flag:1,**{z:-1 for z,_,k,_ in regimes if k==1}},0,0);short=m.product(n[2],short_flag,'short_stage_steps')
 wave_steps=m.product(waves,n[2],'wave_stage_steps');grid_tc=m.product(grid,tc,'grid_tensor_steps');grid_short=m.product(grid,short,'grid_short_steps')
 inv_tc=[]
 for o,level in rs:inv_tc.append((m.product(o,grid_tc,f'resident_tensor_steps_{level}'),level))
 t=m.var('time_ms',0,100,False);c=model['serial_coefficients'];a=model['aggregate_coefficients']
 assert c[4]==0 and c[5]==0 and a[2]==0 and a[5]==0,'Nonzero unsupported fitted term requires additional reformulation'
 m.constraint({t:1,short:-c[1],tc:-c[2],copy:-c[3]},lo=c[0])
 terms={t:1,wave_steps:-a[1],grid_tc:-a[4]/170,grid_short:-a[6]/170}
 for x,level in inv_tc:terms[x]=-a[3]/(170*level)
 m.constraint(terms,lo=a[0])
 return m,{'q':q,'n':n,'time':t,'resident':r,'waves':waves,'shared':shared,'registers':allocated}

def solve(shape,seconds=60):
 model=json.loads((ROOT/'model.json').read_text());m,v=build(shape,model);start=time.perf_counter();result=m.solve({v['time']:1},seconds);elapsed=time.perf_counter()-start
 receipt={'shape':shape,'status':int(result.status),'message':result.message,'solve_seconds':elapsed,'mip_gap':getattr(result,'mip_gap',None),'variables':len(m.names),'constraints':len(m.rows),'model_sha256':__import__('hashlib').sha256((ROOT/'model.json').read_bytes()).hexdigest()}
 if result.x is None:return receipt
 tile=[16*round(result.x[x]) for x in v['q']];receipt.update(tile=tile,milp_predicted_ms=float(result.x[v['time']]),**evaluate(shape,tile,model));rows=[]
 for qs in itertools.product(range(1,7),range(1,7),range(1,5)):
  tt=[16*x for x in qs];rows.append(dict(tile=tt,**evaluate(shape,tt,model)))
 rows.sort(key=lambda r:r['predicted_ms']);receipt.update(independent_optimum=rows[0],agrees_with_independent_enumeration=abs(rows[0]['predicted_ms']-receipt['milp_predicted_ms'])<1e-6,top_predictions=rows[:10]);return receipt
if __name__=='__main__':
 shape=list(map(int,sys.argv[1:4])) or [640,640,640];r=solve(shape);(ROOT/('solution_'+'_'.join(map(str,shape))+'.json')).write_text(json.dumps(r,indent=2));print(json.dumps(r,indent=2))
