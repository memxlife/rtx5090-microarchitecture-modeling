# 02. Warp state and instruction supply

[System specification and chapter index](../../rtl_microarchitecture_spec.md) · [Approved manual structure](../../hardware_manual_structure.md)

## 1. Purpose and boundary

A warp context stores where a group of lanes is in its instruction sequence and whether it can proceed. It supplies control state; it does not itself execute an instruction.

This is a specification of the executable reconstruction. Statements about physical RTX 5090 hardware retain their source or measurement scope; helper defaults describe model configurations.

## 2. Quantitative parameters

The table assigns this chapter ownership of the following inventory entries. “Baseline” preserves the existing setting; the evidence check may instead support a scoped alternative. Source priors are usable provisional estimates, not measurements of a private circuit.

| ID | Definition | Baseline | Unit | Recorded basis | Initial check |
|---|---|---|---|---|---|
| F005 | The number of instruction bytes that can remain cached. | 16384 | bytes per partition | ENGINEERING_ASSUMPTION | Scoped source or observation |
| F006 | The number of independently indexed instruction-cache groups. | 64 | sets per partition | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F007 | The number of instruction-cache lines allowed in each indexed group. | 4 | ways | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F008 | The function mapping an instruction address to its cache group and tag. | set=(instruction_byte_address//64)%64; partition-private | policy | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F009 | The rule choosing an instruction-cache line to evict when its group is full. | LRU | replacement policy | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F010 | The interpretation of native instruction bits, operands, predicates and scheduling controls. | use supported native_shared_decode, native_generic_load_decode and native_control_decode modules; unsupported opcodes rejected | policy | MEASURED | Scoped source or observation |
| F011 | How a warp selects active lanes when lanes take different branches. | active-lane mask with per-thread program counter; only enabled lanes execute | policy | ENGINEERING_ASSUMPTION | Scoped source or observation |
| F012 | How lanes rejoin after executing different branch paths. | explicit convergence tokens and active-mask restoration at annotated merge PCs | policy | ENGINEERING_ASSUMPTION | Scoped source or observation |
| T004 | Time from requesting an instruction already in the instruction cache to receiving its bytes; excludes misses and decoding. | Not specified | SM cycles for instruction-cache hit | unidentified | Transferred simulator prior |
| T005 | Number of instruction bytes or native instructions delivered per scheduler partition per cycle; excludes execution throughput. | Not specified | 16-byte native instructions per partition per SM cycle | unidentified | Transferred simulator prior |
| T006 | Time from available instruction bytes to a decoded instruction ready for scheduling; excludes operand waiting. | Not specified | SM cycles | unidentified | Transferred simulator prior |

Use the [complete parameter table](../../parameter_master_table.md) for values, scope, evidence links and provisional alternatives. Device capacities are centralized in the system specification. Per-module tables below identify which parameters are actually consumed by each implementation.

## 3. Interfaces and transaction ownership

Instruction position and barrier state → eligibility inputs. The standalone context is a small instruction-position model; the numerical GEMM engines use specialized stage state machines instead of a general instruction fetch/decode engine.

The exact port names, directions, widths and acceptance rules are listed in the implementation contracts in Section 8 and their linked sources. A connection must preserve both payload and ownership while stalled. The common system protocol applies unless a module contract explicitly states a pulse-only interface.

## 4. State and storage

Each linked module contract specifies its arrays, counters, masks, pointers or state machine. Those fields belong to that implementation only. A primitive helper is not an additional copy of a hardware resource inside the connected top unless that top instantiates it. Reset removes outstanding model ownership according to the specified contract; physical power-on behavior is outside this model.

## 5. Functional transitions

Only accepted issue advances the program counter. An accepted barrier sets a waiting state, release clears it, and end makes termination sticky. A barrier accepted on the same edge as release retains the newly entered wait according to the module priority.

Requests are accepted only when the named receiver permits acceptance. Completion must update the original owner before resources are released. The implementation contracts below describe each state transition and numerical transformation separately.

## 6. Timing and arbitration

Use completion latency, acceptance interval and queue capacity as three distinct quantities: when a result becomes available, how often a new request can start, and how many requests can remain pending. The per-module timing contract gives their actual code meaning.

For a held-response interface, observe a valid response after an edge, hold readiness low for one more edge, and verify that identity and data remain unchanged. Retirement occurs only on a later edge with both valid and ready. A receiver becoming free after an edge does not retroactively accept a request at that edge.

## 7. Invariants and failure handling

A stalled instruction retains its position. No issue may occur after end. Divergence, reconvergence and instruction-cache misses are outside the implemented domain.

Unsupported configurations must remain explicit. A passing test of a helper establishes its tested model contract, not a GPU-wide hardware policy.

## 8. Linked implementations and detailed contracts

The following contracts retain the quantitative organization, exact interfaces, state transitions and verification scope of the existing implementations. Verilog stays in separate source files. C++ adapters expose the same generated ports and clock behavior; they do not introduce independent timing constants.

### Implementation 3: Warp instruction context

**Role.** Stores a program counter and barrier/end state. It advances exactly once for an accepted instruction, stops at a barrier, resumes on release, and stops issuing after end. Instruction storage and decoding are provided by the caller.

**Quantitative configuration.** `DEPTH` is the trace instruction limit, default 256. The test workload has four warps of 32 threads, but this module represents one warp.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| DEPTH | 256 | trace positions | Positive; PC must stay below depth on issue | Baseline |
| pc | 32 | signed bits | Nonnegative legal program position | Interface choice |
| Warp width | 32 | threads | Native lane trace required upstream | Recorded execution structure |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| issue_fire, barrier_instruction, end_instruction | input | Accepted issue pulse and classifications of that instruction. |
| barrier_release | input | Release pulse for this warp’s waiting barrier. |
| pc | output, signed 32-bit index | Index of the next instruction to present. |
| waiting, ended | output, one bit each | Barrier wait and permanent end state. |

**Interface protocol.** issue_fire is the accepted-instruction pulse. The caller must not issue while waiting or ended.

**Stored state.** Program counter, waiting bit, ended bit.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| pc | Signed 32 bits | Next trace instruction |
| waiting / ended | One bit each | Issue inhibition |

**Reset and cycle transitions.** Reset selects instruction zero. Accepted instruction increments the counter; barrier sets waiting and end sets ended. Release clears waiting. The incoming barrier/end classification belongs to that accepted instruction.

**Invariants and failure handling.** Counter advances only on issue_fire. Illegal issue during waiting/end or beyond the configured depth terminates simulation.

**Operation lifecycle.** These state names summarize the register implementation; they are not additional RTL registers.

| Phase | Trigger | Update/output | Next phase |
|---|---|---|---|
| RUN | accepted ordinary instruction | Increment PC | RUN |
| RUN | accepted barrier | Increment PC and set waiting | WAIT_BARRIER |
| WAIT_BARRIER | barrier_release | Clear waiting | RUN |
| RUN | accepted end | Set ended | ENDED |

**Linked behavioral implementation.**


**Source implementation:** [warp_context.sv](../../components/library/warp_context.sv)


**Verification expectation.** Test stalled counter, barrier wait/release, end, and depth overflow. Not behaviorally tested yet.

**Unimplemented or unidentified.** Fetch/cache delays, divergence, reconvergence, native decoding, and the real instruction trace are missing.

### C++ component adapters

- [warp_context](../../cpp/warp_context.hpp) — adapter for [the matching Verilog source](../../components/library/warp_context.sv).

## 9. Verification and evidence

Retain the verification expectations and existing receipts in Section 8. The [integration and verification chapter](../integration_and_verification.md) separates existing numerical tests, new C++ smoke tests and GPU measurements. The most recent connected-grid receipt checks 24,576 output words; it does not calibrate the integrated cycle count.

## 10. Optimization implications and remaining gaps

A kernel schedule needs precedence and active-lane information. A general CUDA program requires additional instruction decoding and control-flow support; the current model covers a fixed GEMM path.

A parameter checked through documentation or a transferred prior can be used provisionally. Refine it when a new end-to-end case disagrees materially or when it changes the optimization choice. Do not spend time recovering a private property that the supported execution path does not exercise.
