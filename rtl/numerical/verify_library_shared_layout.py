#!/usr/bin/env python3
"""Compare every legal SV address against the authoritative Python layout."""
import hashlib,importlib.util,json,shutil,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parent
AUTH=ROOT.parent/'discovery_rounds/executed_layout_009/layout_binding.py'
spec=importlib.util.spec_from_file_location('authoritative_layout',AUTH);layout=importlib.util.module_from_spec(spec);spec.loader.exec_module(layout)

def main():
 rows=[]
 for slot in range(2):
  for thread in range(128):
   aa,bb=layout.producer(thread,slot)
   for group in range(4):
    rows.extend([(0,thread,slot,group,0,0,aa[group]),(1,thread,slot,group,0,0,bb[group])])
  for kstep in range(8):
   for warp in range(4):
    for lane in range(32):
     aa,bb=layout.consumer(warp,lane,slot,kstep)
     for word in range(4):rows.extend([(2,warp,lane,slot,kstep,word,aa[word]),(3,warp,lane,slot,kstep,word,bb[word])])
 assert len(rows)==18432
 from verify_numerical_matrix import no_core
 with tempfile.TemporaryDirectory()as td:
  t=Path(td);vectors=t/'vectors.txt';vectors.write_text('\n'.join(' '.join(map(str,row))for row in rows)+'\n')
  build=t/'build'
  subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','tb_library_shared_layout','--Mdir',str(build),str(ROOT/'library_shared_layout.sv'),str(ROOT/'tb_library_shared_layout.sv')],check=True,capture_output=True,text=True)
  exe=build/'Vtb_library_shared_layout'
  result=subprocess.run([str(exe),'+VECTORS='+str(vectors)],check=True,capture_output=True,text=True,preexec_fn=no_core)
  assert 'PASS18432' in result.stdout.replace(' ','')
  bad=subprocess.run([str(exe),'+invalid'],capture_output=True,text=True,preexec_fn=no_core)
  assert bad.returncode!=0 and 'index outside' in bad.stdout+bad.stderr
 receipt={'legal_address_checks':len(rows),'mismatches':0,'invalid_index_rejected':True,'shared_bytes':layout.TOTAL,'authoritative_source':str(AUTH),'authoritative_sha256':hashlib.sha256(AUTH.read_bytes()).hexdigest(),'SV_sha256':hashlib.sha256((ROOT/'library_shared_layout.sv').read_bytes()).hexdigest(),'stdout':result.stdout.strip(),'scope':'Selected library software shared-address layout only; no private hardware capacity or timing identification.','review':{'human_first_technical_writing':True,'undergraduate_reader_review':True}}
 (ROOT/'library_shared_layout_verification.json').write_text(json.dumps(receipt,indent=2)+'\n');print(result.stdout.strip())
if __name__=='__main__':main()
