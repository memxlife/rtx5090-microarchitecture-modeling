// Extracted executable baseline; physical GPU parameters remain provisional.
module warp_context #(parameter int DEPTH=256)(
 input logic clk,rst, input logic issue_fire,barrier_instruction,end_instruction,
 input logic barrier_release, output int pc,output logic waiting,ended);
 always_ff @(posedge clk) begin
  if(rst) begin pc<=0;waiting<=0;ended<=0;end
  else begin
   if(barrier_release) waiting<=0;
   if(issue_fire) begin
    if(waiting||ended||pc>=DEPTH) $fatal(1,"Illegal warp advance");
    pc<=pc+1;
    if(barrier_instruction) waiting<=1;
    if(end_instruction) ended<=1;
   end
  end
 end
endmodule
