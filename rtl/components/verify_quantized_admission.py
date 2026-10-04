"""Build and verify connected quantized resource admission using installed Verilator."""
import hashlib,json,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parent
sources=[ROOT/n for n in ['hardware_blocks.sv','allocation_demands.sv','quantized_block_admission.sv','quantized_admission_tb.sv']]
def main():
 with tempfile.TemporaryDirectory(prefix='rtx-quantized-admission-') as directory:
  args=['verilator','--binary','--timing','--assert','-Wno-fatal','--top-module','quantized_admission_tb','--Mdir',directory,*map(str,sources)]
  build=subprocess.run(args,text=True,capture_output=True)
  (ROOT/'quantized_admission_build.log').write_text(build.stdout+build.stderr)
  if build.returncode:raise RuntimeError('Build failed; see quantized_admission_build.log')
  run=subprocess.run([str(Path(directory)/'Vquantized_admission_tb')],text=True,capture_output=True)
  assert run.returncode==0 and 'QUANTIZED_ADMISSION_PASS' in run.stdout,(run.stdout,run.stderr)
  receipt={'result':'passed','sources':{str(s.name):hashlib.sha256(s.read_bytes()).hexdigest() for s in sources},
           'checks':['saved smallGEMM11blocks44warps','saved largeGEMM8blocks32warps','no pre-edge retire bypass','retire releases capacity','warp48limit','block24limit','perblocksharedlimit','invalid zero-thread request'],
           'output':run.stdout,'timing_validated':False,'private_partition_placement_modeled':False,'full_GPU_integrated':False}
  (ROOT/'quantized_admission_verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
  print('Connected quantized allocation/admission: all directed checks passed.')
if __name__=='__main__':main()
