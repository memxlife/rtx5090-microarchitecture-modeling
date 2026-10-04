"""Check actual-library operand addresses and MOVM against independent products."""
from pathlib import Path
import hashlib,json,re,subprocess,tempfile
from verify_numerical_matrix import no_core

ROOT=Path(__file__).resolve().parent;RTL=ROOT.parent
SOURCES=[RTL/'discovery_rounds/functional_mapping_002/native_bf16_layout.sv',
 ROOT/'library_shared_layout.sv',ROOT/'library_movm_permutation.sv',
 ROOT/'numerical_matrix_pipeline.sv',ROOT/'native_bf16_adapter.sv',
 ROOT/'generic_shared_matrix_pipeline.sv',ROOT/'library_generic_matrix_pipeline.sv',ROOT/'library_generic_matrix_tb.sv',ROOT/'bf16_reference.cpp']

def run():
    subprocess.run(['python',str(ROOT/'generate_library_generic_vectors.py')],check=True,capture_output=True,text=True)
    checks=[]
    with tempfile.TemporaryDirectory(prefix='library-generic-matrix-') as tmp:
        for latency,interval in [(16,4),(37,9)]:
            build=Path(tmp)/str(latency)
            result=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal',
             '--top-module','library_generic_matrix_tb',f'-GLATENCY={latency}',f'-GINTERVAL={interval}',
             '--Mdir',str(build),'-CFLAGS','-std=c++20',*map(str,SOURCES)],capture_output=True,text=True)
            (ROOT/f'library_generic_build_{latency}.log').write_text(result.stdout+result.stderr)
            assert result.returncode==0,result.stdout+result.stderr
            command=[str(build/'Vlibrary_generic_matrix_tb'),f'+vectors={ROOT/"library_generic_vectors"}']
            result=subprocess.run(command,capture_output=True,text=True,preexec_fn=no_core)
            assert result.returncode==0,result.stdout+result.stderr
            match=re.search(r'LIBRARY_GENERIC_MATRIX_PASS checked_words=(\d+) operations=(\d+)',result.stdout)
            assert match and tuple(map(int,match.groups()))==(33024,129),result.stdout
            checks.append({'latency_synthetic':latency,'interval_synthetic':interval,'checked_words':33024,'operations':129,'passed':True,'stdout':result.stdout})
            if latency==16:
                bad=subprocess.run(command+['+oddwrite'],capture_output=True,text=True,preexec_fn=no_core)
                assert bad.returncode!=0 and 'Invalid library shared write address' in bad.stdout+bad.stderr
                checks.append({'invalid_input_rejected':'oddwrite','passed':True})
    receipt={'all_passed':True,'checked_output_words':sum(x.get('checked_words',0) for x in checks),'checks':checks,
     'source_sha256':{str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCES},
     'vector_manifest_sha256':hashlib.sha256((ROOT/'library_generic_vectors/manifest.json').read_bytes()).hexdigest(),
     'scope':'Four warp tiles and16reductionsteps (two128-Kslots) assemble a32x32 K256 integer GEMM product using actual selected-library generic shared operand addresses and measured MOVM mapping.',
     'oracle':'Direct ordinary matrix multiplication, independent of consumer-address/permutation implementation.',
     'protocol_checks':['last referenced halfword delays admission','operation identity','accepted operand snapshot survives shared overwrite','held result values','actual result accumulates into next step','reset invalidates words and pending results'],
     'timing_calibrated':False,'native_hotloop_scheduler_implemented':False,'full_gpu_integrated':False,
     'remaining':'Generic-load bank/response service and MOVM latency/issue controls omitted; global staging/cache/output stores and multiwarp scheduling are not connected to this operand adapter.'}
    (ROOT/'library_generic_matrix_verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(json.dumps({'passed':True,'checked_words':receipt['checked_output_words'],'timing_calibrated':False}))

if __name__=='__main__':run()
