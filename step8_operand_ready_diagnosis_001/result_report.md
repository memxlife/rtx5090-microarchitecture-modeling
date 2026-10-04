# Do separate A and B readiness measurements explain the remaining error?

The separate operand-readiness hypothesis does not explain the missing runtime. Independent A and B probes produce smaller readiness estimates than the old uniform prior, so the candidate model predicts an even shorter runtime. This is useful negative evidence: the remaining positive delay cannot be repaired by those operand measurements alone. Fresh physical confirmation shows 38.99% underprediction on the full workload, worse than the preceding 31.53%. The candidate priors are therefore not promoted to the default model.

## Question and baseline

Tests run on an RTX 5090 with 170 active streaming multiprocessors, the GPU's processing units. The direct matrix kernel multiplies a 192×3,072 matrix A by a 3,072×768 matrix B, using BF16 16-bit inputs and FP32 32-bit accumulation/output. Its 144 blocks each contain four warps of 32 threads. Matrix operands are loaded directly from global memory into registers instead of first copying a shared tile. The cache-corrected model predicts 29.797 microseconds against 43.519 measured, 31.53% too little time. This round asks whether A and B need distinct loaded-value readiness delays.

A readiness delay is the interval before an instruction can use a returned register value. It is not necessarily intrinsic cache latency: instruction issue, dependency tags, and probe control also affect a measured interval. The investigation retains the original workload, kernel choice, and useful matrix products.

## Source repair before asymmetric timing

Independent inspection finds an operand-label error in the earlier address-order mapping. The first four active matrix loads derive from the second kernel pointer and B's 768-element pitch, not A; the next four derive from the first pointer and A's 3,072-element pitch. Explicit pointer ancestry repairs the mapping before applying separate priors.

Regenerating the complete cache-address sequence with corrected labels preserves the aggregate request counts for both tested reduction lengths. That numerical coincidence does not validate the old address mapping. The new classification uses actual instruction program counters and pointer ancestry, while old receipts remain unchanged.

## Independent probes and rejected controls

Mapped raw-word probes read one 32-bit operand word and wait on a predicate requiring its value. The A probe reports 421 cycles versus 129 for a control whose predicate uses an already-ready lane/index value instead of the loaded value: a 292-cycle difference. B reports 391 versus an analogous 86-cycle control: 305 cycles. Their endpoints precede matrix register rearrangement. All 1,179,648 checked final mapped values pass. [The paired primitive receipt](../step8_direct_timing_diagnosis_001/paired_primitives_receipt.json) records the measurements and compiled-path checks.

These probes differ from the previous four-load-batch measurement of 352 cycles. They use mapped loads and shared-memory retention rather than the complete matrix-instruction sequence, so their surrounding resource use also differs. Applying each raw-word estimate to every corresponding compiled load is an explicit transfer hypothesis, not a recovered universal latency. The model retains finite issue capacity, register ownership, and request constraints rather than adding the two measured differences to whole-kernel time.

Additional probes target constant loads and special-register reads that the model currently treats as one-cycle arithmetic. Initial attempts are rejected because the compiler moves the target read before the starting clock. A bounded address-dependency repair preserves the intended compiled interval but fails its output correctness check. It supplies no admissible timing prior. No guessed cycle value replaces the unresolved constant/special-register delays, and encoded issue-control annotation names are not assumed to equal cycles.

## Frozen candidate and formulation

The [frozen operand prediction](frozen_operand_prediction.json) uses A=292 and B=305 cycles before new complete-kernel measurements. For reduction length 3,072 it predicts 26.548 microseconds, below the cache-corrected 29.797 baseline. This moves away from the earlier 43.519-microsecond observation rather than explaining its positive gap.

The four-path formulation still allows staged strides 32, 48, and 64 and direct loading. It selects direct under the new source rules. All 357,040 source-executor issue checks match the reconstructed graph. Two initial HiGHS solver-error attempts are preserved; source-derived critical-path lower-bound cuts resolve the formulation with zero gap in 5.732 seconds. These cuts strengthen mathematical constraints, not physical timings. [The resolved MIP](resolved_four_path_mip.json) records the finite-domain result. Exact internal replay remains distinct from accurate GPU prediction.

## Fresh physical confirmation and decision

[The final confirmation receipt](../step8_direct_timing_diagnosis_001/final_confirmation_summary.json) reports timing with 200 independent matrix multiplications per CUDA graph, five warm graph launches, and eleven timed samples. All complete output checks pass. Reduction length means the shared inner dimension of the two input matrices; one loop stage accumulates 32 positions of that dimension. The length 2,048 is a new intermediate validation workload; lengths 1,024 and 3,072 repeat earlier cases.

| Reduction length | Frozen predicted microseconds | Measured direct-kernel microseconds | Signed error |
|---:|---:|---:|---:|
| 1,024 | 10.697 | 15.133 | −29.31% |
| 2,048 | 18.627 | 29.251 | −36.32% |
| 3,072 | 26.548 | 43.515 | −38.99% |

Signed error is predicted minus measured time, divided by measured time. Cycle conversion retains the 2.94 GHz reference. The direct path remains the measured winner among the four admitted full-workload candidates: direct 43.515, staged stride 48 at 94.491, stride 32 at 96.001, and stride 64 at 100.097 microseconds. Correct ranking therefore survives while absolute timing worsens.

At reduction length 3,072, the cache-corrected baseline predicts 29.797 microseconds. The new candidate lowers it by about 3.248 microseconds, increasing the missing-time gap by approximately 23.7% relative to that baseline gap. It explains no positive fraction of the missing delay; this is arithmetic prediction deterioration, not a physical contribution estimate. The raw-word A/B transfer hypothesis is rejected as a route to closing the error, and its priors are retained for diagnosis rather than installed as the default.

From reduction length 1,024 to 3,072, physical time grows by about 0.443 microseconds per added 32-position stage, while this candidate grows by about 0.248. The roughly 0.195-microsecond difference is a diagnostic of repeated missing cost, not a coefficient to install in the model.

The implemented operand-specific model and corrected address classification remain useful capabilities, but the remaining root cause is unproved. Constant/special-register readiness, warp-local synchronization, and actual compiled issue controls still have simplified timing. Profiler waiting percentages do not apportion their costs, and rejected probes supply no replacement parameters. Further work should target those fixed compiled-path mechanisms, preserving numerical and instruction-order controls. No latency is fitted to the residual and no full Verilog timing-equivalence claim is made. All GPU jobs in this bounded round have finished.
