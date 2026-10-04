"""Verify numerical cache-to-shared integration using synthetic backing delays."""
from pathlib import Path
import hashlib,json,re,subprocess,tempfile
from verify_numerical_matrix import no_core

ROOT=Path(__file__).resolve().parent
RTL=ROOT.parent
MAP=RTL/'discovery_rounds/functional_mapping_002'
SOURCES=[RTL/'discovery_rounds/ldsm_mapping_003/ldsm_x4_layout.sv',
 MAP/'native_bf16_layout.sv',RTL/'components/sector_read_cache.sv',
 ROOT/'numerical_matrix_pipeline.sv',ROOT/'native_bf16_adapter.sv',
 ROOT/'shared_matrix_pipeline.sv',ROOT/'cached_shared_matrix_pipeline.sv',
 ROOT/'cached_shared_matrix_tb.sv',ROOT/'bf16_reference.cpp']

def run():
    subprocess.run(['python',str(RTL/'export_provisional_config.py')],check=True,capture_output=True,text=True)
    checks=[]
    with tempfile.TemporaryDirectory(prefix='cached-shared-matrix-') as temporary:
        for mode,cases in [(0,24),(1,4)]:
            build=Path(temporary)/f'mode{mode}'
            command=['verilator','--binary','--timing','-j','2','-Wno-fatal',
             '--top-module','cached_shared_matrix_tb',f'-GARITHMETIC_MODE={mode}',f'-GCASES={cases}',
             '-I'+str(RTL/'generated'),'--Mdir',str(build),'-CFLAGS','-std=c++20',*map(str,SOURCES)]
            result=subprocess.run(command,text=True,capture_output=True)
            (ROOT/f'cached_shared_build_mode{mode}.log').write_text(result.stdout+result.stderr)
            assert result.returncode==0,result.stdout+result.stderr
            binary=[str(build/'Vcached_shared_matrix_tb'),f'+vectors={ROOT/"shared_vectors"}',f'+mappings={MAP}']
            observed=[]
            for delay in [2,13]:
                result=subprocess.run(binary+[f'+backing_delay={delay}'],capture_output=True,text=True,preexec_fn=no_core)
                assert result.returncode==0,result.stdout+result.stderr
                match=re.search(r'CACHED_SHARED_MATRIX_PASS cases=(\d+) checked_words=(\d+) misses=(\d+) cycles=(\d+)',result.stdout)
                assert match,result.stdout
                count,words,misses,cycles=map(int,match.groups())
                assert count==cases and words==cases*256 and misses==cases*32
                checks.append({'mode':mode,'cases':cases,'checked_words':words,'backing_delay_synthetic':delay,'backing_sector_requests':misses,'cycles':cycles,'passed':True,'stdout':result.stdout})
                observed.append(cycles)
            assert observed[1]-observed[0]==cases*32*11,(mode,observed)
            checks.append({'mode':mode,'variable_latency_propagation_cycles':observed[1]-observed[0],'expected_cycles':cases*32*11,'passed':True})
            if mode==0:
                for flag,message in [('unaligned','Unaligned or out-of-bounds staging address'),('wrongid','Cache backing completion identity mismatch')]:
                    result=subprocess.run(binary+['+'+flag],capture_output=True,text=True,preexec_fn=no_core)
                    assert result.returncode!=0 and message in result.stdout+result.stderr,result.stdout+result.stderr
                    checks.append({'rejected':flag,'passed':True})
    receipt={'all_passed':True,'checked_output_words':sum(c.get('checked_words',0) for c in checks),'checks':checks,
     'source_sha256':{str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCES},
     'profile_sha256':hashlib.sha256((RTL/'provisional_hardware_profile.json').read_bytes()).hexdigest(),
     'timing_calibrated':False,'full_gpu_integrated':False,
     'supported_increment':'One warp numerical16x16x16 operation; backing sector return through cache, two shared stores, measured LDSM placement and matrix arithmetic.',
     'remaining':'No full-GEMM scheduler, global output-store path, multiblock residency or calibrated chip timing. This LDSM path is not the genericLD.E/MOVM path of the inspected cuBLAS kernel.',
     'protocol_checks':['matrix waits for initialized operands and consumed staging acknowledgment','sector reuse and request conservation','staging/result identity','held staging and numerical completions','reset invalidates shared and cache state','actual backing delay propagates to elapsed cycles'],
     'arithmetic_scope':'MODE0 sequential reference24cases; MODE1 reconstructed aligned-dot four exact integer identity cases. These tests do not establish universal NVIDIA numerical behavior.'}
    (ROOT/'cached_shared_matrix_verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'passed':True,'checked_words':receipt['checked_output_words'],'checks':len(checks),'timing_calibrated':False}))

if __name__=='__main__':run()
