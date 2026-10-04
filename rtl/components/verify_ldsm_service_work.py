"""Check inferred LDSM service packages against retained hardware profiles."""
from pathlib import Path
import json,hashlib,subprocess,tempfile,sys
ROOT=Path(__file__).resolve().parent
sys.path.insert(0,str(ROOT.parent/'parameter_sweep'))
from shared_work import ldsm_packages
def addresses(transpose,pattern):
 if pattern==1:return [(512 if transpose else 384)*(lane&15)+16*((lane&7)^(lane>>4)) for lane in range(32)]
 if pattern==2:return [128*lane for lane in range(32)]
 if pattern==3:return [16*(lane%8) for lane in range(32)]
 return [16*lane for lane in range(32)]
def run():
 d=json.loads((ROOT.parent/'parameter_sweep/ldsm_service/analysis.json').read_text());assert d['all_predictions_match'];rows=[];widths=[];expected=[]
 for case in d['cases']:
  a=addresses(case['transpose'],case['pattern']);assert ldsm_packages(a,case['width'])==case['packages_per_instruction']
  rows.extend(a);widths.append(case['width']);expected.append(int(case['packages_per_instruction']))
 sources=[ROOT/'ldsm_service_work.sv',ROOT/'ldsm_service_work_tb.sv']
 with tempfile.TemporaryDirectory(prefix='ldsm-work-') as tmp:
  tmp=Path(tmp);v=tmp/'vectors';v.mkdir()
  for name,values in [('rows',rows),('widths',widths),('expected',expected)]:(v/(name+'.hex')).write_text(''.join(f'{x:08x}\n' for x in values))
  result=subprocess.run(['verilator','--binary','--timing','-Wno-fatal','--top-module','ldsm_service_work_tb','--Mdir',str(tmp/'build'),*map(str,sources)],text=True,capture_output=True);(ROOT/'ldsm_service_work_build.log').write_text(result.stdout+result.stderr);assert result.returncode==0,result.stdout+result.stderr
  result=subprocess.run([str(tmp/'build/Vldsm_service_work_tb'),f'+vectors={v}'],text=True,capture_output=True);assert result.returncode==0 and 'PASS:24 measured' in result.stdout,result.stdout+result.stderr
 receipt={'all_passed':True,'measured_configurations':24,'source_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},'python_source_sha256':hashlib.sha256((ROOT.parent/'parameter_sweep/shared_work.py').read_bytes()).hexdigest(),'output':result.stdout,'scope':'Aligned all-lane LDSM service work; group boundaries do not merge','intrinsic_timing_identified':False,'full_GPU_integrated':False,'within_group_duplicate_row_rule':'inferred; fresh confirmation pending'}
 (ROOT/'ldsm_service_work_verification.json').write_text(json.dumps(receipt,indent=2)+'\n');print('LDSM service work: Python and RTL match24 measured configurations; invalid alignment/width rejected.')
if __name__=='__main__':run()
