# Round 1: easy documentation sweep

This round checked public NVIDIA references found through Google in Chrome. It ran no GPU benchmark. Five functional fields became identified in their stated domain; four others became partially identified. No timing field became identified.

| Category | Newly identified | Cumulative identified | Remaining, including partial |
|---|---:|---:|---:|
| Functional/structural | 5 | 5 / 87 | 82 |
| Timing | 0 | 0 / 47 | 47 |
| Total | 5 | 5 / 134 | 129 |

The four partial fields remain in the 129 unresolved entries. No new fields were added. Identified means supported by the reference in the named scope; it does not mean the implementation already reproduces that hardware.

## Identified fields and model consequences

| Field | Finding | Consequence |
|---|---|---|
| F013 | Four architectural scheduler partitions per SM | Model partitioned scheduling; assignment/arbitration remain unknown |
| F053 | Shared reads support broadcast/multicast | Same-word consumers need not be priced as independent conflicting words |
| F081 | Named CTA barrier participant rules | Support full-block or legal explicit participant counts |
| F082 | Named CTA barriers reset on completion | Keep reuse generations separate |
| F083 | Participant-relative memory visibility is required | Do not interpret barrier completion as universal DRAM writeback |

Sources: [RTX whitepaper, Figure 5](https://images.nvidia.com/aem-dam/Solutions/geforce/blackwell/nvidia-rtx-blackwell-gpu-architecture.pdf#page=11), [CUDA shared-memory rules](https://docs.nvidia.com/cuda/cuda-c-best-practices-guide/index.html#shared-memory-and-memory-banks), [PTX CTA barriers](https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#parallel-synchronization-and-communication-instructions-bar).

## Partial findings and exclusions

The RTX whitepaper identifies unified FP32/INT32 execution, four architectural Tensor Core blocks per SM, a 128 KiB unified L1/shared pool and sixteen 32-bit memory controllers. These narrow F029, F030, F054 and F075. They do not identify all pipeline sharing, internal tensor pipelines, the selected cache partition or DRAM banks. [RTX whitepaper, pages 10–12 and 46–47](https://images.nvidia.com/aem-dam/Solutions/geforce/blackwell/nvidia-rtx-blackwell-gpu-architecture.pdf).

PTX leaves BF16 WMMA accumulation order, rounding and subnormal treatment unspecified. The sequential-FMA model therefore remains a reference convention, not identified NVIDIA arithmetic. Descriptions of prompt barrier restart do not supply a measured zero-cycle release/resume delay. [PTX WMMA semantics](https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#warp-level-matrix-instructions-wmma-mma).

The Blackwell tuning guide confirms occupancy limits for compute capability 12.0, but its later B200-specific cache discussion is not an RTX configuration. The existing 100 KiB runtime allocation context and 99 KiB opt-in block limit remain alongside the published unified-pool figure. No cache geometry or timing is inferred from that comparison. [Blackwell tuning guide](https://docs.nvidia.com/cuda/blackwell-tuning-guide/index.html).

## Next sweep

Continue with CUDA/PTX operation and ordering contracts and saved native instruction records. Profile uncertain physical timing only after GPU work is authorized. Prefer a short test that can resolve several related fields, and preserve the largest runtime error as the guide when selecting expensive experiments.
