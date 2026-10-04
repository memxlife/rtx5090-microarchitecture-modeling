import json,statistics,math,sys,copy
from pathlib import Path
from scipy.stats import spearmanr
from solve_revision import evaluate
sys.path.insert(0,str(Path(__file__).parent.parent));from solve import evaluate as old_evaluate
ROOT=Path(__file__).parent;model=json.loads((ROOT/'model.json').read_text());rows=[json.loads(l) for l in (ROOT/'confirmation.jsonl').read_text().splitlines()];(ROOT/'confirmation.json').write_text(json.dumps(rows,indent=2));results=[]
for shape in json.loads((ROOT/'contract.json').read_text())['confirmation_shapes']:
 subset=[r for r in rows if r['shape']==shape];bytile={tuple(r['tile']):r for r in subset};best=min(subset,key=lambda r:r['latency_ms_median']);rev=json.loads((ROOT/('solution_'+'_'.join(map(str,shape))+'.json')).read_text());old=json.loads((ROOT/('baseline_solution_'+'_'.join(map(str,shape))+'.json')).read_text())
 actual=[r['latency_ms_median'] for r in subset];pred=[evaluate(shape,r['tile'],model)['predicted_ms'] for r in subset];oldpred=[old_evaluate(shape,r['tile'],old['bandwidth_B_s'],old['effective_flops_s']) for r in subset]
 item={'shape':shape,'tested_tiles':len(subset),'correct_tiles':sum(r['correct'] for r in subset),'best_tile':best['tile'],'best_ms':best['latency_ms_median'],'new_tile':rev['tile'],'new_ms':bytile[tuple(rev['tile'])]['latency_ms_median'],'old_tile':old['tile'],'old_ms':bytile[tuple(old['tile'])]['latency_ms_median'],'new_predicted_ms':rev['predicted_ms'],'solve_seconds':rev['solve_seconds'],'new_spearman':float(spearmanr(pred,actual).statistic),'old_spearman':float(spearmanr(oldpred,actual).statistic),'new_median_relative_error':statistics.median(abs(p-a)/a for p,a in zip(pred,actual)),'old_median_relative_error':statistics.median(abs(p-a)/a for p,a in zip(oldpred,actual))}
 item['new_regret']=item['new_ms']/item['best_ms']-1;item['old_regret']=item['old_ms']/item['best_ms']-1
 ablations=[]
 for mode in ['remove_serial_path','remove_wave_stage','remove_resident_tensor_latency']:
  modified=copy.deepcopy(model)
  if mode=='remove_serial_path':modified['serial_coefficients']=[0]*6
  elif mode=='remove_wave_stage':modified['aggregate_coefficients'][1]=0
  else:modified['aggregate_coefficients'][3]=0
  chosen=min(subset,key=lambda r:evaluate(shape,r['tile'],modified)['predicted_ms']);ablations.append({'removed_term':mode,'tile':chosen['tile'],'measured_ms':chosen['latency_ms_median'],'regret':chosen['latency_ms_median']/item['best_ms']-1})
 item['ablations']=ablations;results.append(item)
(ROOT/'results.json').write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2))
