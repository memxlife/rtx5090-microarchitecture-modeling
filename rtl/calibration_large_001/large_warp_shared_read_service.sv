// Behavioral scalar shared-memory service. One request is one full warp.
// Bank-work rule is measured; capacities and cycle parameters are hypotheses.
// Timing-only: input_words are ignored and output_words are zero; IDs and service timing remain explicit.
module large_warp_shared_read_service #(
 parameter int SLOTS=4,SERVICE_INTERVAL=1,RETURN_DELAY=1
)(
 input logic clk,rst,
 input logic req_valid,output logic req_ready,input logic [31:0] req_id,
 input logic [31:0] byte_addresses[32],input_words[32],
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,output_words[32],
 output int outstanding,output logic [5:0] request_packages
);
 logic live[SLOTS],serviced[SLOTS];
 logic [31:0] ids[SLOTS];
 int remaining[SLOTS],delay_left[SLOTS];
 longint unsigned sequence_number[SLOTS],next_sequence;
 int free_slot,service_slot,response_slot,pacing;
 logic legal;
 initial if(SLOTS<1||SERVICE_INTERVAL<1||RETURN_DELAY<1)
  $fatal(1,"Invalid shared service parameters");
 always_comb begin
  int largest;
  legal=1;largest=0;
  for(int lane=0;lane<32;lane++)if(byte_addresses[lane][1:0]!=0)legal=0;
  // Count each distinct word once. Broadcast duplicates share one bank service.
  begin
   int words_per_bank[32];
   for(int bank=0;bank<32;bank++)words_per_bank[bank]=0;
   for(int lane=0;lane<32;lane++)begin
    bit first;first=1;
    for(int earlier=0;earlier<lane;earlier++)
     if(byte_addresses[lane]==byte_addresses[earlier])first=0;
    if(first)words_per_bank[byte_addresses[lane][6:2]]++;
   end
   for(int bank=0;bank<32;bank++)
    if(words_per_bank[bank]>largest)largest=words_per_bank[bank];
  end
  request_packages=6'(largest);
  free_slot=-1;service_slot=-1;response_slot=-1;outstanding=0;
  for(int slot=0;slot<SLOTS;slot++)begin
   if(!live[slot]&&free_slot==-1)free_slot=slot;
   if(live[slot])begin
    outstanding++;
    if(!serviced[slot])begin
     if(service_slot==-1)service_slot=slot;
     else if(sequence_number[slot]<sequence_number[service_slot])service_slot=slot;
    end
    if(serviced[slot]&&delay_left[slot]==0)begin
     if(response_slot==-1)response_slot=slot;
     else if(sequence_number[slot]<sequence_number[response_slot])response_slot=slot;
    end
   end
  end
  req_ready=!rst&&legal&&free_slot!=-1;
  rsp_valid=!rst&&response_slot!=-1;rsp_id=0;
  for(int lane=0;lane<32;lane++)output_words[lane]=0;
  if(response_slot!=-1)begin
   rsp_id=ids[response_slot];

  end
 end
 always_ff @(posedge clk)begin
  if(rst)begin
   next_sequence<=0;pacing<=0;
   for(int slot=0;slot<SLOTS;slot++)begin
    live[slot]<=0;serviced[slot]<=0;remaining[slot]<=0;delay_left[slot]<=0;
    sequence_number[slot]<=0;ids[slot]<=0;
   end
  end else begin
   if(req_valid&&!legal)$fatal(1,"Misaligned scalar shared request");
   if(pacing>0)pacing<=pacing-1;
   if(service_slot!=-1&&pacing==0)begin
    remaining[service_slot]<=remaining[service_slot]-1;
    pacing<=SERVICE_INTERVAL-1;
    if(remaining[service_slot]==1)begin
     serviced[service_slot]<=1;delay_left[service_slot]<=RETURN_DELAY;
    end
   end
   for(int slot=0;slot<SLOTS;slot++)
    if(live[slot]&&serviced[slot]&&delay_left[slot]>0)
     delay_left[slot]<=delay_left[slot]-1;
   if(rsp_valid&&rsp_ready)live[response_slot]<=0;
   // Admission uses pre-edge capacity. A retiring slot becomes free next cycle.
   if(req_valid&&req_ready)begin
    for(int slot=0;slot<SLOTS;slot++)
     if(live[slot]&&ids[slot]==req_id)$fatal(1,"Duplicate live shared request ID");
    live[free_slot]<=1;serviced[free_slot]<=0;ids[free_slot]<=req_id;
    remaining[free_slot]<=int'(request_packages);delay_left[free_slot]<=0;
    sequence_number[free_slot]<=next_sequence;next_sequence<=next_sequence+1;

   end
  end
 end
endmodule
