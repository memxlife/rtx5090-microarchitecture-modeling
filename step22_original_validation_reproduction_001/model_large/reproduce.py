from pathlib import Path
import json, hashlib, subprocess, time, datetime, os, re
D=Path(__file__).resolve().parent
S=D.parents[1]; B=S/'rtl/calibration_large_001/event_cpp'; exe=B/'full_gpu_parallel'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
refs={k:json.loads((B/f'full_{k}_result.json').read_text())for k in [1536,3072]}
for r in refs.values():
 assert sha(exe)==r['binary_sha256']
 for n,h in r['source_sha256'].items():assert sha(B/n)==h,(n,sha(B/n),h)
receipt={'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'binary':str(exe),'binary_sha256':sha(exe),'source_sha256':refs[1536]['source_sha256'],'cpu_count':os.cpu_count(),'mode':'two concurrent preserved executable runs; no rebuild or parameter change','cases':[]}
(D/'launch_receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
procs=[]
for k,r in refs.items():
 out=open(D/f'K{k}_stdout.txt','w');err=open(D/f'K{k}_stderr.txt','w'); t=time.monotonic();p=subprocess.Popen([str(exe),*r['argv']],stdout=out,stderr=err)
 procs.append((k,p,out,err,t));receipt['cases'].append({'K':k,'argv':r['argv'],'pid':p.pid,'original_cycles':r['cycles']})
(D/'launch_receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
for k,p,o,e,t in procs:
 rc=p.wait();o.close();e.close(); text=(D/f'K{k}_stdout.txt').read_text(); errs=(D/f'K{k}_stderr.txt').read_text();r=refs[k]
 result={'K':k,'completed_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'exit_code':rc,'host_seconds':time.monotonic()-t,'binary_sha256':sha(exe),'argv':r['argv'],'original_cycles':r['cycles'],'stdout':f'K{k}_stdout.txt','stderr':f'K{k}_stderr.txt'}
 matches=re.findall(r'PROGRESS cycles=(\d+).*?completed=(\d+).*?checked=(\d+).*?native=(\d+)',text+'\n'+errs)
 result['last_progress']=matches[-1] if matches else None
 (D/f'K{k}_repeat_receipt.json').write_text(json.dumps(result,indent=2)+'\n')
 print(json.dumps(result),flush=True)
