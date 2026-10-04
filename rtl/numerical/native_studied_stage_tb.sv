`timescale 1ns/1ps
module native_studied_stage_tb #(parameter bit USE_WARP_WRITES=0);
 logic clk=0;always #0.05 clk=~clk;
 logic rst=1,write_valid=0,write_ready,req_valid=0,req_ready,rsp_valid,rsp_ready=0;
 logic[31:0]write_byte_address=0,req_id=0,tile_index=3,rsp_id;
 logic[15:0]write_data;
 logic write_warp_valid=0,write_warp_ready;
 logic[31:0]write_warp_byte_addresses[32],write_warp_mask=0;
 logic[15:0]write_warp_halfwords[32];
 logic[31:0]c_registers[32][8],result_registers[32][8];
 logic operands_initialized,addresses_legal,native_issue_valid;
 logic[31:0]native_issue_pc;int outstanding,issued_count=0,checked=0,cycle=0;
 native_studied_stage_pipeline #(.ALLOW_WARP_WRITES(USE_WARP_WRITES),.RETURN_DELAY(9),.MOVM_LATENCY(19),.HMMA_LATENCY(73)) dut(.*);
 function automatic logic[31:0] dyadic(input integer numerator,input integer bits);
  integer n,top;logic[31:0]fraction;
  begin
   if(numerator==0)return 0;
   n=numerator<0?-numerator:numerator;top=0;while((n>>(top+1))!=0)top++;
   if(top>23)$fatal(1,"Oracle value exceeds exact FP32 domain");
   fraction=32'(n-(1<<top))<<(23-top);
   return (numerator<0?32'h80000000:0)|(32'(127+top-bits)<<23)|fraction;
  end
 endfunction
 always @(posedge clk)begin
  cycle<=cycle+1;if(cycle>10000)$fatal(1,"Native stage failed to terminate");
  if(!rst&&req_valid&&req_ready)issued_count=0;
  if(native_issue_valid)begin
   if(native_issue_pc!=32'h1350+32'(16*issued_count))$fatal(1,"Native PC order mismatch");
   issued_count++;
  end
 end
 task automatic check_result(input integer tile);
  begin
   if(rsp_id!=req_id||issued_count!=40)$fatal(1,"Native response identity/issued count mismatch");
   for(int lane=0;lane<32;lane++)for(int word_index=0;word_index<8;word_index++)begin
    integer element,row,col,sum;logic[31:0]want;
    element=native_bf16_layout::c_element_index(lane,word_index);
    row=16*(tile/2)+element/16;col=16*(tile%2)+element%16;sum=0;
    for(int k=0;k<32;k++)sum+=((row*32+k)%17-8)*((k*32+col)%13-6);
    sum+=64*((lane+word_index)%7-3);
    want=dyadic(sum,8);
    if(result_registers[lane][word_index]!==want)$fatal(1,"Native numeric mismatch tile%0d lane%0d word%0d got%h want%h",tile,lane,word_index,result_registers[lane][word_index],want);
    checked++;
   end
  end
 endtask
 initial begin
  for(int lane=0;lane<32;lane++)for(int w=0;w<8;w++)c_registers[lane][w]=dyadic((lane+w)%7-3,2);
  repeat(3)@(negedge clk);rst=0;
  if(USE_WARP_WRITES)begin
   // Adjacent halves share a 32-bit word but are independently writable.
   for(int lane=0;lane<32;lane++)begin write_warp_byte_addresses[lane]=32'(2*lane);write_warp_halfwords[lane]=16'h5678;end
   write_warp_halfwords[0]=16'h1234;write_warp_mask=3;write_warp_valid=1;
   if($test$plusargs("bad_alignment"))write_warp_byte_addresses[0]=1;
   if($test$plusargs("bad_duplicate"))write_warp_byte_addresses[1]=0;
   @(negedge clk);write_warp_valid=0;
   if(dut.memory[0]!==16'h1234||dut.memory[1]!==16'h5678)$fatal(1,"Adjacent vector halves lost");
   write_warp_mask=1;write_warp_halfwords[0]=16'h9abc;write_warp_valid=1;
   @(negedge clk);write_warp_valid=0;
   if(dut.memory[0]!==16'h9abc||dut.memory[1]!==16'h5678)$fatal(1,"Masked neighbor halfword changed");
   // Scalar offers win arbitration; a blocked vector packet commits nothing.
   write_valid=1;write_byte_address=0;write_data=16'hdef0;write_warp_valid=1;
   #0.001;if(write_warp_ready)$fatal(1,"Scalar/vector write collision admitted");
   @(negedge clk);write_valid=0;write_warp_valid=0;
   if(dut.memory[0]!==16'hdef0||dut.memory[1]!==16'h5678)$fatal(1,"Scalar priority/vector rejection failed");
   rst=1;@(negedge clk);rst=0;
   for(int packet=0;packet<64;packet++)begin
    if(req_ready)$fatal(1,"Native tile3 ready before final vector packet");
    for(int lane=0;lane<32;lane++)begin
     int halfword;logic[31:0]bits;halfword=32*packet+lane;
     bits=dyadic(halfword<1024?halfword%17-8:(halfword-1024)%13-6,4);
     write_warp_byte_addresses[lane]=32'(2*halfword);write_warp_halfwords[lane]=bits[31:16];
    end
    write_warp_mask='1;write_warp_valid=1;#0.001;
    if(!write_warp_ready)$fatal(1,"Legal warp packet not accepted");
    @(negedge clk);
   end
   write_warp_valid=0;
  end else begin
   for(int halfword=0;halfword<2048;halfword++)begin
    logic[31:0]bits;
    if(req_ready)$fatal(1,"Native tile3 ready before final referenced halfword");
    bits=dyadic(halfword<1024?halfword%17-8:(halfword-1024)%13-6,4);
    write_byte_address=32'(2*halfword);write_data=bits[31:16];write_valid=1;
    @(negedge clk);
   end
   write_valid=0;
   if(write_warp_ready)$fatal(1,"Disabled vector port admitted input");
  end
  for(int tile=0;tile<4;tile++)begin
   @(negedge clk);tile_index=32'(tile);req_id=32'(10+tile);#0.001;
   while(!req_ready)@(negedge clk);req_valid=1;@(negedge clk);req_valid=0;wait(rsp_valid);@(negedge clk);check_result(tile);
   repeat(3)@(negedge clk);
   if(!rsp_valid||rsp_id!=req_id)$fatal(1,"Held native result changed");
   rsp_ready=1;@(negedge clk);rsp_ready=0;
   @(negedge clk);
  end
  rst=1;@(negedge clk);
  if(rsp_valid||req_ready||operands_initialized||outstanding)$fatal(1,"Native reset failed");
  $display("NATIVE_STAGE_PASS checked_words=%0d requests=4 issue_trace_instructions=160",checked);$finish;
 end
endmodule
