"""Generate the bounded original hot-loop descriptors from saved native instructions."""
from pathlib import Path
import hashlib,json,re
ROOT=Path(__file__).resolve().parent
SOURCE=ROOT.parent/'discovery_rounds/original_native_schedule/original_kernel_schedule.json'
d=json.loads(SOURCE.read_text())
rows=[x for x in d['instructions'] if 0x1350<=int(x['pc'],16)<=0x15c0]
assert len(rows)==40 and [int(x['pc'],16) for x in rows]==list(range(0x1350,0x15d0,16))
# Semantic operand groups are reconstructed from the saved explicit register bases.
a={**{12+i:(0,i) for i in range(4)},**{8+i:(1,i) for i in range(4)}}
b={28:(0,0),29:(0,1),24:(0,2),25:(0,3),5:(1,0),6:(1,1),7:(1,2),26:(1,3)}
lines=['// Generated from original_kernel_schedule.json; do not hand-edit controls.',f'// Source SHA256 {hashlib.sha256(SOURCE.read_bytes()).hexdigest()}','package native_studied_stage_schedule;',' localparam int INSTRUCTIONS=40;',' typedef struct packed {logic[127:0] raw;logic[1:0] kind;logic operand_b;logic kk;logic[1:0] word_index;logic upper_half;} descriptor_t;',' function automatic descriptor_t descriptor(input int index);','  descriptor_t d;d=\'0;','  case(index)']
for i,x in enumerate(rows):
 op=x['opcode'];kind=0;operand_b=kk=word=upper=0
 if op=='LD.E':
  kind=1;dst=x['generic_load']['destination_register'];operand_b=int(dst in b);kk,word=(b if operand_b else a)[dst]
 elif op=='MOVM.16.MT88':
  kind=2;kk,word=b[x['operand_registers']['source']]
 elif op=='HMMA.16816.F32.BF16':
  kind=3;v=x['operand_register_bases'];kk=int(v['A']==8);upper=int(v['C_destination']==16)
  assert v['A'] in (8,12) and v['C_destination'] in (16,20)
 else:assert op in ('UMOV','IADD.64','LEA','LEA.HI.X','NOP','WARPSYNC.ALL'),op
 assert x['control']['read_barrier']==7
 lines.append(f"   {i}:begin d.raw=128'h{x['raw_high']}{x['raw_low']};d.kind=2'd{kind};d.operand_b=1'b{operand_b};d.kk=1'b{kk};d.word_index=2'd{word};d.upper_half=1'b{upper};end // {x['pc']} {op}")
lines+=['   default:$fatal(1,"Native stage instruction index out of range");','  endcase','  return d;',' endfunction','endpackage']
ROOT.joinpath('native_studied_stage_schedule.sv').write_text('\n'.join(lines)+'\n')
ROOT.joinpath('native_studied_stage_schedule_generation.json').write_text(json.dumps({'source_sha256':hashlib.sha256(SOURCE.read_bytes()).hexdigest(),'instructions':40,'opcodes':{op:sum(x['opcode']==op for x in rows) for op in sorted({x['opcode'] for x in rows})},'control_only_semantics':'UMOV/IADD/LEA addresses precomputed; WARPSYNC one collective warp; no full address-ALU or CTA barrier reconstruction','all_read_barriers_disabled':True},indent=2)+'\n')
