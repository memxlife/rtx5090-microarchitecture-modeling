module cta_generation_barrier_tb #(parameter int RELEASE_DELAY=1);
 logic clk=0,rst=1;always #5 clk=~clk;
 logic arm_valid=0,arm_ready,arrival_valid=0,arrival_ready,release_valid,release_ready=0,active;
 logic[31:0]arm_generation=0,arrival_generation=0,generation;
 logic[3:0]expected_mask=0,arrival_mask=0,release_mask,arrived_mask;int checks=0;
 cta_generation_barrier #(.RELEASE_DELAY(RELEASE_DELAY))dut(.*);
 task tick;@(posedge clk);#1;endtask
 task arm(input int gen,input logic[3:0]mask);
  @(negedge clk);arm_valid=1;arm_generation=32'(gen);expected_mask=mask;#1;
  if(!arm_ready)$fatal(1,"Arm not ready");tick();@(negedge clk);arm_valid=0;
 endtask
 task arrive(input int gen,input logic[3:0]mask);
  @(negedge clk);arrival_valid=1;arrival_generation=32'(gen);arrival_mask=mask;#1;
  if(!arrival_ready&&!$test$plusargs("negative"))$fatal(1,"Arrival not ready");tick();@(negedge clk);arrival_valid=0;
 endtask
 initial begin
  tick();@(negedge clk);rst=0;
  if($test$plusargs("early"))begin arrival_valid=1;arrival_mask=1;tick();$fatal(1,"Missing early rejection");end
  if($test$plusargs("same_edge"))begin arm_valid=1;expected_mask=15;arrival_valid=1;arrival_mask=1;tick();$fatal(1,"Missing simultaneous rejection");end
  if($test$plusargs("empty_arm"))begin arm_valid=1;tick();$fatal(1,"Missing empty arm rejection");end
  if($test$plusargs("bad_arm"))begin arm_valid=1;expected_mask=15;arm_generation=1;tick();$fatal(1,"Missing arm sequence rejection");end
  arm(0,7);
  if($test$plusargs("future"))begin arrival_valid=1;arrival_generation=1;arrival_mask=1;tick();$fatal(1,"Missing future rejection");end
  if($test$plusargs("wrongmask"))begin arrival_valid=1;arrival_mask=8;tick();$fatal(1,"Missing unknown warp rejection");end
  if($test$plusargs("empty_arrival"))begin arrival_valid=1;tick();$fatal(1,"Missing empty arrival rejection");end
  arrive(0,3);if(arrived_mask!=3||release_valid||!active)$fatal(1,"Partial arrival released early");checks++;
  if($test$plusargs("duplicate"))begin arrival_valid=1;arrival_mask=1;tick();$fatal(1,"Missing duplicate rejection");end
  @(negedge clk);arrival_valid=1;arrival_generation=0;arrival_mask=4;#1;if(!arrival_ready)$fatal(1,"Final arrival not ready");tick();
  if(release_valid)$fatal(1,"Release bypassed registered delay");checks++;
  @(negedge clk);arrival_valid=0;
  for(int elapsed=1;elapsed<=RELEASE_DELAY;elapsed++)begin tick();if(release_valid!=(elapsed==RELEASE_DELAY))$fatal(1,"Release delay mismatch");end checks++;
  if(generation!=0||release_mask!=7||arrived_mask!=7)$fatal(1,"Release payload wrong");checks++;
  // Arm generation1 stays offered while release0 is stalled, but cannot accept.
  @(negedge clk);arm_valid=1;arm_generation=1;expected_mask=15;
  repeat(4)begin tick();if(arm_ready||!release_valid||generation!=0||release_mask!=7)$fatal(1,"Held release changed");end checks++;
  @(negedge clk);release_ready=1;#1;if(arm_ready)$fatal(1,"Same-edge release/arm reuse");tick();
  @(negedge clk);release_ready=0;tick();@(negedge clk);arm_valid=0;
  if(generation!=1||!active||arrived_mask!=0)$fatal(1,"Next sequential arm not accepted");checks++;
  if($test$plusargs("stale"))begin arrival_valid=1;arrival_generation=0;arrival_mask=1;tick();$fatal(1,"Missing stale rejection");end
  arrive(1,15);while(!release_valid)tick();@(negedge clk);release_ready=1;tick();@(negedge clk);release_ready=0;
  arm(2,15);arrive(2,1);@(negedge clk);rst=1;tick();@(negedge clk);rst=0;#1;
  if(active||release_valid||arrived_mask!=0||!arm_ready)$fatal(1,"Reset did not cancel generation");checks++;
  arm(0,15);arrive(0,15);while(!release_valid)tick();
  if(generation!=0||release_mask!=15)$fatal(1,"Reset did not restore initial generation");checks++;
  @(negedge clk);rst=1;tick();@(negedge clk);rst=0;#1;
  if(active||release_valid||arrived_mask!=0)$fatal(1,"Reset did not cancel held release");checks++;
  arm(0,15);arrive(0,15);rst=1;tick();@(negedge clk);rst=0;#1;
  if(active||release_valid||arrived_mask!=0)$fatal(1,"Reset did not cancel delayed release");checks++;
  $display("CTA_GENERATION_BARRIER_PASS checks=%0d delay=%0d",checks,RELEASE_DELAY);$finish;
 end
 initial begin #10000;$fatal(1,"CTA barrier timeout");end
endmodule
