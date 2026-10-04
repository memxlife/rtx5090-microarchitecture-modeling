// Bounded original BM32/BN32/BK32 PC1350..15c0 operand hot loop.
// Actual decoded issue controls and service completions; address ALU instructions
// are control-only with precomputed shared offsets, not native address replay.
module native_studied_stage_pipeline #(
 parameter bit ALLOW_WARP_WRITES=0,
 parameter int READ_SLOTS=4,SERVICE_INTERVAL=1,RETURN_DELAY=1,
 parameter int MOVM_SLOTS=4,MOVM_LATENCY=1,MOVM_INTERVAL=1,
 parameter int HMMA_SLOTS=2,HMMA_LATENCY=16,HMMA_INTERVAL=4,ARITHMETIC_MODE=1
)(
 input logic clk,rst,
 input logic write_valid,output logic write_ready,
 input logic[31:0]write_byte_address,input logic[15:0]write_data,
 input logic write_warp_valid,output logic write_warp_ready,
 input logic[31:0]write_warp_byte_addresses[32],
 input logic[15:0]write_warp_halfwords[32],input logic[31:0]write_warp_mask,
 input logic req_valid,output logic req_ready,input logic[31:0]req_id,tile_index,
 input logic[31:0]c_registers[32][8],
 output logic operands_initialized,addresses_legal,
 output logic rsp_valid,input logic rsp_ready,
 output logic[31:0]rsp_id,result_registers[32][8],output int outstanding,
 output logic native_issue_valid,output logic[31:0]native_issue_pc
);
 import native_studied_stage_schedule::*;
 localparam int HALFWORDS=2048;
 typedef enum logic[1:0]{IDLE,RUN,DRAIN,RESPONSE} state_t;
 state_t state;int pc;logic[31:0]saved_id,saved_tile;
 logic[15:0]memory[HALFWORDS];logic initialized[HALFWORDS];
 logic[31:0]a_words[2][32][4],b_raw[2][32][4],b_moved[2][32][4],accumulator[32][8];
 logic a_ready[2][4],b_ready[2][4],mov_ready[2][4],c_ready[2];
 descriptor_t desc,completion_desc;
 native_control_decode::control_t control,completion_control;
 logic dependencies_ready,gate_valid,gate_ready,dispatch_valid,dispatch_ready,issued,gate_error;
 logic[5:0]busy_write,busy_read;logic[3:0]cooldown;
 logic write_complete_valid;logic[6:0]write_complete_tag;
 logic read_req_valid,read_req_ready,read_rsp_valid,read_rsp_ready;
 logic[31:0]read_req_id,read_rsp_id,read_addresses[32],read_inputs[32],read_outputs[32];int read_outstanding;
 logic mov_req_valid,mov_req_ready,mov_rsp_valid,mov_rsp_ready;
 logic[31:0]mov_req_id,mov_rsp_id,mov_inputs[32],mov_outputs[32];int mov_outstanding;
 logic h_req_valid,h_req_ready,h_rsp_valid,h_rsp_ready;
 logic[31:0]h_req_id,h_rsp_id,h_a[32][4],h_b[32][2],h_c[32][4],h_results[32][4];int h_outstanding;
 logic completion_valid,write_address_legal,write_warp_legal;logic[31:0]completion_id;
 function automatic int address(input bit operand_b,input int kk,word_index,lane,tile);
  if(operand_b)return 2048+64*(16*kk+lane/4)+32*(tile%2)+4*(lane%4)+(word_index%2)*512+(word_index/2)*16;
  return 64*(16*(tile/2)+lane/4)+32*kk+4*(lane%4)+(word_index%2)*512+(word_index/2)*16;
 endfunction
 assign write_address_legal=write_byte_address[0]==0&&write_byte_address<=4094;
 // Memory is read at native LD.E issue, not at external stage acceptance.
 // Block writes while that request is offered so a stalled read payload stays stable.
 assign write_ready=!rst&&write_address_legal&&!read_req_valid;
 // Optional ideal vector commit port. It does not model a native STS issue rate.
 // Disabled by default so legacy callers need not drive the optional inputs.
 always_comb begin
  write_warp_legal=1;
  if(ALLOW_WARP_WRITES)begin
   for(int lane=0;lane<32;lane++)if(write_warp_mask[lane])begin
    if(write_warp_byte_addresses[lane][0]!=0||write_warp_byte_addresses[lane]>4094)write_warp_legal=0;
    for(int other=0;other<lane;other++)if(write_warp_mask[other]&&
     write_warp_byte_addresses[lane]==write_warp_byte_addresses[other])write_warp_legal=0;
   end
  end
 end
 assign write_warp_ready=ALLOW_WARP_WRITES&&!rst&&write_warp_legal&&!write_valid&&!read_req_valid;
 assign req_ready=!rst&&state==IDLE&&addresses_legal&&operands_initialized;
 assign rsp_valid=!rst&&state==RESPONSE;assign rsp_id=saved_id;
 assign outstanding=state==IDLE?0:1;
 assign native_issue_valid=issued;assign native_issue_pc=32'h1350+32'(16*pc);
 always_comb begin
  addresses_legal=tile_index<4;operands_initialized=addresses_legal;
  if(addresses_legal)for(int kk=0;kk<2;kk++)for(int lane=0;lane<32;lane++)for(int word_index=0;word_index<4;word_index++)begin
   operands_initialized=operands_initialized&&
    initialized[address(0,kk,word_index,lane,int'(tile_index))/2]&&
    initialized[address(0,kk,word_index,lane,int'(tile_index))/2+1]&&
    initialized[address(1,kk,word_index,lane,int'(tile_index))/2]&&
    initialized[address(1,kk,word_index,lane,int'(tile_index))/2+1];
  end
  desc='0;if(pc<INSTRUCTIONS)desc=descriptor(pc);
  control=native_control_decode::decode(desc.raw);
  dependencies_ready=1;
  if(desc.kind==2)dependencies_ready=b_ready[desc.kk][desc.word_index];
  if(desc.kind==3)begin
   dependencies_ready=c_ready[desc.upper_half];
   for(int w=0;w<4;w++)dependencies_ready=dependencies_ready&&a_ready[desc.kk][w];
   for(int w=0;w<2;w++)dependencies_ready=dependencies_ready&&mov_ready[desc.kk][2*int'(desc.upper_half)+w];
  end
  dispatch_ready=1;
  case(desc.kind)
   1:dispatch_ready=read_req_ready;
   2:dispatch_ready=mov_req_ready;
   3:dispatch_ready=h_req_ready;
   default:dispatch_ready=1;
  endcase
  for(int lane=0;lane<32;lane++)begin
   int location;location=address(desc.operand_b,int'(desc.kk),int'(desc.word_index),lane,int'(saved_tile));
   read_addresses[lane]=32'(location);
   read_inputs[lane]={memory[location/2+1],memory[location/2]};
   mov_inputs[lane]=b_raw[desc.kk][lane][desc.word_index];
   for(int w=0;w<4;w++)begin
    h_a[lane][w]=a_words[desc.kk][lane][w];
    h_c[lane][w]=accumulator[lane][4*int'(desc.upper_half)+w];
   end
   for(int w=0;w<2;w++)h_b[lane][w]=b_moved[desc.kk][lane][2*int'(desc.upper_half)+w];
   for(int w=0;w<8;w++)result_registers[lane][w]=accumulator[lane][w];
  end
  // One completion is acknowledged per edge so the barrier gate receives one
  // actual write-completion event. Other services retain their response slots.
  read_rsp_ready=!rst&&(state==RUN||state==DRAIN);
  mov_rsp_ready=read_rsp_ready&&!read_rsp_valid;
  h_rsp_ready=mov_rsp_ready&&!mov_rsp_valid;
  completion_valid=(read_rsp_valid&&read_rsp_ready)||(mov_rsp_valid&&mov_rsp_ready)||(h_rsp_valid&&h_rsp_ready);
  completion_id=read_rsp_valid?read_rsp_id:(mov_rsp_valid?mov_rsp_id:h_rsp_id);
  completion_desc='0;
  if(completion_valid&&completion_id<INSTRUCTIONS)completion_desc=descriptor(int'(completion_id));
  completion_control=native_control_decode::decode(completion_desc.raw);
  write_complete_valid=completion_valid&&completion_control.write_barrier!=7;
  write_complete_tag=7'(completion_id);
 end
 assign gate_valid=!rst&&state==RUN&&pc<INSTRUCTIONS&&dependencies_ready;
 assign read_req_valid=dispatch_valid&&desc.kind==1;assign read_req_id=32'(pc);
 assign mov_req_valid=dispatch_valid&&desc.kind==2;assign mov_req_id=32'(pc);
 assign h_req_valid=dispatch_valid&&desc.kind==3;assign h_req_id=32'(pc);
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;pc<=0;saved_id<=0;saved_tile<=0;
   for(int i=0;i<HALFWORDS;i++)initialized[i]<=0;
   for(int kk=0;kk<2;kk++)for(int w=0;w<4;w++)begin a_ready[kk][w]<=0;b_ready[kk][w]<=0;mov_ready[kk][w]<=0;end
   for(int h=0;h<2;h++)c_ready[h]<=0;
   for(int lane=0;lane<32;lane++)for(int w=0;w<8;w++)accumulator[lane][w]<=0;
  end else begin
   if(write_valid&&!write_address_legal)$fatal(1,"Invalid native stage shared write");
   if(ALLOW_WARP_WRITES&&write_warp_valid&&!write_warp_legal)$fatal(1,"Invalid native stage warp write");
   if(req_valid&&!addresses_legal)$fatal(1,"Invalid native stage tile index");
   if(gate_error)$fatal(1,"Native stage issue/barrier tracking error");
   if(write_valid&&write_ready)begin memory[write_byte_address/2]<=write_data;initialized[write_byte_address/2]<=1;end
   if(ALLOW_WARP_WRITES&&write_warp_valid&&write_warp_ready)
    for(int lane=0;lane<32;lane++)if(write_warp_mask[lane])begin
     memory[write_warp_byte_addresses[lane]/2]<=write_warp_halfwords[lane];
     initialized[write_warp_byte_addresses[lane]/2]<=1;
    end
   if(completion_valid&&completion_id>=INSTRUCTIONS)$fatal(1,"Unknown native stage completion ID");
   if(read_rsp_valid&&read_rsp_ready)begin
    if(completion_desc.kind!=1)$fatal(1,"Read completion ID is not a load");
    for(int lane=0;lane<32;lane++)begin
     if(completion_desc.operand_b)b_raw[completion_desc.kk][lane][completion_desc.word_index]<=read_outputs[lane];
     else a_words[completion_desc.kk][lane][completion_desc.word_index]<=read_outputs[lane];
    end
    if(completion_desc.operand_b)b_ready[completion_desc.kk][completion_desc.word_index]<=1;
    else a_ready[completion_desc.kk][completion_desc.word_index]<=1;
   end
   if(mov_rsp_valid&&mov_rsp_ready)begin
    if(completion_desc.kind!=2)$fatal(1,"MOVM completion ID is not MOVM");
    for(int lane=0;lane<32;lane++)b_moved[completion_desc.kk][lane][completion_desc.word_index]<=mov_outputs[lane];
    mov_ready[completion_desc.kk][completion_desc.word_index]<=1;
   end
   if(h_rsp_valid&&h_rsp_ready)begin
    if(completion_desc.kind!=3)$fatal(1,"HMMA completion ID is not HMMA");
    for(int lane=0;lane<32;lane++)for(int w=0;w<4;w++)accumulator[lane][4*int'(completion_desc.upper_half)+w]<=h_results[lane][w];
    c_ready[completion_desc.upper_half]<=1;
   end
   case(state)
    IDLE:if(req_valid&&req_ready)begin
     saved_id<=req_id;saved_tile<=tile_index;pc<=0;state<=RUN;
     for(int kk=0;kk<2;kk++)for(int w=0;w<4;w++)begin a_ready[kk][w]<=0;b_ready[kk][w]<=0;mov_ready[kk][w]<=0;end
     for(int h=0;h<2;h++)c_ready[h]<=1;
     for(int lane=0;lane<32;lane++)for(int w=0;w<8;w++)accumulator[lane][w]<=c_registers[lane][w];
    end
    RUN:if(issued)begin
     if(desc.kind==3)c_ready[desc.upper_half]<=0;
     if(pc==INSTRUCTIONS-1)begin pc<=INSTRUCTIONS;state<=DRAIN;end
     else pc<=pc+1;
    end
    DRAIN:if(read_outstanding==0&&mov_outstanding==0&&h_outstanding==0&&busy_write==0&&busy_read==0&&cooldown==0&&c_ready[0]&&c_ready[1])state<=RESPONSE;
    RESPONSE:if(rsp_valid&&rsp_ready)state<=IDLE;
    default:$fatal(1,"Invalid native stage state");
   endcase
  end
 end
 decoded_native_issue_gate #(.MAX_OPS(64),.TAG_W(7),.COUNT_W(7)) gate(
  .clk,.reset(rst||state==IDLE),.instr_valid(gate_valid),.instr_ready(gate_ready),
  .operation_id(7'(pc)),.control,.dispatch_valid,.dispatch_ready,.issued,
  .write_complete_valid,.write_complete_tag,.read_complete_valid(1'b0),.read_complete_tag(7'd0),
  .busy_write_mask(busy_write),.busy_read_mask(busy_read),.cooldown,.error_sticky(gate_error)
 );
 warp_shared_read_service #(.SLOTS(READ_SLOTS),.SERVICE_INTERVAL(SERVICE_INTERVAL),.RETURN_DELAY(RETURN_DELAY)) reads(
  .clk,.rst,.req_valid(read_req_valid),.req_ready(read_req_ready),.req_id(read_req_id),
  .byte_addresses(read_addresses),.input_words(read_inputs),.rsp_valid(read_rsp_valid),.rsp_ready(read_rsp_ready),
  .rsp_id(read_rsp_id),.output_words(read_outputs),.outstanding(read_outstanding)
 );
 native_movm_word_pipeline #(.SLOTS(MOVM_SLOTS),.LATENCY(MOVM_LATENCY),.INTERVAL(MOVM_INTERVAL)) moves(
  .clk,.rst,.req_valid(mov_req_valid),.req_ready(mov_req_ready),.req_id(mov_req_id),.input_words(mov_inputs),
  .rsp_valid(mov_rsp_valid),.rsp_ready(mov_rsp_ready),.rsp_id(mov_rsp_id),.output_words(mov_outputs),.outstanding(mov_outstanding)
 );
 native_hmma16816_adapter #(.SLOTS(HMMA_SLOTS),.LATENCY(HMMA_LATENCY),.INTERVAL(HMMA_INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) tensor(
  .clk,.rst,.req_valid(h_req_valid),.req_ready(h_req_ready),.req_id(h_req_id),.a_registers(h_a),.b_registers(h_b),.c_registers(h_c),
  .rsp_valid(h_rsp_valid),.rsp_ready(h_rsp_ready),.rsp_id(h_rsp_id),.result_registers(h_results),.outstanding(h_outstanding)
 );
endmodule
