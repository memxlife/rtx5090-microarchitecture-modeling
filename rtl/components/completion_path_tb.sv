`timescale 1ns/1ps
module completion_path_tb #(parameter int MEMORY_LATENCY=12);
 logic clk=0,rst=1;always #1 clk=~clk;
 int source_a=1,source_b=0,destination=1,complete_destination;
 logic use_a=1,use_b=0,operands_ready,reserve_valid=0,reserve_ready;
 logic[31:0] operand_a,operand_b,reservation_id=41,complete_id,complete_data;
 logic complete_valid;int pending_count;
 completion_register_file #(.REGS(8)) registers(.*);
 logic memory_req=0,memory_ready,memory_rsp,memory_return_ready=0;
 logic[31:0] memory_result;
 timed_queue #(.SLOTS(2),.LATENCY(MEMORY_LATENCY),.INTERVAL(1)) memory_path(
  .clk,.rst,.req_valid(memory_req),.req_ready(memory_ready),.req_id(32'd41),
  .rsp_valid(memory_rsp),.rsp_ready(memory_return_ready),.rsp_id(memory_result));
 logic consumer_ready=0,consumer_valid;int consumer_issues=0;
 logic execute_req,execute_ready,execute_rsp,execute_return_ready=0;
 logic[31:0] execute_result,computed_result=0;
 timed_queue #(.SLOTS(2),.LATENCY(3),.INTERVAL(1)) execution_path(
  .clk,.rst,.req_valid(execute_req),.req_ready(execute_ready),.req_id(32'd42),
  .rsp_valid(execute_rsp),.rsp_ready(execute_return_ready),.rsp_id(execute_result));
 int mode=0,cycles=0;string negative_case;
 logic inject=0;int inject_destination=1;logic[31:0] inject_id=99;
 assign consumer_valid=mode==1&&operands_ready&&reserve_ready&&execute_ready;
 assign execute_req=consumer_valid&&consumer_ready;
 always_comb begin
  complete_valid=inject||(memory_rsp&&memory_return_ready)||(execute_rsp&&execute_return_ready);
  complete_destination=inject?inject_destination:(memory_rsp&&memory_return_ready?1:2);
  complete_id=inject?inject_id:(memory_rsp&&memory_return_ready?memory_result:execute_result);
  complete_data=memory_rsp&&memory_return_ready?32'd7:computed_result;
 end
 always @(posedge clk) if(!rst) begin
  cycles<=cycles+1;
  if(execute_req&&execute_ready) begin
   if(operand_a!=7) $fatal(1,"Consumer used incorrect or early load data");
   computed_result<=operand_a+5;consumer_issues<=consumer_issues+1;
  end
 end
 task automatic step; @(negedge clk);#0.1;endtask
 initial begin
  void'($value$plusargs("negative=%s",negative_case));
  repeat(3) step();rst=0;step();
  if(operands_ready||pending_count!=0) $fatal(1,"Undefined source became ready");
  if(negative_case=="bad_index") begin destination=8;reserve_valid=1;step();$fatal(1,"Expected invalid-index rejection");end
  if(negative_case=="unreserved") begin inject=1;step();$fatal(1,"Expected unmatched completion rejection");end
  reserve_valid=1;memory_req=1;
  if(!reserve_ready||!memory_ready) $fatal(1,"Initial load admission failed");
  step();reserve_valid=0;memory_req=0;
  if(negative_case=="wrong_id") begin inject=1;step();$fatal(1,"Expected stale-ID rejection");end
  if(negative_case=="duplicate_id") begin destination=2;reserve_valid=1;step();$fatal(1,"Expected duplicate identity rejection");end
  if(pending_count!=1||operands_ready) $fatal(1,"Pending load became ready");
  mode=1;destination=2;reservation_id=42;consumer_ready=1;
  // Wait well beyond a hypothetical fixed result delay: only actual return counts.
  repeat(8) begin step();if(operands_ready||consumer_issues!=0) $fatal(1,"Premature consumer issue");end
  wait(memory_rsp);step();
  repeat(4) begin step();if(operands_ready||consumer_issues!=0) $fatal(1,"Held return released dependent issue");end
  consumer_ready=0;memory_return_ready=1;step();memory_return_ready=0;
  if(!operands_ready||operand_a!=7||pending_count!=0) $fatal(1,"Actual load completion not reflected");
  if(negative_case=="duplicate_completion") begin inject=1;inject_id=41;step();$fatal(1,"Expected duplicate completion rejection");end
  // Stall downstream consumer after load returns; valid operands must stay intact.
  repeat(3) begin step();if(consumer_issues!=0||operand_a!=7) $fatal(1,"Downstream stall ignored");end
  reserve_valid=consumer_valid;consumer_ready=1;step();
  reserve_valid=0;consumer_ready=0;mode=2;source_a=2;#0.1;
  if(consumer_issues!=1||operands_ready||pending_count!=1) $fatal(1,"Consumer issue/reservation not atomic");
  wait(execute_rsp);step();
  repeat(3) begin step();if(operands_ready) $fatal(1,"Held execution result became ready");end
  execute_return_ready=1;step();execute_return_ready=0;
  if(!operands_ready||operand_a!=12||pending_count!=0) $fatal(1,"Numerical completion wrong");
  // Reserve/complete simultaneously on different destinations; one ends, one begins.
  destination=3;reservation_id=43;reserve_valid=1;step();reserve_valid=0;
  inject=1;inject_id=43;inject_destination=3;destination=4;reservation_id=44;reserve_valid=1;
  step();inject=0;reserve_valid=0;if(pending_count!=1) $fatal(1,"Concurrent events not conserved");
  // Same-destination reservation cannot bypass a pending result on its return edge.
  inject=1;inject_id=44;inject_destination=4;reservation_id=45;reserve_valid=1;
  if(reserve_ready) $fatal(1,"Pending overwrite admitted");
  step();inject=0;
  if(!reserve_ready||pending_count!=0) $fatal(1,"Completion did not unblock held reservation");
  step();reserve_valid=0;if(pending_count!=1) $fatal(1,"Held reservation lost");
  rst=1;step();rst=0;source_a=4;step();
  if(operands_ready||pending_count!=0) $fatal(1,"Reset retained result or reservation");
  $display("COMPLETION_PATH_PASS cycles=%0d issues=%0d delayed_load held_return consumer_stall data_flow concurrent_events reset",cycles,consumer_issues);$finish;
 end
 initial begin #1000;$fatal(1,"Completion-path test timeout");end
endmodule
