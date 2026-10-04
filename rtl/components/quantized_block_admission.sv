// Connected aggregate resource model; private partition placement and dispatch timing unknown.
module quantized_block_admission #(
 parameter int BLOCK_SLOTS=24,REG_WORDS=65536,SHARED_BYTES=102400,
 parameter int MAX_WARPS=48,MAX_SHARED_PER_BLOCK=101376
)(
 input logic clk,rst,admit_valid,
 input int block_threads,registers_per_thread,user_shared_bytes,reserved_shared_bytes,
 output logic admit_ready,
 output int admitted_slot,resident_blocks,resident_warps,
 output int allocated_register_words,allocated_shared_bytes,
 input logic retire_valid,input int retire_slot
);
 logic demands_valid,base_ready,pass_budget;
 int launch_register_words,requested_warps,slot_warps[BLOCK_SLOTS];
 allocation_demands demands(
  .block_threads,.registers_per_thread,.user_shared_bytes,.reserved_shared_bytes,
  .valid(demands_valid),.allocated_register_words,
  .launch_check_register_words(launch_register_words),.allocated_shared_bytes
 );
 always_comb begin
  resident_warps=0;
  for(int i=0;i<BLOCK_SLOTS;i++)resident_warps+=slot_warps[i];
  requested_warps=demands_valid?(block_threads+31)/32:0;
  pass_budget=demands_valid && user_shared_bytes<=MAX_SHARED_PER_BLOCK &&
              launch_register_words<=REG_WORDS && resident_warps+requested_warps<=MAX_WARPS;
  admit_ready=base_ready && pass_budget;
 end
 block_allocator #(.SLOTS(BLOCK_SLOTS),.REG_WORDS(REG_WORDS),.SHARED_BYTES(SHARED_BYTES)) allocator(
  .clk,.rst,.admit_valid(admit_valid && pass_budget),.admit_ready(base_ready),
  .registers_needed(allocated_register_words),.shared_needed(allocated_shared_bytes),
  .admitted_slot,.retire_valid,.retire_slot,.resident_blocks
 );
 always_ff @(posedge clk) begin
  if(rst) begin
   for(int i=0;i<BLOCK_SLOTS;i++)slot_warps[i]<=0;
  end else begin
   if(retire_valid && retire_slot>=0 && retire_slot<BLOCK_SLOTS)slot_warps[retire_slot]<=0;
   if(admit_valid && admit_ready)slot_warps[admitted_slot]<=requested_warps;
  end
 end
endmodule
