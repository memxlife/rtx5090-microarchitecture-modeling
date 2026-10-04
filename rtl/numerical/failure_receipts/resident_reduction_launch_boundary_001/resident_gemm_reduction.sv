// Concurrent complete-reduction operand/compute path for native BM32/BN32.
// One shared input cache and one shared read/MOVM/HMMA service set.
// Results are registers only: output scratch, global stores and CTA barriers
// are not reconstructed here. Result acknowledgement is NOT full CTA retirement.
module resident_gemm_reduction #(
 parameter int CONTEXTS=2,M=64,N=96,K=64,SETS=64,WAYS=8,
 parameter int READ_SLOTS=2,RETURN_DELAY=9,MOVM_LATENCY=19,HMMA_LATENCY=73,
 parameter int SERVICE_INTERVAL=1,MOVM_INTERVAL=1,HMMA_INTERVAL=4,ARITHMETIC_MODE=1
)(
 input logic clk,rst,launch_valid,output logic launch_ready,
 input logic[31:0]launch_id,a_base,b_base,cta_row,cta_col,
 output logic done_valid,input logic done_ready,
 output logic[31:0]done_id,done_context,result_registers[4][32][8],
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data,
 output int resident_blocks,resident_warps,
 output logic native_issue_valid,output logic[31:0]native_issue_context,native_issue_warp,native_issue_pc
);
 localparam int STAGES=K/32;
 typedef enum logic[2:0]{IDLE,STAGE_SEND,STAGE_WAIT,COMPUTE_SEND,COMPUTE_WAIT,RESULT}state_t;
 state_t state[CONTEXTS];
 logic[31:0]ids[CONTEXTS],rows[CONTEXTS],cols[CONTEXTS],abase[CONTEXTS],bbase[CONTEXTS];
 logic[31:0]accumulators[CONTEXTS][4][32][8];
 int stage_number[CONTEXTS],stage_owner,stage_cursor,compute_owner,compute_cursor,result_owner,result_cursor;
 int admitted_slot,allocated_register_words,allocated_shared_bytes;
 logic allocator_ready,launch_legal,admit_fire,retire_fire;
 logic staging_valid,staging_ready,staging_done_valid,staging_done_ready;
 logic[31:0]staging_context,staging_id,staging_done_context,staging_done_id;
 logic[CONTEXTS-1:0]staging_context_ready;int staging_outstanding;
 logic write_warp_valid,write_warp_ready;logic[31:0]write_context,write_warp_byte_addresses[32],write_warp_mask;
 logic[15:0]write_warp_halfwords[32];
 logic compute_valid,compute_ready,compute_rsp_valid,compute_rsp_ready;
 logic[31:0]compute_context,compute_id,compute_rsp_context,compute_rsp_id;
 logic[31:0]compute_c[4][32][8],compute_result[4][32][8];
 logic[CONTEXTS-1:0]compute_context_ready,compute_context_initialized;
 logic[3:0]warp_drained[CONTEXTS],warp_memory_safe[CONTEXTS];
 logic initialized,legal;int compute_outstanding;
 initial if(CONTEXTS<1||M<32||N<32||K<32||M%32||N%32||K%32)$fatal(1,"Unsupported resident reduction geometry");
 assign launch_legal=({32'b0,cta_row}+64'd1)*64'd32<=64'(M)&&
                     ({32'b0,cta_col}+64'd1)*64'd32<=64'(N);
 assign launch_ready=!rst&&allocator_ready&&launch_legal;
 assign admit_fire=launch_valid&&launch_ready;
 assign done_valid=!rst&&result_owner>=0;
 assign done_context=result_owner>=0?32'(result_owner):0;
 assign done_id=result_owner>=0?ids[result_owner]:0;
 assign retire_fire=done_valid&&done_ready;
 always_comb begin
  for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)begin
   result_registers[w][l][e]=result_owner>=0?accumulators[result_owner][w][l][e]:0;
   compute_c[w][l][e]=compute_owner>=0?accumulators[compute_owner][w][l][e]:0;
  end
 end
 assign staging_valid=!rst&&stage_owner>=0;
 assign staging_context=stage_owner>=0?32'(stage_owner):0;
 assign staging_id=stage_owner>=0?32'(stage_number[stage_owner]):0;
 assign staging_done_ready=!rst&&staging_done_context<CONTEXTS&&
                           (staging_done_context<CONTEXTS?state[staging_done_context]==STAGE_WAIT:0);
 assign compute_valid=!rst&&compute_owner>=0;
 assign compute_context=compute_owner>=0?32'(compute_owner):0;
 assign compute_id=compute_owner>=0?32'(stage_number[compute_owner]):0;
 assign compute_rsp_ready=!rst&&compute_rsp_context<CONTEXTS&&
                         (compute_rsp_context<CONTEXTS?state[compute_rsp_context]==COMPUTE_WAIT:0);
 quantized_block_admission #(.BLOCK_SLOTS(CONTEXTS)) admission(
  .clk,.rst,.admit_valid(admit_fire),.block_threads(128),.registers_per_thread(40),
  .user_shared_bytes(8192),.reserved_shared_bytes(1024),.admit_ready(allocator_ready),
  .admitted_slot,.resident_blocks,.resident_warps,.allocated_register_words,.allocated_shared_bytes,
  .retire_valid(retire_fire),.retire_slot(result_owner)
 );
 always_ff @(posedge clk)begin
  if(rst)begin
   stage_owner<=-1;stage_cursor<=0;compute_owner<=-1;compute_cursor<=0;result_owner<=-1;result_cursor<=0;
   for(int c=0;c<CONTEXTS;c++)begin
    state[c]<=IDLE;ids[c]<=0;rows[c]<=0;cols[c]<=0;abase[c]<=0;bbase[c]<=0;stage_number[c]<=0;
    for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)accumulators[c][w][l][e]<=0;
   end
  end else begin
   integer active;active=0;for(int c=0;c<CONTEXTS;c++)if(state[c]!=IDLE)active++;
   if(active!=resident_blocks||resident_warps!=4*active)$fatal(1,"Reduction resource/context conservation failed");
   if(launch_valid&&!launch_legal)$fatal(1,"Reduction launch outside complete output grid");
   if(admit_fire)begin
    if(admitted_slot<0||admitted_slot>=CONTEXTS||state[admitted_slot]!=IDLE)$fatal(1,"Reduction slot admission mismatch");
    state[admitted_slot]<=STAGE_SEND;ids[admitted_slot]<=launch_id;rows[admitted_slot]<=cta_row;cols[admitted_slot]<=cta_col;
    abase[admitted_slot]<=a_base;bbase[admitted_slot]<=b_base;stage_number[admitted_slot]<=0;
    for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)accumulators[admitted_slot][w][l][e]<=0;
   end
   // Owners are registered before a request is offered; stalled payloads stay fixed.
   if(stage_owner<0)begin
    integer choice;choice=-1;
    for(int off=0;off<CONTEXTS;off++)begin integer c;c=(stage_cursor+off)%CONTEXTS;
     if(choice<0&&state[c]==STAGE_SEND)choice=c;
    end
    if(choice>=0)stage_owner<=choice;
   end else if(staging_valid&&staging_ready)begin
    state[stage_owner]<=STAGE_WAIT;stage_cursor<=(stage_owner+1)%CONTEXTS;stage_owner<=-1;
   end
   if(staging_done_valid)begin
    if(staging_done_context>=CONTEXTS)$fatal(1,"Unknown staging completion context");
    else if(state[staging_done_context]!=STAGE_WAIT||staging_done_id!=32'(stage_number[staging_done_context]))$fatal(1,"Staging completion ownership mismatch");
   end
   if(staging_done_valid&&staging_done_ready)state[staging_done_context]<=COMPUTE_SEND;
   if(compute_owner<0)begin
    integer choice;choice=-1;
    for(int off=0;off<CONTEXTS;off++)begin integer c;c=(compute_cursor+off)%CONTEXTS;
     if(choice<0&&state[c]==COMPUTE_SEND)choice=c;
    end
    if(choice>=0)compute_owner<=choice;
   end else if(compute_valid&&compute_ready)begin
    state[compute_owner]<=COMPUTE_WAIT;compute_cursor<=(compute_owner+1)%CONTEXTS;compute_owner<=-1;
   end
   if(compute_rsp_valid)begin
    if(compute_rsp_context>=CONTEXTS)$fatal(1,"Unknown compute completion context");
    else if(state[compute_rsp_context]!=COMPUTE_WAIT||compute_rsp_id!=32'(stage_number[compute_rsp_context]))$fatal(1,"Compute completion ownership mismatch");
   end
   if(compute_rsp_valid&&compute_rsp_ready)begin
    for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)accumulators[compute_rsp_context][w][l][e]<=compute_result[w][l][e];
    if(stage_number[compute_rsp_context]==STAGES-1)state[compute_rsp_context]<=RESULT;
    else begin stage_number[compute_rsp_context]<=stage_number[compute_rsp_context]+1;state[compute_rsp_context]<=STAGE_SEND;end
   end
   if(result_owner<0)begin
    integer choice;choice=-1;
    for(int off=0;off<CONTEXTS;off++)begin integer c;c=(result_cursor+off)%CONTEXTS;
     if(choice<0&&state[c]==RESULT)choice=c;
    end
    if(choice>=0)result_owner<=choice;
   end else if(retire_fire)begin
    state[result_owner]<=IDLE;result_cursor<=(result_owner+1)%CONTEXTS;result_owner<=-1;
   end
  end
 end
 resident_operand_staging #(.CONTEXTS(CONTEXTS),.M(M),.N(N),.K(K),.SETS(SETS),.WAYS(WAYS)) staging(
  .clk,.rst,.req_valid(staging_valid),.req_ready(staging_ready),.req_context(staging_context),.req_id(staging_id),
  .a_base(stage_owner>=0?abase[stage_owner]:0),.b_base(stage_owner>=0?bbase[stage_owner]:0),
  .cta_row(stage_owner>=0?rows[stage_owner]:0),.cta_col(stage_owner>=0?cols[stage_owner]:0),
  .stage_index(stage_owner>=0?32'(stage_number[stage_owner]):0),
  .context_ready(staging_context_ready),.outstanding(staging_outstanding),
  .write_warp_valid,.write_warp_ready,.write_context,.write_warp_byte_addresses,.write_warp_halfwords,.write_warp_mask,
  .done_valid(staging_done_valid),.done_ready(staging_done_ready),.done_context(staging_done_context),.done_id(staging_done_id),
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,
  .backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data
 );
 resident_native_stage_engine #(.CONTEXTS(CONTEXTS),.ALLOW_WARP_WRITES(1),.READ_SLOTS(READ_SLOTS),
  .SERVICE_INTERVAL(SERVICE_INTERVAL),.RETURN_DELAY(RETURN_DELAY),.MOVM_LATENCY(MOVM_LATENCY),.MOVM_INTERVAL(MOVM_INTERVAL),
  .HMMA_LATENCY(HMMA_LATENCY),.HMMA_INTERVAL(HMMA_INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) engine(
  .clk,.rst,.write_context,.write_valid(1'b0),.write_ready(),.write_byte_address(32'd0),.write_data(16'd0),
  .write_warp_valid,.write_warp_ready,.write_warp_byte_addresses,.write_warp_halfwords,.write_warp_mask,
  .req_valid(compute_valid),.req_ready(compute_ready),.req_context(compute_context),.req_id(compute_id),.c_registers(compute_c),
  .operands_initialized(initialized),.addresses_legal(legal),.context_ready(compute_context_ready),.context_initialized(compute_context_initialized),
  .rsp_valid(compute_rsp_valid),.rsp_ready(compute_rsp_ready),.rsp_context(compute_rsp_context),.rsp_id(compute_rsp_id),
  .result_registers(compute_result),.outstanding(compute_outstanding),.warp_drained,.warp_memory_safe,
  .native_issue_valid,.native_issue_context,.native_issue_warp,.native_issue_pc
 );
endmodule
