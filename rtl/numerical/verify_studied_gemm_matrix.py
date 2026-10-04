"""Check original-error GEMM operand layout and full1536-term accumulation."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,tempfile
from verify_numerical_matrix import no_core

ROOT=Path(__file__).resolve().parent;RTL=ROOT.parent
SOURCES=[RTL/'discovery_rounds/functional_mapping_002/native_bf16_layout.sv',
 ROOT/'library_movm_permutation.sv',ROOT/'numerical_matrix_pipeline.sv',
 ROOT/'native_bf16_adapter.sv',RTL/'components/warp_shared_read_service.sv',ROOT/'generic_shared_matrix_pipeline.sv',ROOT/'timed_generic_shared_matrix_pipeline.sv',
 ROOT/'studied_gemm_matrix_pipeline.sv',ROOT/'studied_gemm_matrix_tb.sv',ROOT/'bf16_reference.cpp']

def run(timed_reads=False):
    subprocess.run(['python',str(ROOT/'generate_studied_gemm_vectors.py')],check=True,capture_output=True,text=True)
    checks=[]
    with tempfile.TemporaryDirectory(prefix='studied-gemm-matrix-') as tmp:
        for bm,bn in [(32,32),(64,48)]:
            build=Path(tmp)/f'{bm}_{bn}'
            suffix='_timed' if timed_reads else ''
            result=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal',
             '--top-module','studied_gemm_matrix_tb',f'-GBM={bm}',f'-GBN={bn}',f'-GTIMED_READS={int(timed_reads)}','--Mdir',str(build),
             '-CFLAGS','-std=c++20',*map(str,SOURCES)],capture_output=True,text=True)
            (ROOT/f'studied_gemm_build_{bm}_{bn}{suffix}.log').write_text(result.stdout+result.stderr)
            assert result.returncode==0,result.stdout+result.stderr
            directory=ROOT/'studied_gemm_vectors'/f'bm{bm}_bn{bn}'
            command=[str(build/'Vstudied_gemm_matrix_tb'),f'+vectors={directory}']
            result=subprocess.run(command,capture_output=True,text=True,preexec_fn=no_core)
            assert result.returncode==0,result.stdout+result.stderr
            match=re.search(r'STUDIED_GEMM_MATRIX_PASS BM=(\d+) BN=(\d+) K=(\d+) checked_words=(\d+) operations=(\d+)',result.stdout)
            assert match,result.stdout
            rbm,rbn,k,words,operations=map(int,match.groups())
            assert (rbm,rbn,k,words,operations)==(bm,bn,1536,bm*bn*96,(bm//16)*(bn//16)*96)
            checks.append({'tile':[bm,bn],'K':1536,'checked_words':words,'operations':operations,'passed':True,'stdout':result.stdout})
            for flag,message in [('badtile','tile'),('badstep','step')]:
                bad=subprocess.run(command+['+'+flag],capture_output=True,text=True,preexec_fn=no_core)
                assert bad.returncode!=0 and message in (bad.stdout+bad.stderr).lower(),bad.stdout+bad.stderr
                checks.append({'tile':[bm,bn],'invalid_input_rejected':flag,'passed':True})
    receipt={'all_passed':True,'checked_output_words':sum(x.get('checked_words',0) for x in checks),'checks':checks,
      'source_sha256':{str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCES},
      'target_kernel_source':'../diagnostic_050/gemm_checked.cu','global_shape':[2048,2112,1536],'CTA_coordinate':[0,0],
      'patterns':'A=((global_flat_index%17)-8)/16; B=((global_flat_index%13)-6)/16; same global strides as saved target workload.',
      'oracle':'Independent direct integer dot products divided by256, then represented exactly inFP32. Does not call consumer-address functions.',
      'scope':'Generic scalar shared loads and measured MOVM produce actual native operand values for all four/12fragment tiles through48stage frames. Arithmetic result captures feed subsequent reduction steps.',
      'timed_reads_enabled':timed_reads,'timing_calibrated':False,'native_hotloop_scheduler_implemented':False,'full_gpu_integrated':False,
      'proof_registry_fields_closed':0,'remaining':'Global cache/staging, native instruction scheduling, MOVM service, barriers, block residency and output-store path remain absent; enabled scalar shared service uses provisional rates and accepted-request snapshot isolation.'}
    (ROOT/('studied_gemm_matrix_timed_verification.json' if timed_reads else 'studied_gemm_matrix_verification.json')).write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'passed':True,'checked_words':receipt['checked_output_words'],'timing_calibrated':False}))

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--timed-reads',action='store_true');args=parser.parse_args();run(args.timed_reads)
