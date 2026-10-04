// Complete in-bounds GEMM grid through one reused CTA context.
// Block columns advance first, then rows. This serial development schedule
// is not a multi-SM model, native block-placement rule or GPU timing claim.
module studied_gemm_grid_controller #(
 parameter int BM=32,BN=32,BK=32,M=64,N=96,K=64,
 parameter int SETS=64,WAYS=8,LATENCY=16,INTERVAL=4,READ_SLOTS=4,
 parameter int SERVICE_INTERVAL=1,RETURN_DELAY=1,ARITHMETIC_MODE=1,
 parameter int BARRIER_RELEASE_DELAY=1,MOVM_LATENCY=1,MOVM_INTERVAL=1
)(
 input logic clk,rst,launch_valid,output logic launch_ready,
 input logic[31:0]launch_id,a_base,b_base,c_base,
 output logic done_valid,input logic done_ready,output logic[31:0]done_id,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data,
 output logic store_req_valid,input logic store_req_ready,
 output logic[31:0]store_req_id,store_req_byte_address,store_req_data,
 input logic store_rsp_valid,output logic store_rsp_ready,input logic[31:0]store_rsp_id,
 output logic sector_store_req_valid,input logic sector_store_req_ready,
 output logic[31:0]sector_store_req_id,sector_store_req_byte_address,
 output logic[255:0]sector_store_req_data,output logic[7:0]sector_store_req_word_mask,
 input logic sector_store_rsp_valid,output logic sector_store_rsp_ready,
 input logic[31:0]sector_store_rsp_id,
 output int dispatched_blocks,completed_blocks,
 output logic block_launch_valid,output logic[31:0]block_launch_row,block_launch_col,
 output logic block_done_valid,output logic[31:0]block_done_row,block_done_col
);
 localparam int BLOCK_ROWS=M/BM,BLOCK_COLS=N/BN,BLOCKS=BLOCK_ROWS*BLOCK_COLS;
 typedef enum logic[1:0]{IDLE,LAUNCH_BLOCK,WAIT_BLOCK,DONE}state_t;
 state_t state;int block_row,block_col,block_ordinal;
 logic[31:0]saved_id,saved_a,saved_b,saved_c;
 logic cta_launch_valid,cta_launch_ready,cta_done_valid,cta_done_ready;
 logic[31:0]cta_done_id;
 initial if(BM!=32||BN!=32||BK!=32||M<32||N<32||M%BM!=0||N%BN!=0||K<BK||K%BK!=0)
  $fatal(1,"Unsupported native studied full-grid geometry");
 assign launch_ready=!rst&&state==IDLE;
 assign done_valid=!rst&&state==DONE;assign done_id=saved_id;
 assign cta_launch_valid=!rst&&state==LAUNCH_BLOCK;
 assign cta_done_ready=!rst&&state==WAIT_BLOCK;
 assign block_launch_valid=cta_launch_valid&&cta_launch_ready;
 assign block_launch_row=32'(block_row);assign block_launch_col=32'(block_col);
 assign block_done_valid=cta_done_valid&&cta_done_ready;
 assign block_done_row=32'(block_row);assign block_done_col=32'(block_col);
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;block_row<=0;block_col<=0;block_ordinal<=0;
   saved_id<=0;saved_a<=0;saved_b<=0;saved_c<=0;dispatched_blocks<=0;completed_blocks<=0;
  end else case(state)
   IDLE:if(launch_valid&&launch_ready)begin
    saved_id<=launch_id;saved_a<=a_base;saved_b<=b_base;saved_c<=c_base;
    block_row<=0;block_col<=0;block_ordinal<=0;dispatched_blocks<=0;completed_blocks<=0;
    state<=LAUNCH_BLOCK;
   end
   LAUNCH_BLOCK:if(cta_launch_valid&&cta_launch_ready)begin
    if(dispatched_blocks!=block_ordinal||completed_blocks!=block_ordinal)$fatal(1,"Grid block dispatch conservation failed");
    dispatched_blocks<=dispatched_blocks+1;state<=WAIT_BLOCK;
   end
   WAIT_BLOCK:if(cta_done_valid&&cta_done_ready)begin
    if(cta_done_id!=32'(block_ordinal))$fatal(1,"Grid CTA completion identity mismatch");
    if(dispatched_blocks!=completed_blocks+1)$fatal(1,"Grid CTA completion conservation failed");
    completed_blocks<=completed_blocks+1;
    if(block_ordinal==BLOCKS-1)state<=DONE;
    else begin
     block_ordinal<=block_ordinal+1;
     if(block_col==BLOCK_COLS-1)begin block_col<=0;block_row<=block_row+1;end
     else block_col<=block_col+1;
     state<=LAUNCH_BLOCK;
    end
   end
   DONE:if(done_valid&&done_ready)state<=IDLE;
   default:$fatal(1,"Invalid studied GEMM grid state");
  endcase
 end
 studied_gemm_cta_controller #(.BM(BM),.BN(BN),.BK(BK),.M(M),.N(N),.K(K),
  .DYNAMIC_CTA_COORDS(1),.SETS(SETS),.WAYS(WAYS),.LATENCY(LATENCY),.INTERVAL(INTERVAL),.READ_SLOTS(READ_SLOTS),
  .SERVICE_INTERVAL(SERVICE_INTERVAL),.RETURN_DELAY(RETURN_DELAY),.ARITHMETIC_MODE(ARITHMETIC_MODE),
  .USE_NATIVE_STAGE(1),.COALESCED_STAGING(1),.COALESCED_OUTPUT(1),.MULTIWARP_NATIVE_STAGE(1),
  .USE_OUTPUT_SCRATCH(1),.USE_CTA_BARRIERS(1),.BARRIER_RELEASE_DELAY(BARRIER_RELEASE_DELAY),.MOVM_LATENCY(MOVM_LATENCY),.MOVM_INTERVAL(MOVM_INTERVAL)) cta(
  .clk,.rst,.launch_valid(cta_launch_valid),.launch_ready(cta_launch_ready),.launch_id(32'(block_ordinal)),
  .launch_cta_row(32'(block_row)),.launch_cta_col(32'(block_col)),.a_base(saved_a),.b_base(saved_b),.c_base(saved_c),
  .done_valid(cta_done_valid),.done_ready(cta_done_ready),.done_id(cta_done_id),
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,
  .backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data,
  .store_req_valid,.store_req_ready,.store_req_id,.store_req_byte_address,.store_req_data,
  .store_rsp_valid,.store_rsp_ready,.store_rsp_id,
  .sector_store_req_valid,.sector_store_req_ready,.sector_store_req_id,.sector_store_req_byte_address,.sector_store_req_data,.sector_store_req_word_mask,
  .sector_store_rsp_valid,.sector_store_rsp_ready,.sector_store_rsp_id
 );
 // CTA done already requires every output store acknowledgement. Cache persists
 // between contexts: backing inputs must stay immutable until reset/invalidate.
 // Reset providers flush old transactions; identities contain no reset epoch.
endmodule
