# Component-level functional specification for the RTX 5090 timing-model investigation

The [quantitative specification](quantitative_microarchitecture.md) consolidates capacities, service costs, cycle measurements, and unknown hardware fields.

## 1. What this specification describes

The question is how instructions and data move through hardware to produce GEMM execution time. This document specifies the components needed for that explanation: their interfaces, stored state, transitions, completion conditions, and backpressure. Backpressure means that a receiver cannot accept more work, so its sender must retain the work and retry later.

This is a specification of a **parameterized hardware-model hypothesis for the studied GEMM path**. It is not a recovered NVIDIA design. Unknown capacities, timing parameters, mappings, and policies are listed rather than assigned hardware values. The existing Verilog implements only a subset. A complete functional description of the model must not be confused with complete physical identification of RTX 5090.

The scope is ordinary global input loads, shared-memory staging, operand preparation, matrix computation, synchronization, and output stores. General GPU functionality such as texture processing, special functions, atomics, and asynchronous transfer instructions is outside this first specification. A kernel using those operations must be refused until their components are specified.

The following components collectively describe the required GEMM path. Every component description states what exists now, so unimplemented behavior cannot be mistaken for an executable result.

## 2. Common interfaces and cycle semantics

### 2.1 Instruction and transaction information

A modeled instruction carries its block and warp identity, instruction identity, operation class, source and destination register identities, active-lane mask, and any required addresses. A memory transaction additionally carries its byte mask, parent instruction identity, destination, and transaction identity. Identities distinguish requests even when their addresses match.

The current trace format is smaller: one source, one destination, one representative address, and an operation code. A verified native GEMM trace requires multiple sources, all relevant lane addresses, and the true instruction dependencies. The reduced trace is not sufficient for complete numerical execution or exact transaction reconstruction.

Every request interface uses an acceptance rule. The sender holds a valid request stable until the receiver indicates it can accept it. Only an accepted request changes ownership. The receiver must eventually produce either a completion or a stated failure; it must not silently drop a request.

### 2.2 A tick has an explicit ordering

For the intended model, each reference-clock tick applies the following order:

1. Retire completions scheduled for this tick, updating data readiness and releasing occupied slots.
2. Evaluate synchronization and queue eligibility from the updated state.
3. Arbitrate among eligible requests using the specified policy.
4. Accept selected work and reserve its required state.
5. Record future completions and advance to the next tick.

A producer that becomes ready at a tick may therefore enable a consumer at that tick. A different convention would shift timings, so it must not be left implicit. The present prototype uses readiness timestamps rather than explicit return-message queues, with eligibility comparisons against the current cycle. It permits only one warp instruction to issue each tick.

All capacities and delays must be finite. A deadlock or unsupported operation produces a diagnostic refusal. A cycle limit detects nontermination but must not be used as a predicted completion time.

The current model uses one clock domain. A later multi-clock model must provide a ratio and transfer rule for each domain crossing. Converting elapsed time to reference cycles is not enough to determine those transfer rules.

## 3. Work distributor and block-residency manager

**Function.** Assign output tiles to blocks and blocks to SMs while respecting resource capacity. This is the component that turns a workload into physical placements.

**Inputs and outputs.** Input includes the grid, each block's register/shared/thread requirements, and completion notifications. Output is a block-admission request to a selected SM or a wait indication when no legal placement exists.

**Stored state.** Pending block queue; resident block identities on every SM; free register, shared-memory, warp, and block capacity; and resource reservations for admitted blocks.

**Transitions.** On block completion, release its reservations. For the parameterized baseline, examine pending blocks in grid order and choose the lowest-index SM with sufficient free capacity. Reserve all required resources atomically before admitting a block. The baseline placement policy is an engineering hypothesis, not an observed NVIDIA dispatch policy.

**Stalls and correctness.** A block waits if any required capacity is insufficient. Partial reservation is forbidden: it would allow conflicting admissions. Completion must not release resources while required output writes are still pending.

**Timing parameters and evidence.** SM count is measured as 170. Tested resident limits are eleven and eight for the original smaller and larger kernels. Allocation granularity, dispatch delay, placement policy, and the relationship between actual L1/shared configuration and resource admission remain unresolved. Residency experiments support finite capacity, not the baseline placement rule.

**Implementation.** Missing. The prototype contains one block on one modeled SM and has no resource allocator.

## 4. Warp context and instruction supply

**Function.** Maintain each warp's program position and supply its next legal instruction. Instructions remain in program order within a warp unless a future, separately specified rule permits otherwise.

**Inputs and outputs.** Input is the instruction stream and block admission. Output is the next instruction with its dependency and resource requirements. An accepted issue advances the program position.

**Stored state.** Warp program counter, active mask, block identity, completion state, and synchronization state. A numerical model would also retain values; the current timing model retains only dependency identities.

**Transitions.** On admission, initialize the declared input registers and program counter. Expose the next instruction without advancing. Advance only after issue acceptance. A barrier changes the warp to a waiting state. An end instruction stops further issue but does not erase outstanding work.

**Stalls and correctness.** Fetch stalls at barriers, unresolved instruction dependencies, unavailable issue resources, or unsupported instructions. The model must never skip an instruction to hide a missing dependency. Divergent execution and reconvergence are not specified for this first straight-line trace model.

**Missing parameters.** Instruction-fetch bandwidth and delay, instruction-cache behavior, scheduler partition assignment, and native instruction decoding costs.

**Implementation.** Present in reduced form: four instruction arrays and program counters, each limited to 256 entries. Register zero is initially ready; other values require producers.

## 5. Warp scheduler and issue arbiter

**Function.** Choose ready warp instructions without exceeding issue capacity or admitting work to a full receiver.

**Inputs and outputs.** Each warp supplies a candidate; readiness and downstream availability determine eligibility. Output is an accepted instruction to a resource or operand collector.

**Stored state.** Round-robin cursor for the baseline scheduler, partition assignments when specified, and any per-warp or per-operation issue-spacing state.

**Transitions.** Recompute eligibility each tick. Starting at the cursor, choose the first eligible candidate. Check all required receivers before accepting it. After acceptance, move the cursor to the following warp. Issue bandwidth is a model parameter; the implemented baseline permits one accepted instruction per tick.

**Stalls and correctness.** A warp is ineligible when a source is unavailable, a barrier is outstanding, a required queue is full, or a destination has an unresolved overlapping write. Eligibility must use the real resource requirements, rather than one global utilization percentage. No receiver can be oversubscribed by simultaneous issue choices.

**Missing parameters.** RTX scheduler count and assignment rules, issue width, dual-issue restrictions, operation-class routing, and actual arbitration. The corrected matrix probe constrains effective throughput, but does not uniquely identify these structures. An earlier single-resource scheduler has a retained 24.7% counterexample.

**Implementation.** One round-robin arbiter exists. Its policy is a hypothesis and has not been validated as RTX 5090 scheduling.

## 6. Register file, readiness scoreboard, and operand collection

**Function.** Hold values and ensure an instruction receives the correct completed version of every source. The scoreboard tracks whether a producing instruction has completed; the operand collector obtains sources through available register ports before dispatching execution.

**Inputs and outputs.** Input includes register-read requests and execution writebacks. Output is an operand-ready instruction or a stall. Writebacks name the destination version they complete.

**Stored state.** Physical register allocation, register contents in a numerical model, source-readiness state, pending destination versions, register-bank/port availability, and queued operand requests.

**Transitions.** An instruction reserves a destination version at accepted issue. A writeback makes that version available. Source reads consume available bank ports and collect all required operands. Dispatch occurs only when every operand has been collected. Without renaming, a new writer must wait for an older unfinished writer to the same register.

**Stalls and correctness.** Missing producers, bank contention, insufficient read ports, unavailable operands, or writeback contention block progress. Reading a pending result is forbidden. A barrier cannot turn an undefined register into a defined one.

**Missing parameters.** Register allocation granularity, bank mapping, read/write ports, operand collector capacity and routing, and bypass timing. Native register counts constrain allocation but not these internal mechanisms.

**Implementation.** Only scoreboard timestamps and overlapping-write checks exist. There are 64 abstract register identities per warp. Physical register storage, operand values, banks, collectors, and writeback arbitration are missing. Sixty-four identities must not be interpreted as the GPU's physical register capacity.

## 7. Integer and ordinary arithmetic execution

**Function.** Execute address and control arithmetic or other supported ALU instructions after operands become ready.

**Inputs and outputs.** Input is an accepted instruction with collected sources and a reserved destination. Output is a result-completion event, with a value if numerical execution is implemented.

**Stored state.** In-flight instruction records, execution-lane availability, and output/writeback queue state. Each record identifies its destination and due completion cycle.

**Transitions.** Admit an operation when its execution service interval is available. Reserve initiation capacity independently of its output latency. Advance the operation until completion, then send a writeback; retain it if the writeback receiver is full.

**Stalls and correctness.** Full execution or output queues block admission or retirement. Instruction classes with different pipelines must not automatically share one service limit.

**Missing parameters.** CUDA-core organization, supported integer/floating-point instruction classes, instruction-specific latency and initiation interval, pipeline sharing, and writeback capacity.

**Implementation.** An abstract ALU operation has one configurable result delay and one-cycle initiation spacing. It produces readiness, not computed data. It is not yet a CUDA-core model.

## 8. Matrix operand preparation and Tensor Core execution

**Function.** Convert shared/register operands into the form required by matrix instructions and perform ordered accumulator updates.

**Inputs and outputs.** Input contains operand and accumulator dependencies, operation shape/type, and active lanes. Output is updated accumulator readiness and, in a numerical model, accumulator values.

**Stored state.** Operand-preparation requests, collected operand versions, execution reservations, pending matrix operations, and accumulator destination versions.

**Transitions.** Operand preparation must complete before matrix issue. Matrix operations may overlap if service capacity permits, but updates on the same accumulator chain must observe dependencies. Completion returns the entire modeled destination set; partial destination writes need their own specified semantics.

**Stalls and correctness.** Missing operands, unready accumulators, execution-service limits, or full return queues stall. A matrix-operation abstraction must identify whether it represents one native instruction or a group of instructions; timings for those two choices cannot be mixed.

**Evidence and missing parameters.** The corrected primitive used a 16 × 16 × 16 matrix operation emitted as two native matrix instructions. Its per-warp cost and throughput saturation are observed, but do not identify individual instruction latency, Tensor Core pipeline count, operand collection, or routing. Register rearrangements have separate dependency evidence and cannot simply be treated as free.

**Implementation.** One abstract matrix resource has separate result delay and initiation spacing. Register rearrangements, multiple operand inputs, and numerical updates are not implemented. The example's single matrix token is a synthetic operation, not an automatically reconstructed native instruction.

## 9. Load/store issue, coalescing, and transaction tracking

**Function.** Convert accepted memory instructions into transactions, route them to the appropriate memory path, and assemble returned data for the consuming instruction.

**Inputs and outputs.** Input includes address-space identity, active lane addresses, load/store byte masks, and store values. Output includes memory transactions, accepted-store acknowledgments, and load writebacks.

**Stored state.** Load and store queues, per-instruction transaction records, outstanding transaction slots, and masks of returned bytes.

**Transitions.** Group lane accesses according to an admitted coalescing rule. Reserve queue and transaction capacity before issuing. Track each transaction through request acceptance and return. Complete a load only when all bytes its active lanes need have arrived. Store acceptance and globally visible store completion are distinct events and must be modeled separately when relevant.

**Stalls and correctness.** Queue exhaustion, transaction exhaustion, translation waits, downstream backpressure, and incomplete returns prevent progress. Requests with the same address must retain separate consumers even if the memory system combines the fetch.

**Missing parameters.** Queue depths, transaction granularity, coalescing rules for each native instruction, per-cycle request bandwidth, return bandwidth, and memory-ordering rules.

**Implementation.** Only representative global-load addresses, an outstanding-fill limit, and a common memory issue-spacing timestamp exist. Warp coalescing, independent request queues, global stores, and multi-transaction load completion are missing.

### 9.1 Address translation

**Function and interface.** Convert a virtual memory address into a physical address before a transaction requiring translation reaches the cache/controller mapping. Input includes address and access type; output is a translated request or a reported unsupported/fault condition.

**State and transitions.** A translation cache stores page tags and mappings. On an available mapping, return the physical address after the supplied lookup delay. On a missing mapping, allocate a bounded translation request, obtain a mapping from the configured translation provider, update state, and retry waiting transactions. The provider must give a deterministic mapping and completion rule; the model must refuse execution if it is absent.

**Stalls and gaps.** Pending translation capacity and response backpressure can stall memory issue. Page size, translation-cache structure, shared translation resources, and delays are not identified by our current tests. Identity translation would be an explicit diagnostic assumption, not a hardware fact. This component is unimplemented.

## 10. Shared memory and L1 configuration

**Function.** Serve block-local shared accesses and any modeled L1 accesses while respecting bank service and the chosen shared-memory/L1 partition.

**Inputs and outputs.** Input contains block allocation, address space, per-lane word addresses, byte masks, and load/store values. Output is read data or write completion.

**Stored state.** Shared storage allocated per block, L1 state if modeled, partition configuration, per-bank service queues, and request-completion state.

**Transitions.** Decode accesses into bank requests. For the tested ordinary shared-word path, consecutive four-byte words map cyclically over 32 banks. Duplicate reads of the same word can be treated as a broadcast only where the instruction-specific rule is supported. Different words contending for a bank require separate service. Complete the parent instruction after its required portions finish. Shared writes update bytes before protected consumers can read them.

**Stalls and correctness.** Bank-port limits, full queues, and receiver capacity stall service. Memory allocated to one block must not alias another block's shared storage. A partition request is not proof that a driver selected the requested physical configuration.

**Evidence and missing parameters.** Address-derived service counts are validated for selected compiled operand paths. Exact bank ports, read/write timing, full warp instruction splitting, physical L1/shared partition choices, and L1 behavior remain missing. Fewer bank-processing steps did not guarantee shorter full-kernel runtime.

**L1 behavior required by the contract.** Global requests eligible for L1 must first perform a policy-qualified lookup. L1 state includes tags, valid sectors, pending fills, and any dirty state required by the selected write policy. A valid ready hit returns through the load path. A matching pending fill attaches the consumer; an absent sector sends a miss toward L2 when capacity permits. Returned sectors satisfy consumers and update cache state. Eviction and writes follow a supplied explicit policy. Instructions that bypass L1 must preserve their bypass behavior, rather than receive an assumed L1 benefit. The selected L1/shared partition limits both storage allocations. Actual L1 geometry, policy, timing, and bank/resource sharing are unknown here; its implementation is missing.

**Implementation.** Thirty-two bank-availability timestamps and one global shared-service timestamp exist. One representative address is used per instruction. Storage contents, lane splitting, broadcasts, partitioning, and L1 are missing. The shared-load result does not yet depend on the actual value/version written by a prior store; its readiness is simply scheduled. This is a major functional gap, not only a timing parameter.

## 11. L2 lookup, replacement, and pending misses

**Function.** Decide whether requested sectors are available, still being fetched, or absent; obtain missing data and route completion to every consumer.

**Inputs and outputs.** Input is a sector request with source transaction identity and read/write semantics. Output is a cached response, a device-memory request, or a queued pending response.

**Stored state.** Set/tag mapping, way validity, sector validity, replacement order, pending-fill records with consumer lists, dirty state if writes are supported, and lookup/fill/return queue capacity.

**Transitions.** A lookup checks the address-derived set and tag. If the needed sector is valid and available, enqueue a cached response. If a matching fill is pending, attach the consumer to that fill. Otherwise reserve miss capacity and a legal victim, then send a memory request. On returned data, update validity, release the pending record, and enqueue responses to all consumers. Replacement must preserve or explicitly write back dirty data according to the admitted write policy.

**Stalls and correctness.** Full lookup, miss, fill, or response queues stall. An unfinished fetch cannot be evicted while losing its consumers. Cache replacement never removes a completion obligation. A hit counter observation does not by itself specify whether a consumer waits for an in-progress fill.

**Evidence and missing parameters.** L2 capacity is measured as 96 MiB. Recency-sensitive reuse and pending-data effects are supported in bounded experiments. Set count, associativity, mapping/hash, slice organization, ports, exact replacement, dirty/write policies, miss capacity, and response timing are not identified.

**Implementation.** A synthetic 16-set, two-way, 32-byte-sector cache supports reads only. Its mapping is sector index modulo set count, and replacement uses recency timestamps. Pending data delays the modeled response. It lacks consumer-list queues and backpressure; readiness timestamps stand in for returns. Pending replacement is refused. This 1 KiB demonstration cache is not the measured 96 MiB L2.

## 12. Device-memory controller and return path

**Function.** Service transactions that miss the cache and return their data under finite channel, bank, and bus capacity.

**Inputs and outputs.** Input contains physical addresses, operation type, byte masks, and request identity. Output is returned data or write completion toward the cache.

**Stored state.** Per-channel request queues, bank/row state if modeled, command eligibility, in-progress transfers, and return queues.

**Transitions.** Route each request using an explicit channel/bank mapping. The simplest proposed diagnostic baseline uses bounded FIFO queues and configurable request-service and return delays. A more physical model must separately specify command constraints and data-bus occupation. Dispatch a request only when all its required resources are available; retain returns until the receiver accepts them.

**Stalls and correctness.** Queue capacity, bank conflicts, transfer-bus occupation, and return backpressure delay progress. Read response delay is not equivalent to sustainable bandwidth.

**Evidence and missing parameters.** The GPU uses GDDR7. Compound cold-request measurements do not isolate controller latency. Channel/bank mapping, command timing, queue depth, arbitration, write handling, and actual clock-domain timing remain missing.

**Implementation.** No controller exists. Each new cache miss is assigned a fixed completion timestamp. That is a test assumption, not a device-memory microarchitecture.

## 13. Barrier controller, output completion, and block retirement

**Function.** Enforce block synchronization and determine when the kernel's required outputs are complete.

**Inputs and outputs.** Input contains warp arrival at a named barrier, operation completions, end instructions, and output-store acknowledgments. Output releases waiting warps or retires the block.

**Stored state.** Barrier generation number, participant masks, arrival masks, required memory-completion state, pending output stores, and block completion state.

**Transitions.** Record arrival without confusing successive barrier generations. Release only after all required participants arrive and the specified memory dependencies are satisfied. Apply the modeled release delay. Retire a block only after every warp ends and every required output completion occurs.

**Stalls and correctness.** An unmatched barrier must be diagnosed. A single completed warp cannot release its neighbors. A block cannot release allocations early while output traffic remains pending.

**Missing parameters.** Barrier throughput and release rules, exact memory-ordering obligations, partial participant semantics, and output-store completion boundaries.

**Implementation.** The prototype requires all four warps at the same barrier and drains all earlier timed operations before release. End waits for each warp's latest completion timestamp. Named generations, partial participants, output stores, and whole-grid retirement are missing.

## 14. Clock, event transport, and observation

**Function.** Coordinate clocked transitions and record progress without changing modeled decisions.

**Inputs and outputs.** Input is clock configuration and completion events. Output is trace records and final completion time.

**Stored state.** Reference cycle, completion-event scheduling, and optional per-domain phase state. Observations record accepted operations, not attempted operations alone.

**Transitions.** Advance the clock, apply the common tick ordering, and record issue and completion events. Cross-domain requests must pass through explicit transfer timing if multiple domains are enabled.

**Stalls and correctness.** Event loss, duplicate completion, impossible negative delays, or unsupported domain crossing are errors. Waiting counters are scheduling observations; they must not be added as independent runtime components.

**Implementation and gaps.** A single reference clock drives the model. It prints issue and availability times and detects a cycle-limit failure. No waveform-based verification or independent memory clock exists. GPU profiles demonstrate operating-clock differences; their rates do not determine intrinsic operation delays.

## 15. End-to-end functional example

A complete modeled staging/computation step should proceed as follows:

1. Admit a block after reserving its register and shared storage.
2. Supply a warp's address-producing instructions; issue them when their operands and ALU service are available.
3. Convert accepted global loads into transactions. Route them through lookup or pending-fill state, then device memory if necessary.
4. Return the required values to their destination register versions.
5. Permit shared stores only after their source values become available. Update shared storage through bank service.
6. Record the first barrier. Release it only when participating warps arrive and the protected writes satisfy the model's completion rule.
7. Read shared operands, collect register inputs, and issue supported rearrangement and matrix instructions.
8. Return accumulator results. Protect shared-buffer reuse with the second barrier.
9. Repeat reduction steps, then issue output stores and retire only after required output completions.

The executable demonstration implements selected timing dependencies in steps 3–8. It omits block admission, real transactions, storage values, operand collection, and outputs. Its seven mechanism checks verify the implemented subset, not the complete sequence above.

## 16. Missing information and implementation priorities

| Priority | Required addition | Why it is consequential |
|---|---|---|
| 1 | Verified native GEMM trace with complete register dependencies and lane addresses | Hand-written tokens cannot establish real-kernel behavior |
| 2 | Shared-storage write/read versions and explicit completion transport | The current read delay is disconnected from stored data |
| 3 | Scheduler/operand/execution resource mapping and supported timing | A single-resource interpretation already has a counterexample |
| 4 | Multiple blocks, resource reservations, and finite request/return queues | Necessary to reproduce the largest remaining dense-workload discrepancy |
| 5 | Supported cache mapping, pending fills, and memory service | Traffic counts alone do not establish readiness or contention timing |
| 6 | Output traffic, full completion rules, and clock-domain behavior | Needed for complete kernel elapsed-time prediction |

Observed structural constraints belong in this model even when exact parameters remain unidentified. However, no intrinsic cycle value may be obtained by silently treating a compound benchmark duration as one instruction's latency. Where multiple hardware explanations fit an observation, retain the alternatives until a distinguishing test resolves them.

The proposed baseline policies in this document make model behavior explicit. They are candidates to implement and falsify, not admissions of NVIDIA behavior. Hardware-specific parameters and alternative policies must be tied to measurements or documented source evidence before physical accuracy is claimed.

The current [Verilog source](gpu_timing.sv), [runner](run.py), [mechanism checks](verification.json), and [evidence manifest](evidence.json) identify what is executable today. The [previous experimental synthesis](../architecture_to_mip.md) provides the discovery history but is not a substitute for this component specification. The largest validated error of the independent phase model remains 5.97%; no equivalent accuracy has been established for this structural prototype. GPU experiments remain paused.
