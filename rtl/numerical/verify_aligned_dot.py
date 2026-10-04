"""Compare the configured aligned-dot RTL mode against six saved hardware cases."""
from pathlib import Path
import json,hashlib,struct,subprocess,tempfile,resource
from verify_numerical_matrix import write_vectors,no_core
ROOT=Path(__file__).resolve().parent
EVIDENCE=ROOT.parent/'parameter_sweep/bf16_exceptions'
def bf16(x):return struct.unpack('I',struct.pack('f',x))[0]>>16
def bits(x):return struct.unpack('I',struct.pack('f',x))[0]
def run():
 rows=json.loads((EVIDENCE/'confirmation_analysis.json').read_text())['cases']
 chosen=[(24,.75,0,0),(26,2.5,0,1),(26,6.,1,2),(26,7.,2,0),(28,-7.,1,1),(28,.75,2,2)]
 arrays={k:[] for k in ['a','b','c','expected']};positions=[[0,1,2],[0,8,15],[3,7,11]]
 for power,small,mode,layout in chosen:
  q=next(q for q in rows if(q['power'],q['small'],q['mode'],q['layout'],q['repeat'])==(power,small,mode,layout,0));a=[0]*256;b=[bf16(1.)]*256;c=[bits(small if mode==1 else 0.)]*256;pos=positions[layout]
  for row in range(16):
   a[row*16+pos[0]]=bf16(2.**power);a[row*16+pos[2]]=bf16(-2.**power)
   if mode==0:a[row*16+pos[1]]=bf16(small)
   if mode==2:a[row*16+pos[1]]=bf16(small/2);a[row*16+(pos[1]+2)%16]=bf16(small/2)
  for k,v in [('a',a),('b',b),('c',c),('expected',[q['result_bits']]*256)]:arrays[k].extend(v)
 sources=[ROOT/'numerical_matrix_pipeline.sv',ROOT/'numerical_matrix_tb.sv',ROOT/'bf16_reference.cpp'];checks=[]
 with tempfile.TemporaryDirectory(prefix='aligned-dot-') as tmp:
  vectors=Path(tmp)/'vectors';write_vectors(vectors,arrays)
  for mode in [0,1]:
   build=Path(tmp)/f'mode{mode}'
   cmd=['verilator','--binary','--timing','-Wno-fatal','--top-module','numerical_matrix_tb',f'-GARITHMETIC_MODE={mode}','--Mdir',str(build),'-CFLAGS','-std=c++20',*[str(p) for p in sources]]
   q=subprocess.run(cmd,capture_output=True,text=True);(ROOT/f'aligned_build_mode{mode}.log').write_text(q.stdout+q.stderr);assert q.returncode==0,q.stdout+q.stderr
   q=subprocess.run([str(build/'Vnumerical_matrix_tb'),f'+vectors={vectors}'],capture_output=True,text=True,preexec_fn=no_core)
   if mode==1:assert q.returncode==0 and 'NUMERICAL_MATRIX_PASS' in q.stdout,q.stdout+q.stderr
   else:assert q.returncode!=0 and 'Matrix value mismatch' in q.stdout+q.stderr
   checks.append({'mode':mode,'matches_hardware':mode==1,'output':q.stdout+q.stderr})
   if mode==1:
    for label,word in [('nan',0x7fc0),('subnormal',1)]:
     bad={k:v.copy() for k,v in arrays.items()};bad['a'][0]=word;bad_dir=Path(tmp)/label;write_vectors(bad_dir,bad)
     q=subprocess.run([str(build/'Vnumerical_matrix_tb'),f'+vectors={bad_dir}'],capture_output=True,text=True,preexec_fn=no_core)
     assert q.returncode!=0 and 'Unsupported reference arithmetic' in q.stdout+q.stderr
     checks.append({'rejected':label,'mode':1,'passed':True})
 receipt={'checks':checks,'configured_mode1_passed':True,'sequential_mode0_counterexample_preserved':True,'hardware_cases':chosen,'checked_output_words':1536,'source_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},'supported_domain':'Measured finite power-of-two cancellation and small accumulator/products family','intrinsic_timing_validated':False,'full_gpu_model':False,'unsupported':'Exceptional/subnormal inputs or outputs explicitly rejected; other finite reductions remain hypotheses'}
 (ROOT/'aligned_dot_verification.json').write_text(json.dumps(receipt,indent=2)+'\n');print('Aligned-dot RTL mode matches1536hardware outputs; sequential model counterexample preserved.')
if __name__=='__main__':run()
