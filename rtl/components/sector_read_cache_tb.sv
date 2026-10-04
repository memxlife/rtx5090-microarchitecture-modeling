`timescale 1ns/1ps
module sector_read_cache_tb;
 logic clk=0,rst=1;always #1 clk=~clk;
 logic req_valid=0,req_ready,rsp_valid,rsp_ready=0,rsp_hit;
 logic [31:0]req_id=0,req_byte_address=0,rsp_id,rsp_data;
 logic backing_req_valid,backing_req_ready=0,backing_rsp_valid=0,backing_rsp_ready;
 logic[31:0]backing_req_id,backing_req_byte_address,backing_rsp_id=0;
 logic[255:0]backing_rsp_data=0,rsp_sector_data;
 int requests=0,responses=0,miss_requests=0,checks=0;
 sector_read_cache #(.SETS(2),.WAYS(1))dut(.*);
 always @(posedge clk)if(!rst)begin
  if(req_valid&&req_ready)requests++;
  if(rsp_valid&&rsp_ready)responses++;
  if(backing_req_valid&&backing_req_ready)miss_requests++;
 end
 task automatic issue(input logic[31:0]address,id);
  @(negedge clk);req_byte_address=address;req_id=id;req_valid=1;
  if(!req_ready)$fatal(1,"Cache not idle before issue");
  @(negedge clk);req_valid=0;
 endtask
 task automatic fill(input logic[31:0]address,id);
  logic[31:0]sector_address;sector_address={address[31:5],5'b0};
  if(!backing_req_valid||backing_req_byte_address!=sector_address||backing_req_id!=id)$fatal(1,"Miss payload wrong");
  repeat(3)begin @(negedge clk);if(!backing_req_valid||rsp_valid||req_ready||backing_req_byte_address!=sector_address)$fatal(1,"Miss backpressure wrong");end
  backing_req_ready=1;@(negedge clk);backing_req_ready=0;
  if(!backing_rsp_ready||rsp_valid)$fatal(1,"Waiting completion not represented");
  repeat(7)begin @(negedge clk);if(rsp_valid||req_ready)$fatal(1,"Result appeared before backing completion");end
  for(int i=0;i<8;i++)backing_rsp_data[i*32+:32]=32'h10000000+sector_address+4*i;
  backing_rsp_id=$test$plusargs("wrong_id")?id+1:id;backing_rsp_valid=1;
  @(negedge clk);backing_rsp_valid=0;
 endtask
 task automatic consume(input logic[31:0]address,id,input logic expected_hit);
  if(!rsp_valid||rsp_id!=id||rsp_data!=32'h10000000+address||rsp_hit!=expected_hit)$fatal(1,"Read result wrong address%h",address);
  for(int i=0;i<8;i++)if(rsp_sector_data[i*32+:32]!=32'h10000000+{address[31:5],5'b0}+32'(4*i))$fatal(1,"Sector packet contents wrong");
  repeat(3)begin @(negedge clk);if(!rsp_valid||rsp_id!=id||rsp_data!=32'h10000000+address||req_ready)$fatal(1,"Response not stable under backpressure");end
  rsp_ready=1;@(negedge clk);rsp_ready=0;
  if(rsp_valid||!req_ready)$fatal(1,"Response retirement wrong");checks++;
 endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;
  if($test$plusargs("unaligned"))begin issue(32'h105,1);#20;$fatal(1,"Unaligned request not rejected");end
  issue(32'h104,1);fill(32'h104,1);consume(32'h104,1,0);
  issue(32'h12c,2);fill(32'h12c,2);consume(32'h12c,2,0);
  issue(32'h104,3);if(backing_req_valid)$fatal(1,"Valid sector wrongly misses");consume(32'h104,3,1);
  issue(32'h108,4);consume(32'h108,4,1);
  issue(32'h200,5);fill(32'h200,5);consume(32'h200,5,0);
  issue(32'h12c,6);fill(32'h12c,6);consume(32'h12c,6,0);
  if(requests!=6||responses!=6||miss_requests!=4)$fatal(1,"Request conservation wrong");
  issue(32'h380,7);backing_req_ready=1;@(negedge clk);backing_req_ready=0;
  if(!backing_rsp_ready)$fatal(1,"Reset control did not enter pending miss");
  rst=1;@(negedge clk);rst=0;#0.1;
  if(rsp_valid||backing_req_valid||!req_ready)$fatal(1,"Reset failed to clear pending state");
  backing_rsp_valid=1;backing_rsp_id=7;@(negedge clk);backing_rsp_valid=0;
  if(rsp_valid)$fatal(1,"Canceled response resurrected a result");
  issue(32'h104,8);fill(32'h104,8);consume(32'h104,8,0);
  if(requests!=8||responses!=7||miss_requests!=6)$fatal(1,"Reset cancellation conservation wrong");
  $display("SECTOR_CACHE_PASS checks=%0d sectors_first_miss_then_hit delayed_completion eviction reset",checks);$finish;
 end
 initial begin #3000;$fatal(1,"Sector cache timeout");end
endmodule
