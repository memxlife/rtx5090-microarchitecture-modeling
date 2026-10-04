// One shared read-only sector cache before the serialized memory gateway.
// Default64sets*8ways*128B=64KiB data (four32B sectors per line),
// test geometry not RTX5090 L2 geometry.
// Writes bypass cache; A/B immutable until reset and C disjoint from cached inputs.
module multi_sm_l2_gateway #(parameter int SMS=2,L2_SETS=64,L2_WAYS=8)(
 input logic clk,rst,
 input logic[SMS-1:0]read_req_valid,output logic[SMS-1:0]read_req_ready,
 input logic[31:0]read_req_id[SMS],read_req_byte_address[SMS],
 output logic[SMS-1:0]read_rsp_valid,input logic[SMS-1:0]read_rsp_ready,
 output logic[31:0]read_rsp_id[SMS],output logic[255:0]read_rsp_data[SMS],
 input logic[SMS-1:0]write_req_valid,output logic[SMS-1:0]write_req_ready,
 input logic[31:0]write_req_id[SMS],write_req_byte_address[SMS],
 input logic[255:0]write_req_data[SMS],input logic[7:0]write_req_word_mask[SMS],
 output logic[SMS-1:0]write_rsp_valid,input logic[SMS-1:0]write_rsp_ready,
 output logic[31:0]write_rsp_id[SMS],
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data,
 output logic store_backing_req_valid,input logic store_backing_req_ready,
 output logic[31:0]store_backing_req_id,store_backing_req_byte_address,
 output logic[255:0]store_backing_req_data,output logic[7:0]store_backing_req_word_mask,
 input logic store_backing_rsp_valid,output logic store_backing_rsp_ready,input logic[31:0]store_backing_rsp_id,
 output int l2_read_requests,l2_read_hits,l2_read_misses
);
 logic cache_req_valid,cache_req_ready,cache_rsp_valid,cache_rsp_ready,cache_rsp_hit;
 logic[31:0]cache_req_id,cache_req_address,cache_rsp_id,cache_rsp_word;
 logic[255:0]cache_rsp_packet;
 logic read_pending;
 multi_sm_sector_gateway #(.SMS(SMS)) ownership(
  .clk,.rst,.read_req_valid,.read_req_ready,.read_req_id,.read_req_byte_address,.read_rsp_valid,.read_rsp_ready,.read_rsp_id,.read_rsp_data,
  .write_req_valid,.write_req_ready,.write_req_id,.write_req_byte_address,.write_req_data,.write_req_word_mask,.write_rsp_valid,.write_rsp_ready,.write_rsp_id,
  .backing_req_valid(cache_req_valid),.backing_req_ready(cache_req_ready),.backing_req_id(cache_req_id),.backing_req_byte_address(cache_req_address),
  .backing_rsp_valid(cache_rsp_valid),.backing_rsp_ready(cache_rsp_ready),.backing_rsp_id(cache_rsp_id),.backing_rsp_data(cache_rsp_packet),
  .store_backing_req_valid,.store_backing_req_ready,.store_backing_req_id,.store_backing_req_byte_address,.store_backing_req_data,.store_backing_req_word_mask,
  .store_backing_rsp_valid,.store_backing_rsp_ready,.store_backing_rsp_id
 );
 sector_read_cache #(.SETS(L2_SETS),.WAYS(L2_WAYS)) l2(
  .clk,.rst,.req_valid(cache_req_valid),.req_ready(cache_req_ready),.req_id(cache_req_id),.req_byte_address(cache_req_address),
  .rsp_valid(cache_rsp_valid),.rsp_ready(cache_rsp_ready),.rsp_id(cache_rsp_id),.rsp_data(cache_rsp_word),.rsp_sector_data(cache_rsp_packet),.rsp_hit(cache_rsp_hit),
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,.backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data
 );
 always_ff @(posedge clk)begin
  if(rst)begin l2_read_requests<=0;l2_read_hits<=0;l2_read_misses<=0;read_pending<=0;end
  else begin
   if(cache_req_valid&&cache_req_ready)begin
    if(read_pending)$fatal(1,"L2 accepted overlapping logical read");
    read_pending<=1;l2_read_requests<=l2_read_requests+1;
   end
   if(cache_rsp_valid&&cache_rsp_ready)begin
    if(!read_pending)$fatal(1,"L2 return has no accepted logical read");
    read_pending<=0;
    if(cache_rsp_hit)l2_read_hits<=l2_read_hits+1;else l2_read_misses<=l2_read_misses+1;
   end
   if(l2_read_requests!=l2_read_hits+l2_read_misses+int'(read_pending))$fatal(1,"L2 logical read count conservation failed");
  end
 end
 // A miss is counted once at returned logical completion, never again at its
 // backing request. Held responses cannot double-count. Reset flushes both layers.
 // No write invalidation, dirty lines, cross-SM coherence or multiple MSHRs.
endmodule
