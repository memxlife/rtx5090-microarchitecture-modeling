`timescale 1ns/1ps
module multi_sm_nonblocking_l2_tb;
 logic clk=0;always #0.05 clk=~clk;logic rst=1;
 logic[3:0]read_req_valid=0,read_req_ready,read_rsp_valid,read_rsp_ready=0,write_req_valid=0,write_req_ready,write_rsp_valid,write_rsp_ready=0;
 logic[31:0]read_req_id[4],read_req_byte_address[4],read_rsp_id[4],write_req_id[4],write_req_byte_address[4],write_rsp_id[4];logic[255:0]read_rsp_data[4],write_req_data[4];logic[7:0]write_req_word_mask[4];
 logic backing_req_valid,backing_req_ready=1,backing_rsp_valid=0,backing_rsp_ready,store_backing_req_valid,store_backing_req_ready=1,store_backing_rsp_valid=0,store_backing_rsp_ready;
 logic[31:0]backing_req_id,backing_req_byte_address,backing_rsp_id,store_backing_req_id,store_backing_req_byte_address,store_backing_rsp_id;logic[255:0]backing_rsp_data,store_backing_req_data;logic[7:0]store_backing_req_word_mask;
 int l2_read_requests,l2_read_hits,l2_read_misses,l2_merged_misses,l2_actual_fills,live_owners,live_mshrs,peak_owners,peak_mshrs,cycle=0,fetches=0,writefetches=0,checked=0;
 logic[31:0]fetch_id[8],fetch_address[8],write_id;bit wrong,r3accepted=0;
 multi_sm_nonblocking_l2 #(.SMS(4),.L2_SETS(1),.L2_WAYS(2),.OWNER_SLOTS(4),.MSHRS(2))dut(.*);
 always @(posedge clk)begin
  cycle<=cycle+1;if(cycle>5000)$fatal(1,"Nonblocking L2 timeout");
  if(rst)begin r3accepted=0;fetches=0;writefetches=0;end
  else begin
   for(int sm=0;sm<4;sm++)if(read_req_valid[sm]&&read_req_ready[sm])$display("NB_READ_ACCEPT cycle=%0d sm=%0d id=%0d address=%h",cycle,sm,read_req_id[sm],read_req_byte_address[sm]);
   if(read_req_valid[3]&&read_req_ready[3])r3accepted=1;
   if(backing_req_valid&&backing_req_ready)begin fetch_id[fetches]=backing_req_id;fetch_address[fetches]=backing_req_byte_address;fetches++;end
   if(store_backing_req_valid&&store_backing_req_ready)begin
    if(store_backing_req_byte_address!=1024||store_backing_req_word_mask!=8'h55)$fatal(1,"Write snapshot mask/address");
    for(int w=0;w<8;w++)if(store_backing_req_data[32*w+:32]!==32'h12340000+32'(w))$fatal(1,"Write snapshot data");write_id=store_backing_req_id;writefetches++;
   end
   if(live_owners<0||live_owners>4||live_mshrs<0||live_mshrs>2)$fatal(1,"Owner/MSHR bound");
  end
 end
 always @(negedge clk)if(r3accepted)read_req_valid[3]=0;
 task automatic submit_read(input integer sm,address);
  begin @(negedge clk);read_req_byte_address[sm]=32'(address);read_req_id[sm]=42;read_req_valid[sm]=1;begin bit taken;taken=0;while(!taken)begin @(posedge clk);taken=read_req_ready[sm];end end @(negedge clk);read_req_valid[sm]=0;read_req_byte_address[sm]='1;end
 endtask
 task automatic return_read(input integer which);
  begin @(negedge clk);backing_rsp_id=fetch_id[which]+(wrong?1:0);for(int w=0;w<8;w++)backing_rsp_data[32*w+:32]=(fetch_address[which]+32'(4*w))^32'h56780000;backing_rsp_valid=1;begin bit taken;taken=0;while(!taken)begin @(posedge clk);taken=backing_rsp_ready;end end @(negedge clk);backing_rsp_valid=0;end
 endtask
 task automatic check_read(input integer sm,address);
  begin wait(read_rsp_valid[sm]);@(negedge clk);if(read_rsp_id[sm]!=42)$fatal(1,"Read client owner");for(int w=0;w<8;w++)begin if(read_rsp_data[sm][32*w+:32]!==((32'(address+4*w))^32'h56780000))$fatal(1,"Read packet oracle");checked++;end end
 endtask
 initial begin
  wrong=$test$plusargs("wrong_id");for(int sm=0;sm<4;sm++)begin read_req_id[sm]=42;read_req_byte_address[sm]=0;write_req_id[sm]=42;write_req_byte_address[sm]=1024;write_req_word_mask[sm]=8'h55;for(int w=0;w<8;w++)write_req_data[sm][32*w+:32]=32'h12340000+32'(w);end
  repeat(3)@(negedge clk);rst=0;submit_read(0,0);wait(fetches==1);@(negedge clk);rst=1;repeat(2)@(negedge clk);if(live_owners||live_mshrs)$fatal(1,"Reset cancellation");rst=0;
  submit_read(0,0);submit_read(1,128);wait(fetches==2);submit_read(2,0);
  @(negedge clk);write_req_valid[3]=1;begin bit taken;taken=0;while(!taken)begin @(posedge clk);taken=write_req_ready[3];end end @(negedge clk);write_req_valid[3]=0;write_req_data[3]='1;write_req_word_mask[3]=0;wait(writefetches==1);
  @(negedge clk);read_req_valid[3]=1;read_req_byte_address[3]=256;repeat(3)begin #0.001;if(read_req_ready[3])$fatal(1,"Saturated owners accepted new miss");@(negedge clk);end
  store_backing_rsp_id=write_id;store_backing_rsp_valid=1;begin bit taken;taken=0;while(!taken)begin @(posedge clk);taken=store_backing_rsp_ready;end end @(negedge clk);store_backing_rsp_valid=0;wait(write_rsp_valid[3]);@(negedge clk);if(write_rsp_id[3]!=42)$fatal(1,"Write external ID");write_rsp_ready[3]=1;@(negedge clk);write_rsp_ready=0;
  repeat(3)begin #0.001;if(read_req_ready[3])$fatal(1,"Pinned ways/MSHR accepted replacement");@(negedge clk);end
  // Return second physical miss first; its released way lets the stalled miss proceed.
  return_read(1);check_read(1,128);read_rsp_ready[1]=1;@(negedge clk);read_rsp_ready[1]=0;
  wait(r3accepted);@(negedge clk);read_req_valid[3]=0;wait(fetches==3);
  return_read(0);check_read(0,0);check_read(2,0);
  return_read(2);check_read(3,256);read_rsp_ready[2]=1;read_rsp_ready[3]=1;@(negedge clk);read_rsp_ready=0;
  repeat(4)begin @(negedge clk);if(!read_rsp_valid[0]||read_rsp_id[0]!=42)$fatal(1,"Held owner0 blocked/changed");for(int w=0;w<8;w++)if(read_rsp_data[0][32*w+:32]!==((32'(4*w))^32'h56780000))$fatal(1,"Held packet0");end
  read_rsp_ready[0]=1;@(negedge clk);read_rsp_ready=0;
  submit_read(1,0);check_read(1,0);read_rsp_ready[1]=1;@(negedge clk);read_rsp_ready=0;repeat(3)@(negedge clk);
  // New waiter joins on the exact physical refill acceptance edge.
  submit_read(0,512);wait(fetches==4);@(negedge clk);
  read_req_id[1]=42;read_req_byte_address[1]=512;read_req_valid[1]=1;
  backing_rsp_id=fetch_id[3];for(int w=0;w<8;w++)backing_rsp_data[32*w+:32]=(32'(512+4*w))^32'h56780000;backing_rsp_valid=1;
  #0.001;if(!read_req_ready[1]||!backing_rsp_ready)$fatal(1,"Refill-edge merge was not admitted");
  @(negedge clk);read_req_valid[1]=0;backing_rsp_valid=0;
  check_read(0,512);check_read(1,512);read_rsp_ready[0]=1;read_rsp_ready[1]=1;@(negedge clk);read_rsp_ready=0;repeat(3)@(negedge clk);
  if(fetches!=4||l2_read_requests!=7||l2_read_hits!=1||l2_read_misses!=6||l2_merged_misses!=2||l2_actual_fills!=4||live_owners||live_mshrs||peak_owners!=4||peak_mshrs!=2)$fatal(1,"Final logical/physical conservation");
  $display("NONBLOCKING_L2_PASS checked_words=%0d requests=%0d fills=%0d merged=%0d",checked,l2_read_requests,l2_actual_fills,l2_merged_misses);$finish;
 end
endmodule
