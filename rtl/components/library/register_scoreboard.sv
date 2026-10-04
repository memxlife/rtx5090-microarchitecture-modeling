// Extracted executable baseline; physical GPU parameters remain provisional.
module register_scoreboard #(parameter int REGS=64)(
 input logic clk,rst,input int source_a,source_b,destination,
 input logic use_a,use_b,write_destination,
 output logic operands_ready,destination_free,
 input logic issue_fire,input int result_delay);
 int cycle,available_at[REGS]; logic defined[REGS];
 always_comb begin
  operands_ready=(!use_a||(defined[source_a]&&cycle>=available_at[source_a]))&&
                 (!use_b||(defined[source_b]&&cycle>=available_at[source_b]));
  destination_free=!write_destination||!defined[destination]||cycle>=available_at[destination];
 end
 always_ff @(posedge clk) begin
  if(rst) begin
   cycle<=0;
   for(int r=0;r<REGS;r++) begin defined[r]<=(r==0);available_at[r]<=0;end
  end else begin
   cycle<=cycle+1;
   if(issue_fire) begin
    if(!operands_ready||!destination_free||result_delay<1) $fatal(1,"Illegal register issue");
    if(write_destination) begin defined[destination]<=1;available_at[destination]<=cycle+result_delay;end
   end
  end
 end
endmodule
