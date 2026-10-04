#!/usr/bin/env python3
"""Golden vectors for the original mode3 GEMM, computed by ordinary dot products."""
import argparse,hashlib,json,struct
from pathlib import Path
ROOT=Path(__file__).resolve().parent
SOURCE=ROOT.parent.parent/'diagnostic_050/gemm_checked.cu'
CMAP=ROOT.parent/'discovery_rounds/functional_mapping_002/c_mapping.hex'
def bits(x):return struct.unpack('<I',struct.pack('<f',x))[0]
def hexfile(path,values,width):path.write_text(''.join(f'{x:0{width}x}\n'for x in values))
def build(out,BM,BN):
 M,N,K,BK=2048,2112,1536,32
 # Only the first CTA is represented. Global row/column strides stay exact.
 A=[[((r*K+k)%17)-8 for k in range(K)]for r in range(BM)]
 B=[[((k*N+c)%13)-6 for c in range(BN)]for k in range(K)]
 ci=[int(x,16)for x in CMAP.read_text().split()];assert sorted(ci)==list(range(256))
 d=out/f'bm{BM}_bn{BN}';d.mkdir(parents=True,exist_ok=True)
 frames=[];gold=[];acc=[[0]*BN for _ in range(BM)];tiles=(BM//16)*(BN//16);checks=0
 for stage in range(K//BK):
  k0=stage*BK
  for r in range(BM):
   for k in range(k0,k0+BK):
    f=bits(A[r][k]/16);assert f&65535==0;frames.append(f>>16)
  for k in range(k0,k0+BK):
   for c in range(BN):
    f=bits(B[k][c]/16);assert f&65535==0;frames.append(f>>16)
  for tile in range(tiles):
   r0=16*(tile//(BN//16));c0=16*(tile%(BN//16))
   for kk in range(2):
    start=k0+16*kk
    for r in range(r0,r0+16):
     for c in range(c0,c0+16):acc[r][c]+=sum(A[r][k]*B[k][c]for k in range(start,start+16))
    gold.extend(bits(acc[r0+i//16][c0+i%16]/256)for i in ci)
 # Separate full-K direct dot products establish the accumulated output oracle.
 full=[]
 for r in range(BM):
  for c in range(BN):
   expected=sum(A[r][k]*B[k][c]for k in range(K));assert acc[r][c]==expected;checks+=1;full.append(bits(expected/256))
 hexfile(d/'inputstorage.hex',frames,4);hexfile(d/'expected_accumulated.hex',gold,8);hexfile(d/'expected_full.hex',full,8);(d/'c_mapping.hex').write_bytes(CMAP.read_bytes())
 manifest={'tile':[BM,BN,BK],'global_shape':[M,N,K],'scope':'First CTA rowbase0,colbase0; original mode3, alpha1, initial Czero. No GPU timing claim.','stages':48,'tiles':tiles,'ksteps_per_stage':2,'frame_halfwords':BK*(BM+BN),'frame_bytes':2*BK*(BM+BN),'input_order':'stage, A row-major BMx32, B row-major32xBN','expected_order':'stage, tile, kstep, lane, element','expected_word_offset':'((stage*tiles+tile)*2+kstep)*256+lane*8+element','tile_to_warp':'warp=tile%4; accumulator slot=tile//4; original per-warp order j outer then kk','expected_words':len(gold),'full_K_products_checked':checks,'BF16_input_definition':'A=((row*K+k)%17-8)/16; B=((k*N+col)%13-6)/16','oracle':'Integer dot products divided by256, exactly representable FP32. No consumer address functions used.','source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'c_mapping_sha256':hashlib.sha256(CMAP.read_bytes()).hexdigest()}
 (d/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n');print(json.dumps({'tile':[BM,BN,BK],'expected_words':len(gold),'full_products_checked':checks}))
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,default=ROOT/'studied_gemm_vectors');a=p.parse_args();build(a.output,32,32);build(a.output,64,48)
if __name__=='__main__':main()
