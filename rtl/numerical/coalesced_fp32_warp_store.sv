// Functional grouping of up to32 independent aligned32-bit lane stores.
// Duplicate active addresses are forbidden by this simulator no-race policy.
// Serial sector service and one outstanding acknowledgement are model choices.
module coalesced_fp32_warp_store(
 input logic clk,rst,req_valid,output logic req_ready,input logic[31:0]req_id,
 input logic[31:0]byte_addresses[32],words[32],input logic[31:0]active_mask,
 output logic rsp_valid,input logic rsp_ready,output logic[31:0]rsp_id,
 output int sector_count,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 output logic[255:0]backing_req_data,output logic[7:0]backing_req_word_mask,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic[31:0]backing_rsp_id
);
 typedef enum logic[1:0]{IDLE,SEND,WAIT_ACK,RESPONSE}state_t;
 state_t state;
 logic[31:0]saved_id,sector_addresses[32],candidate_addresses[32];
 logic[255:0]sector_data[32],candidate_data[32];
 logic[7:0]sector_masks[32],candidate_masks[32];
 int candidate_count,current_sector,chosen_index[32];logic legal,duplicates;
 always_comb begin
  candidate_count=0;legal=1;duplicates=0;
  for(int i=0;i<32;i++)begin
   candidate_addresses[i]=0;candidate_data[i]=0;candidate_masks[i]=0;chosen_index[i]=-1;
  end
  for(int lane=0;lane<32;lane++)if(active_mask[lane])begin
   if(byte_addresses[lane][1:0]!=0)legal=0;
   for(int earlier=0;earlier<32;earlier++)if(earlier<lane&&active_mask[earlier]&&byte_addresses[earlier]==byte_addresses[lane])duplicates=1;
   for(int i=0;i<32;i++)if(i<candidate_count&&candidate_addresses[i]=={byte_addresses[lane][31:5],5'b0})chosen_index[lane]=i;
   if(chosen_index[lane]<0)begin
    chosen_index[lane]=candidate_count;candidate_addresses[candidate_count]={byte_addresses[lane][31:5],5'b0};candidate_count=candidate_count+1;
   end
   candidate_masks[chosen_index[lane]][byte_addresses[lane][4:2]]=1;
   candidate_data[chosen_index[lane]][int'(byte_addresses[lane][4:2])*32+:32]=words[lane];
  end
 end
 assign req_ready=!rst&&state==IDLE&&legal&&!duplicates;
 assign rsp_valid=!rst&&state==RESPONSE;assign rsp_id=saved_id;
 assign backing_req_valid=!rst&&state==SEND;
 assign backing_req_id=saved_id^32'(current_sector);
 assign backing_req_byte_address=sector_addresses[current_sector];
 assign backing_req_data=sector_data[current_sector];
 assign backing_req_word_mask=sector_masks[current_sector];
 assign backing_rsp_ready=!rst&&state==WAIT_ACK;
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;saved_id<=0;sector_count<=0;current_sector<=0;
   for(int i=0;i<32;i++)begin sector_addresses[i]<=0;sector_data[i]<=0;sector_masks[i]<=0;end
  end else begin
   if(req_valid&&state==IDLE&&!legal)$fatal(1,"Unaligned active FP32 store address");
   if(req_valid&&state==IDLE&&duplicates)$fatal(1,"Duplicate active FP32 store address");
   case(state)
    IDLE:if(req_valid&&req_ready)begin
     saved_id<=req_id;sector_count<=candidate_count;current_sector<=0;
     for(int i=0;i<32;i++)begin sector_addresses[i]<=candidate_addresses[i];sector_data[i]<=candidate_data[i];sector_masks[i]<=candidate_masks[i];end
     if(candidate_count==0)state<=RESPONSE;else state<=SEND;
    end
    SEND:if(backing_req_valid&&backing_req_ready)state<=WAIT_ACK;
    WAIT_ACK:if(backing_rsp_valid&&backing_rsp_ready)begin
     if(backing_rsp_id!=backing_req_id)$fatal(1,"Warp store acknowledgement identity mismatch");
     if(current_sector==sector_count-1)state<=RESPONSE;
     else begin current_sector<=current_sector+1;state<=SEND;end
    end
    RESPONSE:if(rsp_valid&&rsp_ready)state<=IDLE;
    default:$fatal(1,"Invalid coalesced store state");
   endcase
  end
 end
 // Empty masks acknowledge with no backing traffic. Inactive addresses ignored.
 // Full payloads snapshot at admission and remain stable under backpressure.
 // Providers must flush pre-reset writes/acks; IDs have no reset generation.
endmodule
