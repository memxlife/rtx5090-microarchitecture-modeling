// CUDA allocation-model arithmetic for cc12.0; not physical warp placement.
module allocation_demands #(
 parameter int REG_QUANTUM_WORDS=256,
 parameter int SHARED_QUANTUM_BYTES=128,
 parameter int WARP_THREADS=32,
 parameter int PARTITIONS=4,
 parameter int MAX_THREADS=1024,
 parameter int MAX_REGS_PER_THREAD=255
)(
 input int block_threads,registers_per_thread,user_shared_bytes,reserved_shared_bytes,
 output logic valid,
 output int allocated_register_words,launch_check_register_words,allocated_shared_bytes
);
 int warps,register_words_per_warp;
 always_comb begin
  valid=block_threads>0 && block_threads<=MAX_THREADS &&
        registers_per_thread>=0 && registers_per_thread<=MAX_REGS_PER_THREAD &&
        user_shared_bytes>=0 && reserved_shared_bytes>=0 &&
        REG_QUANTUM_WORDS>0 && SHARED_QUANTUM_BYTES>0 && WARP_THREADS>0 && PARTITIONS>0;
  warps=0;register_words_per_warp=0;
  allocated_register_words=0;launch_check_register_words=0;allocated_shared_bytes=0;
  if(valid) begin
   warps=(block_threads+WARP_THREADS-1)/WARP_THREADS;
   register_words_per_warp=((registers_per_thread*WARP_THREADS+REG_QUANTUM_WORDS-1)/REG_QUANTUM_WORDS)*REG_QUANTUM_WORDS;
   allocated_register_words=register_words_per_warp*warps;
   launch_check_register_words=register_words_per_warp*((warps+PARTITIONS-1)/PARTITIONS)*PARTITIONS;
   allocated_shared_bytes=((user_shared_bytes+reserved_shared_bytes+SHARED_QUANTUM_BYTES-1)/SHARED_QUANTUM_BYTES)*SHARED_QUANTUM_BYTES;
  end
 end
endmodule
