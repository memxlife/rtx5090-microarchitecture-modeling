import json,pathlib,subprocess,os,statistics,itertools,time
root=pathlib.Path(__file__).parent;old=root.parent;contract=json.loads((root/'contract.json').read_text());rows=[];start=time.time()
for shape in contract['confirmation_shapes']:
 selected=json.loads((root/('solution_'+'_'.join(map(str,shape))+'.json')).read_text())['tile'];tiles=[tuple(selected)]+[t for t in itertools.product(range(16,97,16),range(16,97,16),range(16,65,16)) if list(t)!=selected]
 for tile in tiles:
  name='cold_'+'_'.join(map(str,tile));p=subprocess.run([str(old/name),*map(str,shape)],capture_output=True,text=True,env=dict(os.environ,CUDA_VISIBLE_DEVICES='7'))
  if p.returncode:raise RuntimeError(p.stderr)
  r=json.loads(p.stdout);r['latency_ms_median']=statistics.median(r['latency_ms_samples']);r['elapsed_seconds']=time.time()-start;rows.append(r);(root/'confirmation.json').write_text(json.dumps(rows,indent=2));print(json.dumps(r),flush=True)
