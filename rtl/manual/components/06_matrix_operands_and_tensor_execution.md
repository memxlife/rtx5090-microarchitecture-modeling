# 06. Matrix operands and tensor execution

[System specification and chapter index](../../rtl_microarchitecture_spec.md) · [Approved manual structure](../../hardware_manual_structure.md)

## 1. Purpose and boundary

The matrix path transforms lane-organized BF16 operands into FP32 accumulator updates. Operand mapping, request completion, native instruction order and accumulation order all affect its behavior.

This is a specification of the executable reconstruction. Statements about physical RTX 5090 hardware retain their source or measurement scope; helper defaults describe model configurations.

## 2. Quantitative parameters

The table assigns this chapter ownership of the following inventory entries. “Baseline” preserves the existing setting; the evidence check may instead support a scoped alternative. Source priors are usable provisional estimates, not measurements of a private circuit.

| ID | Definition | Baseline | Unit | Recorded basis | Initial check |
|---|---|---|---|---|---|
| F032 | The assignment of each logical matrix element to a lane and native register word. | use measured native_bf16_layout mapping only for supported BF16 m16n16k16 WMMA family | policy | KNOWN_SOURCE | Scoped source or observation |
| F033 | The native instruction sequence implementing one logical matrix operation. | m16n16k16 BF16 WMMA decomposes into two HMMA.16816.F32.BF16 instructions, each covering eight output columns | policy | MEASURED | Scoped source or observation |
| F034 | The order in which products and existing accumulator values are combined. | supported BF16 matrix oracle uses magnitude-aligned truncation before summation for tested cancellation family | policy | ENGINEERING_ASSUMPTION | Scoped source or observation |
| F035 | The output rules for NaNs, infinities, subnormal values, overflow and signed zero. | preserve measured BF16/FP32 subnormals; overflow to infinity; use recorded NaN and zero-times-infinity results | policy | ENGINEERING_ASSUMPTION | Scoped source or observation |
| T016 | Issue-to-next-dependent-issue time for the supported MOVM register permutation; includes scheduling and dependency handling, not just permutation hardware. | Not specified | effective dependent MOVM SM cycles | partially_identified | Previous source or measurement record |
| T017 | Time from an accepted native matrix instruction to its result becoming available; excludes a separately modeled dependent-instruction wakeup. | Not specified | SM cycles for supported HMMA result | unidentified | GPU contract or effective path |
| T018 | Minimum spacing between accepted native matrix instructions on the modeled pipeline; excludes time until their results return. | Not specified | SM cycles per HMMA instruction per partition | unidentified | GPU contract or effective path |
| T019 | Number of matrix result words delivered to destination registers per cycle; excludes matrix-instruction acceptance rate. | Not specified | 32-bit result words per lane per partition per SM cycle | unidentified | GPU contract or effective path |

Use the [complete parameter table](../../parameter_master_table.md) for values, scope, evidence links and provisional alternatives. Device capacities are centralized in the system specification. Per-module tables below identify which parameters are actually consumed by each implementation.

## 3. Interfaces and transaction ownership

Shared-memory completion → MOVM/LDSM operand mapping → native HMMA acceptance → accumulator update. The connected kernel uses the studied native instruction family; generic matrix helpers and library-layout helpers are separate contracts.

The exact port names, directions, widths and acceptance rules are listed in the implementation contracts in Section 8 and their linked sources. A connection must preserve both payload and ownership while stalled. The common system protocol applies unless a module contract explicitly states a pulse-only interface.

## 4. State and storage

Each linked module contract specifies its arrays, counters, masks, pointers or state machine. Those fields belong to that implementation only. A primitive helper is not an additional copy of a hardware resource inside the connected top unless that top instantiates it. Reset removes outstanding model ownership according to the specified contract; physical power-on behavior is outside this model.

## 5. Functional transitions

Operand windows capture completed words before matrix issue. The native operation uses the specified lane/register map and arithmetic mode. Successive reduction stages reuse an accumulator only after its previous producer has completed.

Requests are accepted only when the named receiver permits acceptance. Completion must update the original owner before resources are released. The implementation contracts below describe each state transition and numerical transformation separately.

## 6. Timing and arbitration

Use completion latency, acceptance interval and queue capacity as three distinct quantities: when a result becomes available, how often a new request can start, and how many requests can remain pending. The per-module timing contract gives their actual code meaning.

For a held-response interface, observe a valid response after an edge, hold readiness low for one more edge, and verify that identity and data remain unchanged. Retirement occurs only on a later edge with both valid and ready. A receiver becoming free after an edge does not retroactively accept a request at that edge.

## 7. Invariants and failure handling

No matrix instruction may consume missing operands. Preserve the specified BF16 representation and FP32 accumulation order. The dependency-probe cost includes compiler wait/control effects and is not intrinsic tensor pipeline latency.

Unsupported configurations must remain explicit. A passing test of a helper establishes its tested model contract, not a GPU-wide hardware policy.

## 8. Linked implementations and detailed contracts

The following contracts retain the quantitative organization, exact interfaces, state transitions and verification scope of the existing implementations. Verilog stays in separate source files. C++ adapters expose the same generated ports and clock behavior; they do not introduce independent timing constants.

### Implementation 16: Numerical BF16/FP32 matrix pipeline

**Role.** Accept a row-major 16 × 16 BF16 matrix A, a row-major 16 × 16 BF16 matrix B and a 16 × 16 FP32 accumulator C. Compute C plus the product of A and B. The ARITHMETIC_MODE parameter selects either the older sequential FP32 reference (0) or the experimentally reconstructed aligned-dot candidate (1). The older reference is now falsified for a broader finite input domain: the measured operation preserves the unit in 2^24 + 1 − 2^24, whereas sequential FP32 rounding loses it. Mode 1 fixes this tested failure by aligning contributions before summation; it is not a complete reconstruction of every Tensor Core arithmetic case. Section 4.19 adds the measured lane mapping for one BF16 operation family; bitwise agreement with this arithmetic reference remains unproven for NVIDIA's general Tensor Core accumulation behavior.

**Design specification and parameter restrictions.**

| Field | Implemented value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| Matrix dimensions | 16 × 16 × 16 | rows × columns × reduction elements | Fixed supported operation | Same primitive shape as corrected matrix probe; not a single native-instruction mapping |
| A/B storage at interface | 256 × 16 each | bits | BF16 words, row-major | Explicit operation contract |
| C/result storage at interface | 256 × 32 each | bits | FP32 words, row-major | Explicit operation contract |
| SLOTS | 2 default | operations | Positive | Synthetic capacity; physical matrix queue unknown |
| LATENCY | 17 default | edge intervals | Positive | Synthetic timing; not measured native latency |
| INTERVAL | 3 default | edge intervals/acceptance | Positive | Synthetic timing; not measured native issue interval |
| ARITHMETIC_MODE | 0 default; 1 candidate | Configuration | Only 0 or 1 | 0 preserves old reference; 1 uses measured aligned-dot rule |
| Arithmetic domain | Finite normal values and zero | BF16/FP32 | Reject nonfinite/subnormal operands or results | Candidate hardware validation covers the measured cancellation family; arbitrary finite reductions remain unverified |

**Ports and interface protocol.**

| Signal | Direction and width | Meaning |
|---|---|---|
| clk, rst | Input, 1 bit each | Clock and synchronous reset |
| req_valid, req_ready | Input/output, 1 bit | Accept the complete operand packet at a rising edge |
| req_id | Input, 32 bits | Unique identity while outstanding |
| a_words, b_words | Input, 256 × 16 bits each | Complete row-major A and B matrices |
| accumulator_words | Input, 256 × 32 bits | Initial C values |
| rsp_valid, rsp_ready | Output/input, 1 bit | Retire the complete result packet |
| rsp_id, result_words | Output, 32 bits and 256 × 32 bits | Returned operation identity and numerical results |
| outstanding | Output, signed 32 bits | Accepted operations not yet retired |

The input packet must remain stable while req_valid is asserted and req_ready is low. The output packet is meaningful only while rsp_valid is asserted and remains stable under backpressure. These wide logical ports describe the operation boundary; they do not assert a physical 256-word register-read or writeback capability.

**Stored state and internal storage organization.**

| State | Organization | Function | Reset |
|---|---|---|---|
| results | SLOTS × 256 × 32 bits | Captured arithmetic results | Invalid until accepted work completes |
| ids, due | SLOTS × 32 bits each | Identity and eligibility cycle | Zeroed |
| occupied | SLOTS × 1 bit | Outstanding identity checks | Cleared |
| cycle, head, tail, next_accept, outstanding | Signed 32-bit fields | Clocked FIFO and service admission | Zeroed |

**Reset and cycle transitions.** At request acceptance, calculate the numerical result from the captured packet and store it in a queue slot. Set its due cycle to acceptance cycle plus LATENCY. The result cannot be consumed before that due cycle. Each response retirement releases exactly one FIFO slot. A full queue does not admit a replacement on the same edge that frees its head. Reset discards pending results.

The host evaluates the arithmetic at acceptance through [a simulation-only DPI helper](../../numerical/bf16_reference.cpp). DPI is the simulator interface used to call the C++ arithmetic routine. Numerical computation time on the host is not the modeled hardware duration. Internal multiplier/addition pipeline stages are not represented. This makes the unit useful for numerical integration while leaving its physical implementation and calibration explicit.

**Operation lifecycle and timing.**

| Phase | Trigger | Update | Next phase |
|---|---|---|---|
| Free slot | Packet handshake | Capture identity, evaluate and store results, set due cycle | Pending |
| Pending | Before due cycle or behind earlier result | Hold data; no early return | Pending |
| Head pending | Due cycle reached | Assert response valid | Available |
| Available | Receiver stalled | Preserve identity and all result words | Available |
| Available | Response handshake | Release head and decrement outstanding | Free slot |

LATENCY counts acceptance-to-earliest-response-handshake edge intervals. INTERVAL constrains separate accepted request edges. Capacity and FIFO blocking can increase observed delay; they are not folded into a fitted whole-operation latency. These controls remain synthetic until matched hardware measurements constrain them.

**Invariants and failure handling.** Outstanding count stays between zero and SLOTS. Identities must be unique while pending. Every accepted packet returns once in FIFO order unless reset cancels it. Duplicate pending identities terminate simulation. The arithmetic helper rejects nonfinite/subnormal operands and results, rather than silently claiming unsupported GPU semantics. The model requires bounded runs before signed cycle-counter overflow.

**Linked behavioral implementation.** This module uses simulation-only C++ arithmetic and is not synthesis-qualified.


**Source implementation:** [numerical_matrix_pipeline.sv](../../numerical/numerical_matrix_pipeline.sv)


**Verification expectations.** [The verifier](../../numerical/verify_numerical_matrix.py) constructs identity, zero-product, signed-integer, fractional-rounding, cancellation and varied-exponent cases. Its independent oracle uses exact rational products and additions with explicit nearest-even FP32 rounding. Two synthetic timing configurations run six matrix packets each, checking 3,072 result words bitwise, acceptance intervals, no early completion, queue bounds, FIFO order, stalled response stability and reset. Three expected failures reject duplicate identities, NaN operands and subnormal operands. All five verification cases passed in [the receipt](../../numerical/verification.json). Build logs retain permitted warnings.

**Missing physical parameters.** Native lane/register layout, instruction decomposition, internal accumulation order, execution partition routing, operand collection, intrinsic result latency, initiation interval and output bandwidth remain unresolved. Full GEMM input staging, barriers, multi-block scheduling and output stores are not supplied by this standalone arithmetic unit.

**Measured arithmetic candidate and validation.** For each output, mode 1 computes the sixteen exact BF16 products in double precision, includes the FP32 input accumulator, and finds the exponent of the largest absolute contribution. Its alignment quantum is two raised to that exponent minus 25. It truncates each signed contribution toward zero to an integer multiple of the quantum, sums those integers, then rounds the resulting value to FP32. The number 25 describes this measured behavioral alignment rule; it does not establish a private accumulator bit width.

The rule was developed from magnitude-gap and signed-small-term probes, then frozen before 162 new hardware cases that vary small products, a small FP32 accumulator, and two separate half-sized products. Every prediction matched. The implemented clocked RTL/DPI candidate reproduces 1,536 saved hardware outputs from six of those cases. Running the older reference against the same expectations produces a preserved numerical failure. NaN and subnormal rejection checks pass in candidate mode. Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_aligned_dot.py`; the receipt is `numerical/aligned_dot_verification.json`. Matrix latency and issue interval remain synthetic.

The validated family contains two opposite power-of-two products plus small products or an initial accumulator. General product distributions, repeated accumulation, exceptional values and other shapes remain unverified. Default mode 0 is retained for earlier reference tests; neither mode should be described as universally hardware-correct.

### Implementation 19: Native BF16 operand adapter

**Role and supported operation.** Connect the register contents recovered on RTX 5090 to the numerical component in Section 4.16. Each of the 32 lanes supplies four packed 32-bit A words, four packed B words and eight FP32 accumulator words. The adapter rearranges these values into row-major matrices and places the returned values in the measured lane/register positions. This covers the CUDA 12.8 sm120 BF16 row-major 16 × 16 × 16 operation. It does not model private register banks or a physical Tensor Core pipeline.

The hardware experiment in `discovery_rounds/functional_mapping_002` observed two HMMA instructions. Each computes a 16 × 8 output half from four A words and two B words per lane. The adapter accepts both halves together. Its single completion therefore represents the operation boundary, rather than independently scheduled native instructions. The official PTX comparison in `discovery_rounds/literature_sweep_009.json` agrees with all 768 measured A/B/C element positions.

**Quantitative parameters and ports.**

| Port or parameter | Direction or value | Meaning and evidence |
|---|---|---|
| clk, rst | Input, 1 bit each | Common model clock and synchronous reset |
| req_valid, req_ready | Input/output, 1 bit each | Whole packet accepted on a rising edge when both are high |
| req_id | Input, 32 bits | Identity unique among outstanding requests |
| a_registers, b_registers | Input, 32 lanes × 4 words × 32 bits each | Two BF16 elements per word; measured native operand contents |
| c_registers | Input, 32 lanes × 8 words × 32 bits | FP32 accumulators in measured result positions |
| rsp_valid, rsp_ready | Output/input, 1 bit each | Whole result retires when both are high at an edge |
| rsp_id | Output, 32 bits | Accepted request identity |
| result_registers | Output, 32 lanes × 8 words × 32 bits | Returned FP32 values in measured positions |
| outstanding | Output, signed 32 bits | Accepted operations not yet retired |
| SLOTS | Default 2 | Positive synthetic queue capacity inherited from Section 4.16 |
| LATENCY, INTERVAL | Defaults 17 and 3 cycles | Positive synthetic completion delay and acceptance interval; uncalibrated |

**Storage, transition and timing contract.** The adapter itself has no stored state. Its wiring is combinational; the matrix component owns the queue and captures the entire input at acceptance. Inputs must remain stable while a valid request waits. Returned words and identity remain stable while a valid response waits. Reset clears the downstream queue, so neither request acceptance nor response validity is asserted during reset. No additional cycle is charged for rearrangement. Physical operand delivery and native issue timing remain unknown.

For example, lane 0's first packed A word contains row 0, columns 0 and 1. Its second A word contains row 8, columns 0 and 1. Its first B word contains rows 0 and 1, column 0. The first returned FP32 word is row 0, column 0. These mappings describe values; they do not imply that NVIDIA physically routes all words in one cycle.

**Inline behavior.** The package below defines the recovered positions. Element indices identify row-major matrix words; the index is sixteen times the row plus the column.


**Source implementation:** [native_bf16_layout.sv](../../discovery_rounds/functional_mapping_002/native_bf16_layout.sv)


The adapter connects those positions to the arithmetic component.


**Source implementation:** [native_bf16_adapter.sv](../../numerical/native_bf16_adapter.sv)


**Verification and remaining gaps.** Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_native_matrix.py` from the project root. Six matrix patterns run under two synthetic timing configurations. The test uses the saved hardware position tables independently of the package formulas and compares 3,072 output words with an exact rational arithmetic oracle. It also checks queue bounds, identity, stalled-response values, minimum configured delay, reset and duplicate-identity rejection. The receipt is `numerical/native_matrix_verification.json`.

The default numerical oracle still uses sequential FP32 fused multiply-add. ARITHMETIC_MODE=1 propagates to the measured aligned-dot candidate; see Section 4.16 for its supported domain and counterexample. Successful tests establish the adapter's connection to that reference, rather than hardware equivalence for arbitrary floating-point inputs. Other shapes, numerical formats, layouts, physical operand queues and separate HMMA completions remain unsupported. These results strengthen F032 and F033 without closing either broad parameter field.

### Implementation 21: Clocked shared storage connected to matrix execution

**Role and connections.** This subsystem connects stored BF16 values to the measured normal and transposed LDSM x4 operand maps, then to Section 4.19's numerical adapter. Shared writes initialize actual words. A matrix request waits until every word referenced by its row addresses is initialized. Once accepted, the numerical component captures the operands, so subsequent writes cannot change the in-flight result. This closes a value-delivery connection; it does not implement the complete instruction, cache, barrier or block-dispatch path.

The input supplies 32 row addresses for A and 32 for B. Each address points to eight contiguous 16-bit values and must be divisible by 16. A uses the normal shared-to-register map; B uses its transposed form. All 32 lanes participate. Reversed, swapped and repeated row addresses are supported. The recovered map is backed by 518 hardware cases in `discovery_rounds/ldsm_mapping_003`, not by an assumed general vector-load layout.

**Quantitative configuration.**

| Parameter or structure | Value | Evidence and restriction |
|---|---:|---|
| SHARED_BYTES | 102400 default | Queried maximum shared allocation per SM; a caller selects the modeled region, not an inferred carveout policy |
| Tested regions | 1024 and 102400 bytes | The 1024-byte operand buffers sit at each region's upper boundary; simulation configurations |
| Region restrictions | At least 1024 bytes, multiple of 16 | Explicit model requirement |
| Stored words | SHARED_BYTES / 2 | 16-bit values, each with one initialization bit |
| Logical write interface | 1 halfword per accepted edge | Simulation interface; not a physical shared-bank port count |
| Collective operand read | 256 halfwords for A and 256 for B | Functional value selection; physical service and return delay are not modeled here |
| SLOTS | 2 default | Synthetic matrix queue capacity inherited from Section 4.16 |
| LATENCY, INTERVAL | 17 and 3 cycles default | Synthetic matrix delay and acceptance interval; no LDSM timing has been calibrated |

**Interfaces and admission.**

| Port | Direction and width | Meaning |
|---|---|---|
| clk, rst | Input, 1 bit each | Common clock and synchronous reset |
| write_valid, write_ready | Input/output, 1 bit each | Accept one shared halfword at a rising edge when both are high |
| write_byte_address | Input, 32 bits | Even byte address wholly inside the modeled region |
| write_data | Input, 16 bits | BF16 bits stored at that address |
| req_valid, req_ready | Input/output, 1 bit each | Accept one complete matrix operand/address packet |
| req_id | Input, 32 bits | Unique identity while outstanding |
| a_row_addresses, b_row_addresses | Input, 32 × 32 bits each | Per-lane row pointers; each complete 16-byte row must lie inside the region |
| c_registers | Input, 32 lanes × 8 FP32 words | Initial accumulators in the measured result positions |
| operands_initialized | Output, 1 bit | Every referenced shared halfword has been written since reset |
| addresses_legal | Output, 1 bit | Every row has legal alignment and bounds |
| rsp_valid, rsp_ready | Output/input, 1 bit each | Return and retirement handshake |
| rsp_id, result_registers | Output, 32 bits and 32 × 8 × 32 bits | Captured identity and computed values |
| outstanding | Output, signed 32 bits | Accepted matrix requests not yet retired |

Request addresses, accumulators and identity must remain stable while a valid request waits. The write interface may fill missing operands during that wait. Invalid writes or valid requests with illegal row addresses terminate simulation explicitly. Valid row addresses with uninitialized words instead cause a readiness stall. Duplicate rows are legal reads. A valid stalled result keeps its identity and values stable.

**State, reset and simultaneous events.** The subsystem stores halfwords and initialization bits. Reset clears the bits and the downstream matrix queue; memory bits themselves need not be zeroed because unwritten values cannot be consumed. Combinational address selection produces packed operand words from the pre-edge storage. The downstream component owns accepted work and numerical result storage.

A same-edge write does not bypass storage. Suppose one referenced word is missing before edge E. The matrix request is not accepted at E, even if the write at E initializes that word. The new value is available after E, so the request may be accepted at E+1 if the matrix queue allows it. If an already initialized word is overwritten at an acceptance edge, the captured operand uses its pre-edge value. These are explicit simulation ordering rules, not measurements of an RTX bypass path.

No extra physical delay is assigned to LDSM selection. Its separate request queue, bank service, return timing and native completion remain missing. The shared service-work decoder in Section 4.20 applies to ordinary LDS128 broadcasts and must not be substituted for LDSM.

**Inline functional address map.**


**Source implementation:** [ldsm_x4_layout.sv](../../discovery_rounds/ldsm_mapping_003/ldsm_x4_layout.sv)


**Inline connected behavior.**


**Source implementation:** [shared_matrix_pipeline.sv](../../numerical/shared_matrix_pipeline.sv)


**Verification and remaining gaps.** Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_shared_matrix.py`. Six arithmetic patterns each use four row-address arrangements under two synthetic timing configurations and two storage capacities, for 72 operations and 18,432 checked FP32 outputs. The test places the buffers against the upper address boundary, keeps a genuinely referenced word until the final write, checks that issue waits, overwrites an operand after acceptance, holds the result response, retires it, and resets storage validity. Three negative cases reject odd write addresses, unaligned rows and out-of-range rows. Evidence and source hashes are in `numerical/shared_matrix_verification.json`.

An initial test incorrectly required unrelated words to be initialized before a repeated-row request could proceed. The corrected test delays a word actually referenced by that request; the model's readiness rule did not change. This failure is preserved in `numerical/shared_initial_test_failure.json`.

ARITHMETIC_MODE propagates through shared storage and native operand mapping to the numerical component. Existing integration checks use mode 0; separate mode-1 checks match saved hardware results for the cancellation family. Full arbitrary-input arithmetic remains unresolved. These checks establish connected reference execution and the measured value map, rather than independent RTX timing accuracy. Global-memory input/output, register allocation and operand collection, instruction scheduling, separate native matrix completions, barriers, caches, shared-bank contention and multi-block execution still need integration.

### Implementation 22: Supported native LDSM descriptor decoder

**Role and connections.** This combinational decoder takes the two 64-bit words of a native instruction and exposes the register-direct shared matrix-load descriptor. It does not fetch instructions, track a program counter or issue a load. The downstream instruction controller must enforce active-lane and readiness conditions before accepting the decoded request.

| Port | Direction and width | Meaning |
|---|---|---|
| low_word, high_word | Input, 64 bits each | Native instruction encoding |
| supported | Output, 1 bit | Descriptor lies within the implemented subset |
| transpose | Output, 1 bit | Normal or transposed shared-to-register map |
| register_words | Output, 3 bits | One, two or four destination words per lane |
| destination_register, address_register | Output, 8 bits each | Destination base and shared-address register numbers |

**Functional rule.** The low 16-bit signature is `0x783b`; destination and address registers occupy low-word bits 23:16 and 31:24. High-word bits 9:8 encode one, two or four destination words, and bit 14 selects transpose. Other admitted formatting bits must match the inline mask. Register 255 is not a legal address register here, and the destination span cannot extend into it. Eight observed encodings verify these fields. Scheduling-control bits are not interpreted. This does not establish a complete decoder for all combinations that the mask would admit.

**State and timing.** There is no stored state, clock, reset or handshake. Outputs recompute from input bits. No physical decode delay is assigned. Treat `supported=0` as rejection rather than an operation with zero latency. Predicated forms, address offsets, other opcodes and full scheduling controls remain unsupported.

**Inline behavior.**


**Source implementation:** [native_ldsm_decode.sv](../../components/native_ldsm_decode.sv)


**Verification.** `python studies/rtx5090_gemm_milp/rtl/components/verify_native_ldsm_decode.py` checks eight measured descriptors and five unsupported controls. Source hashes and exact encodings are preserved in `components/native_ldsm_decode_verification.json`. F010 is partially identified; neither physical decode delay nor the complete instruction vocabulary is established.

### Implementation 23: LDSM shared service-work decoder

**Role and connections.** This combinational block calculates the shared-memory work of an aligned all-lane native LDSM request. It receives row addresses and the number of matrices, and supplies a work count to a future clocked shared service controller. It is separate from value mapping in Section 4.21. An address group cannot be replaced by a generic LDS128 broadcast rule.

| Port | Direction and width | Meaning |
|---|---|---|
| row_byte_addresses | Input, 32 × 32 bits | Shared byte address supplied by each lane |
| matrix_count | Input, 3 bits | One, two or four matrices |
| request_legal | Output, 1 bit | Supported matrix count and 16-byte alignment |
| service_packages | Output, 6 bits | Sum of group service work, at most 32 |

**Functional rule and state.** Each active group has eight provider lanes. Equal row addresses within a group merge. Address bits 6:4 identify a bank quartet; count distinct rows in each quartet and use the maximum count as that group’s work. Sum the work of the first one, two or four groups. Equal addresses in different groups remain separate. The block has no stored state, reset or arbitration. It does not validate shared capacity or partial-lane legality; callers must supply those checks.

**Timing meaning.** The work count is not an intrinsic result latency. In the measured single-warp x4 load-and-sum loop, an extra package adds two SM cycles relative to the four-package case. Six fresh timing predictions match this incremental rule. The baseline includes consuming arithmetic and loop scheduling. Independent issue rate, queue depth, cross-warp contention and base return delay remain unknown. Do not apply the two-cycle increment to a GEMM unless its relevant execution path has been verified.

**Inline behavior.**


**Source implementation:** [ldsm_service_work.sv](../../components/ldsm_service_work.sv)


**Verification and transfer limits.** `python studies/rtx5090_gemm_milp/rtl/components/verify_ldsm_service_work.py` checks the 24 original measured configurations and invalid alignment/count controls. Hardware confirmation adds six new address cases, and six additional untouched timing cases verify the incremental delay. The confirmation evidence supports duplicate-row merging within a group; the original component receipt predates that confirmation. These narrow results strengthen F052 and partially identify T020. They do not establish intrinsic shared-bank ports or a full-chip timing model.

### Implementation 28: Compiled-library shared-address layout package

**Purpose and evidence boundary.** The [library shared layout package](../../numerical/library_shared_layout.sv) implements the reconstructed software address rules of the selected non-transposed library kernel family. It is separate from the LDSM-based tile controller in section 4.27. These rules describe where compiled code puts operands, not GPU memory capacity, physical bank organization or instruction latency. The actual library input path uses scalar generic `LD.E` reads and register rearrangement; this package alone does not execute that instruction schedule.

**Constants and index domains.** The reconstructed shared footprint is 37,376 bytes. A has 32 rows with 528-byte pitch; B has 128 rows with 80-byte pitch. B begins at byte 16,896 and its second slot adds 10,240 bytes. Both pitches contain 16 bytes of row padding. The two A slots instead differ by 256 bytes inside the packed row. Each stage has eight matrix reduction steps of 16 elements. Producer thread IDs range from zero to 127; slot IDs are zero or one; producer group IDs are zero to three. Consumer warp IDs are zero to three, lanes zero to 31, reduction-step IDs zero to seven and word IDs zero to three. Invalid indices cause a fatal error.

| Function | Returned value |
|---|---|
| `producer_a(thread_id, slot, group_id)` | Shared byte address of a thread's 16-byte A producer fragment |
| `producer_b(thread_id, slot, group_id)` | Shared byte address of its 16-byte B producer fragment |
| `consumer_a(warp_id, lane, slot, kstep, word_id)` | Shared byte address of one scalar four-byte A consumer word |
| `consumer_b(warp_id, lane, slot, kstep, word_id)` | Shared byte address of one scalar four-byte B consumer word before the separately modeled register permutation |

**Behavior and timing.** These are deterministic integer address functions. They store no state and perform no ready/valid transaction. Evaluating a function does not assign physical address-generation latency. A native instruction model must charge the compiled arithmetic, dependency and memory-service work at its own boundaries, rather than treating these functions as a measured zero-cycle GPU instruction.

**Verification status.** The [verification receipt](../../numerical/library_shared_layout_verification.json) passes 18,432 address comparisons against the reconstructed Python layout and rejects an invalid index. Both source hashes match the verified files. This validates the ported software functions; it does not establish dynamic native execution timing or a complete library kernel model. The separately extracted [static native operand schedule](../../discovery_rounds/compiled_operand_schedule.json) contains 333 instructions, including 72 `LD.E`, 36 `MOVM` and 16 `HMMA` instructions. Its dynamic loop replay remains incomplete because pointer and control dependencies are unresolved.

**Authoritative behavioral implementation.** The following source is copied exactly from `numerical/library_shared_layout.sv`.


**Source implementation:** [library_shared_layout.sv](../../numerical/library_shared_layout.sv)

### Implementation 29: Selected-library generic shared operands and measured register permutation

**Purpose and distinction from section 4.26.** The [generic matrix pipeline](../../numerical/library_generic_matrix_pipeline.sv) replaces the earlier LDSM operand path with the selected library's scalar shared-word addresses and measured `MOVM` halfword permutation. It stores actual BF16 values, gathers A and B operands, and passes them to the existing numerical matrix adapter. This corrects a functional input-path mismatch. It does not reproduce the native instructions' issue timing: the scalar reads are modeled as one ideal collective snapshot, and the permutation is an ideal function.

**Storage and request fields.** Shared storage defaults to 37,376 bytes, the reconstructed software footprint from section 4.28. Each write supplies a two-byte-aligned 16-bit value. Each matrix request contains a 32-bit ID, two-bit warp ID, one-bit slot ID, three-bit reduction-step ID, and 32 × 8 FP32 accumulator words. Warp IDs zero to three select four 16 × 16 output tiles: row half is `warp_id modulo 2`, and column half is `floor(warp_id/2)`. Each of two slots contains eight steps of 16 reduction elements, giving 256 reduction elements across both slots. A request returns 32 × 8 FP32 words in the supported native accumulator layout.

The defaults are two numerical request slots, a 16-cycle numerical delay, a four-cycle issue interval and arithmetic mode one. Delay and issue interval are synthetic. The shared read and register permutation have no separately calibrated latency, bandwidth limit, queue or arbitration here. Their omission must remain visible when comparing this model with GPU time.

**Operand construction.** For each of 32 lanes and four packed words, the pipeline evaluates `consumer_a` and `consumer_b` from section 4.28. Each word reads two adjacent BF16 halfwords. A is packed directly. B first creates a 256-halfword raw vector, indexed by `8 × lane + 2 × word + halfword`. The measured permutation maps each destination halfword after `MOVM` to its raw source index before `MOVM`. The destination values are then packed into four 32-bit B registers per lane. The 256-entry table is a bijection and matches the saved measured mapping exactly.

**Interfaces and clocked state.** Write and matrix interfaces use ready/valid acceptance at the clock edge. A matrix request is ready only when every referenced halfword is initialized, every address is legal, reset is inactive and the numerical child can accept it. That child snapshots A, B and C on acceptance. Later shared writes therefore do not change an in-flight computation. A same-edge write uses pre-edge storage; the final initializing write cannot enable admission until a later edge. Result IDs and values remain held while the consumer applies backpressure. Reset invalidates shared initialization and cancels pending numerical results. Memory payload bits need not be cleared because invalid words cannot supply accepted operands.

**Independent verification.** The [generic-path receipt](../../numerical/library_generic_matrix_verification.json) passes 66,048 FP32 output comparisons under two synthetic timing configurations: delay/interval 16/4 and 37/9 cycles. Each configuration checks 129 operations. Ordinary matrix multiplication supplies expectations independently of the consumer-address and permutation implementation. Four warp tiles and 16 reduction steps assemble a 32 × 32 output with reduction length 256. Fixtures use small integer BF16 inputs and exact FP32 sums; this is not a test of general NVIDIA rounding behavior. Protocol checks cover a missing final operand delaying admission, request IDs, accepted snapshots surviving shared overwrite, held outputs, carried accumulation and reset cancellation. An odd-byte shared write is rejected. Receipt source hashes match the verified files.

The scalar shared-read and `MOVM` **functional value path** is now connected to numerical accumulation. Global staging/cache delivery, output stores and native multiwarp scheduling are not connected to this adapter. No new physical parameter identification, GPU measurement or timing calibration follows from these local checks.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_library_generic_matrix.py` from the project root.

**Authoritative library address wrapper.** The shared storage, readiness and numerical snapshot now live in the common explicit-address module; this wrapper supplies the padded compiled-library addresses.


**Source implementation:** [library_generic_matrix_pipeline.sv](../../numerical/library_generic_matrix_pipeline.sv)


**Authoritative common generic shared-word module.** This module accepts 32 × 4 explicit byte addresses for each operand. The library wrapper and original studied-kernel wrapper share its initialization, address checks, measured permutation and numerical snapshot behavior.


**Source implementation:** [generic_shared_matrix_pipeline.sv](../../numerical/generic_shared_matrix_pipeline.sv)


**Authoritative measured permutation package.** The literal table preserves the measured mapping without assuming an undocumented hardware transpose network.


**Source implementation:** [library_movm_permutation.sv](../../numerical/library_movm_permutation.sv)

### Implementation 30: Original studied-GEMM shared operands and full reduction values

**Question and concrete target.** Does the original kernel that produced the largest model error deliver the correct matrix operands through its own generic shared-load path? The [studied wrapper](../../numerical/studied_gemm_matrix_pipeline.sv) reconstructs that path from [diagnostic 050 source](../../../diagnostic_050/gemm_checked.cu), rather than borrowing the padded cuBLASLt layout. Both use scalar generic shared reads and `MOVM`, but their shared addresses differ. This distinction matters: correct arithmetic with the wrong operand layout would not reproduce the workload being modeled.

**Geometry and storage.** `BM` and `BN` are the output-block row and column counts; `BK` is the reduction width held in one shared stage. Defaults are 32, 32 and 32. A occupies `2 × BM × BK` bytes, stored without row padding. B follows A and occupies `2 × BK × BN` bytes, also without padding. Shared operand storage is therefore 4,096 bytes for 32 × 32 output blocks and 7,168 bytes for 64 × 48 blocks at `BK = 32`. This is operand storage only; it excludes the original kernel's additional output scratch and does not establish total CTA allocation.

Each request selects one 16 × 16 fragment using `tile_index` and one 16-element reduction slice using `k_step`. There are `(BM/16) × (BN/16)` fragment tiles and `BK/16` slices. Fragment tiles are enumerated by output row first, with the column varying inside a row. Tile and reduction indices are checked before acceptance. `BM`, `BN` and `BK` must be positive multiples of 16; storage must fit the two operands. The wrapper computes explicit scalar word addresses and delegates actual value reads, measured `MOVM` permutation, initialization, result IDs and snapshot/reset behavior to the common module in section 4.29. Its default `TIMED_READS = 0` retains that path; selecting `TIMED_READS = 1` uses the completion-driven service wrapper in section 4.32. Read slots, package interval and return delay remain engineering choices. No LDSM operand path is used.

**Interfaces and timing.** Inputs are halfword shared writes, a ready/valid matrix request with 32-bit ID, tile/reduction indices, and 32 × 8 FP32 accumulator words. Outputs are readiness/initialization flags, held result ID and values, and numerical outstanding-request count. Acceptance snapshots the operands and accumulator. Later shared overwrites do not modify that request. Reset invalidates shared words and cancels numerical results. Defaults remain two numerical slots, synthetic delay/interval 16/4 cycles and the bounded arithmetic candidate. They are not physical generic-load or `MOVM` delays.

**Independent original-workload value checks.** The [verification receipt](../../numerical/studied_gemm_matrix_verification.json) passes **393,216 intermediate FP32 result-word comparisons** through reduction length 1,536. It tests the first CTA, at coordinate (0,0), for both 32 × 32 and 64 × 48 output blocks in the original global shape 2,048 × 2,112 × 1,536. Each has 48 shared stage frames and two 16-element slices per frame. The smaller block checks 384 fragment operations; the larger checks 1,152. These are first-CTA checks, not the entire global matrix output.

Inputs reproduce the original dyadic patterns: A's element at flattened global index `i` is `((i modulo 17) - 8)/16`; B's element is `((i modulo 13) - 6)/16`, using the original global strides. The independent oracle computes integer dot products and divides by 256; it does not call the consumer-address functions. Actual result registers supply each later accumulator. Invalid fragment and reduction indices are rejected for both geometries. All receipt source hashes match the verified files. The refactored library path retains its separate 66,048-word regression checks.

This closes a functional operand/value-path mismatch for the workload that motivated the error investigation. Global cache delivery, staging instructions, native warp scheduling, load/permutation service, barriers, residency and output stores remain unconnected for this wrapper. No hardware runtime prediction has been validated by these local checks. Physical evidence counts remain eight identified, 32 partial and 94 unknown fields.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_studied_gemm_matrix.py` for the untimed path, or add `--timed-reads` for completion-driven scalar reads. Both pass the 393,216-word original-workload checks.

**Authoritative studied-kernel address wrapper.**


**Source implementation:** [studied_gemm_matrix_pipeline.sv](../../numerical/studied_gemm_matrix_pipeline.sv)

### Implementation 32: Generic matrix operands delivered by shared-read completions

**Purpose.** The [timed generic matrix wrapper](../../numerical/timed_generic_shared_matrix_pipeline.sv) connects section 4.31's scalar bank-service events to numerical matrix operands. One external request generates eight full-warp scalar reads: four A word groups, then four B word groups. A numerical operation cannot be admitted merely because its addresses were computed; all eight matching read responses must arrive first.

**Quantitative configuration and interfaces.** Defaults are 4,096 bytes of shared storage, one external matrix request in flight, four shared-read slots, a one-cycle package service interval and one-cycle return delay. The numerical child has two request slots, synthetic latency/interval 16/4 and arithmetic mode one. An external request provides a 32-bit ID, 32 × 4 A byte addresses, 32 × 4 B byte addresses and 32 × 8 accumulator words. Each read-group response carries 32 words and a group ID from zero to seven. Final output has the original request ID and 256 FP32 result words. These quantities describe the model, not discovered silicon capacities.

**Snapshot and completion rules.** On external request acceptance, the wrapper snapshots every address, memory word and accumulator. This early snapshot is an engineering contract: it does not reproduce the memory-read time of each later native instruction or establish the GPU's read/write hazard behavior. Subsequent writes and changes to external addresses/C do not alter saved inputs. Reads are offered to the service queue in group order; capacity can stall admission. Each accepted completion sets one bit in an eight-bit received mask and stores the returned words. Duplicate, unissued or unknown read IDs are rejected. Only a complete mask allows matrix admission. B uses the measured permutation from section 4.29. The final numerical result remains held until acknowledgment, after which the wrapper accepts another external request.

All referenced input halfwords must be initialized and all scalar addresses aligned and in bounds before acceptance. Same-edge writes use pre-edge values. Reset invalidates shared words, cancels read and matrix requests, clears the completion mask and discards the saved external operation. Read-only service does not arbitrate concurrent writes for a physical shared-memory port.

**Verification.** The [timed-wrapper receipt](../../numerical/timed_generic_shared_matrix_verification.json) passes 256 output comparisons against an independent identity-matrix-times-column-values oracle. Checks verify eight actual read responses feeding arithmetic, accepted snapshots surviving intervening shared writes/address/C changes, held numerical output, uninitialized inputs blocking acceptance, and reset invalidation. Receipt hashes match the verified sources. The [timed original-workload receipt](../../numerical/studied_gemm_matrix_timed_verification.json) also passes 393,216 intermediate result-word checks for the first CTA of both original output-block geometries through reduction length 1,536. The untimed baseline separately reruns the same 393,216 checks after the refactor. Thus actual shared-read completions now gate the original workload's numerical accumulation; these synthetic-service tests do not validate hardware time. Generic instruction scheduling, calibrated shared return delay, `MOVM` timing and native queue structure remain absent. Physical evidence counts are unchanged.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_timed_generic_shared_matrix.py` from the project root.

**Authoritative behavioral implementation.**


**Source implementation:** [timed_generic_shared_matrix_pipeline.sv](../../numerical/timed_generic_shared_matrix_pipeline.sv)

### Implementation 35: Numerical service for one supported native HMMA instruction

The original GEMM uses native matrix instructions rather than a single indivisible matrix-multiplication call. This service computes the numerical result of one supported `HMMA.16816.F32.BF16` operation: a 16-row by 8-column output, with 16 products contributing to each output value. BF16 supplies the multiplicands; FP32 supplies the initial and resulting accumulator. The service is a numerical instruction adapter, not a claim about how many physical Tensor Core pipelines execute it.

#### Operand organization and quantitative configuration

Each of the 32 lanes presents four packed 32-bit A words, two packed 32-bit B words, and four FP32 C words. Each packed input word contains two BF16 values. Across lanes these encode the 16 × 16 A operand and one 16 × 8 B column half, together with its 16 × 8 C accumulator. The [measured layout](../../discovery_rounds/functional_mapping_002/analysis.json) defines where each value belongs; the arrays below describe contents rather than physical register-bank routing.

| Parameter or quantity | Default or supported value | Meaning |
|---|---:|---|
| Lanes | 32 | One complete participating warp; partial-lane matrix operations are unsupported |
| A words per lane | 4 | Eight BF16 values |
| B words per lane | 2 | Four BF16 values for the selected output-column half |
| C/D words per lane | 4 | Four FP32 accumulators/results |
| `SLOTS` | 2 | Configured operation-buffer capacity, not a measured physical depth |
| `LATENCY` | 16 cycles | Chosen response delay inherited from the numerical matrix service; not measured HMMA latency |
| `INTERVAL` | 4 cycles | Chosen minimum admission interval; not identified native throughput |
| `ARITHMETIC_MODE` | 1 | Existing magnitude-aligned matrix arithmetic approximation; exceptional and general rounding coverage remain limited |

The adapter supplies B words 0–1 and C words 0–3 to the complete numerical matrix operation, zeros the unused B/C column half, and returns D words 0–3. Each output dot product is independent of the unused columns. To compute the upper half of a full WMMA operation, the caller instead supplies its original B words 2–3 and C words 4–7 through the same small interface, then places the four returned words in full-result slots 4–7. Thus two applications cover the full 16 × 16 output.

#### Interfaces and cycle behavior

| Signals | Direction | Contract |
|---|---|---|
| `clk`, `rst` | Input | Rising-edge clock and synchronous reset |
| `req_valid`, `req_ready` | Input/output | Their conjunction accepts a numerical operation |
| `req_id[31:0]` | Input | Identity preserved until the result is accepted; duplicate live identities are invalid under the underlying numerical service contract |
| `a_registers[32][4]`, `b_registers[32][2]` | Input | Packed BF16 operands, captured on request acceptance |
| `c_registers[32][4]` | Input | FP32 initial accumulator, captured on the same edge |
| `rsp_valid`, `rsp_ready` | Output/input | Their conjunction retires the result |
| `rsp_id[31:0]`, `result_registers[32][4]` | Output | Matching identity and result words; usable when response valid is asserted |
| `outstanding` | Output | Number of buffered operations that have not retired |

Inputs may change after request acceptance. The inherited operation buffer keeps captured values and preserves response order. Backpressure holds the visible response and keeps its buffer occupied. Reset discards pending operations. The configured response delay is a model timing choice; this adapter contains no native issue-control decoder, shared-load service, register-bank arbitration, or physical execution-unit scheduler.

#### Inline behavior model


**Source implementation:** [native_hmma16816_adapter.sv](../../numerical/native_hmma16816_adapter.sv)


#### Verification and limits

Run `python numerical/verify_native_hmma16816.py` from the RTL directory. The [receipt](../../numerical/native_hmma16816_verification.json) reports 512 output comparisons against independent, direct sixteen-term dot products. The inputs are exactly representable fractions with power-of-two denominators, so the reference calculation has no ambiguous rounding in these cases. Four half operations cover lower and upper columns with zero and nonzero initial accumulators. A further 512 comparisons check that the two returned halves equal the complete WMMA adapter's results. Acceptance capture, response backpressure and reset are also exercised.

These cases validate supported numerical contents and the half-operation interface. They do not identify general native accumulation semantics, exceptional-value behavior, physical pipeline count, HMMA latency or initiation interval. The underlying complete matrix oracle is reused internally; native execution resources are not duplicated merely because the source instantiates an adapter.

### Implementation 36: Measured lane-word transformation for one MOVM instruction

The same native GEMM prepares some B operands with `MOVM.16.MT88`. This service accepts one 32-bit word from each of 32 lanes and returns the transformed word for each lane. It moves the two 16-bit halves among lanes according to the supported measured permutation. It performs no arithmetic conversion and does not read shared memory.

#### Mapping and configuration

The literal table in [the permutation package](../../numerical/library_movm_permutation.sv) maps each destination halfword position to its original source position. Its original 256 positions cover four words in every lane. Review of all 256 entries confirms two necessary properties: each mapping preserves the source word number, and the source-lane/source-halfword rule is identical for all four word numbers. A one-word instruction service can therefore use the entries for word zero to transform any selected word in this supported family.

| Parameter or quantity | Default | Meaning and evidence boundary |
|---|---:|---|
| Lanes | 32 | A full collective lane group; inactive-lane masks are not modeled |
| Word width | 32 bits | Two 16-bit halves per lane |
| `SLOTS` | 4 | Configured FIFO capacity; a simulation choice |
| `LATENCY` | 1 cycle | Synthetic return delay; not the measured 29-cycle effective dependent recurrence |
| `INTERVAL` | 1 cycle | Synthetic minimum request spacing; not a private hardware initiation interval |
| Request/response identity | 32 bits | Distinguishes live operations; duplicate live identities are rejected |

The earlier 29-cycle MOVM result is an effective dependent recurrence measured with compiled scheduling controls. It must not be silently substituted for this module's intrinsic latency or added again as a separate dependency delay. Physical latency and service interval remain unseparated. The module permits controlled synthetic timing while preserving the measured value transformation.

#### Interface, storage and transition rules

| Signals | Direction | Contract |
|---|---|---|
| `clk`, `rst` | Input | Rising-edge clock and synchronous reset |
| `req_valid`, `req_ready` | Input/output | Accept one word from every lane when both are asserted |
| `req_id[31:0]`, `input_words[32]` | Input | Identity and captured 32-bit lane values |
| `rsp_valid`, `rsp_ready` | Output/input | Return/retire the oldest accepted operation |
| `rsp_id[31:0]`, `output_words[32]` | Output | Matching identity and transformed words, valid only with `rsp_valid` |
| `outstanding` | Output | Number of occupied FIFO slots |

At acceptance, the service applies the measured permutation and stores the result, identity and synthetic due cycle in the FIFO tail. Each slot stores 32 result words, one identity, one due-cycle counter and an occupied flag. The admission interval determines the next eligible acceptance cycle. The head becomes visible only when its configured due cycle has arrived. A held response remains in the head slot; retirement releases it and advances the head.

Simultaneous acceptance and retirement preserve the outstanding count. A full queue does not accept a replacement on its retirement edge, so reuse waits one cycle. Duplicate identities are checked against pre-edge occupied slots, including an identity being retired on that edge. Reset clears the queue and its cycle state. The signed cycle counter limits the current implementation to short simulation runs; counter wrap is outside the supported contract.

#### Inline behavior model


**Source implementation:** [native_movm_word_pipeline.sv](../../numerical/native_movm_word_pipeline.sv)


#### Verification and limits

Run `python numerical/verify_native_movm_word.py` from the RTL directory. The [receipt](../../numerical/native_movm_word_verification.json) reports 131,840 output-word comparisons using 515 saved GPU mapping cases. Each case supplies four individual word operations. The reference outputs are actual saved post-MOVM BF16 fragments; the raw input words are reconstructed independently from the original coordinate, identity and basis inputs and ordinary load addresses. Two synthetic configurations, latency/interval 1/1 and 7/3, each check 65,920 words. These are local simulations replaying preserved measurements; no new GPU experiment was launched.

The evidence supports the tested finite BF16 lane/register mapping. It does not establish arbitrary exceptional-bit behavior, partial-warp behavior, intrinsic MOVM latency, FIFO capacity, or physical arbitration policy. The response can supply an actual completion event to the issue gate, but connecting these components does not by itself recover the original instruction schedule or GPU runtime.

### Implementation 37: Original operand hot-loop window with decoded native controls

**Purpose and exact boundary.** PC means program counter, the byte address of an instruction inside the compiled function. The [native stage pipeline](../../numerical/native_studied_stage_pipeline.sv) executes the supported operand/value sequence at native addresses `0x1350` through `0x15c0` from the [original kernel schedule](../../discovery_rounds/original_native_schedule/original_kernel_schedule.json). It covers one 16 × 16 output fragment through a 32-element reduction step of the original 32 × 32 block. It is not the complete kernel: instructions before and after this window, branch replay, global-load issue, block scheduling and native address-arithmetic dependencies are absent.

One accepted external request supplies a fragment index zero to three, a 32-bit ID and 32 × 8 initial FP32 accumulators. Shared storage is 4,096 bytes, written through a halfword ready/valid port. All referenced words must be initialized before acceptance. The request computes two 16-element slices and returns 256 FP32 accumulator words. Four native HMMA services perform the lower/upper output halves of each slice; a whole-WMMA delay is not substituted for them.

**Generated instruction descriptors.** `generate_native_studied_stage.py` selects exactly 40 contiguous native instructions from the saved JSON and copies every 128-bit instruction encoding. The decoder from section 4.33 interprets the original wait masks, read/write barrier assignments and issue-delay fields; controls are not hand-retyped. The generated package binds instruction operands to semantic A/B word groups using the saved explicit register operands.

| Window work | Count per fragment step | Numerical action |
|---|---:|---|
| Scalar `LD.E` | 16 | Eight warp words for each of two reduction slices, using original shared offsets |
| `MOVM.16.MT88` | 8 | Four B words per slice, using the measured per-word permutation |
| `HMMA.16816.F32.BF16` | 4 | Lower and upper 16 × 8 results for both slices; actual returned C carries forward |
| Remaining address/control instructions | 12 | Preserve decoded issue controls; no additional numerical result is produced here |

B's second-slice loads occur in the original nonsequential word order 0, 3, 1, 2, interleaved with A loads and address/control instructions. A/B addresses are precomputed from the supported unpadded shared layout. `UMOV`, `IADD.64`, `LEA` and `LEA.HI.X` therefore preserve their controls but do not replay an address ALU or its register dependencies. `WARPSYNC.ALL` represents an already participating full warp in this bounded model; it does not model missing-lane arrivals or CTA barrier machinery. Producer/barrier context before the window is assumed complete at its entry. All saved read-barrier fields inside the window are disabled; the generator rejects a different unsupported contract.

**Actual completion and implicit readiness.** Native issue advances only after the decoded gate and selected service both accept an instruction. Shared reads sample memory at each actual `LD.E` acceptance, rather than snapshotting every value when the external request begins. Writes receive backpressure while a read request is offered, so its addresses and input words stay stable if the read queue is full. Each load completion updates its A or raw-B group. Each MOVM completion updates the transformed B group. Each HMMA completion updates its four C words. Explicit ready flags prevent use before completion even when an instruction has no encoded write barrier.

The semantic group arrays preserve the values required by this specific instruction sequence. They do not reproduce a physical GPR file, register-bank routing or all alias hazards. For example, later MOVM destinations alias registers used earlier for A; earlier HMMA services have already captured those operands. The selected sequence and snapshots make that bounded reuse safe, without claiming a general register model.

A common completion arbiter prioritizes shared reads, then MOVM, then HMMA. It acknowledges only one service response per edge. The same selected handshake commits returned values and emits a write-barrier completion event if that instruction allocated one. Unselected services hold their outputs. This prevents simultaneous returns from losing an event at the issue gate's one-completion interface. At the end of the 40-instruction window, the controller drains all service requests, ready C halves, tracked producers and issue cooldown before exposing the result. A held result blocks a new external operation. Reset invalidates shared words, clears the window and cancels all service/gate state.

**Provisional quantitative choices.** Defaults are four shared-read slots with one-cycle package spacing and one-cycle return delay; four MOVM slots with delay/interval 1/1; and two HMMA slots with delay/interval 16/4. The decoded producer gate holds at most 64 simulation operation tags, using one tag per selected instruction index; that is not a physical queue capacity. These service settings and the all-producers-complete barrier interpretation are hypotheses. The original encoded issue controls are source evidence. Do not add the measured compound MOVM recurrence of about 29 cycles on top of synthetic MOVM latency plus decoded controls: that would combine effective and decomposed costs without a matching calibration experiment.

**Optional vector shared writes.** `ALLOW_WARP_WRITES = 0` disables the added interface for legacy callers. When enabled, `write_warp_valid/write_warp_ready` accepts 32 byte addresses, 32 halfwords and a 32-bit active mask. Every active address must be even and at most 4,094, and active addresses must be distinct. A scalar write offer or held native load offer blocks acceptance. An accepted packet updates all active halfwords on one edge; inactive neighboring halfwords remain unchanged. An empty mask is a no-op. This is an ideal commit interface, not a modeled native shared-store pipeline. The [vector-write receipt](../../numerical/native_studied_stage_warp_write_verification.json) verifies 1,024 numerical outputs and 160 issued instruction addresses after 64 packets initialize all 2,048 halfwords, plus masked-neighbor preservation, scalar priority and invalid alignment/duplicate rejection.

**Independent verification.** The [window receipt](../../numerical/native_studied_stage_verification.json) checks 1,024 output words across all four fragments, with nonzero initial C, against a direct 32-element dot product. It verifies every one of 160 issued instruction addresses in exact native order, initialized-operand gating, held output and reset. Synthetic read-return/MOVM/HMMA delays are 9/19/73 cycles. Deliberately long operation delays exercise explicit completion readiness beyond the encoded instruction spacing; they are not latency estimates.

The [end-to-end native CTA receipt](../../numerical/studied_gemm_cta_native_verification.json) checks another 5,120 final output words through global sector returns, staging, this native operand window, all accumulation and acknowledged stores. Its supported full-reduction case is the first 32 × 32 CTA through K1536. Global loads and fragment scheduling remain serial; the 64 × 48 block continues to use the baseline path. Source hashes match the tested files. No hardware timing comparison or new physical field closure has been made.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_native_studied_stage.py` for the window check and `python studies/rtx5090_gemm_milp/rtl/numerical/verify_studied_gemm_cta.py --native-stage` for integration.

**Authoritative native stage implementation.**


**Source implementation:** [native_studied_stage_pipeline.sv](../../numerical/native_studied_stage_pipeline.sv)


**Generated descriptor package.** The source JSON hash is retained in the generated header and [generation receipt](../../numerical/native_studied_stage_schedule_generation.json).


**Source implementation:** [native_studied_stage_schedule.sv](../../numerical/native_studied_stage_schedule.sv)

### Implementation 40: Four native operand windows sharing finite services

**Question and role.** Can the four fragment warps make progress together while contending for the same modeled shared-read, MOVM and HMMA services? The [multiwarp stage](../../numerical/native_multiwarp_stage_pipeline.sv) replaces four sequential fragment calls with one batch. Each warp retains its own instruction position, operand values, readiness flags and decoded producer tracking. The services are instantiated once for the entire batch. This makes resource contention executable rather than giving every warp an independent copy of each unit.

The default batch has four warps, each with 32 lanes and one 16 × 16 output fragment. Warp indices zero through three select the four quadrants of the original 32 × 32 output block. Each warp executes section 4.37’s 40-instruction window at addresses 0x1350–0x15c0. The batch therefore issues 160 instructions: 64 shared loads, 32 MOVM operations, 16 HMMA operations and 48 control-only instructions. The latter preserve decoded spacing but use precomputed addresses instead of replaying address arithmetic.

| Interface | Payload | Acceptance or completion |
|---|---|---|
| Clock and reset | `clk`, `rst` | Rising-edge updates; reset cancels all warp and service work |
| Scalar shared write | Byte address, 32 bits; data, 16 bits; valid/ready | An aligned address within the 4,096-byte stage is accepted when no read is being issued |
| Optional vector shared write | 32 byte addresses; 32 halfwords; 32-bit mask; valid/ready | Enabled by `ALLOW_WARP_WRITES`; active addresses must be legal and distinct; scalar/read offers take priority |
| Batch request | 32-bit ID; C registers `[WARPS][32][8]`, 32 bits each; valid/ready | Accepted only while idle and all required shared halfwords are initialized |
| Batch result | Retained ID; result registers `[WARPS][32][8]`; valid/ready | Exposed only after all warps and shared services drain; held until accepted |
| Readiness outputs | `operands_initialized`, `addresses_legal`, `outstanding` | Initialization covers every requested fragment; addresses are fixed by the supported geometry; at most one batch is outstanding |
| Per-warp memory/result conditions | `warp_memory_safe` and `warp_drained`, one bit per warp each | Memory-safe requires the bounded instruction window/cooldown and actual shared reads to finish; fully drained additionally requires tracked producers, C readiness and all accepted service requests to finish; reset/new acceptance clears both |
| Issued-instruction trace | Valid, warp index and instruction address | Reports the one actual decoded instruction issued on that edge |

**State and organization.** One shared array stores 2,048 BF16 halfwords, or 4,096 bytes, with one initialization flag per halfword. Each warp has 256 C words and separate A, raw B and transformed B groups. These semantic arrays preserve supported operation values; their size is not a recovered physical register-file capacity. `WARPS = 4` is the default; the implementation accepts one through four, but the recorded checks exercise four. State advances through IDLE, RUN, DRAIN and RESPONSE. Admission captures all initial C values and resets each warp’s instruction position and local readiness. Shared values are sampled at each accepted native load, not copied at batch admission.

**Issue and completion arbitration.** The issue selector scans warps from a rotating starting index. A warp is eligible only when its decoded control gate and operand readiness permit progress, and its destination service can accept the operation. An accepted-minus-retired shared-read counter limits admission and is checked against the shared service’s outstanding count. At most one instruction issues per edge across the batch. After an accepted issue, the starting index moves to the following warp. A stalled warp can therefore yield to another eligible warp, while each warp’s instruction order stays intact. One global issue port and this round-robin policy are development choices, not discovered RTX scheduler topology or throughput.

Requests carry `warp × 40 + instruction_index` as their internal completion ID. The common response arbiter acknowledges at most one result per edge, prioritizing shared reads, then MOVM, then HMMA. That same acknowledged result updates only its owning warp’s semantic values and readiness and reports the corresponding producer completion to that warp’s gate. Other responses remain held. Explicit readiness still handles operations without encoded write barriers. DRAIN waits for every instruction position, producer tracker, cooldown, C half and service queue before presenting the complete batch result. This preserves completion ownership even when several services finish together. Each warp now also tracks accepted-minus-acknowledged service requests and pending instruction identities. A completion must match an accepted operation, and the sum of per-warp live counts must equal the three shared services’ outstanding counts. The registered `warp_drained` bit rises only after its instruction index reaches 40, all decoded producers/cooldowns clear, both C halves are ready and its live count is zero. A separate registered `warp_memory_safe` bit requires the bounded instruction position/cooldown to finish and its accepted shared reads to retire, but does not require independent MOVM/HMMA results to retire. Per-warp read counts are checked against the shared service’s total count. Register-result readiness and memory-reuse safety are therefore different conditions.

**Quantitative timing choices.** Defaults are one shared-read service with four slots, one-cycle package spacing and one-cycle return delay; one MOVM service with four slots and delay/interval 1/1; and one HMMA service with two slots and delay/interval 16/4. These are model settings. Encoded instruction controls come from the saved compiled kernel; the queue sizes, arbitration, unit timing and producer-wait interpretation remain hypotheses. No compound MOVM recurrence cost is added again on top of decoded controls and service latency.

**Verification and limits.** The [unit receipt](../../numerical/native_multiwarp_stage_verification.json) checks 4,096 output words against an independent direct dot product with nonzero input C. Two tests use shared-read capacities one and two; each test performs two four-warp batches. Across the tests, 16 warp windows issue all 40 instructions in order. At least two warps issue before any finishes its instruction window, confirming modeled overlap rather than four serial copies. Synthetic shared-return/MOVM/HMMA delays of 9/19/73 cycles force readiness waits and finite-service contention. This is functional verification, not a measured GPU timing result.

`MULTIWARP_NATIVE_STAGE = 1` selects this batch in the CTA controller. It requires the native BM32/BN32/BK32 geometry. A K1536 CTA has 48 batch requests, one after each complete shared stage, rather than 192 single-fragment requests. Input staging, whole-stage replacement and output retirement remain serialized. Missing address-ALU replay, scratch service, actual barrier implementation, multiple CTAs/SMs and physical timing validation remain unchanged.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_native_multiwarp_stage.py` for the component checks. The connected controller command uses `--multiwarp`, which also enables native operand execution and coalesced input/output.

The [connected receipt](../../numerical/studied_gemm_cta_multiwarp_verification.json) then checks 5,120 original first-CTA outputs: two K64 replays at each backing delay of 2 and 13, and one K1536 launch. The full reduction completes 48 accepted batches with all four fragments carried between stages and waits for all 128 output-sector acknowledgments. Its 67,389-cycle execution boundary is accepted launch to observed completion under synthetic settings. Final component and connected receipts use the warning-clean source; the initial numerically correct but warning-bearing build is preserved separately. No physical evidence field is closed by these simulations.

**Inline behavior.**


**Source implementation:** [native_multiwarp_stage_pipeline.sv](../../numerical/native_multiwarp_stage_pipeline.sv)

### Implementation 47: Resident complete reductions from global data to register results

**Role and limit.** The [resident reduction controller](../../numerical/resident_gemm_reduction.sv) connects section 4.46’s actual global-to-shared frames to section 4.44’s shared native stage engine. Two resident contexts can retain different block coordinates, stage positions and accumulators while sharing **one input cache and one read/MOVM/HMMA service set**. Each context carries C through every 32-element stage of K. Its result is four fragments’ register values, not an acknowledged global output matrix. Output scratch, global stores and explicit CTA barrier generations are absent from this path.

| Interface or state | Contract |
|---|---|
| Launch | 32-bit ID, A/B bases and block coordinates; accepted into a free resource slot |
| Result | Context, retained ID and `[4][32][8]` FP32 registers; held until actual result acknowledgment |
| Backing input | Shared completion-driven sector request/return interface |
| Residency | Live block/warp counts; one context uses four warps and the 5,120-register-word/9,216-shared-byte request demand |
| Instruction trace | Actual selected native context/warp/instruction address across the shared engine |

Launch validation rejects odd A/B bases and input allocations extending beyond the 32-bit byte-address space before resource reservation. Admission reserves the context before staging begins and captures its metadata. Each context then progresses through STAGE_SEND, STAGE_WAIT, COMPUTE_SEND, COMPUTE_WAIT and RESULT. Registered round-robin staging/compute owners retain payloads while stalled. A staging completion must match the context and reduction-stage number; it permits compute admission only after actual shared commits. The engine snapshots that context’s carried C at acceptance. An ID-matched actual arithmetic response replaces C and either increments the stage or exposes the final register result.

The next frame in a context is not staged until its prior compute result has returned. This is a conservative whole-stage lifetime rule, not a recovered native barrier protocol. Another context can stage or compute meanwhile, subject to the same shared capacities and arbitration. Defaults are two contexts, M64/N96/K64, shared-read capacity two with return delay nine, MOVM delay/interval 19/1 and HMMA delay/interval 73/4. Those deliberately long service delays exercise ownership/readiness; they are not calibrated RTX latency estimates. K64 uses two stages; K1536 uses 48 per context.

A final result owner is latched and held until acknowledgment. The allocator remains live through all stages and a held result; the active-context count must equal live blocks, with four live warps per context. Result acknowledgment frees this **reduction** allocation. It must not be substituted for full-CTA retirement: the original kernel still owes output scratch, synchronization and acknowledged global stores. Reset cancels contexts, staging, engine and pending provider work; cached backing input is immutable until reset.

The [reduction receipt](../../numerical/resident_reduction_verification.json) checks 4,096 FP32 register values: two distinct 32 × 32 block coordinates at K64 and the same two contexts at K1536, using an independent complete integer-dot-product oracle. The current guarded version also rejects odd-base and allocation-overflow launches. The earlier positive-only receipt is retained in `numerical/failure_receipts/resident_reduction_launch_boundary_001`; it does not prove those admission boundaries. These checks connect returned global values, shared commits, measured operand transformations and all carried reduction stages. Held results and resource counts are checked for stability; this reduction test does not prove new issue progress during that hold. The separate stage-engine test in section 4.44 does prove another context completing while a result is held. They do not validate output-store completion, a complete concurrent grid, multiple SMs or hardware runtime. Physical evidence remains eight identified fields, 32 partial and 94 unknown; no field is closed by this integration.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_resident_gemm_reduction.py`.

**Inline behavior.**


**Source implementation:** [resident_gemm_reduction.sv](../../numerical/resident_gemm_reduction.sv)

### Implementation 49: Resident native stages with externally shared reads

**Role.** The [shared native engine](../../numerical/resident_native_stage_shared.sv) retains the resident execution state from section 4.44 but removes its private shared-read unit. Its native operand reads use section 4.48's candidate/grant interface. One MOVM service and one HMMA service remain inside the engine. With two contexts and four warps per context, eight independent instruction positions share these services; this is a bounded stage model, not a complete concurrent kernel.

| Interface or state | Contract |
|---|---|
| Read preview | One eligible native read ID, 32 byte addresses and 32 current operand words |
| Read grant | Actual common-service acceptance; advances instruction state and allocates pending ownership |
| Read return | ID and 32 words; acknowledgment updates the owning operand registers and readiness |
| Read accounting | `read_client_outstanding` is this engine's hub-client count, not the hub's total across clients |
| Context storage | 4,096 operand bytes per context; separate A/B registers, accumulators, readiness and instruction positions |
| Admission/result | Context and 32-bit operation ID; `[4][32][8]` FP32 register results held until acknowledgment |
| Other services | Defaults: four MOVM slots at delay/interval 1/1; two HMMA slots at 16/4 |
| Local read limit | Default `READ_SLOTS = 4`; this is an engine credit limit, not an additional physical read queue |

Only a granted read produces an accepted-operation record. Completion decodes context, warp, instruction and epoch, rejects stale or unexpected ownership, and updates that operation's actual values. The engine checks that accepted minus retired read credits equal its hub-client count. It also checks per-warp pending counts against the read, MOVM and HMMA service totals. Native register dependencies and decoded instruction controls remain active. Completion arbitration gives read returns priority over MOVM and HMMA, allowing one selected completion to update values and barrier bookkeeping per edge. Ungranted read previews can change as another eligible instruction becomes selected; no operand or instruction state advances merely because a preview was visible.

Scalar and optional vector writes initialize idle context storage. Native reads sample their operand values on actual grant. Registered response ownership keeps a held context result stable while another context can finish. Memory-safe indications remain distinct from complete register/service drain. Reset cancels contexts and pending services; external shared clients must reset consistently with the hub. Epoch tags guard context reuse within the declared bounded instruction window. Address generation outside that window, full CTA barriers, output stores and allocation through complete kernel retirement remain outside this component.

The [shared-engine receipt](../../numerical/resident_shared_stage_verification.json) verifies 8,192 native result words with distinct dyadic inputs and nonzero accumulators across read capacities one and two. It also checks 256 words from a synthetic scratch client using the **same hub service**. The connected tests check context interleaving, another context finishing while a result is held, retained resource allocations, matching retirement and reset/refill. The scratch client is a test participant; this receipt does not validate the separately developed output-scratch component or a complete kernel connecting it. No physical parameter is closed: eight fields remain identified, 32 partial and 94 unknown. All delay, arbitration and credit settings remain uncalibrated model choices.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_resident_native_stage_shared.py`.

**Inline behavior.**


**Source implementation:** [resident_native_stage_shared.sv](../../numerical/resident_native_stage_shared.sv)

### C++ component adapters

- [numerical_matrix_pipeline](../../cpp/numerical_matrix_pipeline.hpp) — adapter for [the matching Verilog source](../../numerical/numerical_matrix_pipeline.sv).
- [native_bf16_adapter](../../cpp/native_bf16_adapter.hpp) — adapter for [the matching Verilog source](../../numerical/native_bf16_adapter.sv).
- [shared_matrix_pipeline](../../cpp/shared_matrix_pipeline.hpp) — adapter for [the matching Verilog source](../../numerical/shared_matrix_pipeline.sv).
- [native_ldsm_decode](../../cpp/native_ldsm_decode.hpp) — adapter for [the matching Verilog source](../../components/native_ldsm_decode.sv).
- [ldsm_service_work](../../cpp/ldsm_service_work.hpp) — adapter for [the matching Verilog source](../../components/ldsm_service_work.sv).
- [library_generic_matrix_pipeline](../../cpp/library_generic_matrix_pipeline.hpp) — adapter for [the matching Verilog source](../../numerical/library_generic_matrix_pipeline.sv).
- [generic_shared_matrix_pipeline](../../cpp/generic_shared_matrix_pipeline.hpp) — adapter for [the matching Verilog source](../../numerical/generic_shared_matrix_pipeline.sv).
- [studied_gemm_matrix_pipeline](../../cpp/studied_gemm_matrix_pipeline.hpp) — adapter for [the matching Verilog source](../../numerical/studied_gemm_matrix_pipeline.sv).
- [timed_generic_shared_matrix_pipeline](../../cpp/timed_generic_shared_matrix_pipeline.hpp) — adapter for [the matching Verilog source](../../numerical/timed_generic_shared_matrix_pipeline.sv).
- [native_hmma16816_adapter](../../cpp/native_hmma16816_adapter.hpp) — adapter for [the matching Verilog source](../../numerical/native_hmma16816_adapter.sv).
- [native_movm_word_pipeline](../../cpp/native_movm_word_pipeline.hpp) — adapter for [the matching Verilog source](../../numerical/native_movm_word_pipeline.sv).
- [native_studied_stage_pipeline](../../cpp/native_studied_stage_pipeline.hpp) — adapter for [the matching Verilog source](../../numerical/native_studied_stage_pipeline.sv).
- [native_multiwarp_stage_pipeline](../../cpp/native_multiwarp_stage_pipeline.hpp) — adapter for [the matching Verilog source](../../numerical/native_multiwarp_stage_pipeline.sv).
- [resident_gemm_reduction](../../cpp/resident_gemm_reduction.hpp) — adapter for [the matching Verilog source](../../numerical/resident_gemm_reduction.sv).
- [resident_native_stage_shared](../../cpp/resident_native_stage_shared.hpp) — adapter for [the matching Verilog source](../../numerical/resident_native_stage_shared.sv).

## 9. Verification and evidence

Retain the verification expectations and existing receipts in Section 8. The [integration and verification chapter](../integration_and_verification.md) separates existing numerical tests, new C++ smoke tests and GPU measurements. The most recent connected-grid receipt checks 24,576 output words; it does not calibrate the integrated cycle count.

## 10. Optimization implications and remaining gaps

Tile shapes, operand layout and stage scheduling are optimization decisions. Native HMMA work and service limits can be represented, but one probe cost cannot be transferred to every matrix instruction family.

A parameter checked through documentation or a transferred prior can be used provisionally. Refine it when a new end-to-end case disagrees materially or when it changes the optimization choice. Do not spend time recovering a private property that the supported execution path does not exercise.
