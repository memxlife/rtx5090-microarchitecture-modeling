from pathlib import Path
import subprocess,sys
e=Path(__file__).resolve().parent;d=e.parent
src=[d/'large_shared_read_candidate_hub.sv',d/'large_warp_shared_read_service.sv',e/'hub_component_top.sv']
with(e/'hub_rtl_build.log').open('w')as f:
 c=subprocess.run(['verilator','--cc','--exe','--build','-j','2','-Wno-fatal','--top-module','hub_component_top','--Mdir',str(e/'build_hub'),'-CFLAGS','-O3 -std=c++20',*map(str,src),str(e/'hub_rtl_host.cpp')],stdout=f,stderr=subprocess.STDOUT)
assert c.returncode==0
c=subprocess.run([str(e/'build_hub/Vhub_component_top')]);sys.exit(c.returncode)
