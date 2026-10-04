`timescale 1ns/1ps
module multi_sm_l2_gateway_tb;
 logic clk=0;always #0.05 clk=~clk;logic rst=1;
 logic[1:0]read_req_valid=0,read_req_ready,read_rsp_valid,read_rsp_ready=0,write_req_valid=0,write_req_ready,write_rsp_valid,write_rsp_ready=0;
 logic[31:0]read_req_id[2],read_req_byte_address[2],read_rsp_id[2],write_req_id[2],write_req_byte_address[2],write_rsp_id[2];
 logic[255:0]read_rsp_data[2],write_req_data[2];logic[7:0]write_req_word_mask[2];
 logic backing_req_valid,backing_req_ready,backing_rsp_valid,backing_rsp_ready,store_backing_req_valid,store_backing_req_ready,store_backing_rsp_valid,store_backing_rsp_ready;
 logic[31:0]backing_req_id,backing_req_byte_address,backing_rsp_id,store_backing_req_id,store_backing_req_byte_address,store_backing_rsp_id;logic[255:0]backing_rsp_data,store_backing_req_data;logic[7:0]store_backing_req_word_mask;
 int l2_read_requests,l2_read_hits,l2_read_misses,cycle=0,wait_left=0,backing_reads=0,writes=0,checked=0;bit pending=0,is_write=0,wrong=0;logic[31:0]saved_id,saved_address;
 multi_sm_l2_gateway #(.L2_SETS(1),.L2_WAYS(1))dut(.*);
 assign backing_req_ready=!rst&&!pending&&(cycle%3!=0);assign store_backing_req_ready=!rst&&!pending&&(cycle%3!=0);
 assign backing_rsp_valid=!rst&&pending&&!is_write&&wait_left==0;assign store_backing_rsp_valid=!rst&&pending&&is_write&&wait_left==0;
 assign backing_rsp_id=saved_id+(wrong?1:0);assign store_backing_rsp_id=saved_id;
 always_comb for(int w=0;w<8;w++)backing_rsp_data[32*w+:32]=(saved_address+32'(4*w))^32'h56780000;
 always @(posedge clk)begin
  cycle<=cycle+1;if(cycle>5000)$fatal(1,"L2 gateway timeout");
  if(rst)begin pending<=0;wait_left<=0;backing_reads<=0;writes<=0;end
  else begin
   if(backing_req_valid&&backing_req_ready&&store_backing_req_valid&&store_backing_req_ready)$fatal(1,"Combined backing overlap");
   if(backing_req_valid&&backing_req_ready)begin pending<=1;is_write<=0;saved_id<=backing_req_id;saved_address<=backing_req_byte_address;wait_left<=7;backing_reads<=backing_reads+1;end
   if(store_backing_req_valid&&store_backing_req_ready)begin
    if(store_backing_req_byte_address!=256||store_backing_req_word_mask!=8'h55)$fatal(1,"Masked output contract");
    for(int w=0;w<8;w++)if(store_backing_req_data[32*w+:32]!==32'h12340000+32'(w))$fatal(1,"Write snapshot");
    pending<=1;is_write<=1;saved_id<=store_backing_req_id;saved_address<=store_backing_req_byte_address;wait_left<=7;writes<=writes+1;
   end
   if(pending&&wait_left>0)wait_left<=wait_left-1;
   if((backing_rsp_valid&&backing_rsp_ready)||(store_backing_rsp_valid&&store_backing_rsp_ready))pending<=0;
  end
 end
 task automatic read_sector(input integer sm,address);
  begin
   @(negedge clk);read_req_id[sm]=42;read_req_byte_address[sm]=32'(address);read_req_valid[sm]=1;#0.001;while(!read_req_ready[sm])@(negedge clk);@(negedge clk);read_req_valid[sm]=0;read_req_byte_address[sm]='1;
   wait(read_rsp_valid[sm]);@(negedge clk);
   repeat(4)begin
    if(!read_rsp_valid[sm]||read_rsp_id[sm]!=42)$fatal(1,"Held read owner");
    for(int w=0;w<8;w++)if(read_rsp_data[sm][32*w+:32]!==((32'(address+4*w))^32'h56780000))$fatal(1,"L2 sector payload");@(negedge clk);
   end
   checked+=8;read_rsp_ready[sm]=1;@(negedge clk);read_rsp_ready[sm]=0;
  end
 endtask
 initial begin
  wrong=$test$plusargs("wrong_id");for(int sm=0;sm<2;sm++)begin read_req_id[sm]=42;read_req_byte_address[sm]=0;write_req_id[sm]=42;write_req_byte_address[sm]=256;write_req_word_mask[sm]=8'h55;for(int w=0;w<8;w++)write_req_data[sm][32*w+:32]=32'h12340000+32'(w);end
  repeat(3)@(negedge clk);rst=0;read_req_valid[0]=1;#0.001;while(!read_req_ready[0])@(negedge clk);@(negedge clk);read_req_valid=0;wait(pending);@(negedge clk);rst=1;repeat(2)@(negedge clk);if(pending||backing_rsp_valid)$fatal(1,"Reset flush");rst=0;
  read_sector(0,0);if(backing_reads!=1||l2_read_hits!=0||l2_read_misses!=1)$fatal(1,"Initial miss counts");
  read_sector(1,0);if(backing_reads!=1||l2_read_hits!=1||l2_read_misses!=1)$fatal(1,"Cross SM hit counts");
  read_sector(1,32);if(backing_reads!=2)$fatal(1,"Different sector must miss");
  read_sector(1,128);if(backing_reads!=3)$fatal(1,"Different line eviction miss");
  read_sector(0,0);if(backing_reads!=4||l2_read_requests!=5||l2_read_hits!=1||l2_read_misses!=4)$fatal(1,"Eviction refetch counts");
  @(negedge clk);write_req_valid[1]=1;#0.001;while(!write_req_ready[1])@(negedge clk);@(negedge clk);write_req_valid=0;write_req_data[1]='1;write_req_word_mask[1]=0;
  wait(write_rsp_valid[1]);@(negedge clk);if(write_rsp_id[1]!=42)$fatal(1,"Write owner");write_rsp_ready[1]=1;@(negedge clk);write_rsp_ready=0;
  if(writes!=1||l2_read_requests!=5||l2_read_hits!=1||l2_read_misses!=4)$fatal(1,"Write changed read cache counters");
  $display("MULTI_SM_L2_PASS checked_words=%0d hits=%0d misses=%0d backing_reads=%0d",checked,l2_read_hits,l2_read_misses,backing_reads);$finish;
 end
endmodule
