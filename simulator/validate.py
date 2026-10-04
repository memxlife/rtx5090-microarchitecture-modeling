#!/usr/bin/env python3
"""Portable metadata/timing simulator check. make smoke is quick; make full runs both large cases.
Requires a C++20 compiler with std::barrier support, make, and Python 3.
The simulator covers output addresses and timing, not floating-point GEMM arithmetic.
"""
import argparse, json, pathlib, re, subprocess
p = pathlib.Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--full', action='store_true', help='Run both 170-SM workloads; may take tens of minutes.')
a = parser.parse_args()
subprocess.run(['make', 'all'], cwd=p, check=True)
exe = p / 'build/full_gpu_parallel'
cases = [(1536, 836886, 277.273601), (3072, 1636081, 532.447994)] if a.full else [(64, None, None)]
receipts = []
for k, expected, measured in cases:
    args = [2048,2112,k,1,170,48,11,20000000,1,1024,1,4,32] if a.full else [64,96,64,1,2,2,2,200000,0,4,2,2,32]
    result = subprocess.run([str(exe), *map(str,args)], cwd=p, text=True, capture_output=True, check=True)
    log = p / 'build' / ('full_%d.log'%k if a.full else 'smoke.log')
    log.write_text(result.stdout)
    rows = [dict(re.findall(r'(\w+)=(\S+)',line)) for line in result.stdout.splitlines() if line.startswith('FULL_CPP_PASS ')]
    assert len(rows)==(1 if a.full else 2), rows
    progress = [dict(re.findall(r'(\w+)=(\S+)',line)) for line in result.stdout.splitlines() if line.startswith('PROGRESS ')]
    final_progress = [x for x in progress if x['completed']==('4224' if a.full else '6')]
    assert len(final_progress)==len(rows), final_progress
    assert all(int(x['native'])==(32440320 if k==1536 else 64880640) for x in final_progress) if a.full else all(int(x['native'])==1920 for x in final_progress)
    if a.full:
        assert int(rows[0]['cycles'])==expected, rows
        assert int(rows[0]['checked'])==2048*2112, rows
        rows[0]['reference_us']=expected/2940
        rows[0]['hardware_us']=measured
        rows[0]['signed_error_percent']=(expected/2940/measured-1)*100
    else:
        for row,cycles,counts in zip(rows,[29592,25031],[(1536,324,1212,476,736),(3072,1125,1947,655,1292)]):
            assert int(row['cycles'])==cycles, row
            assert int(row['checked'])==6144, row
            assert tuple(int(row[x]) for x in ['requests','hits','misses','merges','fills'])==counts, row
    receipts.extend(rows)
(p/'build/validation.json').write_text(json.dumps(receipts,indent=2)+'\n')
print('PASS:', receipts)
