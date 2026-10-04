# Integration and verification

[System specification](../rtl_microarchitecture_spec.md) · [Whole-GPU overview](00_gpu_overview.md)

## Connected execution contract

The existing numerical top is [resident_gemm_multi_sm_nb_l2.sv](../numerical/resident_gemm_multi_sm_nb_l2.sv). It assigns disjoint output tiles to two SM models, each with two resident contexts. A shared nonblocking read gateway coordinates pending fetches. Backing reads and masked writes are serviced by the numerical test harness; store acknowledgement is required before grid completion.

The source has explicit launch range, alignment and overlap checks. It captures matrix bases at acceptance so subsequent host changes do not alter an in-flight launch. The test domain uses immutable A/B inputs and disjoint C output. General coherent writes, atomics and arbitrary CUDA control flow are not implemented.

## Existing numerical receipt

[Connected-grid verification receipt](../numerical/resident_multi_sm_nb_l2_verification.json) records 24,576 checked output words across reductions of length 64 and 1,536, with two launches per reduction length. Each launch executes six blocks and reaches four resident blocks. Invalid launches cover misaligned C, overlap with A or B, and address overflow. Reset is tested only at the first pending input read, not during output stores.

The oracle constructs expected numerical matrix results independently of cache service and request ordering. Thus changing modeled cache timing cannot make wrong matrix values pass merely by finishing later. The receipt's elapsed cycles are model measurements, not comparisons with measured RTX timing.

## Source dependency and rebuild contract

[The connected-grid verifier](../numerical/verify_resident_gemm_multi_sm_nb_l2.py) is the authoritative existing dependency recipe. It imports its base source list and adds the resident-grid, shared-cache and transport modules. Preserve that dependency order and its DPI numerical support. The verifier builds a clocked Verilator testbench and checks the expected output words.

The fourteen primitive modules are separately available under the component library directory. Their bodies were extracted from [the preserved compatibility bundle](../components/hardware_blocks.sv). Compile either the bundle or the corresponding split files, never both, because they define the same modules.

## C++ equivalence boundary

[The C++ adapter](../cpp/component_model.hpp) drives Verilator-generated components. For these adapters, state transitions come from the linked Verilog rather than a separate handwritten copy of cache or queue behavior. A connected top must be evaluated as one hierarchy. Do not tick its children separately.

The two new adapter tests passed: [queue capacity/FIFO/held response](../cpp/queue_smoke.cpp) and [shared-memory write/read/latency/held response](../cpp/shared_smoke.cpp). Their exact build commands and source hashes are in [the C++ verification receipt](../cpp/verification.json). They do not prove every generated adapter was separately compiled.

## Performance validation boundary

The earlier phase-cost estimator and the connected numerical RTL are separate models. The former has two new workload predictions within 5%; the latter has numerical correctness and synthetic cycle timing. Preserve this distinction in plots, MIP objective comparisons and reported errors.

The synthetic backing gateway is much narrower than physical full-chip bandwidth. Numerical correctness is still meaningful, but its runtime cannot be scaled to the 170-SM GPU merely by multiplying the number of SMs. Timing calibration must preserve service demand, concurrency and dependency ownership together.

## Change procedure

When a test changes a meaningful parameter, update its evidence record, consuming implementation and chapter together. Rebuild the affected helper and one relevant connected numerical case. Compare hardware runtime only when the change is intended to affect physical prediction. Stop investigating a private detail when provisional behavior is adequate for the end-to-end optimization decision.

## Large-grid calibration follow-up

The [large-grid experiment](../calibration_large_001/README.md) adds 170 SM instances and provisional cache slices totaling 96 MiB. Its CUDA service sweep supplies effective read, write, mixed-traffic, and backing-memory limits. An independent C++ timing executor preserves queues, dependencies, arbitration, and backpressure. Complete small-grid and component comparisons reproduce RTL timing, including eleven resident contexts per SM; these are implementation checks, not hardware parameter identification.

The completed large comparisons use M=2048 and N=2112. For [K=1536](../calibration_large_001/event_cpp/full_1536_result.json), 836,886 model cycles become 284.655 microseconds at the 2.94 GHz reference, versus the saved GPU median of 277.274 microseconds: a 2.662% overestimate. For [K=3072](../calibration_large_001/event_cpp/full_3072_result.json), 1,636,081 cycles become 556.490 microseconds, versus 532.448 microseconds: a 4.515% overestimate. Error is (prediction − measurement) / measurement. These historical comparisons met the approximate 5% target against those saved GPU measurements; they do not describe the latest reproduction. The fresh six-case original-workload comparison has median absolute error 3.275% and maximum 5.870% for the frozen full-chip model, as recorded in [the replay receipt](../../step23_hlm_connected_gpu_reproduction_001/regression_suite/root_verified_replay.json); the [combined receipt](../calibration_large_001/event_cpp/full_completed_comparison.json) records them.

The model assumes warm input data, 48 cache slices, provisional XOR address routing, and 32 shared-read slots. All read requests hit the modeled cache. These assumptions remain provisional, and the GPU measurements lack matched active-clock records. Each case retires all 4,224 thread blocks and covers all 4,325,376 output addresses, but the large simulation contains no numerical payload or matrix arithmetic. Earlier numerical tests remain separate evidence for matrix correctness. Full-chip large-workload equivalence with RTL has not been tested.

## Compiled staging repair candidate

The latest candidate changes the staging producer inside the full-chip C++ timing model. It adds the actual compiled load/store prefix and register ownership rather than treating every cache response as immediate producer readiness. The frozen earlier simulator remains available. This candidate is not yet a calibrated 5% RTX 5090 model.

### Sources and interface boundary

The [C++ staging component](../../step23_hlm_connected_gpu_reproduction_001/staging_cpp_repair/staging_event.hpp) consumes the [decoded producer path](../../step23_hlm_connected_gpu_reproduction_001/staging_cpp_repair/producer_path.json). It is wired through [the candidate SM](../../step23_hlm_connected_gpu_reproduction_001/staging_cpp_repair/sm_event.hpp) and [full-chip driver](../../step23_hlm_connected_gpu_reproduction_001/staging_cpp_repair/full_gpu_parallel.cpp). Chapters [04](components/04_registers_readiness_and_operand_collection.md#11-candidate-staging-register-ownership), [07](components/07_load_store_execution.md#11-candidate-compiled-staging-path), and [13](components/13_barriers_and_retirement.md#11-staging-barrier-and-context-reuse-contract) define readiness, transactions and barrier drain.

One stage request carries context, request ID, tile coordinates, reduction-stage index, and A/B bases. Accepted sector requests retain their IDs until a corresponding return; shared commits retain their context and address packet until accepted. Completion carries the original stage ID. Reset or context reuse must not allow an old callback to alter a later stage. The repaired producer has its own register-ready, source-release and encoded-tag state; it does not instantiate another copy of the native compute pipeline.

The separate [behavioral Verilog staging component](../../step23_hlm_connected_gpu_reproduction_001/staging_rtl_repair/repaired_staging.sv) uses [generated producer tables](../../step23_hlm_connected_gpu_reproduction_001/staging_rtl_repair/producer_tables.svh). Its request, backing, commit and completion ports correspond to the C++ contract; the RTL additionally receives a 256-bit sector payload and emits 32 sixteen-bit shared-memory values per commit. The [differential harness](../../step23_hlm_connected_gpu_reproduction_001/staging_rtl_repair/parity.cpp) checks the component boundary. This is simulation behavior, with explicit ordered edge updates, rather than synthesis-ready implementation RTL. Full-chip replacement and equivalence remain separate checks. Sample ready/valid signals and packet fields before the rising edge; acceptance occurs when both are asserted. A stalled offer retains its identity and payload. The behavioral RTL deliberately uses ordered blocking updates to mirror the C++ edge transition, so the testbench must not resample partially updated state as a second acceptance on the same edge.

### Required checks and current evidence

| Check | Current evidence | What it establishes |
|---|---|---|
| Producer sector/commit conservation | [Unit receipt](../../step23_hlm_connected_gpu_reproduction_001/staging_cpp_repair/unit_receipt.json): 128 sectors and 64 commits per stage | Address coverage and transaction ownership. |
| Early versus delayed returns | Unit cycles 2,012 versus 2,661 | Register readiness cannot be bypassed by an early cache return; a late return remains limiting. |
| Backpressure and stale callbacks | Unit receipt | Commits are held until accepted; completed-stage callbacks are rejected. |
| Focused connected prediction | [Focused result](../../step23_hlm_connected_gpu_reproduction_001/staging_cpp_repair/focused_result.json) | The candidate completes the focused address/timing workload; numerical arithmetic is absent from this timing executor. |
| Original GPU numerical outputs | [Exact original reproduction](../../step23_three_way_original_workloads_001/GPU/small_receipt.json) | Forty-five complete output-matrix comparisons per case, not forty-five sampled values. |
| Relevant whole-kernel regressions | [Completed candidate summary](../../step23_hlm_connected_gpu_reproduction_001/regression_suite/candidate_summary.json): focused −11.0541%, long-small −11.4203%, dense +31.5735% | The candidate fails the approximate 5% accuracy target; completed tests block promotion. |
| New Verilog differential test | [Parity receipt](../../step23_hlm_connected_gpu_reproduction_001/staging_rtl_repair/parity_receipt.json): 921,445 protocol/address/counter comparisons; 36,864 BF16 payload checks across 18 frames | Matches the candidate component under three tested traffic scenarios; does not establish full-chip equivalence. |

For the 128×96×12,288 focus case, the unchanged GPU median is 380.345607 microseconds. The frozen baseline predicts 226.873129 microseconds; the repaired candidate predicts 338.301701 microseconds using 2,940 reference cycles per microsecond. Signed error, defined as `(prediction − GPU measurement) / GPU measurement`, changes from −40.3508% to −11.0541%. The difference between the two predictions removes 72.605% of the original timing gap arithmetically. That percentage is not a causal allocation of GPU time to a hardware mechanism.

The 340-cycle register-readiness prior, one-cycle source capture and one-cycle shared commit remain provisional. The native 40-instruction compute template and remaining full-kernel control path are unchanged and incomplete. Source parity, numerical correctness, and physical timing accuracy are three separate acceptance checks; passing one does not imply the others.

The completed dense regression is a failure to preserve earlier timing accuracy: on 1920×1920×1536, the repaired model predicts 945,861 cycles, or 321.721429 microseconds, against 244.518396 microseconds on the GPU: +31.5735% error. The frozen baseline error was +0.2739%. [The dense receipt](../../step23_hlm_connected_gpu_reproduction_001/regression_suite/candidate_dense.json) therefore blocks promotion even though the focused small-grid prediction improved.

The completed staging differential scenarios take 5,868, 7,062 and 5,872 cycles. The payload oracle checks returned BF16 data and shared commits; a host multiplication uses those RTL-produced operands. It is not Verilog matrix computation or full-GEMM validation. Each scenario starts with reset; reset during in-flight transactions was not tested. Stale-return rejection was tested in C++ only, and RTL negative-response tests remain absent. Commit-time payload retention is safe within the tested single-write-per-group, drained-stage contract; overlapping writes to the same shared group require a separate ownership rule.

The longer 128×96×49,152 regression completes 3,956,399 cycles, or 1,345.713946 microseconds, versus 1,519.212790 microseconds measured on the GPU: −11.4203% error. It covers all 12,288 output addresses in the metadata model; GPU numerical comparisons are separate. All three requested candidate regressions are now complete.


## Four-partition staging follow-up

Step24 separately replaces the Step23 single staging issue port with four partition lanes and a native-compute reservation mask. [Chapter03](components/03_scheduling_and_instruction_issue.md#11-experimental-four-partition-staging-issue) defines its shared queues, per-partition cursors, native-first provisional priority and unchanged readiness rules. [The completed comparison](../../step24_staging_interaction_001/result_report.md) gives small error −27.5375% and dense error +10.4050%; the dense prediction improves relative to the single-issue candidate, but the small prediction worsens. Both candidates remain unpromoted. [The matching Verilog component receipt](../../step24_staging_interaction_001/partition_rtl/parity_receipt.json) passes 943,985 protocol/address/counter comparisons and 49,152 operand-value checks over 24 frames, including native partition reservations. It verifies behavioral component consistency with host product checking, not full-chip Verilog execution or GPU timing accuracy.
