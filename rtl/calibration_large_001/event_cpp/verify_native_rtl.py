import subprocess,sys
from pathlib import Path
n=int(sys.argv[1]) if len(sys.argv)>1 else 1
e=Path(__file__).resolve().parent;d=e.parent;r=d.parent
src=[r/'discovery_rounds/native_barrier_015/native_control_decode.sv',r/'discovery_rounds/functional_mapping_002/native_bf16_layout.sv',r/'numerical/native_studied_stage_schedule.sv',r/'numerical/library_movm_permutation.sv',r/'numerical/native_movm_word_pipeline.sv']+[d/x for x in ['large_producer_barrier_tracker.sv','large_decoded_native_issue_gate.sv','large_native_stage_shared.sv','large_warp_shared_read_service.sv','large_timing_matrix_pipeline.sv','large_timing_bf16_adapter.sv','large_timing_hmma_adapter.sv']]+[e/'native_component_top.sv']
with (e/'native_rtl_build.log').open('w')as f:
 ret=subprocess.run(['verilator','--cc','--exe','--build','-j','2','-Wno-fatal','--top-module','native_component_top','--Mdir',str(e/f'build_native_{n}'),f'-GCONTEXTS={n}','-CFLAGS',f'-O3 -std=c++20 -DTEST_CONTEXTS={n}',*map(str,src),str(e/'native_rtl_host.cpp')],stdout=f,stderr=subprocess.STDOUT)
print(ret.returncode)
if ret.returncode==0:subprocess.run([str(e/f'build_native_{n}/Vnative_component_top')])
