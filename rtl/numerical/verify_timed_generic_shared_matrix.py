"""Validate returned-word operand integration with an independent identity oracle."""
from pathlib import Path
import json,subprocess,tempfile,hashlib
from verify_numerical_matrix import no_core
ROOT=Path(__file__).resolve().parent;RTL=ROOT.parent
SOURCES=[RTL/'discovery_rounds/functional_mapping_002/native_bf16_layout.sv',ROOT/'library_movm_permutation.sv',RTL/'components/warp_shared_read_service.sv',ROOT/'numerical_matrix_pipeline.sv',ROOT/'native_bf16_adapter.sv',ROOT/'timed_generic_shared_matrix_pipeline.sv',ROOT/'timed_generic_shared_matrix_tb.sv',ROOT/'bf16_reference.cpp']
with tempfile.TemporaryDirectory(prefix='timed-generic-')as tmp:
 b=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','timed_generic_shared_matrix_tb','--Mdir',tmp,'-CFLAGS','-std=c++20',*map(str,SOURCES)],capture_output=True,text=True)
 (ROOT/'timed_generic_build.log').write_text(b.stdout+b.stderr);assert b.returncode==0,b.stdout+b.stderr
 x=subprocess.run([str(Path(tmp)/'Vtimed_generic_shared_matrix_tb')],capture_output=True,text=True,preexec_fn=no_core)
 (ROOT/'timed_generic_run.log').write_text(x.stdout+x.stderr);assert x.returncode==0,x.stdout+x.stderr
 assert 'TIMED_GENERIC_PASS'in x.stdout
 receipt={'all_passed':True,'checked_words':256,'oracle':'A identity times B with each column equal col+1; direct expected FP32 values independent of native operand permutation','checks':['eight actual warp-read responses feed matrix operands','accepted values survive shared writes/address/C changes','response backpressure','uninitialized operand rejection','reset clears initialized state and output'],'timing_calibrated':False,'snapshot_scope':'All eight read payloads snapshot at external matrix acceptance, an isolation choice distinct from native per-instruction sampling.','source_sha256':{str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest()for p in SOURCES},'stdout':x.stdout}
 (ROOT/'timed_generic_shared_matrix_verification.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps({'passed':True,'checked_words':256}))
