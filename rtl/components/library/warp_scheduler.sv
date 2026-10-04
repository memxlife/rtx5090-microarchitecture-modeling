// Extracted executable baseline; physical GPU parameters remain provisional.
module warp_scheduler #(parameter int WARPS=4)(
 input logic clk,rst,input logic [WARPS-1:0] eligible,
 output logic issue_valid,input logic issue_ready,output int issue_warp);
 int cursor;
 always_comb begin
  issue_valid=0;issue_warp=0;
  for(int k=0;k<WARPS;k++) begin
   if(!issue_valid&&eligible[(cursor+k)%WARPS]) begin issue_valid=1;issue_warp=(cursor+k)%WARPS;end
  end
 end
 always_ff @(posedge clk) begin
  if(rst) cursor<=0;
  else if(issue_valid&&issue_ready) cursor<=(issue_warp+1)%WARPS;
 end
endmodule
