# Phase timing must preserve the execution being modeled

Our goal is an accurate performance model grounded in hardware mechanisms. We tested whether clock reads inside the original GEMM could measure operand staging and computation without materially changing execution. The answer depends on the tile: the smaller tile tolerates this instrumentation, while the larger tile does not. We therefore cannot use these readings as general hardware phase parameters.

## The experiment and its measurement rule

The original kernel stages BF16 operands from global memory into shared memory, synchronizes the block, performs matrix operations with FP32 accumulation, and synchronizes again before reusing shared memory. We sample one middle reduction stage, which processes 32 reduction elements. Its staging interval includes the first synchronization barrier; its computation interval includes the second. These intervals include scheduling and contention, rather than measuring isolated device latency.

We compare four separately compiled builds: no timestamps; two reads around the whole stage; three reads splitting its two phases; and three adjacent reads at stage entry. All builds retain the original matrix calculation, layouts, and necessary synchronization. Two workloads and two tiles are each tested in two paired repetitions, reversing build order. Every execution checks all outputs against cuBLAS and uses the established cache sweep before ordinary timing launches. The compiled instruction listings preserve the expected matrix instruction counts and both original barriers.

Before running, we required unchanged block residency, no spills, numerical correctness, and no more than 5% change in median whole-kernel time in either repetition. That is a measurement-admission rule, not an achieved prediction-accuracy target. Even passing it does not prove that a local interval is unbiased.

## Whole-kernel timing reveals the instrumentation effect

The table reports the change in whole-kernel elapsed time for the split-phase build relative to its paired uninstrumented baseline. Each range contains the two paired results; lower absolute change means less disturbance.

| Matrix shape: rows, columns, reduction length | Output tile | Timing change | Resident blocks per SM, baseline and split build | Decision |
|---|---|---:|---:|---|
| 960, 1152, 640 | 32 by 32 | +1.90% to +1.92% | 11 and 11 | Passes initial disturbance check |
| 1728, 2112, 2304 | 32 by 32 | +0.22% to +0.44% | 11 and 11 | Passes initial disturbance check |
| 960, 1152, 640 | 64 by 48 | +65.70% to +66.28% | 8 and 8 | Reject phase values |
| 1728, 2112, 2304 | 64 by 48 | +57.39% to +57.71% | 8 and 8 | Reject phase values |

All 32 executions passed correctness checks without register spills. The smaller tile uses 40 registers per thread in both baseline and split builds. The larger tile changes from 64 to 56 registers, but the resident-block limit remains eight. Its slowdown is therefore not explained by reduced block residency or spills. Retaining the arithmetic and memory layout does not establish that compilation retained the original instruction schedule.

The adjacent-read control changes whole-kernel time by less than 2% in every case. Its median span for three adjacent clock reads is two cycles. This span measures read spacing, not the full execution cost of the instrumentation, and cannot be subtracted to repair the much larger slowdown. The whole-stage two-read build slows the larger tile by roughly 88% to 100%, despite using fewer reads than the split build. Read count alone therefore does not predict the disruption.

## A bounded repair does not restore valid measurement

We removed the empty compiler memory barriers around timestamps while retaining the original GPU synchronization and clock reads. Twelve further executions compare the repaired larger-tile builds against a freshly timed baseline on both workloads, again reversing order across two repetitions. All outputs were correct, and no build spilled registers.

The repaired split build still slows by 65.72% to 65.73% on the smaller workload and 57.40% to 57.63% on the larger workload. It still uses 56 registers and permits eight resident blocks. The empty compiler barriers are therefore not sufficient to explain the disturbance. We reject these repaired readings as well. This does not uniquely identify the compiler transformation or hardware resource that causes the slowdown.

## What we can retain

For the smaller tile, the median sampled staging interval is 4025 cycles on the 960-by-1152-by-640 workload and 4424.5 cycles on the larger workload. Median computation intervals are 1387 and 1313.5 cycles. These are per-warp observations pooled across blocks and the two executions, from the last timed launch of each execution. They include their respective block barriers and should not be described as raw global-memory latency or Tensor Core latency.

The split build's median whole-stage interval is 5414 cycles on the smaller workload, close to the separate whole-stage build's 5401 cycles. On the larger workload, those medians are 5790 and 6144 cycles, a difference of about 5.8%. Small whole-kernel disturbance therefore does not guarantee consistent local phase measurements. We retain these values as diagnostic observations rather than fitting hardware constants from them.

The experiment samples only the middle reduction stage. Startup, later stages, different block waves, and contention can behave differently. Clock, temperature, and power snapshots accompany the original sweep, but clocks were not locked and snapshots cannot reconstruct every operating-state transition. Hardware caches remained active; explicit L2 modeling remains excluded.

## Consequence for the physically grounded model

This experiment prevents an invalid shortcut: inserting instrumented phase times into the model simply because outputs remain correct. The larger tile demonstrates that arithmetic correctness, identical matrix instruction counts, and unchanged block residency are insufficient to preserve execution timing.

The next measurement should attribute waiting to the original compiled kernel without recompiling it, using source-correlated hardware profiling where available. We should distinguish instruction demand, operand readiness, issue capacity, and memory-request concurrency. Those measurements must then support a specific execution model whose parameters have defined units and measured uncertainty. Its predictions must be checked on workloads not used to choose its parameters. A reduction in fitted timing error alone does not establish that the mechanisms are correctly identified.

The MILP model remains unchanged and its hash matches the preserved revision 005 model. We have not yet built or validated a more accurate physically grounded replacement, and the unique cause of its remaining error is unresolved. Evidence is preserved in the [experiment plan](experiment.md), [summary](summary.json), [original measurements](measurements.json), and [repair measurements](no_fence_measurements.json), alongside source and compiled instructions.
