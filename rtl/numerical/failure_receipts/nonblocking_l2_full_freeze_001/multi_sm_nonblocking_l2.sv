// Shared nonblocking read-only sector cache, write-around output transactions.
// RR issue, owner/MSHR capacities and geometry are simulation choices.
module multi_sm_nonblocking_l2 #(
 parameter int SMS=2,L2_SETS=64,L2_WAYS=8,OWNER_SLOTS=8,MSHRS=4
)(
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
 output int l2_read_requests,l2_read_hits,l2_read_misses,l2_merged_misses,l2_actual_fills,live_owners,live_mshrs,peak_owners,peak_mshrs);
 logic owner_live[OWNER_SLOTS],owner_done[OWNER_SLOTS],owner_write[OWNER_SLOTS],owner_sent[OWNER_SLOTS];
 int owner_client[OWNER_SLOTS],owner_mshr[OWNER_SLOTS];
 logic[31:0]owner_id[OWNER_SLOTS],owner_internal_id[OWNER_SLOTS],owner_address[OWNER_SLOTS];
 logic[255:0]owner_data[OWNER_SLOTS];logic[7:0]owner_mask[OWNER_SLOTS];
 logic mshr_live[MSHRS],mshr_sent[MSHRS];
 int mshr_set[MSHRS],mshr_way[MSHRS],mshr_sector[MSHRS];
 logic[31:0]mshr_address[MSHRS],mshr_id[MSHRS];
 logic line_valid[L2_SETS][L2_WAYS];logic[31:0]line_tag[L2_SETS][L2_WAYS];
 logic[3:0]sector_valid[L2_SETS][L2_WAYS];logic[255:0]sectors[L2_SETS][L2_WAYS][4];
 int victim_cursor[L2_SETS];logic pinned[L2_SETS][L2_WAYS];
 int response_owner[2*SMS],admission_cursor,selected,free_owner,free_mshr;
 int read_set[SMS],read_way[SMS],read_sector[SMS],read_join[SMS];
 logic[31:0]read_tag[SMS];logic read_hit[SMS],read_admissible[SMS];
 logic backend_offer,backend_kind;int backend_owner,backend_mshr,backend_cursor;
 logic[31:0]next_internal_id,backend_id,backend_address;
 logic[255:0]backend_data;logic[7:0]backend_mask;
 int read_return_mshr,write_return_owner;
 initial if(SMS<1||L2_SETS<1||L2_WAYS<1||OWNER_SLOTS<1||MSHRS<1)$fatal(1,"Invalid nonblocking cache geometry");
 always_comb begin
  live_owners=0;free_owner=-1;
  for(int o=0;o<OWNER_SLOTS;o++)begin if(owner_live[o])live_owners++;else if(free_owner<0)free_owner=o;end
  live_mshrs=0;free_mshr=-1;
  for(int m=0;m<MSHRS;m++)begin if(mshr_live[m])live_mshrs++;else if(free_mshr<0)free_mshr=m;end
  for(int s=0;s<L2_SETS;s++)for(int w=0;w<L2_WAYS;w++)begin
   pinned[s][w]=0;
   for(int m=0;m<MSHRS;m++)if(mshr_live[m]&&mshr_set[m]==s&&mshr_way[m]==w)pinned[s][w]=1;
  end
 end
 always_comb begin
  for(int sm=0;sm<SMS;sm++)begin
   int match_way;match_way=-1;
   read_set[sm]=int'((read_req_byte_address[sm]>>7)%32'(L2_SETS));
   read_tag[sm]=read_req_byte_address[sm]/32'(128*L2_SETS);
   read_sector[sm]=int'(read_req_byte_address[sm][6:5]);read_way[sm]=-1;read_join[sm]=-1;
   for(int w=0;w<L2_WAYS;w++)if(line_valid[read_set[sm]][w]&&line_tag[read_set[sm]][w]==read_tag[sm])match_way=w;
   if(match_way>=0)read_way[sm]=match_way;
   for(int w=0;w<L2_WAYS;w++)if(read_way[sm]<0&&!line_valid[read_set[sm]][w]&&!pinned[read_set[sm]][w])read_way[sm]=w;
   for(int offset=0;offset<L2_WAYS;offset++)begin
    int w;w=(victim_cursor[read_set[sm]]+offset)%L2_WAYS;
    if(read_way[sm]<0&&!pinned[read_set[sm]][w])read_way[sm]=w;
   end
   read_hit[sm]=match_way>=0?(sector_valid[read_set[sm]][match_way][read_sector[sm]]):0;
   for(int m=0;m<MSHRS;m++)if(mshr_live[m]&&mshr_address[m]==read_req_byte_address[sm])read_join[sm]=m;
   read_admissible[sm]=read_req_byte_address[sm][4:0]==0&&(read_hit[sm]||read_join[sm]>=0||(free_mshr>=0&&read_way[sm]>=0));
  end
 end
 always_comb begin
  selected=-1;read_req_ready='0;write_req_ready='0;
  for(int offset=0;offset<2*SMS;offset++)begin
   int client;client=(admission_cursor+offset)%(2*SMS);
   if(!rst&&free_owner>=0&&selected<0)begin
    if(client<SMS)begin if(read_req_valid[client]&&read_admissible[client])selected=client;end
    else if(write_req_valid[client-SMS])selected=client;
   end
  end
  if(selected>=0)begin if(selected<SMS)read_req_ready[selected]=1;else write_req_ready[selected-SMS]=1;end
 end
 always_comb begin
  read_rsp_valid='0;write_rsp_valid='0;
  for(int sm=0;sm<SMS;sm++)begin
   read_rsp_id[sm]=0;read_rsp_data[sm]=0;write_rsp_id[sm]=0;
   if(!rst&&response_owner[sm]>=0)begin read_rsp_valid[sm]=1;read_rsp_id[sm]=owner_id[response_owner[sm]];read_rsp_data[sm]=owner_data[response_owner[sm]];end
   if(!rst&&response_owner[SMS+sm]>=0)begin write_rsp_valid[sm]=1;write_rsp_id[sm]=owner_id[response_owner[SMS+sm]];end
  end
 end
 assign backing_req_valid=!rst&&backend_offer&&!backend_kind;
 assign store_backing_req_valid=!rst&&backend_offer&&backend_kind;
 assign backing_req_id=backend_id;assign store_backing_req_id=backend_id;
 assign backing_req_byte_address=backend_address;assign store_backing_req_byte_address=backend_address;
 assign store_backing_req_data=backend_data;assign store_backing_req_word_mask=backend_mask;
 always_comb begin
  read_return_mshr=-1;write_return_owner=-1;
  for(int m=0;m<MSHRS;m++)if(mshr_live[m]&&mshr_sent[m]&&mshr_id[m]==backing_rsp_id)read_return_mshr=m;
  for(int o=0;o<OWNER_SLOTS;o++)if(owner_live[o]&&owner_write[o]&&owner_sent[o]&&!owner_done[o]&&owner_internal_id[o]==store_backing_rsp_id)write_return_owner=o;
 end
 assign backing_rsp_ready=!rst;
 assign store_backing_rsp_ready=!rst;
 always_ff @(posedge clk)begin
  if(rst)begin
   admission_cursor<=0;backend_cursor<=0;next_internal_id<=0;backend_offer<=0;backend_kind<=0;backend_owner<=0;backend_mshr<=0;backend_id<=0;backend_address<=0;backend_data<=0;backend_mask<=0;
   l2_read_requests<=0;l2_read_hits<=0;l2_read_misses<=0;l2_merged_misses<=0;l2_actual_fills<=0;peak_owners<=0;peak_mshrs<=0;
   for(int o=0;o<OWNER_SLOTS;o++)begin owner_live[o]<=0;owner_done[o]<=0;owner_write[o]<=0;owner_sent[o]<=0;owner_client[o]<=0;owner_mshr[o]<=-1;owner_id[o]<=0;owner_internal_id[o]<=0;owner_address[o]<=0;owner_data[o]<=0;owner_mask[o]<=0;end
   for(int m=0;m<MSHRS;m++)begin mshr_live[m]<=0;mshr_sent[m]<=0;mshr_set[m]<=0;mshr_way[m]<=0;mshr_sector[m]<=0;mshr_address[m]<=0;mshr_id[m]<=0;end
   for(int c=0;c<2*SMS;c++)response_owner[c]<=-1;
   for(int s=0;s<L2_SETS;s++)begin victim_cursor[s]<=0;for(int w=0;w<L2_WAYS;w++)begin line_valid[s][w]<=0;line_tag[s][w]<=0;sector_valid[s][w]<=0;end end
  end else begin
   for(int sm=0;sm<SMS;sm++)if(read_req_valid[sm]&&read_req_byte_address[sm][4:0]!=0)$fatal(1,"Unaligned nonblocking read sector");
   if(live_owners>peak_owners)peak_owners<=live_owners;
   if(live_mshrs>peak_mshrs)peak_mshrs<=live_mshrs;
   if(l2_read_requests!=l2_read_hits+l2_read_misses)$fatal(1,"Nonblocking logical cache count mismatch");
   // Each client has a held reply owner independent of every other client.
   for(int c=0;c<2*SMS;c++)begin
    if(response_owner[c]<0)begin
     int choice;choice=-1;
     for(int o=0;o<OWNER_SLOTS;o++)if(choice<0&&owner_live[o]&&owner_done[o]&&owner_client[o]==c)choice=o;
     if(choice>=0)response_owner[c]<=choice;
    end else if(c<SMS?read_rsp_ready[c]:write_rsp_ready[c-SMS])begin owner_live[response_owner[c]]<=0;response_owner[c]<=-1;end
   end
   if(selected>=0)begin
    int sm;sm=selected%SMS;
    for(int o=0;o<OWNER_SLOTS;o++)if(owner_live[o]&&owner_client[o]==selected&&owner_id[o]==(selected<SMS?read_req_id[sm]:write_req_id[sm]))$fatal(1,"Duplicate nonblocking client ownership ID");
    owner_live[free_owner]<=1;owner_client[free_owner]<=selected;owner_id[free_owner]<=selected<SMS?read_req_id[sm]:write_req_id[sm];owner_done[free_owner]<=0;owner_sent[free_owner]<=0;owner_write[free_owner]<=selected>=SMS;owner_mshr[free_owner]<=-1;
    admission_cursor<=(selected+1)%(2*SMS);
    if(selected>=SMS)begin
     if(write_req_byte_address[sm][4:0]!=0||write_req_word_mask[sm]==0)$fatal(1,"Invalid nonblocking write sector");
     if(&next_internal_id)$fatal(1,"Nonblocking ID exhausted");
     owner_internal_id[free_owner]<=next_internal_id;next_internal_id<=next_internal_id+1;owner_address[free_owner]<=write_req_byte_address[sm];owner_data[free_owner]<=write_req_data[sm];owner_mask[free_owner]<=write_req_word_mask[sm];
    end else begin
     l2_read_requests<=l2_read_requests+1;
     if(read_hit[sm])begin l2_read_hits<=l2_read_hits+1;owner_done[free_owner]<=1;owner_data[free_owner]<=sectors[read_set[sm]][read_way[sm]][read_sector[sm]];end
     else begin
      l2_read_misses<=l2_read_misses+1;
      if(read_join[sm]>=0)begin
       l2_merged_misses<=l2_merged_misses+1;owner_mshr[free_owner]<=read_join[sm];
       // A joining acceptance can coincide with its refill return.
       if(backing_rsp_valid&&read_return_mshr==read_join[sm])begin owner_done[free_owner]<=1;owner_data[free_owner]<=backing_rsp_data;owner_mshr[free_owner]<=-1;end
      end else begin
       if(&next_internal_id)$fatal(1,"Nonblocking ID exhausted");
       mshr_live[free_mshr]<=1;mshr_sent[free_mshr]<=0;mshr_id[free_mshr]<=next_internal_id;next_internal_id<=next_internal_id+1;
       mshr_address[free_mshr]<=read_req_byte_address[sm];mshr_set[free_mshr]<=read_set[sm];mshr_way[free_mshr]<=read_way[sm];mshr_sector[free_mshr]<=read_sector[sm];owner_mshr[free_owner]<=free_mshr;
       if(!line_valid[read_set[sm]][read_way[sm]]||line_tag[read_set[sm]][read_way[sm]]!=read_tag[sm])begin line_valid[read_set[sm]][read_way[sm]]<=1;line_tag[read_set[sm]][read_way[sm]]<=read_tag[sm];sector_valid[read_set[sm]][read_way[sm]]<=0;end
       victim_cursor[read_set[sm]]<=(read_way[sm]+1)%L2_WAYS;
      end
     end
    end
   end
   if(!backend_offer)begin
    int choice;choice=-1;
    for(int off=0;off<MSHRS+OWNER_SLOTS;off++)begin
     int index_value;index_value=(backend_cursor+off)%(MSHRS+OWNER_SLOTS);
     if(choice<0)begin
      if(index_value<MSHRS)begin if(mshr_live[index_value]&&!mshr_sent[index_value])choice=index_value;end
      else if(owner_live[index_value-MSHRS]&&owner_write[index_value-MSHRS]&&!owner_sent[index_value-MSHRS])choice=index_value;
     end
    end
    if(choice>=0)begin
     backend_offer<=1;backend_kind<=choice>=MSHRS;
     if(choice<MSHRS)begin backend_mshr<=choice;backend_id<=mshr_id[choice];backend_address<=mshr_address[choice];backend_data<=0;backend_mask<=0;end
     else begin backend_owner<=choice-MSHRS;backend_id<=owner_internal_id[choice-MSHRS];backend_address<=owner_address[choice-MSHRS];backend_data<=owner_data[choice-MSHRS];backend_mask<=owner_mask[choice-MSHRS];end
     backend_cursor<=(choice+1)%(MSHRS+OWNER_SLOTS);
    end
   end else if((backing_req_valid&&backing_req_ready)||(store_backing_req_valid&&store_backing_req_ready))begin
    backend_offer<=0;if(backend_kind)owner_sent[backend_owner]<=1;else mshr_sent[backend_mshr]<=1;
   end
   if(backing_rsp_valid)begin
    if(read_return_mshr<0)$fatal(1,"Nonblocking read completion identity mismatch");
    else begin
     l2_actual_fills<=l2_actual_fills+1;mshr_live[read_return_mshr]<=0;
     sectors[mshr_set[read_return_mshr]][mshr_way[read_return_mshr]][mshr_sector[read_return_mshr]]<=backing_rsp_data;
     sector_valid[mshr_set[read_return_mshr]][mshr_way[read_return_mshr]][mshr_sector[read_return_mshr]]<=1;
     for(int o=0;o<OWNER_SLOTS;o++)if(owner_live[o]&&!owner_write[o]&&!owner_done[o]&&owner_mshr[o]==read_return_mshr)begin owner_done[o]<=1;owner_data[o]<=backing_rsp_data;owner_mshr[o]<=-1;end
    end
   end
   if(store_backing_rsp_valid)begin
    if(write_return_owner<0)$fatal(1,"Nonblocking write completion identity mismatch");
    else owner_done[write_return_owner]<=1;
   end
  end
 end
 // Logical misses include merged requests. Actual fills count returned fetches,
 // not owner acknowledgments; hits capture data at acceptance. Refill lines pin
 // their ways until all live sectors return. IDs reset only with provider flush.
 // No coherence/write invalidation. Cached inputs remain immutable until reset.
endmodule
