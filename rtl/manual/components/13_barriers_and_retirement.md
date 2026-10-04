# 13. Barriers and retirement

[System specification and chapter index](../../rtl_microarchitecture_spec.md) · [Approved manual structure](../../hardware_manual_structure.md)

## 1. Purpose and boundary

A barrier orders participating warps. Retirement ends a block only after its threads and required external stores have completed.

This is a specification of the executable reconstruction. Statements about physical RTX 5090 hardware retain their source or measurement scope; helper defaults describe model configurations.

## 2. Quantitative parameters

The table assigns this chapter ownership of the following inventory entries. “Baseline” preserves the existing setting; the evidence check may instead support a scoped alternative. Source priors are usable provisional estimates, not measurements of a private circuit.

| ID | Definition | Baseline | Unit | Recorded basis | Initial check |
|---|---|---|---|---|---|
| F081 | Which threads or warps must arrive for a barrier to release. | {"warp_size":32,"default_participants":"all live CTA threads","explicit_count_multiple":32,"barrier_slots":16} | threads; named barrier slots | KNOWN_SOURCE | Scoped source or observation |
| F082 | How a barrier distinguishes successive uses and rejects old arrivals. | {"generation_initial":0,"generation_increment":1,"release_when":"participant arrival count reaches configured count","reuse":"clear arrivals before accepting next generation"} | generation counter | ENGINEERING_ASSUMPTION | Scoped source or observation |
| F083 | Which unfinished memory or execution operations must drain before barrier release. | {"release_requires":"all earlier participant shared/global operations complete at modeled visibility point","later_memory_issue":"blocked until release","universal_DRAM_writeback_required":false} | ordering rule | KNOWN_SOURCE | Scoped source or observation |
| F084 | What completion event acknowledges an output store and what visibility it guarantees. | {"store_ack":"backing memory accepts and commits modeled store","pending_store_counter_bits":16,"thread_exit_waits_for_pending_stores":true} | completion rule | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F085 | Which events must finish before a whole-grid completion event is reported. | {"grid_done":"all CTA threads exited and modeled pending stores returned","completion_collection":"central outstanding-CTA counter","stream_event_visible_after_grid_done":true} | completion rule | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| T043 | Number of participant arrivals accepted by a barrier per cycle; excludes the release delay after the final arrival. | Not specified | warp arrivals per SM reference cycle | unidentified | GPU contract or effective path |
| T044 | Time from the final required arrival and memory condition to the barrier releasing participants; excludes subsequent scheduler selection. | Not specified | SM reference cycles after final accepted arrival | unidentified | GPU contract or effective path |
| T045 | Time from a barrier release to a warp becoming eligible to execute again; excludes its later competition for an issue slot. | Not specified | SM reference cycles from release to scheduler eligibility | unidentified | GPU contract or effective path |

Use the [complete parameter table](../../parameter_master_table.md) for values, scope, evidence links and provisional alternatives. Device capacities are centralized in the system specification. Per-module tables below identify which parameters are actually consumed by each implementation.

## 3. Interfaces and transaction ownership

Warp arrival → generation-specific barrier state → release → continued issue. Warp end plus store acknowledgements → block completion → resource return.

The exact port names, directions, widths and acceptance rules are listed in the implementation contracts in Section 8 and their linked sources. A connection must preserve both payload and ownership while stalled. The common system protocol applies unless a module contract explicitly states a pulse-only interface.

## 4. State and storage

Each linked module contract specifies its arrays, counters, masks, pointers or state machine. Those fields belong to that implementation only. A primitive helper is not an additional copy of a hardware resource inside the connected top unless that top instantiates it. Reset removes outstanding model ownership according to the specified contract; physical power-on behavior is outside this model.

## 5. Functional transitions

The simple controller gathers an arrival mask and emits a delayed release. The numerical generation-aware barrier prevents arrivals from one iteration releasing another. Completion is sticky in the primitive until reset; resident wrappers reuse contexts through their own control.

Requests are accepted only when the named receiver permits acceptance. Completion must update the original owner before resources are released. The implementation contracts below describe each state transition and numerical transformation separately.

## 6. Timing and arbitration

Use completion latency, acceptance interval and queue capacity as three distinct quantities: when a result becomes available, how often a new request can start, and how many requests can remain pending. The per-module timing contract gives their actual code meaning.

For a held-response interface, observe a valid response after an edge, hold readiness low for one more edge, and verify that identity and data remain unchanged. Retirement occurs only on a later edge with both valid and ready. A receiver becoming free after an edge does not retroactively accept a request at that edge.

## 7. Invariants and failure handling

Participants and barrier generation must agree. Release cannot precede required protected work. A final arithmetic result is not equivalent to a committed output store.

Unsupported configurations must remain explicit. A passing test of a helper establishes its tested model contract, not a GPU-wide hardware policy.

## 8. Linked implementations and detailed contracts

The following contracts retain the quantitative organization, exact interfaces, state transitions and verification scope of the existing implementations. Verilog stays in separate source files. C++ adapters expose the same generated ports and clock behavior; they do not introduce independent timing constants.

### Implementation 12: Block barrier controller

**Role.** Collects one arrival bit per participating warp. It begins release only when every participant has arrived and the caller reports protected operations complete. After the supplied release delay, it pulses release and resets arrival state for the next generation.

**Quantitative configuration.** `WARPS` is four for the tested block; there are two barrier instructions per reduction step. `RELEASE_DELAY` is unknown on RTX and is a configuration value.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| WARPS | 4 | participants | All required arrival bits collected | Tested block width |
| RELEASE_DELAY | 1 | cycles | Positive | Baseline; intrinsic release unknown |
| Barrier instances in kernel | 2 | per reduction step | Protect staging and storage reuse | Source/compiled execution structure |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| arrivals | input, WARPS one-cycle arrival bits | One-cycle arrival pulses from the participating warps. |
| protected_operations_complete | input, one bit | External confirmation that barrier-protected work completed. |
| release_warps | output, one-cycle release pulse | Registered pulse releasing the waiting participant set. |

**Documented functional boundary.** Ordinary CTA barrier participation, reuse and participant-relative memory visibility are now identified from PTX. Protected completion means the required prior reads have returned and writes are visible to participants; it is not a universal DRAM flush. Explicit-count and exited-thread cases require caller-side participant tracking that this four-bit baseline does not yet supply. Release/resume delays remain unknown physical timings.

**Interface protocol.** One barrier generation is outstanding. Clear old arrival pulses. The caller supplies a justified protected-completion condition and distributes release to the correct block warps.

**Stored state.** Arrival mask, releasing bit and remaining release delay.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| arrived | WARPS bits | Arrivals in current generation |
| releasing / remaining | 1 / signed 32 bits | Release phase and delay |

**Reset and cycle transitions.** Reset clears arrivals. Accumulate arrival bits while collecting. When all participants arrived and protected work completed, enter release countdown. Pulse release, clear arrivals, and return to collection.

**Invariants and failure handling.** Never release before both arrival and completion conditions. Do not reuse stale arrival bits for a new generation.

**Operation lifecycle.** These state names summarize the register implementation; they are not additional RTL registers.

| Phase | Trigger | Update/output | Next phase |
|---|---|---|---|
| COLLECT | arrival bits | Accumulate participant mask | COLLECT |
| COLLECT | all arrived and protected work complete | Load release delay | RELEASING |
| RELEASING | countdown expires | Pulse release and clear generation | COLLECT |

**Linked behavioral implementation.**


**Source implementation:** [barrier_controller.sv](../../components/library/barrier_controller.sv)


**Verification expectation.** Partial arrivals do not release. All arrivals without protected completion do not release. Completing protected work permits release. Passed with RELEASE_DELAY=2.

**Unimplemented or unidentified.** The completion input defines the modeled drain obligation externally. Actual NVIDIA memory-ordering obligations, arrival throughput, release timing, partial participants, and asynchronous barrier semantics remain unidentified.

### Implementation 13: Block completion

**Role.** Retires the modeled block only after every warp ends and the caller reports output stores complete. Completion remains asserted until reset.

**Quantitative configuration.** Four warp-end bits for the example. Output completion comes from the store path; it is not implied by instruction issue.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| WARPS | 4 | end flags | All must be true before retirement | Tested block width |
| Output completion | External flag | boolean | Must reflect all required stores | Integration requirement, unimplemented return path |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| ended | input, WARPS end flags | Persistent completion flag from each warp. |
| all_output_stores_complete | input, one bit | External confirmation that required output stores completed. |
| block_complete | output, one bit | Latched block retirement eligibility. |

**Interface protocol.** End flags remain asserted after each warp ends. Output completion must come from the store completion path.

**Stored state.** Latched block completion bit.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| block_complete | One bit | Latched completion |

**Reset and cycle transitions.** Reset clears completion. When all ended flags and output completion hold, latch completion until reset.

**Invariants and failure handling.** Instruction end alone cannot retire the block. Return the completed block slot to the allocator only once.

**Operation lifecycle.** These state names summarize the register implementation; they are not additional RTL registers.

| Phase | Trigger | Update/output | Next phase |
|---|---|---|---|
| INCOMPLETE | all ended && stores complete | Latch completion | COMPLETE |
| COMPLETE | until reset | Hold completion | COMPLETE |

**Linked behavioral implementation.**


**Source implementation:** [completion_tracker.sv](../../components/library/completion_tracker.sv)


**Verification expectation.** Test incomplete warps and pending output stores prevent retirement. Not behaviorally tested yet.

**Unimplemented or unidentified.** Whole-grid completion, output-store acknowledgments, allocation release wiring, and end-to-end integration are missing.

### Implementation 42: Explicit producer and consumer barrier generations

**Question and role.** What prevents a fragment warp from reading an incompletely staged operand frame, or the next stage from overwriting values still in use? The [generation barrier](../../components/cta_generation_barrier.sv) makes those obligations explicit. An owner first arms one generation with an expected participant mask, then submits arrivals for those participants. A registered release becomes available only after the entire expected mask has arrived, and remains held until acknowledged. The CTA controller uses two generations per reduction stage: producer visibility before computation and consumer memory-use completion before stage replacement.

A generation is a 32-bit sequence number identifying one barrier use. The default participant count is four modeled warps. Arrival granularity is therefore a warp, not 128 independently modeled threads. The component is an executable synchronization hypothesis; its masks, capacity and release delay do not identify private NVIDIA barrier hardware.

| Interface | Signals and widths | Contract |
|---|---|---|
| Arm | Valid/ready; 32-bit generation; `WARPS`-bit expected mask | Accepted only while idle; generation must be the next sequence number and mask nonempty |
| Arrival | Valid/ready; 32-bit generation; `WARPS`-bit arrival mask | An event for an already armed generation; nonempty expected subset, with no previously arrived bit |
| Release | Valid/ready; retained 32-bit generation and expected mask | Available after all participants arrive and the configured registered delay; stable until acknowledged |
| Diagnostics | Arrived mask and active flag | Show which participants have arrived and whether collection/delay/release is active |
| Clock/reset | `clk`, `rst` | Rising-edge transitions; reset cancels active work and restarts sequence at zero |

**State and timing.** IDLE accepts one arm transaction. COLLECT records distinct participant bits until the accumulated mask equals the expected mask. DELAY applies `RELEASE_DELAY`, whose default is one cycle, then RELEASE holds the generation and mask. Only actual release acknowledgment increments the next-generation counter and clears the state. A new arm cannot be accepted on that same edge; it is eligible in the following cycle. Generation wrap is unsupported.

For a final arrival accepted at edge `a`, release becomes visible after edge `a + RELEASE_DELAY`. With a continuously ready consumer, acknowledgment occurs at edge `a + RELEASE_DELAY + 1`. These are model timing rules. A held arm may be backpressured while active. Arrivals are events for an existing arm, not speculative requests held before one: simultaneous idle arm and arrival, stale generation, duplicate/unexpected participants and arrivals after collection closes are rejected.

**Connection to actual producer and consumer progress.** For zero-based reduction stage `s`, producer generation is `2 × s` and consumer generation is `2 × s + 1`. The controller arms the producer before loading. A producer warp arrives on its final actual vector shared-write commit: the final four 32-halfword groups, numbered 60–63 in the 2,048-halfword stage, belong to warps zero through three. Computation cannot start before producer release is acknowledged.

The consumer generation is armed before the four-warp batch starts. An arrival mask includes only newly registered `warp_memory_safe` participants, as defined in section 4.40. The controller remembers sent bits so a persistent memory-safe indication cannot produce duplicate arrivals. The controller separately waits for and captures the batch’s actual C results, then acknowledges consumer release before overwriting shared input or entering the output phase. At K1536, 48 stages require 192 producer warp arrivals, 192 consumer warp arrivals and 96 releases, with generations zero through 95.

**Memory visibility versus register results.** NVIDIA’s [PTX barrier definition](https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#parallel-synchronization-and-communication-instructions-bar) orders participating memory accesses. A performed read has supplied a value that another participant can no longer change; a performed write is visible to other participants. It does not specify a universal flush of independent matrix register results. [Literature receipt 44](../../discovery_rounds/literature_sweep_044.json) records that distinction.

Consumer arrival therefore uses shared-read completion rather than the all-service `warp_drained` flag. The model still uses a conservative proxy for native arrival: the entire bounded 40-instruction window and cooldown must finish, and shared reads must reach actual response retirement. Original instructions between this window and BAR at address 0x15f0, including LDC/UIADD3, are not replayed. The controller also waits for the full batch result before acknowledging consumer release, independently of memory safety. This change separates the obligations; it does not establish a faster hardware barrier or remove the conservative whole-stage schedule.

The release delay, one-active-generation capacity and warp-granularity participation remain model choices. These stage barriers also do not replace the output scratch component’s stronger whole-phase fence or recover its WARPSYNC semantics.

**Verification.** The [barrier component receipt](../../components/cta_generation_barrier_verification.json) has 20 positive checks under release delays one and five, plus nine rejected protocol cases. It checks partial arrivals, mask matching, held release, generation sequencing, busy-arm backpressure and reset during collection, delay and release. The refreshed [multiwarp receipt](../../numerical/native_multiwarp_stage_verification.json) checks 4,096 numerical words with service ownership and drain tracking. The [connected receipt](../../numerical/studied_gemm_cta_barriers_verification.json) checks 5,120 first-CTA outputs, including K1536, and exact 192/192/96 full-reduction counts. The 5,120-word connected receipt retains its pre-dynamic-coordinate controller version. The current [quick CTA regression](../../numerical/studied_gemm_cta_barriers_quick_verification.json) checks 4,096 words, and the current [complete-grid receipt](../../numerical/studied_gemm_grid_verification.json) checks 24,576 words including K1536 with the dynamically addressed controller. Physical evidence remains eight identified fields, 32 partial and 94 unknown; no barrier latency or other field is newly closed.

Run `python studies/rtx5090_gemm_milp/rtl/components/verify_cta_generation_barrier.py` for the component. Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_studied_gemm_cta.py --cta-barriers` for the connected first CTA.

**Inline behavior.**


**Source implementation:** [cta_generation_barrier.sv](../../components/cta_generation_barrier.sv)

### C++ component adapters

- [barrier_controller](../../cpp/barrier_controller.hpp) — adapter for [the matching Verilog source](../../components/library/barrier_controller.sv).
- [completion_tracker](../../cpp/completion_tracker.hpp) — adapter for [the matching Verilog source](../../components/library/completion_tracker.sv).
- [cta_generation_barrier](../../cpp/cta_generation_barrier.hpp) — adapter for [the matching Verilog source](../../components/cta_generation_barrier.sv).

## 9. Verification and evidence

Retain the verification expectations and existing receipts in Section 8. The [integration and verification chapter](../integration_and_verification.md) separates existing numerical tests, new C++ smoke tests and GPU measurements. The most recent connected-grid receipt checks 24,576 output words; it does not calibrate the integrated cycle count.

## 10. Optimization implications and remaining gaps

Barrier edges become precedence constraints. Use measured compound synchronization costs at their scope; do not label a loop cost as isolated barrier latency.

A parameter checked through documentation or a transferred prior can be used provisionally. Refine it when a new end-to-end case disagrees materially or when it changes the optimization choice. Do not spend time recovering a private property that the supported execution path does not exercise.

## 11. Staging barrier and context reuse contract

The compiled staging candidate reaches a block barrier only after each warp has finished its producer prefix. A barrier represents agreement among all four warps; it cannot release a context whose last load or shared commit is still pending. This connects the register-readiness rules in [Chapter 04](04_registers_readiness_and_operand_collection.md#11-candidate-staging-register-ownership) to the transaction ownership rules in [Chapter 07](07_load_store_execution.md#11-candidate-compiled-staging-path).

For each resident context, the candidate records the original stage-request ID and four warp cursors. Stage completion requires all four cursors at the end of the decoded prefix, no outstanding load for that context, and no outstanding shared-store commit. `done_valid` then carries that context and request ID until `done_ready` is accepted. The surrounding generation barrier and controller still govern the transition from staging to compute; this candidate does not introduce early staging/compute overlap.

Transaction IDs increase across loads and each load owns two sector IDs. A returned sector must still belong to an accepted live load. After the completion handshake, the context can be reused, but an old callback must never satisfy a new stage. The C++ component rejects completed-stage, duplicate and unowned callbacks rather than silently updating current register state. These checks provide ownership isolation; they do not implement a general GPU memory-consistency model.

| Event | Required condition | Consequence |
|---|---|---|
| Warp reaches producer barrier | Its extracted instruction cursor has drained | Wait for the other warps and pending transactions. |
| Shared commit becomes visible to the model | Commit packet accepted by `write_ready` | Release that store's commit ownership. |
| Stage completion offered | All four warps and all loads/stores drained | Hold original context/request ID. |
| Completion acknowledged | `done_valid` and `done_ready` | Release the staging context. |
| Callback from a retired stage | No matching live accepted load | Reject; do not mutate a reused context. |

See [the C++ source](../../../step23_hlm_connected_gpu_reproduction_001/staging_cpp_repair/staging_event.hpp) and [unit receipt](../../../step23_hlm_connected_gpu_reproduction_001/staging_cpp_repair/unit_receipt.json) for executable checks. The RTL counterpart has its own interface and ownership implementation; its source and completed or pending differential checks are linked in the [integration chapter](../integration_and_verification.md#compiled-staging-repair-candidate). No physical barrier-release latency has been inferred from the focused whole-kernel error reduction.

**Separate Verilog realization.** [The behavioral staging module](../../../step23_hlm_connected_gpu_reproduction_001/staging_rtl_repair/repaired_staging.sv) implements the same candidate state and ordered edge transitions, using [generated instruction tables](../../../step23_hlm_connected_gpu_reproduction_001/staging_rtl_repair/producer_tables.svh). It adds numerical sector payloads and shared halfword outputs to the C++ metadata interface. This component implementation does not by itself replace or validate the full-chip model.

[The completed component parity receipt](../../../step23_hlm_connected_gpu_reproduction_001/staging_rtl_repair/parity_receipt.json) records 921,445 protocol/address/counter comparisons and 36,864 BF16 payload checks across 18 frames. It does not validate full-chip timing, Verilog matrix arithmetic, mid-flight reset, or RTL negative-response rejection.
