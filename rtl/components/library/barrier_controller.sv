// Extracted executable baseline; physical GPU parameters remain provisional.
module barrier_controller #(parameter int WARPS=4,RELEASE_DELAY=1)(
 input logic clk,rst,input logic [WARPS-1:0] arrivals,
 input logic protected_operations_complete,output logic release_warps);
 logic [WARPS-1:0] arrived;logic releasing;int remaining;
 always_ff @(posedge clk) begin
  if(rst) begin arrived<=0;releasing<=0;remaining<=0;release_warps<=0;end
  else begin
   release_warps<=0;
   if(!releasing) begin
    arrived<=arrived|arrivals;
    if(&(arrived|arrivals)&&protected_operations_complete) begin
     if(RELEASE_DELAY<1) $fatal(1,"Invalid barrier delay");
     releasing<=1;remaining<=RELEASE_DELAY-1;
    end
   end else if(remaining>0) remaining<=remaining-1;
   else begin release_warps<=1;arrived<=0;releasing<=0;end
  end
 end
endmodule
