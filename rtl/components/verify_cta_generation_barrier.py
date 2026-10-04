"""Check generation ownership, arrival conservation and registered releases."""
from pathlib import Path
import hashlib,json,re,subprocess,tempfile,resource
ROOT=Path(__file__).resolve().parent
sources=[ROOT/'cta_generation_barrier.sv',ROOT/'cta_generation_barrier_tb.sv']
def no_core():resource.setrlimit(resource.RLIMIT_CORE,(0,0))
checks=[]
with tempfile.TemporaryDirectory(prefix='cta-generation-')as tmp:
 for delay in [1,5]:
  b=Path(tmp)/str(delay)
  q=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','cta_generation_barrier_tb',f'-GRELEASE_DELAY={delay}','--Mdir',str(b),*map(str,sources)],capture_output=True,text=True)
  (ROOT/f'cta_generation_barrier_build_{delay}.log').write_text(q.stdout+q.stderr);assert q.returncode==0,q.stdout+q.stderr
  cases=[('normal',None,'CTA_GENERATION_BARRIER_PASS')]
  if delay==1:cases +=[(flag,'+'+flag,msg)for flag,msg in [('early','CTA arrival before generation arm'),('same_edge','CTA arrival before generation arm'),('empty_arm','Empty CTA expected mask'),('bad_arm','CTA arm generation out of sequence'),('future','CTA arrival generation mismatch'),('wrongmask','Unexpected CTA arrival warp'),('empty_arrival','Empty CTA arrival mask'),('duplicate','Duplicate CTA generation arrival'),('stale','CTA arrival generation mismatch')]]
  for name,flag,expected in cases:
   x=subprocess.run([str(b/'Vcta_generation_barrier_tb')]+([flag]if flag else[]),capture_output=True,text=True,preexec_fn=no_core)
   assert (x.returncode==0 if flag is None else x.returncode!=0)and expected in x.stdout+x.stderr,x.stdout+x.stderr
   result={'name':name,'release_delay':delay,'passed':True,'stdout':x.stdout+x.stderr}
   if flag is None:result['directed_checks']=int(re.search(r'checks=(\d+)',x.stdout)[1])
   checks.append(result)
d={'all_passed':True,'directed_positive_checks':sum(x.get('directed_checks',0)for x in checks),'rejection_cases':9,'checks':checks,'generation_sequence':'Starts0; one armed generation; next increment only after release acknowledgement; no wrap supported.','arrival_rule':'Nonempty expected subset with no duplicate warp arrivals; same-edge idle arm+arrival rejected.','backpressure':'Release identity/mask stable until ack; next arm cannot accept on release-ack edge. Held arm allowed while busy.','reset':'Cancels active collection/delayed or held release; next generation resets0.','timing_scope':'Release delay and warp-level arrivals are simulation choices, not measured CTA barrier implementation.','new_identified_registry_fields':0,'source_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest()for p in sources}}
(ROOT/'cta_generation_barrier_verification.json').write_text(json.dumps(d,indent=2)+'\n');print(json.dumps({'passed':True,'directed_checks':d['directed_positive_checks'],'rejections':9}))
