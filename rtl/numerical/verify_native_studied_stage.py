"""Check original native operand hot-loop values and every issued PC."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,tempfile
from verify_numerical_matrix import no_core
ROOT=Path(__file__).resolve().parent;RTL=ROOT.parent
SOURCES=[RTL/'discovery_rounds/native_barrier_015/native_control_decode.sv',
 RTL/'discovery_rounds/native_barrier_015/producer_barrier_tracker.sv',
 RTL/'discovery_rounds/functional_mapping_002/native_bf16_layout.sv',
 ROOT/'library_movm_permutation.sv',ROOT/'native_studied_stage_schedule.sv',
 RTL/'components/decoded_native_issue_gate.sv',RTL/'components/warp_shared_read_service.sv',
 ROOT/'numerical_matrix_pipeline.sv',ROOT/'native_bf16_adapter.sv',ROOT/'native_hmma16816_adapter.sv',
 ROOT/'native_movm_word_pipeline.sv',ROOT/'native_studied_stage_pipeline.sv',
 ROOT/'native_studied_stage_tb.sv',ROOT/'bf16_reference.cpp']
def run(warp_writes=False):
 subprocess.run(['python',str(ROOT/'generate_native_studied_stage.py')],check=True)
 with tempfile.TemporaryDirectory(prefix='native-studied-stage-') as temporary:
  result=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal',
   '--top-module','native_studied_stage_tb',f'-GUSE_WARP_WRITES={int(warp_writes)}','--Mdir',temporary,'-CFLAGS','-std=c++20',*map(str,SOURCES)],capture_output=True,text=True)
  (ROOT/'native_studied_stage_build.log').write_text(result.stdout+result.stderr)
  assert result.returncode==0,result.stdout+result.stderr
  result=subprocess.run([str(Path(temporary)/'Vnative_studied_stage_tb')],capture_output=True,text=True,preexec_fn=no_core,timeout=60)
  assert result.returncode==0,result.stdout+result.stderr
  match=re.search(r'NATIVE_STAGE_PASS checked_words=(\d+) requests=4 issue_trace_instructions=160',result.stdout)
  assert match and int(match.group(1))==1024,result.stdout
  negative_checks=[]
  if warp_writes:
   for case in ['bad_alignment','bad_duplicate']:
    failure=subprocess.run([str(Path(temporary)/'Vnative_studied_stage_tb'),'+'+case],capture_output=True,text=True,preexec_fn=no_core,timeout=60)
    assert failure.returncode!=0 and 'Invalid native stage warp write' in failure.stdout+failure.stderr,failure.stdout+failure.stderr
    negative_checks.append(case)
  receipt={'all_passed':True,'warp_writes_enabled':warp_writes,'negative_checks':negative_checks,'checked_words':1024,'native_issue_trace_instructions':160,'requests':4,
   'service_choices':{'read_return_delay':9,'movm_latency':19,'hmma_latency':73},
   'checks':(['vector fill of all2048halfwords','adjacent halves preserved','masked neighbor half preserved','scalar offer blocks vector acceptance'] if warp_writes else ['optional vector port disabled'])+['all four fragment tiles and both16-element reduction slices','nonzero input accumulators',
    'every issued PC exactly matches40-instruction static order','four actual native HMMA operations per request',
    'implicit/no-barrier operands wait for actual completion','held numerical response','last referenced halfword gates admission','reset cancellation'],
   'source_sha256':{str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest() for p in SOURCES},
   'oracle':'Direct32-element integer dot product on original A17/B13 dyadic pattern plus independent nonzero inputC; no generic/MOVM address calls.',
   'timing_calibrated':False,'native_address_alu_replayed':False,'full_gpu_integrated':False,
   'scope':'Only BM32/BN32/BK32 operand hot-loop PC1350..15c0. Control-only UMOV/IADD/LEA precomputed addresses; no full kernel native replay.',
   'stdout':result.stdout}
  (ROOT/('native_studied_stage_warp_write_verification.json' if warp_writes else 'native_studied_stage_verification.json')).write_text(json.dumps(receipt,indent=2)+'\n')
  print(json.dumps({'passed':True,'checked_words':1024,'native_issued_instructions':160}))
if __name__=='__main__':
 parser=argparse.ArgumentParser();parser.add_argument('--warp-writes',action='store_true');args=parser.parse_args();run(args.warp_writes)
