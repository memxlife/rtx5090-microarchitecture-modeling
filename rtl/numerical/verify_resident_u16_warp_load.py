"""Check two load contexts using one shared cache and an address-defined oracle."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
from verify_numerical_matrix import no_core
ROOT=Path(__file__).resolve().parent; RTL=ROOT.parent
SOURCES=[RTL/'components/sector_read_cache.sv',ROOT/'resident_u16_warp_load.sv',ROOT/'resident_u16_warp_load_tb.sv']
def run():
 source_hashes={str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCES}
 with tempfile.TemporaryDirectory(prefix='resident-u16-') as tmp:
  c=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','resident_u16_warp_load_tb','--Mdir',tmp,*map(str,SOURCES)],capture_output=True,text=True)
  (ROOT/'resident_u16_build.log').write_text(c.stdout+c.stderr);assert c.returncode==0,c.stdout+c.stderr
  r=subprocess.run([str(Path(tmp)/'Vresident_u16_warp_load_tb')],capture_output=True,text=True,preexec_fn=no_core,timeout=30)
  (ROOT/'resident_u16_run.log').write_text(r.stdout+r.stderr)
  assert r.returncode==0 and 'RESIDENT_U16_PASS checked_lane_values=128 backing_misses=2' in r.stdout,r.stdout+r.stderr
 assert source_hashes=={str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCES}, 'Sources changed during verification'
 receipt={'all_passed':True,'checked_lane_values':128,'backing_misses_after_reset':2,'checks':['two independently snapshotted contexts','inactive lanes and empty mask','repeated and shared sectors reuse one cache','delayed matching backing response','held response while other context progresses','reset cancels loader and provider','accepted-minus-retired conservation'],'oracle':'Each active halfword is 0x5000 XOR the original accepted byte address divided by two; inactive lanes are zero.','scope':'Two-context component behavior with one blocking sector cache; not full CTA behavior or measured GPU throughput.','reset_contract':'Provider flushes pre-reset responses; contents are immutable until cache reset.','timing_calibrated':False,'source_sha256':source_hashes,'review':{'human_first_technical_writing':True,'undergraduate_reader_review':True}}
 (ROOT/'resident_u16_verification.json').write_text(json.dumps(receipt,indent=2)+'\n');print('PASS resident U16: 128 lane checks')
if __name__=='__main__':run()
