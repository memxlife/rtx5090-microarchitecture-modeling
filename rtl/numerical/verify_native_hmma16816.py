"""Check one native matrix half against direct 16x8 dyadic dot products."""
from pathlib import Path
import hashlib,json,struct,subprocess,tempfile
from verify_numerical_matrix import no_core
ROOT=Path(__file__).resolve().parent;RTL=ROOT.parent
fp=lambda x:int.from_bytes(struct.pack('>f',x),'big')
def aindex(l,j):return (l//4+8*((j//2)%2))*16+2*(l%4)+j%2+8*(j//4)
def bindex(l,j):return (2*(l%4)+j%2+8*((j//2)%2))*16+l//4+8*(j//4)
arrays={k:[]for k in ['a','b','c','expected']}
for ccase in range(2):
 A=[((row+k)%5-2)/4 for row in range(16)for k in range(16)]
 B=[((k+col)%7-3)/4 for k in range(16)for col in range(16)]
 C=[(row-col)/8 if ccase else 0 for row in range(16)for col in range(16)]
 D=[sum(A[row*16+k]*B[k*16+col]for k in range(16))+C[row*16+col]for row in range(16)for col in range(16)]
 for half in range(2):
  for lane in range(32):
   for word in range(4):arrays['a'].append((fp(A[aindex(lane,2*word)])>>16)|((fp(A[aindex(lane,2*word+1)])>>16)<<16))
   for word in range(2):
    w=word+2*half;arrays['b'].append((fp(B[bindex(lane,2*w)])>>16)|((fp(B[bindex(lane,2*w+1)])>>16)<<16))
   for word in range(4):
    index=aindex(lane,word+4*half);arrays['c'].append(fp(C[index]));arrays['expected'].append(fp(D[index]))
vector=ROOT/'hmma_vectors';vector.mkdir(exist_ok=True)
for name,v in arrays.items():(vector/(name+'.hex')).write_text(''.join(f'{x:08x}\n'for x in v))
sources=[RTL/'discovery_rounds/functional_mapping_002/native_bf16_layout.sv',ROOT/'numerical_matrix_pipeline.sv',ROOT/'native_bf16_adapter.sv',ROOT/'native_hmma16816_adapter.sv',ROOT/'native_hmma16816_tb.sv',ROOT/'bf16_reference.cpp']
with tempfile.TemporaryDirectory(prefix='native-hmma-')as tmp:
 b=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','native_hmma16816_tb','--Mdir',tmp,'-CFLAGS','-std=c++20',*map(str,sources)],capture_output=True,text=True)
 (ROOT/'native_hmma_build.log').write_text(b.stdout+b.stderr);assert b.returncode==0,b.stdout+b.stderr
 x=subprocess.run([str(Path(tmp)/'Vnative_hmma16816_tb'),f'+vectors={vector}'],capture_output=True,text=True,preexec_fn=no_core)
 (ROOT/'native_hmma_run.log').write_text(x.stdout+x.stderr);assert x.returncode==0,x.stdout+x.stderr
 assert 'NATIVE_HMMA_PASS'in x.stdout
 d={'all_passed':True,'checked_words':512,'native_half_operations':4,'oracle':'Independent direct sixteen-term dyadic dot product for all16x8outputs in each column half; two distinct FP32accumulators.','recombined_full_matrix_cases':2,'full_WMMA_comparison_words':512,'checks':['Both column halves cover the full256output matrix and match the complete WMMA adapter','Nonzero initial accumulation','Acceptance snapshot','Response backpressure','reset'],'timing_calibrated':False,'scope':'Supported numerical operation family adapter, not physical pipeline count or native result timing.','new_identified_registry_fields':0,'source_sha256':{str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest()for p in sources},'stdout':x.stdout}
 (ROOT/'native_hmma16816_verification.json').write_text(json.dumps(d,indent=2)+'\n');print(json.dumps({'passed':True,'checked_words':512}))
