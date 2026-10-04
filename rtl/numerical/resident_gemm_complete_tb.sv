`timescale 1ns/1ps
module resident_gemm_complete_tb #(parameter int K=64);
 logic clk=0;always #0.05 clk=~clk;logic rst=1,launch_valid=0,launch_ready,done_valid,done_ready=0;
 logic[31:0]launch_id=0,a_base=0,b_base=32'h100000,c_base=32'h200000,cta_row=0,cta_col=0,done_id,done_context,result_registers[4][32][8];
 logic backing_req_valid,backing_req_ready,backing_rsp_valid=0,backing_rsp_ready;
 logic[31:0]backing_req_id,backing_req_byte_address,backing_rsp_id;logic[255:0]backing_rsp_data;
 int resident_blocks,resident_warps,cycle=0,delay_left=0,checked=0;bit pending=0;
 logic[31:0]pending_id,pending_address;logic native_issue_valid;logic[31:0]native_issue_context,native_issue_warp,native_issue_pc;
 int issues[2],producer_releases[2],consumer_releases[2];bit read_contention=0,write_contention=0;logic[31:0]held[4][32][8];
 logic store_backing_req_valid,store_backing_req_ready,store_backing_rsp_valid,store_backing_rsp_ready;
 logic[31:0]store_backing_req_id,store_backing_req_byte_address,store_backing_rsp_id;
 logic[255:0]store_backing_req_data;logic[7:0]store_backing_req_word_mask;
 bit store_pending=0,store_held=0,seen[6144],done_seen[6];int store_wait=0,stores=0,acks=0,block_acks[6],completed=0;
 logic[31:0]saved_store_id,held_store_id,held_store_address;logic[255:0]held_store_data;logic[7:0]held_store_mask;int pending_block,pending_words;
 assign store_backing_req_ready=!rst&&!store_pending&&(cycle%5==0);
 assign store_backing_rsp_valid=!rst&&store_pending&&store_wait==0;
 assign store_backing_rsp_id=saved_store_id;
 function automatic logic[31:0] output_expected(input integer row,col);
  integer sum;begin sum=0;for(int k=0;k<K;k++)sum+=((row*K+k)%17-8)*((k*96+col)%13-6);return dyadic(sum,8);end
 endfunction
 always @(posedge clk)begin
  if(rst)begin store_pending<=0;store_held<=0;stores=0;acks=0;completed=0;for(int b=0;b<6;b++)begin block_acks[b]=0;done_seen[b]=0;end for(int i=0;i<6144;i++)seen[i]=0;end
  else begin
   if(store_held)begin
    if(!store_backing_req_valid||store_backing_req_id!=held_store_id||store_backing_req_byte_address!=held_store_address||store_backing_req_data!==held_store_data||store_backing_req_word_mask!=held_store_mask)$fatal(1,"Held output packet changed");
   end
   store_held<=store_backing_req_valid&&!store_backing_req_ready;
   if(store_backing_req_valid&&!store_backing_req_ready)begin held_store_id<=store_backing_req_id;held_store_address<=store_backing_req_byte_address;held_store_data<=store_backing_req_data;held_store_mask<=store_backing_req_word_mask;end
   if(store_pending&&store_wait>0)store_wait<=store_wait-1;
   if(store_backing_rsp_valid&&store_backing_rsp_ready)begin store_pending<=0;acks+=pending_words;block_acks[pending_block]+=pending_words;end
   if(store_backing_req_valid&&store_backing_req_ready)begin
    int words,owner;words=0;owner=-1;
    if(store_backing_req_byte_address[4:0]||!store_backing_req_word_mask)$fatal(1,"Output sector contract");
    for(int w=0;w<8;w++)if(store_backing_req_word_mask[w])begin
     int index,row,col,block_id;index=int'(store_backing_req_byte_address+32'(4*w)-32'h200000)/4;row=index/96;col=index%96;block_id=3*(row/32)+col/32;
     if(index<0||index>=6144||seen[index])$fatal(1,"Output coverage/address mismatch");
     if(store_backing_req_data[32*w+:32]!==output_expected(row,col))$fatal(1,"Global output numerical mismatch");
     if(owner>=0&&owner!=block_id)$fatal(1,"Packet crosses block");owner=block_id;seen[index]=1;words++;stores++;
    end
    pending_block=owner;pending_words=words;saved_store_id<=store_backing_req_id;store_wait<=11;store_pending<=1;
   end
   if(done_valid)begin int b;b=int'(done_id)-20;if(b<0||b>=6||block_acks[b]!=1024)$fatal(1,"Done before own output acks");end
   if(done_valid&&done_ready)begin int b;b=int'(done_id)-20;if(done_seen[b])$fatal(1,"Duplicate block done");done_seen[b]=1;completed++;end
  end
 end
 resident_gemm_complete #(.K(K),.READ_SLOTS(2),.RETURN_DELAY(9),.MOVM_LATENCY(19),.HMMA_LATENCY(73))dut(.*);
 assign backing_req_ready=!rst&&!pending&&!backing_rsp_valid&&(cycle%4!=0);
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
  cycle<=cycle+1;if(cycle>3000000)$fatal(1,"Reduction timeout");
  if(rst)begin pending<=0;backing_rsp_valid<=0;delay_left<=0;for(int c=0;c<2;c++)begin issues[c]=0; end end
  else begin
   if(backing_req_valid&&backing_req_ready)begin pending<=1;pending_id<=backing_req_id;pending_address<=backing_req_byte_address;delay_left<=5;if(backing_req_byte_address[4:0])$fatal(1,"Sector alignment");end
   if(pending)if(delay_left>0)delay_left<=delay_left-1;else begin pending<=0;backing_rsp_valid<=1;backing_rsp_id<=pending_id;for(int h=0;h<16;h++)backing_rsp_data[16*h+:16]<=memory_value(pending_address+32'(2*h));end
   if(backing_rsp_valid&&backing_rsp_ready)backing_rsp_valid<=0;
   if(native_issue_valid)begin if(native_issue_context>=2)$fatal(1,"Trace context");issues[native_issue_context]++;end
   if(resident_blocks<0||resident_blocks>2||resident_warps!=4*resident_blocks)$fatal(1,"Resource conservation");
  end
 end
 task automatic offer(input integer ctx,id);
  begin @(negedge clk);launch_id=32'(id);cta_row=32'(ctx/3);cta_col=32'(ctx%3);a_base=0;b_base=32'h100000;c_base=32'h200000;launch_valid=1;#0.001;while(!launch_ready)@(negedge clk);@(negedge clk);launch_valid=0;cta_row=99;cta_col=99;a_base=32'hdead0000;b_base=32'hdead8000;c_base=32'hdeadf000;end
 endtask
 generate for(genvar c=0;c<2;c++)begin:barrier_checks
  always @(posedge clk)begin
   if(rst)begin producer_releases[c]=0;consumer_releases[c]=0;end
   else begin
    if(dut.producer_release_valid[c])begin
     if(dut.barriers[c].prod_generation!=dut.stage_number[c]||dut.barriers[c].prod_release_mask!=4'b1111)$fatal(1,"Producer generation/mask mismatch");producer_releases[c]++;
    end
    if(dut.consumer_release_valid[c])begin
     if(dut.barriers[c].cons_generation!=dut.stage_number[c]||dut.barriers[c].cons_release_mask!=4'b1111)$fatal(1,"Consumer generation/mask mismatch");consumer_releases[c]++;
    end
   end
  end
 end endgenerate
 always @(posedge clk)begin
  if(rst)begin read_contention<=0;write_contention<=0;end
  else begin
   if(dut.read_candidate_valid==2'b11)read_contention<=1;
   if(dut.write_warp_valid&&dut.scratch_store_candidate)write_contention<=1;
  end
 end
 initial begin
  repeat(3)@(negedge clk);rst=0;
  if($test$plusargs("misaligned_c")||$test$plusargs("c_overlap_a")||$test$plusargs("c_overlap_b")||$test$plusargs("c_overflow"))begin
   @(negedge clk);a_base=0;b_base=32'h100000;c_base=32'h200000;
   if($test$plusargs("misaligned_c"))c_base=32'h200002;
   if($test$plusargs("c_overlap_a"))c_base=0;
   if($test$plusargs("c_overlap_b"))c_base=32'h100000;
   if($test$plusargs("c_overflow"))c_base=32'hfffffffc;
   launch_valid=1;repeat(3)@(negedge clk);$fatal(1,"Invalid C launch was not rejected");
  end
  offer(0,10);wait(pending);@(negedge clk);rst=1;repeat(2)@(negedge clk);if(pending||backing_rsp_valid||resident_blocks)$fatal(1,"Reset flush");rst=0;
  fork
   begin for(int block_id=0;block_id<6;block_id++)offer(block_id,20+block_id);end
   begin
    wait(done_valid);@(negedge clk);
    begin logic[31:0]first_id,first_context;first_id=done_id;first_context=done_context;
     for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)held[w][l][e]=result_registers[w][l][e];
     repeat(200)begin @(negedge clk);if(!done_valid||done_id!=first_id||done_context!=first_context)$fatal(1,"Held completion changed");
      for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)if(result_registers[w][l][e]!==held[w][l][e])$fatal(1,"Held final data changed");
     end
    end
    done_ready=1;wait(completed==6);@(negedge clk);done_ready=0;
   end
  join
  repeat(3)@(negedge clk);if(resident_blocks||resident_warps||stores!=6144||acks!=6144)$fatal(1,"Final grid conservation");
  if(producer_releases[0]+producer_releases[1]!=6*(K/32)||consumer_releases[0]+consumer_releases[1]!=6*(K/32))$fatal(1,"Missing barrier generations");
  $display("RESIDENT_COMPLETE_CONTENTION read=%0d write=%0d",read_contention,write_contention);
  for(int i=0;i<6144;i++)if(!seen[i])$fatal(1,"Output hole");
  $display("RESIDENT_COMPLETE_PASS K=%0d checked_words=%0d completed=%0d",K,stores,completed);$finish;
 end
endmodule
