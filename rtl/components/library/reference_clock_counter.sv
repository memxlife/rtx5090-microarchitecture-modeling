// Extracted executable baseline; physical GPU parameters remain provisional.
module reference_clock_counter(input logic clk,rst,output logic [63:0] cycles);
 always_ff @(posedge clk) begin if(rst) cycles<=0;else cycles<=cycles+1;end
endmodule
