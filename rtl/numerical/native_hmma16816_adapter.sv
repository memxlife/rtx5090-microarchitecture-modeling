// Numerical instruction-family adapter: one HMMA.16816.F32.BF16 half.
// Measured supported mapping: two B words and four C words per lane.
// Reusing a full matrix oracle does not model two physical pipelines.
module native_hmma16816_adapter #(
 parameter int SLOTS=2,LATENCY=16,INTERVAL=4,ARITHMETIC_MODE=1
)(
 input logic clk,rst,req_valid,output logic req_ready,
 input logic [31:0] req_id,
 input logic [31:0] a_registers[32][4],b_registers[32][2],c_registers[32][4],
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,result_registers[32][4],output int outstanding
);
 logic [31:0] full_b[32][4],full_c[32][8],full_result[32][8];
 for(genvar lane=0;lane<32;lane++)begin:lanes
  for(genvar word=0;word<4;word++)begin:words
   if(word<2)begin:used_b
    assign full_b[lane][word]=b_registers[lane][word];
   end else begin:unused_b
    assign full_b[lane][word]=32'b0;
   end
   assign full_c[lane][word]=c_registers[lane][word];
   assign full_c[lane][word+4]=32'b0;
   assign result_registers[lane][word]=full_result[lane][word];
  end
 end
 native_bf16_adapter #(.SLOTS(SLOTS),.LATENCY(LATENCY),.INTERVAL(INTERVAL),
  .ARITHMETIC_MODE(ARITHMETIC_MODE)) operation(
  .clk,.rst,.req_valid,.req_ready,.req_id,.a_registers,.b_registers(full_b),.c_registers(full_c),
  .rsp_valid,.rsp_ready,.rsp_id,.result_registers(full_result),.outstanding
 );
endmodule
