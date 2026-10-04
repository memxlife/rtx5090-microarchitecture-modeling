// Fixed BM32/BN32/BK32 operand frames. Global row-major u16 values reach
// context-local shared memory only through actual cache returns and vector commits.
// RR requests, blocking cache and serial per-context groups are hypotheses.
module resident_operand_staging #(
 parameter int CONTEXTS=2,M=64,N=96,K=64,SETS=64,WAYS=8
)(
 input logic clk,rst,req_valid,output logic req_ready,
 input logic[31:0]req_context,req_id,a_base,b_base,cta_row,cta_col,stage_index,
 output logic[CONTEXTS-1:0]context_ready,output int outstanding,
 output logic write_warp_valid,input logic write_warp_ready,
 output logic[31:0]write_context,write_warp_byte_addresses[32],write_warp_mask,
 output logic[15:0]write_warp_halfwords[32],
 output logic done_valid,input logic done_ready,output logic[31:0]done_context,done_id,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data
);
 localparam int LOCAL_BITS=$clog2(CONTEXTS*64),EPOCH_BITS=32-LOCAL_BITS;
 typedef enum logic[1:0]{IDLE,SEND,WAIT_VALUES,DONE}state_t;
 state_t state[CONTEXTS];
 logic[EPOCH_BITS-1:0]epoch[CONTEXTS];
 logic[31:0]ids[CONTEXTS],abase[CONTEXTS],bbase[CONTEXTS],rows[CONTEXTS],cols[CONTEXTS],stages[CONTEXTS];
 int group_index[CONTEXTS],request_owner,request_cursor,done_owner,done_cursor;
 logic request_legal;
 logic load_req_valid,load_req_ready,load_rsp_valid,load_rsp_ready;
 logic[31:0]load_req_context,load_req_id,load_addresses[32],load_rsp_context,load_rsp_id;
 logic[15:0]load_halfwords[32];logic[CONTEXTS-1:0]load_context_ready;
 int load_outstanding,load_sector_count;
 function automatic logic[31:0]tag(input int ctx);
  return (32'(epoch[ctx])<<LOCAL_BITS)|32'(ctx*64+group_index[ctx]);
 endfunction
 function automatic logic[31:0]global_address(input int ctx,lane);
  longint unsigned h,r,c,index_value;
  h=64'(group_index[ctx]*32+lane);
  if(h<1024)begin
   r=64'(rows[ctx])*32+h/32;c=64'(stages[ctx])*32+h%32;
   index_value=64'(abase[ctx])+2*(r*64'(K)+c);
  end else begin
   h-=1024;r=64'(stages[ctx])*32+h/32;c=64'(cols[ctx])*32+h%32;
   index_value=64'(bbase[ctx])+2*(r*64'(N)+c);
  end
  return 32'(index_value);
 endfunction
 initial if(CONTEXTS<1||EPOCH_BITS<1||M<32||N<32||K<32||M%32||N%32||K%32)$fatal(1,"Only complete BM32/BN32/BK32 frames supported");
 always_comb begin
  request_legal=req_context<CONTEXTS&&cta_row<M/32&&cta_col<N/32&&stage_index<K/32&&!a_base[0]&&!b_base[0];
  if(64'(a_base)+2*64'(M)*64'(K)>64'h100000000||64'(b_base)+2*64'(K)*64'(N)>64'h100000000)request_legal=0;
  outstanding=0;
  for(int ctx=0;ctx<CONTEXTS;ctx++)begin
   context_ready[ctx]=!rst&&state[ctx]==IDLE;
   if(state[ctx]!=IDLE)outstanding++;
  end
 end
 assign req_ready=!rst&&request_legal&&(req_context<CONTEXTS?context_ready[req_context]:0);
 assign load_req_valid=!rst&&request_owner>=0;
 assign load_req_context=request_owner>=0?32'(request_owner):0;
 assign load_req_id=request_owner>=0?tag(request_owner):0;
 always_comb for(int lane=0;lane<32;lane++)load_addresses[lane]=request_owner>=0?global_address(request_owner,lane):0;
 // A loader response stays held until the external shared-vector writer accepts.
 assign write_warp_valid=!rst&&load_rsp_valid;
 assign load_rsp_ready=!rst&&write_warp_ready;
 assign write_context=load_rsp_context;
 assign write_warp_mask='1;
 always_comb begin
  for(int lane=0;lane<32;lane++)begin
   write_warp_halfwords[lane]=load_halfwords[lane];
   write_warp_byte_addresses[lane]=load_rsp_context<CONTEXTS?32'(2*(group_index[load_rsp_context]*32+lane)):0;
  end
 end
 assign done_valid=!rst&&done_owner>=0;
 assign done_context=done_owner>=0?32'(done_owner):0;
 assign done_id=done_owner>=0?ids[done_owner]:0;
 always_ff @(posedge clk)begin
  if(rst)begin
   request_owner<=-1;request_cursor<=0;done_owner<=-1;done_cursor<=0;
   for(int ctx=0;ctx<CONTEXTS;ctx++)begin
    state[ctx]<=IDLE;epoch[ctx]<=0;ids[ctx]<=0;abase[ctx]<=0;bbase[ctx]<=0;rows[ctx]<=0;cols[ctx]<=0;stages[ctx]<=0;group_index[ctx]<=0;
   end
  end else begin
   if(req_valid&&!request_legal)$fatal(1,"Invalid resident operand frame");
   if(req_valid&&req_ready)begin
    if(&epoch[req_context])$fatal(1,"Staging epoch exhausted; reset required");
    epoch[req_context]<=epoch[req_context]+1;ids[req_context]<=req_id;
    abase[req_context]<=a_base;bbase[req_context]<=b_base;rows[req_context]<=cta_row;cols[req_context]<=cta_col;stages[req_context]<=stage_index;
    group_index[req_context]<=0;state[req_context]<=SEND;
   end
   if(request_owner<0)begin
    int choice;choice=-1;
    for(int offset=0;offset<CONTEXTS;offset++)begin
     int candidate;candidate=(request_cursor+offset)%CONTEXTS;
     if(choice<0&&state[candidate]==SEND&&load_context_ready[candidate])choice=candidate;
    end
    if(choice>=0)request_owner<=choice;
   end else if(load_req_valid&&load_req_ready)begin
    state[request_owner]<=WAIT_VALUES;request_cursor<=(request_owner+1)%CONTEXTS;request_owner<=-1;
   end
   if(load_rsp_valid)begin
    if(load_rsp_context>=CONTEXTS)$fatal(1,"Staging return context outside capacity");
    else if(state[load_rsp_context]!=WAIT_VALUES||load_rsp_id!=tag(int'(load_rsp_context)))$fatal(1,"Staging return without matching frame/group");
   end
   if(load_rsp_valid&&load_rsp_ready)begin
    if(group_index[load_rsp_context]==63)state[load_rsp_context]<=DONE;
    else begin group_index[load_rsp_context]<=group_index[load_rsp_context]+1;state[load_rsp_context]<=SEND;end
   end
   if(done_owner<0)begin
    int choice;choice=-1;
    for(int offset=0;offset<CONTEXTS;offset++)begin
     int candidate;candidate=(done_cursor+offset)%CONTEXTS;
     if(choice<0&&state[candidate]==DONE)choice=candidate;
    end
    if(choice>=0)done_owner<=choice;
   end else if(done_valid&&done_ready)begin
    state[done_owner]<=IDLE;done_cursor<=(done_owner+1)%CONTEXTS;done_owner<=-1;
   end
  end
 end
 resident_u16_warp_load #(.CONTEXTS(CONTEXTS),.SETS(SETS),.WAYS(WAYS)) loader(
  .clk,.rst,.req_valid(load_req_valid),.req_ready(load_req_ready),.req_context(load_req_context),.req_id(load_req_id),
  .byte_addresses(load_addresses),.active_mask(32'hffffffff),.context_ready(load_context_ready),.outstanding(load_outstanding),
  .rsp_valid(load_rsp_valid),.rsp_ready(load_rsp_ready),.rsp_context(load_rsp_context),.rsp_id(load_rsp_id),.halfwords(load_halfwords),.sector_count(load_sector_count),
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,.backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data
 );
 // Exactly64 accepted32-halfword commits per frame. Provider flushes reset-era
 // transactions; immutable backing data/cache-reset contract inherited from loader.
endmodule
