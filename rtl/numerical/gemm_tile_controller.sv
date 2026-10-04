// One 16x16 GEMM tile with K=16*STAGES and zero initial accumulator.
// Input per stage: A512B then B512B, each four row-major 8x8 tiles in
// tile order (row-half + 2*column-half), not ordinary matrix storage.
// Serialized staging/stores and latency defaults are simulation choices.
module gemm_tile_controller #(
 parameter int STAGES=2,SETS=64,WAYS=8,SHARED_BYTES=32768,SLOTS=2,
 parameter int LATENCY=16,INTERVAL=4,ARITHMETIC_MODE=1
)(
 input logic clk,rst,launch_valid,output logic launch_ready,
 input logic [31:0] launch_id,input_base,output_base,
 output logic done_valid,input logic done_ready,output logic [31:0] done_id,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic [31:0] backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic [31:0] backing_rsp_id,input logic [255:0] backing_rsp_data,
 output logic store_req_valid,input logic store_req_ready,
 output logic [31:0] store_req_id,store_req_byte_address,store_req_data,
 input logic store_rsp_valid,output logic store_rsp_ready,
 input logic [31:0] store_rsp_id
);
 typedef enum logic [3:0]{IDLE,STAGE_SEND,STAGE_WAIT,MATRIX_SEND,
  MATRIX_WAIT,STORE_SEND,STORE_WAIT,DONE} state_t;
 state_t state;
 logic [31:0] saved_launch_id,saved_input_base,saved_output_base;
 int stage_number,word_number,store_number;
 logic stage_valid,stage_ready,stage_done_valid,stage_done_ready,stage_done_hit;
 logic [31:0] stage_id,stage_global_address,stage_shared_address,stage_done_id;
 logic matrix_valid,matrix_ready,matrix_rsp_valid,matrix_rsp_ready;
 logic [31:0] matrix_id,matrix_rsp_id;
 logic [31:0] a_addresses[32],b_addresses[32];
 logic [31:0] accumulator[32][8],matrix_results[32][8];
 logic operands_initialized,addresses_legal;int outstanding;
 initial if(STAGES<1||STAGES>65535)$fatal(1,"Invalid stage count");
 assign launch_ready=!rst&&state==IDLE;
 assign done_valid=!rst&&state==DONE;assign done_id=saved_launch_id;
 assign stage_valid=!rst&&state==STAGE_SEND;
 assign stage_id=32'(stage_number*256+word_number);
 assign stage_global_address=saved_input_base+32'(stage_number*1024+word_number*4);
 assign stage_shared_address=32'(word_number*4);
 assign stage_done_ready=!rst&&state==STAGE_WAIT;
 assign matrix_valid=!rst&&state==MATRIX_SEND;assign matrix_id=32'(stage_number);
 assign matrix_rsp_ready=!rst&&state==MATRIX_WAIT;
 assign store_req_valid=!rst&&state==STORE_SEND;
 assign store_req_id=32'(store_number);
 assign store_rsp_ready=!rst&&state==STORE_WAIT;
 assign store_req_byte_address=saved_output_base+
  32'(4*native_bf16_layout::c_element_index(store_number/8,store_number%8));
 assign store_req_data=accumulator[store_number/8][store_number%8];
 always_comb begin
  for(int lane=0;lane<32;lane++)begin
   a_addresses[lane]=32'(lane*16);b_addresses[lane]=32'(512+lane*16);
  end
 end
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;saved_launch_id<=0;saved_input_base<=0;saved_output_base<=0;
   stage_number<=0;word_number<=0;store_number<=0;
   for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)accumulator[lane][word]<=0;
  end else case(state)
   IDLE:if(launch_valid&&launch_ready)begin
    if(input_base[9:0]!=0||output_base[1:0]!=0)
     $fatal(1,"Unaligned GEMM launch base address");
    if({1'b0,input_base}+33'(STAGES*1024)>33'h100000000 ||
       {1'b0,output_base}+33'd1024>33'h100000000)
     $fatal(1,"GEMM address span exceeds 32-bit address space");
    if({1'b0,output_base}<{1'b0,input_base}+33'(STAGES*1024)&&
       {1'b0,input_base}<{1'b0,output_base}+33'd1024)
     $fatal(1,"Overlapping input/output requires unsupported cache write coherence");
    saved_launch_id<=launch_id;saved_input_base<=input_base;saved_output_base<=output_base;
    stage_number<=0;word_number<=0;store_number<=0;
    for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)accumulator[lane][word]<=0;
    state<=STAGE_SEND;
   end
   STAGE_SEND:if(stage_valid&&stage_ready)state<=STAGE_WAIT;
   STAGE_WAIT:if(stage_done_valid&&stage_done_ready)begin
    if(stage_done_id!=stage_id)$fatal(1,"Staging completion identity mismatch");
    if(word_number==255)begin word_number<=0;state<=MATRIX_SEND;end
    else begin word_number<=word_number+1;state<=STAGE_SEND;end
   end
   MATRIX_SEND:if(matrix_valid&&matrix_ready)state<=MATRIX_WAIT;
   MATRIX_WAIT:if(matrix_rsp_valid&&matrix_rsp_ready)begin
    if(matrix_rsp_id!=matrix_id)$fatal(1,"Matrix completion identity mismatch");
    for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)
     accumulator[lane][word]<=matrix_results[lane][word];
    if(stage_number==STAGES-1)begin store_number<=0;state<=STORE_SEND;end
    else begin stage_number<=stage_number+1;word_number<=0;state<=STAGE_SEND;end
   end
   STORE_SEND:if(store_req_valid&&store_req_ready)state<=STORE_WAIT;
   STORE_WAIT:if(store_rsp_valid&&store_rsp_ready)begin
    if(store_rsp_id!=store_req_id)$fatal(1,"Store completion identity mismatch");
    if(store_number==255)state<=DONE;
    else begin store_number<=store_number+1;state<=STORE_SEND;end
   end
   DONE:if(done_valid&&done_ready)state<=IDLE;
   default:$fatal(1,"Invalid GEMM controller state");
  endcase
 end
 cached_shared_matrix_pipeline #(.SETS(SETS),.WAYS(WAYS),.SHARED_BYTES(SHARED_BYTES),
  .SLOTS(SLOTS),.LATENCY(LATENCY),.INTERVAL(INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) path(
  .clk,.rst,.stage_valid,.stage_ready,.stage_id,
  .stage_global_byte_address(stage_global_address),.stage_shared_byte_address(stage_shared_address),
  .stage_done_valid,.stage_done_ready,.stage_done_id,.stage_done_hit,
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,
  .backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data,
  .req_valid(matrix_valid),.req_ready(matrix_ready),.req_id(matrix_id),
  .a_row_addresses(a_addresses),.b_row_addresses(b_addresses),.c_registers(accumulator),
  .operands_initialized,.addresses_legal,
  .rsp_valid(matrix_rsp_valid),.rsp_ready(matrix_rsp_ready),.rsp_id(matrix_rsp_id),
  .result_registers(matrix_results),.outstanding
 );
 // Backing provider must flush pre-reset transactions; IDs have no reset epoch.
 // Store acknowledgement means actual externally defined completion, not launch.
endmodule
