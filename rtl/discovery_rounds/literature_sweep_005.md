# CUDA and PTX parameter research: round 5

Which missing RTX 5090 rules can official documentation establish without another GPU experiment? This review used Google through Chrome to locate NVIDIA sources, then read the relevant CUDA 13.4 and PTX ISA 9.4 sections. It proposes two allocation rules and six partial findings for the hardware manual. It does not change the shared parameter registry.

## Allocation rules from the installed NVIDIA toolkit

The coordinator retrieved the official CUDA 12.8.93 `cuda_occupancy.h` header from the existing GPU environment. Its compute-major-12 branch specifies **256 register words per warp allocation quantum (F001)** and **128 bytes per block shared-memory allocation quantum (F002)**. These are complete rules within the toolkit occupancy model; they do not identify physical register-bank or SRAM geometry.

The register calculation rounds the product of registers per thread and warp size up to 256 before multiplying by the number of warps. A separate launch-admission check rounds warp count up to the number of SM partitions. The shared-memory calculation adds static, dynamic and per-block reserved memory, then rounds the byte total up to 128. Thus omitting reserved memory changes the predicted occupancy even when application storage is counted correctly. The coordinator will check these functions locally before admitting the two fields. The source digest and exact line locations are in the companion JSON.

## Parameters constrained by documentation

| Field | Documented rule | What still needs measurement or native instruction analysis |
|---|---|---|
| F011: divergence | Divergent paths disable lanes that are not executing that path. Modern GPUs retain execution state per thread. | How the native scheduler selects divergent work. |
| F012: reconvergence | Threads can regroup below full-warp size. | The regrouping algorithm and control-state storage. |
| F028: numerical semantics | Scalar `fma.rn.f32` rounds once to nearest-even after forming the product and sum; `.ftz` changes subnormal treatment. | Complete native instruction coverage and Tensor Core numerical rules. |
| F032: matrix operands | A BF16 16 × 16 × 16 WMMA fragment uses four 32-bit registers for each input per thread and eight FP32 accumulator registers. | Which matrix elements belong to each lane and native register. |
| F040: global transactions | Ordinary warp accesses use the required 32-byte segments on compute capability 6.0 and later. | Wider native operations, request splitting and result assembly. |
| T015: execution service | The cc12.0/12.1 table gives theoretical peaks of 128 FP32 arithmetic results, 128 integer additions, 64 integer multiplications or shifts, and 32 converged shuffle results per SM cycle. | Individual pipeline acceptance intervals, interference between classes and result latency. |

Divergence and reconvergence are documented in [Advanced Kernel Programming, §3.2.2.1](https://docs.nvidia.com/cuda/cuda-programming-guide/03-advanced/advanced-kernel-programming.html#independent-thread-scheduling). Scalar arithmetic is specified in [PTX floating-point FMA](https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#floating-point-instructions-fma). The [WMMA fragment section](https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#matrix-fragments-for-wmma) explicitly leaves element identities unspecified. Thus the fragment size helps define an interface, but does not recover native routing.

The global transaction rule comes from [CUDA Best Practices §10.2.1](https://docs.nvidia.com/cuda/cuda-c-best-practices-guide/index.html#coalesced-access-to-global-memory). The service ceilings come from its [native arithmetic table](https://docs.nvidia.com/cuda/cuda-c-best-practices-guide/index.html#arithmetic-instructions-throughput-native-arithmetic-instructions). The table was read with its merged columns preserved. These ceilings can reject impossible predicted rates; they cannot supply an instruction's dependent-use delay.

## A documentation conflict that matters for occupancy

The [Programming Guide's cc12.x tables](https://docs.nvidia.com/cuda/cuda-programming-guide/05-appendices/compute-capabilities.html#features-and-technical-specifications) give **24 resident blocks and 100 KiB shared memory per SM**. The [Blackwell Tuning Guide](https://docs.nvidia.com/cuda/blackwell-tuning-guide/index.html#occupancy), also version 13.4, instead gives 32 blocks and 128 KiB for cc12.0.

The saved RTX 5090 profile in `diagnostic_042/profile_64_48_p2_k16384_c1.raw.csv` reports `device__attribute_max_blocks_per_multiprocessor = 24`, `device__attribute_limits_max_cta_per_sm = 24`, and `device__attribute_max_shared_memory_per_multiprocessor = 102400` bytes. It agrees with the Programming Guide. The opt-in block limit is 101376 bytes, or 99 KiB. The separately documented 128 KiB unified L1/shared pool must not be substituted for allocatable shared memory.

This corrects a possible source assumption rather than resolving a new inventory field. The manual should use the saved device values for this hardware and preserve the source discrepancy.

## What this round does not establish

The register-allocation example of 256 registers per warp is explicitly for cc7.0; it cannot establish F001 on cc12.0 by analogy. The retrieved toolkit header supplies direct cc12 support instead. The H100/B200 shared-memory partition choices do not establish F048 on RTX 5090. The documented barrier-throughput paragraph covers older compute capabilities and does not identify T043 on cc12.0. PTX defines virtual instruction behavior, so its matrix fragment sizes must not be treated as native physical register routing or timing.

## Parameter count and model consequences

This receipt proposes **two fully specified functional fields**, subject to the coordinator’s local header checks. Five other functional fields and one timing field gain partial evidence. If all candidates are accepted, the totals become **seven identified functional fields, zero identified timing fields, and 80 functional + 47 timing = 127 remaining**. Until integration, the authoritative registry remains unchanged.

The proposed model changes are to retain per-thread control state, represent disabled lanes, require explicit scalar rounding modes, distinguish virtual matrix fragments from native operands, count global service segments, and constrain aggregate execution rates by documented ceilings. All private arbitration and timing values remain explicit unknowns. No hardware experiment was run for this review.
