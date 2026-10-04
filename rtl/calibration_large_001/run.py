from pathlib import Path
import json,subprocess,time,sys,hashlib
D=Path(__file__).resolve().parent;R=D.parent
smoke='--smoke' in sys.argv
sms,contexts,slices,sets,m,n,k=(2,2,2,4,64,96,64)if smoke else(170,11,48,1024,2048,2112,int(sys.argv[1])if len(sys.argv)>1 else 1536)
saved=json.loads((R/'calibration_connected_001/aligned_cache_results.json').read_text())
src=[p for p in [str(Path(__file__).resolve().parents[1] / key) for key in saved['source_sha256']]if Path(p).name not in ['calibration_connected_tb.sv','calibration_connected_top.sv','calibration_shared_l2.sv','calibration_gemm_complete.sv']]+[str(D/'large_slice_l2.sv'),str(D/'large_connected_top.sv'),str(D/'large_gemm_complete.sv'),str(D/'large_native_stage_shared.sv'),str(D/'large_warp_shared_read_service.sv'),str(D/'large_shared_read_candidate_hub.sv'),str(Path(__file__).resolve().parent / 'large_producer_barrier_tracker.sv'),str(Path(__file__).resolve().parent / 'large_decoded_native_issue_gate.sv'),str(Path(__file__).resolve().parent / 'large_timing_matrix_pipeline.sv'),str(Path(__file__).resolve().parent / 'large_timing_bf16_adapter.sv'),str(Path(__file__).resolve().parent / 'large_timing_hmma_adapter.sv'),str(Path(__file__).resolve().parent / 'large_cg_sector_path.sv'),str(Path(__file__).resolve().parent / 'large_u16_warp_load.sv'),str(Path(__file__).resolve().parent / 'large_operand_staging.sv')]
b=D/('build_smoke'if smoke else f'build_k{k}');b.mkdir(exist_ok=True)
start=time.monotonic()
cmd=['verilator','--cc','--hierarchical','--inline-mult','0','--unroll-count','1','--timing','--exe','--build','-j','2','-Wno-fatal','--top-module','large_connected_top',f'-GSMS={sms}',f'-GCONTEXTS={contexts}',f'-GSLICES={slices}',f'-GL2_SETS={sets}',f'-GM={m}',f'-GN={n}',f'-GK={k}','-GRETURN_DELAY=28','-GMOVM_LATENCY=29','-GHMMA_LATENCY=32','-GHMMA_INTERVAL=8','--Mdir',str(b),'-CFLAGS',f'-O3 -std=c++20 -DMATRIX_M={m} -DMATRIX_N={n} -DMATRIX_K={k} -DCACHE_SLICES={slices}',*src,str(D/'host.cpp')]
with (D/('smoke_build.log'if smoke else f'build_k{k}.log')).open('w')as log:
 c=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,timeout=900)
assert c.returncode==0,'Build failed; inspect log'
build_seconds=time.monotonic()-start;print('BUILD_DONE',build_seconds,flush=True)
start=time.monotonic()
with (D/('smoke_run.log'if smoke else f'run_k{k}.log')).open('w')as log:
 c=subprocess.run([str(b/'Vlarge_connected_top')],stdout=log,stderr=subprocess.STDOUT,timeout=1800)
receipt={'smoke':smoke,'M':m,'N':n,'K':k,'sms':sms,'contexts':contexts,'slices':slices,'build_seconds':build_seconds,'run_seconds':time.monotonic()-start,'returncode':c.returncode,'source_sha256':{p:hashlib.sha256(Path(p).read_bytes()).hexdigest()for p in src+[str(D/'host.cpp')]},'hardware_timing_validated':False}
(D/('smoke_receipt.json'if smoke else f'receipt_k{k}.json')).write_text(json.dumps(receipt,indent=2)+'\n')
print({k:v for k,v in receipt.items()if k!="source_sha256"},flush=True);assert c.returncode==0,'Simulation failed; inspect log'
