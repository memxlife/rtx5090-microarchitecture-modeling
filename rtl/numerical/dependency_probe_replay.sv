// Effective issue-to-next-dependent-issue recurrences, one full dependent warp.
// MOVM28.98828125 rounded to29 integer cycles; direct conflict-free LDS32 uses28.
// MOVM source timer did NOT wait for final result;29 is a provisional rounded
// successive-admission spacing, not measured final return latency. Using return
// to enable the dependent issue is an explicit model choice. N*29 is NOT an
// experimentally validated total duration.
// These include measured issue/wakeup/compiler scheduling, not intrinsic unit
// latency. Do not add cache/issue/wakeup delays or infer independent throughput.
module dependency_probe_replay #(
 parameter int OPERATIONS=1024,TIMING_MODE=0,MOVM_RECURRENCE=29,LDS_RECURRENCE=28,
 parameter int EXTRA_ISSUE_CYCLES=0,EXTRA_WAKEUP_CYCLES=0,EXTRA_CACHE_CYCLES=0
)(
 input logic clk,rst,launch_valid,output logic launch_ready,
 input logic[31:0]launch_id,input logic[1:0]opcode,
 input logic[31:0]input_words[32],byte_addresses[32],
 input logic write_valid,output logic write_ready,input logic[31:0]write_byte_address,write_data,
 output logic done_valid,input logic done_ready,output logic[31:0]done_id,result_words[32],
 output logic issue_valid,output logic[31:0]issue_id,output logic[1:0]issue_opcode,
 output logic[63:0]elapsed_cycles
);
 typedef enum logic[1:0]{IDLE,RUN,DONE}state_t;state_t state;
 logic[31:0]memory[8192];logic initialized[8192];
 logic[31:0]saved_id,chain_words[32];logic[1:0]saved_opcode;
 int issued_count,returned_count,cycle;
 logic mov_req_valid,mov_req_ready,mov_rsp_valid,mov_rsp_ready;
 logic[31:0]mov_inputs[32],mov_outputs[32],mov_rsp_id;int mov_outstanding;
 logic lds_pending,lds_return_valid;int lds_due;logic[31:0]lds_values[32],lds_return_id;
 logic return_valid;logic[31:0]return_id,return_words[32],next_inputs[32];
 initial begin
  if(TIMING_MODE!=0||EXTRA_ISSUE_CYCLES!=0||EXTRA_WAKEUP_CYCLES!=0||EXTRA_CACHE_CYCLES!=0)$fatal(1,"Effective recurrence rejects decomposed/additional timing");
  if(OPERATIONS<1||MOVM_RECURRENCE<1||LDS_RECURRENCE<1)$fatal(1,"Invalid dependency replay length/timing");
 end
 assign launch_ready=!rst&&state==IDLE;
 assign write_ready=!rst&&state==IDLE&&write_byte_address[1:0]==0&&write_byte_address<=32764;
 assign done_valid=!rst&&state==DONE;assign done_id=saved_id;
 assign lds_return_valid=!rst&&state==RUN&&lds_pending&&cycle>=lds_due;
 assign return_valid=saved_opcode==0?mov_rsp_valid:lds_return_valid;
 assign return_id=saved_opcode==0?mov_rsp_id:lds_return_id;
 always_comb for(int lane=0;lane<32;lane++)begin
  return_words[lane]=saved_opcode==0?mov_outputs[lane]:lds_values[lane];
  next_inputs[lane]=issued_count==0?chain_words[lane]:return_words[lane];
  mov_inputs[lane]=next_inputs[lane];
 end
 // Direct forwarding allows the next issue on the exact return-acceptance edge.
 // Launch/snapshot and final held response are separately visible overhead;
 // they are never charged again to each measured recurrence.
 assign issue_valid=!rst&&state==RUN&&issued_count<OPERATIONS&&(issued_count==0||return_valid)&&(saved_opcode==1||mov_req_ready);
 assign issue_id=32'(issued_count);assign issue_opcode=saved_opcode;
 assign mov_req_valid=issue_valid&&saved_opcode==0;
 assign mov_rsp_ready=!rst&&state==RUN&&saved_opcode==0;
 native_movm_word_pipeline #(.SLOTS(2),.LATENCY(MOVM_RECURRENCE),.INTERVAL(1)) movm(
  .clk,.rst,.req_valid(mov_req_valid),.req_ready(mov_req_ready),.req_id(issue_id),.input_words(mov_inputs),
  .rsp_valid(mov_rsp_valid),.rsp_ready(mov_rsp_ready),.rsp_id(mov_rsp_id),.output_words(mov_outputs),.outstanding(mov_outstanding));
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;saved_id<=0;saved_opcode<=0;issued_count<=0;returned_count<=0;cycle<=0;elapsed_cycles<=0;lds_pending<=0;lds_due<=0;lds_return_id<=0;
   for(int word=0;word<8192;word++)initialized[word]<=0;
   for(int lane=0;lane<32;lane++)begin chain_words[lane]<=0;result_words[lane]<=0;lds_values[lane]<=0;end
  end else begin
   cycle<=cycle+1;
   if(write_valid&&(write_byte_address[1:0]!=0||write_byte_address>32764))$fatal(1,"Invalid replay shared write");
   if(write_valid&&write_ready)begin memory[write_byte_address/4]<=write_data;initialized[write_byte_address/4]<=1;end
   case(state)
    IDLE:if(launch_valid&&launch_ready)begin
     if(opcode>1)$fatal(1,"Unsupported dependency replay opcode");
     if(write_valid)$fatal(1,"Replay launch and memory write cannot share edge");
     saved_id<=launch_id;saved_opcode<=opcode;issued_count<=0;returned_count<=0;elapsed_cycles<=0;state<=RUN;
     for(int lane=0;lane<32;lane++)chain_words[lane]<=opcode==0?input_words[lane]:byte_addresses[lane];
    end
    RUN:begin
     elapsed_cycles<=elapsed_cycles+1;
     if(return_valid)begin
      if(return_id!=32'(returned_count)||returned_count>=issued_count)$fatal(1,"Dependency return identity mismatch");
      returned_count<=returned_count+1;
      for(int lane=0;lane<32;lane++)begin chain_words[lane]<=return_words[lane];result_words[lane]<=return_words[lane];end
      if(saved_opcode==1)lds_pending<=0;
      if(returned_count==OPERATIONS-1)state<=DONE;
     end
     if(issue_valid)begin
      issued_count<=issued_count+1;
      if(saved_opcode==1)begin
       for(int lane=0;lane<32;lane++)begin
        if(next_inputs[lane][1:0]!=0||next_inputs[lane]>32764)$fatal(1,"LDS pointer outside aligned shared memory");
        else if(!initialized[next_inputs[lane]/4])$fatal(1,"LDS pointer reads uninitialized shared word");
        for(int earlier=0;earlier<lane;earlier++)if((next_inputs[lane]/4)%32==(next_inputs[earlier]/4)%32)$fatal(1,"Replay LDS scope requires distinct32banks");
        lds_values[lane]<=memory[next_inputs[lane]/4];
       end
       lds_pending<=1;lds_due<=cycle+LDS_RECURRENCE;lds_return_id<=issue_id;
      end
     end
    end
    DONE:if(done_valid&&done_ready)state<=IDLE;
    default:$fatal(1,"Invalid dependency replay state");
   endcase
  end
 end
 // LDS values are memory reads and become future dependent byte addresses.
 // Native cache/global/conflicting/multiwarp paths and full GEMM are excluded.
endmodule
