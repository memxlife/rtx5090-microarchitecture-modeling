module resident_component_top(input logic clk,rst,launch_valid,done_ready,staging_ready,staging_done_valid,compute_ready,compute_rsp_valid,scratch_req_ready,scratch_rsp_valid,store_req_ready,store_rsp_valid,write_warp_valid,staging_commit_ready,scratch_store_grant,input logic[31:0]launch_id,cta_row,cta_col,a_base,b_base,c_base,staging_done_context,staging_done_id,compute_rsp_context,compute_rsp_id,scratch_rsp_id,store_rsp_id,input logic producer_release_valid[11],consumer_release_valid[11],input logic[3:0]consumer_arrival_mask[11],output logic launch_ready,done_valid,staging_valid,compute_valid,staging_done_ready,compute_rsp_ready,scratch_req_valid,store_req_valid,store_rsp_ready,scratch_rsp_ready,output logic[31:0]done_id,done_context,staging_context,staging_id,compute_context,compute_id,store_id,output int resident_blocks,resident_warps,stage_owner,compute_owner,output_owner,result_owner,stage_cursor,compute_cursor,output_cursor,result_cursor,store_ordinal,write_cursor,output logic store_wait,output int state_out[11],stage_out[11],output logic producer_out[11],consumer_out[11],output logic[3:0]seen_out[11]);
localparam int CONTEXTS=11,STAGES=2;typedef enum logic[2:0]{IDLE,STAGE_SEND,STAGE_WAIT,COMPUTE_SEND,COMPUTE_WAIT,OUTPUT_SEND,OUTPUT_WAIT,RESULT}state_t;state_t state[CONTEXTS];
logic[31:0]ids[CONTEXTS],rows[CONTEXTS],cols[CONTEXTS],abase[CONTEXTS],bbase[CONTEXTS],cbase[CONTEXTS],accumulators[CONTEXTS][4][32][8],compute_result[4][32][8];int stage_number[CONTEXTS],admitted_slot,allocated_register_words,allocated_shared_bytes;logic producer_released[CONTEXTS],consumer_released[CONTEXTS];logic[3:0]consumer_seen[CONTEXTS];logic allocator_ready,launch_legal,admit_fire,retire_fire;
assign launch_legal=1;assign launch_ready=!rst&&allocator_ready;assign admit_fire=launch_valid&&launch_ready;assign done_valid=!rst&&result_owner>=0;assign done_context=result_owner>=0?32'(result_owner):0;assign done_id=result_owner>=0?ids[result_owner]:0;assign retire_fire=done_valid&&done_ready;
assign staging_valid=!rst&&stage_owner>=0;assign staging_context=stage_owner>=0?32'(stage_owner):0;assign staging_id=stage_owner>=0?32'(stage_number[stage_owner]):0;assign compute_valid=!rst&&compute_owner>=0;assign compute_context=compute_owner>=0?32'(compute_owner):0;assign compute_id=compute_owner>=0?32'(stage_number[compute_owner]):0;
assign staging_done_ready=!rst&&staging_done_context<CONTEXTS&&(staging_done_context<CONTEXTS?state[staging_done_context]==STAGE_WAIT&&producer_released[staging_done_context]:0);assign compute_rsp_ready=!rst&&compute_rsp_context<CONTEXTS&&(compute_rsp_context<CONTEXTS?state[compute_rsp_context]==COMPUTE_WAIT&&consumer_released[compute_rsp_context]:0);
assign scratch_req_valid=!rst&&output_owner>=0&&(output_owner>=0?state[output_owner]==OUTPUT_SEND:0);assign store_id=output_owner>=0?32'(output_owner*32+store_ordinal):0;assign store_req_valid=!rst&&output_owner>=0&&scratch_rsp_valid&&!store_wait;assign store_rsp_ready=!rst&&output_owner>=0&&store_wait;assign scratch_rsp_ready=store_rsp_valid&&store_rsp_ready&&store_ordinal==31;
quantized_block_admission #(.BLOCK_SLOTS(CONTEXTS)) admission(.clk,.rst,.admit_valid(admit_fire),.block_threads(128),.registers_per_thread(40),.user_shared_bytes(8192),.reserved_shared_bytes(1024),.admit_ready(allocator_ready),.admitted_slot,.resident_blocks,.resident_warps,.allocated_register_words,.allocated_shared_bytes,.retire_valid(retire_fire),.retire_slot(result_owner));
always_comb begin for(int c=0;c<11;c++)begin state_out[c]=int'(state[c]);stage_out[c]=stage_number[c];producer_out[c]=producer_released[c];consumer_out[c]=consumer_released[c];seen_out[c]=consumer_seen[c];end for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)compute_result[w][l][e]=0;end
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
endmodule
