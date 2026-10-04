# What changes when blocks share an SM?

We tested whether the model predicts how the same matrix multiplication behaves when an SM—a GPU processing unit—can hold one, four, or eleven blocks. The native GPU instructions remained identical. All 270 numerical checks succeeded, with the original register usage and no local memory.

For the longer reduction length, the saved predictions and measured runtimes were:

| Allowed blocks per SM | Predicted runtime | Measured runtime | Absolute relative error |
|---|---:|---:|---:|
| 1 | 3.002 ms | 2.981 ms | 0.71% |
| 4 | 0.998 ms | 0.965 ms | 3.40% |
| 11 | 0.729 ms | 0.693 ms | 5.06% |

Error is the absolute prediction difference divided by measured runtime. Each measurement is the median of nine samples, each averaging five launches. Predictions used earlier isolated-path measurements, not these full-kernel runtimes.

The intermediate four-block case was not calibrated. Its prediction agrees within 4.54% across both tested reduction lengths. This supports the model's distinction between waiting and finite shared service, and extends the supported resident-capacity settings without fitting new coefficients. Increasing capacity from one to eleven blocks gives about 4.3 times the throughput in this test, rather than eleven times.

Profiles measured identical dynamic instruction counts and 100% L2 hits at all three settings. Overall instruction issuing remained below its nominal maximum. These facts do not identify the exact busy pipeline: different instruction classes, dependencies, and memory processing can still limit performance.

Profile clock rates also differed between settings. Unused shared reservation and a common requested partition constrain the experiment, but the partition request is a driver hint. We retain clock and cache-partition uncertainty. The resident limit is a capacity, not a direct measurement of the number of active blocks throughout execution.

The executable model now supports these bounded capacity settings. Its largest error across the broader existing validation remains 5.97%. The remaining discrepancy increasingly appears when blocks share hardware; the precise cause is still unresolved. [Raw verification](verification.json) and [profile evidence](profile_analysis.json) preserve the comparison.
