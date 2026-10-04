// Resource reservation for a preloaded resident native stage.
// One stage represents a bounded compute window, not an entire CTA lifetime.
// Do not use stage response retirement as full-GEMM block retirement.
module resident_stage_admission #(
 parameter int CONTEXTS=2,REG_WORDS=65536,SHARED_BYTES=102400,MAX_WARPS=48,
 parameter int THREADS=128,REGS_PER_THREAD=40,USER_SHARED_BYTES=8192,RESERVED_SHARED_BYTES=1024
)(
 input logic clk,rst,
 input logic launch_valid,output logic launch_ready,input logic[31:0]launch_id,
 output logic stage_req_valid,input logic stage_req_ready,
 output int stage_req_context,output logic[31:0]stage_req_id,
 input logic stage_rsp_valid,output logic stage_rsp_ready,
 input int stage_rsp_context,input logic[31:0]stage_rsp_id,
 output logic done_valid,input logic done_ready,
 output int done_context,output logic[31:0]done_id,
 output int resident_blocks,resident_warps,allocated_register_words,allocated_shared_bytes
);
 logic allocator_ready,admit_fire,retire_fire;
 int admitted_slot;
 logic live[CONTEXTS];logic[31:0]ids[CONTEXTS];
 initial if(CONTEXTS<1)$fatal(1,"Invalid resident context capacity");
 assign stage_req_context=admitted_slot;
 assign stage_req_id=launch_id;
 // The engine must evaluate readiness independently of stage_req_valid for
 // the selected context. This ready-qualified transfer strobe avoids offering
 // a stalled request whose lowest-free context could change on retirement.
 // Reservation and stage acceptance happen at the same edge, or neither does.
 assign stage_req_valid=!rst&&launch_valid&&allocator_ready&&stage_req_ready;
 assign launch_ready=!rst&&allocator_ready&&stage_req_ready;
 assign admit_fire=launch_valid&&launch_ready;
 assign done_valid=!rst&&stage_rsp_valid;
 assign done_context=stage_rsp_context;assign done_id=stage_rsp_id;
 assign stage_rsp_ready=!rst&&done_ready;
 assign retire_fire=stage_rsp_valid&&stage_rsp_ready;
 quantized_block_admission #(.BLOCK_SLOTS(CONTEXTS),.REG_WORDS(REG_WORDS),
  .SHARED_BYTES(SHARED_BYTES),.MAX_WARPS(MAX_WARPS)) admission(
  .clk,.rst,.admit_valid(admit_fire),.block_threads(THREADS),
  .registers_per_thread(REGS_PER_THREAD),.user_shared_bytes(USER_SHARED_BYTES),
  .reserved_shared_bytes(RESERVED_SHARED_BYTES),.admit_ready(allocator_ready),
  .admitted_slot,.resident_blocks,.resident_warps,.allocated_register_words,.allocated_shared_bytes,
  .retire_valid(retire_fire),.retire_slot(stage_rsp_context)
 );
 always_ff @(posedge clk)begin
  if(rst)for(int c=0;c<CONTEXTS;c++)begin live[c]<=0;ids[c]<=0;end
  else begin
   // Check even a held response: malformed completion must never escape.
   if(stage_rsp_valid)begin
    if(stage_rsp_context<0||stage_rsp_context>=CONTEXTS)$fatal(1,"Resident response context outside capacity");
    else if(!live[stage_rsp_context]||ids[stage_rsp_context]!=stage_rsp_id)$fatal(1,"Resident response has no matching admitted operation");
   end
   if(retire_fire)live[stage_rsp_context]<=0;
   if(admit_fire)begin
    if(admitted_slot<0||admitted_slot>=CONTEXTS)$fatal(1,"Resident admission context outside capacity");
    else if(live[admitted_slot])$fatal(1,"Resident admission overwrote a live context");
    else begin live[admitted_slot]<=1;ids[admitted_slot]<=launch_id;end
   end
  end
 end
endmodule
