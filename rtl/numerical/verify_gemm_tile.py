"""Verify repeated numerical matrix stages and acknowledged global output stores."""
from pathlib import Path
import hashlib,json,re,struct,subprocess,tempfile
from verify_numerical_matrix import bf16,no_core
from verify_shared_matrix import tiled
from verify_cached_shared_matrix import SOURCES,ROOT,RTL

def make_vectors(directory,stages):
    words=[];out=[0]*256
    for stage in range(stages):
        a=[(r*3+k+stage)%7-3 for r in range(16) for k in range(16)]
        b=[(k+c*2-stage)%5-2 for k in range(16) for c in range(16)]
        words.extend(tiled([bf16(x) for x in a])+tiled([bf16(x) for x in b]))
        for r in range(16):
            for c in range(16):out[r*16+c]+=sum(a[r*16+k]*b[k*16+c] for k in range(16))
    directory.mkdir(parents=True)
    (directory/'input.hex').write_text(''.join(f'{x:04x}\n' for x in words))
    (directory/'expected.hex').write_text(''.join(f'{struct.unpack("<I",struct.pack("<f",x))[0]:08x}\n' for x in out))

def run():
    sources=SOURCES[:-2]+[ROOT/'gemm_tile_controller.sv',ROOT/'gemm_tile_tb.sv',ROOT/'bf16_reference.cpp']
    checks=[]
    with tempfile.TemporaryDirectory(prefix='gemm-tile-') as tmp:
        for stages in [2,3]:
            build=Path(tmp)/f'build{stages}';directory=Path(tmp)/f'vectors{stages}';make_vectors(directory,stages)
            result=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','gemm_tile_tb',f'-GSTAGES={stages}','-I'+str(RTL/'generated'),'--Mdir',str(build),'-CFLAGS','-std=c++20',*map(str,sources)],text=True,capture_output=True)
            (ROOT/f'gemm_tile_build_{stages}.log').write_text(result.stdout+result.stderr)
            assert result.returncode==0,result.stdout+result.stderr
            command=[str(build/'Vgemm_tile_tb'),f'+vectors={directory}']
            observations=[]
            for delay in [2,13]:
                result=subprocess.run(command+[f'+backing_delay={delay}'],text=True,capture_output=True,preexec_fn=no_core)
                assert result.returncode==0,result.stdout+result.stderr
                match=re.search(r'GEMM_TILE_PASS stages=(\d+) checked_words=(\d+) backing_requests=(\d+) stores=(\d+) cycles=(\d+)',result.stdout)
                assert match,result.stdout
                _,words,misses,stores,cycles=map(int,match.groups())
                assert words==512 and misses==stages*32 and stores==512
                execution=[{'launch_id':int(a),'cycles':int(b)} for a,b in re.findall(r'TILE_EXECUTION id=(\d+) cycles=(\d+)',result.stdout)]
                assert len(execution)==2 and execution[0]['cycles']>execution[1]['cycles']
                checks.append({'stages':stages,'K':stages*16,'checked_words':words,'backing_delay_synthetic':delay,'backing_requests':misses,'committed_stores':stores,'cycles':cycles,'execution_cycles':execution,'passed':True,'stdout':result.stdout});observations.append(cycles)
            assert observations[1]-observations[0]==stages*32*11
            checks.append({'stages':stages,'latency_propagation':True,'added_cycles':observations[1]-observations[0],'passed':True})
            if stages==2:
                for flag,message in [('wrongstoreid','identity'),('badbase','base'),('overlap','unsupported cache write coherence')]:
                    result=subprocess.run(command+['+'+flag],text=True,capture_output=True,preexec_fn=no_core)
                    assert result.returncode!=0 and message in (result.stdout+result.stderr).lower(),result.stdout+result.stderr
                    checks.append({'rejected':flag,'passed':True})
    receipt={'all_passed':True,'checked_output_words':sum(x.get('checked_words',0) for x in checks),'checks':checks,
      'source_sha256':{str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
      'scope':'Two launches per configuration of one16x16 GEMM tile, K32/K48, numerical BF16 inputs, FP32 accumulators, completion-driven staging and output-store acknowledgments.',
      'timing_calibrated':False,'full_gpu_integrated':False,'physical_timing_validation':'NOT RUN',
      'execution_boundary':'Accepted launch rising edge to first rising edge observing done_valid, before testbench completion-hold cycles. Synthetic controller schedule; not original-kernel runtime.',
      'numerical_scope':'Small integer inputs with exact intermediate sums; tests functional reduction and dataflow, not complete NVIDIA rounding semantics.',
      'remaining':'Multiblock/multi-SM scheduling and contention, actual studied kernel instruction path, memory write cache coherence, barriers, general shapes and independent hardware timing remain incomplete.'}
    (ROOT/'gemm_tile_verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'passed':True,'checked_words':receipt['checked_output_words'],'checks':len(checks),'timing_calibrated':False}))

if __name__=='__main__':run()
