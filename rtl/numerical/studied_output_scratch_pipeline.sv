// Original BM32 output scratch: four STS64 groups per warp, then eight LDS
// warp reads per warp. Native C layout is measured; serial service and bank
// write interval/return delays are simulation choices, not identified timing.
// Collective visibility fence substitutes for native WARPSYNC arrival rules.
module studied_output_scratch_pipeline #(
 parameter int STORE_INTERVAL=1,STORE_RETURN_DELAY=1,
 parameter int READ_SLOTS=4,READ_INTERVAL=1,READ_RETURN_DELAY=1
)(
 input logic clk,rst,req_valid,output logic req_ready,input logic[31:0]req_id,
 input logic[31:0]c_registers[4][32][8],
 output logic rsp_valid,input logic rsp_ready,output logic[31:0]rsp_id,
 output logic[31:0]row_major_words[4][256],output int outstanding,
 output int store_requests,store_commit_words,read_requests,read_completions
);
 typedef enum logic[2:0]{IDLE,STORE_PREP,STORE_SERVICE,STORE_RETURN,
  READ_SEND,READ_WAIT,RESPONSE}state_t;
 state_t state;
 logic[31:0]saved_id,saved_c[4][32][8],scratch[1024];logic initialized[1024];
 int store_warp,store_group,remaining_words,pacing,return_delay,read_ordinal;
 logic pending_entry[64];int entry_address[64];logic[31:0]entry_data[64];
 int selected_entry[32],selected_words;
 logic read_req_valid,read_req_ready,read_rsp_valid,read_rsp_ready;
 logic[31:0]read_req_id,read_rsp_id,read_addresses[32],read_inputs[32],read_outputs[32];int read_outstanding;
 initial if(STORE_INTERVAL<1||STORE_RETURN_DELAY<1||READ_SLOTS<1||READ_INTERVAL<1||READ_RETURN_DELAY<1)
  $fatal(1,"Invalid output scratch timing configuration");
 assign req_ready=!rst&&state==IDLE;
 assign rsp_valid=!rst&&state==RESPONSE;assign rsp_id=saved_id;
 assign outstanding=state==IDLE?0:1;
 always_comb begin
  selected_words=0;
  for(int bank=0;bank<32;bank++)begin
   selected_entry[bank]=-1;
   for(int entry=0;entry<64;entry++)if(pending_entry[entry]&&entry_address[entry]%32==bank&&selected_entry[bank]<0)selected_entry[bank]=entry;
   if(selected_entry[bank]>=0)selected_words++;
  end
 end
 assign read_req_valid=!rst&&state==READ_SEND;
 assign read_rsp_ready=!rst&&state==READ_WAIT;
 assign read_req_id=32'(read_ordinal);
 always_comb begin
  for(int lane=0;lane<32;lane++)begin
   read_addresses[lane]=32'(1024*(read_ordinal/8)+4*(lane+32*(read_ordinal%8)));
   read_inputs[lane]=scratch[256*(read_ordinal/8)+lane+32*(read_ordinal%8)];
  end
 end
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;saved_id<=0;store_warp<=0;store_group<=0;remaining_words<=0;pacing<=0;return_delay<=0;read_ordinal<=0;
   store_requests<=0;store_commit_words<=0;read_requests<=0;read_completions<=0;
   for(int i=0;i<1024;i++)begin scratch[i]<=0;initialized[i]<=0;end
   for(int entry=0;entry<64;entry++)begin pending_entry[entry]<=0;entry_address[entry]<=0;entry_data[entry]<=0;end
   for(int warp=0;warp<4;warp++)begin
    for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)saved_c[warp][lane][word]<=0;
    for(int word=0;word<256;word++)row_major_words[warp][word]<=0;
   end
  end else case(state)
   IDLE:if(req_valid&&req_ready)begin
    saved_id<=req_id;store_warp<=0;store_group<=0;read_ordinal<=0;state<=STORE_PREP;
    store_requests<=0;store_commit_words<=0;read_requests<=0;read_completions<=0;
    for(int i=0;i<1024;i++)initialized[i]<=0;
    for(int warp=0;warp<4;warp++)begin
     for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)saved_c[warp][lane][word]<=c_registers[warp][lane][word];
     for(int word=0;word<256;word++)row_major_words[warp][word]<=0;
    end
   end
   STORE_PREP:begin
    // Pairs0/1,2/3,4/5,6/7 have native byte offsets0,512,32,544.
    for(int lane=0;lane<32;lane++)for(int half=0;half<2;half++)begin
     pending_entry[2*lane+half]<=1;
     entry_address[2*lane+half]<=256*store_warp+native_bf16_layout::c_element_index(lane,2*store_group+half);
     entry_data[2*lane+half]<=saved_c[store_warp][lane][2*store_group+half];
    end
    remaining_words<=64;pacing<=0;store_requests<=store_requests+1;state<=STORE_SERVICE;
   end
   STORE_SERVICE:begin
    if(pacing>0)pacing<=pacing-1;
    else begin
     if(selected_words<1||selected_words>remaining_words)$fatal(1,"Invalid output scratch bank work");
     for(int bank=0;bank<32;bank++)if(selected_entry[bank]>=0)begin
      scratch[entry_address[selected_entry[bank]]]<=entry_data[selected_entry[bank]];
      initialized[entry_address[selected_entry[bank]]]<=1;pending_entry[selected_entry[bank]]<=0;
     end
     store_commit_words<=store_commit_words+selected_words;
     remaining_words<=remaining_words-selected_words;pacing<=STORE_INTERVAL-1;
     if(remaining_words==selected_words)begin return_delay<=STORE_RETURN_DELAY-1;state<=STORE_RETURN;end
    end
   end
   STORE_RETURN:begin
    if(return_delay>0)return_delay<=return_delay-1;
    else if(store_group<3)begin store_group<=store_group+1;state<=STORE_PREP;end
    else if(store_warp<3)begin store_warp<=store_warp+1;store_group<=0;state<=STORE_PREP;end
    else begin
     if(store_commit_words!=1024||store_requests!=16)$fatal(1,"Scratch visibility fence reached before all stores");
     read_ordinal<=0;state<=READ_SEND;
    end
   end
   READ_SEND:if(read_req_valid&&read_req_ready)begin
    for(int lane=0;lane<32;lane++)if(!initialized[256*(read_ordinal/8)+lane+32*(read_ordinal%8)])$fatal(1,"Scratch load precedes write visibility");
    read_requests<=read_requests+1;state<=READ_WAIT;
   end
   READ_WAIT:if(read_rsp_valid&&read_rsp_ready)begin
    if(read_rsp_id!=read_req_id)$fatal(1,"Scratch read completion identity mismatch");
    for(int lane=0;lane<32;lane++)row_major_words[read_ordinal/8][lane+32*(read_ordinal%8)]<=read_outputs[lane];
    read_completions<=read_completions+1;
    if(read_ordinal==31)state<=RESPONSE;
    else begin read_ordinal<=read_ordinal+1;state<=READ_SEND;end
   end
   RESPONSE:if(rsp_valid&&rsp_ready)state<=IDLE;
   default:$fatal(1,"Invalid output scratch state");
  endcase
 end
 warp_shared_read_service #(.SLOTS(READ_SLOTS),.SERVICE_INTERVAL(READ_INTERVAL),.RETURN_DELAY(READ_RETURN_DELAY)) reads(
  .clk,.rst,.req_valid(read_req_valid),.req_ready(read_req_ready),.req_id(read_req_id),
  .byte_addresses(read_addresses),.input_words(read_inputs),.rsp_valid(read_rsp_valid),.rsp_ready(read_rsp_ready),
  .rsp_id(read_rsp_id),.output_words(read_outputs),.outstanding(read_outstanding),.request_packages()
 );
 // Actual shared words feed response reads; no C-to-output bypass. Each batch
 // drains all writes then all32 reads. Reset discards pending service events.
endmodule
