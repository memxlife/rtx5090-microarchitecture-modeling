`timescale 1ns/1ps
module studied_gemm_matrix_tb #(parameter int BM=32,BN=32,BK=32,STAGES=48,parameter bit TIMED_READS=0);
 localparam int HALFWORDS=BK*(BM+BN),TILES=(BM/16)*(BN/16),STEPS=BK/16;
 localparam int EXPECTED_WORDS=STAGES*TILES*STEPS*256;
 localparam int CRITICAL=BM*BK+15*BN+15;
 logic clk=0,rst=1;always #1 clk=~clk;
 logic write_valid=0,write_ready,req_valid=0,req_ready,rsp_valid,rsp_ready=0;
 logic[31:0]write_byte_address=0,req_id=0,rsp_id,tile_index=0,k_step=0;
 logic[15:0]write_data=0,storage_file[STAGES*HALFWORDS];
 logic[31:0]c_registers[32][8],result_registers[32][8],accumulators[TILES][32][8];
 logic[31:0]expected[EXPECTED_WORDS];logic operands_initialized,addresses_legal;
 int outstanding,accepted=0,checked=0;string directory;
 studied_gemm_matrix_pipeline #(.BM(BM),.BN(BN),.BK(BK),.TIMED_READS(TIMED_READS)) dut(.*);
 always @(posedge clk)if(!rst&&req_valid&&req_ready)accepted<=accepted+1;
 initial begin
  if(!$value$plusargs("vectors=%s",directory))$fatal(1,"Missing vectors");
  $readmemh({directory,"/inputstorage.hex"},storage_file);
  $readmemh({directory,"/expected_accumulated.hex"},expected);
  for(int t=0;t<TILES;t++)for(int lane=0;lane<32;lane++)for(int e=0;e<8;e++)accumulators[t][lane][e]=0;
  for(int lane=0;lane<32;lane++)for(int e=0;e<8;e++)c_registers[lane][e]=0;
  repeat(2)@(negedge clk);rst=0;
  if($test$plusargs("badtile"))begin tile_index=32'(TILES);req_valid=1;@(negedge clk);$fatal(1,"Missing tile rejection");end
  if($test$plusargs("badstep"))begin k_step=32'(STEPS);req_valid=1;@(negedge clk);$fatal(1,"Missing step rejection");end
  for(int stage=0;stage<STAGES;stage++)begin
   tile_index=0;k_step=0;
   for(int i=0;i<HALFWORDS;i++)begin
    int index;index=i==HALFWORDS-1?CRITICAL:(i<CRITICAL?i:i+1);
    write_valid=1;write_byte_address=32'(index*2);write_data=storage_file[stage*HALFWORDS+index];
    @(negedge clk);
    if(stage==0&&i<HALFWORDS-1&&req_ready)$fatal(1,"Uninitialized studied operand packet ready");
   end
   write_valid=0;
   for(int t=0;t<TILES;t++)for(int step=0;step<STEPS;step++)begin
    int target,offset;
    tile_index=32'(t);k_step=32'(step);req_id=32'((stage*TILES+t)*STEPS+step);
    for(int lane=0;lane<32;lane++)for(int e=0;e<8;e++)c_registers[lane][e]=accumulators[t][lane][e];
    target=accepted+1;while(!req_ready)@(negedge clk);req_valid=1;@(negedge clk);req_valid=0;
    wait(accepted==target);wait(rsp_valid);@(negedge clk);
    if(rsp_id!=req_id)$fatal(1,"Studied matrix identity mismatch");
    offset=((stage*TILES+t)*STEPS+step)*256;
    repeat(2)begin
     for(int lane=0;lane<32;lane++)for(int e=0;e<8;e++)
      if(result_registers[lane][e]!==expected[offset+lane*8+e])$fatal(1,"Studied numerical mismatch stage%0d tile%0d step%0d lane%0d element%0d",stage,t,step,lane,e);
     @(negedge clk);
    end
    checked+=256;
    for(int lane=0;lane<32;lane++)for(int e=0;e<8;e++)accumulators[t][lane][e]=result_registers[lane][e];
    rsp_ready=1;@(negedge clk);rsp_ready=0;
    if(outstanding)$fatal(1,"Studied result not retired");
   end
  end
  if(checked!=EXPECTED_WORDS||accepted!=STAGES*TILES*STEPS)$fatal(1,"Studied operation conservation");
  rst=1;@(negedge clk);#0.1;
  if(outstanding||rsp_valid||req_ready||operands_initialized)$fatal(1,"Studied reset failed");
  $display("STUDIED_GEMM_MATRIX_PASS BM=%0d BN=%0d K=%0d checked_words=%0d operations=%0d",BM,BN,STAGES*BK,checked,accepted);$finish;
 end
 initial begin #2000000;$fatal(1,"Studied GEMM timeout");end
endmodule
