// Independent warp-load contexts share exactly one blocking sector cache.
// RR arbitration and serial sector service are simulation hypotheses.
module large_u16_warp_load #(
 parameter int CONTEXTS=2,SETS=64,WAYS=8
)(
 input logic clk,rst,req_valid,output logic req_ready,
 input logic[31:0]req_context,req_id,byte_addresses[32],active_mask,
 output logic[CONTEXTS-1:0]context_ready,output int outstanding,
 output logic rsp_valid,input logic rsp_ready,
 output logic[31:0]rsp_context,rsp_id,
 output logic[15:0]halfwords[32],output int sector_count,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data
);
 localparam int LOCAL_BITS=$clog2(CONTEXTS*32),EPOCH_BITS=32-LOCAL_BITS;
 typedef enum logic[1:0]{IDLE,SEND,WAIT_PACKET,RESPONSE}state_t;
 state_t state[CONTEXTS];
 logic[EPOCH_BITS-1:0]epoch[CONTEXTS];
 logic[31:0]saved_id[CONTEXTS],saved_addresses[CONTEXTS][32],saved_mask[CONTEXTS],sector_list[CONTEXTS][32],candidate_sectors[32];
 logic[15:0]saved_halfwords[CONTEXTS][32];
 int counts[CONTEXTS],current_sector[CONTEXTS],candidate_count;
 int cache_owner,cache_cursor,response_owner,response_cursor;
 logic addresses_legal,lane_found[32];
 logic cache_req_valid,cache_req_ready,cache_rsp_valid,cache_rsp_ready,cache_rsp_hit;
 logic[31:0]cache_id,cache_address,cache_rsp_id,cache_rsp_word;
 logic[255:0]cache_packet;
 initial if(CONTEXTS<1||EPOCH_BITS<1)$fatal(1,"Invalid resident loader context capacity");
 always_comb begin
  candidate_count=0;addresses_legal=1;
  for(int i=0;i<32;i++)begin candidate_sectors[i]=0;lane_found[i]=0;end
  for(int lane=0;lane<32;lane++)if(active_mask[lane])begin
   if(byte_addresses[lane][0])addresses_legal=0;
   for(int i=0;i<32;i++)if(i<candidate_count&&candidate_sectors[i]=={byte_addresses[lane][31:5],5'b0})lane_found[lane]=1;
   if(!lane_found[lane])begin candidate_sectors[candidate_count]={byte_addresses[lane][31:5],5'b0};candidate_count++;end
  end
 end
 always_comb begin
  outstanding=0;
  for(int ctx=0;ctx<CONTEXTS;ctx++)begin
   context_ready[ctx]=!rst&&state[ctx]==IDLE;
   if(state[ctx]!=IDLE)outstanding++;
  end
 end
 assign req_ready=!rst&&addresses_legal&&(req_context<CONTEXTS?context_ready[req_context]:0);
 assign rsp_valid=!rst&&response_owner>=0;
 assign rsp_context=response_owner>=0?32'(response_owner):0;
 assign rsp_id=response_owner>=0?saved_id[response_owner]:0;
 assign sector_count=response_owner>=0?counts[response_owner]:0;
 always_comb for(int lane=0;lane<32;lane++)halfwords[lane]=response_owner>=0?saved_halfwords[response_owner][lane]:0;
 // Owners latch before valid is asserted. Payload therefore cannot change when
 // another context becomes eligible while the cache/provider is backpressured.
 assign cache_req_valid=!rst&&cache_owner>=0&&(cache_owner>=0?state[cache_owner]==SEND:0);
 assign cache_rsp_ready=!rst;
 assign cache_id=cache_owner>=0?(32'(epoch[cache_owner])<<LOCAL_BITS)|32'(cache_owner*32+current_sector[cache_owner]):0;
 assign cache_address=cache_owner>=0?sector_list[cache_owner][current_sector[cache_owner]]:0;
 always_ff @(posedge clk)begin
  if(rst)begin
   cache_owner<=-1;cache_cursor<=0;response_owner<=-1;response_cursor<=0;
   for(int ctx=0;ctx<CONTEXTS;ctx++)begin
    state[ctx]<=IDLE;epoch[ctx]<=0;saved_id[ctx]<=0;saved_mask[ctx]<=0;counts[ctx]<=0;current_sector[ctx]<=0;
    for(int lane=0;lane<32;lane++)begin saved_addresses[ctx][lane]<=0;saved_halfwords[ctx][lane]<=0;sector_list[ctx][lane]<=0;end
   end
  end else begin
   if(req_valid&&req_context>=CONTEXTS)$fatal(1,"Resident load context out of bounds");
   if(req_valid&&req_context<CONTEXTS&&state[req_context]==IDLE&&!addresses_legal)$fatal(1,"Unaligned active resident u16 address");
   if(req_valid&&req_ready)begin
    if(&epoch[req_context])$fatal(1,"Resident loader epoch exhausted; reset required");
    epoch[req_context]<=epoch[req_context]+1;
    saved_id[req_context]<=req_id;saved_mask[req_context]<=active_mask;
    counts[req_context]<=candidate_count;current_sector[req_context]<=0;
    for(int lane=0;lane<32;lane++)begin
     saved_addresses[req_context][lane]<=byte_addresses[lane];sector_list[req_context][lane]<=candidate_sectors[lane];saved_halfwords[req_context][lane]<=0;
    end
    state[req_context]<=candidate_count==0?RESPONSE:SEND;
   end
   if(cache_owner<0)begin
    int choice;choice=-1;
    for(int offset=0;offset<CONTEXTS;offset++)begin
     int candidate;candidate=(cache_cursor+offset)%CONTEXTS;
     if(choice<0&&state[candidate]==SEND)choice=candidate;
    end
    if(choice>=0)cache_owner<=choice;
   end else begin
    if(cache_req_valid&&cache_req_ready)begin state[cache_owner]<=WAIT_PACKET;cache_cursor<=(cache_owner+1)%CONTEXTS;cache_owner<=-1;end
   end
   if(cache_rsp_valid&&cache_rsp_ready)begin
    int ctx;logic[31:0] expected_id;
    ctx=int'(cache_rsp_id&((32'b1<<LOCAL_BITS)-1))/32;
    if(ctx>=CONTEXTS)$fatal(1,"Unknown global sector completion context");
    else begin
     expected_id=(32'(epoch[ctx])<<LOCAL_BITS)|32'(ctx*32+current_sector[ctx]);
     if(state[ctx]!=WAIT_PACKET||cache_rsp_id!=expected_id)$fatal(1,"Stale or duplicate global sector completion");
     if(current_sector[ctx]==counts[ctx]-1)state[ctx]<=RESPONSE;
     else begin current_sector[ctx]<=current_sector[ctx]+1;state[ctx]<=SEND;end
    end
   end

   if(response_owner<0)begin
    int choice;choice=-1;
    for(int offset=0;offset<CONTEXTS;offset++)begin
     int candidate;candidate=(response_cursor+offset)%CONTEXTS;
     if(choice<0&&state[candidate]==RESPONSE)choice=candidate;
    end
    if(choice>=0)response_owner<=choice;
   end else if(rsp_valid&&rsp_ready)begin
    state[response_owner]<=IDLE;response_cursor<=(response_owner+1)%CONTEXTS;response_owner<=-1;
   end
  end
 end
 // Timing-only cg path: no persistent per-SM input cache. Each load context
 // owns at most one tagged outstanding sector, while other contexts can issue.
 assign cache_req_ready=backing_req_ready;
 assign backing_req_valid=cache_req_valid;
 assign backing_req_id=cache_id;
 assign backing_req_byte_address=cache_address;
 assign cache_rsp_valid=backing_rsp_valid;
 assign cache_rsp_id=backing_rsp_id;
 assign backing_rsp_ready=cache_rsp_ready;
 assign cache_packet=0;
 // Immutable backing storage between requests, or cache reset required. Reset
 // cancels contexts/cache; the external provider must flush pre-reset returns.
 // Empty requests return zeros without traffic; inactive lane addresses ignored.
endmodule
