# Testing the independent hardware components on real GEMM

## Question

Do the independently measured hardware components predict the execution time of the original GEMM kernels? This is the test that separates an accurate physical runtime model from several accurate small benchmarks. We fixed all component costs before running this experiment and used no GEMM timing to fit them.

The answer is still no. The components predict most of the extra cost of fetching cold data, but the simple assembled model underestimates a full reduction stage by 17–31%. The missing time remains substantial even when every requested sector hits L2. We preserve that failure instead of adding a fitted GEMM correction.

## Setup and prediction

We ran the original 32-by-32-by-32 and 64-by-48-by-32 tiles on matrix shapes with 64 output rows, 96 output columns, and reduction lengths of 4,096 and 16,384. A reduction stage consumes 32 elements along the reduction dimension. The two lengths contain 128 and 512 stages. The original compiled GPU functions are identical instruction for instruction; only the host's preparation and checking changed.

Before measurement, we initialized two 2 GiB operand allocations with the original deterministic BF16 input patterns. Each timed launch used different input regions, with offsets chosen to preserve the same matrix values. Initialization after the reference calculation and warmups displaced those early regions. For the warmed condition, a separate read kernel loaded the chosen regions into L2 while bypassing the first-level cache. This preparation was excluded from timing. Every measured output was compared with an independent cuBLAS result.

The assembled prediction used three independent sources. The ordinary global-load response experiment supplied cycles per four-load group. The shared-memory experiment supplied bank-processing demand. The register-resident matrix experiment supplied matrix progress cost at four warps. A warp is a group of 32 threads. The original small tile has four load groups per warp and stage; the large tile has seven. Those counts come from executed compiled instructions, rather than from requested byte counts alone.

We compared two incomplete ways to combine the compute costs. One adds bank work and matrix work after load response. The other lets their resource demands overlap and uses the larger demand. Neither includes a fitted cost for the original program's additional address calculation, operand waiting, instruction issue, or synchronization. Bank work and matrix capacity by themselves are resource requirements, not complete elapsed times. Therefore these are competing composition hypotheses, not proven timing bounds.

For fresh input, the dependency-aware hypothesis retained cold response for groups whose data were being fetched, including requests shared by concurrently running blocks. We also retained an average-hit-rate baseline for comparison. For warmed input, every group used the independently measured cached response. All predictions were saved before running the eight GEMM cases.

## Validation of the measured conditions

All 360 timed launches passed full output checks without register spills. The small tile used 40 registers per thread and the large tile used 64, as before. Four profiles verified the longer reduction cases:

| Tile | Fresh-input L2 hit fraction | Fresh-input miss sectors | Warmed-input L2 hit fraction |
|---|---:|---:|---:|
| 32 by 32 | 58.33% | 163,840 | 100% |
| 64 by 48 | 28.57% | 163,840 | 100% |

A sector is 32 bytes. The fresh-input misses exactly equal the sectors needed to read each input once; hits arise from reuse between blocks. Every warmed-input read hit L2. No profile had first-level cache hits.

Executed global-request counts, four- and seven-group structures, shared-read processing counts, and matrix-instruction counts all matched their independently derived values. Both tiles executed 49,152 native matrix instructions on the longer workload. The fresh and warmed conditions also had identical total instruction counts within each tile.

Operating frequencies in the profiles were approximately 2.934–2.946 GHz. Profiled device durations differed from ordinary measured medians by at most 0.37%, supporting use of those frequencies to convert the saved cycle costs to time. Post-run clock snapshots were lower in several cases and cannot reconstruct the frequency during the kernel. We retain that observation limit; we did not lock clocks or treat the nominal specification as the operating clock.

## Full-kernel stage comparison

For each condition, we subtract the median duration at 4,096 reduction elements from the median at 16,384 and divide by the additional 384 stages. This measures the incremental cost of a stage while removing fixed launch, setup, and final-output costs. The table therefore reports stage-cost accuracy measured in complete GEMMs, rather than an independently established error for total runtime at every shape.

| Tile | Input condition | Predicted stage, microseconds | Measured stage, microseconds | Error relative to measurement |
|---|---|---:|---:|---:|
| 32 by 32 | Fresh input | 1.515 | 1.887 | 19.71% |
| 32 by 32 | Warmed input | 0.673 | 0.979 | 31.31% |
| 64 by 48 | Fresh input | 2.742 | 3.290 | 16.66% |
| 64 by 48 | Warmed input | 1.278 | 1.719 | 25.68% |

These are the additive bank-and-matrix predictions. Allowing their resource costs to overlap produces still shorter predictions and larger errors. Neither composition met the 5% accuracy criterion.

The average-hit-rate baseline predicted approximately 1.025 microseconds for the smaller fresh-input stage and 2.323 microseconds for the larger one. Retaining dependent waiting improves those predictions to 1.515 and 2.742 microseconds, but does not explain the entire measured duration.

## What is explained and what remains

For the small tile, changing from warmed to fresh input adds 0.908 microseconds per stage. The independent response model predicts 0.842 microseconds, a 7.26% error. For the large tile, the measured addition is 1.570 microseconds and the prediction is 1.464, a 6.75% error. Thus the response mechanism captures about 93% of this extra cold-data cost without fitting GEMM timings.

The additive model still leaves 0.307 microseconds unexplained in the smaller warmed-input stage and 0.442 microseconds in the larger one. Fresh-input residuals are 0.372 and 0.548 microseconds. Most of the unexplained time therefore survives when every requested value is already in L2. Matching cache counts does not prove correct cache timing, but external-memory fetch alone cannot account for the whole residual.

The next test will measure the path from the actual shared-memory operand loads into matrix instructions. The current bank model describes how much processing is required, and the matrix model describes register-resident execution capacity; neither describes all of the waiting between those operations. If that path does not account for the residual, we will measure the original address-production and synchronization dependencies separately. Stall percentages will guide where to look, rather than being treated as fractions of elapsed time.

The composed model is explicitly recorded as an unsuccessful timing predictor in [stage_composition_evidence.json](../model_components/stage_composition_evidence.json). Its independent components remain useful evidence, but they are not promoted as an accurate full GEMM runtime model. The full requested physical model remains unfinished.

[analyze.py](analyze.py) reproduces [verification.json](verification.json). The saved predictions, exact compiled comparisons, raw timing samples, every-launch correctness receipts, cache and instruction profiles, and clock snapshots are preserved in this directory.
