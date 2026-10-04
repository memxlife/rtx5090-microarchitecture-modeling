# Hardware sweep 1: shared-memory dependencies and service work

This approved sweep ran on idle GPU 7. It tested a dependent shared-memory load chain and independent shared reads under three bank patterns and three warp counts. All 189 measured, unprofiled launches passed numerical checks and reported zero local-memory allocation. Three additional profiler launches completed successfully. These results characterize the tested paths; they do not validate a full GPU simulator.

## Dependent reads

The chain used 256, 1,024 and 4,096 iterations. Taking the difference in median elapsed cycles and dividing by the added iterations gives **34 SM cycles per iteration** for both length intervals. Each iteration waits for the previous loaded value before constructing the next address.

The binary contains an `LDS` instruction and dependent address arithmetic (`LEA`), plus loop control and compiler scheduling. Therefore 34 cycles is the repeated dependency-path cost, not intrinsic shared-memory latency. The compiler removed the source's final shared store and warp synchronization. A constant final-return boundary may affect the intercept; it does not justify claiming that the bracket measures standalone load completion. Clock readings changed from an idle 22 MHz to an after-sweep 2,430 MHz, and only before/after telemetry was collected. The measured cycle slopes must not be presented as a controlled-frequency wall-time calibration.

## Independent reads and bank work

Each iteration performs four scalar reads. Addresses were grouped into rows separated by 16, 24 or 32 words. For each read, counting the largest number of distinct words requested from any one of the 32 banks predicts the number of service packages. A profiler wavefront is the corresponding reported unit of shared-memory service work.

| Row spacing, words | Predicted packages per read | Predicted total wavefronts | Measured total wavefronts |
|---|---:|---:|---:|
| 16 | 4 | 32,768 | 32,768 |
| 24 | 2 | 16,384 | 16,384 |
| 32 | 8 | 65,536 | 65,536 |

Each profiled case had one warp and 2,048 iterations. The predicted total is packages per read × four reads × 2,048 iterations. All three predictions matched exactly. The requested shared-request counter was absent from the returned report; the comparison uses wavefront counts, not a measured request ratio.

| Row spacing, words | One warp: cycles/iteration | Four warps | Eight warps |
|---|---:|---:|---:|
| 16 | 77 | 77 | 128 |
| 24 | 60 | 65.012 | 64 |
| 32 | 108 | 128 | 256 |

These are differences between the median cycle measurements at 2,048 and 8,192 iterations, divided by the added iterations. They include address arithmetic, accumulation and loop control. The different scaling shows why a single fixed read cost cannot represent all tested bank patterns and warp counts. It does not uniquely identify bank ports, request queues or arbitration.

## Model update and counts

The executable [shared_work.py](../parameter_sweep/shared_work.py) now computes scalar warp-read packages. Its three hardware comparisons are recorded in [shared_work_verification.json](../parameter_sweep/shared_work_verification.json). This adds a verified work rule for later integration; it does not change the current Verilog bank timing or GEMM coefficients.

F052, shared transaction splitting, gained partial evidence for the tested scalar patterns. T027, shared response latency, gained a measured dependency-path constraint, but remains partial because address and scheduling costs are not separated.

- Newly fully identified: **0 functional, 0 timing**.
- Newly partially identified: **1 functional, 1 timing**.
- Cumulative fully identified: **5 functional, 0 timing**.
- Remaining: **82 functional and 47 timing**, or **129 total**.
- Partial fields included in those remaining totals: **9 functional and 1 timing**.

The next discriminating control should reduce or independently measure address and loop costs in the dependent path, while keeping the actual load instruction unchanged. It should also test the package rule on additional scalar patterns before extending it to wider reads or stores. Independent experiments may use separate available GPUs; calibration records must preserve device identity and avoid assuming all boards have identical timing.

Raw measurements, compiled instructions, tool versions and telemetry are in [hardware_receipt.json](../parameter_sweep/hardware_receipt.json); profiles are in [profiles.json](../parameter_sweep/profiles.json). Run `python studies/rtx5090_gemm_milp/rtl/parameter_sweep/analyze.py` to reproduce the cycle summaries.
