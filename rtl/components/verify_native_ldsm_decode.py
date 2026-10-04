"""Check partial native descriptor decoding against compiled and executed forms."""
from pathlib import Path
import json,re,hashlib,subprocess,tempfile
ROOT=Path(__file__).resolve().parent
STUDY=ROOT.parent
SERVICE=STUDY/'parameter_sweep/ldsm_service'
def run():
 measured=json.loads((SERVICE/'analysis.json').read_text());assert measured['all_predictions_match']
 descriptors=[]
 for c in measured['native_encodings']:
  descriptors.append({'low':int(c['low_word'],16),'high':int(c['high_word'],16),'width':c['width'],'transpose':c['transpose'],'destination':4,'address':3})
 lines=(STUDY/'discovery_rounds/ldsm_mapping_003/ldsm_mapping.sass').read_text().splitlines()
 for i,line in enumerate(lines):
  if 'LDSM.16.' in line:
   m=re.search(r'LDSM.16.(MT88|M88).4 R(\d+), \[R(\d+)\]',line);assert m,line
   words=re.findall(r'0x[0-9a-f]{16}',line+' '+lines[i+1]);assert len(words)==2
   descriptors.append({'low':int(words[0],16),'high':int(words[1],16),'width':4,'transpose':int(m[1]=='MT88'),'destination':int(m[2]),'address':int(m[3])})
 assert len(descriptors)==8
 sources=[ROOT/'native_ldsm_decode.sv',ROOT/'native_ldsm_decode_tb.sv']
 with tempfile.TemporaryDirectory(prefix='native-decode-') as tmp:
  tmp=Path(tmp);vectors=tmp/'vectors';vectors.mkdir()
  for filename,key in [('lows','low'),('highs','high'),('widths','width'),('transposes','transpose'),('destinations','destination'),('addresses','address')]:
   (vectors/(filename+'.hex')).write_text(''.join(f'{c[key]:016x}\n' for c in descriptors))
  result=subprocess.run(['verilator','--binary','--timing','-Wno-fatal','--top-module','native_ldsm_decode_tb','--Mdir',str(tmp/'build'),*map(str,sources)],text=True,capture_output=True)
  (ROOT/'native_ldsm_decode_build.log').write_text(result.stdout+result.stderr);assert result.returncode==0,result.stdout+result.stderr
  result=subprocess.run([str(tmp/'build/Vnative_ldsm_decode_tb'),f'+vectors={vectors}'],text=True,capture_output=True);assert result.returncode==0 and 'PASS:8 native descriptors' in result.stdout,result.stdout+result.stderr
 receipt={'all_passed':True,'descriptors':descriptors,'source_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},'output':result.stdout,'scope':'Six observed sm120 unpredicated register-direct LDSM16 forms and two separate mapping-kernel instances; partial descriptor only','unsupported':['predicated forms','address offsets','other opcodes','reserved format/width bits','scheduling controls'],'hardware_timing_identified':False,'full_decoder_implemented':False}
 (ROOT/'native_ldsm_decode_verification.json').write_text(json.dumps(receipt,indent=2)+'\n');print('Native LDSM descriptor:8 observed forms and5 unsupported controls passed.')
if __name__=='__main__':run()
