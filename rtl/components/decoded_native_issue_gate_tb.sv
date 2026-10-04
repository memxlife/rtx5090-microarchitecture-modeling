module decoded_native_issue_gate_tb;
 import native_control_decode::*;
 logic clk=0,reset=1;always #5 clk=~clk;
 logic instr_valid=0,instr_ready,dispatch_valid,dispatch_ready=1,issued;
 logic[4:0]operation_id=0,write_complete_tag=0,read_complete_tag=0;
 control_t control;
 logic write_complete_valid=0,read_complete_valid=0;
 logic[5:0]busy_write_mask,busy_read_mask;logic[3:0]cooldown;logic error_sticky;
 int checks=0,issues=0;
 decoded_native_issue_gate dut(.*);
 always @(posedge clk)if(!reset&&issued)issues<=issues+1;
 task tick;@(posedge clk);#1;endtask
 task issue(input int id,input logic[127:0]raw);
  @(negedge clk);operation_id=5'(id);control=decode(raw);instr_valid=1;#1;
  while(!instr_ready)begin tick();@(negedge clk);#1;end
  tick();@(negedge clk);instr_valid=0;
 endtask
 task complete_write(input int id);
  @(negedge clk);write_complete_tag=5'(id);write_complete_valid=1;tick();
  @(negedge clk);write_complete_valid=0;
 endtask
 initial begin
  control='0;control.write_barrier=7;control.read_barrier=7;
  tick();@(negedge clk);reset=0;
  // Exact original kernel0x1350 LD.E wr3 delay4,0x14c0 MOVM waits3.
  issue(0,128'h000ee8000c1019000008000a221c7980);
  if(cooldown!=3||!busy_write_mask[3])$fatal(1,"Original load allocation/delay failed");checks++;
  @(negedge clk);instr_valid=1;operation_id=1;
  control=decode(128'h008fe80000000000000000001c1c723a);#1;
  repeat(6)begin if(dispatch_valid)$fatal(1,"Consumer issued before actual return");tick();end checks++;
  @(negedge clk);write_complete_valid=1;write_complete_tag=0;#1;
  if(dispatch_valid)$fatal(1,"Unexpected same-edge completion bypass");tick();checks++;
  if(!dispatch_valid)$fatal(1,"Actual completion did not unblock");
  @(negedge clk);write_complete_valid=0;tick();@(negedge clk);instr_valid=0;
  // Exact original0x1370/0x1380 both allocate wr5: same barrier supports two ops.
  issue(2,128'h000f68000c1019000008100a22187980);
  issue(3,128'h000f62000c101900000a100a22197980);
  if(dut.write_counts[5]!=2)$fatal(1,"Same-barrier allocation incorrectly serialized");checks++;
  @(negedge clk);instr_valid=1;operation_id=4;
  control=decode(128'h020fe80000000000000000001818723a);#1;
  if(dispatch_valid)$fatal(1,"Reused barrier prematurely ready");
  complete_write(2);#1;if(dispatch_valid)$fatal(1,"First completion cleared two producers");checks++;
  complete_write(3);#1;if(!dispatch_valid)$fatal(1,"Final producer did not clearwait");
  tick();@(negedge clk);instr_valid=0;checks++;
  // Held downstream acceptance allocates nothing; read barrier remains pending
  // until actual operand-consumed event, independent of result completion.
  while(cooldown!=0)tick();
  @(negedge clk);dispatch_ready=0;instr_valid=1;operation_id=5;
  control.issue_delay=1;control.write_barrier=1;control.read_barrier=2;control.wait_mask=0;#1;
  repeat(3)begin tick();if(busy_write_mask||busy_read_mask||instr_ready)$fatal(1,"Held issue allocated prematurely");end checks++;
  @(negedge clk);dispatch_ready=1;tick();@(negedge clk);instr_valid=0;
  complete_write(5);if(!busy_read_mask[2]||busy_write_mask[1])$fatal(1,"Read/write namespaces coupled incorrectly");checks++;
  @(negedge clk);instr_valid=1;operation_id=6;control.write_barrier=7;control.read_barrier=7;control.wait_mask=4;#1;
  if(dispatch_valid)$fatal(1,"Read completion wait ignored");
  @(negedge clk);read_complete_tag=5;read_complete_valid=1;tick();
  @(negedge clk);read_complete_valid=0;tick();@(negedge clk);instr_valid=0;checks++;
  if(error_sticky)$fatal(1,"Unexpected tracker error");
  // One operation can legitimately complete read and write on the same edge.
  issue(7,128'h00044200000000000000000000000000);
  @(negedge clk);write_complete_tag=7;read_complete_tag=7;
  write_complete_valid=1;read_complete_valid=1;tick();
  if(busy_read_mask||busy_write_mask)$fatal(1,"Simultaneous read/write completion failed");checks++;
  @(negedge clk);write_complete_valid=0;read_complete_valid=0;
  // Completion of one tag and allocation of another update independently.
  issue(8,128'h00044200000000000000000000000000);
  @(negedge clk);instr_valid=1;operation_id=9;control=decode(128'h00090200000000000000000000000000);
  write_complete_tag=8;read_complete_tag=8;write_complete_valid=1;read_complete_valid=1;#1;
  if(!instr_ready)$fatal(1,"Distinct-tag completion/dispatch unnecessarily blocked");tick();
  if(busy_write_mask!=16||busy_read_mask!=16)$fatal(1,"Concurrent completion/dispatch lost state");checks++;
  @(negedge clk);instr_valid=0;write_complete_tag=9;read_complete_tag=9;tick();
  @(negedge clk);write_complete_valid=0;read_complete_valid=0;
  // Unsupported barrier6 rejected and sticky error recorded.
  @(negedge clk);instr_valid=1;operation_id=7;control.write_barrier=6;control.wait_mask=0;#1;
  if(instr_ready||dispatch_valid)$fatal(1,"Unsupported barrier admitted");tick();
  if(!error_sticky)$fatal(1,"Missing invalid-field report");checks++;
  @(negedge clk);reset=1;instr_valid=0;tick();
  if(error_sticky||busy_read_mask||busy_write_mask||cooldown)$fatal(1,"Reset failed");checks++;
  $display("DECODED_ISSUE_GATE_PASS checks=%0d issued=%0d",checks,issues);$finish;
 end
 initial begin #10000;$fatal(1,"Issuegate timeout");end
endmodule
