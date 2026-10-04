module native_hmma16816_tb;
 logic clk=0,rst=1;always #5 clk=~clk;
 logic req_valid=0,req_ready,rsp_valid,rsp_ready=0;
 logic[31:0] req_id=0,rsp_id,a_registers[32][4],b_registers[32][2],c_registers[32][4],result_registers[32][4];
 int outstanding;logic[31:0]a_file[512],b_file[256],c_file[512],expected[512];string directory;
 native_hmma16816_adapter #(.LATENCY(2),.INTERVAL(1)) dut(.*);
 logic full_req_valid=0,full_req_ready,full_rsp_valid,full_rsp_ready=0;
 logic[31:0]full_a[32][4],full_b[32][4],full_c[32][8],full_result[32][8],full_rsp_id;
 logic[31:0]half_saved[2][32][4];int full_outstanding;
 native_bf16_adapter #(.LATENCY(2),.INTERVAL(1),.ARITHMETIC_MODE(1)) full_operation(
  .clk,.rst,.req_valid(full_req_valid),.req_ready(full_req_ready),.req_id(32'd987),
  .a_registers(full_a),.b_registers(full_b),.c_registers(full_c),
  .rsp_valid(full_rsp_valid),.rsp_ready(full_rsp_ready),.rsp_id(full_rsp_id),
  .result_registers(full_result),.outstanding(full_outstanding)
 );
 task tick;@(posedge clk);#1;endtask
 initial begin
  if(!$value$plusargs("vectors=%s",directory))$fatal(1,"Missing vectors");
  $readmemh({directory,"/a.hex"},a_file);$readmemh({directory,"/b.hex"},b_file);
  $readmemh({directory,"/c.hex"},c_file);$readmemh({directory,"/expected.hex"},expected);
  tick();@(negedge clk);rst=0;
  for(int test=0;test<4;test++)begin
   @(negedge clk);req_valid=1;req_id=32'(100+test);
   for(int lane=0;lane<32;lane++)begin
    for(int w=0;w<4;w++)begin a_registers[lane][w]=a_file[test*128+lane*4+w];c_registers[lane][w]=c_file[test*128+lane*4+w];end
    for(int w=0;w<2;w++)b_registers[lane][w]=b_file[test*64+lane*2+w];
   end
   #1;while(!req_ready)begin tick();@(negedge clk);#1;end
   tick();@(negedge clk);req_valid=0;
   // Mutate offered operands after acceptance: adapter must have captured them.
   for(int lane=0;lane<32;lane++)begin
    for(int w=0;w<4;w++)begin a_registers[lane][w]=0;c_registers[lane][w]=0;end
    for(int w=0;w<2;w++)b_registers[lane][w]=0;
   end
   while(!rsp_valid)tick();
   if(rsp_id!=100+test)$fatal(1,"HMMA identity mismatch");
   for(int lane=0;lane<32;lane++)for(int w=0;w<4;w++)
    if(result_registers[lane][w]!==expected[test*128+lane*4+w])$fatal(1,"HMMA numerical mismatch test%0d lane%0d word%0d",test,lane,w);
   for(int lane=0;lane<32;lane++)for(int w=0;w<4;w++)half_saved[test%2][lane][w]=result_registers[lane][w];
   repeat(3)begin tick();if(!rsp_valid||rsp_id!=100+test)$fatal(1,"HMMA held response lost");end
   @(negedge clk);rsp_ready=1;tick();@(negedge clk);rsp_ready=0;
   if(test%2==1)begin
    @(negedge clk);full_req_valid=1;
    for(int lane=0;lane<32;lane++)begin
     for(int w=0;w<4;w++)full_a[lane][w]=a_file[(test-1)*128+lane*4+w];
     for(int h=0;h<2;h++)begin
      for(int w=0;w<2;w++)full_b[lane][2*h+w]=b_file[(test-1+h)*64+lane*2+w];
      for(int w=0;w<4;w++)full_c[lane][4*h+w]=c_file[(test-1+h)*128+lane*4+w];
     end
    end
    #1;while(!full_req_ready)begin tick();@(negedge clk);#1;end
    tick();@(negedge clk);full_req_valid=0;
    while(!full_rsp_valid)tick();
    for(int lane=0;lane<32;lane++)for(int h=0;h<2;h++)for(int w=0;w<4;w++)
     if(full_result[lane][4*h+w]!==half_saved[h][lane][w])$fatal(1,"Two HMMA halves differ from full WMMA");
    @(negedge clk);full_rsp_ready=1;tick();@(negedge clk);full_rsp_ready=0;
   end
  end
  if(outstanding)$fatal(1,"HMMA result not retired");
  @(negedge clk);rst=1;tick();if(rsp_valid||outstanding)$fatal(1,"HMMA reset failed");
  $display("NATIVE_HMMA_PASS checked_words=512 halves=4 full_recombination_checks=512");$finish;
 end
 initial begin #10000;$fatal(1,"HMMA timeout");end
endmodule
