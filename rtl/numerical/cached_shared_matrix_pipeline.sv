// Behavioral integration: backing return -> cached word -> two shared halfwords.
// Geometry, blocking staging, and LATENCY are explicit model choices, not RTX timing.
module cached_shared_matrix_pipeline #(
 parameter int SETS=64,WAYS=8,SHARED_BYTES=32768,SLOTS=2,
 parameter int LATENCY=17,INTERVAL=3,ARITHMETIC_MODE=0
)(
 input logic clk,rst,
 input logic stage_valid,output logic stage_ready,
 input logic [31:0] stage_id,stage_global_byte_address,stage_shared_byte_address,
 output logic stage_done_valid,input logic stage_done_ready,
 output logic [31:0] stage_done_id,output logic stage_done_hit,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic [31:0] backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic [31:0] backing_rsp_id,input logic [255:0] backing_rsp_data,
 input logic req_valid,output logic req_ready,input logic [31:0] req_id,
 input logic [31:0] a_row_addresses[32],b_row_addresses[32],
 input logic [31:0] c_registers[32][8],
 output logic operands_initialized,addresses_legal,
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,result_registers[32][8],output int outstanding
);
 typedef enum logic [1:0] {IDLE,LOW_HALF,HIGH_HALF,DONE} state_t;
 state_t state;
 logic cache_req_ready,cache_rsp_valid,cache_rsp_ready,cache_rsp_hit;
 logic [31:0] cache_rsp_id,cache_rsp_data,saved_id,saved_shared_address;
 logic saved_hit,write_valid,write_ready,matrix_ready,matrix_admit;
 logic [31:0] write_byte_address;logic [15:0] write_data;
 logic stage_legal,stage_accept;
 initial if(SHARED_BYTES<1024||SHARED_BYTES%16!=0)
  $fatal(1,"Shared region must be a multiple of16 bytes and at least1024 bytes");
 assign stage_legal=stage_global_byte_address[1:0]==0 &&
                    stage_shared_byte_address[0]==0 &&
                    stage_shared_byte_address<=SHARED_BYTES-4;
 assign stage_ready=!rst&&state==IDLE&&cache_req_ready&&stage_legal;
 assign stage_accept=stage_valid&&stage_ready;
 assign stage_done_valid=!rst&&state==DONE;
 assign stage_done_id=saved_id;
 assign stage_done_hit=saved_hit;
 assign write_valid=!rst&&cache_rsp_valid&&(state==LOW_HALF||state==HIGH_HALF);
 assign write_byte_address=saved_shared_address+(state==HIGH_HALF?32'd2:32'd0);
 assign write_data=state==HIGH_HALF?cache_rsp_data[31:16]:cache_rsp_data[15:0];
 // Keep the cache response stable until its second halfword is stored.
 assign cache_rsp_ready=!rst&&state==HIGH_HALF&&write_ready;
 // A same-edge stage admission has priority over a matrix admission.
 assign matrix_admit=!rst&&state==IDLE&&!stage_accept;
 assign req_ready=matrix_admit&&matrix_ready;
 always_ff @(posedge clk) begin
  if(rst)begin state<=IDLE;saved_id<=0;saved_shared_address<=0;saved_hit<=0;end
  else begin
   if(stage_valid&&state==IDLE&&!stage_legal)
    $fatal(1,"Unaligned or out-of-bounds staging address");
   if(cache_rsp_valid&&(state==LOW_HALF||state==HIGH_HALF)&&cache_rsp_id!=saved_id)
    $fatal(1,"Stage/cache response identity mismatch");
   case(state)
    IDLE:if(stage_accept)begin
     saved_id<=stage_id;saved_shared_address<=stage_shared_byte_address;state<=LOW_HALF;
    end
    LOW_HALF:if(write_valid&&write_ready)state<=HIGH_HALF;
    HIGH_HALF:if(write_valid&&write_ready)begin saved_hit<=cache_rsp_hit;state<=DONE;end
    DONE:if(stage_done_valid&&stage_done_ready)state<=IDLE;
    default:$fatal(1,"Invalid staging state");
   endcase
  end
 end
 sector_read_cache #(.SETS(SETS),.WAYS(WAYS)) cache(
  .clk,.rst,.req_valid(stage_valid&&state==IDLE&&stage_legal),.req_ready(cache_req_ready),
  .req_id(stage_id),.req_byte_address(stage_global_byte_address),
  .rsp_valid(cache_rsp_valid),.rsp_ready(cache_rsp_ready),.rsp_id(cache_rsp_id),
  .rsp_data(cache_rsp_data),.rsp_hit(cache_rsp_hit),
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,
  .backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data
 );
 shared_matrix_pipeline #(.SHARED_BYTES(SHARED_BYTES),.SLOTS(SLOTS),
  .LATENCY(LATENCY),.INTERVAL(INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) shared_matrix(
  .clk,.rst,.write_valid,.write_ready,.write_byte_address,.write_data,
  .req_valid(req_valid&&matrix_admit),.req_ready(matrix_ready),.req_id,
  .a_row_addresses,.b_row_addresses,.c_registers,.operands_initialized,.addresses_legal,
  .rsp_valid,.rsp_ready,.rsp_id,.result_registers,.outstanding
 );
endmodule
