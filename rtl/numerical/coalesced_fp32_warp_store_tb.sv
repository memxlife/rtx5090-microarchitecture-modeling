module coalesced_fp32_warp_store_tb;
 logic clk=0,rst=1;always #5 clk=~clk;
 logic req_valid=0,req_ready,rsp_valid,rsp_ready=0;logic[31:0]req_id=0,rsp_id,active_mask=0,byte_addresses[32],words[32];int sector_count;
 logic backing_req_valid,backing_req_ready,backing_rsp_valid=0,backing_rsp_ready;
 logic[31:0]backing_req_id,backing_req_byte_address,backing_rsp_id=0;logic[255:0]backing_req_data;logic[7:0]backing_req_word_mask;
 logic[31:0]memory[4096],expected[4096];logic pending=0;logic[31:0]pending_id;int cycles=0,delay=0,requests=0,acks=0,checked=0,cases=0;
 logic[31:0]held_address,held_id;logic[255:0]held_data;logic[7:0]held_mask;logic held=0;
 coalesced_fp32_warp_store dut(.*);
 assign backing_req_ready=!rst&&!pending&&!backing_rsp_valid&&(cycles%4==0);
 always @(posedge clk)begin
  if(rst)begin cycles<=0;pending<=0;delay<=0;backing_rsp_valid<=0;requests<=0;acks<=0;held<=0;end
  else begin
   cycles<=cycles+1;
   if(backing_req_valid&&!backing_req_ready)begin
    if(held&&(held_address!=backing_req_byte_address||held_id!=backing_req_id||held_data!=backing_req_data||held_mask!=backing_req_word_mask))$fatal(1,"Backing store payload changed while held");
    held<=1;held_address<=backing_req_byte_address;held_id<=backing_req_id;held_data<=backing_req_data;held_mask<=backing_req_word_mask;
   end else held<=0;
   if(backing_req_valid&&backing_req_ready)begin
    if(backing_req_byte_address[4:0]!=0||backing_req_byte_address>=16384)$fatal(1,"Bad backing sector address");
    requests<=requests+1;pending<=1;pending_id<=backing_req_id;delay<=5;
    for(int word=0;word<8;word++)if(backing_req_word_mask[word])memory[backing_req_byte_address/4+word]<=backing_req_data[word*32+:32];
   end
   if(pending)begin
    if(delay>0)delay<=delay-1;
    else begin pending<=0;backing_rsp_valid<=1;backing_rsp_id<=$test$plusargs("wrong_id")?pending_id+1:pending_id;end
   end
   if(backing_rsp_valid&&backing_rsp_ready)begin backing_rsp_valid<=0;acks<=acks+1;end
   if(rsp_valid&&acks!=requests)$fatal(1,"Store done before actual acknowledgement");
  end
 end
 task tick;@(posedge clk);#1;endtask
 task run_case(input int id,sectors);
  int before_requests;before_requests=requests;
  for(int lane=0;lane<32;lane++)if(active_mask[lane])expected[byte_addresses[lane]/4]=words[lane];
  @(negedge clk);req_id=32'(id);req_valid=1;#1;if(!req_ready)$fatal(1,"Store not ready");tick();
  @(negedge clk);req_valid=0;active_mask=0;for(int lane=0;lane<32;lane++)begin byte_addresses[lane]=1;words[lane]=0;end
  while(!rsp_valid)tick();
  if(rsp_id!=id||sector_count!=sectors||requests-before_requests!=sectors)$fatal(1,"Store sector/identity mismatch");
  for(int word=0;word<4096;word++)if(memory[word]!==expected[word])$fatal(1,"Memory mismatch word%0d",word);checked+=4096;cases++;
  repeat(4)begin tick();if(!rsp_valid||req_ready)$fatal(1,"Store done not held");end
  @(negedge clk);rsp_ready=1;tick();@(negedge clk);rsp_ready=0;
 endtask
 initial begin
  for(int i=0;i<4096;i++)begin memory[i]=32'hcafebabe;expected[i]=32'hcafebabe;end
  for(int lane=0;lane<32;lane++)begin byte_addresses[lane]=0;words[lane]=0;end
  tick();@(negedge clk);rst=0;
  if($test$plusargs("unaligned"))begin active_mask=1;byte_addresses[0]=2;req_valid=1;tick();$fatal(1,"Missing alignment rejection");end
  if($test$plusargs("duplicate"))begin active_mask=3;req_valid=1;tick();$fatal(1,"Missing duplicate rejection");end
  for(int lane=0;lane<32;lane++)begin byte_addresses[lane]=32'h1000+32'(4*lane);words[lane]=32'h12340000+32'(lane);end active_mask='1;run_case(1,4);
  // One native C register per lane covers eight rows x four columns in16-column stride.
  for(int lane=0;lane<32;lane++)begin byte_addresses[lane]=32'h2000+32'(4*((lane/4)*16+2*(lane%4)));words[lane]=32'h56780000+32'(lane);end active_mask='1;run_case(2,8);
  for(int lane=0;lane<32;lane++)begin byte_addresses[lane]=32'h3000+32'(128*lane);words[lane]=32'habcd0000+32'(lane);end active_mask='1;run_case(3,32);
  for(int lane=0;lane<32;lane++)begin byte_addresses[lane]=lane<3?32'h1000+32'(4*lane):1;words[lane]=32'h99990000+32'(lane);end active_mask=7;run_case(4,1);
  active_mask=0;run_case(5,0);
  // Reset an accepted operation before backing acknowledgement; provider flushes too.
  @(negedge clk);active_mask=1;byte_addresses[0]=32'h100;words[0]=42;req_valid=1;tick();
  @(negedge clk);req_valid=0;repeat(2)tick();@(negedge clk);rst=1;tick();
  if(rsp_valid||backing_req_valid)$fatal(1,"Reset retained store traffic");
  @(negedge clk);rst=0;#1;if(!req_ready||sector_count!=0)$fatal(1,"Reset did not clear state");
  $display("COALESCED_FP32_STORE_PASS checked_words=%0d cases=%0d reset=1",checked,cases);$finish;
 end
 initial begin #100000;$fatal(1,"Store timeout");end
endmodule
