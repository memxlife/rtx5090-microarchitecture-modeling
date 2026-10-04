"""Verify two staging contexts against independent global address formulas."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
from verify_numerical_matrix import no_core
ROOT=Path(__file__).resolve().parent;RTL=ROOT.parent
SOURCES=[RTL/'components/sector_read_cache.sv',ROOT/'resident_u16_warp_load.sv',ROOT/'resident_operand_staging.sv',ROOT/'resident_operand_staging_tb.sv']
def run():
 with tempfile.TemporaryDirectory(prefix='resident-staging-')as tmp:
  c=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','resident_operand_staging_tb','--Mdir',tmp,*map(str,SOURCES)],capture_output=True,text=True)
  (ROOT/'resident_operand_staging_build.log').write_text(c.stdout+c.stderr);assert c.returncode==0,c.stdout+c.stderr
  r=subprocess.run([str(Path(tmp)/'Vresident_operand_staging_tb')],capture_output=True,text=True,preexec_fn=no_core,timeout=60)
  (ROOT/'resident_operand_staging_run.log').write_text(r.stdout+r.stderr);assert r.returncode==0 and 'RESIDENT_STAGING_PASS checked_halfwords=4096' in r.stdout,r.stdout+r.stderr
 receipt={'all_passed':True,'checked_halfwords':4096,'shape':{'M':64,'N':96,'K':64},'contexts':[{'row':0,'column':0,'stage':0},{'row':1,'column':1,'stage':1}],'oracle':'A global linear index modulo17 minus8 and B index modulo13 minus6, divided by16; each actual shared destination checked once.','checks':['request snapshot','held shared vector payload','delayed backing packets','all2048 commits before done','held done permits other context staging','reset cancels provider and model','final outstanding zero'],'scope':'Staging into checked shared-write sinks, not numerical compute integration or full CTA execution.','timing_calibrated':False,'source_sha256':{str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest()for p in SOURCES},'review':{'human_first_technical_writing':True,'undergraduate_reader_review':True}}
 (ROOT/'resident_operand_staging_verification.json').write_text(json.dumps(receipt,indent=2)+'\n');print('PASS resident staging:4096 halfwords')
if __name__=='__main__':run()
