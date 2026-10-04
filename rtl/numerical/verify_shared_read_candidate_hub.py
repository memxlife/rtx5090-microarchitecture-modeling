"""Verify shared-service arbitration and response ownership across two clients."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
from verify_numerical_matrix import no_core
ROOT=Path(__file__).resolve().parent;RTL=ROOT.parent
SOURCES=[RTL/'components/warp_shared_read_service.sv',RTL/'components/shared_read_candidate_hub.sv',ROOT/'shared_read_candidate_hub_tb.sv']
def run():
 hashes={str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest()for p in SOURCES};checks=[]
 with tempfile.TemporaryDirectory(prefix='shared-hub-')as tmp:
  for slots in [1,2]:
   b=Path(tmp)/str(slots)
   c=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','shared_read_candidate_hub_tb',f'-GSLOTS={slots}','--Mdir',str(b),*map(str,SOURCES)],capture_output=True,text=True)
   (ROOT/f'shared_hub_build_{slots}.log').write_text(c.stdout+c.stderr);assert c.returncode==0,c.stdout+c.stderr
   r=subprocess.run([str(b/'Vshared_read_candidate_hub_tb')],capture_output=True,text=True,preexec_fn=no_core,timeout=30)
   (ROOT/f'shared_hub_run_{slots}.log').write_text(r.stdout+r.stderr);assert r.returncode==0 and f'SHARED_HUB_PASS slots={slots} checked_words=128' in r.stdout,r.stdout+r.stderr
   checks.append({'slots_synthetic':slots,'checked_words':128,'passed':True})
  r=subprocess.run([str(b/'Vshared_read_candidate_hub_tb'),'+duplicate'],capture_output=True,text=True,preexec_fn=no_core,timeout=30)
  (ROOT/'shared_hub_duplicate.log').write_text(r.stdout+r.stderr);assert r.returncode!=0 and 'Duplicate' in r.stdout+r.stderr,r.stdout+r.stderr
 assert hashes=={str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest()for p in SOURCES}
 d={'all_passed':True,'checked_words':256,'checks':checks,'negative_duplicate_rejected':True,'scope':'Two clients share one synthetic scalar shared service; arbitration and queue settings are model choices, not measured GPU capacities.','contracts':['grant means actual acceptance','ungranted previews may change','same IDs across clients retain ownership','accepted data snapshot','held response stability','per-client/global conservation','reset cancellation'],'timing_calibrated':False,'source_sha256':hashes}
 (ROOT/'shared_hub_verification.json').write_text(json.dumps(d,indent=2)+'\n');print('PASS shared hub256 words')
if __name__=='__main__':run()
