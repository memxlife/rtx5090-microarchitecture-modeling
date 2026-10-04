"""Verify source-to-native counts against saved profiler instruction totals."""
import csv
import hashlib
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def matrix_instruction_count(bm,bn,bk,k,blocks):
    if min(bm,bn,bk,k,blocks)<=0 or bm%16 or bn%16 or bk%16:
        raise ValueError('Positive dimensions and complete 16-wide tiles required')
    # Two native HMMA instructions per WMMA is admitted only for this saved family.
    if (bm,bn,bk) not in {(32,32,32),(64,48,32)}:
        raise ValueError('Unverified compiled tile family')
    stages=(k+bk-1)//bk
    wmma_per_block_stage=(bm//16)*(bn//16)*(bk//16)
    return blocks*stages*wmma_per_block_stage*2

def main():
    records=[]
    for bm,bn in [(32,32),(64,48)]:
        stem=f'profile_{bm}_{bn}_p2_k16384_c1'
        source=ROOT/'diagnostic_042'/f'{stem}.source.csv'
        raw=ROOT/'diagnostic_042'/f'{stem}.raw.csv'
        lines=source.read_text().splitlines()
        start=next(i for i,line in enumerate(lines) if line.startswith('"Address"'))
        rows=list(csv.DictReader(lines[start:]))
        instructions=[r for r in rows if r['Source'].strip().startswith('HMMA.')]
        measured=sum(int(r['Instructions Executed'].replace(',','')) for r in instructions)
        launch=list(csv.DictReader(raw.read_text().splitlines()))[-1]
        blocks=int(launch['launch__grid_size'])
        assert int(launch['launch__block_size'])==128
        predicted=matrix_instruction_count(bm,bn,32,16384,blocks)
        assert measured==predicted,(bm,bn,measured,predicted)
        records.append({'tile':[bm,bn],'blocks':blocks,'k':16384,'stages':512,
                        'observed_warp_matrix_instructions':measured,'derived_warp_matrix_instructions':predicted,
                        'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
                        'raw_sha256':hashlib.sha256(raw.read_bytes()).hexdigest(),
                        'source':str(source.relative_to(ROOT)),'raw':str(raw.relative_to(ROOT))})
    result={'records':records,'scope':'Saved diagnostic_042 p2 launches only; arithmetic count, not timing prediction',
            'hardware_benchmark_run':False,'timing_parameters_identified':0}
    (Path(__file__).parent/'dynamic_matrix_inventory.json').write_text(json.dumps(result,indent=2)+'\n')
    print('Both saved profiler totals match: 49152 warp matrix instructions per launch.')
if __name__=='__main__':main()
