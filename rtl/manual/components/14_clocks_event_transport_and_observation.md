# 14. Clocks, event transport, and observation

[System specification and chapter index](../../rtl_microarchitecture_spec.md) · [Approved manual structure](../../hardware_manual_structure.md)

## 1. Purpose and boundary

This chapter defines the simulator time base, response holding and observation. Cycle counts are meaningful only with an explicit edge convention and a stated conversion clock.

This is a specification of the executable reconstruction. Statements about physical RTX 5090 hardware retain their source or measurement scope; helper defaults describe model configurations.

## 2. Quantitative parameters

The table assigns this chapter ownership of the following inventory entries. “Baseline” preserves the existing setting; the evidence check may instead support a scoped alternative. Source priors are usable provisional estimates, not measurements of a private circuit.

| ID | Definition | Baseline | Unit | Recorded basis | Initial check |
|---|---|---|---|---|---|
| F086 | Which GPU components use separate clocks and how those domains relate. | {"reference_SM_MHz":2950,"L1TEX_to_SM_rate_ratio":1.0,"LTS_to_SM_rate_ratio":0.9020911965950098,"globaltimer_reference":"documented nanosecond counter; target-specific"} | MHz; clock-rate ratios | MEASURED | GPU contract or effective path |
| F087 | The handshake and buffering rules carrying requests and values between clock domains. | {"protocol":"dual-clock ready/valid FIFO","depth":4,"synchronizer_stages":2,"ordering":"FIFO; no loss/duplication"} | entries; clock edges | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| T046 | Operating frequencies reported or measured for memory-related units; management clock labels do not reveal every physical clock domain. | Not specified | management-reported MHz; counter-derived MHz | partially_identified | GPU contract or effective path |
| T047 | Time for a request or response to cross between independently clocked units, measured in named source or destination clock edges. | Not specified | destination clock edges | unidentified | Transferred simulator prior |

Use the [complete parameter table](../../parameter_master_table.md) for values, scope, evidence links and provisional alternatives. Device capacities are centralized in the system specification. Per-module tables below identify which parameters are actually consumed by each implementation.

## 3. Interfaces and transaction ownership

One shared clock edge → simultaneous component state updates → settled outputs → observation. C++ calls the connected generated model rather than ticking child components sequentially.

The exact port names, directions, widths and acceptance rules are listed in the implementation contracts in Section 8 and their linked sources. A connection must preserve both payload and ownership while stalled. The common system protocol applies unless a module contract explicitly states a pulse-only interface.

## 4. State and storage

Each linked module contract specifies its arrays, counters, masks, pointers or state machine. Those fields belong to that implementation only. A primitive helper is not an additional copy of a hardware resource inside the connected top unless that top instantiates it. Reset removes outstanding model ownership according to the specified contract; physical power-on behavior is outside this model.

## 5. Functional transitions

Requests transfer on valid and ready at a rising edge. Outputs settle after evaluation and remain held until accepted. The reference counter counts model edges; the queue keeps due times and the dependency replay waits for actual returned operands.

Requests are accepted only when the named receiver permits acceptance. Completion must update the original owner before resources are released. The implementation contracts below describe each state transition and numerical transformation separately.

## 6. Timing and arbitration

Use completion latency, acceptance interval and queue capacity as three distinct quantities: when a result becomes available, how often a new request can start, and how many requests can remain pending. The per-module timing contract gives their actual code meaning.

For a held-response interface, observe a valid response after an edge, hold readiness low for one more edge, and verify that identity and data remain unchanged. Retirement occurs only on a later edge with both valid and ready. A receiver becoming free after an edge does not retroactively accept a request at that edge.

## 7. Invariants and failure handling

The chosen 2.94 GHz reference converts one microsecond to 2,940 reference cycles. Observed GPU clocks vary: older full GEMM was about 2.85 GHz and recent probes about 2.95 GHz. Conversion does not recover separate physical clock domains.

Unsupported configurations must remain explicit. A passing test of a helper establishes its tested model contract, not a GPU-wide hardware policy.

## 8. Linked implementations and detailed contracts

The following contracts retain the quantitative organization, exact interfaces, state transitions and verification scope of the existing implementations. Verilog stays in separate source files. C++ adapters expose the same generated ports and clock behavior; they do not introduce independent timing constants.

### Implementation 1: Shared timing and completion queue

**Role.** Stores accepted operation identities and their due cycles. It admits requests only when there is an unused slot and the initiation interval has expired. It retains a completed response until its receiver accepts it. Results retire in FIFO order; variable-latency out-of-order returns require a different completion structure.

**Quantitative configuration.** `SLOTS`: outstanding operations; `LATENCY`: cycles from acceptance to modeled completion; `INTERVAL`: cycles between acceptances. All must be positive. Default values are engineering test settings, not RTX parameters.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| SLOTS | 4 | entries | Positive | Baseline; hardware depth unknown |
| LATENCY | 1 | cycles | Positive | Baseline; resource-specific delay unknown |
| INTERVAL | 1 | cycles/acceptance | Positive | Baseline; measured service depends on operation class |
| req_id/rsp_id | 32 | bits | Caller assigns unique outstanding identities | Interface choice |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| req_valid / req_ready | input / output | Request present / receiver permits acceptance. |
| req_id | input, 32 bits | Operation or transaction identity retained until return. |
| rsp_valid / rsp_ready | output / input | Completed response present / consumer permits retirement. |
| rsp_id | output, 32 bits | Identity of the completed operation or transaction. |

**Interface protocol.** Request and response handshake; payload is an operation identity, not a numerical result.

**Stored state.** cycle, count, head, tail, next_accept; per-slot identity and due time.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| ids | SLOTS × 32 bits | Accepted identities |
| due | SLOTS × signed 32 bits | Due cycle of each identity |
| head/tail/count/next_accept | Signed 32-bit fields | FIFO and service admission |

**Reset and cycle transitions.** Reset clears count, pointers, cycle and initiation state. Empty queues ignore payload storage. An accepted request sets its slot due time to the acceptance cycle plus LATENCY. A held response remains stable until accepted.

**Invariants and failure handling.** 0 <= count <= SLOTS. Each accepted identity returns once, in acceptance order. A full queue does not accept a request even if a response will retire at the same edge.

**Operation lifecycle.** These state names summarize the register implementation; they are not additional RTL registers.

| Phase | Trigger | Update/output | Next phase |
|---|---|---|---|
| RESET | rst | Clear ownership count, pointers and service cycle | EMPTY |
| READY | valid && ready | Record identity/due time; increment occupancy | ACTIVE |
| ACTIVE | head due but rsp_ready=0 | Hold valid and identity | RESPONSE_HELD |
| RESPONSE_HELD | rsp_valid && rsp_ready | Retire head and free one entry | READY/ACTIVE |

**Linked behavioral implementation.**


**Source implementation:** [timed_queue.sv](../../components/library/timed_queue.sv)


**Verification expectation.** Test queue capacity, return ordering, and response stability with rsp_ready held low. These cases passed in components_tb.

**Unimplemented or unidentified.** Actual per-resource queue capacities and initiation/return limits are unknown. This queue is used by the simple pipeline and controller wrappers below.

### Implementation 14: Reference clock and cycle accounting

**Role.** Counts rising clock edges after reset. Other components use that same reference domain in this baseline. Observed completion-cycle differences provide timing output.

**Quantitative configuration.** Chosen reporting reference is 2.94 GHz, corresponding to 0.340136 ns/cycle. Final profile rates ranged from 2.66450 GHz for staging to 2.93218 GHz for computation.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| Counter width | 64 | bits | Wrap is outside admitted run horizon | Interface choice |
| Reporting reference | 2.94 | GHz | Unit conversion, not physical clock lock | Chosen reference |
| Domain count | 1 | clock | All current modules share clk | Baseline; memory domains missing |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| cycles | output, 64-bit unsigned counter | Reference clock edges counted since reset. |

**Interface protocol.** Counter is observational and must not control arbitration. Clock and reset are common inputs.

**Stored state.** 64-bit cycle counter.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| cycles | 64 bits | Reference tick count |

**Reset and cycle transitions.** Synchronous reset sets zero; every other rising edge increments by one.

**Invariants and failure handling.** All timed components in this baseline must share the same reset/clock convention. This does not implement memory-clock crossings.

**Linked behavioral implementation.**


**Source implementation:** [reference_clock_counter.sv](../../components/library/reference_clock_counter.sv)


**Verification expectation.** Test reset and monotonic increment. Not separately behaviorally tested.

**Unimplemented or unidentified.** Memory-clock domains and cross-domain transfer rules are missing. The reference is a reporting convention; it does not identify intrinsic response timing.

### Implementation 58: Effective dependent-operation replay

**Purpose and measurement boundary.** The [dependency replay](../../numerical/dependency_probe_replay.sv) executes actual repeated MOVM transformations or scalar shared-memory pointer reads with a configured successive-dependency spacing. It makes measured effective cost executable without interpreting that cost as intrinsic hardware latency. The saved MOVM observation is 29,684 net cycles/1,024 operations = 28.98828125 cycles per operation, rounded to 29. It includes loop/timer work, and `end_timer_waits_final_result = false`: the timer does not await the final result. Using a 29-cycle result return to enable the next dependent issue is therefore a calibration convention, not identified final-return latency or exact reproduction of the historical timer interval. Scalar shared loads use a 28-cycle effective recurrence including return, wakeup, issue and native-control effects. Neither value identifies independent throughput.

| Interface or parameter | Contract |
|---|---|
| Launch | Valid/ready, 32-bit ID, two-bit opcode and 32 input words or byte addresses; opcode zero MOVM, one LDS |
| Shared writes | Aligned 32-bit words into an initialized 32 KiB array, only while IDLE |
| Result | 32 actual transformed/read words and retained ID, held until acknowledgment |
| Trace | Actual operation admission pulse, ordinal and opcode |
| Defaults | 1,024 operations; MOVM recurrence 29 and LDS recurrence 28 model cycles |
| Timing mode | Effective mode zero only; nonzero extra issue/wakeup/cache costs are rejected |

Acceptance captures inputs and enters RUN. The first operation issues on the following edge. Each actual return updates the chain values; direct forwarding permits the next admission on that same return edge. MOVM uses the measured word transformation, while LDS reads actual initialized words and uses their values as future byte addresses. All 32 LDS addresses must be aligned, in range and mapped to distinct banks. The model excludes conflicting/multiwarp/global/cache paths. Launch and shared write cannot share an edge. The last actual return enters DONE; elapsed cycles then freeze while completion is held. Reset clears state and initialization.

For N operations and recurrence R, first-to-last admission spans `(N − 1) × R`, first admission to final return spans `N × R`, and accepted launch to registered DONE spans `1 + N × R`. These are explicit simulator edges, not the historical probe's timer endpoints:

| Operation/count | First-to-last admission | First-to-final return | Launch-to-DONE |
|---|---:|---:|---:|
| MOVM / 37 | 1,044 | 1,073 | 1,074 |
| LDS / 37 | 1,008 | 1,036 | 1,037 |
| MOVM / 1,024 | 29,667 | 29,696 | 29,697 |
| LDS / 1,024 | 28,644 | 28,672 | 28,673 |

The [replay receipt](../../numerical/dependency_probe_verification.json) checks 128 output words across these cases with an independent repeated coordinate-transpose oracle and a 32-address pointer ring. Unsupported timing mode and double charging are rejected. This validates implementation of the configured recurrence, not independent hardware timing. In particular, 29,696 final-return cycles must not be compared directly with the 29,684 historical net timer count as matching endpoints. The 0.01171875-cycle rounding difference per MOVM operation is approximately 0.0404% of its measured average; that is rounding error, not GEMM prediction error.

Effective costs cannot be charged again as intrinsic service latency plus separate included overhead. Their transfer to GEMM remains unvalidated because scheduling, dependencies and competition differ. The separate phase-composition model’s largest recorded error remains 5.966342%; physical counts remain eight identified, 32 partial and 94 unknown. No new hardware evidence is added by this replay.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_dependency_probe_replay.py`.

**Inline behavior.**


**Source implementation:** [dependency_probe_replay.sv](../../numerical/dependency_probe_replay.sv)

### C++ component adapters

- [timed_queue](../../cpp/timed_queue.hpp) — adapter for [the matching Verilog source](../../components/library/timed_queue.sv).
- [reference_clock_counter](../../cpp/reference_clock_counter.hpp) — adapter for [the matching Verilog source](../../components/library/reference_clock_counter.sv).
- [dependency_probe_replay](../../cpp/dependency_probe_replay.hpp) — adapter for [the matching Verilog source](../../numerical/dependency_probe_replay.sv).

## 9. Verification and evidence

Retain the verification expectations and existing receipts in Section 8. The [integration and verification chapter](../integration_and_verification.md) separates existing numerical tests, new C++ smoke tests and GPU measurements. The most recent connected-grid receipt checks 24,576 output words; it does not calibrate the integrated cycle count.

## 10. Optimization implications and remaining gaps

Record elapsed model cycles and hardware time separately. The phase estimator within 5% on two new workloads is not validation of the integrated Verilog cycle count.

A parameter checked through documentation or a transferred prior can be used provisionally. Refine it when a new end-to-end case disagrees materially or when it changes the optimization choice. Do not spend time recovering a private property that the supported execution path does not exercise.
