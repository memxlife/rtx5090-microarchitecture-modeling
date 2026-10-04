`timescale 1ns/1ps
module dependency_probe_replay_tb #(parameter int OPERATIONS=37,TIMING_MODE=0,EXTRA_WAKEUP_CYCLES=0);
 logic clk=0;always #0.05 clk=~clk;logic rst=1,launch_valid=0,launch_ready,write_valid=0,write_ready,done_valid,done_ready=0;
 logic[31:0]launch_id=0,input_words[32],byte_addresses[32],write_byte_address=0,write_data=0,done_id,result_words[32],issue_id;
 logic[1:0]opcode=0,issue_opcode;logic issue_valid;logic[63:0]elapsed_cycles;
 int cycle=0,issued=0,previous_issue=-1,accepted_launch=-1,first_issue=-1,final_return=-1,checked=0;logic[31:0]oracle[32],temporary[32],held[32];
 dependency_probe_replay #(.OPERATIONS(OPERATIONS),.TIMING_MODE(TIMING_MODE),.EXTRA_WAKEUP_CYCLES(EXTRA_WAKEUP_CYCLES))dut(.*);
 always @(posedge clk)begin
  cycle<=cycle+1;if(cycle>200000)$fatal(1,"Dependency replay timeout");
  if(rst)begin issued=0;previous_issue=-1;accepted_launch=-1;end
  else begin
   if(launch_valid&&launch_ready)begin issued=0;previous_issue=-1;accepted_launch=cycle;first_issue=-1;final_return=-1;end
   if(issue_valid)begin
    if(issue_opcode!=opcode||issue_id!=issued)$fatal(1,"Issue identity/opcode mismatch");
    if(previous_issue>=0&&cycle-previous_issue!=(opcode==0?29:28))$fatal(1,"Effective recurrence spacing mismatch");
    if(previous_issue<0&&cycle-accepted_launch!=1)$fatal(1,"First issue edge mismatch");if(first_issue<0)first_issue=cycle;previous_issue=cycle;issued++;
   end
   if(dut.return_valid&&dut.returned_count==OPERATIONS-1)final_return=cycle;
  end
 end
 task automatic fill;
  begin for(int l=0;l<32;l++)begin @(negedge clk);write_byte_address=32'(4*l);write_data=32'(4*((l+1)%32));write_valid=1;begin bit taken;taken=0;while(!taken)begin @(posedge clk);taken=write_ready;end end @(negedge clk);write_valid=0;end end
 endtask
 task automatic launch(input integer op,id);
  begin
   @(negedge clk);opcode=2'(op);launch_id=32'(id);for(int l=0;l<32;l++)begin input_words[l]=32'h41000000+32'(257*l);byte_addresses[l]=32'(4*l);oracle[l]=input_words[l];end
   if(op==0)for(int n=0;n<OPERATIONS;n++)begin
    for(int l=0;l<32;l++)for(int h=0;h<2;h++)temporary[l][16*h+:16]=oracle[8*(l%4)+(l/8)%4+4*h][16*((l/4)%2)+:16];
    for(int l=0;l<32;l++)oracle[l]=temporary[l];
   end else for(int l=0;l<32;l++)oracle[l]=32'(4*((l+OPERATIONS)%32));
   launch_valid=1;begin bit taken;taken=0;while(!taken)begin @(posedge clk);taken=launch_ready;end end @(negedge clk);launch_valid=0;
   for(int l=0;l<32;l++)begin input_words[l]='1;byte_addresses[l]='1;end
  end
 endtask
 task automatic finish_check(input integer id);
  logic[63:0]saved_elapsed;
  begin
   wait(done_valid);@(negedge clk);if(done_id!=id||issued!=OPERATIONS)$fatal(1,"Completion identity/count");saved_elapsed=elapsed_cycles;
   if(elapsed_cycles!=1+OPERATIONS*(opcode==0?29:28)||previous_issue-first_issue!=(OPERATIONS-1)*(opcode==0?29:28)||final_return-first_issue!=OPERATIONS*(opcode==0?29:28))$fatal(1,"Replay admission/final-return boundaries");
   for(int l=0;l<32;l++)begin if(result_words[l]!==oracle[l])$fatal(1,"Actual recurrence value mismatch lane%0d",l);held[l]=result_words[l];checked++;end
   repeat(4)begin @(negedge clk);if(!done_valid||done_id!=id||elapsed_cycles!=saved_elapsed)$fatal(1,"Held completion metadata");for(int l=0;l<32;l++)if(result_words[l]!==held[l])$fatal(1,"Held completion values");end
   $display("DEPENDENCY_CASE opcode=%0d operations=%0d recurrence=%0d modeled_elapsed=%0d first_to_last_admission=%0d first_to_final_return=%0d",opcode,OPERATIONS,opcode==0?29:28,elapsed_cycles,previous_issue-first_issue,final_return-first_issue);
   done_ready=1;@(negedge clk);done_ready=0;
  end
 endtask
 initial begin
  for(int l=0;l<32;l++)begin input_words[l]=0;byte_addresses[l]=0;end
  repeat(3)@(negedge clk);rst=0;fill();launch(0,10);wait(issued==2);@(negedge clk);rst=1;repeat(2)@(negedge clk);if(done_valid||issue_valid)$fatal(1,"Reset cancellation");rst=0;fill();
  launch(0,20);finish_check(20);launch(1,21);finish_check(21);
  $display("DEPENDENCY_REPLAY_PASS operations=%0d checked_words=%0d",OPERATIONS,checked);$finish;
 end
endmodule
