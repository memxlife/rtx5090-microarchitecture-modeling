# Does instruction double-counting explain the remaining error?

The largest remaining validated error is a roughly 6% overestimate for a dense matrix multiplication using 32 × 32 output tiles. Separate phase counters count 4.1% more executed warp instructions than the original program. Could correcting that count remove the timing error?

We tested the simplest hypothesis against the existing measurements: divide the composed runtime estimate by 1.040971, the independently measured instruction-count ratio. This hypothesis assumes every instruction contributes the same average cost and that overlap remains unchanged. Neither assumption is established for this GPU.

| Matrix rows × columns; reduction length | Existing error | Count-scaled error |
|---|---:|---:|
| 1920 × 1920; 1536 | 4.43% | 0.32% |
| 1920 × 1920; 4608 | 4.51% | 0.39% |
| 2048 × 2112; 1536 | 5.97% | 1.80% |
| 2048 × 2112; 4608 | 5.65% | 1.49% |
| 1920 × 1920; 16384 | 0.78% | 3.19% |

Error is the absolute prediction difference divided by measured runtime. These are retrospective comparisons using recorded tests, not new untouched validation. The ratio came from counters rather than a runtime fit, but its applicability across these workloads remains a hypothesis.

The correction improves four shorter tests but worsens the longer test and changes its overestimate into an underestimate. That does not rule out extra instructions contributing to the original error. It does show that aggregate counts alone do not justify a general correction: instructions can use different hardware, depend on previous results, and overlap differently with memory work.

We therefore did not admit this correction to the physically grounded model. The remaining task is to distinguish the cost of the extra control instructions from resource sharing and overlap, while preserving the actual memory and matrix instruction paths. The earlier constant-mode probes failed that requirement because the compiler removed shared operand loads.

The [machine-readable comparison](verification.json) preserves the predictions, measurements, and decision. The model's largest validated error remains 5.97%; its precise cause remains unresolved.


## Where the discrepancy accumulates

The two recorded reduction lengths also distinguish startup error from repeated-step error. For the 1920 × 1920 case, the prediction excess rises from 10.92 to 31.41 microseconds when the repeated steps increase from 48 to 144. A line through these two observations attributes about 98% of the longer-run gap to repeated steps. For the 2048 × 2112 case, the corresponding fraction is about 94%.

This is a description of two measured points, not a new runtime coefficient or proof that the discrepancy is linear everywhere. It contradicts a startup-only explanation. The next test should therefore preserve the repeated memory and matrix paths while changing how blocks share hardware, rather than tuning launch overhead.
