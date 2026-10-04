"""Check numerical snapshots, queueing, service pacing and delivery separately."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parent
def run():
 sources=[ROOT/'warp_shared_read_service.sv',ROOT/'warp_shared_read_service_tb.sv']
 cases=[]
 for interval,delay in [(1,9),(3,1)]:
  with tempfile.TemporaryDirectory(prefix='warp-shared-service-') as tmp:
   command=['verilator','--binary','--timing','-Wno-fatal','--top-module','warp_shared_read_service_tb','--Mdir',tmp,f'-GINTERVAL={interval}',f'-GDELAY={delay}',*map(str,sources)]
   build=subprocess.run(command,text=True,capture_output=True)
   (ROOT/f'warp_shared_read_service_build_{interval}_{delay}.log').write_text(build.stdout+build.stderr)
   assert build.returncode==0,build.stdout+build.stderr
   binary=str(Path(tmp)/'Vwarp_shared_read_service_tb')
   result=subprocess.run([binary],text=True,capture_output=True)
   assert result.returncode==0 and 'SHARED_SERVICE_PASS checks=160' in result.stdout,result.stdout+result.stderr
   cases.append({'interval':interval,'return_delay':delay,'checked_words':160,'stdout':result.stdout})
   for flag,message in [('misaligned','Misaligned scalar shared request'),('duplicate','Duplicate live shared request ID'),('broadcast','Inconsistent shared broadcast snapshot')]:
    negative=subprocess.run([binary,'+'+flag],text=True,capture_output=True)
    assert negative.returncode!=0 and message in negative.stdout+negative.stderr,negative.stdout+negative.stderr
 receipt={'all_passed':True,'checked_output_words':320,'cases':cases,'checks':['scalar broadcast and 2/4/32 bank packages','four concurrent requests and capacity backpressure','acceptance snapshots','FIFO response identities','stable stalled response','exact isolated completion edge','reset cancellation and slot reclamation','misalignment and duplicate ID rejection'],'source_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},'timing_parameters_identified':0,'evidence_boundary':'Bank-work rule matches measured scalar contract; FIFO policy, queue capacity, initiation and return delays remain model hypotheses. This is local protocol verification, not RTX5090 timing validation.'}
 (ROOT/'warp_shared_read_service_verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
 print('Shared service:320 returned words and queue/service/return controls passed.')
if __name__=='__main__':run()
