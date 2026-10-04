// Concurrent complete-reduction operand/compute path for native BM32/BN32.
// One shared input cache and one shared read/MOVM/HMMA service set.
// Actual scratch/output-store acknowledgments and context barrier generations
// complete this bounded lifecycle. Arbitration and all timing remain hypotheses.
module large_gemm_complete #(
 parameter int CONTEXTS=2,M=64,N=96,K=64,SETS=64,WAYS=8,
 parameter int STORE_INTERVAL=1,STORE_RETURN_DELAY=1,BARRIER_RELEASE_DELAY=1,
 parameter int READ_SLOTS=2,RETURN_DELAY=9,MOVM_LATENCY=19,HMMA_LATENCY=73,
 parameter int SERVICE_INTERVAL=1,MOVM_INTERVAL=1,HMMA_INTERVAL=4,ARITHMETIC_MODE=1
)(
 input logic clk,rst,local_cache_invalidate,launch_valid,output logic launch_ready,
 input logic[31:0]launch_id,a_base,b_base,c_base,cta_row,cta_col,
 output logic done_valid,input logic done_ready,
 output logic[31:0]done_id,done_context,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data,
 output logic store_backing_req_valid,input logic store_backing_req_ready,
 output logic[31:0]store_backing_req_id,store_backing_req_byte_address,
 output logic[255:0]store_backing_req_data,output logic[7:0]store_backing_req_word_mask,
 input logic store_backing_rsp_valid,output logic store_backing_rsp_ready,input logic[31:0]store_backing_rsp_id,
 output int resident_blocks,resident_warps,
 output logic native_issue_valid,output logic[31:0]native_issue_context,native_issue_warp,native_issue_pc
);
 /* verilator hier_block */
 localparam int STAGES=K/32;
 typedef enum logic[2:0]{IDLE,STAGE_SEND,STAGE_WAIT,COMPUTE_SEND,COMPUTE_WAIT,OUTPUT_SEND,OUTPUT_WAIT,RESULT}state_t;
 state_t state[CONTEXTS];
 logic[31:0]ids[CONTEXTS],rows[CONTEXTS],cols[CONTEXTS],abase[CONTEXTS],bbase[CONTEXTS],cbase[CONTEXTS];
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
 logic[1:0]read_candidate_valid,read_candidate_grant,read_return_valid,read_return_ready;
 logic[31:0]read_candidate_id[2],read_candidate_addresses[2][32],read_candidate_words[2][32],read_return_id[2],read_return_words[2][32];
 int read_outstanding,read_client_outstanding[2];
 logic staging_commit_ready,engine_write_ready,scratch_store_candidate,scratch_store_grant;
 int write_cursor;
 logic producer_released[CONTEXTS],consumer_released[CONTEXTS];
 logic producer_release_valid[CONTEXTS],consumer_release_valid[CONTEXTS];
 logic[3:0]consumer_arrived[CONTEXTS],consumer_arrival_mask[CONTEXTS],consumer_seen[CONTEXTS];
 logic producer_arrival_valid[CONTEXTS];logic[3:0]producer_arrival_mask[CONTEXTS];
 int output_owner,output_cursor,store_ordinal;
 logic scratch_req_valid,scratch_req_ready,scratch_rsp_valid,scratch_rsp_ready;
 logic[31:0]scratch_rsp_id,scratch_c[4][32][8],scratch_words[4][256];
 int scratch_outstanding,scratch_store_requests,scratch_commit_words,scratch_read_requests,scratch_read_completions;
 logic store_req_valid,store_req_ready,store_rsp_valid,store_rsp_ready;
 logic[31:0]store_id,store_rsp_id,store_addresses[32],store_words[32];int store_sectors;
 logic store_wait;
 initial if(CONTEXTS<1||M<32||N<32||K<32||M%32||N%32||K%32)$fatal(1,"Unsupported resident reduction geometry");
 always_comb begin
  launch_legal=cta_row<M/32&&cta_col<N/32&&!a_base[0]&&!b_base[0]&&c_base[1:0]==0;
  if(64'(a_base)+2*64'(M)*64'(K)>64'h100000000||64'(b_base)+2*64'(K)*64'(N)>64'h100000000||64'(c_base)+4*64'(M)*64'(N)>64'h100000000)launch_legal=0;
  if(64'(c_base)<64'(a_base)+2*64'(M)*64'(K)&&64'(a_base)<64'(c_base)+4*64'(M)*64'(N))launch_legal=0;
  if(64'(c_base)<64'(b_base)+2*64'(K)*64'(N)&&64'(b_base)<64'(c_base)+4*64'(M)*64'(N))launch_legal=0;
 end
 assign launch_ready=!rst&&allocator_ready&&launch_legal;
 assign admit_fire=launch_valid&&launch_ready;
 assign done_valid=!rst&&result_owner>=0;
 assign done_context=result_owner>=0?32'(result_owner):0;
 assign done_id=result_owner>=0?ids[result_owner]:0;
 assign retire_fire=done_valid&&done_ready;
 always_comb begin
  for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)begin

   compute_c[w][l][e]=compute_owner>=0?accumulators[compute_owner][w][l][e]:0;
  end
 end
 assign staging_valid=!rst&&stage_owner>=0;
 assign staging_context=stage_owner>=0?32'(stage_owner):0;
 assign staging_id=stage_owner>=0?32'(stage_number[stage_owner]):0;
 assign staging_done_ready=!rst&&staging_done_context<CONTEXTS&&
                           (staging_done_context<CONTEXTS?state[staging_done_context]==STAGE_WAIT&&producer_released[staging_done_context]:0);
 assign compute_valid=!rst&&compute_owner>=0;
 assign compute_context=compute_owner>=0?32'(compute_owner):0;
 assign compute_id=compute_owner>=0?32'(stage_number[compute_owner]):0;
 assign compute_rsp_ready=!rst&&compute_rsp_context<CONTEXTS&&
                         (compute_rsp_context<CONTEXTS?state[compute_rsp_context]==COMPUTE_WAIT&&consumer_released[compute_rsp_context]:0);
 quantized_block_admission #(.BLOCK_SLOTS(CONTEXTS)) admission(
  .clk,.rst,.admit_valid(admit_fire),.block_threads(128),.registers_per_thread(40),
  .user_shared_bytes(8192),.reserved_shared_bytes(1024),.admit_ready(allocator_ready),
  .admitted_slot,.resident_blocks,.resident_warps,.allocated_register_words,.allocated_shared_bytes,
  .retire_valid(retire_fire),.retire_slot(result_owner)
 );
 always_ff @(posedge clk)begin
  if(rst)begin
   stage_owner<=-1;stage_cursor<=0;compute_owner<=-1;compute_cursor<=0;result_owner<=-1;result_cursor<=0;output_owner<=-1;output_cursor<=0;store_ordinal<=0;store_wait<=0;write_cursor<=0;
   for(int c=0;c<CONTEXTS;c++)begin
    state[c]<=IDLE;ids[c]<=0;rows[c]<=0;cols[c]<=0;abase[c]<=0;bbase[c]<=0;cbase[c]<=0;stage_number[c]<=0;producer_released[c]<=0;consumer_released[c]<=0;consumer_seen[c]<='0;
    for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)accumulators[c][w][l][e]<=0;
   end
  end else begin
   integer active;active=0;for(int c=0;c<CONTEXTS;c++)if(state[c]!=IDLE)active++;
   if(active!=resident_blocks||resident_warps!=4*active)$fatal(1,"Reduction resource/context conservation failed");
   if(launch_valid&&!launch_legal)$fatal(1,"Invalid resident reduction launch geometry or input allocation");
   if(admit_fire)begin
    if(admitted_slot<0||admitted_slot>=CONTEXTS||state[admitted_slot]!=IDLE)$fatal(1,"Reduction slot admission mismatch");
    state[admitted_slot]<=STAGE_SEND;ids[admitted_slot]<=launch_id;rows[admitted_slot]<=cta_row;cols[admitted_slot]<=cta_col;
    abase[admitted_slot]<=a_base;bbase[admitted_slot]<=b_base;cbase[admitted_slot]<=c_base;stage_number[admitted_slot]<=0;
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
    producer_released[stage_owner]<=0;state[stage_owner]<=STAGE_WAIT;stage_cursor<=(stage_owner+1)%CONTEXTS;stage_owner<=-1;
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
    consumer_released[compute_owner]<=0;consumer_seen[compute_owner]<='0;state[compute_owner]<=COMPUTE_WAIT;compute_cursor<=(compute_owner+1)%CONTEXTS;compute_owner<=-1;
   end
   if(compute_rsp_valid)begin
    if(compute_rsp_context>=CONTEXTS)$fatal(1,"Unknown compute completion context");
    else if(state[compute_rsp_context]!=COMPUTE_WAIT||compute_rsp_id!=32'(stage_number[compute_rsp_context]))$fatal(1,"Compute completion ownership mismatch");
   end
   if(compute_rsp_valid&&compute_rsp_ready)begin
    for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)accumulators[compute_rsp_context][w][l][e]<=compute_result[w][l][e];
    if(stage_number[compute_rsp_context]==STAGES-1)state[compute_rsp_context]<=OUTPUT_SEND;
    else begin stage_number[compute_rsp_context]<=stage_number[compute_rsp_context]+1;state[compute_rsp_context]<=STAGE_SEND;end
   end
   for(int ctx=0;ctx<CONTEXTS;ctx++)begin
    if(producer_release_valid[ctx])producer_released[ctx]<=1;
    if(consumer_release_valid[ctx])consumer_released[ctx]<=1;
    if(consumer_arrival_mask[ctx]!=0)consumer_seen[ctx]<=consumer_seen[ctx]|consumer_arrival_mask[ctx];
   end
   if(write_warp_valid&&staging_commit_ready)write_cursor<=1;
   if(scratch_store_grant)write_cursor<=0;
   if(output_owner<0)begin
    integer choice;choice=-1;
    for(int off=0;off<CONTEXTS;off++)begin integer c;c=(output_cursor+off)%CONTEXTS;
     if(choice<0&&state[c]==OUTPUT_SEND)choice=c;
    end
    if(choice>=0)begin output_owner<=choice;store_ordinal<=0;store_wait<=0;end
   end else begin
    if(scratch_req_valid&&scratch_req_ready)state[output_owner]<=OUTPUT_WAIT;
    if(scratch_rsp_valid&&scratch_rsp_id!=32'(output_owner))$fatal(1,"Scratch ownership mismatch");
    if(store_req_valid&&store_req_ready)store_wait<=1;
    if(store_rsp_valid)begin
     if(!store_wait||store_rsp_id!=store_id)$fatal(1,"Output store identity mismatch");
    end
    if(store_rsp_valid&&store_rsp_ready)begin
     store_wait<=0;
     if(store_ordinal==31)begin state[output_owner]<=RESULT;output_cursor<=(output_owner+1)%CONTEXTS;output_owner<=-1;end
     else store_ordinal<=store_ordinal+1;
    end
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
 large_operand_staging #(.CONTEXTS(CONTEXTS),.M(M),.N(N),.K(K),.SETS(SETS),.WAYS(WAYS)) staging(
  .clk,.rst(rst||local_cache_invalidate),.req_valid(staging_valid),.req_ready(staging_ready),.req_context(staging_context),.req_id(staging_id),
  .a_base(stage_owner>=0?abase[stage_owner]:0),.b_base(stage_owner>=0?bbase[stage_owner]:0),
  .cta_row(stage_owner>=0?rows[stage_owner]:0),.cta_col(stage_owner>=0?cols[stage_owner]:0),
  .stage_index(stage_owner>=0?32'(stage_number[stage_owner]):0),
  .context_ready(staging_context_ready),.outstanding(staging_outstanding),
  .write_warp_valid,.write_warp_ready(staging_commit_ready),.write_context,.write_warp_byte_addresses,.write_warp_halfwords,.write_warp_mask,
  .done_valid(staging_done_valid),.done_ready(staging_done_ready),.done_context(staging_done_context),.done_id(staging_done_id),
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,
  .backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data
 );
 large_native_stage_shared #(.CONTEXTS(CONTEXTS),.ALLOW_WARP_WRITES(1),.READ_SLOTS(READ_SLOTS),
  .SERVICE_INTERVAL(SERVICE_INTERVAL),.RETURN_DELAY(RETURN_DELAY),.MOVM_LATENCY(MOVM_LATENCY),.MOVM_INTERVAL(MOVM_INTERVAL),
  .HMMA_LATENCY(HMMA_LATENCY),.HMMA_INTERVAL(HMMA_INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) engine(
  .read_candidate_valid(read_candidate_valid[0]),.read_candidate_grant(read_candidate_grant[0]),
  .read_candidate_id(read_candidate_id[0]),.read_candidate_byte_addresses(read_candidate_addresses[0]),.read_candidate_input_words(read_candidate_words[0]),
  .read_rsp_valid(read_return_valid[0]),.read_rsp_ready(read_return_ready[0]),.read_rsp_id(read_return_id[0]),.read_rsp_words(read_return_words[0]),.read_client_outstanding(read_client_outstanding[0]),
  .clk,.rst,.write_context,.write_valid(1'b0),.write_ready(),.write_byte_address(32'd0),.write_data(16'd0),
  .write_warp_valid(write_warp_valid&&staging_commit_ready),.write_warp_ready(engine_write_ready),.write_warp_byte_addresses,.write_warp_halfwords,.write_warp_mask,
  .req_valid(compute_valid),.req_ready(compute_ready),.req_context(compute_context),.req_id(compute_id),.c_registers(compute_c),
  .operands_initialized(initialized),.addresses_legal(legal),.context_ready(compute_context_ready),.context_initialized(compute_context_initialized),
  .rsp_valid(compute_rsp_valid),.rsp_ready(compute_rsp_ready),.rsp_context(compute_rsp_context),.rsp_id(compute_rsp_id),
  .result_registers(compute_result),.outstanding(compute_outstanding),.warp_drained,.warp_memory_safe,
  .native_issue_valid,.native_issue_context,.native_issue_warp,.native_issue_pc
 );
 // Common write edge: staging vector or scratch bank package, never both.
 always_comb begin
  staging_commit_ready=0;scratch_store_grant=0;
  if(!rst)begin
   if(write_warp_valid&&engine_write_ready&&(!scratch_store_candidate||write_cursor==0))staging_commit_ready=1;
   else if(scratch_store_candidate)scratch_store_grant=1;
  end
 end
 assign write_warp_ready=staging_commit_ready;
 for(genvar ctx=0;ctx<CONTEXTS;ctx++)begin:barriers
  logic prod_arm_ready,cons_arm_ready,prod_arrival_ready,cons_arrival_ready,prod_active,cons_active;
  logic[31:0]prod_generation,cons_generation;logic[3:0]prod_arrived,prod_release_mask,cons_release_mask;
  always_comb begin
   producer_arrival_valid[ctx]=write_warp_valid&&staging_commit_ready&&write_context==ctx&&write_warp_byte_addresses[0]>=3840;
   producer_arrival_mask[ctx]=producer_arrival_valid[ctx]?4'(1<<(int'(write_warp_byte_addresses[0])/64-60)):0;
   consumer_arrival_mask[ctx]=state[ctx]==COMPUTE_WAIT?(warp_memory_safe[ctx]&~consumer_seen[ctx]):0;
  end
  cta_generation_barrier #(.RELEASE_DELAY(BARRIER_RELEASE_DELAY)) producer(
   .clk,.rst(rst||state[ctx]==IDLE),.arm_valid(staging_valid&&staging_ready&&stage_owner==ctx),.arm_ready(prod_arm_ready),.arm_generation(32'(stage_number[ctx])),.expected_mask(4'b1111),
   .arrival_valid(producer_arrival_valid[ctx]),.arrival_ready(prod_arrival_ready),.arrival_generation(32'(stage_number[ctx])),.arrival_mask(producer_arrival_mask[ctx]),
   .release_valid(producer_release_valid[ctx]),.release_ready(1'b1),.generation(prod_generation),.release_mask(prod_release_mask),.arrived_mask(prod_arrived),.active(prod_active));
  cta_generation_barrier #(.RELEASE_DELAY(BARRIER_RELEASE_DELAY)) consumer(
   .clk,.rst(rst||state[ctx]==IDLE),.arm_valid(compute_valid&&compute_ready&&compute_owner==ctx),.arm_ready(cons_arm_ready),.arm_generation(32'(stage_number[ctx])),.expected_mask(4'b1111),
   .arrival_valid(consumer_arrival_mask[ctx]!=0),.arrival_ready(cons_arrival_ready),.arrival_generation(32'(stage_number[ctx])),.arrival_mask(consumer_arrival_mask[ctx]),
   .release_valid(consumer_release_valid[ctx]),.release_ready(1'b1),.generation(cons_generation),.release_mask(cons_release_mask),.arrived_mask(consumer_arrived[ctx]),.active(cons_active));
 end
 large_shared_read_candidate_hub #(.CLIENTS(2),.SLOTS(READ_SLOTS),.SERVICE_INTERVAL(SERVICE_INTERVAL),.RETURN_DELAY(RETURN_DELAY)) read_hub(
  .clk,.rst,.candidate_valid(read_candidate_valid),.candidate_grant(read_candidate_grant),.candidate_id(read_candidate_id),.byte_addresses(read_candidate_addresses),.input_words(read_candidate_words),
  .rsp_valid(read_return_valid),.rsp_ready(read_return_ready),.rsp_id(read_return_id),.output_words(read_return_words),.outstanding(read_outstanding),.client_outstanding(read_client_outstanding));
 assign scratch_req_valid=!rst&&output_owner>=0&&(output_owner>=0?state[output_owner]==OUTPUT_SEND:0);
 always_comb for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)scratch_c[w][l][e]=output_owner>=0?accumulators[output_owner][w][l][e]:0;
 studied_output_scratch_shared #(.STORE_INTERVAL(STORE_INTERVAL),.STORE_RETURN_DELAY(STORE_RETURN_DELAY)) scratch(
  .clk,.rst,.store_candidate_valid(scratch_store_candidate),.store_grant(scratch_store_grant),
  .read_candidate_valid(read_candidate_valid[1]),.read_candidate_grant(read_candidate_grant[1]),.read_candidate_id(read_candidate_id[1]),.read_candidate_byte_addresses(read_candidate_addresses[1]),.read_candidate_input_words(read_candidate_words[1]),
  .read_rsp_valid(read_return_valid[1]),.read_rsp_ready(read_return_ready[1]),.read_rsp_id(read_return_id[1]),.read_rsp_words(read_return_words[1]),
  .req_valid(scratch_req_valid),.req_ready(scratch_req_ready),.req_id(output_owner>=0?32'(output_owner):0),.c_registers(scratch_c),
  .rsp_valid(scratch_rsp_valid),.rsp_ready(scratch_rsp_ready),.rsp_id(scratch_rsp_id),.row_major_words(scratch_words),.outstanding(scratch_outstanding),
  .store_requests(scratch_store_requests),.store_commit_words(scratch_commit_words),.read_requests(scratch_read_requests),.read_completions(scratch_read_completions));
 assign store_id=output_owner>=0?32'(output_owner*32+store_ordinal):0;
 assign store_req_valid=!rst&&output_owner>=0&&scratch_rsp_valid&&!store_wait;
 assign store_rsp_ready=!rst&&output_owner>=0&&store_wait;
 assign scratch_rsp_ready=store_rsp_valid&&store_rsp_ready&&store_ordinal==31;
 always_comb for(int lane=0;lane<32;lane++)begin
  int warp,index_value,row_value,col_value;
  warp=store_ordinal/8;index_value=32*(store_ordinal%8)+lane;
  row_value=16*(warp/2)+index_value/16;col_value=16*(warp%2)+index_value%16;
  store_words[lane]=scratch_words[warp][index_value];
  store_addresses[lane]=output_owner>=0?cbase[output_owner]+32'(4*((int'(rows[output_owner])*32+row_value)*N+int'(cols[output_owner])*32+col_value)):0;
 end
 coalesced_fp32_warp_store stores(
  .clk,.rst,.req_valid(store_req_valid),.req_ready(store_req_ready),.req_id(store_id),.byte_addresses(store_addresses),.words(store_words),.active_mask(32'hffffffff),
  .rsp_valid(store_rsp_valid),.rsp_ready(store_rsp_ready),.rsp_id(store_rsp_id),.sector_count(store_sectors),
  .backing_req_valid(store_backing_req_valid),.backing_req_ready(store_backing_req_ready),.backing_req_id(store_backing_req_id),.backing_req_byte_address(store_backing_req_byte_address),.backing_req_data(store_backing_req_data),.backing_req_word_mask(store_backing_req_word_mask),
  .backing_rsp_valid(store_backing_rsp_valid),.backing_rsp_ready(store_backing_rsp_ready),.backing_rsp_id(store_backing_rsp_id));
endmodule
