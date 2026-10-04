// Extracted executable baseline; physical GPU parameters remain provisional.
module completion_tracker #(parameter int WARPS=4)(
 input logic clk,rst,input logic [WARPS-1:0] ended,
 input logic all_output_stores_complete,output logic block_complete);
 always_ff @(posedge clk) begin
  if(rst) block_complete<=0;
  else if((&ended)&&all_output_stores_complete) block_complete<=1;
 end
endmodule
