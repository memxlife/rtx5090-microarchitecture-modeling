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

The completed large comparisons use M=2048 and N=2112. For [K=1536](../calibration_large_001/event_cpp/full_1536_result.json), 836,886 model cycles become 284.655 microseconds at the 2.94 GHz reference, versus the saved GPU median of 277.274 microseconds: a 2.662% overestimate. For [K=3072](../calibration_large_001/event_cpp/full_3072_result.json), 1,636,081 cycles become 556.490 microseconds, versus 532.448 microseconds: a 4.515% overestimate. Error is (prediction − measurement) / measurement. Both results meet the approximate 5% target under this reference-clock conversion; the [combined receipt](../calibration_large_001/event_cpp/full_completed_comparison.json) records them.

The model assumes warm input data, 48 cache slices, provisional XOR address routing, and 32 shared-read slots. All read requests hit the modeled cache. These assumptions remain provisional, and the GPU measurements lack matched active-clock records. Each case retires all 4,224 thread blocks and covers all 4,325,376 output addresses, but the large simulation contains no numerical payload or matrix arithmetic. Earlier numerical tests remain separate evidence for matrix correctness. Full-chip large-workload equivalence with RTL has not been tested.
