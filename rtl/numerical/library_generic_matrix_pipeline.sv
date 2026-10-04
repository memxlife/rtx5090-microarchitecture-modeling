// Address wrapper for the verified cuBLASLt nn shared layout; software layout only.
module library_generic_matrix_pipeline #(
 parameter int SHARED_BYTES=37376,SLOTS=2,LATENCY=16,INTERVAL=4,ARITHMETIC_MODE=1
)(
 input logic clk,rst,
 input logic write_valid,output logic write_ready,
 input logic [31:0] write_byte_address,input logic [15:0] write_data,
 input logic req_valid,output logic req_ready,input logic [31:0] req_id,
 input logic [1:0] warp_id,input logic slot,input logic [2:0] k_step,
 input logic [31:0] c_registers[32][8],
 output logic operands_initialized,addresses_legal,
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,result_registers[32][8],output int outstanding
);
 logic [31:0] a_word_addresses[32][4],b_word_addresses[32][4];
 initial if(SHARED_BYTES<37376)$fatal(1,"Library shared storage too small");
 always_comb begin
  for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)begin
   a_word_addresses[lane][word]=32'(library_shared_layout::consumer_a(int'(warp_id),lane,int'(slot),int'(k_step),word));
   b_word_addresses[lane][word]=32'(library_shared_layout::consumer_b(int'(warp_id),lane,int'(slot),int'(k_step),word));
  end
 end
 generic_shared_matrix_pipeline #(.SHARED_BYTES(SHARED_BYTES),.SLOTS(SLOTS),
  .LATENCY(LATENCY),.INTERVAL(INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) path(
  .clk,.rst,.write_valid,.write_ready,.write_byte_address,.write_data,
  .req_valid,.req_ready,.req_id,.a_word_addresses,.b_word_addresses,.c_registers,
  .operands_initialized,.addresses_legal,.rsp_valid,.rsp_ready,.rsp_id,.result_registers,.outstanding
 );
endmodule
