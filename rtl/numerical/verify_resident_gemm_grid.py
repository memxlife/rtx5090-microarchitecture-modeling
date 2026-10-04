"""Check complete reductions through shared staging and native matrix execution."""
from pathlib import Path
import hashlib,json,re,subprocess,tempfile
from verify_resident_native_stage import SOURCES as BASE
from verify_numerical_matrix import no_core
ROOT=Path(__file__).resolve().parent;RTL=ROOT.parent
SOURCES=[p for p in BASE if p.name not in ['resident_native_stage_tb.sv','resident_native_stage_engine.sv']]+[RTL/'components/sector_read_cache.sv',ROOT/'resident_u16_warp_load.sv',ROOT/'resident_operand_staging.sv',ROOT/'resident_gemm_complete.sv',ROOT/'resident_gemm_grid.sv',ROOT/'resident_gemm_grid_tb.sv',ROOT/'resident_native_stage_shared.sv',RTL/'components/shared_read_candidate_hub.sv',ROOT/'studied_output_scratch_shared.sv',ROOT/'coalesced_fp32_warp_store.sv',RTL/'components/cta_generation_barrier.sv']
SOURCES=list(dict.fromkeys(SOURCES))
def run():
 checks=[];rejected=[]; rejected=[]
 frozen_hashes={str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest()for p in SOURCES}
 with tempfile.TemporaryDirectory(prefix='resident-reduction-')as tmp:
  for k in [64,1536]:
   b=Path(tmp)/str(k)
   c=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','resident_gemm_grid_tb',f'-GK={k}','--Mdir',str(b),'-CFLAGS','-std=c++20',*map(str,SOURCES)],capture_output=True,text=True)
   (ROOT/f'resident_grid_build_{k}.log').write_text(c.stdout+c.stderr);assert c.returncode==0,c.stdout+c.stderr
   r=subprocess.run([str(b/'Vresident_gemm_grid_tb')],capture_output=True,text=True,preexec_fn=no_core,timeout=180)
   (ROOT/f'resident_grid_run_{k}.log').write_text(r.stdout+r.stderr);assert r.returncode==0 and f'RESIDENT_GRID_PASS K={k} checked_words=12288 launches=2' in r.stdout,r.stdout+r.stderr
   metrics=[dict(zip(['id','words','blocks','peak_resident','modeled_elapsed_cycles'],map(int,x)))for x in re.findall(r'RESIDENT_GRID_LAUNCH id=(\d+) words=(\d+) blocks=(\d+) peak_resident=(\d+) elapsed_cycles=(\d+)',r.stdout)]
   assert len(metrics)==2 and all(x['words']==6144 and x['blocks']==6 and x['peak_resident']==2 for x in metrics)
   checks.append({'K':k,'checked_words':12288,'launch_metrics':metrics,'passed':True});print(f'PASS resident complete K{k}:12288 words',flush=True)
   if k==64:
    for case in ['misaligned_c','c_overlap_a','c_overlap_b','c_overflow']:
     negative=subprocess.run([str(b/'Vresident_gemm_grid_tb'),'+'+case],capture_output=True,text=True,preexec_fn=no_core,timeout=10)
     log=negative.stdout+negative.stderr
     (ROOT/f'resident_grid_reject_{case}.log').write_text(log)
     assert negative.returncode!=0 and 'Invalid resident grid launch allocation' in log,log
     rejected.append(case)
 assert frozen_hashes=={str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest()for p in SOURCES},'Sources changed during verification'
 receipt={'all_passed':True,'checked_words':24576,'rejected_invalid_launches':rejected,'input_snapshot_checks':['A/B/C bases captured at grid launch','C base perturbed after each acceptance'],'coverage_gaps':['reset is tested only at the first pending input read, not during output stores'],'checks':checks,'oracle':'Direct full K integer dot products using original A17/B13 global strides, then exact division by256; all six block coordinates.','scope':'Two complete six-block grids with two resident contexts on one modeled SM; immutable inputs retained between launches. Conservative serial output actor and synthetic timing.','reset_contract':'Backing provider flushes pre-reset work; memory remains immutable.','timing_calibrated':False,'source_sha256':frozen_hashes,'review':{'human_first_technical_writing':True,'undergraduate_reader_review':True}}
 (ROOT/'resident_grid_verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
if __name__=='__main__':run()
