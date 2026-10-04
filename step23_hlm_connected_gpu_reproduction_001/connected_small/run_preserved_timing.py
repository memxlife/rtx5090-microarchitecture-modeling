raise SystemExit("Disabled: user forbids further Verilog execution; historical script retained below.")
"""Run newly elaborated original calibrated components at exact HLM shapes."""
from pathlib import Path
import subprocess,time,json,hashlib
O=Path(__file__).resolve().parent
S=json.loads((O/'sources.json').read_text())['sources']
for k in [12288,49152]:
 b=O/f'build_k{k}';exe=b/'Vcalibration_connected_tb'
 if not exe.exists():
  cmd=['verilator','--binary','--timing','--build','-j','2','-Wno-fatal','--top-module','calibration_connected_tb',f'-GK={k}','--Mdir',str(b),'-CFLAGS','-std=c++20',*S]
  p=subprocess.run(cmd,text=True,capture_output=True,timeout=600);(O/f'build_k{k}.log').write_text(p.stdout+p.stderr);assert p.returncode==0,p.stderr[-2000:]
 cmd=[str(exe),'+hit_delay=4','+setup_cycles=3346'];st=time.monotonic()
 with (O/f'run_k{k}.log').open('w') as out:
  p=subprocess.run(cmd,stdout=out,stderr=subprocess.STDOUT,timeout=2400)
 text=(O/f'run_k{k}.log').read_text();metrics=[s for s in text.splitlines()if s.startswith('RESIDENT_MULTI_SM_NB_L2_LAUNCH')]
 receipt={'K':k,'command':cmd,'executable_sha256':hashlib.sha256(exe.read_bytes()).hexdigest(),'wall_seconds':time.monotonic()-st,'returncode':p.returncode,'launch_metrics':metrics,'numerical_full_24576':'checked_words=24576 launches=2' in text,'scope':'New shape elaboration of preserved calibrated components, no parameter retuning; not preserved executable identity.'}
 (O/f'result_k{k}.json').write_text(json.dumps(receipt,indent=2));print(json.dumps(receipt),flush=True)
 assert p.returncode==0 and receipt['numerical_full_24576']
