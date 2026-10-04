# Quantitative RTX 5090 specification: established numbers and missing parameters

For a baseline value, units, uncertainty range, and evidence label for every specification field, use the [134-field provisional profile](provisional_parameters.md). Physical identification remains 8 full, 32 partial, and 94 unknown; provisional values do not change those counts.

This specification separates physical capacities, measured service costs, and compound benchmark response times. A measured instruction-sequence duration is not automatically the intrinsic latency of one hardware unit. Numbers below come from saved device queries and experiments; no new GPU workload was run.

“Unknown” means our evidence does not identify a defensible hardware value. Synthetic numbers in the Verilog demonstration are excluded from the hardware tables.

## 1. Device and SM capacities

| Component or property | Quantitative value | Evidence and interpretation |
|---|---:|---|
| Active SMs | 170 | Device configuration recorded in the architecture review |
| L2 capacity | 96 MiB = 100,663,296 bytes | Device configuration |
| Registers per SM | 65,536 × 32-bit words = 256 KiB | Saved runtime query |
| Maximum resident warps per SM | 48 | Compute-capability 12.0 documentation recorded in the source review |
| Threads per warp | 32 | CUDA execution structure; full-warp probes use this width |
| Maximum resident threads implied by 48 warps | 1,536 | 48 × 32; not a measured count of productive threads |
| Runtime-reported shared memory per SM | 100 KiB = 102,400 bytes | Saved device query; use this experimental allocation context |
| Runtime-reported opt-in shared limit per block | 99 KiB = 101,376 bytes | Saved device query |
| Published versus queried shared-memory limit | 128 KiB published versus 100 KiB queried | Recorded discrepancy; do not substitute the larger number for verified launch limits |
| Shared-memory banks | 32 | Documented mapping and counter validation for tested accesses |
| Shared bank word unit | 4 bytes | Bank index is four-byte word index modulo 32 for tested ordinary accesses |
| Memory-sector counter unit | 32 bytes | Source-specific traffic counting |
| Documented cache line | 128 bytes, four 32-byte sectors | Saved architecture/source review; not a discovered set mapping |
| SM reference frequency for conversions | 2.94 GHz | Chosen reference close to observed rates; not a guaranteed hardware maximum |
| Reference-cycle duration | 0.340136 nanoseconds | Reciprocal of 2.94 GHz |
| Sustained large-copy rate | 1.4737 TB/s | Original device-copy benchmark; decimal bytes per second, workload-specific |

Sources: [device-query record](../experiment.json), [architecture source review](../architecture_012/results.md), and [shared-memory evidence](../model_components/shared_memory_evidence.json).

## 2. Measured matrix-execution behavior

The primitive performs a 16 × 16 × 16 BF16 matrix operation with FP32 accumulation. Each operation emits two native matrix instructions. Inputs are already in registers. Costs below are median elapsed cycles per operation per warp, not intrinsic latency of either native instruction.

| Active warps in a block | One accumulator chain | Eight independent chains |
|---:|---:|---:|
| 1 | 64.013 cycles/operation/warp | 64.465 cycles/operation/warp |
| 4 | 64.217 cycles/operation/warp | 64.325 cycles/operation/warp |
| 8 | 127.997 cycles/operation/warp | 128.015 cycles/operation/warp |

At four warps, the approximate aggregate rate is 4/64.217 = 0.06229 operations per SM cycle. At eight it is 8/127.997 = 0.06250. That constrains the tested primitive's throughput ceiling. It does not identify pipeline count, issue-port organization, or result latency. [Corrected matrix experiment](../diagnostic_006/results.md).

**Missing:** native instruction result latency, initiation interval per execution partition, internal Tensor pipeline organization/routing as incorporated into this model (four architectural Tensor Core blocks per SM are documented), operand-collection capacity, and register-rearrangement timing under the real workload.

## 3. Shared-memory service costs

| Measured/model quantity | Value | Valid meaning |
|---|---:|---|
| Bank-processing cost in saturated probe | 1 cycle/package | Effective service rate; not read-result latency |
| Scalar full-warp load service floor | 2 cycles/load | Measured lower-bound model for tested aligned 32-bit reads |
| Contiguous 128-bit-per-lane load | 512 bytes/warp load | 32 lanes × 16 bytes |
| Processing demand of that vector load | 4 packages/load | Tested aligned contiguous pattern |
| Effective saturated vector service | 4 cycles/load | Tested pattern; equivalent to 128 bytes/cycle under its assumptions |
| Pure low-bank stream discrepancy | Approximately 7–9% | Counterexample to interpreting service work as complete elapsed time |

The scalar model uses the larger of instruction service demand and bank service demand. Its parameters price work under the tested saturation conditions, not all shared-memory waiting. [Executable service model](../model_components/shared_memory.py).

**Missing:** intrinsic shared read/write response delays, physical read/write ports per bank, broadcast timing, queue capacity, exact L1/shared configuration, and the delays from returned words to collected matrix operands.

## 4. Global-load response measured with controlled L2 states

Each request in this probe reads 64 bytes from a distinct 128-byte line. Four warps issue ordinary 16-bit global loads followed by consuming shared stores. The timing includes address work, stores, control, and scheduling.

| Data source | One-load group | Four-load group | Effective increment for each added request |
|---|---:|---:|---:|
| Verified L2 hits | 375.302 cycles | 399.426 cycles | 8.041 cycles |
| Verified L2 misses | 956.986 cycles | 1,015.362 cycles | 19.459 cycles |

At the 2.94 GHz reference, these four-load group durations correspond to 135.86 nanoseconds and 345.36 nanoseconds. This conversion does not make them isolated L2 or GDDR7 latencies. [Calibration parameters](../model_components/global_response_parameters.json).

| Additional controlled comparison | Observed cost |
|---|---:|
| 75% hits, one miss in every four-load group | 959.531–969.486 cycles/group |
| Same 75% hits, misses concentrated in a quarter of groups | 552.993 cycles/group |
| Two blocks requesting shared fresh data together | Approximately 1,010.6 cycles/group in both |
| Second block starts after the first has fetched the data | 396.884 cycles/group for the second block |

These results constrain dependency and pending-data behavior. They reject a timing model based only on overall hit fraction. Sources: [mixed request outcomes](../diagnostic_020/results.md) and [pending-data experiment](../diagnostic_021/results.md).

**Missing:** actual cached load latency, per-slice L2 service bandwidth, L2 queue depths, load/store issue widths, miss-record capacity, return bandwidth, translation costs, and intrinsic GDDR7 response timing.

## 5. Quantitative resource demand of the two original GEMM tiles

Both kernels use 128 threads, four warps, BK = 32, and two block barriers per repeated step. The shared allocation below is derived from the original single-buffer storage formula, including 4,096 bytes of output scratch. It is not a model of allocation rounding.

| Property | 32 × 32 tile | 64 × 48 tile |
|---|---:|---:|
| Registers reported per thread | 40 | 64 |
| Register words before allocation rounding, per block | 5,120 | 8,192 |
| Source-required shared bytes, per block | 8,192 | 11,264 |
| Observed normal resident blocks/SM | 11 | 8 |
| Warps at that resident capacity | 44 | 32 |
| Whole-device resident block capacity | 1,870 | 1,360 |
| Compiled four-load response groups/warp/step | 4 | 7 |
| Blocks for 1,920 × 1,920 output | 3,600 | 1,200 |

For shared bytes, the calculation is 2 × 32 × (BM + BN) + 4,096. Raw register/shared totals alone do not explain allocation granularity or establish the exact resident limit; use the observed occupancy results. [Capacity diagnosis](../diagnostic_004/final_report.md).

## 6. Separately measured real-path costs

These are effective durations of compound compiled paths in the warm small-grid context. They are useful evidence to explain, not substitutes for a component's intrinsic timing specification.

| Path | Smaller tile, microseconds/step | Larger tile, microseconds/step |
|---|---:|---:|
| Common loop and barriers | 0.037325 | 0.050675 |
| Input staging plus common work | 0.780275 | 1.345067 |
| Operand preparation/computation plus common work | 0.202142 | 0.462933 |
| Composed cost after subtracting common work once | 0.945092 | 1.757325 |
| Same composed cost in 2.94 GHz reference cycles | 2,778.57 | 5,166.54 |

These independent path measurements, combined with separately measured service limits for dense grids, support complete-GEMM predictions within a largest observed error of 5.97%. They do not validate the new Verilog model. [Actual-path parameters](../model_components/actual_path_parameters.json).

## 7. Clock rates actually reported in the final profiles

| Profiled path | SM counter rate |
|---|---:|
| Common loop/barrier path | 2.93005 GHz |
| Input staging | 2.66450 GHz |
| Operand computation | 2.93218 GHz |
| Complete GEMM | 2.84958 GHz |

These rates differ from host-side snapshots. They also show why assigning one reference-clock conversion to a compound measurement does not identify separate memory-domain delays. [Clock controls](../diagnostic_058/results.md).

## 8. Hardware fields that still have no identified value

| Component | Missing quantitative fields |
|---|---|
| Warp scheduler | Assignment rule, issue width by instruction class, initiation restrictions; architectural partition count is now documented as four |
| Registers/operand collection | Bank count, ports/bank, collector entries, bypass delay; allocation quantum is established separately |
| Matrix/CUDA execution | Modeled pipeline counts, native instruction delays and service intervals, sharing rules |
| Load/store path | Load/store queue entries, outstanding transactions/warp and SM, return throughput |
| L1/shared memory | Actual partition, L1 sets/ways/mapping, bank ports, intrinsic read/write delays |
| L2 | Sets, ways, slice mapping, lookup ports, intrinsic read/write latency, service rate, replacement and write policy |
| Device memory | Channel/bank mapping, request queues, read/write turnaround, controller and transfer timing |
| Synchronization | Barrier arrival throughput and release delay; documented drain obligations are established separately |

Write-back versus write-through is a missing policy, not a numeric field. We must identify it before writing correct write/eviction transitions. Similarly, a missing mapping or arbitration rule cannot be repaired by supplying one fitted cycle value.

The hardware specification should carry these unknowns visibly. The current demo's 3-cycle cache delay and 8-cycle matrix delay must not appear in this table as RTX 5090 facts. The [functional specification](component_specification.md) defines their eventual interfaces and transitions; the tables here provide the presently defensible quantities and precise gaps.


## 9. Discovery counts

The current physical inventory has **8 fully identified, 24 partially identified, and 55 unidentified functional fields**. Timing has **0 fully identified, 8 partially identified, and 39 unidentified fields**. Thus 79 functional fields and all 47 timing fields remain incompletely identified. The [registry](missing_parameter_registry.json) preserves evidence and scope. The [provisional profile](provisional_parameters.md) supplies development baselines for all 134 fields without closing these evidence gaps.

The admitted allocation rules round register words to 256 per warp and shared bytes to 128 per block. The shared total includes runtime-reserved bytes. Saved GEMM allocations are therefore 9,216 and 12,288 shared bytes, including the 1,024-byte reservation, for the 32 × 32 and 64 × 48 tiles. These allocation quantums describe CUDA resource admission, not physical bank geometry.

## 10. Measured LDSM service work and additional delay

All 32 lanes participate in these aligned x1/x2/x4 shared matrix loads. Row providers are divided into groups of eight lanes. Within each group, equal row addresses merge; distinct rows are assigned to one of eight bank quartets by address bits 6:4. The largest number of distinct rows in a quartet gives that group’s work. Sum group work without merging rows across group boundaries. This predicts 24 development cases and six fresh address cases, for both normal and transposed forms.

In the exact single-warp x4 load-and-sum loop, each extra package adds **2 SM cycles** relative to the conflict-free four-package case. A package here is one counted shared-memory service unit; its timing does not establish physical bank ports. The baseline loop cost is 73.00146484375 cycles per iteration after subtracting the zero-iteration measurement. It includes the load, consuming additions, loop control and compiler scheduling.

| Fresh case | Packages | Predicted cycles/iteration | Measured cycles/iteration | Absolute relative error |
|---|---:|---:|---:|---:|
| Three distinct rows per bank quartet | 12 | 89.00146484375 | 89.00146484375 | 0% |
| Five distinct rows in one quartet | 20 | 105.00146484375 | 105.00146484375 | 0% |
| Six distinct rows in one quartet | 24 | 113.00146484375 | 113.00146484375 | 0% |

Each case was measured with normal and transposed loads, making six fresh timing cases. Repetitions returned identical cycle counts within each tested configuration. The frozen prediction is baseline plus twice the package count above four. [Raw comparisons](parameter_sweep/ldsm_service/timing_validation_analysis.json) preserve both cycle-count boundaries. These exact matches validate this probe’s incremental conflict cost; they do not validate GEMM runtime, a pure LDSM latency, or the full simulator.

## 11. Quantitative arithmetic reconstruction

The supported BF16 cancellation tests retain a unit against opposite products of magnitude 2^25, but lose it at magnitude 2^26. At 2^26, a small contribution of 3 becomes 2 and a contribution of −3 becomes −2. These measurements support truncating each signed contribution toward zero after alignment to a quantum of 2^(largest contribution exponent −25). They do not identify the physical accumulator width.

The frozen rule predicts all 162 independent cancellation-family cases. The actual RTL/DPI implementation matches 1,536 saved hardware outputs with ARITHMETIC_MODE=1, while mode 0 preserves the older sequential-reference failure. The parameter propagates through native operand and shared-storage adapters. Both modes reject nonfinite/subnormal operands and results explicitly; the hardware observations that some subnormals survive have not yet expanded the executable domain. Base timing remains synthetic. [Model verification](numerical/aligned_dot_verification.json).

## 12. Clock references and unit-specific cycle rates

Three accepted probe samples measured 2.949618350 SM cycles per global-timer tick during computation, 2.953583287 during dependent loads, and 2.953207374 during a timer-read loop with a consumed checksum. PTX describes the global timer as a nanosecond reference, with target-specific behavior intended for NVIDIA tools. The ratios describe these compiled runs; neither advertised boost nor an idle frequency snapshot substitutes for them. An initial empty timer loop was eliminated and its one-cycle, zero-tick result was rejected.

A separate, single shared-bank-conflict profile measured all four counter rates together:

| Counter domain | Measured cycles/second |
|---|---:|
| SM | 2,011,504,039.38 |
| L1TEX | 2,011,504,039.38 |
| GPC | 2,011,159,285.99 |
| LTS | 1,814,560,085.84 |

SM and L1TEX rates are identical in this profile. Thus two SM cycles convert to two L1TEX cycles here; the proposed interpretation of one L1 cycle from an assumed half-rate clock is unsupported. Each counter belongs to its named unit. To convert a measured source-cycle duration, multiply by the destination rate divided by the source rate from the same profile. This does not identify intrinsic bank service latency or a fixed ratio for every operating condition.

The management interface reports supported memory frequencies of 405, 810, 7001, 13801 and 14001 MHz, and graphics values between 180 and 3090 MHz. These reported values do not establish GDDR7 command clocks, data clocks or a conversion to physical signaling rates. The private clock tree and clock crossings remain unknown. [Raw clock evidence](parameter_sweep/clock_domains/analysis.json), [same-profile unit rates](parameter_sweep/unit_clock_rates/analysis.json) and [official cycle-counter semantics](discovery_rounds/literature_sweep_030.json).
