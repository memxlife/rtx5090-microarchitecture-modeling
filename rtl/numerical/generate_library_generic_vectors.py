#!/usr/bin/env python3
"""Generate shared-storage stimuli and direct matrix-product golden results."""
import argparse,hashlib,importlib.util,json,struct
from pathlib import Path
ROOT=Path(__file__).resolve().parent
AUTH=ROOT.parent/'discovery_rounds/executed_layout_009/layout_binding.py'
MAP=ROOT.parent/'discovery_rounds/functional_mapping_002/c_mapping.hex'

def f32bits(x):return struct.unpack('<I',struct.pack('<f',float(x)))[0]
def writehex(path,values,width=8):path.write_text(''.join(f'{x:0{width}x}\n'for x in values))
def generate(out):
 out.mkdir(parents=True,exist_ok=True)
 spec=importlib.util.spec_from_file_location('layout_authority',AUTH);layout=importlib.util.module_from_spec(spec);spec.loader.exec_module(layout)
 # Small exact integers keep BF16 inputs and all accumulated FP32 products exact.
 A=[[((r*5+k*3+1)%7)-3 for k in range(256)]for r in range(32)]
 B=[[((k*7+c*5+2)%9)-4 for c in range(32)]for k in range(256)]
 memory=[0]*(layout.TOTAL//2);written=set()
 def store(addr,value):
  assert addr%2==0 and 0<=addr<len(memory)*2
  assert addr not in written,'Producer overlap';written.add(addr)
  bits=f32bits(value);assert bits&65535==0
  memory[addr//2]=bits>>16
 for slot in range(2):
  for thread in range(128):
   aa,bb=layout.producer(thread,slot)
   for group in range(4):
    for h in range(8):
     store(aa[group]+2*h,A[thread//16+8*group][128*slot+8*(thread%16)+h])
     store(bb[group]+2*h,B[128*slot+thread//4+32*group][8*(thread%4)+h])
 writehex(out/'inputstorage.hex',memory,4)
 cindices=[int(s,16)for s in MAP.read_text().split()];assert len(cindices)==256 and sorted(cindices)==list(range(256))
 (out/'c_mapping.hex').write_bytes(MAP.read_bytes())
 stages=[];accums=[];cases=[]
 accum=[[[0]*16 for _ in range(16)]for _ in range(4)]
 for slot in range(2):
  for kstep in range(8):
   kstart=128*slot+16*kstep
   for warp in range(4):
    rowbase=16*(warp%2);colbase=16*(warp//2)
    stage=[[sum(A[rowbase+r][k]*B[k][colbase+c]for k in range(kstart,kstart+16))for c in range(16)]for r in range(16)]
    for r in range(16):
     for c in range(16):accum[warp][r][c]+=stage[r][c]
    stagewords=[f32bits(stage[i//16][i%16])for i in cindices]
    accumwords=[f32bits(accum[warp][i//16][i%16])for i in cindices]
    name=f'w{warp}_s{slot}_k{kstep}'
    writehex(out/f'expected_{name}.hex',stagewords)
    writehex(out/f'accumulated_{name}.hex',accumwords)
    cases.append({'warp':warp,'slot':slot,'kstep':kstep,'aggregate_word_offset':len(stages),'stage_file':f'expected_{name}.hex','accumulated_file':f'accumulated_{name}.hex'})
    stages.extend(stagewords);accums.extend(accumwords)
 # Independent full K dot-product confirms all per-step sums, without shared consumer formulas.
 for warp in range(4):
  for r in range(16):
   for c in range(16):assert accum[warp][r][c]==sum(A[16*(warp%2)+r][k]*B[k][16*(warp//2)+c]for k in range(256))
 writehex(out/'expected_all_stages.hex',stages);writehex(out/'expected_all_accumulated.hex',accums)
 full=[f32bits(sum(A[r][k]*B[k][c]for k in range(256)))for r in range(32)for c in range(32)]
 writehex(out/'expected_full_32x32.hex',full)
 receipt={'shared_bytes':layout.TOTAL,'storage_halfwords':len(memory),'written_halfwords':len(written),'matrix_shapes':{'A':[32,256],'B':[256,32],'C':[32,32]},'stage_cases':len(cases),'output_words_per_case':256,'stage_output_words':len(stages),'accumulated_output_words':len(accums),'aggregate_order':'slot, kstep, warp, lane, word','C_order':'Measured c_mapping.hex maps lane*8+word to row*16+column','cases':cases,'oracle':'Direct ordinary integer matrix multiplication; does not call consumer_a/b or reconstruct operands through the functions being tested. All integer sums exactly representable in FP32.','source_sha256':{'layout_binding.py':hashlib.sha256(AUTH.read_bytes()).hexdigest(),'c_mapping.hex':hashlib.sha256(MAP.read_bytes()).hexdigest()},'validation':'1024 full-K products equal accumulated sixteen stage products; producer addresses nonoverlapping and in bounds.','scope':'Selected compiled-software layout; no hardware timing claim.'}
 (out/'manifest.json').write_text(json.dumps(receipt,indent=2)+'\n');print(json.dumps({k:receipt[k]for k in ['storage_halfwords','stage_cases','stage_output_words','accumulated_output_words']}))
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,default=ROOT/'library_generic_vectors');generate(p.parse_args().output)
