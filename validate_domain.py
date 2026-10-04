"""Compile and measure the complete bounded domain, after MILP selection."""
import concurrent.futures,itertools,json,os,pathlib,statistics,subprocess,time
root=pathlib.Path(__file__).parent
solution=json.loads((root/'solution.json').read_text())
alltiles=[tuple(solution['tile'])]+[t for t in itertools.product(range(16,97,16),range(16,97,16),range(16,65,16)) if list(t)!=solution['tile']]
def compile_one(tile):
 bm,bn,bk=tile;name=f'cold_{bm}_{bn}_{bk}';cmd=['/usr/local/cuda-12.8/bin/nvcc','-O3','-arch=sm_120','-Xptxas=-v',f'-DBM={bm}',f'-DBN={bn}',f'-DBK={bk}','gemm_cold.cu','-lcublas','-o',name]
 p=subprocess.run(cmd,cwd=root,capture_output=True,text=True);(root/f'{name}.compile.log').write_text(p.stderr)
 return {'tile':tile,'executable':name,'compile_returncode':p.returncode,'compile_command':cmd,'compiler_spills':('0 bytes spill stores, 0 bytes spill loads' not in p.stderr)}
rows=[];start=time.time()
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
 # Compilation uses CPUs in parallel; GPU trials remain sequential.
 for row in pool.map(compile_one,alltiles):
  if row['compile_returncode']==0:
   p=subprocess.run([str(root/row['executable']),*map(str,solution['shape'])],env=dict(os.environ,CUDA_VISIBLE_DEVICES='7'),capture_output=True,text=True)
   row['run_returncode']=p.returncode
   if p.stdout:
    try:row.update(json.loads(p.stdout));row['latency_ms_median']=statistics.median(row['latency_ms_samples'])
    except Exception:row['error']='non-JSON result'
   if p.stderr:row['error']=p.stderr
  row['elapsed_seconds']=time.time()-start;rows.append(row);(root/'domain_validation.json').write_text(json.dumps(rows,indent=2));print(json.dumps(row),flush=True)
