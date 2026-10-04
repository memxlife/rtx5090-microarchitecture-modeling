// Extracted executable baseline; physical GPU parameters remain provisional.
module read_cache #(parameter int SETS=16,WAYS=2,HIT_DELAY=1,MISS_DELAY=1)(
 input logic clk,rst,req_valid,output logic req_ready,input logic [31:0] byte_address,
 output logic rsp_valid,input logic rsp_ready,output logic hit,output logic [31:0] response_address);
 int tags[SETS][WAYS],age[SETS][WAYS],cycle,remaining,set_id,tag,found,victim;
 logic valid[SETS][WAYS],occupied;
 assign req_ready=!occupied;assign rsp_valid=occupied&&remaining==0;
 always_comb begin
  set_id=int'((byte_address>>5)%SETS);tag=int'((byte_address>>5)/SETS);found=-1;victim=0;
  for(int a=0;a<WAYS;a++) begin
   if(valid[set_id][a]&&tags[set_id][a]==tag) found=a;
   if(!valid[set_id][a]||age[set_id][a]<age[set_id][victim]) victim=a;
  end
 end
 always_ff @(posedge clk) begin
  if(rst) begin
   cycle<=0;remaining<=0;occupied<=0;hit<=0;response_address<=0;
   for(int s=0;s<SETS;s++) for(int a=0;a<WAYS;a++) begin valid[s][a]<=0;tags[s][a]<=0;age[s][a]<=0;end
  end else begin
   cycle<=cycle+1;
   if(occupied&&remaining>0) remaining<=remaining-1;
   if(rsp_valid&&rsp_ready) occupied<=0;
   if(req_valid&&req_ready) begin
    if(HIT_DELAY<1||MISS_DELAY<1) $fatal(1,"Invalid cache delay");
    occupied<=1;hit<=found>=0;response_address<=byte_address;
    if(found>=0) begin remaining<=HIT_DELAY-1;age[set_id][found]<=cycle;end
    else begin remaining<=MISS_DELAY-1;valid[set_id][victim]<=1;tags[set_id][victim]<=tag;age[set_id][victim]<=cycle;end
   end
  end
 end
 // Blocking read-only cache: no request accepted until response retires.
endmodule
