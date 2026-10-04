"""Local connected-interface tests; no GPU access or hardware timing calibration."""
import hashlib,json,resource,subprocess,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parent

def no_core():
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))

def run():
    tool='verilator'
    sources=[ROOT/'hardware_blocks.sv',ROOT/'completion_register_file.sv',ROOT/'completion_path_tb.sv']
    checks=[]
    errors={
        'bad_index':'Reservation destination outside writable register range',
        'unreserved':'Completion has no matching pending reservation',
        'wrong_id':'Completion has no matching pending reservation',
        'duplicate_id':'Duplicate outstanding reservation identity',
        'duplicate_completion':'Completion has no matching pending reservation',
    }
    with tempfile.TemporaryDirectory(prefix='rtx-completion-') as directory:
        base=Path(directory)
        for latency in [2,12,40]:
            build=base/f'latency_{latency}'
            args=[tool,'--binary','--timing','-Wno-fatal','--top-module','completion_path_tb',
                  f'-GMEMORY_LATENCY={latency}','--Mdir',str(build),*[str(s) for s in sources]]
            compilation=subprocess.run(args,text=True,capture_output=True)
            (ROOT/f'completion_build_{latency}.log').write_text(compilation.stdout+compilation.stderr)
            assert compilation.returncode==0,compilation.stderr
            binary=build/'Vcompletion_path_tb'
            result=subprocess.run([str(binary)],text=True,capture_output=True,preexec_fn=no_core)
            assert result.returncode==0 and 'COMPLETION_PATH_PASS' in result.stdout,result.stdout+result.stderr
            checks.append({'memory_latency_baseline_cycles':latency,'passed':True,'output':result.stdout})
            if latency==12:
                for case,message in errors.items():
                    result=subprocess.run([str(binary),f'+negative={case}'],text=True,capture_output=True,preexec_fn=no_core)
                    combined=result.stdout+result.stderr
                    assert result.returncode!=0 and message in combined,(case,combined)
                    checks.append({'rejected_case':case,'passed':True,'diagnostic':message})
    receipt={
        'source_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
        'verilator_version':subprocess.check_output([tool,'--version'],text=True).strip(),
        'checks':checks,'all_passed':True,'hardware_calibrated':False,'full_gemm_model':False,
        'behavior_update':'Register data/readiness is updated only by a matching actual completion; timestamps are not used.',
        'limits':['Single register context, two read views and one completion port',
                  'Arithmetic in the test is integer addition, not matrix instruction emulation',
                  'Three memory delays are synthetic protocol controls, not RTX measurements']}
    (ROOT/'completion_verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
    print(f'Completion-path verification passed: {len(checks)} cases; no physical timing claim.')

if __name__=='__main__':run()
