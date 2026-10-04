`timescale 1ns/1ps
module multi_sm_sector_gateway_tb;
 logic clk=0;always #0.05 clk=~clk;logic rst=1;
 logic[1:0]read_req_valid=0,read_req_ready,read_rsp_valid,read_rsp_ready=0,write_req_valid=0,write_req_ready,write_rsp_valid,write_rsp_ready=0;
 logic[31:0]read_req_id[2],read_req_byte_address[2],read_rsp_id[2],write_req_id[2],write_req_byte_address[2],write_rsp_id[2];
 logic[255:0]read_rsp_data[2],write_req_data[2];logic[7:0]write_req_word_mask[2];
 logic backing_req_valid,backing_req_ready,backing_rsp_valid,backing_rsp_ready,store_backing_req_valid,store_backing_req_ready,store_backing_rsp_valid,store_backing_rsp_ready;
 logic[31:0]backing_req_id,backing_req_byte_address,backing_rsp_id,store_backing_req_id,store_backing_req_byte_address,store_backing_rsp_id;logic[255:0]backing_rsp_data,store_backing_req_data;logic[7:0]store_backing_req_word_mask;
 int cycle=0,wait_left=0,checked=0;bit pending=0,is_write=0,wrong=0;logic[31:0]saved_id,saved_address;
 bit held_read=0,held_write=0;logic[31:0]held_read_id,held_read_address,held_write_id,held_write_address;logic[255:0]held_write_data;logic[7:0]held_write_mask;
 bit accepted_read[2],accepted_write[2],retired_read[2],retired_write[2];
 multi_sm_sector_gateway dut(.*);
 assign backing_req_ready=!rst&&!pending&&(cycle%3!=0);assign store_backing_req_ready=!rst&&!pending&&(cycle%3!=0);
 assign backing_rsp_valid=!rst&&pending&&!is_write&&wait_left==0;assign store_backing_rsp_valid=!rst&&pending&&is_write&&wait_left==0;
 assign backing_rsp_id=saved_id+(wrong?1:0);assign store_backing_rsp_id=saved_id+(wrong?1:0);
 always_comb begin for(int w=0;w<8;w++)backing_rsp_data[32*w+:32]=saved_address+32'(4*w)^32'h56780000;end
 always @(posedge clk)begin
  cycle<=cycle+1;if(cycle>5000)$fatal(1,"Gateway timeout");
  if(rst)begin held_read<=0;held_write<=0;pending<=0;wait_left<=0;for(int s=0;s<2;s++)begin accepted_read[s]=0;accepted_write[s]=0;retired_read[s]=0;retired_write[s]=0;end end
  else begin
   if(held_read&&(!backing_req_valid||backing_req_id!=held_read_id||backing_req_byte_address!=held_read_address))$fatal(1,"Held backing read changed");
   if(held_write&&(!store_backing_req_valid||store_backing_req_id!=held_write_id||store_backing_req_byte_address!=held_write_address||store_backing_req_data!==held_write_data||store_backing_req_word_mask!=held_write_mask))$fatal(1,"Held backing write changed");
   held_read<=backing_req_valid&&!backing_req_ready;held_write<=store_backing_req_valid&&!store_backing_req_ready;
   if(backing_req_valid&&!backing_req_ready)begin held_read_id<=backing_req_id;held_read_address<=backing_req_byte_address;end
   if(store_backing_req_valid&&!store_backing_req_ready)begin held_write_id<=store_backing_req_id;held_write_address<=store_backing_req_byte_address;held_write_data<=store_backing_req_data;held_write_mask<=store_backing_req_word_mask;end
   if(backing_req_valid&&backing_req_ready&&store_backing_req_valid&&store_backing_req_ready)$fatal(1,"Read/write overlap accepted");
   if(backing_req_valid&&backing_req_ready)begin pending<=1;is_write<=0;saved_id<=backing_req_id;saved_address<=backing_req_byte_address;wait_left<=7;end
   if(store_backing_req_valid&&store_backing_req_ready)begin
    int s;s=int'(store_backing_req_byte_address)/32-8;
    if(s<0||s>=2||store_backing_req_word_mask!=8'h55)$fatal(1,"Write snapshot mask/address");
    for(int w=0;w<8;w++)if(store_backing_req_data[32*w+:32]!==32'h12340000+32'(256*s+w))$fatal(1,"Write data snapshot");
    pending<=1;is_write<=1;saved_id<=store_backing_req_id;saved_address<=store_backing_req_byte_address;wait_left<=7;
   end
   if(pending&&wait_left>0)wait_left<=wait_left-1;
   if((backing_rsp_valid&&backing_rsp_ready)||(store_backing_rsp_valid&&store_backing_rsp_ready))pending<=0;
   for(int s=0;s<2;s++)begin
    if(read_req_valid[s]&&read_req_ready[s])begin if(accepted_read[s])$fatal(1,"Repeated read acceptance");accepted_read[s]=1;end
    if(write_req_valid[s]&&write_req_ready[s])begin if(accepted_write[s])$fatal(1,"Repeated write acceptance");accepted_write[s]=1;end
    if(read_rsp_valid[s])begin
     if(!accepted_read[s]||read_rsp_id[s]!=42)$fatal(1,"Read client identity");
     for(int w=0;w<8;w++)if(read_rsp_data[s][32*w+:32]!==((32'(32*s+4*w))^32'h56780000))$fatal(1,"Read client data");
    end
    if(read_rsp_valid[s]&&read_rsp_ready[s])begin if(retired_read[s])$fatal(1,"Repeated read completion");retired_read[s]=1;checked+=8;end
    if(write_rsp_valid[s]&&(!accepted_write[s]||write_rsp_id[s]!=42))$fatal(1,"Held write client identity");
    if(write_rsp_valid[s]&&write_rsp_ready[s])begin if(!accepted_write[s]||retired_write[s]||write_rsp_id[s]!=42)$fatal(1,"Write client identity");retired_write[s]=1;end
   end
  end
 end
 initial begin
  wrong=$test$plusargs("wrong_id");for(int s=0;s<2;s++)begin read_req_id[s]=42;read_req_byte_address[s]=32'(32*s);write_req_id[s]=42;write_req_byte_address[s]=32'(256+32*s);write_req_word_mask[s]=8'h55;for(int w=0;w<8;w++)write_req_data[s][32*w+:32]=32'h12340000+32'(256*s+w);end
  repeat(3)@(negedge clk);rst=0;read_req_valid[0]=1;#0.001;while(!read_req_ready[0])@(negedge clk);@(negedge clk);read_req_valid=0;wait(pending);@(negedge clk);rst=1;repeat(2)@(negedge clk);if(pending||backing_rsp_valid||store_backing_rsp_valid)$fatal(1,"Provider reset flush");rst=0;
  read_req_valid=3;write_req_valid=3;
  begin bit finished;finished=0;
   while(!finished)begin
    logic[1:0]rg,wg;#0.001;rg=read_req_valid&read_req_ready;wg=write_req_valid&write_req_ready;@(negedge clk);
    for(int s=0;s<2;s++)begin if(rg[s])begin read_req_valid[s]=0;read_req_byte_address[s]='1;end if(wg[s])begin write_req_valid[s]=0;write_req_data[s]='1;write_req_word_mask[s]=0;end end
    if(cycle%11==0)begin read_rsp_ready=3;write_rsp_ready=3;end else begin read_rsp_ready=0;write_rsp_ready=0;end
    finished=retired_read[0]&&retired_read[1]&&retired_write[0]&&retired_write[1];
   end
  end
  if(checked!=16)$fatal(1,"Gateway coverage");$display("MULTI_SM_GATEWAY_PASS checked_words=%0d",checked);$finish;
 end
endmodule
