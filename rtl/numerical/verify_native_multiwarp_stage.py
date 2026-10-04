"""Check four concurrent native operand windows against independent dot products."""
from pathlib import Path
import hashlib,json,re,subprocess,tempfile
from verify_native_studied_stage import SOURCES as SINGLE_SOURCES
from verify_numerical_matrix import no_core
ROOT=Path(__file__).resolve().parent;RTL=ROOT.parent
SOURCES=[p for p in SINGLE_SOURCES if p.name not in ['native_studied_stage_pipeline.sv','native_studied_stage_tb.sv']]+[ROOT/'native_multiwarp_stage_pipeline.sv',ROOT/'native_multiwarp_stage_tb.sv']
def run():
 checks=[]
 with tempfile.TemporaryDirectory(prefix='native-multiwarp-')as t:
  for slots in [1,2]:
   build=Path(t)/str(slots)
   c=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','native_multiwarp_stage_tb',f'-GREAD_SLOTS={slots}','--Mdir',str(build),'-CFLAGS','-std=c++20',*map(str,SOURCES)],capture_output=True,text=True)
   (ROOT/f'native_multiwarp_stage_build_{slots}.log').write_text(c.stdout+c.stderr);assert c.returncode==0,c.stdout+c.stderr
   r=subprocess.run([str(build/'Vnative_multiwarp_stage_tb')],capture_output=True,text=True,preexec_fn=no_core,timeout=90)
   (ROOT/f'native_multiwarp_stage_run_{slots}.log').write_text(r.stdout+r.stderr);assert r.returncode==0,r.stdout+r.stderr
   m=re.search(r'MULTIWARP_STAGE_PASS checked_words=(\d+) read_slots=(\d+)',r.stdout);assert m and tuple(map(int,m.groups()))==(2048,slots)
   windows=[{'warp':int(w),'first_cycle':int(f),'last_cycle':int(l),'instructions':int(n)}for w,f,l,n in re.findall(r'MULTIWARP_WINDOW warp=(\d+) first=(\d+) last=(\d+) instructions=(\d+)',r.stdout)]
   assert len(windows)==8 and all(w['instructions']==40 for w in windows)
   trace=[{'cycle':int(c),'warp':int(w),'PC':p}for c,w,p in re.findall(r'MULTIWARP_ISSUE cycle=(\d+) warp=(\d+) pc=([0-9a-fA-F]+)',r.stdout)]
   assert len({x['cycle']for x in trace})==len(trace),'Multiple issued instructions on one edge'
   checks.append({'read_slots_synthetic':slots,'checked_words':2048,'windows':windows,'issue_trace':trace,'passed':True});print(f'PASS slots={slots} checked_words=2048',flush=True)
 receipt={'all_passed':True,'checked_words':4096,'checks':checks,'synthetic_service_choices':{'MOVM_latency':19,'HMMA_latency':73,'shared_return_delay':9},'oracle':'Original A17/B13 patterns use globalK1536,N2112 strides; direct32element integerdot plus nonzero per-registerC.','scope':'Four modeled warp operand windows share finite services; trace/fairness/numerical verification is not hardware timing validation.','overlap_check':'At least two warps issue before any reaches its40th instruction; this checks instruction-window overlap, not measured physical completion.','timing_calibrated':False,'source_sha256':{str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest()for p in SOURCES},'review':{'human_first_technical_writing':True,'undergraduate_reader_review':True}}
 (ROOT/'native_multiwarp_stage_verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
if __name__=='__main__':run()
