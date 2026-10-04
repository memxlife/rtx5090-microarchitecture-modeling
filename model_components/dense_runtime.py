"""Bounded latency/service composition derived from isolated phases.

No full GEMM runtime is used as a coefficient. Reservation controls may also
change the L1/shared partition; intrinsic resource ownership is unresolved.
"""
import json,math
from pathlib import Path

def predict_us(bm,bn,m,n,k,*,resident_blocks=None):
    if (bm,bn) not in [(32,32),(64,48)] or (m,n) not in [(1920,1920),(2048,2112)] or (k not in [1536,4608] and not ((m,n)==(1920,1920) and k==16384)):
        raise ValueError('Unvalidated dense-grid context')
    d=json.loads(Path(__file__).with_name('dense_parameters.json').read_text())
    c=d[f'{bm}_{bn}'];blocks=m//bm*(n//bn);sm=170;resident=c['resident'];base=c['base_blocks'];base_per_sm=math.ceil(base/sm)
    selected_resident=resident if resident_blocks is None else resident_blocks
    if resident_blocks is not None and ((bm,bn)!=(32,32) or (m,n)!=(1920,1920) or k not in [1536,4608] or resident_blocks not in [1,4,11]):
        raise ValueError('Unvalidated resident-block contrast')
    values={};detail={}
    for mode in ['0','1','2']:
        latency=c['1'][mode]['stage_us']/base_per_sm
        service=c[str(resident)][mode]['stage_us']/base_per_sm
        wait=math.ceil(blocks/(sm*selected_resident))*latency
        demand=math.ceil(blocks/sm)*service
        stage=max(wait,demand)
        fixed=c[str(resident)][mode]['fixed_us']*blocks/base
        values[mode]=fixed+k/32*stage
        detail[mode]={'latency_wave_us':wait,'service_demand_us':demand,'stage_us':stage}
    return {'predicted_us':values['1']+values['2']-values['0'],
            'phase_predictions':values,'phase_limits':detail,'allowed_resident_blocks':selected_resident,
            'coefficients_from_full_gemm':False,'full_model_complete':False,
            'unresolved':['exact shared service resource','phase interaction','clock/calibration context','cache partition confound','broader grids']}
