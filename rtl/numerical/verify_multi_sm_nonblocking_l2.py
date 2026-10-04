"""Verify multiple request owners and pending shared-cache fetches."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
from verify_numerical_matrix import no_core
ROOT=Path(__file__).resolve().parent;RTL=ROOT.parent
SOURCES=[ROOT/'multi_sm_nonblocking_l2.sv',ROOT/'multi_sm_nonblocking_l2_tb.sv']
def run():
 hashes={str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest()for p in SOURCES}
 (ROOT/'multi_sm_nonblocking_l2_prebuild.json').write_text(json.dumps({'source_sha256':hashes,'phase':'before first build'},indent=2)+'\n')
 with tempfile.TemporaryDirectory(prefix='sm-gateway-')as tmp:
  c=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','multi_sm_nonblocking_l2_tb','--Mdir',tmp,*map(str,SOURCES)],capture_output=True,text=True)
  (ROOT/'multi_sm_nonblocking_l2_build.log').write_text(c.stdout+c.stderr);assert c.returncode==0,c.stdout+c.stderr
  results=[]
  for name,args in [('normal',[]),('wrong_id',['+wrong_id'])]:
   x=subprocess.run([str(Path(tmp)/'Vmulti_sm_nonblocking_l2_tb'),*args],capture_output=True,text=True,preexec_fn=no_core,timeout=20);log=x.stdout+x.stderr
   (ROOT/f'multi_sm_nonblocking_l2_{name}.log').write_text(log)
   assert ((x.returncode==0 and 'NONBLOCKING_L2_PASS checked_words=56 requests=7 fills=4 merged=2' in log) if name=='normal' else (x.returncode!=0 and ('identity mismatch' in log.lower()))),log
   results.append({'case':name,'passed':True})
 assert hashes=={str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest()for p in SOURCES}
 (ROOT/'multi_sm_nonblocking_l2_verification.json').write_text(json.dumps({'all_passed':True,'checks':results,'checked_read_words':56,'shared_l2_hits':1,'shared_l2_misses':6,'merged_misses':2,'actual_fills':4,'checks_scope':['equal IDs across SMs/read-write','accepted write payload snapshot','delayed actual backing returns','held client responses','at most one combined backing request acceptance per edge; multiple requests may remain outstanding','reset provider flush','wrong return identity rejection'],'timing_calibrated':False,'source_sha256':hashes},indent=2)+'\n')
if __name__=='__main__':run()
