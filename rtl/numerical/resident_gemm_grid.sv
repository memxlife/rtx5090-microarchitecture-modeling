// A complete grid dispatches into one resident SM model. Column index changes
// fastest within each tile row. Scheduling/timing are hypotheses, not multi-SM.
module resident_gemm_grid #(
 parameter int CONTEXTS=2,M=64,N=96,K=64,SETS=64,WAYS=8,
 parameter int READ_SLOTS=2,RETURN_DELAY=9,MOVM_LATENCY=19,HMMA_LATENCY=73,
 parameter int SERVICE_INTERVAL=1,MOVM_INTERVAL=1,HMMA_INTERVAL=4,ARITHMETIC_MODE=1,
 parameter int STORE_INTERVAL=1,STORE_RETURN_DELAY=1,BARRIER_RELEASE_DELAY=1
)(
 input logic clk,rst,launch_valid,output logic launch_ready,
 input logic[31:0]launch_id,a_base,b_base,c_base,
 output logic done_valid,input logic done_ready,output logic[31:0]done_id,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data,
 output logic store_backing_req_valid,input logic store_backing_req_ready,
 output logic[31:0]store_backing_req_id,store_backing_req_byte_address,
 output logic[255:0]store_backing_req_data,output logic[7:0]store_backing_req_word_mask,
 input logic store_backing_rsp_valid,output logic store_backing_rsp_ready,input logic[31:0]store_backing_rsp_id,
 output int resident_blocks,resident_warps,dispatched_blocks,completed_blocks,
 output logic[63:0]elapsed_cycles,
 output logic block_launch_valid,block_done_valid,
 output logic[31:0]block_launch_ordinal,block_launch_row,block_launch_col,
 output logic[31:0]block_done_ordinal,block_done_row,block_done_col,
 output logic native_issue_valid,output logic[31:0]native_issue_context,native_issue_warp,native_issue_pc
);
 localparam int TILE_ROWS=M/32,TILE_COLS=N/32,BLOCKS=TILE_ROWS*TILE_COLS;
 typedef enum logic[1:0]{IDLE,RUN,COMPLETE}state_t;
 state_t state;logic[31:0]saved_id,saved_a,saved_b,saved_c;
 logic launched[BLOCKS],completed[BLOCKS];logic launch_legal;
 logic child_launch_valid,child_launch_ready,child_done_valid,child_done_ready;
 logic[31:0]child_id,child_done_id,child_done_context,child_result[4][32][8];
 initial if(CONTEXTS<1||M<32||N<32||K<32||M%32||N%32||K%32||BLOCKS<1)$fatal(1,"Invalid resident grid geometry");
 always_comb begin
  launch_legal=!a_base[0]&&!b_base[0]&&c_base[1:0]==0;
  if(64'(a_base)+2*64'(M)*64'(K)>64'h100000000||64'(b_base)+2*64'(K)*64'(N)>64'h100000000||64'(c_base)+4*64'(M)*64'(N)>64'h100000000)launch_legal=0;
  if(64'(c_base)<64'(a_base)+2*64'(M)*64'(K)&&64'(a_base)<64'(c_base)+4*64'(M)*64'(N))launch_legal=0;
  if(64'(c_base)<64'(b_base)+2*64'(K)*64'(N)&&64'(b_base)<64'(c_base)+4*64'(M)*64'(N))launch_legal=0;
 end
 assign launch_ready=!rst&&state==IDLE&&launch_legal;
 assign done_valid=!rst&&state==COMPLETE;assign done_id=saved_id;
 assign child_launch_valid=!rst&&state==RUN&&dispatched_blocks<BLOCKS;
 assign child_id=32'(dispatched_blocks);
 assign child_done_ready=!rst&&state==RUN;
 assign block_launch_valid=child_launch_valid&&child_launch_ready;
 assign block_launch_ordinal=child_id;
 assign block_launch_row=32'(dispatched_blocks/TILE_COLS);
 assign block_launch_col=32'(dispatched_blocks%TILE_COLS);
 assign block_done_valid=child_done_valid&&child_done_ready;
 assign block_done_ordinal=child_done_id;
 assign block_done_row=child_done_id/32'(TILE_COLS);
 assign block_done_col=child_done_id%32'(TILE_COLS);
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;elapsed_cycles<=0;saved_id<=0;saved_a<=0;saved_b<=0;saved_c<=0;dispatched_blocks<=0;completed_blocks<=0;
   for(int block_index=0;block_index<BLOCKS;block_index++)begin launched[block_index]<=0;completed[block_index]<=0;end
  end else begin
   if(launch_valid&&state==IDLE&&!launch_legal)$fatal(1,"Invalid resident grid launch allocation");
   if(state==RUN&&resident_blocks!=dispatched_blocks-completed_blocks)$fatal(1,"Grid dispatch/retirement conservation failed");
   case(state)
    IDLE:if(launch_valid&&launch_ready)begin
     elapsed_cycles<=0;saved_id<=launch_id;saved_a<=a_base;saved_b<=b_base;saved_c<=c_base;
     dispatched_blocks<=0;completed_blocks<=0;
     for(int block_index=0;block_index<BLOCKS;block_index++)begin launched[block_index]<=0;completed[block_index]<=0;end
     state<=RUN;
    end
    RUN:begin
     elapsed_cycles<=elapsed_cycles+1;
     if(block_launch_valid)begin
      if(dispatched_blocks>=BLOCKS||launched[dispatched_blocks])$fatal(1,"Duplicate/out-of-range grid dispatch");
      launched[dispatched_blocks]<=1;dispatched_blocks<=dispatched_blocks+1;
     end
     if(block_done_valid)begin
      if(child_done_id>=BLOCKS)$fatal(1,"Out-of-range grid completion");
      else if(!launched[child_done_id]||completed[child_done_id])$fatal(1,"Unlaunched/duplicate grid completion");
      completed[child_done_id]<=1;completed_blocks<=completed_blocks+1;
     end
     if(dispatched_blocks==BLOCKS&&completed_blocks==BLOCKS&&resident_blocks==0)state<=COMPLETE;
    end
    COMPLETE:if(done_valid&&done_ready)state<=IDLE;
    default:$fatal(1,"Invalid resident grid state");
   endcase
  end
 end
 resident_gemm_complete #(.CONTEXTS(CONTEXTS),.M(M),.N(N),.K(K),.SETS(SETS),.WAYS(WAYS),
  .READ_SLOTS(READ_SLOTS),.RETURN_DELAY(RETURN_DELAY),.MOVM_LATENCY(MOVM_LATENCY),.HMMA_LATENCY(HMMA_LATENCY),
  .SERVICE_INTERVAL(SERVICE_INTERVAL),.MOVM_INTERVAL(MOVM_INTERVAL),.HMMA_INTERVAL(HMMA_INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE),
  .STORE_INTERVAL(STORE_INTERVAL),.STORE_RETURN_DELAY(STORE_RETURN_DELAY),.BARRIER_RELEASE_DELAY(BARRIER_RELEASE_DELAY)) sm(
  .clk,.rst,.launch_valid(child_launch_valid),.launch_ready(child_launch_ready),.launch_id(child_id),.a_base(saved_a),.b_base(saved_b),.c_base(saved_c),
  .cta_row(32'(dispatched_blocks/TILE_COLS)),.cta_col(32'(dispatched_blocks%TILE_COLS)),
  .done_valid(child_done_valid),.done_ready(child_done_ready),.done_id(child_done_id),.done_context(child_done_context),.result_registers(child_result),
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,.backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data,
  .store_backing_req_valid,.store_backing_req_ready,.store_backing_req_id,.store_backing_req_byte_address,.store_backing_req_data,.store_backing_req_word_mask,
  .store_backing_rsp_valid,.store_backing_rsp_ready,.store_backing_rsp_id,.resident_blocks,.resident_warps,
  .native_issue_valid,.native_issue_context,.native_issue_warp,.native_issue_pc
 );
 // elapsed_cycles counts every edge after accepted launch through the edge
 // registering COMPLETE (including the final retirement and drain-check edge).
 // It freezes while COMPLETE is held; no hardware-frequency conversion implied.
 // Completion means all child stores acknowledged, every block retired, and
 // resident reservations zero. Providers must cancel stale returns on reset.
endmodule
