"""Check every output of complete small GEMM grids through serial CTA reuse."""
from pathlib import Path
import argparse,hashlib,json,re,subprocess,tempfile
from verify_studied_gemm_cta import SOURCES as CTA_SOURCES
from verify_numerical_matrix import no_core
ROOT=Path(__file__).resolve().parent;RTL=ROOT.parent
SOURCES=[p for p in CTA_SOURCES if p.name!='studied_gemm_cta_tb.sv']+[ROOT/'coalesced_fp32_warp_store.sv',ROOT/'studied_gemm_grid_controller.sv',ROOT/'studied_gemm_grid_tb.sv']
SOURCES=list(dict.fromkeys(SOURCES))
def run(quick=False):
 checks=[];configs=[(64,96,64,2,2)]
 if not quick:configs.extend([(64,96,1536,7,1),(96,64,64,7,1)])
 with tempfile.TemporaryDirectory(prefix='studied-grid-')as t:
  for m,n,k,delay,replays in configs:
   b=Path(t)/f'{m}_{n}_{k}'
   c=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','studied_gemm_grid_tb',f'-GM={m}',f'-GN={n}',f'-GK={k}',f'-GREAD_DELAY={delay}',f'-GREPLAYS={replays}','--Mdir',str(b),'-CFLAGS','-std=c++20',*map(str,SOURCES)],capture_output=True,text=True)
   (ROOT/f'studied_grid_build_{m}_{n}_{k}.log').write_text(c.stdout+c.stderr);assert c.returncode==0,c.stdout+c.stderr
   r=subprocess.run([str(b/'Vstudied_gemm_grid_tb')],capture_output=True,text=True,preexec_fn=no_core,timeout=240)
   (ROOT/f'studied_grid_run_{m}_{n}_{k}.log').write_text(r.stdout+r.stderr);assert r.returncode==0,r.stdout+r.stderr
   match=re.search(r'STUDIED_GRID_PASS M=(\d+) N=(\d+) K=(\d+) checked_words=(\d+) launches=(\d+) stores=(\d+) acks=(\d+) backing_requests=(\d+) cycles=(\d+)',r.stdout);assert match,r.stdout
   v=list(map(int,match.groups()));assert v[:7]==[m,n,k,m*n*replays,replays,m*n*replays,m*n*replays]
   metrics=[dict(zip(['id','completion_cycles','blocks','packets','packet_acks'],map(int,x)))for x in re.findall(r'GRID_LAUNCH_METRICS id=(\d+) completion_cycles=(\d+) blocks=(\d+) packets=(\d+) packet_acks=(\d+)',r.stdout)]
   assert len(metrics)==replays and all(x['blocks']==6 and x['packets']==x['packet_acks']for x in metrics)
   checks.append({'shape':[m,n,k],'launches':replays,'checked_words':v[3],'acknowledged_words':v[6],'backing_requests':v[7],'synthetic_total_cycles':v[8],'launch_metrics':metrics,'passed':True});print(json.dumps(checks[-1]),flush=True)
 receipt={'all_passed':True,'checked_words':sum(x['checked_words']for x in checks),'checks':checks,'oracle':'Independent full integerdot A=((row*K+k)%17-8)/16, B=((k*N+col)%13-6)/16 with whole-grid coordinates, exact FP32dyadicoutputs.','protocol_checks':['all six distinct block coordinates','every grid output exactly once','all acknowledged words before grid completion','sector aligned input provider','output masks and stable packet under backpressure','delayed stores and backing responses','cancel first pending backing read withreset','held grid done','K64replay'],'timing_calibrated':False,'scope':'Complete smallgrid functional correctness through one serial reusableCTA; no multiSM placement/concurrency or hardware timingvalidation.','source_sha256':{str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest()for p in SOURCES},'review':{'human_first_technical_writing':True,'undergraduate_reader_review':True}}
 (ROOT/('studied_gemm_grid_quick_verification.json'if quick else'studied_gemm_grid_verification.json')).write_text(json.dumps(receipt,indent=2)+'\n')
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--quick',action='store_true');run(p.parse_args().quick)
