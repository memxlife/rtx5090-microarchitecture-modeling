"""Replay captured post-MOVM hardware words, not a duplicated permutation oracle."""
from pathlib import Path
import hashlib,json,struct,subprocess,tempfile
ROOT=Path(__file__).resolve().parent
RTL=ROOT.parent
EVIDENCE=RTL/'discovery_rounds/functional_mapping_002'
def bf16(value):
 return struct.unpack('<I',struct.pack('<f',float(value)))[0]>>16
def run():
 captured=struct.unpack('<'+'H'*(515*256),(EVIDENCE/'b_fragments.bin').read_bytes())
 permutation=json.loads((EVIDENCE/'analysis.json').read_text())['movm_post_to_pre_halfword_permutation']
 assert all((source//2)%4==(dest//2)%4 for dest,source in enumerate(permutation))
 assert all(permutation[lane*8+2*word+h]-2*word==permutation[lane*8+h] for lane in range(32) for word in range(4) for h in range(2))
 raw=[];gold=[]
 for case in range(515):
  if case in (0,2):matrix=list(range(1,257))
  elif case<259:matrix=[int(i//16==i%16) for i in range(256)]
  else:matrix=[int(i==case-259) for i in range(256)]
  for word in range(4):
   for lane in range(32):
    row=lane//4+8*(word%2);column=2*(lane%4)+8*(word//2)
    raw.append(bf16(matrix[16*row+column])|(bf16(matrix[16*row+column+1])<<16))
    index=case*256+lane*8+2*word
    gold.append(captured[index]|(captured[index+1]<<16))
 sources=[ROOT/'library_movm_permutation.sv',ROOT/'native_movm_word_pipeline.sv',ROOT/'native_movm_word_tb.sv']
 cases=[]
 with tempfile.TemporaryDirectory(prefix='native-movm-') as tmp:
  tmp=Path(tmp);a=tmp/'raw.hex';b=tmp/'gold.hex'
  a.write_text(''.join(f'{x:08x}\n' for x in raw));b.write_text(''.join(f'{x:08x}\n' for x in gold))
  for latency,interval in [(1,1),(7,3)]:
   build=tmp/f'build_{latency}_{interval}'
   result=subprocess.run(['verilator','--binary','--timing','-j','2','-Wno-fatal','--top-module','native_movm_word_tb',f'-GLATENCY={latency}',f'-GINTERVAL={interval}','--Mdir',str(build),*map(str,sources)],capture_output=True,text=True)
   (ROOT/f'native_movm_build_{latency}_{interval}.log').write_text(result.stdout+result.stderr)
   assert result.returncode==0,result.stdout+result.stderr
   result=subprocess.run([str(build/'Vnative_movm_word_tb'),f'+raw={a}',f'+gold={b}'],capture_output=True,text=True)
   assert result.returncode==0 and 'checked_words=65920' in result.stdout,result.stdout+result.stderr
   cases.append({'latency':latency,'interval':interval,'operations':2060,'checked_words':65920,'stdout':result.stdout})
 receipt={'all_passed':True,'hardware_mapping_cases':515,'checked_output_words':131840,'cases':cases,'oracle':'Actual saved post-MOVM BF16 hardware fragments; raw source words independently reconstructed from the original coordinate, identity and basis inputs and ordinary shared-load addresses.','evidence_boundary':'Supported finite BF16 mapping only; arbitrary bit semantics and intrinsic MOVM timing are not identified. Both cycle configurations are synthetic.','source_sha256':{str(p.relative_to(RTL)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources+[EVIDENCE/'b_fragments.bin',EVIDENCE/'analysis.json']},'new_identified_registry_fields':0}
 (ROOT/'native_movm_word_verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
 print('MOVM:131840 returned words match515 saved hardware mapping cases in two synthetic timing configurations.')
if __name__=='__main__':run()
