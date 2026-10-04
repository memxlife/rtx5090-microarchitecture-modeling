"""Read-only replay of six saved high-level model predictions."""
from pathlib import Path
import sys,json
R=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(R/'model_components'))
import runtime_v3,dense_runtime
out=[]
for e in json.loads((R/'diagnostic_044/frozen_absolute_and_multi_predictions.json').read_text())['checks']:
    if e['single']:continue
    p=runtime_v3.predict_us(32,32,128,96,e['k'],warm=True,single_block=False)['predicted_us']
    assert p==e['predicted_us']
    out.append({'shape':[128,96,e['k']],'prediction_us':p,'exact_saved_prediction':True})
for e in json.loads((R/'diagnostic_050/frozen_predictions.json').read_text())['checks']:
    p=dense_runtime.predict_us(32,32,e['m'],e['n'],e['k'])['predicted_us']
    assert p==e['predicted_us']
    out.append({'shape':[e['m'],e['n'],e['k']],'prediction_us':p,'exact_saved_prediction':True})
print(json.dumps(out,indent=2))
