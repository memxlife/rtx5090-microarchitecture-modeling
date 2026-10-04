# 05. Scalar and address execution

[System specification and chapter index](../../rtl_microarchitecture_spec.md) · [Approved manual structure](../../hardware_manual_structure.md)

## 1. Purpose and boundary

This chapter defines the boundary for scalar arithmetic, address generation and control execution. The primitive implementation transports operation identities through a timing queue; it does not compute a complete CUDA scalar instruction set.

This is a specification of the executable reconstruction. Statements about physical RTX 5090 hardware retain their source or measurement scope; helper defaults describe model configurations.

## 2. Quantitative parameters

The table assigns this chapter ownership of the following inventory entries. “Baseline” preserves the existing setting; the evidence check may instead support a scoped alternative. Source priors are usable provisional estimates, not measurements of a private circuit.

| ID | Definition | Baseline | Unit | Recorded basis | Initial check |
|---|---|---|---|---|---|
| F027 | The number of execution pipelines available for each instruction class. | {"FP32_INT32":32,"tensor_blocks":1,"SFU":4,"LSU":4} | logical lanes or blocks per partition | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F028 | The mathematical operation, input format, output format and rounding allowed for each supported instruction. | PTX specified rounding/FTZ; measured BF16 exceptional cases and supported FP32 semantics retained | policy | ENGINEERING_ASSUMPTION | Scoped source or observation |
| F029 | Which instruction classes compete for the same execution resources. | FP32 and INT32 share unified execution capacity; tensor and LSU are independently scheduled logical paths | policy | ENGINEERING_ASSUMPTION | GPU contract or effective path |
| F030 | The structure and count of tensor execution resources, including their partitioning. | 4 | architectural Tensor Core blocks per SM | KNOWN_SOURCE | Previous source or measurement record |
| T014 | Time from accepting an instruction to its result becoming available, by instruction class; existing observations also include dependent scheduling. | Not specified | effective dependent SM cycles | partially_identified | Different-GPU measurement prior |
| T015 | Maximum scalar arithmetic or shuffle results per SM cycle for each supported instruction class; this is distinct from instruction acceptance spacing. | Not specified | maximum scalar results per SM clock cycle | partially_identified | Previous source or measurement record |

Use the [complete parameter table](../../parameter_master_table.md) for values, scope, evidence links and provisional alternatives. Device capacities are centralized in the system specification. Per-module tables below identify which parameters are actually consumed by each implementation.

## 3. Interfaces and transaction ownership

Ready operands → execution acceptance → result completion. Numerical address calculations in the GEMM engines are implemented directly in their control logic; they are not routed through a calibrated scalar pipeline.

The exact port names, directions, widths and acceptance rules are listed in the implementation contracts in Section 8 and their linked sources. A connection must preserve both payload and ownership while stalled. The common system protocol applies unless a module contract explicitly states a pulse-only interface.

## 4. State and storage

Each linked module contract specifies its arrays, counters, masks, pointers or state machine. Those fields belong to that implementation only. A primitive helper is not an additional copy of a hardware resource inside the connected top unless that top instantiates it. Reset removes outstanding model ownership according to the specified contract; physical power-on behavior is outside this model.

## 5. Functional transitions

The primitive accepts a token when its service queue has capacity and its initiation interval permits acceptance. It returns that token after the configured delay. Adding a general scalar unit requires opcode-specific numerical semantics and destination values.

Requests are accepted only when the named receiver permits acceptance. Completion must update the original owner before resources are released. The implementation contracts below describe each state transition and numerical transformation separately.

## 6. Timing and arbitration

Use completion latency, acceptance interval and queue capacity as three distinct quantities: when a result becomes available, how often a new request can start, and how many requests can remain pending. The per-module timing contract gives their actual code meaning.

For a held-response interface, observe a valid response after an edge, hold readiness low for one more edge, and verify that identity and data remain unchanged. Retirement occurs only on a later edge with both valid and ready. A receiver becoming free after an edge does not retroactively accept a request at that edge.

## 7. Invariants and failure handling

Token completion cannot establish arithmetic correctness. Throughput in scalar results per SM cycle is distinct from warp instruction issue interval.

Unsupported configurations must remain explicit. A passing test of a helper establishes its tested model contract, not a GPU-wide hardware policy.

## 8. Linked implementations and detailed contracts

The following contracts retain the quantitative organization, exact interfaces, state transitions and verification scope of the existing implementations. Verilog stays in separate source files. C++ adapters expose the same generated ports and clock behavior; they do not introduce independent timing constants.

### Implementation 6: ALU, operand-preparation, and matrix service

**Role.** This module is instantiated separately for each modeled operation class. It delegates admission, outstanding storage, delay, and return backpressure to the explicit timing queue above. Separate instances avoid assuming every instruction uses one resource.

**Quantitative configuration.** `SLOTS`, `LATENCY`, and `INTERVAL` are explicit configuration fields. The corrected register-resident matrix probe measured approximately 64 cycles per operation per warp at four warps and 128 at eight. Those compound costs are not assigned as this module's intrinsic latency.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| SLOTS | 4 | operations | Positive | Baseline |
| LATENCY | 1 | cycles | Positive | Baseline; native result latency unknown |
| INTERVAL | 1 | cycles/acceptance | Positive | Baseline; native service interval unknown |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| req_valid / req_ready | input / output | Request present / receiver permits acceptance. |
| req_id | input, 32 bits | Operation or transaction identity retained until return. |
| rsp_valid / rsp_ready | output / input | Completed response present / consumer permits retirement. |
| rsp_id | output, 32 bits | Identity of the completed operation or transaction. |

**Interface protocol.** Accepted identity is returned after service timing. Instantiate separately for each declared operation class.

**Stored state.** Inherited from timed_queue; this wrapper adds no state.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| Inherited timed_queue arrays | Configured by SLOTS | Operation storage and completion |

**Reset and cycle transitions.** Reset, accept, initiation spacing, due time and retirement follow timed_queue exactly.

**Invariants and failure handling.** Never reinterpret a completion token as computed arithmetic data. Dependencies and operation-class assignment are supplied upstream.

**Linked behavioral implementation.**


**Source implementation:** [execution_pipeline.sv](../../components/library/execution_pipeline.sv)


**Verification expectation.** Verify each configured instance against latency and service expectations. Wrapper is compiled; class-specific behavior is not separately tested.

**Unimplemented or unidentified.** Functional arithmetic is not performed. Native CUDA/Integer/Tensor pipeline counts, instruction semantics, operand routing, and per-instruction delays are unidentified. This module emits timed completion tokens, not numerical matrix outputs.

### C++ component adapters

- [execution_pipeline](../../cpp/execution_pipeline.hpp) — adapter for [the matching Verilog source](../../components/library/execution_pipeline.sv).

## 9. Verification and evidence

Retain the verification expectations and existing receipts in Section 8. The [integration and verification chapter](../integration_and_verification.md) separates existing numerical tests, new C++ smoke tests and GPU measurements. The most recent connected-grid receipt checks 24,576 output words; it does not calibrate the integrated cycle count.

## 10. Optimization implications and remaining gaps

The optimizer can include scalar service demand only at its documented scope. A fixed kernel path can use measured combined costs; arbitrary scalar instruction mixes require further execution support.

A parameter checked through documentation or a transferred prior can be used provisionally. Refine it when a new end-to-end case disagrees materially or when it changes the optimization choice. Do not spend time recovering a private property that the supported execution path does not exercise.
