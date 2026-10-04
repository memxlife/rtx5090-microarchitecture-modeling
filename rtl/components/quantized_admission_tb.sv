module quantized_admission_tb;
 logic clk=0;always #5 clk=~clk;
 logic rst=1,request=0,ready,retire=0;
 int threads=128,regs=40,shared_bytes=8192,reserved=1024,slot,blocks,warps,allocated_regs,allocated_shared,retire_slot=0;
 quantized_block_admission dut(clk,rst,request,threads,regs,shared_bytes,reserved,ready,slot,blocks,warps,allocated_regs,allocated_shared,retire,retire_slot);
 task automatic reset;
  @(negedge clk);rst=1;request=0;retire=0;@(negedge clk);rst=0;#1;
  assert(blocks==0 && warps==0) else $fatal;
 endtask
 task automatic admit(input int count);
  for(int i=0;i<count;i++)begin
   @(negedge clk);#1;assert(ready) else $fatal(1,"Expected admission %0d",i);request=1;
   @(negedge clk);request=0;#1;
  end
 endtask
 initial begin
  reset();admit(11);
  assert(blocks==11 && warps==44 && !ready && allocated_shared==9216) else $fatal(1,"Small saved GEMM occupancy");
  @(negedge clk);retire=1;retire_slot=0;#1;
  assert(!ready) else $fatal(1,"Retirement cannot free space before its edge");
  @(negedge clk);retire=0;#1;assert(ready && blocks==10 && warps==40) else $fatal;
  admit(1);assert(blocks==11 && !ready) else $fatal;
  reset();regs=64;shared_bytes=11264;admit(8);
  assert(blocks==8 && warps==32 && !ready && allocated_shared==12288) else $fatal(1,"Large saved GEMM occupancy");
  reset();threads=1024;regs=1;shared_bytes=0;reserved=0;admit(1);
  assert(blocks==1 && warps==32 && !ready) else $fatal(1,"Warp capacity");
  reset();threads=32;admit(24);
  assert(blocks==24 && warps==24 && !ready) else $fatal(1,"Block slot capacity");
  reset();shared_bytes=101377;#1;assert(!ready) else $fatal(1,"Perblock shared limit");
  shared_bytes=0;threads=0;#1;assert(!ready) else $fatal(1,"Invalid request");
  $display("QUANTIZED_ADMISSION_PASS");$finish;
 end
endmodule
