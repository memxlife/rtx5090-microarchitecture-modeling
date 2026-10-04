# What the fast cuBLASLt implementation actually does

For the same 192-by-3072 times 3072-by-768 BF16 multiplication, the captured cuBLASLt configuration divides the reduction into eight pieces and uses a larger output tile with six shared-memory staging buffers. These are concrete differences from our direct-load kernel. They explain how the library can expose more parallel work and overlap memory delivery with computation. We have not yet measured how much of the speedup each mechanism contributes.

## Evidence and its scope

The original timing comparison was 9.200 microseconds for tuned cuBLASLt versus 43.519 microseconds for our direct kernel. A later capture recreated the same library version, matrix dimensions, data types, algorithm ID, heuristic index, and workspace requirement, and recorded the algorithm attributes and actual launches. All 147,456 output values passed its numerical check. See [the capture receipt](../step20_lt_winner_capture_001/validation_receipt.json), [capture source](../step20_lt_winner_capture_001/capture.cu), and [raw launch measurements](../step20_lt_winner_capture_001/profile.csv).

This is a reproduction of the matching configuration, not byte-for-byte restoration of a serialized original descriptor. The capture did not measure a new runtime or preserve disassembly of the exact launched functions. The earlier 9.200-microsecond timing remains the performance evidence.

## Three identified mechanisms

**1. Divide the long reduction among independent blocks.** The queried split-K count is eight, and the trace contains both a matrix-product kernel and a separate reduction kernel. Instead of one block following all 3072 reduction elements, the library divides that work into eight equal-sized mathematical contributions, each covering 384 elements, then adds the partial results. The configured workspace is 4,718,592 bytes: exactly eight copies of the 589,824-byte FP32 output. The exact order of operations within each partition remains to be decoded. NVIDIA describes the separate-workspace reduction scheme in [the cuBLAS documentation](https://docs.nvidia.com/cuda/archive/12.8.1/cublas/index.html#cublasltreduction-scheme-t).

**2. Compute a larger output tile per block.** The captured function name identifies a 64-by-64 output tile with a reduction stage of 32 elements. Our kernel uses a 32-by-32 output tile. Both launch four warps per main block, but the larger tile provides four times as many output accumulations per block. It offers more opportunities to reuse each operand across arithmetic operations. The exact per-warp partition and register mapping are not established by the name alone.

There are 36 logical 64-by-64 output tiles. Eight reduction partitions therefore provide 288 logical tile-partition tasks. The captured grid launches 384 blocks, probably including padding associated with its coordinate mapping; the extra blocks must not be counted as useful computation without decoding that mapping. Our direct kernel launches 144 blocks and has no reduction partitioning. The library therefore trades larger tiles for additional reduction parallelism rather than simply choosing the largest tile.

**3. Buffer future input tiles while computing the current tile.** The captured name specifies six stages; the main kernel reserves 49,152 bytes of dynamic shared memory. A pair of BF16 input tiles for one 64-by-64-by-32 stage occupies `(64×32 + 32×64)×2 = 8,192` bytes. Six such pairs occupy exactly the reported allocation. This agrees with six staging buffers. NVIDIA defines stage settings as the depth of shared-memory buffering in [the cuBLAS stage documentation](https://docs.nvidia.com/cuda/archive/12.8.1/cublas/index.html#cublasltmatmulstages-t).

The public CUTLASS multistage implementation prefetches future tiles, commits and waits for asynchronous copies, and alternates register fragments while performing matrix operations. That gives a concrete implementation hypothesis for this captured CUTLASS-family kernel. It is not proof of its exact machine instructions. See [NVIDIA's multistage source](https://github.com/NVIDIA/cutlass/blob/v3.8.0/include/cutlass/gemm/threadblock/mma_multistage.h). Our direct kernel has no explicitly programmed alternate input buffers; compiler scheduling may still create some overlap.

## Resource tradeoff and remaining uncertainty

The library main kernel uses 96 registers per thread and 48 KiB dynamic shared memory, compared with 38 registers per thread and no shared input staging in our direct kernel. Higher register occupancy is therefore not a supported explanation for its advantage. Resource allocations alone do not establish achieved occupancy, tensor-core activity, or stall duration.

The captured main launch is 384 blocks of 128 threads. Its reduction launch is 288 blocks of 512 threads. The original timing includes the complete library call, so the second kernel's cost is already included in the 9.200 microseconds. There is no evidence yet that this implementation uses TMA or Tensor Memory. A separate disassembly study examined another shipped library function; transferring its instructions to this winner would be incorrect.

The smallest remaining inspection is to disassemble the exact captured function from the same hashed library for SM120. That can identify asynchronous copy instructions, shared matrix loads, tensor-core operations, register alternation, and padded-grid exits without launching new GPU work. A later controlled experiment can compare the same tile and stage configuration with split-K disabled, and then vary stage depth separately. Until those matched measurements exist, the mechanisms are identified, but the 4.73-fold speedup cannot be assigned quantitatively to each one.
