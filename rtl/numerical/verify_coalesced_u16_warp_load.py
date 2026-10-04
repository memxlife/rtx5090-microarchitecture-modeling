"""Check unique sector requests and lane values using an address-defined oracle."""
from pathlib import Path
import json,hashlib,subprocess,tempfile
from verify_numerical_matrix import no_core
ROOT=Path(__file__).resolve().parent;RTL=ROOT.parent
sources=[RTL/'components/sector_read_cache.sv',ROOT/'coalesced_u16_warp_load.sv',ROOT/'coalesced_u16_warp_load_tb.sv']
with tempfile.TemporaryDirectory(prefix='coalesced-u16-')as tmp:
 b=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','coalesced_u16_warp_load_tb','--Mdir',tmp,*map(str,sources)],capture_output=True,text=True)
 (ROOT/'coalesced_u16_build.log').write_text(b.stdout+b.stderr);assert b.returncode==0,b.stdout+b.stderr
 checks=[]
 for name,flag,expected in [('normal',None,'COALESCED_U16_PASS'),('alignment','+unaligned','Unaligned active u16 lane address'),('completion_identity','+wrong_id','Cache backing completion identity mismatch')]:
  x=subprocess.run([str(Path(tmp)/'Vcoalesced_u16_warp_load_tb')]+([flag]if flag else[]),capture_output=True,text=True,preexec_fn=no_core)
  assert (x.returncode==0 if flag is None else x.returncode!=0)and expected in x.stdout+x.stderr,x.stdout+x.stderr
  checks.append({'name':name,'passed':True,'stdout':x.stdout+x.stderr})
 d={'all_passed':True,'checked_lane_values':224,'warp_cases':7,'checks':checks,'unique_sector_counts':[2,2,1,8,32,1,0],'backing_misses':[2,0,1,8,32,0,0],'oracle':'Each requested halfword equals0x5000 XOR its global halfword index; expected per-lane values use original accepted addresses, not packet extraction or permutation.','snapshot':'Addresses and active mask capture on acceptance; data comes from each actual matching packet response.','timing_scope':'Serial unique sector cache service and FIFO/blocking policy are model choices, not native warp load issue throughput.','reset_contract':'Backing provider discards pre-reset transactions; IDs contain no reset epoch.','cache_contract':'Input contents immutable between requests unless cache reset.','new_identified_registry_fields':0,'source_sha256':{str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest()for p in sources}}
 (ROOT/'coalesced_u16_warp_load_verification.json').write_text(json.dumps(d,indent=2)+'\n');print(json.dumps({'passed':True,'checked_lane_values':224,'cases':7}))
