"""Verify clocked shared values, measured collective mapping and matrix arithmetic."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
from verify_numerical_matrix import vectors,write_vectors,decode,round_fp32,no_core
ROOT=Path(__file__).resolve().parent
MAP=ROOT.parent/'discovery_rounds/functional_mapping_002'
LDSM=ROOT.parent/'discovery_rounds/ldsm_mapping_003'
def tiled(matrix):
 out=[0]*256
 for row in range(16):
  for col in range(16):out[((row//8)+2*(col//8))*64+(row%8)*8+col%8]=matrix[row*16+col]
 return out
def transformed(storage,mode):
 out=[0]*256
 for tile in range(4):
  for row in range(8):
   provider=tile*8+row
   readrow=(tile*8+7-row if mode==1 else provider^8 if mode==2 else row if mode==3 else provider)
   for col in range(8):out[(row+8*(tile%2))*16+col+8*(tile//2)]=storage[readrow*8+col]
 return out
def generate():
 original,labels=vectors();arrays={'storage':[],'c':[],'expected':[]};cases=[]
 for base,label in enumerate(labels):
  aa=tiled(original['a'][base*256:(base+1)*256]);bb=tiled(original['b'][base*256:(base+1)*256]);cc=original['c'][base*256:(base+1)*256]
  for mode in range(4):
   a=transformed(aa,mode);b=transformed(bb,mode);expected=[]
   for row in range(16):
    for col in range(16):
     value=cc[row*16+col]
     for k in range(16):value=round_fp32(decode(a[row*16+k],7)*decode(b[k*16+col],7)+decode(value,23))
     expected.append(value)
   arrays['storage'].extend(aa+bb);arrays['c'].extend(cc);arrays['expected'].extend(expected);cases.append({'base_pattern':label,'row_mode':mode})
 return arrays,cases
def run():
 arrays,cases=generate();directory=ROOT/'shared_vectors';write_vectors(directory,arrays)
 sources=[LDSM/'ldsm_x4_layout.sv',MAP/'native_bf16_layout.sv',ROOT/'numerical_matrix_pipeline.sv',ROOT/'native_bf16_adapter.sv',ROOT/'shared_matrix_pipeline.sv',ROOT/'shared_matrix_tb.sv',ROOT/'bf16_reference.cpp']
 checks=[]
 with tempfile.TemporaryDirectory(prefix='shared-matrix-') as tmp:
  for latency,interval,capacity in [(2,1,1024),(17,3,1024),(17,3,102400)]:
   build=Path(tmp)/f'{latency}_{capacity}'
   result=subprocess.run(['verilator','--binary','--timing','-Wno-fatal','--top-module','shared_matrix_tb',f'-GLATENCY={latency}',f'-GINTERVAL={interval}',f'-GSHARED_BYTES={capacity}','--Mdir',str(build),'-CFLAGS','-std=c++20',*map(str,sources)],text=True,capture_output=True)
   (ROOT/f'shared_build_{latency}_{capacity}.log').write_text(result.stdout+result.stderr)
   assert result.returncode==0,result.stdout+result.stderr
   command=[str(build/'Vshared_matrix_tb'),f'+vectors={directory}',f'+mappings={MAP}']
   result=subprocess.run(command,text=True,capture_output=True,preexec_fn=no_core)
   assert result.returncode==0 and 'SHARED_MATRIX_PASS' in result.stdout,result.stdout+result.stderr
   checks.append({'latency_synthetic':latency,'interval_synthetic':interval,'storage_capacity_bytes':capacity,'output':result.stdout,'passed':True})
   if latency==17 and capacity==1024:
    for flag,message in [('writeodd','Invalid shared write address'),('unaligned','Invalid LDSM row address'),('outofbounds','Invalid LDSM row address')]:
     result=subprocess.run(command+['+'+flag],text=True,capture_output=True,preexec_fn=no_core)
     assert result.returncode!=0 and message in result.stdout+result.stderr,result.stdout+result.stderr
     checks.append({'invalid_input_rejected':flag,'passed':True})
 receipt={'all_passed':True,'checked_output_words':18432,'cases':cases,'checks':checks,'source_sha256':{str(p.relative_to(ROOT.parent)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},'vector_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in directory.glob('*.hex')},'modelled_storage_bytes_test':[1024,102400], 'buffers_at_upper_capacity_boundary':True,'model_default_storage_bytes':102400,'physical_timing_calibrated':False,'native_accumulation_order_identified':False,'full_gpu_integrated':False,'protocol_checks':['no issue before final shared write becomes visible','input snapshot survives subsequent shared overwrite','operation identity','stalled result stability','completion retirement','reset invalidates shared operands'],'arithmetic_oracle':'Exact rational sequential FP32 fused-multiply-add convention; not identified NVIDIA accumulation order'}
 (ROOT/'shared_matrix_verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
 print('Shared matrix verification passed:18432 output words, readiness/snapshot/stall/reset and three invalid-address controls. Timing remains synthetic.')
if __name__=='__main__':run()
