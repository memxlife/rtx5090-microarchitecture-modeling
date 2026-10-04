"""Verify executable work rules against measured development and confirmation masks."""
from pathlib import Path
import sys,json,hashlib,subprocess,tempfile
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent/'parameter_sweep'))
from shared_work import shared_broadcast128_packages
MASKS=[0xff,0x11111111,0xffff,0x55555555,0xffffffff,0xff000000,0xffff0000,0x00ffff00,0x80000001,0x80000000]
EXPECTED=[1,2,1,2,2,1,1,2,2,1]
def run():
 for mask,expected in zip(MASKS,EXPECTED):assert shared_broadcast128_packages(mask)==expected
 assert shared_broadcast128_packages(0)==0
 try:shared_broadcast128_packages(1,4)
 except ValueError:pass
 else:raise AssertionError('Unaligned request accepted')
 sources=[ROOT/'shared_broadcast_work.sv',ROOT/'shared_broadcast_work_tb.sv']
 with tempfile.TemporaryDirectory(prefix='broadcast-work-') as tmp:
  result=subprocess.run(['verilator','--binary','--timing','-Wno-fatal','--top-module','shared_broadcast_work_tb','--Mdir',tmp,*map(str,sources)],text=True,capture_output=True)
  (ROOT/'shared_broadcast_work_build.log').write_text(result.stdout+result.stderr)
  assert result.returncode==0,result.stdout+result.stderr
  result=subprocess.run([str(Path(tmp)/'Vshared_broadcast_work_tb')],text=True,capture_output=True)
  assert result.returncode==0 and 'PASS:10 measured masks' in result.stdout,result.stdout+result.stderr
 receipt={'all_passed':True,'source_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},'python_source_sha256':hashlib.sha256((ROOT.parent/'parameter_sweep/shared_work.py').read_bytes()).hexdigest(),'measured_development_masks':5,'measured_confirmation_masks':5,'cases':[{'mask':hex(m),'measured_packages':e} for m,e in zip(MASKS,EXPECTED)],'boundary_checks':['zero active lanes','invalid common address alignment'],'output':result.stdout,'scope':'Naturally aligned same-vector LDS128 read service work only','intrinsic_timing_parameters_identified':0,'full_gpu_integrated':False}
 (ROOT/'shared_broadcast_work_verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
 print('Shared broadcast work: Python and RTL match ten measured masks; empty and unaligned controls passed.')
if __name__=='__main__':run()
