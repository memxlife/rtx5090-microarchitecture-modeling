"""Verify measured lane mapping connected to the finite arithmetic reference."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
from verify_numerical_matrix import vectors,write_vectors,no_core
ROOT=Path(__file__).resolve().parent
MAP=ROOT.parent/'discovery_rounds/functional_mapping_002'
def run():
 arrays,labels=vectors();directory=ROOT/'vectors';write_vectors(directory,arrays)
 sources=[MAP/'native_bf16_layout.sv',ROOT/'numerical_matrix_pipeline.sv',ROOT/'native_bf16_adapter.sv',ROOT/'native_matrix_vectors_tb.sv',ROOT/'bf16_reference.cpp']
 tool='verilator';checks=[]
 with tempfile.TemporaryDirectory(prefix='rtx-native-') as tmp:
  for latency,interval in [(2,1),(17,3)]:
   build=Path(tmp)/str(latency)
   result=subprocess.run([tool,'--binary','--timing','-Wno-fatal','--top-module','native_matrix_vectors_tb',f'-GLATENCY={latency}',f'-GINTERVAL={interval}','--Mdir',str(build),'-CFLAGS','-std=c++20',*[str(p) for p in sources]],text=True,capture_output=True)
   (ROOT/f'native_build_{latency}.log').write_text(result.stdout+result.stderr)
   assert result.returncode==0,result.stdout+result.stderr
   command=[str(build/'Vnative_matrix_vectors_tb'),f'+vectors={directory}',f'+mappings={MAP}']
   result=subprocess.run(command,text=True,capture_output=True,preexec_fn=no_core)
   assert result.returncode==0 and 'NATIVE_MATRIX_PASS' in result.stdout,result.stdout+result.stderr
   checks.append({'latency_synthetic':latency,'interval_synthetic':interval,'output':result.stdout,'passed':True})
   if latency==17:
    result=subprocess.run(command+['+duplicate'],text=True,capture_output=True,preexec_fn=no_core)
    assert result.returncode!=0 and 'Duplicate pending matrix identity' in result.stdout+result.stderr
    checks.append({'duplicate_identity_rejected':True})
 receipt={'all_passed':True,'checked_output_words':3072,'cases':labels,'checks':checks,'source_sha256':{str(p.relative_to(ROOT.parent)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},'layout_table_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in MAP.glob('*_mapping.hex')},'hardware_timing_calibrated':False,'native_accumulation_order_identified':False,'arithmetic_reference':'Exact rational oracle with sequential FP32 FMA rounding; numerical hardware equivalence beyond exact integer mapping tests is unproven','full_gpu_integrated':False}
 (ROOT/'native_matrix_verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
 print('Native matrix verification: 3072 output words, queue/backpressure/reset and duplicate identity checks passed; timings remain synthetic.')
if __name__=='__main__':run()
