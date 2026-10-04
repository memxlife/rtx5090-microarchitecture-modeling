"""Compile and run a timing-only RTL hypothesis, with explicit input assumptions."""
import argparse
import json
import re
import shutil
import subprocess
import tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parent
WARPS, DEPTH=4,256
KEYS={'hit_latency':'HIT','miss_latency':'MISS','memory_spacing':'MEM_SPACING',
      'memory_slots':'MEM_SLOTS','shared_latency':'SHARED','shared_spacing':'SHARED_SPACING',
      'mma_latency':'MMA','mma_spacing':'MMA_SPACING','alu_latency':'ALU',
      'barrier_latency':'BARRIER','max_cycles':'MAX_CYCLES'}
OP={'global_load':1,'shared_store':2,'shared_load':3,'matrix':4,'alu':5,'barrier':6,'end':15}
def build(build_dir):
    compiler=shutil.which('verilator')
    if not compiler: raise RuntimeError('Verilator is required; no tool installation performed')
    build_dir=Path(build_dir).resolve(); build_dir.mkdir(parents=True,exist_ok=True)
    cmd=[compiler,'--binary','--timing','-Wno-fatal','--top-module','gpu_timing',
         '--Mdir',str(build_dir),str(ROOT/'gpu_timing.sv')]
    r=subprocess.run(cmd,text=True,capture_output=True)
    (build_dir/'compile.log').write_text(r.stdout+r.stderr)
    if r.returncode: raise RuntimeError('RTL compilation failed; see '+str(build_dir/'compile.log'))
    return build_dir/'Vgpu_timing'
def simulate(binary, config, programs):
    if set(config)!=set(KEYS):raise ValueError('Every timing/capacity assumption must be supplied explicitly')
    if any(type(v)!=int or v<=0 for v in config.values()):raise ValueError('Positive integer parameters required')
    if len(programs)!=WARPS:raise ValueError('Exactly four warp streams required')
    memory=[]
    for program in programs:
        if len(program)>=DEPTH:raise ValueError('Trace exceeds program capacity')
        encoded=[]
        for item in program:
            op=OP[item['op']];src=item.get('src',0);dst=item.get('dst',0);addr=item.get('address',0)
            if not 0<=src<64 or not 0<=dst<64 or not 0<=addr<2**31:raise ValueError('Unsupported register/address')
            encoded.append(op|(src<<4)|(dst<<10)|(addr<<16))
        if not encoded or encoded[-1]&15!=15:encoded.append(15)
        memory+=encoded+[15]*(DEPTH-len(encoded))
    with tempfile.TemporaryDirectory(prefix='rtx5090-rtl-trace-') as td:
        trace=Path(td)/'trace.hex';trace.write_text('\n'.join(f'{x:016x}' for x in memory)+'\n')
        args=[str(binary),'+TRACE='+str(trace)]+[f'+{KEYS[k]}={v}' for k,v in config.items()]
        r=subprocess.run(args,text=True,capture_output=True,timeout=30)
        if r.returncode:raise RuntimeError(r.stdout+r.stderr)
        line=next((x for x in r.stdout.splitlines() if x.startswith('RESULT ')),None)
        if not line:raise RuntimeError('Simulation produced no completion result')
        return {'metrics':{k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)},
                'events':[{k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',x)} for x in r.stdout.splitlines() if x.startswith('ISSUE ')],
                'hardware_validated':False,'numerical_gemm_simulated':False,
                'parameters':config,'cache_structure':{'sets':16,'ways':2,'sector_bytes':32,'replacement':'LRU hypothesis'},
                'scheduler':'one issue per cycle, round robin, one SM and one four-warp block'}
def main():
    p=argparse.ArgumentParser();p.add_argument('--input',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True);p.add_argument('--build-dir',type=Path,default=Path('/tmp/rtx5090-rtl-build'))
    a=p.parse_args(); data=json.loads(a.input.read_text());binary=build(a.build_dir)
    result=simulate(binary,data['parameters'],data['programs'])
    a.output.write_text(json.dumps(result,indent=2)+'\n')
    print('Completed timing-only RTL simulation:',result['metrics'])
if __name__=='__main__':main()
