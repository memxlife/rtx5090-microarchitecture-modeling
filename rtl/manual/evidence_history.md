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

The original component adapters are Verilator-generated C++ and share their source behavior. The later connected timing executor is handwritten C++; its implementation checks and physical comparisons are recorded separately below.

## Original validation lineage and the staging repair

The October 3 high-level model composed costs measured from isolated staging, operand-compute, and common-control paths. Its small-grid domain was 128×96 with long reductions; its dense-grid domain included 1920×1920 and 2048×2112. The later connected numerical RTL calibration used different 64×96 workloads. These are distinct models and validation pairs. [The preserved chronology](../../step22_original_validation_reproduction_001/highlevel_oct3_chronology.json) records the distinction.

The exact original high-level-model GPU binary was reproduced without recompilation. Its kernel has 376 printed instructions, including scalar global loads, shared stores, operand rearrangements and BF16 matrix instructions. Warm conditioning does not mean the GEMM explicitly bypasses L1: `.cg` was used by the preheating helper, while the GEMM producer uses ordinary `LDG.E.U16`. The [small](../../step23_three_way_original_workloads_001/GPU/small_receipt.json) and [dense](../../step23_three_way_original_workloads_001/GPU/large_receipt.json) receipts preserve nine timing samples, each averaging five launches. After every launch, all output elements are compared with the reference. The reported `output_checks=45` counts complete matrix comparisons; an earlier interpretation as forty-five sampled values was incorrect and is preserved in the [correction record](../../step22_original_validation_reproduction_001/numeric_scope_correction.json).

The new [C++ staging repair](../../step23_hlm_connected_gpu_reproduction_001/staging_cpp_repair/focused_result.json) extracts the compiled producer prefix from program address `0x220` to the first barrier at `0x1010`. It keeps loaded-register readiness, source ownership, dependency tags and outstanding shared commits. On the focused 128×96×12,288 comparison, prediction changes from 226.873 to 338.302 microseconds against the 380.346-microsecond GPU result. The remaining −11.054% error exceeds the target. The change is a candidate mechanism correction, not a promoted accurate model or a fitted correction to the complete kernel runtime.

The [integration chapter](integration_and_verification.md#compiled-staging-repair-candidate) records unit checks, the pending Verilog counterpart, and the boundary between component correctness and whole-workload regressions. Pending differential tests and running regressions must not be described as completed evidence. The frozen baseline and its earlier bounded successes remain preserved.

The dense regression reverses the focused improvement: 1920×1920×1536 has +31.5735% candidate error versus +0.2739% for the frozen baseline. [This completed regression](../../step23_hlm_connected_gpu_reproduction_001/regression_suite/candidate_dense.json) prevents treating the staging repair as validated across concurrency. The separate [Verilog component](../../step23_hlm_connected_gpu_reproduction_001/staging_rtl_repair/repaired_staging.sv) now materializes the same producer contract; component parity and full-chip accuracy remain different questions.

[The staging RTL parity receipt](../../step23_hlm_connected_gpu_reproduction_001/staging_rtl_repair/parity_receipt.json) now records 921,445 protocol/address/counter comparisons and 36,864 BF16 payload checks over 18 frames. This is component equivalence with host-side product checking, not Verilog GEMM or full-chip timing validation. Mid-flight reset and RTL negative-response rejection remain untested.
