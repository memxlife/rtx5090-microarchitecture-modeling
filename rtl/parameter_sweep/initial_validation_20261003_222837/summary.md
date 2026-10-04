# Initial parameter checks and runtime validation

The research question is whether kernel optimization on a realistic RTX 5090 can be formulated as a mixed-integer program and solved efficiently. This pass supplies practical hardware-model estimates for that work. It uses one relevant source or experiment per entry when possible, rather than trying to recover every private circuit exactly.

All 118 assumption-based entries received an initial evidence check. The complete table retains the other 16 functional or timing entries and 17 recorded capacities or configuration values, for 151 entries in total. Some checks support an alternative model rule or a combined execution cost rather than the previous numerical baseline. The earlier value and checked estimate therefore remain separate.

| Strongest recorded basis for each assumption-based entry | Entries |
|---|---:|
| Fresh GPU contract or combined execution path | 20 |
| Published RTX 5090 path measurement | 1 |
| Other scoped sources or observations | 15 |
| Transferred GPU simulator prior | 80 |
| Numerical model consistency only | 2 |
| **Total** | **118** |
| **Awaiting a first check** | **0** |

The 80 transferred priors are values or rules from published models of other GPUs. They make the estimates traceable, but do not establish the corresponding RTX 5090 circuitry. For example, the examined simulator imposes no separate per-warp transaction cap; that provides an admission-policy alternative, while leaving the earlier eight-transaction hardware guess unsupported. Queue-constrained alternatives must not be presented as measurements of that guess.

The three tracks ran in parallel. The benchmark track queried the device and measured shared-memory dependencies, cache paths, barriers, stores, matrix sequences, streaming copies, and the complete GEMM. Google searches through Chrome supplied official contracts, published measurements, and simulator priors. Native-code analysis checked instruction counts, data layouts, numerical behavior, and the correspondence between the parameter table and executable components.

The fresh device query confirms 170 streaming multiprocessors, 65,536 32-bit register words per multiprocessor, 96 MiB of L2, 100 KiB of allocatable shared memory per multiprocessor, and 24 resident blocks or 48 warps per multiprocessor. A warp contains 32 threads. These are recorded configuration limits, rather than inferred hidden queue sizes.

The shared-load measurements support a complete dependency cost of 28 SM cycles, with two additional cycles for each extra distinct word that must be served by the busiest bank. A broadcast of the same word adds no extra cost in this test. Two additional address patterns predicted 28 and 30 cycles and measured exactly those values. The tested L1-dependent and L2-dependent load paths measured about 43.21 and 357.08 SM cycles. These values include the surrounding instruction path; they replace that complete path and must not be added to another decomposition of its delays.

The largest saved runtime error reproduced: the unchanged full GEMM measured 277.27 microseconds against the previous prediction of 293.38 microseconds, a 5.81% overestimate. Separate staging and computation measurements, after removing their common work once, summed to 301.84 microseconds. That is 8.86% above the complete kernel. Matching register use and residency did not remove this discrepancy. The result rejects simple addition for this compiled kernel, but does not distinguish overlap, scheduling, or differences introduced by executing the phases separately.

We added one provisional interaction coefficient to the phase model. It subtracts a calibrated fraction of the smaller net phase cost. One matched phase/full-kernel case supplied the coefficient; it is an effective approximation, not an identified physical overlap fraction. Predictions for two new reduction-length workloads were saved before their measurements and were not revised afterward.

Runtime error here is the absolute difference between predicted and measured duration, divided by measured duration, expressed as a percentage. Smaller error is better. Each measured duration is the median of nine batches, where each batch averages five CUDA event timings.

| Workload dimensions | Measured duration, microseconds | Previous prediction, microseconds | Revised prediction, microseconds | Previous error | Revised error |
|---|---:|---:|---:|---:|---:|
| 1920 × 1920 × 3072 | 472.24 | 493.00 | 450.46 | 4.40% | 4.61% |
| 2048 × 2112 × 3072 | 532.47 | 561.04 | 512.67 | 5.37% | 3.72% |

Both revised predictions meet the provisional 5% target, and all 90 numerical correctness checks passed. The first prediction worsened slightly, while the second improved. This is a useful initial confirmation for the 32 × 32 tile and compiled kernel family. It does not establish accuracy for other tiles or all operating conditions.

The integrated Verilog timing model remains uncalibrated. In particular, a modeled backing-memory interface can admit only one sector every two SM edges, which is too restrictive to represent full-chip memory bandwidth at that clock scale. The confirmed runtime results belong to the revised phase performance model. The MIP solver and its scaling have not been retested in this parameter-check pass.

Two existing profile-to-code mismatches also have explicit corrections: the exercised warp selector uses round-robin selection rather than oldest-ready selection, and the cache uses an advancing victim pointer rather than the stated pseudo-LRU policy. These are corrections to the reconstruction's specification, not discoveries of NVIDIA's private policies.

The next optimization formulation can use the measured effective paths, source-backed constraints, and labeled provisional alternatives. Detailed investigation is warranted when a mismatch changes a candidate's predicted runtime or the solver's choice. The immediate evidence supports that practical handoff; it does not require every transferred prior to become a measured hardware constant first.

- [All 151 parameter entries and checks](consolidated_checks.md)
- [Machine-readable parameter checks](consolidated_checks.json)
- [Effective model costs](../../initial_validation_effective_profile.json)
- [Executable cost functions](../../effective_path_model.py)
- [Unchanged-kernel and phase comparison](phase_composition_evidence.json)
- [Frozen new-workload predictions](interaction_candidate_frozen.json)
- [New-workload confirmation measurements](interaction_confirmation_evidence.json)
- [Native-code review](../../discovery_rounds/initial_validation_native_001/round_002_003_native_review.json)
