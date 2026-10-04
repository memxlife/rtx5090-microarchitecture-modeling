`timescale 1ns/1ps
module library_generic_matrix_tb #(parameter int LATENCY=16,INTERVAL=4);
 localparam int HALFWORDS=18688,WORDS=64*256,CRITICAL=9063;
 logic clk=0,rst=1;always #1 clk=~clk;
 logic write_valid=0,write_ready,req_valid=0,req_ready,rsp_valid,rsp_ready=0;
 logic[31:0]write_byte_address=0,req_id=900,rsp_id;
 logic[15:0]write_data=0,storage_file[HALFWORDS];
 logic[1:0]warp_id=0;logic slot=0;logic[2:0]k_step=0;
 logic[31:0]c_registers[32][8],result_registers[32][8],accumulators[4][32][8];
 logic[31:0]expected_stage[WORDS],expected_accum[WORDS];
 logic operands_initialized,addresses_legal;int outstanding,written=0,accepted=0,checked=0;
 string directory;
 library_generic_matrix_pipeline #(.LATENCY(LATENCY),.INTERVAL(INTERVAL)) dut(.*);
 always @(posedge clk)if(!rst&&req_valid&&req_ready)begin
  if(written!=HALFWORDS)$fatal(1,"Library matrix admitted before final required write");
  accepted<=accepted+1;
 end
 task automatic check_response(input int case_number,input bit accumulation);
  wait(rsp_valid);@(negedge clk);
  if(rsp_id!=req_id)$fatal(1,"Library matrix identity mismatch");
  repeat(3)begin
   for(int lane=0;lane<32;lane++)for(int e=0;e<8;e++)begin
    logic[31:0]want;
    want=accumulation?expected_accum[case_number*256+lane*8+e]:expected_stage[case_number*256+lane*8+e];
    if(result_registers[lane][e]!==want)$fatal(1,"Library generic result mismatch case%0d lane%0d element%0d",case_number,lane,e);
   end
   @(negedge clk);
  end
  checked+=256;
 endtask
 initial begin
  if(!$value$plusargs("vectors=%s",directory))$fatal(1,"Missing vectors");
  $readmemh({directory,"/inputstorage.hex"},storage_file);
  $readmemh({directory,"/expected_all_stages.hex"},expected_stage);
  $readmemh({directory,"/expected_all_accumulated.hex"},expected_accum);
  for(int lane=0;lane<32;lane++)for(int e=0;e<8;e++)c_registers[lane][e]=0;
  repeat(2)@(negedge clk);rst=0;
  if($test$plusargs("oddwrite"))begin write_byte_address=1;write_valid=1;@(negedge clk);$fatal(1,"Missing odd-address rejection");end
  req_valid=1;
  // Hold one actually referenced B halfword until the last initializing edge.
  for(int i=0;i<HALFWORDS;i++)begin
   int index;index=i==HALFWORDS-1?CRITICAL:(i<CRITICAL?i:i+1);
   write_valid=1;write_byte_address=32'(index*2);write_data=storage_file[index];
   @(negedge clk);written=i+1;
   if(i<HALFWORDS-1&&req_ready)$fatal(1,"Incomplete generic operand packet ready");
  end
  write_valid=0;wait(accepted==1);@(negedge clk);req_valid=0;
  // Accepted operands must survive later shared-memory modification.
  write_valid=1;write_byte_address=32'(CRITICAL*2);write_data=0;@(negedge clk);write_valid=0;
  check_response(0,0);rsp_ready=1;@(negedge clk);rsp_ready=0;
  write_valid=1;write_data=storage_file[CRITICAL];@(negedge clk);write_valid=0;
  for(int mode=0;mode<2;mode++)begin
   for(int w=0;w<4;w++)for(int lane=0;lane<32;lane++)for(int e=0;e<8;e++)accumulators[w][lane][e]=0;
   for(int c=0;c<64;c++)begin
    int target_count;
    warp_id=2'(c%4);slot=1'(c/32);k_step=3'((c/4)%8);req_id=32'(1000+mode*64+c);
    for(int lane=0;lane<32;lane++)for(int e=0;e<8;e++)c_registers[lane][e]=mode?accumulators[c%4][lane][e]:0;
    target_count=accepted+1;while(!req_ready)@(negedge clk);req_valid=1;
    @(negedge clk);req_valid=0;wait(accepted==target_count);
    check_response(c,1'(mode));
    for(int lane=0;lane<32;lane++)for(int e=0;e<8;e++)accumulators[c%4][lane][e]=result_registers[lane][e];
    rsp_ready=1;@(negedge clk);rsp_ready=0;
    if(outstanding)$fatal(1,"Library result not retired");
   end
  end
  rst=1;@(negedge clk);#0.1;
  if(outstanding||rsp_valid||req_ready||operands_initialized)$fatal(1,"Library path reset failed");
  $display("LIBRARY_GENERIC_MATRIX_PASS checked_words=%0d operations=%0d latency=%0d",checked,accepted,LATENCY);$finish;
 end
 initial begin #1000000;$fatal(1,"Library generic matrix timeout");end
endmodule
