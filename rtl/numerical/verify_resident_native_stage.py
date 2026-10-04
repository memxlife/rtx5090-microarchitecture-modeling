"""Verify two admitted stage contexts sharing finite execution services."""
from pathlib import Path
import hashlib,json,re,subprocess,tempfile
from verify_native_multiwarp_stage import SOURCES as BASE
from verify_numerical_matrix import no_core
ROOT=Path(__file__).resolve().parent;RTL=ROOT.parent
SOURCES=[p for p in BASE if p.name not in ['native_multiwarp_stage_pipeline.sv','native_multiwarp_stage_tb.sv']]+[RTL/'components/hardware_blocks.sv',RTL/'components/allocation_demands.sv',RTL/'components/quantized_block_admission.sv',ROOT/'resident_stage_admission.sv',ROOT/'resident_native_stage_engine.sv',ROOT/'resident_native_stage_tb.sv']
def run():
 checks=[]
 with tempfile.TemporaryDirectory(prefix='resident-stage-')as t:
  for slots in [1,2]:
   b=Path(t)/str(slots)
   c=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','resident_native_stage_tb',f'-GREAD_SLOTS={slots}','--Mdir',str(b),'-CFLAGS','-std=c++20',*map(str,SOURCES)],capture_output=True,text=True)
   (ROOT/f'resident_native_stage_build_{slots}.log').write_text(c.stdout+c.stderr);assert c.returncode==0,c.stdout+c.stderr
   r=subprocess.run([str(b/'Vresident_native_stage_tb')],capture_output=True,text=True,preexec_fn=no_core,timeout=90)
   (ROOT/f'resident_native_stage_run_{slots}.log').write_text(r.stdout+r.stderr);assert r.returncode==0,r.stdout+r.stderr
   m=re.search(r'RESIDENT_STAGE_PASS checked_words=(\d+) read_slots=(\d+)',r.stdout);assert m and tuple(map(int,m.groups()))==(4096,slots)
   assert 'RESIDENT_HELD_PROGRESS' in r.stdout
   trace=[dict(zip(['cycle','context','warp','PC'],[int(c),int(ctx),int(w),p]))for c,ctx,w,p in re.findall(r'RESIDENT_ISSUE cycle=(\d+) context=(\d+) warp=(\d+) pc=([0-9a-fA-F]+)',r.stdout)]
   assert len({x['cycle']for x in trace})==len(trace)
   checks.append({'read_slots_synthetic':slots,'checked_words':4096,'issue_trace':trace,'held_other_context_progress':True,'passed':True});print(f'PASS resident slots={slots} checked_words4096',flush=True)
 receipt={'all_passed':True,'checked_words':8192,'checks':checks,'oracle':'Distinct context-specific A17/B13 dyadic inputs and nonzeroC; direct32element dot products with globalK1536,N2112 strides.','scope':'Two preloaded native-stage lifetimes reserve two CTA-shaped resource demands; not fullCTA/grid retirement or physical resident capacity.','protocol_checks':['independent shared values and input snapshot','interleaved context instructions','held context0 response permits new context1 batch to fully drain','two allocations/eight warps retained until acknowledgment','one retirement leaves other allocation','final live block, warp and engine counts are zero; per-request demand outputs remain nonzero','reset cancels resident contexts then refill/replay'],'timing_calibrated':False,'source_sha256':{str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest()for p in SOURCES},'review':{'human_first_technical_writing':True,'undergraduate_reader_review':True}}
 (ROOT/'resident_native_stage_verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
if __name__=='__main__':run()
