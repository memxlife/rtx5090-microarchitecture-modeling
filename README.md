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

## Recorded results and limits

For an output matrix of 2048 by 2112, the completed timing model overestimates saved GPU measurements by **2.662%** at reduction length 1536 and **4.515%** at reduction length 3072. Both retire 4,224 blocks and cover 4,325,376 output addresses. The [combined receipt](rtl/calibration_large_001/event_cpp/full_completed_comparison.json) preserves the results.

Those percentages convert model cycles at a 2.94 GHz reference; the GPU measurements do not have matched active-clock records. Both tests begin with inputs resident in the modeled cache, and all reads hit. The 48-slice organization, XOR address routing, and 32 shared-read slots are provisional choices. These results do not identify NVIDIA's private RTL, validate cold-cache or DRAM timing, or establish full-chip large-workload equivalence with Verilog. Component and small-grid timing comparisons are narrower implementation checks.

The [master parameter table](rtl/parameter_master_table.md) distinguishes documented, measured, transferred, and provisional values. The research purpose is to expose consequential model errors and derive optimization constraints, rather than claim a complete reconstruction of every GPU unit.

Historical receipts preserve the evidence from the original research workspace. Portability edits relocate paths and test-tool discovery; old source hashes refer to the original files, not necessarily their relocated public copies. The current checkout can be checked with `python3 tools/check_package.py`, followed by the smoke tests above.
