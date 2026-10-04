"""Check actual-completion issue gating with original native control fixtures."""
from pathlib import Path
import json,hashlib,re,subprocess,tempfile
ROOT=Path(__file__).resolve().parent;RTL=ROOT.parent
NATIVE=RTL/'discovery_rounds/native_barrier_015'
sources=[NATIVE/'native_control_decode.sv',NATIVE/'producer_barrier_tracker.sv',ROOT/'decoded_native_issue_gate.sv',ROOT/'decoded_native_issue_gate_tb.sv']
schedule=RTL/'discovery_rounds/original_native_schedule/original_kernel_schedule.json'
records={x['pc']:x for x in json.loads(schedule.read_text())['instructions']}
fixture_pcs=['0x1350','0x14c0','0x1370','0x1380','0x14e0']
for pc in fixture_pcs:
    r=records[pc];assert r['raw_high']+r['raw_low'] in sources[-1].read_text()
with tempfile.TemporaryDirectory(prefix='native-issue-')as tmp:
 b=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','decoded_native_issue_gate_tb','--Mdir',tmp,*map(str,sources)],capture_output=True,text=True)
 (ROOT/'decoded_native_issue_build.log').write_text(b.stdout+b.stderr);assert b.returncode==0,b.stdout+b.stderr
 x=subprocess.run([str(Path(tmp)/'Vdecoded_native_issue_gate_tb')],capture_output=True,text=True)
 (ROOT/'decoded_native_issue_run.log').write_text(x.stdout+x.stderr);assert x.returncode==0,x.stdout+x.stderr
 m=re.search(r'DECODED_ISSUE_GATE_PASS checks=(\d+) issued=(\d+)',x.stdout);assert m,x.stdout
 d={'all_passed':True,'checks':int(m[1]),'issued_operations':int(m[2]),'original_fixture_PCs':['0x1350','0x14c0','0x1370','0x1380','0x14e0'],'fixture_source':'../diagnostic_050/gemm.sass','control_semantics':'Issue-delay floor1 and all outstanding producers per requested barrier; reconstruction hypothesis, not complete native scoreboard semantics.','completion_contract':'Separate actual operands-consumed read event and result-ready write event; no predicted timestamps; clients complete only allocated barrier namespaces.','same_edge_rule':'Pre-edge readiness; completion unblocks following cycle; no same-edge ID reuse.','tag_rule':'Operation IDs cannot be reused while either allocated read/write tracker is active. No-barrier operations have no completion tracking.','unsupported':['Opcode-specific implicit dependencies and results without assigned barriers','group_continue scheduling semantics','Branch execution and register scoreboard','Physical hardware queue capacity or timing'],'new_identified_registry_fields':0,'source_sha256':{str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest()for p in sources},'stdout':x.stdout}
 (ROOT/'decoded_native_issue_gate_verification.json').write_text(json.dumps(d,indent=2)+'\n');print(json.dumps({'passed':True,'checks':d['checks']}))
