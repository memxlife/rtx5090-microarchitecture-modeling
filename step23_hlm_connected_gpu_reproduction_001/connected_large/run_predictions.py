from pathlib import Path
import json,hashlib,subprocess,time,datetime,os,re,concurrent.futures
D=Path(__file__).resolve().parent;S=D.parents[1];B=S/'rtl/calibration_large_001/event_cpp';exe=B/'full_gpu_parallel'
ref=json.loads((B/'full_1536_result.json').read_text());sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
assert sha(exe)==ref['binary_sha256']
for n,h in ref['source_sha256'].items():assert sha(B/n)==h,n
shapes=[(1920,1920,1536),(1920,1920,4608),(2048,2112,4608)]
launch={'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'binary':str(exe),'binary_sha256':sha(exe),'source_sha256':ref['source_sha256'],'cpu_count':os.cpu_count(),'concurrent_jobs':3,'workers_per_job':4,'parameter_policy':'Only M,N,K change; original full-chip parameters unchanged, no rebuild or timing retuning. Calibrated small C++ model cases and the high-level performance model are separate.','cases':[{'shape':x,'argv':list(map(str,x))+ref['argv'][3:]}for x in shapes]}
(D/'launch_receipt.json').write_text(json.dumps(launch,indent=2)+'\n')
def run(shape):
 name='_'.join(map(str,shape));args=list(map(str,shape))+ref['argv'][3:];start=time.monotonic()
 with open(D/f'{name}_stdout.txt','w')as out,open(D/f'{name}_stderr.txt','w')as err:
  p=subprocess.Popen([str(exe),*args],stdout=out,stderr=err)
  (D/f'{name}_running.json').write_text(json.dumps({'pid':p.pid,'argv':args,'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()},indent=2)+'\n');rc=p.wait()
 elapsed=time.monotonic()-start;text=(D/f'{name}_stdout.txt').read_text();line=next((x for x in text.splitlines()if x.startswith('FULL_CPP_PASS')),None);counters={k:int(v)for k,v in re.findall(r'(\w+)=(\d+)',line or '')}
 result={'shape':shape,'completed_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'exit_code':rc,'host_seconds':elapsed,'argv':args,'binary_sha256':sha(exe),'source_sha256':ref['source_sha256'],'shape_instantiation':'Runtime M,N,K arguments to preserved original large-model executable; hardware/resource/timing parameters unchanged.','counters':counters,'cycles':counters.get('cycles'),'predicted_us_at2940':counters.get('cycles',0)/2940,'reference_cycles_per_us':2940,'numerical_payload_validation':False,'stdout':f'{name}_stdout.txt','stderr':f'{name}_stderr.txt'}
 for label in ['SLICE_READS','SLICE_WRITES']:
  a=next((x for x in text.splitlines()if x.startswith(label)),None);result[label.lower()]=list(map(int,a.split()[1:]))if a else None
 (D/f'{name}_result.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps({k:result[k]for k in ['shape','exit_code','host_seconds','cycles','predicted_us_at2940']}),flush=True);return result
with concurrent.futures.ThreadPoolExecutor(max_workers=3)as pool:results=list(pool.map(run,shapes))
(D/'completed_predictions.json').write_text(json.dumps({'completed_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'all_exit_zero':all(x['exit_code']==0 for x in results),'cases':results},indent=2)+'\n')
