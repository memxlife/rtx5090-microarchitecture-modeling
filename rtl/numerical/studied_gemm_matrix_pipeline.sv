// Unpadded shared operand layout of diagnostic_050/gemm_checked.cu.
// Generic shared-word reads + measured MOVM; no LDSM or native service timing.
module studied_gemm_matrix_pipeline #(
 parameter int BM=32,BN=32,BK=32,SHARED_BYTES=2*BK*(BM+BN),
 parameter int SLOTS=2,LATENCY=16,INTERVAL=4,ARITHMETIC_MODE=1,
 parameter bit TIMED_READS=0,parameter int READ_SLOTS=4,SERVICE_INTERVAL=1,RETURN_DELAY=1
)(
 input logic clk,rst,
 input logic write_valid,output logic write_ready,
 input logic [31:0] write_byte_address,input logic [15:0] write_data,
 input logic req_valid,output logic req_ready,input logic [31:0] req_id,
 input logic [31:0] tile_index,k_step,
 input logic [31:0] c_registers[32][8],
 output logic operands_initialized,addresses_legal,
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,result_registers[32][8],output int outstanding
);
 localparam int TN=BN/16,TILES=(BM/16)*TN;
 logic [31:0] a_word_addresses[32][4],b_word_addresses[32][4];
 logic selection_legal,inner_ready,inner_addresses_legal,inner_initialized;
 initial if(BM<16||BN<16||BK<16||BM%16!=0||BN%16!=0||BK%16!=0||
  SHARED_BYTES<2*BK*(BM+BN))$fatal(1,"Invalid studied GEMM geometry");
 assign selection_legal=tile_index<TILES&&k_step<BK/16;
 assign req_ready=!rst&&selection_legal&&inner_ready;
 assign addresses_legal=selection_legal&&inner_addresses_legal;
 assign operands_initialized=selection_legal&&inner_initialized;
 always_comb begin
  for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)begin
   a_word_addresses[lane][word]=0;b_word_addresses[lane][word]=0;
   if(selection_legal)begin
    a_word_addresses[lane][word]=32'(2*BK*(16*(tile_index/TN)+lane/4)+
     32*k_step+4*(lane%4)+(word%2)*16*BK+(word/2)*16);
    b_word_addresses[lane][word]=32'(2*BM*BK+2*BN*(16*k_step+lane/4)+
     32*(tile_index%TN)+4*(lane%4)+(word%2)*16*BN+(word/2)*16);
   end
  end
 end
 always_ff @(posedge clk)if(!rst&&req_valid&&!selection_legal)
  $fatal(1,"Studied GEMM tile or reduction-step index out of bounds");
 generate if(TIMED_READS)begin:timed_path
 timed_generic_shared_matrix_pipeline #(.SHARED_BYTES(SHARED_BYTES),.SLOTS(SLOTS),
  .LATENCY(LATENCY),.INTERVAL(INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE),
  .READ_SLOTS(READ_SLOTS),.SERVICE_INTERVAL(SERVICE_INTERVAL),.RETURN_DELAY(RETURN_DELAY)) path(
  .clk,.rst,.write_valid,.write_ready,.write_byte_address,.write_data,
  .req_valid(req_valid&&selection_legal),.req_ready(inner_ready),.req_id,
  .a_word_addresses,.b_word_addresses,.c_registers,
  .operands_initialized(inner_initialized),.addresses_legal(inner_addresses_legal),
  .rsp_valid,.rsp_ready,.rsp_id,.result_registers,.outstanding
 );
 end else begin:ideal_path
 generic_shared_matrix_pipeline #(.SHARED_BYTES(SHARED_BYTES),.SLOTS(SLOTS),
  .LATENCY(LATENCY),.INTERVAL(INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) path(
  .clk,.rst,.write_valid,.write_ready,.write_byte_address,.write_data,
  .req_valid(req_valid&&selection_legal),.req_ready(inner_ready),.req_id,
  .a_word_addresses,.b_word_addresses,.c_registers,
  .operands_initialized(inner_initialized),.addresses_legal(inner_addresses_legal),
  .rsp_valid,.rsp_ready,.rsp_id,.result_registers,.outstanding
 );
 end endgenerate
endmodule
