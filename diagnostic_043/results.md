# Matched global loads make pointer retention a small effect

We asked whether repeated pointer reloads account for the missing GEMM time. The preceding experiment changed global-load instruction form and reduced load overlap, making it unsuitable for that question. Here both versions explicitly use the same global-load instruction. One uses kernel-parameter pointers; the other reads the pointers from device memory before the loop.

Both tiles use four warps, 64 output rows, 96 output columns, warmed inputs, and inner dimensions 4,096 and 16,384. The table estimates repeated-stage time by subtracting the two median runtimes and dividing by 384 additional stages. This removes fixed setup costs, including the initial pointer reads, but does not prove that all interaction with setup is absent.

| Tile | Parameter-pointer stage time | Retained-pointer stage time | Net reduction |
|---|---:|---:|---:|
| 32 by 32 | 0.992 microseconds | 0.960 microseconds | 3.25% |
| 64 by 48 | 1.737 microseconds | 1.722 microseconds | 0.86% |

All 360 complete output checks against cuBLAS succeeded. Both smaller-tile versions allocate 40 registers per thread and permit 11 resident blocks; both larger-tile versions allocate 64 registers and permit eight blocks. None spills registers.

Four profiles verify the same input-load instruction form and four-load grouping. The smaller tile has four groups and the larger has seven per warp per stage. Retaining pointers removes all repeated 64-bit parameter loads: 16 and 28 per warp per stage, respectively. Input reads hit L2; the retained-pointer profiles have one missing sector in the extra setup traffic.

The comparison still changes address and integer instructions. Total repeated warp instruction counts are 293 versus 293 for the smaller tile, and 668 versus 677 for the larger. These kernels also differ from the unchanged C++ baseline. The result therefore measures a net effect of a compiled-path intervention, not the intrinsic latency of a parameter-load instruction. It does not prove that pointer loads are free, or quantitatively partition the original model error.

## Model update and next question

The model now composes response cost from observed compiled load groups, and refuses an uncalibrated global-load instruction form. This uses the same measured response coefficients; it does not fit new ones. Regression checks preserve matching group counts here and the instruction-form rejection from the preceding experiment. The learning registry records both the net timing result and its remaining confounds.

The small net benefit is insufficient evidence for adding a large pointer-load penalty to explain the missing time. The unchanged-kernel validation remains a 25.3% and 17.8% underestimate of additional runtime. Those numbers are separate tests, not estimates recomputed from this transformed kernel.

The next question is whether the original global staging and operand computation interact differently from isolated probes. A useful control should keep both paths inside one compiled kernel, use ordinary external timing, and avoid the extra checksum and intrusive timing instructions that invalidated earlier stage comparisons. Its compiled paths must be checked before costs transfer to the model.

Evidence: [measurement verification](verification.json), [dynamic instruction analysis](profile_analysis.json), and [model experiment registry](../model_components/learning_registry.json).
