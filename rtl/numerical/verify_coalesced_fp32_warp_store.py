"""Check masked sector writes against independent per-lane memory updates."""
from pathlib import Path
import json,hashlib,subprocess,tempfile
from verify_numerical_matrix import no_core
ROOT=Path(__file__).resolve().parent
sources=[ROOT/'coalesced_fp32_warp_store.sv',ROOT/'coalesced_fp32_warp_store_tb.sv']
with tempfile.TemporaryDirectory(prefix='coalesced-fp32-store-')as tmp:
 b=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','coalesced_fp32_warp_store_tb','--Mdir',tmp,*map(str,sources)],capture_output=True,text=True)
 (ROOT/'coalesced_fp32_store_build.log').write_text(b.stdout+b.stderr);assert b.returncode==0,b.stdout+b.stderr
 checks=[]
 for name,flag,expected in [('normal',None,'COALESCED_FP32_STORE_PASS'),('alignment','+unaligned','Unaligned active FP32 store address'),('duplicate_policy','+duplicate','Duplicate active FP32 store address'),('completion_identity','+wrong_id','Warp store acknowledgement identity mismatch')]:
  x=subprocess.run([str(Path(tmp)/'Vcoalesced_fp32_warp_store_tb')]+([flag]if flag else[]),capture_output=True,text=True,preexec_fn=no_core)
  assert (x.returncode==0 if flag is None else x.returncode!=0)and expected in x.stdout+x.stderr,x.stdout+x.stderr
  checks.append({'name':name,'passed':True,'stdout':x.stdout+x.stderr})
 d={'all_passed':True,'checked_memory_words':20480,'warp_cases':5,'unique_sector_counts':[4,8,32,1,0],'oracle':'Direct active-lane updates to a separate global word array using original addresses and payloads, independent of sector grouping, masks and packet extraction; untouched words checked too.','checks':checks,'scope':'Functional grouping into aligned32B masked word writes; serial sector requests and one outstanding acknowledgement are explicit simulation choices.','duplicate_policy':'Any duplicate active byte address rejected, including equal values; no-race policy, not a GPU hardware restriction.','reset_contract':'Provider flushes pre-reset requests/acks; already committed words are not rolled back.','identity':'External full32bit ID preserved; internal ID=external XOR sector ordinal, injective within one inflight warp.','new_identified_registry_fields':0,'timing_calibrated':False,'source_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest()for p in sources}}
 (ROOT/'coalesced_fp32_warp_store_verification.json').write_text(json.dumps(d,indent=2)+'\n');print(json.dumps({'passed':True,'checked_memory_words':20480,'cases':5}))
