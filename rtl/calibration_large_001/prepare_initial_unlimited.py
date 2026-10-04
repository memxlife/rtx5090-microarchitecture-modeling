from pathlib import Path
import json
D=Path(__file__).resolve().parent; S=D.parent/'calibration_connected_001'
s=(S/'calibration_shared_l2.sv').read_text().replace('module calibration_shared_l2','module large_slice_l2').replace('parameter int SMS=2,L2_SETS=64','parameter int SET_STRIDE=48,SMS=170,L2_SETS=1024').replace('(read_req_byte_address[sm]>>7)%32\'(L2_SETS)','(read_req_byte_address[sm]>>7)/32\'(SET_STRIDE)%32\'(L2_SETS)').replace("32'(128*L2_SETS)","32'(128*L2_SETS*SET_STRIDE)")
(D/'large_slice_l2.sv').write_text(s)
s=(S/'calibration_connected_top.sv').read_text().replace('module calibration_connected_top','module large_connected_top').replace('parameter int L2_SETS=64,L2_WAYS=8,OWNER_SLOTS=8,MSHRS=4,','parameter int SLICES=48,L2_SETS=1024,L2_WAYS=16,OWNER_SLOTS=8,MSHRS=4,').replace('parameter int SMS=2,CONTEXTS=2,M=64,N=96,K=64','parameter int SMS=170,CONTEXTS=11,M=2048,N=2112,K=1536')
# Separate backing interfaces per slice. Arbitration inside each slice is explicit.
for n in ['backing_req_valid','backing_req_ready','backing_rsp_valid','backing_rsp_ready','store_backing_req_valid','store_backing_req_ready','store_backing_rsp_valid','store_backing_rsp_ready']:
 import re
 s=re.sub(r'\b'+n+r'\b',n+'[SLICES]',s,count=1)
for n in ['backing_req_id','backing_req_byte_address','backing_rsp_id','backing_rsp_data','store_backing_req_id','store_backing_req_byte_address','store_backing_req_data','store_backing_req_word_mask','store_backing_rsp_id']:
 s=re.sub(r'\b'+n+r'\b',n+'[SLICES]',s,count=1)
a=s.index(' calibration_shared_l2 #(');b=s.index(' // elapsed_cycles',a)
ports=['read_req_valid','read_req_ready','read_rsp_valid','read_rsp_ready','write_req_valid','write_req_ready','write_rsp_valid','write_rsp_ready']
outputs=['read_req_ready','read_rsp_valid','write_req_ready','write_rsp_valid']
counters=['l2_read_requests','l2_read_hits','l2_read_misses','l2_merged_misses','l2_actual_fills','live_owners','live_mshrs','peak_owners','peak_mshrs']
t=''
for n in outputs:t+=f' logic[SMS-1:0] slice_{n}[SLICES];\n'
t+=' logic[31:0]slice_read_rsp_id[SLICES][SMS],slice_write_rsp_id[SLICES][SMS];logic[255:0]slice_read_rsp_data[SLICES][SMS];\n'
for n in counters:t+=f' int slice_{n}[SLICES];\n'
t+=' always_comb begin\n'
for n in counters:t+=f'  {n}=0;for(int sl=0;sl<SLICES;sl++){n}+=slice_{n}[sl];\n'
t+='  for(int sm=0;sm<SMS;sm++)begin\n'
for n in outputs:t+=f'   {n}[sm]=0;for(int sl=0;sl<SLICES;sl++){n}[sm]|=slice_{n}[sl][sm];\n'
t+='   read_rsp_id[sm]=0;read_rsp_data[sm]=0;write_rsp_id[sm]=0;\n   for(int sl=0;sl<SLICES;sl++)begin\n    if(slice_read_rsp_valid[sl][sm])begin read_rsp_id[sm]=slice_read_rsp_id[sl][sm];read_rsp_data[sm]=slice_read_rsp_data[sl][sm];end\n    if(slice_write_rsp_valid[sl][sm])write_rsp_id[sm]=slice_write_rsp_id[sl][sm];\n   end\n  end\n end\n'
t+=' for(genvar sl=0;sl<SLICES;sl++)begin:cache_slices\n logic[SMS-1:0] routed_read,routed_write;\n always_comb for(int sm=0;sm<SMS;sm++)begin\n routed_read[sm]=read_req_valid[sm]&&((read_req_byte_address[sm]>>7)%SLICES==sl);\n routed_write[sm]=write_req_valid[sm]&&((write_req_byte_address[sm]>>7)%SLICES==sl);\n end\n large_slice_l2 #(.SET_STRIDE(SLICES),.SMS(SMS),.L2_SETS(L2_SETS),.L2_WAYS(L2_WAYS),.OWNER_SLOTS(OWNER_SLOTS),.MSHRS(MSHRS)) gateway(\n .clk,.rst,.hit_delay_cycles(l2_hit_delay_cycles),\n'
connections=[]
for n in counters:connections.append(f'.{n}(slice_{n}[sl])')
for n in ports:
 v='routed_read' if n=='read_req_valid' else 'routed_write' if n=='write_req_valid' else f'slice_{n}[sl]' if n in outputs else n
 connections.append(f'.{n}({v})')
for n in ['read_rsp_id','read_rsp_data','write_rsp_id']:connections.append(f'.{n}(slice_{n}[sl])')
for n in ['read_req_id','read_req_byte_address','write_req_id','write_req_byte_address','write_req_data','write_req_word_mask']:connections.append('.'+n)
for n in ['backing_req_valid','backing_req_ready','backing_req_id','backing_req_byte_address','backing_rsp_valid','backing_rsp_ready','backing_rsp_id','backing_rsp_data','store_backing_req_valid','store_backing_req_ready','store_backing_req_id','store_backing_req_byte_address','store_backing_req_data','store_backing_req_word_mask','store_backing_rsp_valid','store_backing_rsp_ready','store_backing_rsp_id']:connections.append(f'.{n}({n}[sl])')
t+=',\n '.join(connections)+');\n end\n'
s=s[:a]+t+s[b:]
s=s.replace(' logic[31:0]slice_read_rsp_id',' logic[SMS-1:0] slice_read_rsp_ready[SLICES],slice_write_rsp_ready[SLICES];\n logic[31:0]slice_read_rsp_id')
s=s.replace(' always_comb begin\n  l2_read_requests',' always_comb begin\n  for(int sl=0;sl<SLICES;sl++)begin slice_read_rsp_ready[sl]=0;slice_write_rsp_ready[sl]=0;end\n  l2_read_requests')
s=s.replace('  for(int sm=0;sm<SMS;sm++)begin\n   read_req_ready','  for(int sm=0;sm<SMS;sm++)begin\n   bit read_chosen,write_chosen;read_chosen=0;write_chosen=0;\n   read_req_ready')
s=s.replace('if(slice_read_rsp_valid[sl][sm])begin','if(slice_read_rsp_valid[sl][sm]&&!read_chosen)begin read_chosen=1;slice_read_rsp_ready[sl][sm]=read_rsp_ready[sm];')
s=s.replace('if(slice_write_rsp_valid[sl][sm])write_rsp_id[sm]=slice_write_rsp_id[sl][sm];','if(slice_write_rsp_valid[sl][sm]&&!write_chosen)begin write_chosen=1;slice_write_rsp_ready[sl][sm]=write_rsp_ready[sm];write_rsp_id[sm]=slice_write_rsp_id[sl][sm];end')
s=s.replace('.read_rsp_ready(read_rsp_ready)', '.read_rsp_ready(slice_read_rsp_ready[sl])').replace('.write_rsp_ready(write_rsp_ready)', '.write_rsp_ready(slice_write_rsp_ready[sl])')
(D/'large_connected_top.sv').write_text(s)
(D/'contract.json').write_text(json.dumps({'physical_sms':170,'contexts_per_sm':11,'l2_slices':48,'sets_per_slice':1024,'ways':16,'line_bytes':128,'l2_bytes':48*1024*16*128,'slice_mapping':'(byte_address/128)%48','mapping_status':'provisional','per_slice_admissions_per_cycle':1,'owner_slots_per_slice':8,'mshrs_per_slice':4,'target_shapes':[[2048,2112,1536],[2048,2112,3072]],'acceptance':'Every output matches; record actual host wall time and counters; timing comparison requires matching clock and cache conditions. Do not fit target runtimes.','state':'implementation_in_progress'},indent=2)+'\n')
