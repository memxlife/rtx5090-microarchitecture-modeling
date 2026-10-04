from pathlib import Path
import json,subprocess,sys
E=Path(__file__).resolve().parent;D=E.parent;R=D.parent
n=int(sys.argv[1])if len(sys.argv)>1 else 2;cols=352 if n==11 else 96
saved=json.loads((R/'calibration_connected_001/aligned_cache_results.json').read_text())
src=[p for p in [str(Path(__file__).resolve().parents[2] / key) for key in saved['source_sha256']]if Path(p).name not in ['calibration_connected_tb.sv','calibration_connected_top.sv','calibration_shared_l2.sv','calibration_gemm_complete.sv']]+[str(D/x)for x in ['large_gemm_complete.sv','large_native_stage_shared.sv','large_warp_shared_read_service.sv','large_shared_read_candidate_hub.sv','large_producer_barrier_tracker.sv','large_decoded_native_issue_gate.sv','large_timing_matrix_pipeline.sv','large_timing_bf16_adapter.sv','large_timing_hmma_adapter.sv','large_u16_warp_load.sv','large_operand_staging.sv']]
with(E/f'sm_rtl_build_{n}.log').open('w')as f:
 c=subprocess.run(['verilator','--cc','--exe','--build','-j','2','-Wno-fatal','--top-module','large_gemm_complete',f'-GCONTEXTS={n}','-GM=64',f'-GN={cols}','-GK=64','-GRETURN_DELAY=28','-GMOVM_LATENCY=29','-GHMMA_LATENCY=32','-GHMMA_INTERVAL=8','--Mdir',str(E/f'build_sm_{n}'),'-CFLAGS',f'-O3 -std=c++20 -DTEST_CONTEXTS={n} -DTEST_COLUMNS={cols}',*src,str(E/'sm_rtl_host.cpp')],stdout=f,stderr=subprocess.STDOUT)
assert c.returncode==0
c=subprocess.run([str(E/f'build_sm_{n}/Vlarge_gemm_complete')]);sys.exit(c.returncode)
