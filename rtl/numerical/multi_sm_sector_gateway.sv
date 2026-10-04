// One shared external memory transaction. Serialization/RR is a hypothesis;
// this is not a measured physical DRAM controller or global cache.
module multi_sm_sector_gateway #(parameter int SMS=2)(
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
 input logic store_backing_rsp_valid,output logic store_backing_rsp_ready,input logic[31:0]store_backing_rsp_id
);
 typedef enum logic[1:0]{IDLE,SEND,WAIT_REPLY,RETURN}state_t;state_t state;
 int cursor,selected,owner;logic kind;
 logic[31:0]next_id,saved_internal_id,saved_external_id,saved_address;
 logic[255:0]saved_data,returned_data;logic[7:0]saved_mask;
 initial if(SMS<1)$fatal(1,"Invalid gateway SM count");
 always_comb begin
  selected=-1;read_req_ready='0;write_req_ready='0;
  for(int offset=0;offset<2*SMS;offset++)begin
   int candidate;candidate=(cursor+offset)%(2*SMS);
   if(!rst&&state==IDLE&&selected<0&&(candidate<SMS?read_req_valid[candidate]:write_req_valid[candidate-SMS]))selected=candidate;
  end
  if(selected>=0)begin
   if(selected<SMS)read_req_ready[selected]=1;else write_req_ready[selected-SMS]=1;
  end
 end
 always_comb begin
  read_rsp_valid='0;write_rsp_valid='0;
  for(int sm=0;sm<SMS;sm++)begin read_rsp_id[sm]=0;write_rsp_id[sm]=0;read_rsp_data[sm]=0;end
  if(!rst&&state==RETURN)begin
   if(kind)begin write_rsp_valid[owner]=1;write_rsp_id[owner]=saved_external_id;end
   else begin read_rsp_valid[owner]=1;read_rsp_id[owner]=saved_external_id;read_rsp_data[owner]=returned_data;end
  end
 end
 assign backing_req_valid=!rst&&state==SEND&&!kind;
 assign store_backing_req_valid=!rst&&state==SEND&&kind;
 assign backing_req_id=saved_internal_id;assign store_backing_req_id=saved_internal_id;
 assign backing_req_byte_address=saved_address;assign store_backing_req_byte_address=saved_address;
 assign store_backing_req_data=saved_data;assign store_backing_req_word_mask=saved_mask;
 assign backing_rsp_ready=!rst&&state==WAIT_REPLY&&!kind;
 assign store_backing_rsp_ready=!rst&&state==WAIT_REPLY&&kind;
 always_ff @(posedge clk)begin
  if(rst)begin state<=IDLE;cursor<=0;owner<=0;kind<=0;next_id<=0;saved_internal_id<=0;saved_external_id<=0;saved_address<=0;saved_data<=0;saved_mask<=0;returned_data<=0;end
  else case(state)
   IDLE:if(selected>=0)begin
    if(&next_id)$fatal(1,"Gateway ID exhausted; reset required");
    owner<=selected%SMS;kind<=selected>=SMS;saved_internal_id<=next_id;next_id<=next_id+1;
    if(selected<SMS)begin
     if(read_req_byte_address[selected][4:0]!=0)$fatal(1,"Unaligned gateway read sector");
     saved_external_id<=read_req_id[selected];saved_address<=read_req_byte_address[selected];saved_data<=0;saved_mask<=0;
    end else begin
     if(write_req_byte_address[selected-SMS][4:0]!=0||write_req_word_mask[selected-SMS]==0)$fatal(1,"Invalid gateway write sector");
     saved_external_id<=write_req_id[selected-SMS];saved_address<=write_req_byte_address[selected-SMS];saved_data<=write_req_data[selected-SMS];saved_mask<=write_req_word_mask[selected-SMS];
    end
    cursor<=(selected+1)%(2*SMS);state<=SEND;
   end
   SEND:if((backing_req_valid&&backing_req_ready)||(store_backing_req_valid&&store_backing_req_ready))state<=WAIT_REPLY;
   WAIT_REPLY:begin
    if(backing_rsp_valid&&backing_rsp_ready)begin
     if(backing_rsp_id!=saved_internal_id)$fatal(1,"Gateway read completion identity mismatch");
     returned_data<=backing_rsp_data;state<=RETURN;
    end
    if(store_backing_rsp_valid&&store_backing_rsp_ready)begin
     if(store_backing_rsp_id!=saved_internal_id)$fatal(1,"Gateway write completion identity mismatch");
     state<=RETURN;
    end
   end
   RETURN:if(kind?write_rsp_ready[owner]:read_rsp_ready[owner])state<=IDLE;
   default:$fatal(1,"Invalid gateway state");
  endcase
 end
 // Owners and all payloads remain held through external/provider/client stalls.
 // Reset cancels the record; provider must flush stale responses before restart.
endmodule
