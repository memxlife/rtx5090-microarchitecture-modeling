# Large-grid connected-model validation

Can the connected microarchitecture timing model predict a large GEMM on the RTX 5090 within about 5%? This experiment uses the saved 2048-by-2112 output grids with reduction lengths 1536 and 3072. The GPU measured 277.274 and 532.448 microseconds, respectively. These are CUDA-event measurements; their saved clock snapshots are not the active clock during each kernel. An exact cycle comparison therefore remains unavailable for those measurements.

## Hardware configuration and execution

The [connected top](large_connected_top.sv) contains 170 SM instances, each with 11 resident-block slots for the studied kernel. Its 48 provisional [cache slices](large_slice_l2.sv) contain 1024 sets, 16 ways, and 128 bytes per line: 96 MiB in total. The physical slice count and address mapping are assumptions. They are not identified NVIDIA properties.

The [C++ driver](host.cpp) executes the Verilator-generated model, supplies tagged memory responses, and checks that every output address is written exactly once. The large run carries no numerical memory payload and performs no matrix arithmetic; it follows instruction readiness, queue occupancy, arbitration, cache metadata, and completion. Numerical correctness is checked separately by the earlier small-workload tests. It records simulated cycles, cache counters, resident blocks, host execution time, and simulated cycles per host second. This driver and Verilog share the same implementation. The subsequent [independent C++ executor](event_cpp/full_gpu_parallel.cpp) translates component behavior into C++ and uses integer-cycle event times to skip inactive work. Its small-workload comparisons check that this separate implementation preserves the Verilog model’s timing and behavior.

Requests contend within each slice. Response arbitration selects one returning packet per SM and holds that selection during backpressure, so a stalled response cannot change its data or identity. Global read, write, and mixed-traffic credits impose measured aggregate service limits. A separate credit pool limits backing-memory reads. These credits describe effective throughput, not a physical number of ports.

## Quick hardware service check

The [CUDA benchmark](service_probe.cu) uses 256 threads per block and visits every word four times. It compares 1, 32, 170, and 680 blocks for read-only, write-only, and equal read/write traffic. Reads use the cache-global instruction qualifier; stores use the write-back qualifier. Numerical checks confirm total read coverage and every written value. Each reported time is the median of three CUDA-event measurements after a warm-up.

The 16 MiB operand footprint fits within nominal L2 capacity, including the output buffer. The 256 MiB operand footprint exceeds L2 capacity. Requested bytes divided by elapsed time give the following maximum observed rates:

| Operand footprint | Read only | Write only | Equal read/write, counting both directions |
|---|---:|---:|---:|
| 16 MiB | 3.444 TB/s | 2.853 TB/s | 4.510 TB/s |
| 256 MiB | 1.568 TB/s | 1.668 TB/s | 1.364 TB/s |

For 16 MiB reads, increasing concurrency from 170 to 680 blocks raised throughput from 1.111 to 3.444 TB/s. Thus one block per SM did not saturate this path. The different read, write, and mixed rates also show why a single service limit cannot describe every traffic mixture. These measurements include instruction issue and concurrency effects. Without hardware traffic counters, they do not prove cache-hit fractions, intrinsic memory latency, or port counts.

The [raw observations](hardware_service.json) and [effective service parameters](service_parameters.json) preserve those limits and their scope. The model converts them to sectors per cycle using a 2.94 GHz reference. This conversion is provisional because the sweep did not measure active SM cycles. Its backing-response latency remains an assumption; throughput measurements do not identify that latency.

## Cache policy used by this workload

The source for the unchanged GEMM contains cache-global loads and no calls that configure a persisting-cache set-aside or stream access-policy window. The model therefore uses ordinary replacement. [CUDA L2 Cache Control](https://docs.nvidia.com/cuda/cuda-programming-guide/04-special-topics/l2-cache-control.html) describes persisting access as retention priority and streaming access as eviction priority. Neither guarantees residency. Its `hitRatio` selects an approximate fraction of accesses for a policy; it is not the resulting cache-hit rate.

[NVIDIA lists RTX 5090 as compute capability 12.0](https://developer.nvidia.com/cuda/gpus), within the documented support range for L2 persistence controls. Numerical window and set-aside maxima remain device-specific and were not queried in this run. The model assigns no persisting reservation to the unchanged workload. B200 cache configuration is not transferred to this GPU.

## Verification and large-workload comparison

The earlier sliced-cache timing smoke test checked all 6144 output addresses in each of two launches, with two SMs and a deliberately small cache. It verifies routing and completion, not arithmetic or full-chip timing. Its two launches take 34,493 and 28,251 model cycles. The [receipt](smoke_receipt.json) and output log (not distributed) record that test. The full-chip configuration is specified separately in the [experiment contract](contract.json).

The independent C++ executor now matches the RTL on complete single-SM workloads with both two and eleven resident contexts. It also matches both complete small-grid launches with the provisional address hash and 32 shared-read slots: 29,592 cycles from an initially empty cache and 25,031 cycles with the previous launch’s cache contents retained. Cache requests, hits, misses, merged requests, fills, and output-address coverage match exactly. The [SM comparison](event_cpp/sm_event_receipt.json) and [hashed-cache comparison](event_cpp/hashed_queue32_equivalence.json) record the evidence. These comparisons establish consistency between implementations, rather than identifying the GPU’s private hardware parameters.

Both full-chip C++ workloads have completed. Each uses M=2048 and N=2112, retires all 4,224 thread blocks, and covers all 4,325,376 output addresses. The comparison below converts model cycles at the 2.94 GHz reference. Relative error means (predicted time − measured time) / measured time.

| Reduction length K | Model cycles | Predicted time (µs) | Saved GPU time (µs) | Relative error |
| --- | ---: | ---: | ---: | ---: |
| [1536](event_cpp/full_1536_result.json) | 836,886 | 284.655 | 277.274 | +2.662% |
| [3072](event_cpp/full_3072_result.json) | 1,636,081 | 556.490 | 532.448 | +4.515% |

Both are within the approximate 5% target under this reference-clock conversion. The [combined receipt](event_cpp/full_completed_comparison.json) records both results. The saved GPU measurements do not include matched active-clock records, so these are not comparisons at a measured common clock.

The model uses 170 SMs and 96 MiB L2, with inputs initially resident in cache. All read requests hit the modeled cache in both cases. Its 48-slice organization, XOR-based address routing, and 32 shared-read slots are provisional choices. These results test execution with warm inputs; they do not validate cold-cache behavior or DRAM delays. The large simulation carries no matrix values and checks output-address coverage rather than numerical matrix results. Numerical correctness remains covered separately by the earlier small-workload tests. Full-chip large-workload equivalence with RTL has not been tested.

The original single-gateway small-case results remain unchanged; all four of their C++ execution checks reproduce the Verilog harness exactly.

The [linked build driver](link_compiled.py) reuses the compiled Verilog component libraries and builds a thin top-level model; this avoids repeating full-chip compilation. [run.py](run.py) supplies the original component-build path. The initial generator is preserved as historical construction code; it predates the measured service limits and must not overwrite the current sources. No large-case runtime is used to fit the new service limits.

## Timing-path corrections and execution speed

Cache-global (`.cg`) loads bypass L1 under the [PTX cache-operator specification](https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#cache-operators). The timing model therefore retains within-request coalescing and tagged outstanding requests but removes persistent per-SM operand-cache reuse. Each resident load context can wait for its own packet while other contexts issue requests. These are structural changes, so they are not counted as equivalent host optimizations.

Subsequent host optimizations pack readiness flags and count duplicate shared-memory words once per lane instead of repeating that count for every bank. Bank-conflict service demand remains unchanged. The first 10,000 full-chip cycles reproduce the same event hash, cache counts, resident blocks, and completion counts before and after these changes. Execution time fell from 23.605 to 15.699 seconds in that screen, a 1.50-fold speed increase. This short comparison verifies preservation of the observed prefix; it is not full GEMM validation. The small timing smoke also retains both complete cycle counts and all counters.
