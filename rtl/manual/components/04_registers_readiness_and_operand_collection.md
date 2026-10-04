# 04. Registers, readiness, and operand collection

[System specification and chapter index](../../rtl_microarchitecture_spec.md) · [Approved manual structure](../../hardware_manual_structure.md)

## 1. Purpose and boundary

Registers hold values; readiness records whether the most recent producer has completed. Operand collection delivers only defined, completed values to an execution operation.

This is a specification of the executable reconstruction. Statements about physical RTX 5090 hardware retain their source or measurement scope; helper defaults describe model configurations.

## 2. Quantitative parameters

The table assigns this chapter ownership of the following inventory entries. “Baseline” preserves the existing setting; the evidence check may instead support a scoped alternative. Source priors are usable provisional estimates, not measurements of a private circuit.

| ID | Definition | Baseline | Unit | Recorded basis | Initial check |
|---|---|---|---|---|---|
| F019 | The number of independently accessed groups in the register file. | 4 | register banks per partition | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F020 | The function assigning a register and lane to a register-file bank. | register index modulo 4 | bank mapping | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F021 | The number of register values one bank can supply in one service step. | 2 | 32-bit operand words per bank per cycle per lane | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F022 | The number of register values one bank can accept in one service step. | 1 | 32-bit write words per bank per cycle per lane | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F023 | The number of instructions whose operands can wait in operand collectors. | 8 | collector entries per partition | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F024 | The connections and selection rules moving register operands into collectors. | allocate any free collector in opcode class; bank conflicts serialize reads | policy | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F025 | The number of completed results that can wait to write registers. | 8 | writeback entries per partition | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F026 | The rule choosing which waiting result writes the register file next. | oldest completed instruction first; tensor and scalar share final arbitration | policy | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| T009 | Time from an accepted register-read request to its value reaching the operand path; excludes collection of other operands. | Not specified | SM cycles | unidentified | Transferred simulator prior |
| T010 | Time from an accepted register write to the value being stored and visible to later reads; excludes preceding execution. | Not specified | SM cycles | unidentified | Transferred simulator prior |
| T011 | Time to gather all register operands after collection begins, including conflicts; excludes execution of the instruction. | Not specified | SM cycles plus serialized bank conflicts | unidentified | Transferred simulator prior |
| T012 | Additional time to forward a produced value directly to a dependent consumer; excludes ordinary register-file read time. | Not specified | additional SM cycles for supported bypass | unidentified | Transferred simulator prior |
| T013 | Number of destination register vectors committed per scheduler partition per cycle; excludes instruction initiation rate. | Not specified | warp destination register vectors per partition per SM cycle | unidentified | Transferred simulator prior |

Use the [complete parameter table](../../parameter_master_table.md) for values, scope, evidence links and provisional alternatives. Device capacities are centralized in the system specification. Per-module tables below identify which parameters are actually consumed by each implementation.

## 3. Interfaces and transaction ownership

Issue reservation → pending destination → tagged completion → register value → dependent issue. The timestamp scoreboard models deterministic readiness; the completion-based register module stores actual returned values. Neither reconstructs physical register banks.

The exact port names, directions, widths and acceptance rules are listed in the implementation contracts in Section 8 and their linked sources. A connection must preserve both payload and ownership while stalled. The common system protocol applies unless a module contract explicitly states a pulse-only interface.

## 4. State and storage

Each linked module contract specifies its arrays, counters, masks, pointers or state machine. Those fields belong to that implementation only. A primitive helper is not an additional copy of a hardware resource inside the connected top unless that top instantiates it. Reset removes outstanding model ownership according to the specified contract; physical power-on behavior is outside this model.

## 5. Functional transitions

A producer reserves a destination before completion. The timestamp model marks it available at a configured cycle; the completion model waits for its matching return. A consumer must use the version produced by the intended writer, not an earlier value.

Requests are accepted only when the named receiver permits acceptance. Completion must update the original owner before resources are released. The implementation contracts below describe each state transition and numerical transformation separately.

## 6. Timing and arbitration

Use completion latency, acceptance interval and queue capacity as three distinct quantities: when a result becomes available, how often a new request can start, and how many requests can remain pending. The per-module timing contract gives their actual code meaning.

For a held-response interface, observe a valid response after an edge, hold readiness low for one more edge, and verify that identity and data remain unchanged. Retirement occurs only on a later edge with both valid and ready. A receiver becoming free after an edge does not retroactively accept a request at that edge.

## 7. Invariants and failure handling

Undefined source use and overwrite of an unfinished destination are errors. Physical capacity is 65,536 32-bit words per SM; 64 abstract register identities per modeled warp are a separate implementation setting.

Unsupported configurations must remain explicit. A passing test of a helper establishes its tested model contract, not a GPU-wide hardware policy.

## 8. Linked implementations and detailed contracts

The following contracts retain the quantitative organization, exact interfaces, state transitions and verification scope of the existing implementations. Verilog stays in separate source files. C++ adapters expose the same generated ports and clock behavior; they do not introduce independent timing constants.

### Implementation 5: Register readiness scoreboard

**Role.** Maintains when each register identity becomes available. Two optional source checks determine operand readiness. A destination cannot be overwritten while a previous write is pending. Accepted issue reserves its destination until the supplied result delay expires.

**Quantitative configuration.** `REGS` defaults to 64 abstract identities per modeled warp. Register zero starts ready. Queried physical storage is 65,536 32-bit words per SM; the abstract identity count does not model that capacity.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| REGS | 64 | register identities | Source/destination indices in range | Baseline, not physical storage capacity |
| result_delay | Runtime input | cycles | Positive deterministic delay only | Operation-specific hardware value unknown |
| Initially defined register | 0 | register index | Other values require explicit producers | Test initialization convention |
| Register bank/port counts | Unknown | banks/ports | Needed for operand collection | Unidentified |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| source_a, source_b, destination | input, register indices | Register identities queried or reserved. |
| use_a, use_b, write_destination | input, flags | Enable source checks and destination reservation. |
| operands_ready, destination_free | output, flags | Sources available and no conflicting unfinished destination write. |
| issue_fire, result_delay | input | Accepted issue pulse and configured destination-availability delay in cycles. |

**Interface protocol.** Use valid in-range indices. result_delay is positive and deterministic for the accepted operation; the module cannot ingest a variable-latency completion event.

**Stored state.** Cycle counter, defined bit and availability cycle per register identity.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| defined | REGS bits | Whether a producer exists |
| available_at | REGS × signed 32 bits | Result readiness cycle |

**Reset and cycle transitions.** Reset marks only register zero defined. Source queries check definition and due time. An accepted writer marks its destination defined but unavailable until cycle + result_delay.

**Invariants and failure handling.** No accepted instruction reads unavailable sources or overwrites an unfinished destination. Such acceptance terminates simulation.

**Linked behavioral implementation.**


**Source implementation:** [register_scoreboard.sv](../../components/library/register_scoreboard.sv)


**Verification expectation.** Test dependent versus independent operations and overlapping writes in this module. Not behaviorally tested; related checks exist in the older integrated prototype.

**Unimplemented or unidentified.** Banking, physical register values, ports, operand collection, writeback queues, allocation granularity, and variable-latency completion feedback remain missing. Its timestamp result is valid only for the supplied deterministic delay.

### Implementation 15: Completion-driven register storage

**Role.** Store 32-bit values and prevent a dependent instruction from using a destination until its producer actually returns. This is the replacement readiness contract for variable-latency operations. The original timestamp scoreboard remains available for its older deterministic tests; the new path does not consult it.

**Design specification and parameter restrictions.**

| Field | Implemented value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| REGS | 64 default; 8 in connected test | logical registers | At least 2 | Baseline; not physical register allocation |
| Data width | 32 | bits/register | One word per logical identity | Interface choice |
| Read views | 2 | sources | Valid indices when enabled | Baseline; not physical bank ports |
| Reservation/completion width | 32 | bits/identity | Unique among pending destinations | Interface choice |
| Completion inputs | 1 | result/edge | Must match a pending destination and identity | Baseline; physical writeback capacity unknown |
| Return-to-readiness delay | Registered update at completion edge | edge boundary | No same-edge issue bypass | Model rule; physical bypass delay unknown |

**Ports and interface protocol.**

| Signal | Direction and width | Meaning |
|---|---|---|
| clk, rst | Input, 1 bit each | Rising-edge clock, synchronous reset |
| source_a, source_b; use_a, use_b | Input, signed 32-bit indices; 1-bit enables | Select required operands |
| operands_ready; operand_a, operand_b | Output, 1 bit; 32 bits each | Data may be consumed only when all enabled sources are ready |
| reserve_valid, reserve_ready | Input/output, 1 bit | Accept a destination reservation when both are high |
| destination, reservation_id | Input, signed 32-bit index; 32-bit identity | Writable destination and producer identity |
| complete_valid | Input, 1 bit | Actual completion event; upstream arbitration must present at most one |
| complete_destination, complete_id, complete_data | Input, index and two 32-bit values | Destination, matching producer identity and returned data |
| pending_count | Output, signed 32 bits | Number of reserved destinations awaiting completion |

The completion input has no ready signal: every valid legal completion is consumed. A future shared return network must arbitrate and buffer competing producers before this port. Source selection is a combinational read view, not an independent ready/valid request. Its values are meaningful only when operands_ready is true. Downstream execution acceptance and destination reservation must occur atomically; the connected test exercises that obligation.

**Stored state and internal storage organization.**

| Array | Organization | Function | Reset |
|---|---|---|---|
| values | REGS × 32 bits | Actual returned words | Zeroed |
| owners | REGS × 32 bits | Pending producer identity | Zeroed |
| pending | REGS × 1 bit | Prevent early reads/overwrites | Cleared |
| initialized | REGS × 1 bit | Distinguish valid values from absent producers | Only register zero initialized |

Register zero is an immutable zero source in this model. Its identity is a trace convention, not a claim about physical NVIDIA register allocation. Undefined sources remain unready.

**Reset and cycle transitions.** A reservation sets pending and remembers the identity. A legal completion writes data, marks the destination initialized and clears pending. Readiness follows this stored state rather than elapsed time. Concurrent reservation and completion on different destinations are permitted. A destination pending before an edge cannot accept a replacement on its completion edge; a held reservation can enter at the next edge. Reset discards all reservations and nonzero-register validity.

**Operation lifecycle and timing.**

| Phase | Trigger | State/update | Next phase |
|---|---|---|---|
| Undefined/free | Legal reservation handshake | Remember identity; set pending | Pending |
| Ready/free | Legal reservation handshake | Old value becomes unavailable | Pending |
| Pending | No matching completion | Hold identity; dependent instructions stay blocked | Pending |
| Pending | Matching completion at edge k | Store value; clear pending after edge | Ready/free |
| Ready/free | Consumer accepted at edge k+1 or later | Consumer captures value | Ready/free unless reserved again |

A producer may wait arbitrarily long. No result-delay parameter releases its destination. Physical register ports, bypass behavior and bank contention are not identified by this implementation.

**Invariants and failure handling.** A completion must name a writable index, pending reservation and matching identity. Duplicate outstanding identities, stale or duplicate completions, and invalid reservation indices terminate simulation. Pending overwrites are blocked by reserve_ready. Invalid source indices produce unready operands without indexing outside the array. Upstream code must ensure instruction acceptance cannot occur without every required operand and destination reservation. Old completions arriving after reset are invalid; an integrated reset protocol must drain or discard them upstream.

**Linked behavioral implementation.** Simulation contract; synthesis qualification is not established.


**Source implementation:** [completion_register_file.sv](../../components/completion_register_file.sv)


**Verification expectations.** [The connected test](../../components/completion_path_tb.sv) joins timed memory/execution queues to this register file and checks actual data flow through a dependent addition. Three synthetic memory delays (2, 12 and 40 cycles) exercise delayed returns, held results, downstream stalls, concurrent updates and reset. Five rejection cases cover invalid destinations, unreserved returns, wrong identities, duplicate outstanding identities and duplicate completion. All eight cases passed in [the receipt](../../components/completion_verification.json). Integer addition in the test is not BF16 matrix emulation.

**Missing physical parameters.** Register-bank organization, port counts, collector capacity, bypass latency and writeback arbitration remain unknown. Warp-wide values, multiple completion sources and a full native instruction path remain unimplemented. This test establishes a necessary functional rule; it does not reduce or validate RTX runtime prediction error.

### C++ component adapters

- [register_scoreboard](../../cpp/register_scoreboard.hpp) — adapter for [the matching Verilog source](../../components/library/register_scoreboard.sv).
- [completion_register_file](../../cpp/completion_register_file.hpp) — adapter for [the matching Verilog source](../../components/completion_register_file.sv).

## 9. Verification and evidence

Retain the verification expectations and existing receipts in Section 8. The [integration and verification chapter](../integration_and_verification.md) separates existing numerical tests, new C++ smoke tests and GPU measurements. The most recent connected-grid receipt checks 24,576 output words; it does not calibrate the integrated cycle count.

## 10. Optimization implications and remaining gaps

Register demand bounds residency. Dependency edges bound earliest issue. Unknown port conflicts should not be inserted as additional penalties without evidence or combined-path validation.

A parameter checked through documentation or a transferred prior can be used provisionally. Refine it when a new end-to-end case disagrees materially or when it changes the optimization choice. Do not spend time recovering a private property that the supported execution path does not exercise.
