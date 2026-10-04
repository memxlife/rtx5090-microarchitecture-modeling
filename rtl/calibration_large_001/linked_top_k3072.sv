// Read-only shared L2 test geometry; immutable inputs, disjoint write-around C.
// Complete disjoint grid across explicit resident SM models, one shared memory
// gateway. Serialization, dispatch RR and timing remain uncalibrated hypotheses.
module large_connected_top #(
 parameter int SLICES=48,L2_SETS=1024,L2_WAYS=16,OWNER_SLOTS=8,MSHRS=4,
 parameter int SMS=170,CONTEXTS=11,M=2048,N=2112,K=3072,SETS=64,WAYS=8,
 parameter int READ_SLOTS=2,RETURN_DELAY=9,MOVM_LATENCY=19,HMMA_LATENCY=73,
 parameter int SERVICE_INTERVAL=1,MOVM_INTERVAL=1,HMMA_INTERVAL=4,ARITHMETIC_MODE=1,
 parameter int STORE_INTERVAL=1,STORE_RETURN_DELAY=1,BARRIER_RELEASE_DELAY=1
)(
 input logic clk,rst,local_cache_invalidate,launch_valid,
 input int cache_read_rate_q10,cache_write_rate_q10,cache_mixed_rate_q10,
 input int l2_hit_delay_cycles,kernel_setup_cycles,output logic launch_ready,
 input logic[31:0]launch_id,a_base,b_base,c_base,
 output logic done_valid,input logic done_ready,output logic[31:0]done_id,
 output logic backing_req_valid[SLICES],input logic backing_req_ready[SLICES],
 output logic[31:0]backing_req_id[SLICES],backing_req_byte_address[SLICES],
 input logic backing_rsp_valid[SLICES],output logic backing_rsp_ready[SLICES],
 input logic[31:0]backing_rsp_id[SLICES],
 output logic store_backing_req_valid[SLICES],input logic store_backing_req_ready[SLICES],
 output logic[31:0]store_backing_req_id[SLICES],store_backing_req_byte_address[SLICES],
 output logic[7:0]store_backing_req_word_mask[SLICES],
 input logic store_backing_rsp_valid[SLICES],output logic store_backing_rsp_ready[SLICES],input logic[31:0]store_backing_rsp_id[SLICES],
 output int resident_blocks,resident_warps,dispatched_blocks,completed_blocks,
 output logic[63:0]elapsed_cycles,
 output logic block_launch_valid,block_done_valid,
 output logic[31:0]block_launch_ordinal,block_launch_row,block_launch_col,
 output logic[31:0]block_done_ordinal,block_done_row,block_done_col,block_launch_sm,block_done_sm,
 output int l2_read_requests,l2_read_hits,l2_read_misses,l2_merged_misses,l2_actual_fills,live_owners,live_mshrs,peak_owners,peak_mshrs,
 output logic[SMS-1:0]sm_native_issue_valid
);
 localparam int TILE_ROWS=M/32,TILE_COLS=N/32,BLOCKS=TILE_ROWS*TILE_COLS;
 typedef enum logic[1:0]{IDLE,RUN,COMPLETE,STARTUP}state_t;
 state_t state;int setup_left;logic[31:0]saved_id,saved_a,saved_b,saved_c;
 logic launched[BLOCKS],completed[BLOCKS];logic launch_legal;
 logic[SMS-1:0]child_launch_valid,child_launch_ready,child_done_valid,child_done_ready;
 logic[31:0]child_id,child_done_id[SMS],child_done_context[SMS];
 int launch_owner,launch_cursor,completion_owner,completion_cursor;
 int sm_resident_blocks[SMS],sm_resident_warps[SMS];
 logic[31:0]sm_native_context[SMS],sm_native_warp[SMS],sm_native_pc[SMS];
 logic[SMS-1:0]read_req_valid,read_req_ready,read_rsp_valid,read_rsp_ready,write_req_valid,write_req_ready,write_rsp_valid,write_rsp_ready;
 logic[31:0]read_req_id[SMS],read_req_byte_address[SMS],read_rsp_id[SMS],write_req_id[SMS],write_req_byte_address[SMS],write_rsp_id[SMS];
 logic[255:0]read_rsp_data[SMS],write_req_data[SMS];logic[7:0]write_req_word_mask[SMS];
 initial if(SMS<1||CONTEXTS<1||M<32||N<32||K<32||M%32||N%32||K%32||BLOCKS<1)$fatal(1,"Invalid resident grid geometry");
 always_comb begin
  launch_legal=!a_base[0]&&!b_base[0]&&c_base[1:0]==0;
  if(64'(a_base)+2*64'(M)*64'(K)>64'h100000000||64'(b_base)+2*64'(K)*64'(N)>64'h100000000||64'(c_base)+4*64'(M)*64'(N)>64'h100000000)launch_legal=0;
  if(64'(c_base)<64'(a_base)+2*64'(M)*64'(K)&&64'(a_base)<64'(c_base)+4*64'(M)*64'(N))launch_legal=0;
  if(64'(c_base)<64'(b_base)+2*64'(K)*64'(N)&&64'(b_base)<64'(c_base)+4*64'(M)*64'(N))launch_legal=0;
 end
 assign launch_ready=!rst&&state==IDLE&&launch_legal;
 assign done_valid=!rst&&state==COMPLETE;assign done_id=saved_id;
 assign child_id=32'(dispatched_blocks);
 always_comb begin
  child_launch_valid='0;child_done_ready='0;
  if(!rst&&state==RUN&&launch_owner>=0&&dispatched_blocks<BLOCKS)child_launch_valid[launch_owner]=1;
  completion_owner=-1;
  for(int off=0;off<SMS;off++)begin
   int sm;sm=(completion_cursor+off)%SMS;
   if(!rst&&state==RUN&&completion_owner<0&&child_done_valid[sm])completion_owner=sm;
  end
  if(completion_owner>=0)child_done_ready[completion_owner]=1;
  resident_blocks=0;resident_warps=0;
  for(int sm=0;sm<SMS;sm++)begin resident_blocks+=sm_resident_blocks[sm];resident_warps+=sm_resident_warps[sm];end
 end
 assign block_launch_valid=launch_owner>=0?(child_launch_valid[launch_owner]&&child_launch_ready[launch_owner]):0;
 assign block_launch_ordinal=child_id;assign block_launch_sm=launch_owner>=0?32'(launch_owner):0;
 assign block_launch_row=32'(dispatched_blocks/TILE_COLS);assign block_launch_col=32'(dispatched_blocks%TILE_COLS);
 assign block_done_valid=completion_owner>=0;
 assign block_done_ordinal=completion_owner>=0?child_done_id[completion_owner]:0;
 assign block_done_sm=completion_owner>=0?32'(completion_owner):0;
 assign block_done_row=block_done_ordinal/32'(TILE_COLS);assign block_done_col=block_done_ordinal%32'(TILE_COLS);
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;setup_left<=0;launch_owner<=-1;launch_cursor<=0;completion_cursor<=0;elapsed_cycles<=0;saved_id<=0;saved_a<=0;saved_b<=0;saved_c<=0;dispatched_blocks<=0;completed_blocks<=0;
   for(int block_index=0;block_index<BLOCKS;block_index++)begin launched[block_index]<=0;completed[block_index]<=0;end
  end else begin
   if(launch_valid&&state==IDLE&&!launch_legal)$fatal(1,"Invalid resident grid launch allocation");
   if(state==RUN&&resident_blocks!=dispatched_blocks-completed_blocks)$fatal(1,"Grid dispatch/retirement conservation failed");
   case(state)
    IDLE:if(launch_valid&&launch_ready)begin
     launch_owner<=-1;launch_cursor<=0;completion_cursor<=0;elapsed_cycles<=0;saved_id<=launch_id;saved_a<=a_base;saved_b<=b_base;saved_c<=c_base;
     dispatched_blocks<=0;completed_blocks<=0;
     for(int block_index=0;block_index<BLOCKS;block_index++)begin launched[block_index]<=0;completed[block_index]<=0;end
     setup_left<=kernel_setup_cycles-1;state<=kernel_setup_cycles>0?STARTUP:RUN;
    end
    STARTUP:begin elapsed_cycles<=elapsed_cycles+1;if(setup_left<=0)state<=RUN;else setup_left<=setup_left-1;end
    RUN:begin
     elapsed_cycles<=elapsed_cycles+1;
     if(launch_owner<0&&dispatched_blocks<BLOCKS)begin
      int choice;choice=-1;
      for(int off=0;off<SMS;off++)begin int sm;sm=(launch_cursor+off)%SMS;
       if(choice<0&&child_launch_ready[sm])choice=sm;
      end
      if(choice>=0)launch_owner<=choice;
     end
     if(block_launch_valid)begin launch_cursor<=(launch_owner+1)%SMS;launch_owner<=-1;end
     if(block_done_valid)completion_cursor<=(completion_owner+1)%SMS;
     if(block_launch_valid)begin
      if(dispatched_blocks>=BLOCKS||launched[dispatched_blocks])$fatal(1,"Duplicate/out-of-range grid dispatch");
      launched[dispatched_blocks]<=1;dispatched_blocks<=dispatched_blocks+1;
     end
     if(block_done_valid)begin
      if(block_done_ordinal>=BLOCKS)$fatal(1,"Out-of-range grid completion");
      else if(!launched[block_done_ordinal]||completed[block_done_ordinal])$fatal(1,"Unlaunched/duplicate grid completion");
      completed[block_done_ordinal]<=1;completed_blocks<=completed_blocks+1;
     end
     if(dispatched_blocks==BLOCKS&&completed_blocks==BLOCKS&&resident_blocks==0)state<=COMPLETE;
    end
    COMPLETE:if(done_valid&&done_ready)state<=IDLE;
    default:$fatal(1,"Invalid resident grid state");
   endcase
  end
 end
 for(genvar sm=0;sm<SMS;sm++)begin:sm_models
 large_gemm_complete_9 model(
  .clk,.rst,.local_cache_invalidate,.launch_valid(child_launch_valid[sm]),.launch_ready(child_launch_ready[sm]),.launch_id(child_id),.a_base(saved_a),.b_base(saved_b),.c_base(saved_c),
  .cta_row(32'(dispatched_blocks/TILE_COLS)),.cta_col(32'(dispatched_blocks%TILE_COLS)),
  .done_valid(child_done_valid[sm]),.done_ready(child_done_ready[sm]),.done_id(child_done_id[sm]),.done_context(child_done_context[sm]),
  .backing_req_valid(read_req_valid[sm]),.backing_req_ready(read_req_ready[sm]),.backing_req_id(read_req_id[sm]),.backing_req_byte_address(read_req_byte_address[sm]),
  .backing_rsp_valid(read_rsp_valid[sm]),.backing_rsp_ready(read_rsp_ready[sm]),.backing_rsp_id(read_rsp_id[sm]),.backing_rsp_data(read_rsp_data[sm]),
  .store_backing_req_valid(write_req_valid[sm]),.store_backing_req_ready(write_req_ready[sm]),.store_backing_req_id(write_req_id[sm]),.store_backing_req_byte_address(write_req_byte_address[sm]),.store_backing_req_data(write_req_data[sm]),.store_backing_req_word_mask(write_req_word_mask[sm]),
  .store_backing_rsp_valid(write_rsp_valid[sm]),.store_backing_rsp_ready(write_rsp_ready[sm]),.store_backing_rsp_id(write_rsp_id[sm]),.resident_blocks(sm_resident_blocks[sm]),.resident_warps(sm_resident_warps[sm]),
  .native_issue_valid(sm_native_issue_valid[sm]),.native_issue_context(sm_native_context[sm]),.native_issue_warp(sm_native_warp[sm]),.native_issue_pc(sm_native_pc[sm])
 );
 end
 logic[SMS-1:0] slice_read_req_ready[SLICES];
 logic[SMS-1:0] slice_read_rsp_valid[SLICES];
 logic[SMS-1:0] slice_write_req_ready[SLICES];
 logic[SMS-1:0] slice_write_rsp_valid[SLICES];
 int held_read_slice[SMS],held_write_slice[SMS],chosen_read_slice[SMS],chosen_write_slice[SMS];
 logic[SMS-1:0] slice_read_rsp_ready[SLICES],slice_write_rsp_ready[SLICES];
 logic[31:0]slice_read_rsp_id[SLICES][SMS],slice_write_rsp_id[SLICES][SMS];logic[255:0]slice_read_rsp_data[SLICES][SMS];
 int slice_l2_read_requests[SLICES];
 int slice_l2_read_hits[SLICES];
 int slice_l2_read_misses[SLICES];
 int slice_l2_merged_misses[SLICES];
 int slice_l2_actual_fills[SLICES];
 int slice_live_owners[SLICES];
 int slice_live_mshrs[SLICES];
 int slice_peak_owners[SLICES];
 int slice_peak_mshrs[SLICES];
 always_comb begin
  for(int sl=0;sl<SLICES;sl++)begin slice_read_rsp_ready[sl]=0;slice_write_rsp_ready[sl]=0;end
  l2_read_requests=0;for(int sl=0;sl<SLICES;sl++)l2_read_requests+=slice_l2_read_requests[sl];
  l2_read_hits=0;for(int sl=0;sl<SLICES;sl++)l2_read_hits+=slice_l2_read_hits[sl];
  l2_read_misses=0;for(int sl=0;sl<SLICES;sl++)l2_read_misses+=slice_l2_read_misses[sl];
  l2_merged_misses=0;for(int sl=0;sl<SLICES;sl++)l2_merged_misses+=slice_l2_merged_misses[sl];
  l2_actual_fills=0;for(int sl=0;sl<SLICES;sl++)l2_actual_fills+=slice_l2_actual_fills[sl];
  live_owners=0;for(int sl=0;sl<SLICES;sl++)live_owners+=slice_live_owners[sl];
  live_mshrs=0;for(int sl=0;sl<SLICES;sl++)live_mshrs+=slice_live_mshrs[sl];
  peak_owners=0;for(int sl=0;sl<SLICES;sl++)peak_owners+=slice_peak_owners[sl];
  peak_mshrs=0;for(int sl=0;sl<SLICES;sl++)peak_mshrs+=slice_peak_mshrs[sl];
  for(int sm=0;sm<SMS;sm++)begin
   bit read_chosen,write_chosen;read_chosen=0;write_chosen=0;chosen_read_slice[sm]=-1;chosen_write_slice[sm]=-1;
   read_req_ready[sm]=0;for(int sl=0;sl<SLICES;sl++)read_req_ready[sm]|=slice_read_req_ready[sl][sm];
   read_rsp_valid[sm]=0;for(int sl=0;sl<SLICES;sl++)read_rsp_valid[sm]|=slice_read_rsp_valid[sl][sm];
   write_req_ready[sm]=0;for(int sl=0;sl<SLICES;sl++)write_req_ready[sm]|=slice_write_req_ready[sl][sm];
   write_rsp_valid[sm]=0;for(int sl=0;sl<SLICES;sl++)write_rsp_valid[sm]|=slice_write_rsp_valid[sl][sm];
   read_rsp_id[sm]=0;read_rsp_data[sm]=0;write_rsp_id[sm]=0;
   for(int sl=0;sl<SLICES;sl++)begin
    if(slice_read_rsp_valid[sl][sm]&&!read_chosen&&(held_read_slice[sm]<0||held_read_slice[sm]==sl))begin chosen_read_slice[sm]=sl;read_chosen=1;slice_read_rsp_ready[sl][sm]=read_rsp_ready[sm]; read_rsp_id[sm]=slice_read_rsp_id[sl][sm];read_rsp_data[sm]=0;end
    if(slice_write_rsp_valid[sl][sm]&&!write_chosen&&(held_write_slice[sm]<0||held_write_slice[sm]==sl))begin chosen_write_slice[sm]=sl;write_chosen=1;slice_write_rsp_ready[sl][sm]=write_rsp_ready[sm];write_rsp_id[sm]=slice_write_rsp_id[sl][sm];end
   end
  end
 end
 always_ff @(posedge clk)begin
  for(int sm=0;sm<SMS;sm++)begin
   if(rst)begin held_read_slice[sm]<=-1;held_write_slice[sm]<=-1;end
   else begin
    if(read_rsp_valid[sm])held_read_slice[sm]<=read_rsp_ready[sm]?-1:chosen_read_slice[sm];
    if(write_rsp_valid[sm])held_write_slice[sm]<=write_rsp_ready[sm]?-1:chosen_write_slice[sm];
   end
  end
 end
 logic[SMS-1:0] permitted_read,permitted_write;
 longint read_credit,write_credit,mixed_credit;
 int service_cursor;
 always_comb begin
  longint r,w,t;r=read_credit+cache_read_rate_q10;w=write_credit+cache_write_rate_q10;t=mixed_credit+cache_mixed_rate_q10;
  permitted_read=0;permitted_write=0;
  for(int off=0;off<SMS;off++)begin
   int sm;sm=(service_cursor+off)%SMS;
   if(read_req_valid[sm]&&r>=1024&&t>=1024)begin permitted_read[sm]=1;r-=1024;t-=1024;end
   if(write_req_valid[sm]&&w>=1024&&t>=1024)begin permitted_write[sm]=1;w-=1024;t-=1024;end
  end
 end
 always_ff @(posedge clk)begin
  if(rst)begin read_credit<=0;write_credit<=0;mixed_credit<=0;service_cursor<=0;end
  else begin
   longint r,w,t;r=read_credit+cache_read_rate_q10;w=write_credit+cache_write_rate_q10;t=mixed_credit+cache_mixed_rate_q10;
   for(int sm=0;sm<SMS;sm++)begin
    if(read_req_valid[sm]&&read_req_ready[sm])begin r-=1024;t-=1024;end
    if(write_req_valid[sm]&&write_req_ready[sm])begin w-=1024;t-=1024;end
   end
   read_credit<=r<cache_read_rate_q10?r:cache_read_rate_q10;
   write_credit<=w<cache_write_rate_q10?w:cache_write_rate_q10;
   mixed_credit<=t<cache_mixed_rate_q10?t:cache_mixed_rate_q10;
   service_cursor<=(service_cursor+1)%SMS;
  end
 end
 for(genvar sl=0;sl<SLICES;sl++)begin:cache_slices
 logic[SMS-1:0] routed_read,routed_write;
 always_comb for(int sm=0;sm<SMS;sm++)begin
 routed_read[sm]=read_req_valid[sm]&&permitted_read[sm]&&((read_req_byte_address[sm]>>7)%SLICES==sl);
 routed_write[sm]=write_req_valid[sm]&&permitted_write[sm]&&((write_req_byte_address[sm]>>7)%SLICES==sl);
 end
 large_slice_l2_a gateway(
 .clk,.rst,.hit_delay_cycles(l2_hit_delay_cycles),
.l2_read_requests(slice_l2_read_requests[sl]),
 .l2_read_hits(slice_l2_read_hits[sl]),
 .l2_read_misses(slice_l2_read_misses[sl]),
 .l2_merged_misses(slice_l2_merged_misses[sl]),
 .l2_actual_fills(slice_l2_actual_fills[sl]),
 .live_owners(slice_live_owners[sl]),
 .live_mshrs(slice_live_mshrs[sl]),
 .peak_owners(slice_peak_owners[sl]),
 .peak_mshrs(slice_peak_mshrs[sl]),
 .read_req_valid(routed_read),
 .read_req_ready(slice_read_req_ready[sl]),
 .read_rsp_valid(slice_read_rsp_valid[sl]),
 .read_rsp_ready(slice_read_rsp_ready[sl]),
 .write_req_valid(routed_write),
 .write_req_ready(slice_write_req_ready[sl]),
 .write_rsp_valid(slice_write_rsp_valid[sl]),
 .write_rsp_ready(slice_write_rsp_ready[sl]),
 .read_rsp_id(slice_read_rsp_id[sl]),

 .write_rsp_id(slice_write_rsp_id[sl]),
 .read_req_id,
 .read_req_byte_address,
 .write_req_id,
 .write_req_byte_address,

 .write_req_word_mask,
 .backing_req_valid(backing_req_valid[sl]),
 .backing_req_ready(backing_req_ready[sl]),
 .backing_req_id(backing_req_id[sl]),
 .backing_req_byte_address(backing_req_byte_address[sl]),
 .backing_rsp_valid(backing_rsp_valid[sl]),
 .backing_rsp_ready(backing_rsp_ready[sl]),
 .backing_rsp_id(backing_rsp_id[sl]),

 .store_backing_req_valid(store_backing_req_valid[sl]),
 .store_backing_req_ready(store_backing_req_ready[sl]),
 .store_backing_req_id(store_backing_req_id[sl]),
 .store_backing_req_byte_address(store_backing_req_byte_address[sl]),

 .store_backing_req_word_mask(store_backing_req_word_mask[sl]),
 .store_backing_rsp_valid(store_backing_rsp_valid[sl]),
 .store_backing_rsp_ready(store_backing_rsp_ready[sl]),
 .store_backing_rsp_id(store_backing_rsp_id[sl]));
 end
 // elapsed_cycles counts every edge after accepted launch through the edge
 // registering COMPLETE (including the final retirement and drain-check edge).
 // It freezes while COMPLETE is held; no hardware-frequency conversion implied.
 // Completion means all child stores acknowledged, every block retired, and
 // resident reservations zero. Providers must cancel stale returns on reset.
endmodule
