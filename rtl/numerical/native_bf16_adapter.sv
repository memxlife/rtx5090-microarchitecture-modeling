// Supported sm120 BF16 WMMA operand layout recovered in functional_mapping_002.
// Timing and accumulation convention are inherited from numerical_matrix_pipeline.
// This is an operation-level adapter, not a model of two physical HMMA pipelines.
module native_bf16_adapter #(
 parameter int SLOTS=2,LATENCY=17,INTERVAL=3,ARITHMETIC_MODE=0
)(
 input logic clk,rst,req_valid,output logic req_ready,
 input logic [31:0] req_id,
 input logic [31:0] a_registers[32][4],b_registers[32][4],
 input logic [31:0] c_registers[32][8],
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,result_registers[32][8],output int outstanding
);
 import native_bf16_layout::*;
 logic [15:0] a_words[256],b_words[256];
 logic [31:0] accumulator_words[256],result_words[256];
 for(genvar lane=0;lane<32;lane++) begin: lanes
  for(genvar element=0;element<8;element++) begin: elements
   assign a_words[a_element_index(lane,element)] =
     a_registers[lane][element/2][16*(element%2)+:16];
   assign b_words[b_element_index(lane,element)] =
     b_registers[lane][element/2][16*(element%2)+:16];
   assign accumulator_words[c_element_index(lane,element)] = c_registers[lane][element];
   assign result_registers[lane][element] = result_words[c_element_index(lane,element)];
  end
 end
 numerical_matrix_pipeline #(.SLOTS(SLOTS),.LATENCY(LATENCY),.INTERVAL(INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) matrix (
  .clk,.rst,.req_valid,.req_ready,.req_id,.a_words,.b_words,.accumulator_words,
  .rsp_valid,.rsp_ready,.rsp_id,.result_words,.outstanding
 );
endmodule
