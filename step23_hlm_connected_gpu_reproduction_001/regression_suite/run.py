"""Immutable GPU-reference regression checks; CPU-only, never Verilog or GPU."""
from pathlib import Path
import argparse,json,hashlib,re,subprocess,sys,time,datetime,importlib.util,math
O=Path(__file__).resolve().parent; P=O.parent; R=P.parent
CPP=R/'rtl/calibration_large_001/event_cpp'; BIN=CPP/'full_gpu_parallel'; MAIN=CPP/'full_gpu_parallel.cpp'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def closure(p,seen=None):
 seen=set() if seen is None else seen
 p=p.resolve()
 if p in seen:return seen
 seen.add(p)
 for name in re.findall(r'#include\s+"([^"]+)"',p.read_text()):
  q=p.parent/name
  if q.exists():closure(q,seen)
 return seen
def identity(paths):return {str(p.relative_to(R)) if p.is_relative_to(R) else str(p):sha(p)for p in sorted(paths)}
def model_identity(kind):
 if kind=='full_cpp':return identity(closure(MAIN))
 if kind=='direct_cpp':return identity(closure(R/'step8_operand_ready_diagnosis_001/run_executor.cpp')|{R/'step8_operand_ready_diagnosis_001/freeze_prediction.py'}|{R/f'step8_operand_ready_diagnosis_001/direct_K{k}.tsv'for k in [1024,2048,3072]})
 if kind=='hlm':return identity({R/'model_components'/x for x in ['runtime_v3.py','dense_runtime.py','actual_path_parameters.json','dense_parameters.json']})
 return identity({P/'direct_highlevel'/x for x in ['predict.py','frozen_contract.json']})
def loadmodule(name,path):
 spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m

def init():
 if (O/'manifest.json').exists():return
 data=json.loads((P/'three_way_comparison.json').read_text()); cases=[]; refs=O/'references';refs.mkdir(exist_ok=True)
 for row in data['rows']:
  shape=row['shape'];cid='staged_'+'_'.join(map(str,shape));src=(P/row['implementation_receipt']).resolve();saved=refs/f'{cid}_model.json';saved.write_bytes(src.read_bytes());gpu=dict(row);gpu.pop('implementation_receipt',None);g=refs/f'{cid}_gpu.json';g.write_text(json.dumps(gpu,indent=2))
  args=json.loads(saved.read_text())['argv'];cases.append({'id':cid,'shape':shape,'kernel':'preserved diagnostic_044/050 staged32tile','gpu_us':row['repeat_measured_us'],'gpu_numeric':{'full_matrix_checks':row['full_matrix_checks'],'values_checked':row['numeric_values_checked'],'correct':row['correct']},'gpu_reference':str(g.relative_to(O)),'gpu_reference_sha256':sha(g),'old_hlm_us':row['predicted_hlm_us'],'old_cpp_us':row['implementation_us'],'cpp_model':'full_cpp','argv':args,'model_reference':str(saved.relative_to(O)),'model_reference_sha256':sha(saved),'cpp_numeric_payload':False,'output_addresses':shape[0]*shape[1]})
 confirmation=json.loads((R/'step8_direct_timing_diagnosis_001/final_confirmation_summary.json').read_text());direct=json.loads((R/'step8_operand_ready_diagnosis_001/final_timing_diagnosis.json').read_text());adapt=json.loads((P/'direct_highlevel/comparison_receipt.json').read_text());a={x['K']:x['prior_prediction_us']for x in adapt['rows']}
 for row in direct['cases']:
  k=row['K'];cid=f'direct_192_768_{k}';g=refs/f'{cid}_gpu.json';g.write_text(json.dumps(row,indent=2));cases.append({'id':cid,'shape':[192,768,k],'kernel':'original general-purpose direct kernel144blocks; recordedStep8measurements','gpu_us':row['physical_us'],'gpu_numeric':{'correct':confirmation[str(k)]['all_correct'],'scope':'Step8two-seedfullcustomoutputchecks; seeimmutableconfirmationreceipt'},'gpu_reference':str(g.relative_to(O)),'gpu_reference_sha256':sha(g),'old_hlm_us':a[k],'hlm_model':'new_provisional_direct_adaptation','old_cpp_us':row['baseline_uniform352_prediction_us'],'cpp_model':'direct_cpp','cpp_numeric_payload':False,'output_addresses':None,'kernel_identity_limit':'Historical wholeGPUexecutable hash unavailable; nativeSASSandrawtiminghashes preserved.'})
 evidence=[R/'step23_three_way_original_workloads_001/GPU/small_receipt.json',R/'step23_three_way_original_workloads_001/GPU/large_receipt.json',R/'step8_direct_timing_diagnosis_001/final_confirmation_summary.json',R/'step6_data_path_mip_001/direct.sass',R/'step15_same_cubin_pitch_001/instruction_identity_receipt.json']
 manifest={'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'reference_cycles_per_us':2940,'threshold_percent':5,'source_identities':{k:model_identity(k)for k in ['full_cpp','direct_cpp','hlm','direct_hlm']},'full_cpp_binary_path':str(BIN.relative_to(R)),'full_cpp_binary_sha256':sha(BIN),'hardware_args':'170SM48slices11contexts32sharedslots,hashed,warm,1024sets','evidence_identity':identity(set(evidence)),'cases':cases,'scope':'NoVerilog. GPUreferencesareimmutable copiedobservations; directHLMisnewpostmeasurementprovisionaladaptation, notunchangedHLM.'};(O/'manifest.json').write_text(json.dumps(manifest,indent=2))

def run_cmd(cmd,log,timeout=2400):
 st=time.perf_counter()
 with log.open('w') as handle:p=subprocess.run(cmd,stdout=handle,stderr=subprocess.STDOUT,text=True,timeout=timeout)
 if p.returncode:raise RuntimeError(f'Command failed exit{p.returncode}: {log}')
 return log.read_text(),time.perf_counter()-st

def mechanisms(build):
 records=[]
 native=build/'native_stage_test.cpp';native.write_bytes((R/'rtl/calibration_large_001/event_cpp/native_stage_test.cpp').read_bytes())
 for name,src in [('native',native),('staging',O/'staging_screen.cpp')]:
  exe=build/name;cmd=['c++','-std=c++20','-O2','-I'+str(CPP),str(src),'-o',str(exe)];run_cmd(cmd,build/f'{name}_build.log',120);out,cost=run_cmd([str(exe)],build/f'{name}_run.log',120);records.append({'name':name,'source_identity':identity(closure(src)|closure(CPP/('native_stage_event.hpp' if name=='native' else 'staging_event.hpp'))),'command':cmd,'stdout':out,'host_seconds':cost,'functional_screen_pass':True,'physical_5percent_validation':'notapplicable; thesearesourcefunctional/protocolscreens'})
 return records

def main():
 global CPP,MAIN
 runner_hash=sha(Path(__file__))
 ap=argparse.ArgumentParser();ap.add_argument('--scope',choices=['quick','full'],default='quick');ap.add_argument('--evaluate',action='store_true');ap.add_argument('--cases',help='Comma-separated exact manifest case IDs; overrides quick/full selection.');ap.add_argument('--output',default='latest.json');ap.add_argument('--cpp-source',type=Path,help='Candidate handwritten C++ main; --evaluate rebuilds separately, never uses old cached predictions.');a=ap.parse_args();init();
 if a.cpp_source:
  if not a.evaluate:raise RuntimeError('--cpp-source requires --evaluate')
  MAIN=a.cpp_source.resolve();CPP=MAIN.parent
 m=json.loads((O/'manifest.json').read_text());issues=[]
 for f,h in m['evidence_identity'].items():
  if sha(R/f)!=h:issues.append(f'GPU/sourceevidencemodified:{f}')
 for c in m['cases']:
  if sha(O/c['gpu_reference'])!=c['gpu_reference_sha256']:issues.append('immutableGPUreferencechanged:'+c['id'])
  if 'model_reference' in c:
   reference=json.loads((O/c['model_reference']).read_text())
   if sha(O/c['model_reference'])!=c['model_reference_sha256']:issues.append('cached_model_reference_changed:'+c['id'])
   if reference['argv']!=c['argv'] or reference['binary_sha256']!=m['full_cpp_binary_sha256']:issues.append('cached_configuration_or_binary_mismatch:'+c['id'])
 if issues:raise RuntimeError(';'.join(issues))
 now={k:model_identity(k)for k in m['source_identities']};same={k:now[k]==m['source_identities'][k]for k in now};binary_same=BIN.exists() and sha(BIN)==m['full_cpp_binary_sha256'];build=O/'build'/Path(a.output).stem;build.mkdir(parents=True,exist_ok=True);selected=[c for c in m['cases']if a.scope=='full'or c['id']in ['staged_128_96_12288','direct_192_768_1024']];rows=[];full_exe=BIN;direct_exe=None
 if a.cases:
  requested=set(a.cases.split(','));known={c['id']for c in m['cases']}
  if requested-known:raise RuntimeError('Unknown cases: '+','.join(sorted(requested-known)))
  selected=[c for c in m['cases']if c['id']in requested]
 if a.evaluate and not(same['full_cpp']and binary_same):
  full_exe=build/'full_cpp_current';run_cmd(['c++','-std=c++20','-O3','-pthread',str(MAIN),'-o',str(full_exe)],build/'full_cpp_build.log',240)
 for c in selected:
  row={'id':c['id'],'shape':c['shape'],'GPU_us':c['gpu_us'],'gpu_numeric':c['gpu_numeric'],'old_hlm_us':c['old_hlm_us'],'old_cpp_us':c['old_cpp_us'],'CPP_kind':c['cpp_model'],'cpp_numeric_payload':False};st=time.perf_counter();k=c['shape'][2];domain='hlm'if c['cpp_model']=='full_cpp'else'direct_hlm';valid=same[c['cpp_model']]and(domain!='direct_hlm'or same[domain])and(c['cpp_model']!='full_cpp'or binary_same)
  if not valid and not a.evaluate:row['CPP_evaluation']='stale_model_identity_no_cached_prediction'
  if c['cpp_model']=='full_cpp':
   if True:
    mod=loadmodule('hlm',R/'model_components'/('runtime_v3.py'if c['shape'][0]==128 else'dense_runtime.py'));row['new_hlm_us']=mod.predict_us(32,32,*c['shape'],**({'warm':True,'single_block':False}if c['shape'][0]==128 else{}))['predicted_us']
   if valid:
    row['new_cpp_us']=c['old_cpp_us'];row['CPP_evaluation']='identity_verified_cached_complete_execution';ref=json.loads((O/c['model_reference']).read_text());row['address_coverage']=ref.get('checked',ref.get('counters',{}).get('checked',ref.get('repeat_counters',{}).get('checked')));row['address_coverage_expected']=c['output_addresses']
   elif a.evaluate:
    out,cost=run_cmd([str(full_exe),*c['argv']],build/(c['id']+'.log'));match=re.search(r'FULL_CPP_PASS.*cycles=(\d+) checked=(\d+)',out)
    if not match:raise RuntimeError('Incomplete model run:'+c['id'])
    row.update(new_cpp_us=int(match[1])/2940,address_coverage=int(match[2]),address_coverage_expected=c['output_addresses'],CPP_evaluation='fresh_current_source_execution',CPP_host_seconds=cost)
  else:
   if True:
    out,_=run_cmd([sys.executable,str(P/'direct_highlevel/predict.py')],build/'direct_hlm.log',120);row['new_hlm_us']=next(x['prior_prediction_us']for x in json.loads(out)if x['K']==k)
   if valid:row.update(new_cpp_us=c['old_cpp_us'],CPP_evaluation='identity_verified_frozen_instruction_plus_Python_prediction')
   elif a.evaluate:
    if a.scope=='quick':
     row['status']='changed_direct_model_deferred_to_full_evaluation';rows.append(row);continue
    if direct_exe is None:
     direct_exe=build/'instruction_current';run_cmd(['c++','-std=c++20','-O2',str(R/'step8_operand_ready_diagnosis_001/run_executor.cpp'),'-o',str(direct_exe)],build/'instruction_build.log',120)
    out,cost=run_cmd([str(direct_exe),str(R/f'step8_operand_ready_diagnosis_001/direct_K{k}.tsv'),'352','352',str(build/f'direct_{k}.events'),'1','1'],build/f'direct_{k}.log',120);cycles=int(out.split()[0]);row.update(new_cpp_us=max(cycles+7607,7607+math.ceil(144*(k//32)*128/48))/2940,CPP_evaluation='fresh_C++instruction_plus_Python_phase_execution',CPP_host_seconds=cost)
  for model in ['hlm','cpp']:
   if f'new_{model}_us'in row:
    err=100*(row[f'new_{model}_us']/c['gpu_us']-1);old=100*(c[f'old_{model}_us']/c['gpu_us']-1);row[f'{model}_signed_error_percent']=err;row[f'{model}_within_5percent']=abs(err)<=5;row[f'{model}_regressed']=abs(err)>abs(old)+1e-8
  row['host_seconds']=time.perf_counter()-st;row['status']='evaluated' if 'new_cpp_us' in row else 'HLM_evaluated_CPP_unavailable';rows.append(row)
 after={k:model_identity(k) for k in now}
 if after!=now:raise RuntimeError('Model sources changed during evaluation; no result accepted')
 result={'scope':a.scope,'requested_cases':a.cases,'candidate_cpp_source':str(MAIN),'current_source_identity':now,'evaluate_requested':a.evaluate,'source_identity_match':same,'full_cpp_binary_match':binary_same,'evaluated_full_cpp_binary_sha256':sha(full_exe) if full_exe.exists() else None,'suite_sha256':runner_hash,'rows':rows,'mechanisms':mechanisms(build)if a.evaluate else'notexecuted_replay_only','correction_accepted':False,'acceptance_policy':'Neverautomatic: focusedcasewithin5%, relevantold/newregressionsnotworse, physicalnumericsvalid, no source/cacheidentitygap. Baselinefailures remainfailures.','no_GPU_or_Verilog_execution':True};(O/a.output).write_text(json.dumps(result,indent=2));print(json.dumps({'output':str(O/a.output),'rows':[{k:v for k,v in r.items()if k in ['id','status','hlm_signed_error_percent','cpp_signed_error_percent','hlm_within_5percent','cpp_within_5percent']}for r in rows],'identity_match':same,'mechanisms':len(result['mechanisms'])if a.evaluate else 0},indent=2))
if __name__=='__main__':main()
