module coalesced_u16_warp_load_tb;
 logic clk=0,rst=1;always #5 clk=~clk;
 logic req_valid=0,req_ready,rsp_valid,rsp_ready=0;logic[31:0]req_id=0,rsp_id,active_mask=0,byte_addresses[32];
 logic[15:0]halfwords[32];int sector_count;
 logic backing_req_valid,backing_req_ready,backing_rsp_valid=0,backing_rsp_ready;
 logic[31:0]backing_req_id,backing_req_byte_address,backing_rsp_id=0;
 logic[255:0]backing_rsp_data=0;int cycles=0,remaining=0,misses=0;
 logic pending=0;logic[31:0]pending_id,pending_address;
 int checked=0,cases=0;logic[31:0]expected_addresses[32],expected_mask;
 coalesced_u16_warp_load dut(.*);
 assign backing_req_ready=!rst&&!pending&&!backing_rsp_valid&&(cycles%3==0);
 function automatic logic[15:0]oracle(input logic[31:0]address);return 16'h5000^16'(address>>1);endfunction
 always @(posedge clk)begin
  if(rst)begin cycles<=0;remaining<=0;pending<=0;backing_rsp_valid<=0;misses<=0;end
  else begin
   cycles<=cycles+1;
   if(backing_req_valid&&backing_req_ready)begin
    pending<=1;remaining<=4;pending_id<=backing_req_id;pending_address<=backing_req_byte_address;misses<=misses+1;
   end
   if(pending)begin
    if(remaining>0)remaining<=remaining-1;
    else begin
     pending<=0;backing_rsp_valid<=1;
     backing_rsp_id<=$test$plusargs("wrong_id")?pending_id+1:pending_id;
     for(int h=0;h<16;h++)backing_rsp_data[h*16+:16]<=oracle(pending_address+32'(2*h));
    end
   end
   if(backing_rsp_valid&&backing_rsp_ready)backing_rsp_valid<=0;
  end
 end
 task tick;@(posedge clk);#1;endtask
 task run_case(input int id,expected_sectors,expected_misses);
  int before_misses;before_misses=misses;
  for(int lane=0;lane<32;lane++)expected_addresses[lane]=byte_addresses[lane];expected_mask=active_mask;
  @(negedge clk);req_id=32'(id);req_valid=1;#1;
  if(!req_ready)$fatal(1,"Warp not ready");tick();@(negedge clk);req_valid=0;
  // Caller changes addresses/mask after acceptance; captured request must survive.
  for(int lane=0;lane<32;lane++)byte_addresses[lane]=0;active_mask=0;
  while(!rsp_valid)tick();
  if(rsp_id!=id||sector_count!=expected_sectors||misses-before_misses!=expected_misses)
   $fatal(1,"Warp identity/sector count/miss count mismatch id%0d sectors%0d misses%0d",id,sector_count,misses-before_misses);
  repeat(4)begin
   for(int lane=0;lane<32;lane++)begin
    if(halfwords[lane]!== (expected_mask[lane]?oracle(expected_addresses[lane]):16'b0))$fatal(1,"Lane numerical mismatch lane%0d",lane);
   end
   if(!rsp_valid||req_ready)$fatal(1,"Warp held response lost");tick();
  end
  checked+=32;cases++;
  @(negedge clk);rsp_ready=1;tick();@(negedge clk);rsp_ready=0;
 endtask
 initial begin
  for(int lane=0;lane<32;lane++)byte_addresses[lane]=0;
  tick();@(negedge clk);rst=0;
  if($test$plusargs("unaligned"))begin active_mask=1;byte_addresses[0]=1;req_valid=1;tick();$fatal(1,"Missing alignment rejection");end
  for(int lane=0;lane<32;lane++)byte_addresses[lane]=32'h1000+32'(2*lane);active_mask='1;run_case(1,2,2);
  for(int lane=0;lane<32;lane++)byte_addresses[lane]=32'h1000+32'(2*lane);active_mask='1;run_case(2,2,0);
  for(int lane=0;lane<32;lane++)byte_addresses[lane]=32'h2002;active_mask='1;run_case(3,1,1);
  for(int lane=0;lane<32;lane++)byte_addresses[lane]=32'h3000+32'(128*(lane%8)+2*(lane/8));active_mask='1;run_case(4,8,8);
  for(int lane=0;lane<32;lane++)byte_addresses[lane]=32'h8000+32'(128*lane);active_mask='1;run_case(5,32,32);
  for(int lane=0;lane<32;lane++)byte_addresses[lane]=lane<4?32'h1000+32'(2*lane):32'h1;active_mask=15;run_case(6,1,0);
  for(int lane=0;lane<32;lane++)byte_addresses[lane]=1;active_mask=0;run_case(7,0,0);
  // Reset while a fresh miss is still in flight; backing provider resets too.
  @(negedge clk);active_mask=1;byte_addresses[0]=32'h40000;req_id=100;req_valid=1;tick();
  @(negedge clk);req_valid=0;repeat(2)tick();@(negedge clk);rst=1;tick();
  if(rsp_valid||backing_req_valid)$fatal(1,"Reset retained visible traffic");
  @(negedge clk);rst=0;#1;if(!req_ready||sector_count!=0)$fatal(1,"Reset did not clear warp state");
  $display("COALESCED_U16_PASS checked_words=%0d cases=%0d reset=1",checked,cases);$finish;
 end
 initial begin #100000;$fatal(1,"Coalesced load timeout");end
endmodule
