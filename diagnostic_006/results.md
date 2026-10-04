# What limits the matrix loop on RTX 5090?

We want a performance model that explains execution through measurable hardware mechanisms. This experiment asks whether dependencies between matrix operations introduce substantial waiting beyond the matrix execution rate. It also checks how that rate changes when more warps execute together. The experiment used GPU 7 on the authorized RTX 5090 server. The existing MILP model was not changed.

## The controlled comparison

Each warp performs 16,384 BF16 matrix operations with FP32 accumulation. An operation computes a 16-by-16 output tile with a reduction length of 16. Inputs are loaded into registers before the timed loop. We compare one, two, four, and eight independent accumulator chains, always performing the same work. Every loop iteration contains eight operations, so the variants have the same loop count. All output elements are consumed and checked against an exact expected result.

The compiled GPU instructions confirm that each loop contains 16 instances of the same HMMA.16816.F32.BF16 instruction: two hardware instructions per matrix operation. Register use increases from 25 to 76 registers per thread across the four variants. None spills registers to local memory. These resource changes are recorded rather than treated as identical occupancy.

We performed five repeats for each configuration, using one or 170 blocks, one, four, or eight warps per block, and either 16,384 or 4,096 operations per warp. All 240 corrected measurements passed their numerical checks. The shorter loops give similar cycles per operation, supporting that startup and final output reduction are small at these lengths. Cycles are averaged over the participating warps within each run; the table reports the median of five runs. Lower cycles per operation means less elapsed work for each warp.

| Active warps in one block | One accumulator chain | Eight independent chains |
|---|---:|---:|
| 1 | 64.013 cycles per operation | 64.465 cycles per operation |
| 4 | 64.217 cycles per operation | 64.325 cycles per operation |
| 8 | 127.997 cycles per operation | 128.015 cycles per operation |

Independent chains do not materially reduce time. The one-warp eight-chain result is slightly slower and its repeat range overlaps the one-chain range. This comparison therefore does not support a large dependency-hiding benefit for this compiled primitive. It does not separately measure the exact latency of one hardware instruction.

Moving from four to eight warps doubles total work and approximately doubles each warp's loop time. Consequently aggregate matrix throughput stays approximately constant: this register-resident loop reaches a throughput ceiling. One warp and four warps have similar per-warp costs, so throughput initially scales with parallel work. The 170-block cases reproduce these cycle costs closely. This supports explicitly representing finite execution capacity, but does not uniquely identify the limiting Tensor Core, issue path, or operand-collection resource.

## What the complete GEMM profiles suggest

We also profiled the existing 32-by-32-by-32 and 64-by-48-by-32 tiles on the same 1728-by-2112-by-2304 workload. These were profiler runs, not ordinary timing confirmations. Profiling can change clock and cache conditions, so its elapsed times must not replace the earlier confirmation timings.

| Profiler observation | Smaller tile | Larger tile |
|---|---:|---:|
| Long-scoreboard stalls | 29.20% | 35.18% |
| Barrier stalls | 8.06% | 4.97% |
| Short-scoreboard stalls | 8.31% | 6.82% |
| Math-pipeline throttle stalls | 0.99% | 2.99% |
| Eligible warps per active scheduler cycle | 1.10 | 0.84 |

A scoreboard tracks whether operands are ready. Long-scoreboard stalls indicate waiting for operands associated with the global/local/texture memory path. Short-scoreboard stalls cover other operand waits, including shared-memory operations. These percentages describe warp scheduling observations; they are not fractions of total kernel time and cannot be added to predict runtime.

The profiles direct the next investigation toward the actual memory-to-shared-memory path and synchronization. They do not establish that memory waiting explains the remaining prediction error, nor distinguish memory latency from insufficient outstanding requests or the placement of loads and barriers. A matched experiment on that path is still needed.

## Measurement boundaries and next decision

Clock snapshots changed from idle frequency to operating frequencies during the run. We did not lock clocks or alter power limits. Cycle measurements remain more useful than elapsed milliseconds for this comparison, but snapshots cannot reconstruct every frequency transition or prove that all subsystem conditions were constant. Explicit L2 modeling remains excluded; caches remained active.

The first development probe consumed only one accumulator element and allowed the compiler to discard half the matrix output. Its variants also had different loop counts. Its apparent roughly 10% improvement with independent chains was not a valid dependency result and is superseded by the corrected experiment. The original measurements and instruction listing are preserved in development_first.

The model should distinguish per-warp progress from aggregate execution capacity. This diagnostic does not justify adding a large independent-chain benefit. The next bounded question is whether the timing residual follows operand waiting in the actual GEMM staging path. That requires a matched staging experiment before changing model coefficients. We have not yet executed the isolated memory experiment, refitted the MILP model, or proven the cause of its residual timing errors.

Raw corrected measurements are in [measurements.json](measurements.json), clock and power snapshots in [telemetry.json](telemetry.json), and compiled instructions in [probe.sass](probe.sass). The implementation and pre-run rationale are in [experiment.md](experiment.md). These files preserve the evidence separately from interpretation.
