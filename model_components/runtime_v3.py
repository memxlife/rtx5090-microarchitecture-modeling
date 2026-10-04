"""Independent actual-path calibration, not a fitted full GEMM correction.

Stage1 includes actual global staging and common loop/barriers; stage2
includes operand computation and common work; stage0 measures common work.
The subtraction avoids counting common work twice. This is a tested
composition hypothesis under bounded conditions, not an intrinsic ISA model.
"""
import json
from pathlib import Path

def predict_us(bm,bn,m,n,k,*,warm=True,single_block=True):
    if (bm,bn) not in [(32,32),(64,48)] or (m,n)!=(128,96) or not 8192<=k<=73728 or k%32:
        raise ValueError('Unvalidated actual-path tile, matrix layout or cache context')
    d=json.loads(Path(__file__).with_name('actual_path_parameters.json').read_text())
    costs=d[f'tile_{bm}_{bn}']
    slope=costs['1']['stage_us']+costs['2']['stage_us']-costs['0']['stage_us']
    fixed=costs['1']['fixed_us']+costs['2']['fixed_us']-costs['0']['fixed_us']
    if not warm:
        # Independent global-response cold-minus-ready penalty, frozen before validation.
        slope += (4 if bm==32 else 7)*d['cache_penalty_per_group_us']
    return {'predicted_us':fixed+k/32*slope,'stage_us':slope,'fixed_us':fixed,
            'blocks':1 if single_block else (m//bm)*(n//bn),
            'calibration':'isolated actual paths; no full-GEMM coefficients',
            'model':'actual_path_v3',
            'unresolved':['precise latency origin inside staging path','cross-block transfer beyond tested grid','mixed cache states','broader workloads'],
            'full_microarchitecture_model_complete':False}

def predict_increment_us(bm,bn,m,n,k0,k1,**kwargs):
    if k1<=k0:raise ValueError('Ordered reduction lengths required')
    a=predict_us(bm,bn,m,n,k0,**kwargs);b=predict_us(bm,bn,m,n,k1,**kwargs)
    return dict(b,predicted_increment_us=b['predicted_us']-a['predicted_us'])
