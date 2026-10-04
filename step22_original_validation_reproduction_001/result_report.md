# Repeating the saved C++/Verilog model validation

Do the saved C++/Verilog model comparisons reproduce when we rerun their original models and GPU kernels? This repeat keeps that milestone's source, executable, parameters, and measurement methods. It does not substitute the later instruction model or its proposed compute correction. The earlier high-level phase-model milestone is being compared separately in Step23; this C++/Verilog model repeat concerns a different saved validation.

The four small GPU comparisons reproduce within 5%. The repeated large GPU comparisons give 3.27% and 5.08% error with the original reference-clock conversion. The small model repeats reproduce every recorded cycle count, cache counter, and numerical result. Both preserved large-model executions have now completed and reproduced their original cycle counts and counters exactly.

The separate [October 3 one-hour report](../one_hour_results_20261003.md) concerns high-level phase-cost models, rather than this C++/Verilog implementations. Its warm small grids use 128-by-96 outputs, and its dense grids include 1920-by-1920 and 2048-by-2112 outputs. It reports up to 4.20% warm small-grid error and 5.97%/2.46% dense-grid error for its two tile shapes. The [history inventory](highlevel_oct3_chronology.json) preserves those predictions and measurements. The 32-by-32 tile cases have now been repeated in [Step23](../step23_hlm_connected_gpu_reproduction_001/comparison_report.md); their identity differs from the C++/Verilog model cases below.

## Which original tests are being repeated?

Each workload multiplies an M-by-K matrix by a K-by-N matrix. M is the number of output rows, N is the number of output columns, and K is the reduction length. Inputs use 16-bit BF16 values and accumulation uses 32-bit FP32 values. The GPU kernel uses a 32-by-32 output tile and four warps, each containing 32 threads.

The accepted small model represents six active streaming multiprocessors, the GPU units that run blocks, with one block per unit and two shared-memory read slots. It retains the calibrated four-cycle additional cache-return delay and 3,346-cycle setup contribution. The setup contribution was fitted to the original K=64 case; this reproduction does not turn it into an independently measured hardware latency. The two other small reduction lengths, K=128 and K=768, were originally held out of that calibration.

The accepted large model uses 170 modeled multiprocessors, eleven block contexts per unit, 32 shared-read slots, and a provisional 48-slice, 96 MiB cache. Its inputs start resident in the modeled cache. This is a different model configuration and implementation from the calibrated small model. Each original configuration is repeated separately.

The GPU executes the preserved `diagnostic_057/gemm_32_32` binary. Its full SHA-256 is recorded in the [small GPU receipt](gpu/small_reproduction_receipt.json) and [large GPU receipt](gpu/large_reproduction_receipt.json). No GPU kernel was recompiled, optimized, or replaced. Its ordinary scalar global loads stage data into shared memory; explicit `.cg` loads occur in its warm-up helpers, not its GEMM body.

## Small model and testbench reproduction

Each model case executes an initial cold-cache launch followed by a launch retaining the previous cache contents. Both launches check all 6,144 output values against the numerical reference. The table shows elapsed model cycles, not an intrinsic instruction latency.

| Output dimensions | K | Original and repeated cold cycles | Original and repeated retained-cache cycles |
|---|---:|---:|---:|
| 64 × 96 | 64 | 19,491 | 13,852 |
| 64 × 96 | 128 | 30,111 | 19,408 |
| 64 × 96 | 768 | 136,311 | 74,968 |
| 64 × 96 | 1536 | 263,751 | 141,639 |

All four preserved C++ hosts reproduce the original counters and cycles exactly. The separately relinked testbench does so as well. Each execution path checks 49,152 numerical values across the four cases.

The original standalone testbench executable had been overwritten by the historical C++ host build. Its generated main, model archive, and runtime objects remain. They were relinked into separate executables without changing the model. This is a documented repeat of the original testbench behavior, rather than execution of the original standalone binary. Both hosts use the same Verilator-generated model; their agreement does not establish independent handwritten C++ versus Verilog equivalence. [The model-lane report](model_small/result_report.md) records commands, hashes, numerical checks, and this distinction.

## Small GPU comparisons

The original accepted comparison used profiler SM elapsed-cycle counts. The repeat uses the same profiling method. Error is `(model cycles − measured cycles) / measured cycles`; a negative value means the model predicts too little elapsed time. These are aggregate elapsed-cycle measurements, not active-warp cycles or individual instruction delays.

| K | Repeated model cycles | Original measured cycles | Repeated measured cycles | Original error | Repeated error |
|---:|---:|---:|---:|---:|---:|
| 64 | 13,852 | 13,852.31 | 13,956.86 | −0.002% | −0.751% |
| 128 | 19,408 | 19,375.44 | 19,709.74 | +0.168% | −1.531% |
| 768 | 74,968 | 75,657.89 | 77,183.27 | −0.912% | −2.870% |
| 1536 | 141,639 | 146,612.45 | 146,686.81 | −3.392% | −3.441% |

All four repeated comparisons remain within 5%. The repeated profiler durations are 4.768, 6.720, 26.144, and 49.824 microseconds, respectively. The corresponding reported SM elapsed-clock rates range from 2.927 to 2.952 GHz.

The separate CUDA-event repetitions are also preserved in the receipt. They are not substituted for the profiler durations in this cycle comparison. Their times can differ because the runs have different execution and clock conditions.

## Large GPU comparisons and completed model repeats

The original large comparison converts model cycles using a 2.94 GHz reference: 2,940 cycles per microsecond. This reference conversion is preserved. Concurrent clock telemetry is additional evidence; sampled NVML clock reports do not prove the instantaneous frequency of each kernel.

| Output dimensions | K | Original and repeated model cycles | Model time at reference clock (µs) | Original GPU median (µs) | Repeated GPU median (µs) | Repeated error |
|---|---:|---:|---:|---:|---:|---:|
| 2048 × 2112 | 1536 | 836,886 | 284.655 | 277.274 | 275.642 | +3.270% |
| 2048 × 2112 | 3072 | 1,636,081 | 556.490 | 532.448 | 529.587 | +5.080% |

The K=3072 result is about 0.08 percentage points outside a strict 5% cutoff. It is recorded as such; neither parameters nor measurements were adjusted to make it pass.

Both large-model repeats use the exact preserved executable and original arguments, verified against both source and binary hashes before launch. The [launch record](model_large/launch_receipt.json) identifies them. They check block retirement and coverage of all 4,325,376 output addresses; the large model carries no matrix-value payload. Their completion therefore establishes address and timing reproduction, rather than numerical output correctness. Both exited successfully; host execution took 549.017 and 1,010.099 seconds. The [completed comparison](model_large/completed_comparison.json) records every counter comparison.

On the physical GPU, every repeated case passed 45 full output-matrix comparisons. The source copies all M×N outputs after each of the nine groups of five launches and checks every value against the cuBLAS reference. The earlier description of this field as 45 sampled values was incorrect. The large simulator still carries no numerical payload; its address-coverage checks are distinct from these exhaustive GPU comparisons. Raw samples, commands, timestamps, executable hashes, and clock telemetry are retained under `gpu/`.

## What this repeat establishes

The earlier C++/Verilog model small-workload accuracy is supported by an actual repeat. It was not invalidated by the later 89,603-cycle result: that result used the different full-chip model configuration on a small workload. The original small-model prediction for that case is 141,639 cycles, and it reproduces exactly.

The repeated large GPU measurements remain close to their earlier values. Both exact large-model runs are complete, so this saved C++/Verilog model reproduction is finished. None of these results establishes a single calibrated model that already predicts every later direct-global or shared-memory path within 5%.
