"""Directed numerical/handshake checks for the blocking four-sector cache."""
from pathlib import Path
import hashlib,json,subprocess,tempfile,resource
ROOT=Path(__file__).resolve().parent
def no_core():resource.setrlimit(resource.RLIMIT_CORE,(0,0))
def run():
 sources=[ROOT/'sector_read_cache.sv',ROOT/'sector_read_cache_tb.sv'];checks=[]
 with tempfile.TemporaryDirectory(prefix='sector-read-cache-') as tmp:
  q=subprocess.run(['verilator','--binary','--timing','-Wno-fatal','--top-module','sector_read_cache_tb','--Mdir',tmp,*map(str,sources)],text=True,capture_output=True);(ROOT/'sector_read_cache_build.log').write_text(q.stdout+q.stderr);assert q.returncode==0,q.stdout+q.stderr
  for name,plus,expected in [('normal',None,'SECTOR_CACHE_PASS'),('completion_identity','+wrong_id','Cache backing completion identity mismatch'),('alignment','+unaligned','Unaligned cache word request')]:
   q=subprocess.run([str(Path(tmp)/'Vsector_read_cache_tb')]+([plus] if plus else []),text=True,capture_output=True,preexec_fn=no_core);assert (q.returncode==0 if plus is None else q.returncode!=0) and expected in q.stdout+q.stderr,q.stdout+q.stderr;checks.append({'name':name,'passed':True,'output':q.stdout+q.stderr})
 receipt={'all_passed':True,'checks':checks,'physical_geometry':{'line_bytes':128,'sector_bytes':32,'sectors_per_line':4},'model_choices':{'SETS':2,'WAYS':1,'pending_requests':1,'replacement':'first invalid else rotating victim','hit_result':'registered nextedge'},'backing_timing':'Actual ID-matched backing return, no inferred miss timestamp','numerical_storage':'Full256bit sector packet and requested32bit word captured on hit or return; packet contents checked independently for all8words','source_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},'full_gpu_integrated':False,'hardware_latency_identified':False};(ROOT/'sector_read_cache_verification.json').write_text(json.dumps(receipt,indent=2)+'\n');print('Sector cache checks passed:two sectors miss separately, hits, numeric words, delayed completion,backpressure,eviction,reset,invalidinputs.')
if __name__=='__main__':run()
