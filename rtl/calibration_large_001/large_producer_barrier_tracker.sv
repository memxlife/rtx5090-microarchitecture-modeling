// Semantic hypothesis: each producer contributes to its barrier until that op completes.
// Six observed compiler IDs are modeled; MAX_OPS is a configurable simulation bound.
module large_producer_barrier_tracker #(
 parameter int MAX_OPS=8,parameter int TAG_W=$clog2(MAX_OPS+1),parameter int COUNT_W=$clog2(MAX_OPS+1)
)(input logic clk,input logic reset,
 input logic issue_valid,output logic issue_ready,input logic[TAG_W-1:0] issue_tag,input logic[2:0] issue_barrier,
 input logic complete_valid,input logic[TAG_W-1:0] complete_tag,
 input logic[5:0] wait_mask,output logic wait_ready,output logic[5:0] busy_mask,
 output logic[5:0][COUNT_W-1:0] pending_count,output logic error_sticky);
 logic[MAX_OPS-1:0] active;
 logic[MAX_OPS-1:0][2:0] barrier;
 always_comb begin
  issue_ready=0;
  if(int'(issue_tag)<MAX_OPS && issue_barrier<6)issue_ready=!active[issue_tag];
  busy_mask='0;pending_count='0;
  begin
   logic[MAX_OPS-1:0] remaining;remaining=active;
   while(remaining!=0)begin
    int i;i=$clog2(remaining&(~remaining+1'b1));remaining=remaining&(remaining-1'b1);
   busy_mask[barrier[i]]=1;
   pending_count[barrier[i]]=pending_count[barrier[i]]+1'b1;
  end
  end
  wait_ready=((wait_mask & busy_mask)==0);
 end
 always_ff @(posedge clk)begin
  if(reset)begin active<='0;error_sticky<=0; // Inactive barrier labels are not observable; issue overwrites them.
  end
  else begin
   if(issue_valid && (int'(issue_tag)>=MAX_OPS || issue_barrier>=6))error_sticky<=1;
   if(complete_valid)begin
    if(int'(complete_tag)>=MAX_OPS)error_sticky<=1;
    else if(!active[complete_tag])error_sticky<=1;
    else active[complete_tag]<=0;
   end
   if(issue_valid && issue_ready)begin active[issue_tag]<=1;barrier[issue_tag]<=issue_barrier;end
  end
 end
endmodule
