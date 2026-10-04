"""Verify ownership and one combined backing transaction across two SM clients."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
from verify_numerical_matrix import no_core
ROOT=Path(__file__).resolve().parent;RTL=ROOT.parent
SOURCES=[ROOT/'multi_sm_sector_gateway.sv',ROOT/'multi_sm_sector_gateway_tb.sv']
def run():
 hashes={str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest()for p in SOURCES}
 with tempfile.TemporaryDirectory(prefix='sm-gateway-')as tmp:
  c=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','multi_sm_sector_gateway_tb','--Mdir',tmp,*map(str,SOURCES)],capture_output=True,text=True)
  (ROOT/'multi_sm_gateway_build.log').write_text(c.stdout+c.stderr);assert c.returncode==0,c.stdout+c.stderr
  results=[]
  for name,args in [('normal',[]),('wrong_id',['+wrong_id'])]:
   x=subprocess.run([str(Path(tmp)/'Vmulti_sm_sector_gateway_tb'),*args],capture_output=True,text=True,preexec_fn=no_core,timeout=20);log=x.stdout+x.stderr
   (ROOT/f'multi_sm_gateway_{name}.log').write_text(log)
   assert (x.returncode==0 and 'MULTI_SM_GATEWAY_PASS checked_words=16' in log)if name=='normal'else(x.returncode!=0 and 'Gateway read completion identity mismatch' in log),log
   results.append({'case':name,'passed':True})
 assert hashes=={str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest()for p in SOURCES}
 (ROOT/'multi_sm_gateway_verification.json').write_text(json.dumps({'all_passed':True,'checks':results,'checked_read_words':16,'checks_scope':['equal IDs across SMs/read-write','accepted write payload snapshot','delayed actual backing returns','held client responses','one combined read/write transaction','reset provider flush','wrong return identity rejection'],'timing_calibrated':False,'source_sha256':hashes},indent=2)+'\n')
if __name__=='__main__':run()
