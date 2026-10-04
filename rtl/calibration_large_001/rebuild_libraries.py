from pathlib import Path
import subprocess,time
D=Path(__file__).resolve().parent;b=D/'build_k1536'
for stem in ['Vlarge_gemm_complete_9','Vlarge_slice_l2_a']:
 args=b/(stem+'__hierMkArgs.f');start=time.monotonic()
 with(D/(stem+'_rebuild.log')).open('w')as log:
  c=subprocess.run(['verilator','-f',str(args),'--build','-j','2','-CFLAGS','-O3',str(D/'large_native_stage_shared.sv'),str(D/'large_warp_shared_read_service.sv'),str(D/'large_shared_read_candidate_hub.sv'),str(Path(__file__).resolve().parent / 'large_producer_barrier_tracker.sv'),str(Path(__file__).resolve().parent / 'large_decoded_native_issue_gate.sv'),str(Path(__file__).resolve().parent / 'large_timing_matrix_pipeline.sv'),str(Path(__file__).resolve().parent / 'large_timing_bf16_adapter.sv'),str(Path(__file__).resolve().parent / 'large_timing_hmma_adapter.sv'),str(Path(__file__).resolve().parent / 'large_cg_sector_path.sv'),str(Path(__file__).resolve().parent / 'large_u16_warp_load.sv'),str(Path(__file__).resolve().parent / 'large_operand_staging.sv')],stdout=log,stderr=subprocess.STDOUT,timeout=180)
 print(stem,c.returncode,time.monotonic()-start,flush=True);assert c.returncode==0
