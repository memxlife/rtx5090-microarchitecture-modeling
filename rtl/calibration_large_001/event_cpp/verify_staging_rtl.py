from pathlib import Path
import subprocess,sys
n=int(sys.argv[1])if len(sys.argv)>1 else 2
e=Path(__file__).resolve().parent;d=e.parent
src=[d/'large_operand_staging.sv',d/'large_u16_warp_load.sv',e/'staging_component_top.sv']
with(e/f'staging_rtl_build_{n}.log').open('w')as f:
 c=subprocess.run(['verilator','--cc','--exe','--build','-j','2','-Wno-fatal','--top-module','staging_component_top',f'-GCONTEXTS={n}','--Mdir',str(e/f'build_staging_{n}'),'-CFLAGS',f'-O3 -std=c++20 -DTEST_CONTEXTS={n}',*map(str,src),str(e/'staging_rtl_host.cpp')],stdout=f,stderr=subprocess.STDOUT)
assert c.returncode==0
c=subprocess.run([str(e/f'build_staging_{n}/Vstaging_component_top')]);sys.exit(c.returncode)
