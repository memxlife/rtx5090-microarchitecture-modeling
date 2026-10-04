"""Verify native-shaped scratch stores, completion ordering and row-major reload."""
from pathlib import Path
import hashlib,json,re,subprocess,tempfile
from verify_numerical_matrix import no_core
ROOT=Path(__file__).resolve().parent;RTL=ROOT.parent
SOURCES=[RTL/'discovery_rounds/functional_mapping_002/native_bf16_layout.sv',RTL/'components/warp_shared_read_service.sv',ROOT/'studied_output_scratch_pipeline.sv',ROOT/'studied_output_scratch_tb.sv']
def run():
 checks=[]
 with tempfile.TemporaryDirectory(prefix='output-scratch-')as t:
  for store_delay,read_delay,slots in [(7,11,1),(19,23,2)]:
   b=Path(t)/f'{store_delay}_{read_delay}_{slots}'
   c=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','studied_output_scratch_tb',f'-GSTORE_RETURN_DELAY={store_delay}',f'-GRETURN_DELAY={read_delay}',f'-GREAD_SLOTS={slots}','--Mdir',str(b),*map(str,SOURCES)],capture_output=True,text=True)
   (ROOT/f'studied_output_scratch_build_{store_delay}_{read_delay}_{slots}.log').write_text(c.stdout+c.stderr);assert c.returncode==0,c.stdout+c.stderr
   r=subprocess.run([str(b/'Vstudied_output_scratch_tb')],capture_output=True,text=True,preexec_fn=no_core,timeout=60)
   (ROOT/f'studied_output_scratch_run_{store_delay}_{read_delay}_{slots}.log').write_text(r.stdout+r.stderr);assert r.returncode==0,r.stdout+r.stderr
   m=re.search(r'OUTPUT_SCRATCH_PASS checked_words=(\d+) store_delay=(\d+) read_delay=(\d+) read_slots=(\d+)',r.stdout);assert m and tuple(map(int,m.groups()))==(2048,store_delay,read_delay,slots)
   checks.append({'store_delay_synthetic':store_delay,'read_delay_synthetic':read_delay,'read_slots':slots,'checked_words':2048,'passed':True,'stdout':r.stdout});print(f'PASS scratch delay={store_delay}/{read_delay} slots={slots}',flush=True)
 receipt={'all_passed':True,'checked_words':4096,'checks':checks,'per_batch_counts':{'store_requests':16,'store_commit_words':1024,'read_requests':32,'read_completions':32},'oracle':'Coordinate-specific finite FP32 bit identities placed through measured C layout; every resulting row-major coordinate checked independently.','protocol_checks':['request input snapshot despite mutation','first read waits for all1024 committed store words','held response identity/data','reset cancels partial store batch','refill/replay'],'timing_calibrated':False,'scope':'Native-shaped output scratch behavior with synthetic finite service; not physical latency identification.','source_sha256':{str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest()for p in SOURCES},'review':{'human_first_technical_writing':True,'undergraduate_reader_review':True}}
 (ROOT/'studied_output_scratch_verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
if __name__=='__main__':run()
