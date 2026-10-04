// Blocking numerical sector cache. Physical geometry:128B line,4x32B sectors.
// SETS/WAYS/replacement and single pending slot are explicit model choices.
module sector_read_cache #(parameter int SETS=2,WAYS=2)(
 input logic clk,rst,req_valid,output logic req_ready,
 input logic [31:0] req_id,req_byte_address,
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,rsp_data,output logic [255:0] rsp_sector_data,output logic rsp_hit,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic [31:0] backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic [31:0] backing_rsp_id,input logic [255:0] backing_rsp_data
);
 typedef enum logic [1:0]{IDLE,SEND,WAIT_RETURN,RESPONSE} state_t;
 state_t state;
 logic line_valid[SETS][WAYS];logic [31:0] tags[SETS][WAYS];
 logic [3:0] sector_valid[SETS][WAYS];logic [255:0] sectors[SETS][WAYS][4];
 int next_victim[SETS],pending_set,pending_way,pending_sector,pending_word;
 logic pending_newline;logic [31:0] pending_tag,pending_id,pending_address;
 logic [31:0] result_data;logic [255:0] result_sector_data;logic result_hit;
 int selected_set,selected_sector,selected_word,selected_way;
 logic [31:0] selected_tag;logic tag_found,selected_hit;
 initial if(SETS<1||WAYS<1||(SETS&(SETS-1))!=0) $fatal(1,"Invalid sector cache geometry");
 always_comb begin
  selected_set=int'((req_byte_address>>7)%SETS);
  selected_tag=req_byte_address>>(7+$clog2(SETS));
  selected_sector=int'((req_byte_address>>5)&3);
  selected_word=int'((req_byte_address>>2)&7);
  selected_way=next_victim[selected_set];tag_found=0;selected_hit=0;
  // A matching line owns all four sectors even when the requested sector is absent.
  for(int w=0;w<WAYS;w++)if(line_valid[selected_set][w]&&tags[selected_set][w]==selected_tag)begin
   selected_way=w;tag_found=1;selected_hit=sector_valid[selected_set][w][selected_sector];
  end
  if(!tag_found)for(int w=WAYS-1;w>=0;w--)if(!line_valid[selected_set][w])selected_way=w;
 end
 assign req_ready=!rst&&state==IDLE;
 assign rsp_valid=!rst&&state==RESPONSE;
 assign rsp_id=pending_id;assign rsp_data=result_data;assign rsp_sector_data=result_sector_data;assign rsp_hit=result_hit;
 assign backing_req_valid=!rst&&state==SEND;
 assign backing_req_id=pending_id;assign backing_req_byte_address=pending_address;
 assign backing_rsp_ready=!rst&&state==WAIT_RETURN;
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;pending_id<=0;pending_address<=0;result_data<=0;result_sector_data<=0;result_hit<=0;
   pending_set<=0;pending_way<=0;pending_sector<=0;pending_word<=0;pending_tag<=0;pending_newline<=0;
   for(int s=0;s<SETS;s++)begin next_victim[s]<=0;for(int w=0;w<WAYS;w++)begin
    line_valid[s][w]<=0;tags[s][w]<=0;sector_valid[s][w]<=0;
   end end
  end else case(state)
   IDLE:if(req_valid&&req_ready)begin
    if(req_byte_address[1:0]!=0)$fatal(1,"Unaligned cache word request");
    pending_id<=req_id;pending_address<={req_byte_address[31:5],5'b0};
    pending_set<=selected_set;pending_way<=selected_way;pending_sector<=selected_sector;pending_word<=selected_word;
    pending_tag<=selected_tag;pending_newline<=!tag_found;result_hit<=selected_hit;
    if(selected_hit)begin result_sector_data<=sectors[selected_set][selected_way][selected_sector];result_data<=sectors[selected_set][selected_way][selected_sector][selected_word*32+:32];state<=RESPONSE;end
    else state<=SEND;
   end
   SEND:if(backing_req_valid&&backing_req_ready)state<=WAIT_RETURN;
   WAIT_RETURN:if(backing_rsp_valid&&backing_rsp_ready)begin
    if(backing_rsp_id!=pending_id)$fatal(1,"Cache backing completion identity mismatch");
    if(pending_newline)begin
     line_valid[pending_set][pending_way]<=1;tags[pending_set][pending_way]<=pending_tag;
     sector_valid[pending_set][pending_way]<=4'(1<<pending_sector);
     next_victim[pending_set]<=(pending_way+1)%WAYS;
    end else sector_valid[pending_set][pending_way][pending_sector]<=1;
    sectors[pending_set][pending_way][pending_sector]<=backing_rsp_data;
    result_sector_data<=backing_rsp_data;result_data<=backing_rsp_data[pending_word*32+:32];state<=RESPONSE;
   end
   RESPONSE:if(rsp_valid&&rsp_ready)state<=IDLE;
   default:$fatal(1,"Invalid cache state");
  endcase
 end
 // No result becomes valid before actual backing completion. No duplicate miss
 // service is charged here; the connected backing component owns its timing.
endmodule
