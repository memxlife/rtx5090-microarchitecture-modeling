# Original workloads: three-way runtime comparison

Do the original high-level model and the full-chip handwritten C++ model predict the same RTX 5090 measurements? This comparison repeats six original matrix multiplication workloads with 32×32 output tiles. For a shape M×N×K, the output has M rows and N columns, and each output sums K products.

The GPU repeats and high-level predictions are complete. All six C++ model rows are complete. No timing parameters have been retuned for this comparison.

Signed error is 100 × (predicted time / measured time − 1). Positive error means an overestimate. All times below are microseconds.

| Matrix shape M×N×K | Implementation tested | High-level performance model | Implementation prediction | Fresh GPU time | High-level error | Implementation error |
|---|---|---:|---:|---:|---:|---:|
| 128×96×12288 | C++ model | 366.713 | 226.873 | 380.346 | -3.58% | -40.35% |
| 128×96×49152 | C++ model | 1455.458 | 898.296 | 1519.213 | -4.20% | -40.87% |
| 1920×1920×1536 | C++ model | 257.463 | 245.188 | 244.518 | +5.29% | +0.27% |
| 1920×1920×4608 | C++ model | 728.542 | 697.588 | 693.037 | +5.12% | +0.66% |
| 2048×2112×1536 | C++ model | 293.383 | 284.655 | 275.629 | +6.44% | +3.27% |
| 2048×2112×4608 | C++ model | 828.699 | 826.954 | 781.101 | +6.09% | +5.87% |

All C++ model cycle counts are converted using the unchanged 2.94 GHz reference: 2,940 cycles per microsecond. This is a reference-clock comparison, rather than a claim that the GPU maintained that exact frequency. GPU times are the median of nine samples, each timing five launches with CUDA events using the original method; clocks sampled every 10 milliseconds provide context. The high-level predictions retain their original time calibration.

All six GPU cases passed 45 full-matrix numerical comparisons each. The large C++ model checks addresses and execution counters without computing numerical payloads. Separately, the earlier four small C++/Verilog cases agreed exactly in values and cycles; both paths use the same Verilator-generated model. That parity does not establish hardware timing accuracy on these six workloads.

The high-level model’s largest error here is 6.44%. It therefore does not meet a strict 5% limit on every repeated case. The two small-grid C++ predictions underestimate runtime by 40.35% and 40.87%. Its dense-grid errors range from +0.27% to +5.87%. This unchanged full-chip configuration therefore meets the 5% timing target in three of six cases. The high-level model meets it in two of six cases, with maximum error 6.44%. 3 cases remain pending. No Verilog comparison is being run.

All six cases use the preserved full-chip C++ executable with the same hardware settings: 170 streaming multiprocessors (SMs), 11 resident block contexts per SM, 32 shared-memory read service slots, and 48 modeled L2 cache slices. The small cases are new predictions from this C++ implementation, rather than repeats of the earlier calibrated small Verilog configuration. The C++ implementation also omits the separate per-SM cache modeled in that Verilog configuration. Its accuracy on the small workloads must therefore be measured rather than inferred from the earlier Verilog results.

A newly elaborated small Verilog test was stopped at the user's request before completion; it supplies no prediction. No further Verilog builds or executions are part of this comparison.

## Direct-load workloads and the large errors

The direct-load kernel feeds operands to matrix operations without the original global-to-shared staging path. The unchanged high-level performance model has no applicable prediction for these workloads. The full-chip C++ model used above also hardcodes staging, so it cannot represent the direct kernel. Assigning either model an error here would compare different execution paths.

A separate C++ instruction model was previously tested on the actual direct-kernel instruction sequence. Python then combines its cycle count with an approximate startup/output cost and a memory-service bound. The following are those recorded predictions and GPU measurements, not new full-chip C++ runs. Predictions use the same 2.94 GHz reference; GPU times are CUDA-event medians. They are not substitutes for the C++ implementation in the first table.

| Direct-kernel variant | M×N×K | Adapted high-level prediction (µs) | Separate C++ instruction model plus phase costs (µs) | GPU time (µs) | Adapted high-level error | C++ plus phase error |
|---|---|---:|---:|---:|---:|---:|
| Original, 144 blocks | 192×768×1024 | 14.029 | 11.764 | 15.133 | -7.30% | -22.26% |
| Original, 144 blocks | 192×768×2048 | 24.260 | 20.773 | 29.251 | -17.06% | -28.98% |
| Original, 144 blocks | 192×768×3072 | 34.491 | 29.797 | 43.515 | -20.74% | -31.53% |
| Specialized .cg, one block | 192×768×1024 | Not evaluated | 11.517 | 14.329 | Not evaluated | -19.62% |
| Specialized ordinary, one block | 192×768×1024 | Not evaluated | 11.074 | 10.374 | Not evaluated | +6.75% |
| Specialized .cg, one block | 192×768×2048 | Not evaluated | 20.290 | 27.524 | Not evaluated | -26.28% |
| Specialized ordinary, one block | 192×768×2048 | Not evaluated | 19.270 | 19.904 | Not evaluated | -3.18% |
| Specialized .cg, one block | 192×768×3072 | Not evaluated | 29.063 | 42.530 | Not evaluated | -31.66% |
| Specialized ordinary, one block | 192×768×3072 | Not evaluated | 27.474 | 29.417 | Not evaluated | -6.60% |

The original direct kernel computes the full 144-block grid. Each specialized kernel computes only its first 32×32 output tile. Their compiled instructions differ, so their durations must not be treated as interchangeable repetitions. The `.cg` variant requests global loads that bypass L1 caching; its compiled schedule also differs from the ordinary-load variant.

The original direct-kernel prediction misses by up to 31.53%. The separate specialized `.cg` test misses by up to 31.66%. These establish a large error in the separate instruction-and-phase model. They do not establish a large error in the unchanged high-level performance model, because it has not predicted this direct path.

A new provisional high-level adaptation was evaluated separately. It estimates each 32-element reduction stage as two operand groups, each costing 352 + 29 + 64 + 8 reference cycles, plus 34 compiled control instructions charged at one cycle each: 940 cycles per stage. The four costs are a transferred global-load batch delay, operand rearrangement delay, effective matrix-result delay, and matrix issue interval. This grouping is an approximation, rather than an independently established hardware schedule.

Its prediction is the original high-level fixed cost, 3.797330 µs, plus the larger of the stage-duration estimate and an aggregate L2 service bound. The service bound is smaller in every case and does not affect the reported predictions; its transferred bandwidth prior lacks a located raw receipt. The [frozen contract](direct_highlevel/frozen_contract.json), [prediction script](direct_highlevel/predict.py), and [comparison](direct_highlevel/comparison_receipt.json) preserve the inputs and assumptions. No C++ prediction or whole-kernel GPU runtime was used as a model input. GPU results were already known when this adaptation was constructed, so this is not a blind validation.

The adapted high-level errors are −7.30%, −17.06%, and −20.74%. Both this adaptation and the separate C++ instruction model underpredict the original direct kernel, increasingly with reduction length. That establishes a remaining timing mismatch in these approximations, without proving which hardware mechanism causes it. The [direct comparison receipt](direct_applicability/direct_comparison_receipt.json) records exact sources, prediction formulas, clock conventions, and source hashes; the historical temporary C++ executable hash was not recorded.

Evidence:

- [Small GPU repeats](../step23_three_way_original_workloads_001/GPU/small_receipt.json)
- [Large GPU repeats](../step23_three_way_original_workloads_001/GPU/large_receipt.json)
- [High-level prediction replay and source hashes](../step23_highlevel_threeway_reproduction_001/HLM/prediction_replay.json)
- [Completed preserved C++ model repeats](../step22_original_validation_reproduction_001/model_large/completed_comparison.json)
- [1920×1920×1536 C++ prediction](connected_large/1920_1920_1536_result.json)
- [128×96×12288 C++ prediction](cpp_small/128_96_12288_result.json)
- [All six completed C++ predictions and receipts](cpp_all_six_completed.json)
- [Machine-readable comparison](three_way_comparison.json)

The preserved GPU executable and original host timing method were reused. Current high-level source reproduces the saved predictions exactly, but historical source hashes were not recorded; this establishes numerical prediction reproduction, not complete historical source identity.

## Focused diagnosis of the small-grid failure

For 128×96×12288, the high-level model predicts 366.713 µs and the C++ model predicts 226.873 µs, against the same 380.346 µs GPU measurement. The completed four-times-longer reduction allows their repeating cost to be separated from fixed overhead without changing either model. About 99.5% of their difference is recurring stage cost. Existing component accounting places about 97% of that recurring disagreement in the staging representation.

The [focused diagnostic report](staged_gap_diagnosis/result_report.md) gives the calculation and source comparison. The high-level model retains measured physical staging costs; the C++ model substitutes sector-return/shared-commit transitions without explicitly following the load-to-register-to-store instruction path. This identifies the model gap. It does not identify a unique physical latency or justify adding the entire observed residual as a delay.
