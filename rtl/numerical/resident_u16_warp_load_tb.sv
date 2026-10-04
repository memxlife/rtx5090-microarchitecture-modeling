`timescale 1ns/1ps
module resident_u16_warp_load_tb;
 logic clk=0;always #0.05 clk=~clk;
 logic rst=1,req_valid=0,req_ready,rsp_valid,rsp_ready=0;
 logic[31:0]req_context=0,req_id=0,rsp_context,rsp_id,byte_addresses[32],active_mask=0;
 logic[15:0]halfwords[32];int sector_count,outstanding;
 logic[1:0]context_ready;
 logic backing_req_valid,backing_req_ready,backing_rsp_valid=0,backing_rsp_ready;
 logic[31:0]backing_req_id,backing_req_byte_address,backing_rsp_id;
 logic[255:0]backing_rsp_data;
 bit pending=0;int delay_left=0,cycle=0,misses=0,checked=0,accepts=0,retired=0;
 logic[31:0]pending_id,pending_address,saved_addresses[2][32],saved_mask[2];
 logic[15:0]held[32];
 resident_u16_warp_load dut(.*);
 assign backing_req_ready=!rst&&!pending&&!backing_rsp_valid&&(cycle%4!=0);
 function automatic logic[15:0] value_at(input logic[31:0]a);return 16'h5000^16'(a/2);endfunction
 always @(posedge clk)begin
  cycle<=cycle+1;if(cycle>20000)$fatal(1,"Resident loader timeout");
  if(rst)begin pending<=0;backing_rsp_valid<=0;delay_left<=0;misses<=0;accepts<=0;retired<=0;end
  else begin
   if(req_valid&&req_ready)accepts<=accepts+1;
   if(rsp_valid&&rsp_ready)retired<=retired+1;
   if(outstanding!=accepts-retired)$fatal(1,"Resident request conservation mismatch");
   if(backing_req_valid&&backing_req_ready)begin
    if(backing_req_byte_address[4:0]!=0)$fatal(1,"Unaligned backing sector");
    pending<=1;pending_id<=backing_req_id;pending_address<=backing_req_byte_address;delay_left<=7;misses<=misses+1;
   end
   if(pending)begin
    if(delay_left>0)delay_left<=delay_left-1;
    else begin
     backing_rsp_valid<=1;backing_rsp_id<=pending_id;
     for(int h=0;h<16;h++)backing_rsp_data[16*h+:16]<=value_at(pending_address+32'(2*h));
     pending<=0;
    end
   end
   if(backing_rsp_valid&&backing_rsp_ready)backing_rsp_valid<=0;
  end
 end
 task automatic offer(input integer ctx,id,pattern);
  begin
   @(negedge clk);req_context=32'(ctx);req_id=32'(id);active_mask=pattern==2?0:pattern==1?32'h55555555:'1;
   for(int l=0;l<32;l++)byte_addresses[l]=pattern==1?32'(2*(l%8)):32'(2*l);
   saved_mask[ctx]=active_mask;for(int l=0;l<32;l++)saved_addresses[ctx][l]=byte_addresses[l];
   req_valid=1;#0.001;while(!req_ready)@(negedge clk);@(negedge clk);req_valid=0;active_mask=0;
   for(int l=0;l<32;l++)byte_addresses[l]=32'hffff0001;
  end
 endtask
 task automatic inspect(input integer ctx,id,sectors);
  begin
   if(!rsp_valid||rsp_context!=ctx||rsp_id!=id||sector_count!=sectors)$fatal(1,"Resident response contract mismatch");
   for(int l=0;l<32;l++)begin
    if(halfwords[l]!== (saved_mask[ctx][l]?value_at(saved_addresses[ctx][l]):16'b0))$fatal(1,"Resident lane value mismatch");
    held[l]=halfwords[l];checked++;
   end
  end
 endtask
 task automatic hold_check(input integer ctx,id);
  begin if(!rsp_valid||rsp_context!=ctx||rsp_id!=id)$fatal(1,"Held response identity changed");
   for(int l=0;l<32;l++)if(halfwords[l]!==held[l])$fatal(1,"Held response data changed");
  end
 endtask
 task automatic ack;begin rsp_ready=1;@(negedge clk);rsp_ready=0;end endtask
 initial begin
  for(int l=0;l<32;l++)byte_addresses[l]=0;
  repeat(3)@(negedge clk);rst=0;
  offer(0,10,0);wait(pending);@(negedge clk);rst=1;repeat(2)@(negedge clk);
  if(outstanding||backing_rsp_valid||pending)$fatal(1,"Reset did not flush loader/provider");rst=0;
  offer(0,20,0);wait(rsp_valid);@(negedge clk);inspect(0,20,2);
  offer(1,21,1);repeat(80)begin @(negedge clk);hold_check(0,20);end
  if(dut.state[1]!=dut.RESPONSE)$fatal(1,"Held response blocked other context completion");
  if(outstanding!=2||misses!=2)$fatal(1,"Other context/common-sector progress mismatch");
  ack();wait(rsp_valid);@(negedge clk);inspect(1,21,1);ack();
  offer(0,30,2);wait(rsp_valid);@(negedge clk);inspect(0,30,0);ack();
  offer(1,31,0);wait(rsp_valid);@(negedge clk);inspect(1,31,2);ack();
  repeat(3)@(negedge clk);if(outstanding||misses!=2)$fatal(1,"Final retirement/cache reuse mismatch");
  $display("RESIDENT_U16_PASS checked_lane_values=%0d backing_misses=%0d",checked,misses);$finish;
 end
endmodule
