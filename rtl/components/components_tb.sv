`timescale 1ns/1ps
module components_tb;
 logic clk=0,rst=1;always #1 clk=~clk;
 logic [3:0] eligible=0;logic issue_valid,issue_ready=0;int issue_warp;
 warp_scheduler scheduler(.*);
 logic sh_req=0,sh_ready,sh_write=0,sh_rsp,sh_rsp_ready=1;int sh_addr=0;logic[31:0] sh_data=0,sh_result;
 shared_memory_bank #(.LATENCY(3)) shared_bank(.clk,.rst,.req_valid(sh_req),.req_ready(sh_ready),.write(sh_write),.word_address(sh_addr),.write_data(sh_data),.rsp_valid(sh_rsp),.rsp_ready(sh_rsp_ready),.read_data(sh_result));
 logic ca_req=0,ca_ready,ca_rsp,ca_rsp_ready=1,ca_hit;logic[31:0] ca_addr=0,ca_result;
 read_cache #(.HIT_DELAY(2),.MISS_DELAY(6)) cache(.clk,.rst,.req_valid(ca_req),.req_ready(ca_ready),.byte_address(ca_addr),.rsp_valid(ca_rsp),.rsp_ready(ca_rsp_ready),.hit(ca_hit),.response_address(ca_result));
 logic q_req=0,q_ready,q_rsp,q_rsp_ready=0;logic[31:0] q_id=0,q_result;
 timed_queue #(.SLOTS(2),.LATENCY(4),.INTERVAL(1)) queue(.clk,.rst,.req_valid(q_req),.req_ready(q_ready),.req_id(q_id),.rsp_valid(q_rsp),.rsp_ready(q_rsp_ready),.rsp_id(q_result));
 logic[3:0] arrivals=0;logic protected_operations_complete=0,release_warps;
 barrier_controller #(.RELEASE_DELAY(2)) barrier(.*);
 task automatic shared_access(input bit wr,input int address,input logic[31:0] value);
  @(negedge clk);sh_write=wr;sh_addr=address;sh_data=value;sh_req=1;
  if(!sh_ready) $fatal(1,"Shared unexpectedly full");
  @(negedge clk);sh_req=0;
  wait(sh_rsp);if(sh_result!=value) $fatal(1,"Shared value mismatch");
  @(negedge clk);@(negedge clk);
 endtask
 task automatic cache_access(input logic[31:0] address,input bit expected_hit);
  @(negedge clk);ca_addr=address;ca_req=1;
  if(!ca_ready) $fatal(1,"Cache unexpectedly full");
  @(negedge clk);ca_req=0;
  wait(ca_rsp);if(ca_hit!=expected_hit||ca_result!=address) $fatal(1,"Cache lookup mismatch");
  @(negedge clk);@(negedge clk);
 endtask
 initial begin
  repeat(3) @(negedge clk);rst=0;
  @(negedge clk);eligible=4'b1111;issue_ready=1;
  #0.1;if(!issue_valid||issue_warp!=0) $fatal(1,"Initial arbitration");
  @(negedge clk);#0.1;if(issue_warp!=1) $fatal(1,"Round robin");
  issue_ready=0;@(negedge clk);#0.1;if(issue_warp!=1) $fatal(1,"Cursor advanced without acceptance");eligible=0;
  shared_access(1,7,32'h12345678);shared_access(0,7,32'h12345678);
  cache_access(32'h100,0);cache_access(32'h100,1);
  @(negedge clk);q_req=1;q_id=10;
  @(negedge clk);q_id=20;
  @(negedge clk);q_req=0;
  wait(q_rsp);if(q_result!=10||q_ready) $fatal(1,"FIFO or capacity wrong");
  repeat(3) @(negedge clk);
  if(!q_rsp||q_result!=10) $fatal(1,"Response lost during backpressure");
  q_rsp_ready=1;@(negedge clk);if(!q_rsp||q_result!=20) $fatal(1,"Second FIFO response");
  @(negedge clk);q_rsp_ready=0;
  arrivals=4'b0011;repeat(3) @(negedge clk);if(release_warps) $fatal(1,"Early barrier release");
  arrivals=4'b1100;repeat(3) @(negedge clk);if(release_warps) $fatal(1,"Drain ignored");
  arrivals=0;protected_operations_complete=1;wait(release_warps);
  $display("COMPONENT_TESTS_PASS scheduler shared_values cache_reuse queue_capacity backpressure barrier");$finish;
 end
 initial begin #1000;$fatal(1,"Component test timeout");end
endmodule
