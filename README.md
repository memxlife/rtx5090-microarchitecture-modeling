# RTX 5090 Microarchitecture Modeling

Can a model of GPU resources, dependencies, queues, and memory traffic predict GEMM runtime closely enough to support mixed-integer optimization? This repository contains a behavioral reconstruction of the matrix-computation path studied on an RTX 5090, its hardware development manual, and executable Verilog and C++ models.

Start with the [whole-GPU overview](rtl/manual/00_gpu_overview.md), then the [system specification and fourteen component chapters](rtl/rtl_microarchitecture_spec.md). Each component chapter links its behavior, interfaces, parameters, source files, and evidence. The [integration chapter](rtl/manual/integration_and_verification.md) separates numerical tests, implementation consistency checks, and hardware timing comparisons.

## Build and run the independent C++ executor

A C++20 compiler and POSIX threads are required. The portable simulator package provides these targets:

```sh
make -C simulator smoke
make -C simulator full
```

The first runs a small check; the second runs the recorded large configurations and may take tens of minutes, depending on the host CPU. No NVIDIA GPU is required for either simulator test. For direct compilation from the chapter-linked sources, from this repository's root:

```sh
c++ -O3 -std=c++20 -pthread rtl/calibration_large_001/event_cpp/full_gpu_parallel.cpp -o /tmp/rtx5090-sim
/tmp/rtx5090-sim 64 96 64 1 2 2 2 1000000 0 4 2 2 32
```

Arguments select matrix dimensions, provisional hashed cache routing, SM count, cache slices, resident contexts, cycle limit, initial cache warmth, sets per slice, launch count, host worker threads, and shared-read queue slots. The small configuration checks execution and output-address coverage without requiring GPU access. It is intentionally smaller than the hardware configuration.

For the recorded full-chip configuration, run:

```sh
/tmp/rtx5090-sim 2048 2112 1536 1 170 48 11 20000000 1 1024 1 4 32
```

The C++ executor tracks timing and addresses without storing matrix values. Its output-address checks do not establish numerical matrix correctness. Separate numerical Verilog tests check matrix values. A quick component check can be run with `python3 rtl/cpp/build_and_verify.py` after installing Verilator. Verilator, a C++ compiler, and Python 3 are needed for those tests; the [integration chapter](rtl/manual/integration_and_verification.md) links their source recipes. Historical adapters in `rtl/cpp` drive Verilator-generated models; the independent executor is in `rtl/calibration_large_001/event_cpp`.

## Focused scheduling diagnosis and exploratory MIP

The [four-partition diagnosis](step24_staging_interaction_001/result_report.md) identifies a modeled instruction-issue bottleneck. Correcting it lowers dense-case error from +31.57% to +10.41%, while the small case remains −27.54%. The [matching Verilog component](step24_staging_interaction_001/partition_rtl/README.md) passes 943,985 protocol/address/counter comparisons and 49,152 operand-value checks. Hardware accuracy still exceeds the 5% target; neither experimental candidate is promoted.

A separate [exploratory MIP](cublas_mip_001/result_report.md) expresses tile dimensions, split-K, shared buffering, resource limits and reduction workspace through component-demand constraints. It solves a 100-configuration domain to zero gap in about 0.04 seconds; enumeration independently matches. The proxy chooses 64×64×32 tiles and split-K 4, with buffer counts 2/3/4/6 tied, predicting 13.566 microseconds. This is neither a compiled CUDA candidate nor a hardware-optimal result. The captured library uses split-K 8; its measured runtime was not a solver input.

## Recorded results and limits

The latest [staging experiment](step23_hlm_connected_gpu_reproduction_001/staging_cpp_repair/result_report.md) adds the compiled global-load → register → shared-store dependency path. Its separate C++ and Verilog components agree in the tested traffic scenarios, but the candidate is **not promoted**: improving the small workload comes with a large timing regression on the dense workload.

| Matrix dimensions M × N × K | Baseline C++ error | Candidate C++ error |
|---|---:|---:|
| 128 × 96 × 12,288 | −40.35% | −11.05% |
| 128 × 96 × 49,152 | −40.87% | −11.42% |
| 1,920 × 1,920 × 1,536 | +0.27% | +31.57% |

Error is `100 × (prediction / GPU measurement − 1)`; negative values mean the model predicts a shorter runtime. [The regression summary](step23_hlm_connected_gpu_reproduction_001/regression_suite/candidate_summary.json) records all three completed executions. The preserved baseline remains unchanged.

[Verilog component checks](step23_hlm_connected_gpu_reproduction_001/staging_rtl_repair/README.md) pass 921,445 protocol/address/counter comparisons and 36,864 operand-value checks. Matrix multiplication of the returned operands runs on the host; this is not full Verilog GEMM validation or a 5% hardware timing result. Both implementations and their test commands are linked from the revised development manual.

The percentages below are earlier comparisons against saved GPU measurements, with a different measurement lineage from the latest repeats.


For an output matrix of 2048 by 2112, the completed timing model overestimates saved GPU measurements by **2.662%** at reduction length 1536 and **4.515%** at reduction length 3072. Both retire 4,224 blocks and cover 4,325,376 output addresses. The [combined receipt](rtl/calibration_large_001/event_cpp/full_completed_comparison.json) preserves the results.

Those percentages convert model cycles at a 2.94 GHz reference; the GPU measurements do not have matched active-clock records. Both tests begin with inputs resident in the modeled cache, and all reads hit. The 48-slice organization, XOR address routing, and 32 shared-read slots are provisional choices. These results do not identify NVIDIA's private RTL, validate cold-cache or DRAM timing, or establish full-chip large-workload equivalence with Verilog. Component and small-grid timing comparisons are narrower implementation checks.

The [master parameter table](rtl/parameter_master_table.md) distinguishes documented, measured, transferred, and provisional values. The research purpose is to expose consequential model errors and derive optimization constraints, rather than claim a complete reconstruction of every GPU unit.

Historical receipts preserve the evidence from the original research workspace. Portability edits relocate paths and test-tool discovery; old source hashes refer to the original files, not necessarily their relocated public copies. The current checkout can be checked with `python3 tools/check_package.py`, followed by the smoke tests above.
