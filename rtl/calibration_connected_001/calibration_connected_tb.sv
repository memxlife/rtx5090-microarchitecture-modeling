`timescale 1ns/1ps
module calibration_connected_tb #(parameter int K=64);
 logic local_cache_invalidate=0;int l2_hit_delay_cycles=0,kernel_setup_cycles=0;
 logic clk=0;always #0.05 clk=~clk;logic rst=1,launch_valid=0,launch_ready,done_valid,done_ready=0;
 logic[31:0]launch_id=0,a_base=0,b_base=32'h100000,c_base=32'h200000,done_id;
 logic backing_req_valid,backing_req_ready,backing_rsp_valid=0,backing_rsp_ready;
 logic[31:0]backing_req_id,backing_req_byte_address,backing_rsp_id;logic[255:0]backing_rsp_data;
 int l2_read_requests,l2_read_hits,l2_read_misses,l2_merged_misses,l2_actual_fills,live_owners,live_mshrs,peak_owners,peak_mshrs,backing_read_count=0;
 logic[5:0]sm_native_issue_valid;bit sm_issued[6];
 logic[63:0]elapsed_cycles;longint unsigned expected_elapsed=0;bit elapsed_active=0;
 int dispatched_blocks,completed_blocks;logic block_launch_valid,block_done_valid;
 logic[31:0]block_launch_sm,block_done_sm;bit sm_seen[6];int block_owner[6];
 logic[31:0]block_launch_ordinal,block_launch_row,block_launch_col,block_done_ordinal,block_done_row,block_done_col;
 bit dispatched_seen[6];int dispatches=0,grid_launches=0,peak_resident=0;
 int resident_blocks,resident_warps,cycle=0,delay_left=0,checked=0;bit pending=0;
 logic[31:0]pending_id,pending_address;
 int issues[2];
 logic store_backing_req_valid,store_backing_req_ready,store_backing_rsp_valid,store_backing_rsp_ready;
 logic[31:0]store_backing_req_id,store_backing_req_byte_address,store_backing_rsp_id;
 logic[255:0]store_backing_req_data;logic[7:0]store_backing_req_word_mask;
 bit store_pending=0,store_held=0,seen[6144],done_seen[6];int store_wait=0,stores=0,acks=0,block_acks[6],completed=0;
 logic[31:0]saved_store_id,held_store_id,held_store_address;logic[255:0]held_store_data;logic[7:0]held_store_mask;int pending_block,pending_words;
 function automatic logic[31:0] output_expected(input integer row,col);
  integer sum;begin sum=0;for(int k=0;k<K;k++)sum+=((row*K+k)%17-8)*((k*96+col)%13-6);return dyadic(sum,8);end
 endfunction
 always @(posedge clk)begin
  if(rst)begin store_held<=0;stores=0;acks=0;completed=0;for(int b=0;b<6;b++)begin block_acks[b]=0;done_seen[b]=0;end for(int i=0;i<6144;i++)seen[i]=0;end
  else begin
   if(store_held)begin
    if(!store_backing_req_valid||store_backing_req_id!=held_store_id||store_backing_req_byte_address!=held_store_address||store_backing_req_data!==held_store_data||store_backing_req_word_mask!=held_store_mask)$fatal(1,"Held output packet changed");
   end
   store_held<=store_backing_req_valid&&!store_backing_req_ready;
   if(store_backing_req_valid&&!store_backing_req_ready)begin held_store_id<=store_backing_req_id;held_store_address<=store_backing_req_byte_address;held_store_data<=store_backing_req_data;held_store_mask<=store_backing_req_word_mask;end
   if(store_backing_rsp_valid&&store_backing_rsp_ready)begin acks+=provider_words[return_owner];block_acks[provider_block[return_owner]]+=provider_words[return_owner];end
   if(store_backing_req_valid&&store_backing_req_ready)begin
    int words,owner;words=0;owner=-1;
    if(store_backing_req_byte_address[4:0]||!store_backing_req_word_mask)$fatal(1,"Output sector contract");
    for(int w=0;w<8;w++)if(store_backing_req_word_mask[w])begin
     int index,row,col,block_id;index=int'(store_backing_req_byte_address+32'(4*w)-32'h200000)/4;row=index/96;col=index%96;block_id=3*(row/32)+col/32;
     if(index<0||index>=6144||seen[index])$fatal(1,"Output coverage/address mismatch");
     if(store_backing_req_data[32*w+:32]!==output_expected(row,col))$fatal(1,"Global output numerical mismatch");
     if(owner>=0&&owner!=block_id)$fatal(1,"Packet crosses block");owner=block_id;seen[index]=1;words++;stores++;
    end

   end
   if(block_launch_valid)begin
    int b;b=int'(block_launch_ordinal);
    if(b<0||b>=6||dispatched_seen[b]||block_launch_row!=b/3||block_launch_col!=b%3)$fatal(1,"Grid dispatch coordinate/identity");
    if(block_launch_sm>=6)$fatal(1,"Invalid dispatch SM");block_owner[b]=int'(block_launch_sm);sm_seen[block_launch_sm]=1;
    dispatched_seen[b]=1;dispatches++;
   end
   if(block_done_valid)begin
    int b;b=int'(block_done_ordinal);
    if(b<0||b>=6||!dispatched_seen[b]||done_seen[b]||block_done_row!=b/3||block_done_col!=b%3||block_acks[b]!=1024)$fatal(1,"Block completion before own acknowledgments");
    if(block_done_sm!=block_owner[b])$fatal(1,"Completion SM ownership changed");
    done_seen[b]=1;completed++;
   end
   if(resident_blocks>peak_resident)peak_resident=resident_blocks;
   if(done_valid&&(acks!=6144||completed!=6||dispatched_blocks!=6||completed_blocks!=6||resident_blocks!=0))$fatal(1,"Grid done before all output acks and retirement");
  end
 end
 calibration_connected_top #(.K(K),.SMS(6),.CONTEXTS(1),.L2_SETS(49152),.L2_WAYS(16),.READ_SLOTS(2),.RETURN_DELAY(28),.MOVM_LATENCY(29),.HMMA_LATENCY(32),.HMMA_INTERVAL(8))dut(.*);

 function automatic logic[31:0] dyadic(input integer n,input integer f);
  integer m,t;begin if(n==0)return 0;m=n<0?-n:n;t=0;while((m>>(t+1))!=0)t++;if(t>23)$fatal(1,"Oracle exact domain");return(n<0?32'h80000000:0)|(32'(127+t-f)<<23)|(32'(m-(1<<t))<<(23-t));end
 endfunction
 function automatic logic[15:0] memory_value(input logic[31:0]address);
  integer index,n;logic[31:0]v;
  begin if(address<32'h100000)begin index=int'(address)/2;if(index>=64*K)$fatal(1,"A bounds");n=index%17-8;end
   else begin index=int'(address-32'h100000)/2;if(index>=K*96)$fatal(1,"B bounds");n=index%13-6;end
   v=dyadic(n,4);return v[31:16];end
 endfunction
 function automatic logic[31:0] expected(input integer ctx,w,l,e);
  integer i,row,col,sum;
  begin i=native_bf16_layout::c_element_index(l,e);row=32*ctx+16*(w/2)+i/16;col=32*ctx+16*(w%2)+i%16;sum=0;
   for(int k=0;k<K;k++)sum+=((row*K+k)%17-8)*((k*96+col)%13-6);return dyadic(sum,8);end
 endfunction
 always @(posedge clk)begin
  if(rst)begin expected_elapsed<=0;elapsed_active<=0;end
  else if(launch_valid&&launch_ready)begin expected_elapsed<=0;elapsed_active<=1;end
  else if(elapsed_active)begin
   if(done_valid)begin if(elapsed_cycles!=expected_elapsed)$fatal(1,"Modeled elapsed-cycle mismatch actual%0d expected%0d",elapsed_cycles,expected_elapsed);elapsed_active<=0;end
   else expected_elapsed<=expected_elapsed+1;
  end
 end
 always @(posedge clk)begin
  cycle<=cycle+1;if(cycle>3000000)$fatal(1,"Reduction timeout");
  if(!rst)begin

   for(int sm=0;sm<6;sm++)if(sm_native_issue_valid[sm])sm_issued[sm]=1;
   if(resident_blocks<0||resident_blocks>6||resident_warps!=4*resident_blocks)$fatal(1,"Resource conservation");
  end
 end
 bit provider_live[4],provider_write[4];int provider_delay[4],provider_words[4],provider_block[4],provider_seq[4],next_provider_seq=0,return_owner=-1,free_read,free_write,provider_count;
 logic[31:0]provider_id[4],provider_address[4];
 always_comb begin
  free_read=-1;free_write=-1;provider_count=0;
  for(int i=0;i<4;i++)if(provider_live[i])provider_count++;else if(free_read<0)free_read=i;else if(free_write<0)free_write=i;
  pending=provider_count!=0;
  backing_req_ready=!rst&&free_read>=0&&cycle%3!=0;
  store_backing_req_ready=!rst&&(backing_req_valid&&backing_req_ready?free_write>=0:free_read>=0)&&cycle%5!=0;
  backing_rsp_valid=!rst&&return_owner>=0&&(return_owner>=0?!provider_write[return_owner]:0);
  store_backing_rsp_valid=!rst&&return_owner>=0&&(return_owner>=0?provider_write[return_owner]:0);
  backing_rsp_id=return_owner>=0?provider_id[return_owner]:0;store_backing_rsp_id=backing_rsp_id;backing_rsp_data=0;
  if(return_owner>=0&&!provider_write[return_owner])for(int h=0;h<16;h++)backing_rsp_data[16*h+:16]=memory_value(provider_address[return_owner]+32'(2*h));
 end
 always @(posedge clk)begin
  if(rst)begin return_owner<=-1;next_provider_seq<=0;backing_read_count<=0;for(int i=0;i<4;i++)begin provider_live[i]<=0;provider_delay[i]<=0;end end
  else begin
   for(int i=0;i<4;i++)if(provider_live[i]&&provider_delay[i]>0)provider_delay[i]<=provider_delay[i]-1;
   if(return_owner<0)begin int pick;pick=-1;for(int i=0;i<4;i++)if(provider_live[i]&&provider_delay[i]==0)if(pick<0||provider_seq[i]>provider_seq[pick])pick=i;return_owner<=pick;end
   if((backing_rsp_valid&&backing_rsp_ready)||(store_backing_rsp_valid&&store_backing_rsp_ready))begin provider_live[return_owner]<=0;return_owner<=-1;end
   if(backing_req_valid&&backing_req_ready)begin
    provider_live[free_read]<=1;provider_write[free_read]<=0;provider_id[free_read]<=backing_req_id;provider_address[free_read]<=backing_req_byte_address;provider_delay[free_read]<=next_provider_seq%2==0?31:9;provider_seq[free_read]<=next_provider_seq;backing_read_count<=backing_read_count+1;
   end
   if(store_backing_req_valid&&store_backing_req_ready)begin
    int slot,index,row,col,words;slot=backing_req_valid&&backing_req_ready?free_write:free_read;index=int'(store_backing_req_byte_address-32'h200000)/4;row=index/96;col=index%96;words=0;for(int w=0;w<8;w++)if(store_backing_req_word_mask[w])words++;
    provider_live[slot]<=1;provider_write[slot]<=1;provider_id[slot]<=store_backing_req_id;provider_address[slot]<=store_backing_req_byte_address;provider_delay[slot]<=17;provider_seq[slot]<=next_provider_seq+1;provider_words[slot]<=words;provider_block[slot]<=3*(row/32)+col/32;
   end
   next_provider_seq<=next_provider_seq+int'(backing_req_valid&&backing_req_ready)+int'(store_backing_req_valid&&store_backing_req_ready);
  end
 end
 task automatic clear_scoreboard;
  begin
   stores=0;acks=0;completed=0;dispatches=0;peak_resident=0;for(int sm=0;sm<6;sm++)begin sm_seen[sm]=0;sm_issued[sm]=0;end
   for(int b=0;b<6;b++)begin block_acks[b]=0;done_seen[b]=0;dispatched_seen[b]=0;end
   for(int i=0;i<6144;i++)seen[i]=0;
  end
 endtask
 task automatic offer(input integer id);
  begin @(negedge clk);launch_id=32'(id);a_base=0;b_base=32'h100000;c_base=32'h200000;launch_valid=1;#0.001;while(!launch_ready)@(negedge clk);@(negedge clk);launch_valid=0;a_base=32'hdead0000;b_base=32'hdead8000;c_base=32'hdeadf000;end
 endtask
 initial begin
  if($value$plusargs("hit_delay=%d",l2_hit_delay_cycles))begin end
  if($value$plusargs("setup_cycles=%d",kernel_setup_cycles))begin end
  if(kernel_setup_cycles<0)$fatal(1,"Negative setup delay");
  if(l2_hit_delay_cycles<0)$fatal(1,"Negative hit delay");
  repeat(3)@(negedge clk);rst=0;
  if($test$plusargs("misaligned_c")||$test$plusargs("c_overlap_a")||$test$plusargs("c_overlap_b")||$test$plusargs("c_overflow"))begin
   @(negedge clk);a_base=0;b_base=32'h100000;c_base=32'h200000;
   if($test$plusargs("misaligned_c"))c_base=32'h200002;
   if($test$plusargs("c_overlap_a"))c_base=0;
   if($test$plusargs("c_overlap_b"))c_base=32'h100000;
   if($test$plusargs("c_overflow"))c_base=32'hfffffffc;
   launch_valid=1;repeat(3)@(negedge clk);$fatal(1,"Invalid grid C launch was not rejected");
  end
  clear_scoreboard();offer(10);wait(pending);@(negedge clk);rst=1;repeat(2)@(negedge clk);
  if(pending||backing_rsp_valid||resident_blocks)$fatal(1,"Reset flush");rst=0;
  for(int replay=0;replay<2;replay++)begin
   clear_scoreboard();offer(20+replay);wait(done_valid);@(negedge clk);
   if(l2_read_requests!=l2_read_hits+l2_read_misses||l2_actual_fills!=backing_read_count||l2_read_misses!=l2_actual_fills+l2_merged_misses)$fatal(1,"L2 request/backing conservation");
   if(done_id!=20+replay||stores!=6144||acks!=6144||dispatches!=6||completed!=6||peak_resident!=6)$fatal(1,"Final grid identity/coverage/allocation");
   for(int sm=0;sm<6;sm++)if(!sm_seen[sm]||!sm_issued[sm])$fatal(1,"Active SM must receive its block");
   for(int i=0;i<6144;i++)if(!seen[i])$fatal(1,"Output hole");
   repeat(5)begin @(negedge clk);if(!done_valid||done_id!=20+replay||resident_blocks||elapsed_cycles!=expected_elapsed)$fatal(1,"Held grid completion");end
   done_ready=1;@(negedge clk);done_ready=0;grid_launches++;
   if(replay==0)begin local_cache_invalidate=1;@(negedge clk);local_cache_invalidate=0;end
   $display("RESIDENT_MULTI_SM_NB_L2_LAUNCH id=%0d words=%0d blocks=%0d peak_resident=%0d elapsed_cycles=%0d l2_requests=%0d l2_hits=%0d l2_misses=%0d l2_merges=%0d l2_fills=%0d",20+replay,stores,completed,peak_resident,elapsed_cycles,l2_read_requests,l2_read_hits,l2_read_misses,l2_merged_misses,l2_actual_fills);
  end
  $display("RESIDENT_MULTI_SM_NB_L2_PASS K=%0d checked_words=12288 launches=%0d",K,grid_launches);$finish;
 end
endmodule
