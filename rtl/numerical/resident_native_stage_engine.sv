// Resident bounded native stages: independent context storage/state, ONE shared service set.
// Epoch tags isolate reused context windows. Global RR and timing remain hypotheses.
// Round-robin ONE global issue port and read>move>matrix return priority are
// simulation hypotheses, not RTX5090 scheduler topology or bandwidth facts.
// Address ALU is control-only; offsets precomputed, entry barrier assumed.
module resident_native_stage_engine #(
 parameter int CONTEXTS=2,
 parameter int WARPS=4,parameter bit ALLOW_WARP_WRITES=0,
 parameter int READ_SLOTS=4,SERVICE_INTERVAL=1,RETURN_DELAY=1,
 parameter int MOVM_SLOTS=4,MOVM_LATENCY=1,MOVM_INTERVAL=1,
 parameter int HMMA_SLOTS=2,HMMA_LATENCY=16,HMMA_INTERVAL=4,ARITHMETIC_MODE=1
)(
 input logic clk,rst,
 input logic[31:0]write_context,
 input logic write_valid,output logic write_ready,
 input logic[31:0]write_byte_address,input logic[15:0]write_data,
 input logic write_warp_valid,output logic write_warp_ready,
 input logic[31:0]write_warp_byte_addresses[32],
 input logic[15:0]write_warp_halfwords[32],input logic[31:0]write_warp_mask,
 input logic req_valid,output logic req_ready,input logic[31:0]req_context,req_id,
 input logic[31:0]c_registers[WARPS][32][8],
 output logic operands_initialized,addresses_legal,
 output logic[CONTEXTS-1:0]context_ready,context_initialized,
 output logic rsp_valid,input logic rsp_ready,
 output logic[31:0]rsp_context,rsp_id,result_registers[WARPS][32][8],output int outstanding,
 output logic[WARPS-1:0] warp_drained[CONTEXTS],warp_memory_safe[CONTEXTS],
 output logic native_issue_valid,output logic[31:0]native_issue_context,native_issue_warp,native_issue_pc
);
 import native_studied_stage_schedule::*;
 localparam int HALFWORDS=2048,TOTAL_WARPS=CONTEXTS*WARPS;
 localparam int LOCAL_BITS=$clog2(TOTAL_WARPS*INSTRUCTIONS),EPOCH_BITS=32-LOCAL_BITS;
 logic[EPOCH_BITS-1:0]epoch[CONTEXTS];
 int response_owner,response_cursor;
 typedef enum logic[1:0]{IDLE,RUN,DRAIN,RESPONSE}state_t;state_t state[CONTEXTS];
 int read_live_perwarp[TOTAL_WARPS];
 int warp_service_live[TOTAL_WARPS];logic service_pending[TOTAL_WARPS][INSTRUCTIONS];
 int pc[TOTAL_WARPS],round_robin,selected,read_live_count;int read_locations[32];
 logic[31:0]saved_id[CONTEXTS];logic[15:0]memory[CONTEXTS][HALFWORDS];logic initialized[CONTEXTS][HALFWORDS];
 logic[31:0]a_words[TOTAL_WARPS][2][32][4],b_raw[TOTAL_WARPS][2][32][4],b_moved[TOTAL_WARPS][2][32][4],accumulator[TOTAL_WARPS][32][8];
 logic a_ready[TOTAL_WARPS][2][4],b_ready[TOTAL_WARPS][2][4],mov_ready[TOTAL_WARPS][2][4],c_ready[TOTAL_WARPS][2];
 descriptor_t desc[TOTAL_WARPS],chosen_desc,completion_desc;
 native_control_decode::control_t control[TOTAL_WARPS],completion_control;
 logic dependencies_ready[TOTAL_WARPS],gate_valid[TOTAL_WARPS],gate_ready[TOTAL_WARPS],dispatch_valid[TOTAL_WARPS],dispatch_ready[TOTAL_WARPS],issued[TOTAL_WARPS],gate_error[TOTAL_WARPS];
 logic[5:0]busy_write[TOTAL_WARPS],busy_read[TOTAL_WARPS];logic[3:0]cooldown[TOTAL_WARPS];
 logic read_req_valid,read_req_ready,read_rsp_valid,read_rsp_ready;
 logic[31:0]read_req_id,read_rsp_id,read_addresses[32],read_inputs[32],read_outputs[32];int read_outstanding;
 logic mov_req_valid,mov_req_ready,mov_rsp_valid,mov_rsp_ready;
 logic[31:0]mov_req_id,mov_rsp_id,mov_inputs[32],mov_outputs[32];int mov_outstanding;
 logic h_req_valid,h_req_ready,h_rsp_valid,h_rsp_ready;
 logic[31:0]h_req_id,h_rsp_id,h_a[32][4],h_b[32][2],h_c[32][4],h_results[32][4];int h_outstanding;
 logic completion_valid,write_legal,warp_write_legal,selected_issued;
 logic[31:0]completion_id;int completion_warp,completion_pc,completion_context;
 logic[EPOCH_BITS-1:0]completion_epoch;
 logic all_issued[CONTEXTS],all_drained[CONTEXTS];
 function automatic int address(input bit operand_b,input int kk,word_index,lane,tile);
  if(operand_b)return 2048+64*(16*kk+lane/4)+32*(tile%2)+4*(lane%4)+(word_index%2)*512+(word_index/2)*16;
  return 64*(16*(tile/2)+lane/4)+32*kk+4*(lane%4)+(word_index%2)*512+(word_index/2)*16;
 endfunction
 initial if(CONTEXTS<1||WARPS<1||WARPS>4||EPOCH_BITS<1)$fatal(1,"Native stage supports one through four warps");
 assign write_legal=write_context<CONTEXTS&&write_byte_address[0]==0&&write_byte_address<=4094;
 assign write_ready=!rst&&write_legal&&(write_context<CONTEXTS?state[write_context]==IDLE:0)&&!read_req_valid;
 always_comb begin
  warp_write_legal=write_context<CONTEXTS;
  if(ALLOW_WARP_WRITES)for(int lane=0;lane<32;lane++)if(write_warp_mask[lane])begin
   if(write_warp_byte_addresses[lane][0]!=0||write_warp_byte_addresses[lane]>4094)warp_write_legal=0;
   for(int other=0;other<lane;other++)if(write_warp_mask[other]&&write_warp_byte_addresses[lane]==write_warp_byte_addresses[other])warp_write_legal=0;
  end
 end
 assign write_warp_ready=ALLOW_WARP_WRITES&&!rst&&warp_write_legal&&(write_context<CONTEXTS?state[write_context]==IDLE:0)&&!write_valid&&!read_req_valid;
 assign addresses_legal=req_context<CONTEXTS;
 assign req_ready=!rst&&(addresses_legal?context_ready[req_context]:0);
 assign operands_initialized=addresses_legal?context_initialized[req_context]:0;
 assign rsp_valid=!rst&&response_owner>=0;
 assign rsp_context=response_owner>=0?32'(response_owner):0;
 assign rsp_id=response_owner>=0?saved_id[response_owner]:0;
 always_comb begin
  outstanding=0;
  for(int ctx=0;ctx<CONTEXTS;ctx++)begin
   context_initialized[ctx]=1;
   for(int warp=0;warp<WARPS;warp++)for(int kk=0;kk<2;kk++)for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)
    context_initialized[ctx]=context_initialized[ctx]&&initialized[ctx][address(0,kk,word,lane,warp)/2]&&initialized[ctx][address(0,kk,word,lane,warp)/2+1]&&initialized[ctx][address(1,kk,word,lane,warp)/2]&&initialized[ctx][address(1,kk,word,lane,warp)/2+1];
   context_ready[ctx]=!rst&&state[ctx]==IDLE&&context_initialized[ctx];
   if(state[ctx]!=IDLE)outstanding++;
  end
  for(int warp=0;warp<WARPS;warp++)for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)
   result_registers[warp][lane][word]=response_owner>=0?accumulator[response_owner*WARPS+warp][lane][word]:0;
 end
 always_comb begin
  for(int warp=0;warp<TOTAL_WARPS;warp++)begin
   desc[warp]='0;if(pc[warp]<INSTRUCTIONS)desc[warp]=descriptor(pc[warp]);
   control[warp]=native_control_decode::decode(desc[warp].raw);
   dependencies_ready[warp]=1;
   if(desc[warp].kind==2)dependencies_ready[warp]=b_ready[warp][desc[warp].kk][desc[warp].word_index];
   if(desc[warp].kind==3)begin
    dependencies_ready[warp]=c_ready[warp][desc[warp].upper_half];
    for(int word=0;word<4;word++)dependencies_ready[warp]=dependencies_ready[warp]&&a_ready[warp][desc[warp].kk][word];
    for(int word=0;word<2;word++)dependencies_ready[warp]=dependencies_ready[warp]&&mov_ready[warp][desc[warp].kk][2*int'(desc[warp].upper_half)+word];
   end
   gate_valid[warp]=!rst&&state[warp/WARPS]==RUN&&pc[warp]<INSTRUCTIONS&&dependencies_ready[warp];
  end
 end
 always_comb begin
  for(int ctx=0;ctx<CONTEXTS;ctx++)begin
   all_issued[ctx]=1;all_drained[ctx]=1;
   for(int localwarp=0;localwarp<WARPS;localwarp++)begin
    int warp;warp=ctx*WARPS+localwarp;
    if(pc[warp]!=INSTRUCTIONS)all_issued[ctx]=0;
    if(pc[warp]!=INSTRUCTIONS||busy_write[warp]!=0||busy_read[warp]!=0||cooldown[warp]!=0||!c_ready[warp][0]||!c_ready[warp][1]||warp_service_live[warp]!=0)all_drained[ctx]=0;
   end
  end
 end
 always_comb begin
  selected=-1;
  for(int offset=0;offset<TOTAL_WARPS;offset++)begin
   int candidate;candidate=(round_robin+offset)%TOTAL_WARPS;
   if(selected<0&&dispatch_valid[candidate])begin
    case(desc[candidate].kind)
     // All precomputed load addresses are aligned; capacity is readiness here.
     1:if(read_live_count<READ_SLOTS)selected=candidate;
     2:if(mov_req_ready)selected=candidate;
     3:if(h_req_ready)selected=candidate;
     default:selected=candidate;
    endcase
   end
  end
  chosen_desc='0;if(selected>=0)chosen_desc=desc[selected];
 end
 always_comb begin
  for(int warp=0;warp<TOTAL_WARPS;warp++)begin
   dispatch_ready[warp]=0;
   if(selected==warp)begin
    case(desc[warp].kind)
     1:dispatch_ready[warp]=read_req_ready;
     2:dispatch_ready[warp]=mov_req_ready;
     3:dispatch_ready[warp]=h_req_ready;
     default:dispatch_ready[warp]=1;
    endcase
   end
  end
 end
 always_comb begin
  selected_issued=0;
  for(int warp=0;warp<TOTAL_WARPS;warp++)if(issued[warp])selected_issued=1;
 end
 always_comb begin
  read_req_valid=0;mov_req_valid=0;h_req_valid=0;
  read_req_id=0;mov_req_id=0;h_req_id=0;
  native_issue_valid=selected_issued;native_issue_context=0;native_issue_warp=0;native_issue_pc=0;
  if(selected>=0)begin
   native_issue_context=32'(selected/WARPS);native_issue_warp=32'(selected%WARPS);native_issue_pc=32'h1350+32'(16*pc[selected]);
   read_req_id=(32'(epoch[selected/WARPS])<<LOCAL_BITS)|32'(selected*INSTRUCTIONS+pc[selected]);mov_req_id=read_req_id;h_req_id=read_req_id;
   read_req_valid=issued[selected]&&chosen_desc.kind==1;
   mov_req_valid=issued[selected]&&chosen_desc.kind==2;
   h_req_valid=issued[selected]&&chosen_desc.kind==3;
  end
 end
 always_comb begin
  for(int lane=0;lane<32;lane++)begin
   read_locations[lane]=0;
   read_addresses[lane]=0;read_inputs[lane]=0;mov_inputs[lane]=0;
   for(int word=0;word<4;word++)begin h_a[lane][word]=0;h_c[lane][word]=0;end
   for(int word=0;word<2;word++)h_b[lane][word]=0;
   if(selected>=0)begin
    read_locations[lane]=address(chosen_desc.operand_b,int'(chosen_desc.kk),int'(chosen_desc.word_index),lane,selected%WARPS);
    read_addresses[lane]=32'(read_locations[lane]);read_inputs[lane]={memory[selected/WARPS][read_locations[lane]/2+1],memory[selected/WARPS][read_locations[lane]/2]};
    mov_inputs[lane]=b_raw[selected][chosen_desc.kk][lane][chosen_desc.word_index];
    for(int word=0;word<4;word++)begin h_a[lane][word]=a_words[selected][chosen_desc.kk][lane][word];h_c[lane][word]=accumulator[selected][lane][4*int'(chosen_desc.upper_half)+word];end
    for(int word=0;word<2;word++)h_b[lane][word]=b_moved[selected][chosen_desc.kk][lane][2*int'(chosen_desc.upper_half)+word];
   end
  end
 end
 always_comb begin
  read_rsp_ready=!rst;
  mov_rsp_ready=read_rsp_ready&&!read_rsp_valid;
  h_rsp_ready=mov_rsp_ready&&!mov_rsp_valid;
  completion_valid=(read_rsp_valid&&read_rsp_ready)||(mov_rsp_valid&&mov_rsp_ready)||(h_rsp_valid&&h_rsp_ready);
  completion_id=read_rsp_valid?read_rsp_id:(mov_rsp_valid?mov_rsp_id:h_rsp_id);
  completion_warp=int'(completion_id & ((32'b1<<LOCAL_BITS)-1))/INSTRUCTIONS;completion_pc=int'(completion_id & ((32'b1<<LOCAL_BITS)-1))%INSTRUCTIONS;
  completion_context=completion_warp/WARPS;completion_epoch=EPOCH_BITS'(completion_id>>LOCAL_BITS);
  completion_desc='0;if(completion_valid&&completion_warp<TOTAL_WARPS)completion_desc=descriptor(completion_pc);
  completion_control=native_control_decode::decode(completion_desc.raw);
 end
 always_ff @(posedge clk)begin
  if(rst)begin
   response_owner<=-1;response_cursor<=0;round_robin<=0;read_live_count<=0;
   for(int ctx=0;ctx<CONTEXTS;ctx++)begin state[ctx]<=IDLE;saved_id[ctx]<=0;epoch[ctx]<=0;warp_drained[ctx]<='0;warp_memory_safe[ctx]<='0;for(int i=0;i<HALFWORDS;i++)initialized[ctx][i]<=0;end
   for(int warp=0;warp<TOTAL_WARPS;warp++)begin
    read_live_perwarp[warp]<=0;warp_service_live[warp]<=0;for(int op=0;op<INSTRUCTIONS;op++)service_pending[warp][op]<=0;
    pc[warp]<=0;for(int kk=0;kk<2;kk++)for(int word=0;word<4;word++)begin a_ready[warp][kk][word]<=0;b_ready[warp][kk][word]<=0;mov_ready[warp][kk][word]<=0;end
    for(int half=0;half<2;half++)c_ready[warp][half]<=0;
    for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)accumulator[warp][lane][word]<=0;
   end
  end else begin
   // Memory reuse safety is separate from register-only service drain.
   // This bounded-window signal does not replay the following native BAR PCs.
   begin
    integer total_reads;total_reads=0;
    for(int warp=0;warp<TOTAL_WARPS;warp++)begin
     bit accepted_read,retired_read;integer delta;
     accepted_read=read_req_valid&&read_req_ready&&int'(read_req_id & ((32'b1<<LOCAL_BITS)-1))/INSTRUCTIONS==warp;
     retired_read=read_rsp_valid&&read_rsp_ready&&int'(read_rsp_id & ((32'b1<<LOCAL_BITS)-1))/INSTRUCTIONS==warp;
     delta=int'(accepted_read)-int'(retired_read);
     total_reads+=read_live_perwarp[warp];
     if(read_live_perwarp[warp]<0||read_live_perwarp[warp]>READ_SLOTS)$fatal(1,"Per-warp shared-read liveness out of bounds");
     if(retired_read&&read_live_perwarp[warp]==0)$fatal(1,"Shared-read completion lacks warp credit");
     read_live_perwarp[warp]<=read_live_perwarp[warp]+delta;
     if((state[warp/WARPS]==RUN||state[warp/WARPS]==DRAIN)&&pc[warp]==INSTRUCTIONS&&cooldown[warp]==0&&read_live_perwarp[warp]==0)
      warp_memory_safe[warp/WARPS][warp%WARPS]<=1;
     if(warp_memory_safe[warp/WARPS][warp%WARPS]&&(state[warp/WARPS]==RUN||state[warp/WARPS]==DRAIN||state[warp/WARPS]==RESPONSE)&&read_live_perwarp[warp]!=0)$fatal(1,"Memory-safe warp retains pending shared read");
    end
    if(total_reads!=read_outstanding)$fatal(1,"Per-warp shared-read conservation failed");
   end
   // Per-warp liveness follows accepted service operations and actual retired
   // responses. Decoded barrier bits alone do not cover every pending operation.
   begin
    integer total_live;total_live=0;
    for(int warp=0;warp<TOTAL_WARPS;warp++)begin
     integer delta;bit accepted,retired;delta=0;
     accepted=(read_req_valid&&read_req_ready&&int'(read_req_id & ((32'b1<<LOCAL_BITS)-1))/INSTRUCTIONS==warp)||
              (mov_req_valid&&mov_req_ready&&int'(mov_req_id & ((32'b1<<LOCAL_BITS)-1))/INSTRUCTIONS==warp)||
              (h_req_valid&&h_req_ready&&int'(h_req_id & ((32'b1<<LOCAL_BITS)-1))/INSTRUCTIONS==warp);
     retired=completion_valid&&completion_warp==warp;
     total_live+=warp_service_live[warp];
     if(warp_service_live[warp]<0||warp_service_live[warp]>READ_SLOTS+MOVM_SLOTS+HMMA_SLOTS)$fatal(1,"Warp service liveness out of bounds");
     if(accepted)begin
      if(pc[warp]>=INSTRUCTIONS||service_pending[warp][pc[warp]])$fatal(1,"Duplicate/out-of-range warp service acceptance");
      service_pending[warp][pc[warp]]<=1;delta++;
     end
     if(retired)begin
      if(!service_pending[warp][completion_pc]||warp_service_live[warp]==0)$fatal(1,"Warp completion without accepted operation");
      service_pending[warp][completion_pc]<=0;delta--;
     end
     warp_service_live[warp]<=warp_service_live[warp]+delta;
     if((state[warp/WARPS]==RUN||state[warp/WARPS]==DRAIN)&&pc[warp]==INSTRUCTIONS&&busy_read[warp]==0&&busy_write[warp]==0&&cooldown[warp]==0&&c_ready[warp][0]&&c_ready[warp][1]&&warp_service_live[warp]==0)
      warp_drained[warp/WARPS][warp%WARPS]<=1;
     if(warp_drained[warp/WARPS][warp%WARPS]&&(state[warp/WARPS]==RUN||state[warp/WARPS]==DRAIN||state[warp/WARPS]==RESPONSE)&&warp_service_live[warp]!=0)$fatal(1,"Drained warp retains pending service");
     if(state[warp/WARPS]==RESPONSE&&warp_service_live[warp]!=0)$fatal(1,"Batch response retains warp service");
    end
    if(total_live!=read_outstanding+mov_outstanding+h_outstanding)$fatal(1,"Per-warp/global service conservation failed");
   end
   // Local admission credits are exact transfer counts, not capacity estimates.
   if(read_live_count!=read_outstanding)$fatal(1,"Shared read credit conservation failed");
   if(read_req_valid&&!read_req_ready)$fatal(1,"Granted read lacks actual service readiness");
   case({read_req_valid&&read_req_ready,read_rsp_valid&&read_rsp_ready})
    2'b10:read_live_count<=read_live_count+1;
    2'b01:read_live_count<=read_live_count-1;
    default:read_live_count<=read_live_count;
   endcase
   if(write_valid&&!write_legal)$fatal(1,"Invalid multiwarp shared write");
   if(ALLOW_WARP_WRITES&&write_warp_valid&&!warp_write_legal)$fatal(1,"Invalid multiwarp vector write");
   for(int warp=0;warp<TOTAL_WARPS;warp++)if(gate_error[warp])$fatal(1,"Multiwarp barrier error");
   if(write_valid&&write_ready)begin memory[write_context][write_byte_address/2]<=write_data;initialized[write_context][write_byte_address/2]<=1;end
   if(ALLOW_WARP_WRITES&&write_warp_valid&&write_warp_ready)for(int lane=0;lane<32;lane++)if(write_warp_mask[lane])begin memory[write_context][write_warp_byte_addresses[lane]/2]<=write_warp_halfwords[lane];initialized[write_context][write_warp_byte_addresses[lane]/2]<=1;end
   if(completion_valid)begin
    if(completion_warp>=TOTAL_WARPS)$fatal(1,"Unknown resident completion ID");
    else if(completion_epoch!=epoch[completion_context]||state[completion_context]==IDLE||state[completion_context]==RESPONSE)$fatal(1,"Stale resident completion epoch");
   end
   if(read_rsp_valid&&read_rsp_ready)begin
    if(completion_desc.kind!=1)$fatal(1,"Wrong multiwarp read completion class");
    for(int lane=0;lane<32;lane++)begin
     if(completion_desc.operand_b)b_raw[completion_warp][completion_desc.kk][lane][completion_desc.word_index]<=read_outputs[lane];
     else a_words[completion_warp][completion_desc.kk][lane][completion_desc.word_index]<=read_outputs[lane];
    end
    if(completion_desc.operand_b)b_ready[completion_warp][completion_desc.kk][completion_desc.word_index]<=1;
    else a_ready[completion_warp][completion_desc.kk][completion_desc.word_index]<=1;
   end
   if(mov_rsp_valid&&mov_rsp_ready)begin
    if(completion_desc.kind!=2)$fatal(1,"Wrong multiwarp MOVM completion class");
    for(int lane=0;lane<32;lane++)b_moved[completion_warp][completion_desc.kk][lane][completion_desc.word_index]<=mov_outputs[lane];
    mov_ready[completion_warp][completion_desc.kk][completion_desc.word_index]<=1;
   end
   if(h_rsp_valid&&h_rsp_ready)begin
    if(completion_desc.kind!=3)$fatal(1,"Wrong multiwarp HMMA completion class");
    for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)accumulator[completion_warp][lane][4*int'(completion_desc.upper_half)+word]<=h_results[lane][word];
    c_ready[completion_warp][completion_desc.upper_half]<=1;
   end
   if(req_valid&&!addresses_legal)$fatal(1,"Invalid request context");
   for(int warp=0;warp<TOTAL_WARPS;warp++)if(issued[warp])begin
    pc[warp]<=pc[warp]+1;if(desc[warp].kind==3)c_ready[warp][desc[warp].upper_half]<=0;
    round_robin<=(warp+1)%TOTAL_WARPS;
   end
   for(int ctx=0;ctx<CONTEXTS;ctx++)begin
    case(state[ctx])
     IDLE:if(req_valid&&req_ready&&req_context==ctx)begin
      if(&epoch[ctx])$fatal(1,"Resident epoch exhausted; reset required");
      epoch[ctx]<=epoch[ctx]+1;state[ctx]<=RUN;saved_id[ctx]<=req_id;
      warp_drained[ctx]<='0;warp_memory_safe[ctx]<='0;
      for(int localwarp=0;localwarp<WARPS;localwarp++)begin
       int warp;warp=ctx*WARPS+localwarp;
       read_live_perwarp[warp]<=0;warp_service_live[warp]<=0;
       for(int op=0;op<INSTRUCTIONS;op++)service_pending[warp][op]<=0;
       pc[warp]<=0;
       for(int kk=0;kk<2;kk++)for(int word=0;word<4;word++)begin a_ready[warp][kk][word]<=0;b_ready[warp][kk][word]<=0;mov_ready[warp][kk][word]<=0;end
       for(int half=0;half<2;half++)c_ready[warp][half]<=1;
       for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)accumulator[warp][lane][word]<=c_registers[localwarp][lane][word];
      end
     end
     RUN:if(all_issued[ctx])state[ctx]<=DRAIN;
     DRAIN:if(all_drained[ctx])state[ctx]<=RESPONSE;
     RESPONSE:if(rsp_valid&&rsp_ready&&response_owner==ctx)state[ctx]<=IDLE;
     default:$fatal(1,"Invalid resident context state");
    endcase
   end
   if(response_owner<0)begin
    int choice;choice=-1;
    for(int offset=0;offset<CONTEXTS;offset++)begin
     int candidate;candidate=(response_cursor+offset)%CONTEXTS;
     if(choice<0&&state[candidate]==RESPONSE)choice=candidate;
    end
    if(choice>=0)response_owner<=choice;
   end else if(rsp_valid&&rsp_ready)begin response_cursor<=(response_owner+1)%CONTEXTS;response_owner<=-1;end

  end
 end
 for(genvar warp=0;warp<TOTAL_WARPS;warp++)begin:warps
  decoded_native_issue_gate #(.MAX_OPS(64),.TAG_W(7),.COUNT_W(7)) gate(
   .clk,.reset(rst||state[warp/WARPS]==IDLE),.instr_valid(gate_valid[warp]),.instr_ready(gate_ready[warp]),
   .operation_id(7'(pc[warp])),.control(control[warp]),.dispatch_valid(dispatch_valid[warp]),.dispatch_ready(dispatch_ready[warp]),.issued(issued[warp]),
   .write_complete_valid(completion_valid&&completion_warp==warp&&completion_control.write_barrier!=7),.write_complete_tag(7'(completion_pc)),
   .read_complete_valid(1'b0),.read_complete_tag(7'd0),.busy_write_mask(busy_write[warp]),.busy_read_mask(busy_read[warp]),.cooldown(cooldown[warp]),.error_sticky(gate_error[warp])
  );
 end
 warp_shared_read_service #(.SLOTS(READ_SLOTS),.SERVICE_INTERVAL(SERVICE_INTERVAL),.RETURN_DELAY(RETURN_DELAY)) reads(
  .clk,.rst,.req_valid(read_req_valid),.req_ready(read_req_ready),.req_id(read_req_id),.byte_addresses(read_addresses),.input_words(read_inputs),
  .rsp_valid(read_rsp_valid),.rsp_ready(read_rsp_ready),.rsp_id(read_rsp_id),.output_words(read_outputs),.outstanding(read_outstanding),.request_packages()
 );
 native_movm_word_pipeline #(.SLOTS(MOVM_SLOTS),.LATENCY(MOVM_LATENCY),.INTERVAL(MOVM_INTERVAL)) moves(
  .clk,.rst,.req_valid(mov_req_valid),.req_ready(mov_req_ready),.req_id(mov_req_id),.input_words(mov_inputs),
  .rsp_valid(mov_rsp_valid),.rsp_ready(mov_rsp_ready),.rsp_id(mov_rsp_id),.output_words(mov_outputs),.outstanding(mov_outstanding)
 );
 native_hmma16816_adapter #(.SLOTS(HMMA_SLOTS),.LATENCY(HMMA_LATENCY),.INTERVAL(HMMA_INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) tensor(
  .clk,.rst,.req_valid(h_req_valid),.req_ready(h_req_ready),.req_id(h_req_id),.a_registers(h_a),.b_registers(h_b),.c_registers(h_c),
  .rsp_valid(h_rsp_valid),.rsp_ready(h_rsp_ready),.rsp_id(h_rsp_id),.result_registers(h_results),.outstanding(h_outstanding)
 );
 // Shared values sampled on accepted LD.E issue. No full native register file,
 // address-ALU scoreboard, original missing scratch/barrier protocol or full SM.
endmodule
