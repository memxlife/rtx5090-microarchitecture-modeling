"""Replay effective dependency costs; this does not produce hardware evidence."""
from pathlib import Path
import hashlib,json,re,subprocess,tempfile
from verify_numerical_matrix import no_core
ROOT=Path(__file__).resolve().parent;RTL=ROOT.parent
SOURCES=[ROOT/'library_movm_permutation.sv',ROOT/'native_movm_word_pipeline.sv',ROOT/'dependency_probe_replay.sv',ROOT/'dependency_probe_replay_tb.sv']
def run():
 hashes={str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest()for p in SOURCES}
 (ROOT/'dependency_probe_prebuild.json').write_text(json.dumps({'source_sha256':hashes},indent=2)+'\n');checks=[]
 with tempfile.TemporaryDirectory(prefix='dependency-probe-')as tmp:
  for label,flags in [('normal',[]),('long',['-GOPERATIONS=1024']),('mode',['-GTIMING_MODE=1']),('double_charge',['-GEXTRA_WAKEUP_CYCLES=1'])]:
   b=Path(tmp)/label;c=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','dependency_probe_replay_tb','--Mdir',str(b),*flags,*map(str,SOURCES)],capture_output=True,text=True)
   (ROOT/f'dependency_probe_build_{label}.log').write_text(c.stdout+c.stderr);assert c.returncode==0,c.stdout+c.stderr
   x=subprocess.run([str(b/'Vdependency_probe_replay_tb')],capture_output=True,text=True,preexec_fn=no_core,timeout=30);log=x.stdout+x.stderr;(ROOT/f'dependency_probe_run_{label}.log').write_text(log)
   if label in ['normal','long']:assert x.returncode==0 and f"DEPENDENCY_REPLAY_PASS operations={1024 if label=='long' else 37} checked_words=64" in log,log
   else:assert x.returncode!=0 and 'Effective recurrence rejects decomposed/additional timing' in log,log
   checks.append({'case':label,'passed':True,'observations':re.findall(r'DEPENDENCY_CASE .*',log)})
 assert hashes=={str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest()for p in SOURCES}
 d={'all_passed':True,'checked_words':128,'checks':checks,'timing_scope':'29/28-cycle spacing is the effective replay convention, not identified intrinsic hardware latency. Last actual return and held completion are distinct from the historical timer endpoint.','MOVM_observation':{'measured_net_cycles':29684,'measured_operations':1024,'measured_average':28.98828125,'rounded_recurrence':29,'rounding_difference_per_op':0.01171875,'relative_rounding_error':29/28.98828125-1},'new_hardware_evidence':False,'functional_oracle':'Independent MT88 coordinate transpose applied repeatedly; scalar LDS pointer ring rotates32 distinct addresses.','source_sha256':hashes}
 (ROOT/'dependency_probe_verification.json').write_text(json.dumps(d,indent=2)+'\n')
if __name__=='__main__':run()
