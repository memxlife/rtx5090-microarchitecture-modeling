from pathlib import Path
import subprocess,re,time,json
D=Path(__file__).resolve().parent;b=D/'build_k3072';out=D/'build_linked_k3072';out.mkdir(exist_ok=True)
s=(D/'large_connected_top.sv').read_text();s=re.sub(r'K=1536', 'K=3072', s);s=re.sub(r'large_gemm_complete #\(.*?\) model\(', 'large_gemm_complete_9 model(',s,flags=re.S);s=re.sub(r'large_slice_l2 #\(.*?\) gateway\(', 'large_slice_l2_a gateway(',s,flags=re.S);top=D/'linked_top_k3072.sv';top.write_text(s)
wrappers=[b/'Vlarge_gemm_complete_9/large_gemm_complete_9.sv',b/'Vlarge_slice_l2_a/large_slice_l2_a.sv'];libs=[str(x.with_name('lib'+x.stem+'.a'))for x in wrappers]
cmd=['verilator','--cc','--exe','--build','-j','2','--inline-mult','0','--unroll-count','1','-Wno-fatal','--top-module','large_connected_top','--Mdir',str(out),'-CFLAGS','-O3 -std=c++20 -DMATRIX_M=2048 -DMATRIX_N=2112 -DMATRIX_K=3072 -DCACHE_SLICES=48','-LDFLAGS',' '.join(libs),str(top),*map(str,wrappers),str(D/'host.cpp'),str(D.parent/'numerical/bf16_reference.cpp')]
exe=out/'Vlarge_connected_top'
if exe.exists() and any(Path(lib).stat().st_mtime>exe.stat().st_mtime for lib in libs):exe.unlink()
start=time.monotonic()
with(D/'linked_build_k3072.log').open('w')as log:c=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,timeout=240)
print('LINK_BUILD',c.returncode,time.monotonic()-start,flush=True);assert c.returncode==0
print('K3072_BUILD_ONLY_READY',str(exe),flush=True)
