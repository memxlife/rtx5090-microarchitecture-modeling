// Functional 32-byte-sector coalescing of up to32 active aligned u16 loads.
// Unique sectors are serviced serially through a blocking cache hypothesis.
// This does not identify GPU request issue rate, arbitration, or L2 geometry.
module coalesced_u16_warp_load #(parameter int SETS=64,WAYS=8)(
 input logic clk,rst,req_valid,output logic req_ready,input logic[31:0]req_id,
 input logic[31:0]byte_addresses[32],input logic[31:0]active_mask,
 output logic rsp_valid,input logic rsp_ready,output logic[31:0]rsp_id,
 output logic[15:0]halfwords[32],output int sector_count,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data
);
 typedef enum logic[1:0]{IDLE,SEND,WAIT_PACKET,RESPONSE}state_t;
 state_t state;
 logic[31:0]saved_id,saved_addresses[32],saved_mask,sector_list[32],candidate_sectors[32];
 int candidate_count,current_sector;logic addresses_legal;logic lane_found[32];
 logic cache_req_valid,cache_req_ready,cache_rsp_valid,cache_rsp_ready,cache_rsp_hit;
 logic[31:0]cache_id,cache_rsp_id,cache_rsp_word;logic[255:0]cache_packet;
 always_comb begin
  candidate_count=0;addresses_legal=1;
  for(int i=0;i<32;i++)begin candidate_sectors[i]=0;lane_found[i]=0;end
  for(int lane=0;lane<32;lane++)if(active_mask[lane])begin
   if(byte_addresses[lane][0])addresses_legal=0;
   for(int i=0;i<32;i++)if(i<candidate_count&&candidate_sectors[i]=={byte_addresses[lane][31:5],5'b0})lane_found[lane]=1;
   if(!lane_found[lane])begin candidate_sectors[candidate_count]={byte_addresses[lane][31:5],5'b0};candidate_count=candidate_count+1;end
  end
 end
 assign req_ready=!rst&&state==IDLE&&addresses_legal;
 assign rsp_valid=!rst&&state==RESPONSE;assign rsp_id=saved_id;
 assign cache_req_valid=!rst&&state==SEND;
 assign cache_rsp_ready=!rst&&state==WAIT_PACKET;
 // XOR with0..31 is injective for this single inflight warp; external ID is retained.
 assign cache_id=saved_id^32'(current_sector);
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;saved_id<=0;saved_mask<=0;sector_count<=0;current_sector<=0;
   for(int lane=0;lane<32;lane++)begin saved_addresses[lane]<=0;halfwords[lane]<=0;sector_list[lane]<=0;end
  end else begin
   if(req_valid&&state==IDLE&&!addresses_legal)$fatal(1,"Unaligned active u16 lane address");
   case(state)
    IDLE:if(req_valid&&req_ready)begin
     saved_id<=req_id;saved_mask<=active_mask;sector_count<=candidate_count;current_sector<=0;
     for(int lane=0;lane<32;lane++)begin
      saved_addresses[lane]<=byte_addresses[lane];sector_list[lane]<=candidate_sectors[lane];halfwords[lane]<=0;
     end
     if(candidate_count==0)state<=RESPONSE;else state<=SEND;
    end
    SEND:if(cache_req_valid&&cache_req_ready)state<=WAIT_PACKET;
    WAIT_PACKET:if(cache_rsp_valid&&cache_rsp_ready)begin
     if(cache_rsp_id!=cache_id)$fatal(1,"Warp sector completion identity mismatch");
     for(int lane=0;lane<32;lane++)if(saved_mask[lane]&&
       {saved_addresses[lane][31:5],5'b0}==sector_list[current_sector])
      halfwords[lane]<=cache_packet[int'(saved_addresses[lane][4:0])*8+:16];
     if(current_sector==sector_count-1)state<=RESPONSE;
     else begin current_sector<=current_sector+1;state<=SEND;end
    end
    RESPONSE:if(rsp_valid&&rsp_ready)state<=IDLE;
    default:$fatal(1,"Invalid coalesced warp state");
   endcase
  end
 end
 sector_read_cache #(.SETS(SETS),.WAYS(WAYS)) cache(
  .clk,.rst,.req_valid(cache_req_valid),.req_ready(cache_req_ready),.req_id(cache_id),
  .req_byte_address(sector_list[current_sector]),.rsp_valid(cache_rsp_valid),.rsp_ready(cache_rsp_ready),
  .rsp_id(cache_rsp_id),.rsp_data(cache_rsp_word),.rsp_sector_data(cache_packet),.rsp_hit(cache_rsp_hit),
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,
  .backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data
 );
 // Empty masks return32zeros without cache traffic. Inactive addresses ignored.
 // Inputs snapshot at acceptance. Providers flush pre-reset traffic; IDs have no epoch.
 // Across requests the cache assumes backing data remains immutable or is reset.
endmodule
