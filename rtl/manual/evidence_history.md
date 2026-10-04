# Evidence history and interpretation

[System specification](../rtl_microarchitecture_spec.md)

The experimental objective is to determine whether realistic kernel optimization can be formulated and solved as a MIP. Hardware reconstruction supplies resource and timing structure; it is useful when it predicts performance and guides choices on the GPU.

The first model counted arithmetic and requested bytes with fixed rates. Large mismatches motivated residency, stage cost, dependencies, shared-memory service and cache-path tests. The latest initial-check pass supports using scoped estimates, while preserving their provenance.

[Initial-check results and quantitative error comparison](../parameter_sweep/initial_validation_20261003_222837/summary.md)

[Per-entry evidence and alternatives](../parameter_sweep/initial_validation_20261003_222837/consolidated_checks.md)

## Library evidence contract

A disassembled forward-compatible cuBLASLt kernel contains LDSM, but its presence in the shipped library does not establish that a particular workload selects it. The later `discovery_rounds/executed_library_006` experiment records an actually executed cuBLASLt kernel and numerical output. Its LDS128 sites belong to the output epilogue. Its input path uses scalar `LD.E` descriptors whose detailed interpretation is still being investigated. Consequently neither those LDS128 sites nor the unselected forward-compatible LDSM path may be used to explain current GEMM input timing without further evidence.

## Claims that remain bounded

All 118 assumption-based entries have a recorded initial check or provisional alternative. Eighty use transferred priors; two have numerical consistency only. This does not establish 118 physical RTX 5090 facts. The phase estimator met 5% on two new workloads, but the connected Verilog timing remains uncalibrated.

The current component adapters are Verilator-generated C++ and therefore share their source behavior. No independent fast event simulator or measured speedup is claimed.
