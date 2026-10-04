# Where does the original staged-workload discrepancy occur?

For the original 128×96×12288 staged matrix multiplication, the high-level model predicts 366.713 microseconds, the handwritten full-chip C++ simulator predicts 226.873 microseconds, and the GPU takes 380.346 microseconds. Almost all the difference between the two models is a repeating reduction-stage cost, rather than a fixed startup cost.

The output has 128 rows and 96 columns. Each output sums 12,288 products; each reduction stage processes 32 products. The workload therefore has 384 stages and twelve 32×32 output blocks. A second completed simulation uses the same output shape and 49,152 reduction elements, or 1,536 stages. Neither model’s timing parameters were changed.

The high-level model combines independently measured staging, operand-compute, and common-control phases. Its stage cost is 0.780274993 + 0.202141667 − 0.037324998 = 0.945091662 microseconds. Subtracting the common phase avoids counting it twice. Its fixed contribution is 3.797330267 microseconds.

The C++ executions take 667,007 and 2,640,989 cycles. Their difference, divided by the 1,152 extra stages, is 1,713.526042 cycles per stage. At the comparison’s 2,940 reference cycles per microsecond, this is 0.582831987 microseconds per stage. Subtracting 384 such stages from the shorter execution leaves 9,013 cycles, or 3.065646259 microseconds.

These two-point C++ quantities describe the completed results. They are not new simulator coefficients or identified hardware delays.

| Contribution at 384 stages | High-level model minus C++ model |
|---|---:|
| Repeating stage cost | 139.107715 µs |
| Fixed contribution | 0.731684 µs |
| Total | 139.839399 µs |

The repeating term accounts for 99.48% of the model-to-model difference. The C++ model is 153.472478 microseconds below the GPU measurement, while the high-level model is 13.633079 microseconds below it. The largest discrepancy therefore requires explaining the repeated execution path; adjusting only startup cannot close it.

Both C++ runs report twelve simultaneously resident blocks. Their requested sectors and native instruction counts grow exactly fourfold with reduction length. All modeled requests hit the initialized global cache: there are no modeled misses or fills. Additional waves of blocks or simulated DRAM misses therefore do not explain these completed runs. This does not establish the GPU’s cache state or eliminate hardware request-service and register-readiness delays.

The high-level model’s staging phase alone costs 0.780275 microseconds per stage, more than the C++ model’s entire effective stage cost of 0.582832 microseconds. This is a useful warning that phase meanings differ across the implementations, not a proof that exactly 0.197443 microseconds of physical load latency is missing. The C++ simulator couples staging, arithmetic, queues, and shared resource service, whereas the high-level model composes isolated phase measurements. The present counters do not separately time those C++ phases.

The supported conclusion is quantitative but effective: the implementations disagree mainly on recurring work. The following source comparison narrows that difference to the staging representation. No new delay, residual correction, or cache parameter is fitted here. [The calculation receipt](effective_cost_breakdown.json) preserves the original source hashes, counters, and arithmetic.

## Which modeled component differs most?

Existing source-based phase accounting assigns the C++ model 1,155 cycles to staging, 555 cycles to operand computation, and four cycles to registered boundaries. Their sum, 1,714 cycles, is close to the 1,713.526-cycle average derived from the completed full runs. This is component accounting, rather than a newly measured breakdown of every full-run cycle.

For comparison, removing the high-level model's measured common work from its staging phase leaves 0.780275 − 0.037325 = 0.742950 microseconds. Its operand-compute phase remains 0.202142 microseconds, so common work is counted once.

| Repeating contribution | High-level phase composition | C++ source accounting | Difference |
|---|---:|---:|---:|
| Staging, with common work subtracted from the high-level staging phase | 0.742950 µs | 0.392857 µs | 0.350093 µs |
| Operand computation, including the high-level common work | 0.202142 µs | 0.188776 µs | 0.013366 µs |

The staging difference is about 97% of the full model-to-model stage-cost difference. Phase boundaries and control protocols differ, so this is an attribution to the modeled path, rather than proof of an isolated hardware latency.

The C++ staging implementation forms 64 groups per stage, each requesting two 32-byte sectors. Once they return, its registered response owner commits the group directly to shared memory. The modeled cache hit becomes eligible after four cycles; that is a cache-state transition rule, not a measured end-to-end global-load delay. The code does not explicitly track each physical global-load instruction's destination register becoming ready before its dependent shared-store instruction can issue.

The high-level staging cost came from the physical compiled global-to-shared path. It consequently includes effective instruction, request-service, register-dependency, shared-store, and synchronization costs that the C++ sector-to-commit abstraction may omit or represent differently. That is the concrete reason the two formulations can disagree despite matching requested traffic. It does not tell us which of those physical costs supplies the missing time.

The C++ controller also waits for staging before starting computation, and for computation before starting the same block's next stage. Perfect staging/computation overlap within one block is therefore not the rule producing this C++ prediction. Inter-block scheduling remains modeled separately.

[The source comparison receipt](../small_staging_mechanism_comparison.json) records the relevant implementation files and phase-accounting limits. Historical [phase accounting](../../step2_layout_gpu_001/mip_verification.json) and the [staging dependency contract](../../step4_staging_dependency_001/mechanism_predictions.json) preserve the 1,155/555-cycle accounting and the load-register-store capability gap. No timing parameter was changed during this diagnosis.
