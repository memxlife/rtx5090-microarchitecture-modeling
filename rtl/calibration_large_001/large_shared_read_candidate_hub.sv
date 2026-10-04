// Candidate previews are not ready/valid offers: only candidate_grant commits
// the selected values. One common scalar-warp read service snapshots each grant.
// RR issue, FIFO head blocking and one global return are simulation hypotheses.
module large_shared_read_candidate_hub #(
 parameter int CLIENTS=2,SLOTS=4,SERVICE_INTERVAL=1,RETURN_DELAY=1
)(
 input logic clk,rst,
 input logic[CLIENTS-1:0]candidate_valid,output logic[CLIENTS-1:0]candidate_grant,
 input logic[31:0]candidate_id[CLIENTS],byte_addresses[CLIENTS][32],input_words[CLIENTS][32],
 output logic[CLIENTS-1:0]rsp_valid,input logic[CLIENTS-1:0]rsp_ready,
 output logic[31:0]rsp_id[CLIENTS],output_words[CLIENTS][32],
 output int outstanding,client_outstanding[CLIENTS]
);
 logic live[SLOTS];int owner[SLOTS];logic[31:0]internal_ids[SLOTS],external_ids[SLOTS];
 logic[31:0]next_id;int cursor,selected,free_record,response_record;
 logic unit_req_valid,unit_req_ready,unit_rsp_valid,unit_rsp_ready;
 logic[31:0]unit_req_id,unit_rsp_id,unit_addresses[32],unit_inputs[32],unit_outputs[32];
 int unit_outstanding;
 initial if(CLIENTS<1||SLOTS<1)$fatal(1,"Invalid shared-read hub capacity");
 always_comb begin
  free_record=-1;outstanding=0;
  for(int client=0;client<CLIENTS;client++)client_outstanding[client]=0;
  for(int slot=0;slot<SLOTS;slot++)begin
   if(live[slot])begin outstanding++;client_outstanding[owner[slot]]++;end
   else if(free_record<0)free_record=slot;
  end
 end
 always_comb begin
  selected=-1;
  for(int offset=0;offset<CLIENTS;offset++)begin
   int client;client=(cursor+offset)%CLIENTS;
   if(!rst&&free_record>=0&&selected<0&&candidate_valid[client])selected=client;
  end
  for(int lane=0;lane<32;lane++)begin
   unit_addresses[lane]=selected>=0?byte_addresses[selected][lane]:0;
   unit_inputs[lane]=selected>=0?input_words[selected][lane]:0;
  end
 end
 assign unit_req_valid=!rst&&selected>=0;
 assign unit_req_id=next_id;
 always_comb begin
  candidate_grant='0;
  if(unit_req_valid&&unit_req_ready)candidate_grant[selected]=1;
 end
 always_comb begin
  response_record=-1;
  for(int slot=0;slot<SLOTS;slot++)if(live[slot]&&internal_ids[slot]==unit_rsp_id)response_record=slot;
  rsp_valid='0;
  for(int client=0;client<CLIENTS;client++)begin
   rsp_id[client]=0;
   for(int lane=0;lane<32;lane++)output_words[client][lane]=0;
  end
  if(!rst&&unit_rsp_valid&&response_record>=0)begin
   rsp_valid[owner[response_record]]=1;
   rsp_id[owner[response_record]]=external_ids[response_record];
   for(int lane=0;lane<32;lane++)output_words[owner[response_record]][lane]=unit_outputs[lane];

  end
 end
 always_comb begin
  unit_rsp_ready=0;
  if(!rst&&unit_rsp_valid&&response_record>=0)unit_rsp_ready=rsp_ready[owner[response_record]];
 end
 always_ff @(posedge clk)begin
  if(rst)begin
   next_id<=0;cursor<=0;
   for(int slot=0;slot<SLOTS;slot++)begin live[slot]<=0;owner[slot]<=0;internal_ids[slot]<=0;external_ids[slot]<=0;end
  end else begin
   if(outstanding!=unit_outstanding)$fatal(1,"Shared-read owner/service conservation failed");
   if(unit_rsp_valid&&response_record<0)$fatal(1,"Shared-read completion has no owner");
   if(unit_rsp_valid&&unit_rsp_ready)live[response_record]<=0;
   if(unit_req_valid&&unit_req_ready)begin
    if(free_record<0)$fatal(1,"Shared-read grant lacks owner capacity");
    if(&next_id)$fatal(1,"Shared-read service ID exhausted; reset required");
    for(int slot=0;slot<SLOTS;slot++)if(live[slot]&&owner[slot]==selected&&external_ids[slot]==candidate_id[selected])
     $fatal(1,"Duplicate in-flight shared-read client ID");
    live[free_record]<=1;owner[free_record]<=selected;internal_ids[free_record]<=next_id;external_ids[free_record]<=candidate_id[selected];
    next_id<=next_id+1;cursor<=(selected+1)%CLIENTS;
   end
  end
 end
 large_warp_shared_read_service #(.SLOTS(SLOTS),.SERVICE_INTERVAL(SERVICE_INTERVAL),.RETURN_DELAY(RETURN_DELAY)) service(
  .clk,.rst,.req_valid(unit_req_valid),.req_ready(unit_req_ready),.req_id(unit_req_id),.byte_addresses(unit_addresses),.input_words(unit_inputs),
  .rsp_valid(unit_rsp_valid),.rsp_ready(unit_rsp_ready),.rsp_id(unit_rsp_id),.output_words(unit_outputs),.outstanding(unit_outstanding),.request_packages()
 );
 // Owner records live through response acknowledgment. Equal IDs across clients
 // are legal; same-client reuse on a retirement edge is conservatively rejected.
 // Reset discards every outstanding request and resets the shared service.
endmodule
