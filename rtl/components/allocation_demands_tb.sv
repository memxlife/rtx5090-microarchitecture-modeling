module allocation_demands_tb;
 int threads,regs,shared_bytes,reserved,actual_regs,launch_regs,actual_shared;
 logic valid;
 allocation_demands dut(threads,regs,shared_bytes,reserved,valid,actual_regs,launch_regs,actual_shared);
 initial begin
  // Saved GEMM resource records: round compiler usage, including runtime reservation.
  threads=128;regs=40;shared_bytes=8192;reserved=1024;#1;
  assert(valid && actual_regs==5120 && launch_regs==5120 && actual_shared==9216) else $fatal;
  threads=128;regs=64;shared_bytes=11264;#1;
  assert(valid && actual_regs==8192 && actual_shared==12288) else $fatal;
  // Quantization and partial-warps affect allocation, not merely raw byte totals.
  threads=33;regs=9;shared_bytes=129;reserved=0;#1;
  assert(valid && actual_regs==1024 && launch_regs==2048 && actual_shared==256) else $fatal;
  threads=0;#1;assert(!valid && actual_regs==0 && actual_shared==0) else $fatal;
  threads=32;regs=256;#1;assert(!valid) else $fatal;
  regs=1;shared_bytes=-1;#1;assert(!valid) else $fatal;
  $display("ALLOCATION_DEMANDS_PASS");$finish;
 end
endmodule
