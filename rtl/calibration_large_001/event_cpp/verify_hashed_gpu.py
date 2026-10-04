from pathlib import Path
import json,subprocess,sys,time
E=Path(__file__).resolve().parent;D=E.parent;R=D.parent;slots=int(sys.argv[1])if len(sys.argv)>1 else 2;H=E/('hashed_rtl'if slots==2 else f'hashed_rtl_slots{slots}');H.mkdir(exist_ok=True)
top=(D/'large_connected_top.sv').read_text().replace('large_slice_l2 #','hashed_slice_l2 #')
for field in ['read_req_byte_address[sm]','write_req_byte_address[sm]']:
 top=top.replace(f'(({field}>>7)%SLICES==sl)',f'((({field}>>7)^({field}>>14)^({field}>>20))%SLICES==sl)')
(H/'hashed_connected_top.sv').write_text('// Provisional XOR address-routing hypothesis; not recovered NVIDIA mapping.\n'+top)
cache=(D/'large_slice_l2.sv').read_text().replace('module large_slice_l2 #','module hashed_slice_l2 #').replace("read_req_byte_address[sm]/32'(128*L2_SETS*SET_STRIDE)",'read_req_byte_address[sm]>>7')
(H/'hashed_slice_l2.sv').write_text('// Full-line tag required by provisional XOR routing; physical mapping unidentified.\n'+cache)
saved=json.loads((R/'calibration_connected_001/aligned_cache_results.json').read_text())
src=[p for p in [str(Path(__file__).resolve().parents[2] / key) for key in saved['source_sha256']]if Path(p).name not in ['calibration_connected_tb.sv','calibration_connected_top.sv','calibration_shared_l2.sv','calibration_gemm_complete.sv']]+[str(D/x)for x in ['large_gemm_complete.sv','large_native_stage_shared.sv','large_warp_shared_read_service.sv','large_shared_read_candidate_hub.sv','large_producer_barrier_tracker.sv','large_decoded_native_issue_gate.sv','large_timing_matrix_pipeline.sv','large_timing_bf16_adapter.sv','large_timing_hmma_adapter.sv','large_u16_warp_load.sv','large_operand_staging.sv']]+[str(H/'hashed_connected_top.sv'),str(H/'hashed_slice_l2.sv')]
with(H/'build.log').open('w')as f:
 c=subprocess.run(['verilator','--cc','--exe','--build','-j','2','-Wno-fatal','--top-module','large_connected_top','-GSMS=2','-GCONTEXTS=2','-GSLICES=2','-GL2_SETS=4','-GL2_WAYS=16','-GM=64','-GN=96','-GK=64',f'-GREAD_SLOTS={slots}','-GRETURN_DELAY=28','-GMOVM_LATENCY=29','-GHMMA_LATENCY=32','-GHMMA_INTERVAL=8','--Mdir',str(H/'build'),'-CFLAGS','-O3 -std=c++20 -DMATRIX_M=64 -DMATRIX_N=96 -DMATRIX_K=64 -DCACHE_SLICES=2',*src,str(D/'host.cpp')],stdout=f,stderr=subprocess.STDOUT)
assert c.returncode==0
with(H/'run.log').open('w')as f:c=subprocess.run([str(H/'build/Vlarge_connected_top')],stdout=f,stderr=subprocess.STDOUT)
assert c.returncode==0
print((H/'run.log').read_text())
