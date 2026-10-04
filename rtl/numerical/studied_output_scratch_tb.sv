`timescale 1ns/1ps
module studied_output_scratch_tb #(parameter int STORE_RETURN_DELAY=7,RETURN_DELAY=11,READ_SLOTS=1);
 logic clk=0;always #0.05 clk=~clk;
 logic rst=1,req_valid=0,req_ready,rsp_valid,rsp_ready=0;
 logic[31:0]req_id=41,rsp_id,c_registers[4][32][8],row_major_words[4][256];
 int outstanding,store_requests,store_commit_words,read_requests,read_completions,cycle=0,checked=0;
 logic[31:0]held_words[4][256];
 studied_output_scratch_pipeline #(.STORE_INTERVAL(3),.STORE_RETURN_DELAY(STORE_RETURN_DELAY),.READ_SLOTS(READ_SLOTS),.READ_INTERVAL(2),.READ_RETURN_DELAY(RETURN_DELAY))dut(.*);
 function automatic logic[31:0]coordinate_bits(input integer warp_id,row,col);
  // Positive normal finite FP32 bit identities; independent of lane-array order.
  return 32'h3f000000+32'(warp_id*65536+row*256+col);
 endfunction
 always @(posedge clk)begin
  cycle<=cycle+1;if(cycle>100000)$fatal(1,"Scratch output timeout");
  if(!rst)begin
   if(read_requests>0&&store_commit_words!=1024)$fatal(1,"Scratch read preceded all store commits");
   if(store_commit_words>1024||read_requests>32||read_completions>32)$fatal(1,"Scratch conservation overflow");
  end
 end
 task automatic fill;
  begin for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)begin
   integer i;i=native_bf16_layout::c_element_index(l,e);c_registers[w][l][e]=coordinate_bits(w,i/16,i%16);
  end end
 endtask
 task automatic offer;
  begin @(negedge clk);while(!req_ready)@(negedge clk);req_valid=1;@(negedge clk);req_valid=0;
   // The accepted request owns a snapshot; subsequent external changes are irrelevant.
   for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)c_registers[w][l][e]=32'hdeadbeef;
  end
 endtask
 task automatic check;
  begin
   if(rsp_id!=req_id||store_requests!=16||store_commit_words!=1024||read_requests!=32||read_completions!=32)$fatal(1,"Scratch response identity/count mismatch");
   for(int w=0;w<4;w++)for(int i=0;i<256;i++)begin
    if(row_major_words[w][i]!==coordinate_bits(w,i/16,i%16))$fatal(1,"Scratch coordinate mismatch warp%0d element%0d",w,i);
    held_words[w][i]=row_major_words[w][i];checked++;
   end
  end
 endtask
 initial begin
  fill();repeat(3)@(negedge clk);rst=0;offer();wait(store_requests>0);@(negedge clk);rst=1;
  repeat(2)@(negedge clk);rst=0;
  if(rsp_valid||outstanding||store_requests||store_commit_words||read_requests||read_completions)$fatal(1,"Scratch reset failed to cancel work");
  for(int replay=0;replay<2;replay++)begin
   req_id=32'(51+replay);fill();offer();wait(rsp_valid);@(negedge clk);check();
   repeat(4)begin @(negedge clk);
    if(!rsp_valid||rsp_id!=req_id)$fatal(1,"Held scratch response changed");
    for(int w=0;w<4;w++)for(int i=0;i<256;i++)if(row_major_words[w][i]!==held_words[w][i])$fatal(1,"Held scratch payload changed");
   end
   rsp_ready=1;@(negedge clk);rsp_ready=0;
  end
  $display("OUTPUT_SCRATCH_PASS checked_words=%0d store_delay=%0d read_delay=%0d read_slots=%0d",checked,STORE_RETURN_DELAY,RETURN_DELAY,READ_SLOTS);$finish;
 end
endmodule
