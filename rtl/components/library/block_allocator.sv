// Extracted executable baseline; physical GPU parameters remain provisional.
module block_allocator #(
 parameter int SLOTS=4, REG_WORDS=65536, SHARED_BYTES=102400
)(input logic clk,rst, input logic admit_valid,output logic admit_ready,
 input int registers_needed,shared_needed, output int admitted_slot,
 input logic retire_valid,input int retire_slot,output int resident_blocks);
 logic busy[SLOTS]; int reg_alloc[SLOTS],sh_alloc[SLOTS]; int free_regs,free_shared,slot;
 always_comb begin
  free_regs=REG_WORDS;free_shared=SHARED_BYTES;resident_blocks=0;slot=-1;
  for(int i=0;i<SLOTS;i++) begin
   if(busy[i]) begin free_regs-=reg_alloc[i];free_shared-=sh_alloc[i];resident_blocks++;end
   else if(slot<0) slot=i;
  end
  admitted_slot=slot;
  admit_ready=slot>=0&&registers_needed>=0&&shared_needed>=0&&registers_needed<=free_regs&&shared_needed<=free_shared;
 end
 always_ff @(posedge clk) begin
  if(rst) for(int i=0;i<SLOTS;i++) begin busy[i]<=0;reg_alloc[i]<=0;sh_alloc[i]<=0;end
  else begin
   if(retire_valid) begin
    if(retire_slot<0||retire_slot>=SLOTS) $fatal(1,"Invalid retire slot");
    else if(!busy[retire_slot]) $fatal(1,"Retiring unallocated block");
    else busy[retire_slot]<=0;
   end
   if(admit_valid&&admit_ready) begin busy[slot]<=1;reg_alloc[slot]<=registers_needed;sh_alloc[slot]<=shared_needed;end
  end
 end
endmodule
