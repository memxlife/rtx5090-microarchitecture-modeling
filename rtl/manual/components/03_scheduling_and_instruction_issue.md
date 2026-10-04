# 03. Scheduling and instruction issue

[System specification and chapter index](../../rtl_microarchitecture_spec.md) · [Approved manual structure](../../hardware_manual_structure.md)

## 1. Purpose and boundary

The scheduler chooses an eligible warp. Eligibility means its dependencies are complete and its destination service can accept the operation.

This is a specification of the executable reconstruction. Statements about physical RTX 5090 hardware retain their source or measurement scope; helper defaults describe model configurations.

## 2. Quantitative parameters

The table assigns this chapter ownership of the following inventory entries. “Baseline” preserves the existing setting; the evidence check may instead support a scoped alternative. Source priors are usable provisional estimates, not measurements of a private circuit.

| ID | Definition | Baseline | Unit | Recorded basis | Initial check |
|---|---|---|---|---|---|
| F013 | The number of warp-scheduling partitions within one SM. | 4 | scheduler partitions per SM | KNOWN_SOURCE | Previous source or measurement record |
| F014 | The rule assigning each resident warp to a scheduling partition. | warp_id modulo 4 | partition assignment | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F015 | The number of instruction issue opportunities available together in a scheduling partition. | 1 | instructions per scheduler per SM cycle | KNOWN_SOURCE | Previous source or measurement record |
| F016 | Which instruction classes can issue together and what forbids the combination. | one issue per partition per cycle; mixed classes allowed across partitions subject to resource readiness | policy | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F017 | The rule directing an instruction class to an execution resource. | route by native opcode and generic pointer address window; shared-window LD.E uses shared path | policy | ENGINEERING_ASSUMPTION | Scoped source or observation |
| F018 | The rule choosing among ready warps or instructions competing to issue. | oldest-ready warp per partition with round-robin ties | policy | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F031 | The rule assigning execution work to partitions or units within an SM. | issuing scheduler routes to its partition; shared services arbitrate SM-wide | policy | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| T007 | Minimum spacing between accepted instructions of each class at a scheduler partition; excludes result latency. | Not specified | SM cycles per warp instruction per partition | unidentified | Transferred simulator prior |
| T008 | Time from a required result becoming available to its dependent instruction becoming eligible; excludes the producer’s execution time. | Not specified | SM cycles after result ready | unidentified | Transferred simulator prior |

Use the [complete parameter table](../../parameter_master_table.md) for values, scope, evidence links and provisional alternatives. Device capacities are centralized in the system specification. Per-module tables below identify which parameters are actually consumed by each implementation.

## 3. Interfaces and transaction ownership

Warp eligibility → candidate selection → receiver acceptance → issue gate. The primitive scheduler has one round-robin cursor; the numerical native issue gate enforces class-specific admission. Four documented physical scheduler partitions are not four instantiated recovered schedulers.

The exact port names, directions, widths and acceptance rules are listed in the implementation contracts in Section 8 and their linked sources. A connection must preserve both payload and ownership while stalled. The common system protocol applies unless a module contract explicitly states a pulse-only interface.

## 4. State and storage

Each linked module contract specifies its arrays, counters, masks, pointers or state machine. Those fields belong to that implementation only. A primitive helper is not an additional copy of a hardware resource inside the connected top unless that top instantiates it. Reset removes outstanding model ownership according to the specified contract; physical power-on behavior is outside this model.

## 5. Functional transitions

Selection is combinational. The cursor changes only on accepted issue. Timing gates prevent a native operation from accepting before the configured interval has elapsed; a selected instruction remains pending when its receiver stalls.

Requests are accepted only when the named receiver permits acceptance. Completion must update the original owner before resources are released. The implementation contracts below describe each state transition and numerical transformation separately.

## 6. Timing and arbitration

Use completion latency, acceptance interval and queue capacity as three distinct quantities: when a result becomes available, how often a new request can start, and how many requests can remain pending. The per-module timing contract gives their actual code meaning.

For a held-response interface, observe a valid response after an edge, hold readiness low for one more edge, and verify that identity and data remain unchanged. Retirement occurs only on a later edge with both valid and ready. A receiver becoming free after an edge does not retroactively accept a request at that edge.

## 7. Invariants and failure handling

Selection must never bypass readiness. An initiation interval constrains acceptance spacing; it is not the same quantity as completion latency. The profile and RTL arbitration choices can differ and must be recorded.

Unsupported configurations must remain explicit. A passing test of a helper establishes its tested model contract, not a GPU-wide hardware policy.

## 8. Linked implementations and detailed contracts

The following contracts retain the quantitative organization, exact interfaces, state transitions and verification scope of the existing implementations. Verilog stays in separate source files. C++ adapters expose the same generated ports and clock behavior; they do not introduce independent timing constants.

### Implementation 4: Warp scheduler

**Role.** Scans eligible warps starting at its round-robin cursor. It chooses one candidate, presents its identity, and advances the cursor only when the receiver accepts that candidate. Eligibility must be computed upstream from dependencies and receiver capacity.

**Quantitative configuration.** `WARPS` defaults to four, matching the tested block. The model issues at most one warp instruction each cycle; that is an explicit hypothesis, not an identified hardware issue width.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| WARPS | 4 | candidates | Positive | Tested block width |
| Issue width | 1 | warp instruction/cycle | Receiver must accept selected instruction | Baseline; not recovered hardware width |
| Partition count | 4 | partitions/SM | Instantiate separate scheduler contexts; warp assignment still unknown | Documented RTX whitepaper Figure 5 |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| eligible | input, WARPS bits | One readiness bit per candidate warp. |
| issue_valid / issue_ready | output / input | Selected instruction present / destination accepts issue. |
| issue_warp | output, signed 32-bit index | Index of the selected eligible warp. |

**Interface protocol.** eligible is supplied by the dependency/resource logic. Receiver acceptance authorizes the selected instruction.

**Stored state.** Round-robin cursor; selection is combinational.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| cursor | Signed 32 bits | Next starting candidate |

**Reset and cycle transitions.** Reset sets cursor zero. Scan from the cursor and choose the first eligible warp. Advance cursor only on issue_valid && issue_ready.

**Invariants and failure handling.** Never select an ineligible warp. No issue is valid if eligibility is empty. Cursor is stable during nonacceptance.

**Linked behavioral implementation.**


**Source implementation:** [warp_scheduler.sv](../../components/library/warp_scheduler.sv)


**Verification expectation.** Selection begins at warp zero, then rotates to warp one; holding issue_ready low preserves the cursor. Passed.

**Unimplemented or unidentified.** Four architectural scheduler partitions are documented. Warp assignment, multiple-issue rules, class-specific routing and arbitration policy remain unknown. This single-instance module does not yet implement the four-partition SM.

### Implementation 33: Native instruction admission from decoded controls and actual completions

This component answers a narrow question: may a presented native instruction start now, or must it wait for an earlier operation? The instruction's control bits name the producer groups it must wait for and the groups it allocates. A group is called a *barrier identifier* here. Several operations can share one identifier. The model keeps that identifier busy until every tracked operation assigned to it reports completion.

The [issue gate](../../components/decoded_native_issue_gate.sv) uses the decoded fields from the original GEMM's native instructions and the existing [producer tracker](../../discovery_rounds/native_barrier_015/producer_barrier_tracker.sv). It does not execute instructions. A downstream execution component accepts the admitted operation and later returns matching completion events. The gate never predicts those events from a fixed completion time.

#### Quantitative configuration and control fields

| Parameter or field | Value | Meaning and evidence boundary |
|---|---:|---|
| `MAX_OPS` | 16 by default | Number of operation identities the simulation tracks; not a measured hardware queue depth |
| `TAG_W` | 5 bits by default | Width of an operation identity; only values 0–15 are legal with the default capacity |
| `COUNT_W` | 5 bits by default | Counter width sufficient to represent 0–16 pending producers per group |
| Allocatable barrier identifiers | 0–5 | Six identifiers observed in compiled native controls; not six execution pipelines |
| No-allocation encoding | 7 | The presented instruction allocates no barrier in that namespace |
| Unsupported encoding | 6 | Admission is blocked and an error is recorded |
| Wait mask | 6 bits | Each set bit requires the corresponding read and write producer groups to be empty |
| Encoded issue delay | 0–15 cycles | Native field `high[44:41]`; this model uses an issue spacing of the greater of one and this value |
| Write/read barrier fields | 3 bits each | Native fields `high[48:46]` and `high[51:49]` |
| Group-control flag | 1 bit | Native field `high[45]` is preserved but its scheduling meaning is not implemented |

A zero delay cannot produce two admissions on the same edge because this interface admits at most one instruction per cycle. The one-cycle minimum therefore comes from the interface's width. It does not identify the intrinsic execution initiation interval. Interpreting nonzero encoded delays as issue spacing is the bounded reconstruction used here, rather than a claim about every native scheduler behavior.

#### Interface contract

All signals below use the same clock. Inputs marked as valid must remain stable until their ready signal permits acceptance. `TAG_W` is the configured identity width defined above.

| Signals | Direction | Contract |
|---|---|---|
| `clk`, `reset` | Input | Rising-edge clock and synchronous reset |
| `instr_valid`, `instr_ready` | Input/output | The source offers one instruction; their conjunction accepts it |
| `operation_id[TAG_W-1:0]`, `control` | Input | Accepted identity and decoded control record; both remain stable while held |
| `dispatch_valid`, `dispatch_ready` | Output/input | Admission offered to the execution component; allocation occurs only when both are true |
| `issued` | Output | Acceptance pulse, identical to the dispatch handshake |
| `write_complete_valid`, `write_complete_tag` | Input | An actual result-ready event releases this operation's allocated write barrier |
| `read_complete_valid`, `read_complete_tag` | Input | An actual operands-consumed event releases this operation's allocated read barrier |
| `busy_write_mask`, `busy_read_mask` | Output | Six bits identify producer groups with outstanding operations |
| `cooldown[3:0]` | Output | Remaining cycles of the encoded admission delay |
| `error_sticky` | Output | Invalid identities, unsupported barrier encoding, or unexpected completion events set this flag until reset |

The two completion inputs have no ready signal. The connected execution component must deliver each event once, using an active identity that allocated the corresponding barrier. If an instruction allocated no read barrier, it must not send a read completion to this tracker. One operation can allocate both namespaces and complete them on the same edge. An identity remains unavailable for reuse while either namespace still tracks it.

#### State transitions and cycle ordering

Before each edge, the gate tests the wait mask, both trackers' identity availability, the encoded delay and downstream readiness. It offers dispatch only if all required conditions hold. When accepted, the instruction adds a producer to each allocated group. The same acceptance loads `cooldown` with the encoded delay minus one, or zero when the delay is zero. Each later idle issue edge decrements a nonzero count. For example, an encoded delay of four permits the next admission four edges after the accepted instruction.

Actual completion removes the matching producer. Waiting consumers see the changed group state in the following cycle. There is no same-edge completion bypass or identity reuse. A completion for one identity and an admission using another identity can update together; neither update loses the other. Downstream backpressure allocates no producer and starts no delay.

For example, original GEMM instructions at PCs `0x1370` and `0x1380` both allocate write barrier 5 without waiting for it to become empty. Both may therefore remain outstanding. The instruction at `0x14e0` waits for barrier 5: completing only the first load is insufficient, while completing both makes this modeled dependency ready. This example tests the reconstructed control contract; it does not establish NVIDIA's private counter implementation.

#### Inline behavior model


**Source implementation:** [decoded_native_issue_gate.sv](../../components/decoded_native_issue_gate.sv)


#### Verification and remaining scope

Run `python components/verify_decoded_native_issue_gate.py` from this RTL directory. The [verification receipt](../../components/decoded_native_issue_gate_verification.json) reports 13 passing checks. Five raw instruction records are checked against the original kernel schedule before compilation. Directed cases cover delayed actual returns, multiple producers sharing one barrier, the first completion failing to clear their shared dependency, held dispatch, separate read/write events, simultaneous completion of both namespaces, simultaneous completion and distinct-identity admission, invalid control encoding, and reset.

The gate still lacks opcode execution, implicit register dependencies, branch execution, and a full register scoreboard. Results from instructions with no allocated barrier require another mechanism to represent their dependencies. The wait-mask treatment of both namespaces and the all-producers-complete rule are explicit reconstruction hypotheses. The group-control flag is not acted on. Passing these checks adds an executable admission mechanism; it does not close a complete hardware parameter field or establish GPU runtime accuracy.

### C++ component adapters

- [warp_scheduler](../../cpp/warp_scheduler.hpp) — adapter for [the matching Verilog source](../../components/library/warp_scheduler.sv).
- [decoded_native_issue_gate](../../cpp/decoded_native_issue_gate.hpp) — adapter for [the matching Verilog source](../../components/decoded_native_issue_gate.sv).

## 9. Verification and evidence

Retain the verification expectations and existing receipts in Section 8. The [integration and verification chapter](../integration_and_verification.md) separates existing numerical tests, new C++ smoke tests and GPU measurements. The most recent connected-grid receipt checks 24,576 output words; it does not calibrate the integrated cycle count.

## 10. Optimization implications and remaining gaps

Issue capacity and dependency constraints belong in the MIP. Exact scheduler policy can remain provisional until a hardware mismatch depends on it.

A parameter checked through documentation or a transferred prior can be used provisionally. Refine it when a new end-to-end case disagrees materially or when it changes the optimization choice. Do not spend time recovering a private property that the supported execution path does not exercise.
