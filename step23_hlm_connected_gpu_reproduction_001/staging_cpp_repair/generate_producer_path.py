from pathlib import Path
import shutil,sys,re,json,hashlib
S=Path(__file__).resolve().parents[2];D=Path(__file__).resolve().parent;B=S/'rtl/calibration_large_001/event_cpp'
sys.path.insert(0,str((S/'step6_data_path_mip_001').resolve()));from extract_instructions import parse
src=S/'step21_memory_path_ablation_001/anchor_gemm_only.sass';ins=parse(src.read_text(),False);skip={0x290:0x570,0x9f0:0xcb0};back={0x960:0x710,0xff0:0xd40};seen={x:0 for x in back};path=[];pc=0x220
while pc<0x1010:
 x=dict(ins[pc]);path.append(x)
 if pc in skip:pc=skip[pc];continue
 if pc in back:
  seen[pc]+=1
  if seen[pc]==1:pc=back[pc];continue
 pc+=16
loadmap={0x7c0:1,0x7e0:2,0x830:0,0x850:3,0xea0:32,0xef0:33,0xf00:34,0xf20:35};storemap={0x900:1,0x910:2,0x930:0,0x940:3,0xfb0:32,0xfc0:33,0xfd0:34,0xfe0:35};visit={};rows=[]
for x in path:
 pc=x['pc'];group=-1
 if pc in loadmap or pc in storemap:
  v=visit.get(pc,0);visit[pc]=v+1;group=(loadmap|storemap)[pc]+v*4
 if x['opcode'].split('.')[0]=='PRMT' and '@'in x['text']and'RZ'in x['text']:x['src']=[];x['dst']=[];x['wr']=-1;x['rd']=-1
 assert max(x['src']+x['dst']+[0])<64
 rows.append({**x,'group':group})
assert sum(x['kind']==1 for x in rows)==16
assert sum(x['kind']==2 for x in rows)==16
h='#pragma once\n#include <vector>\nnamespace staging_event {\nstruct Op {int pc,kind,req,wr,rd,group;std::vector<int>src,dst;};\ninline const std::vector<Op>& producer_path(){static const std::vector<Op>p={\n'
for x in rows:
 h+='{'+','.join(map(str,[x['pc'],x['kind'],x['req'],x['wr'],x['rd'],x['group']]))+',{'+','.join(map(str,x['src']))+'},{'+','.join(map(str,x['dst']))+'}},\n'
h+='};return p;}\n}\n';(D/'producer_path.hpp').write_text(h)
(D/'producer_path.json').write_text(json.dumps({'source':str(src),'sha256':hashlib.sha256(src.read_bytes()).hexdigest(),'scope':'Full inbounds128thread producer prefix through first BAR; source CFG assumptions carried from reviewedStep21. Predicatedfalsezero-fill retained as no-effectissue.','rows':rows},indent=2)+'\n')
