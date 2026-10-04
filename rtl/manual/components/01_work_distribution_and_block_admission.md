# 01. Work distribution and block admission

[System specification and chapter index](../../rtl_microarchitecture_spec.md) · [Approved manual structure](../../hardware_manual_structure.md)

## 1. Purpose and boundary

The work distributor converts a matrix grid into tile identities. Admission reserves a context and its required resources before any warp starts; retirement returns those reservations only after required stores complete.

This is a specification of the executable reconstruction. Statements about physical RTX 5090 hardware retain their source or measurement scope; helper defaults describe model configurations.

## 2. Quantitative parameters

The table assigns this chapter ownership of the following inventory entries. “Baseline” preserves the existing setting; the evidence check may instead support a scoped alternative. Source priors are usable provisional estimates, not measurements of a private circuit.

| ID | Definition | Baseline | Unit | Recorded basis | Initial check |
|---|---|---|---|---|---|
| F001 | The register-word quantum used when reserving registers for each warp. | 256 | 32-bit register words per warp | KNOWN_SOURCE | Previous source or measurement record |
| F002 | The byte quantum used when reserving shared memory for a block. | 128 | bytes per CTA | KNOWN_SOURCE | Previous source or measurement record |
| F003 | The rule choosing an SM and resource partition for an arriving block. | round-robin across eligible SMs | policy | ENGINEERING_ASSUMPTION | Numerical model consistency only |
| F004 | The rule choosing which eligible block is dispatched next. | oldest ready CTA first | policy | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| T001 | Time from a block requesting admission to its resources being reserved; excludes later instruction execution. | Not specified | SM cycles | unidentified | Transferred simulator prior |
| T002 | Time from an admitted block to its first eligible instruction; excludes the admission delay. | Not specified | SM cycles | unidentified | Transferred simulator prior |
| T003 | Time from a block finishing its required acknowledgments to its resources becoming reusable. | Not specified | SM cycles | unidentified | Transferred simulator prior |

Use the [complete parameter table](../../parameter_master_table.md) for values, scope, evidence links and provisional alternatives. Device capacities are centralized in the system specification. Per-module tables below identify which parameters are actually consumed by each implementation.

## 3. Interfaces and transaction ownership

Grid launch → tile selection → atomic admission → resident context → acknowledged retirement. The connected top has two modeled SMs and two contexts per SM. This exercises resource ownership but does not represent all 170 physical SMs.

The exact port names, directions, widths and acceptance rules are listed in the implementation contracts in Section 8 and their linked sources. A connection must preserve both payload and ownership while stalled. The common system protocol applies unless a module contract explicitly states a pulse-only interface.

## 4. State and storage

Each linked module contract specifies its arrays, counters, masks, pointers or state machine. Those fields belong to that implementation only. A primitive helper is not an additional copy of a hardware resource inside the connected top unless that top instantiates it. Reset removes outstanding model ownership according to the specified contract; physical power-on behavior is outside this model.

## 5. Functional transitions

Launch acceptance captures the matrix bases and identity. A selected tile waits until a resident context is free. Completed tiles are marked once; the grid finishes after every tile has retired. The simple allocator consumes raw register/shared demands, while the quantized allocator adds rounding; these are different implementations.

Requests are accepted only when the named receiver permits acceptance. Completion must update the original owner before resources are released. The implementation contracts below describe each state transition and numerical transformation separately.

## 6. Timing and arbitration

Use completion latency, acceptance interval and queue capacity as three distinct quantities: when a result becomes available, how often a new request can start, and how many requests can remain pending. The per-module timing contract gives their actual code meaning.

For a held-response interface, observe a valid response after an edge, hold readiness low for one more edge, and verify that identity and data remain unchanged. Retirement occurs only on a later edge with both valid and ready. A receiver becoming free after an edge does not retroactively accept a request at that edge.

## 7. Invariants and failure handling

Resource totals must remain conserved. A stalled child cannot advance the dispatch cursor or consume a second reservation. Block completion requires the child completion handshake; issuing its last arithmetic instruction is insufficient.

Unsupported configurations must remain explicit. A passing test of a helper establishes its tested model contract, not a GPU-wide hardware policy.

## 8. Linked implementations and detailed contracts

The following contracts retain the quantitative organization, exact interfaces, state transitions and verification scope of the existing implementations. Verilog stays in separate source files. C++ adapters expose the same generated ports and clock behavior; they do not introduce independent timing constants.

### Implementation 2: Block resource allocator

**Role.** Records register and shared allocations for each admitted block. Combinational logic calculates free capacity and selects a free slot. Admission reserves both resources; valid retirement releases the corresponding allocation. Admission and retirement do not reuse the same occupied slot in one cycle.

**Quantitative configuration.** Queried capacity is 65,536 register words and 102,400 shared bytes per SM. The configurable block slots default to four solely for this component test model. Original GEMM occupancy was eleven smaller-tile or eight larger-tile blocks per SM.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| SLOTS | 4 | resident slots | Positive; admission needs a free slot | Baseline; tested occupancy is 11/8 |
| REG_WORDS | 65,536 | 32-bit words | Accepted total cannot exceed capacity | Queried |
| SHARED_BYTES | 102,400 | bytes | Accepted total cannot exceed capacity | Queried allocation context |
| Allocation granularity | Unknown | words/bytes | Must be supplied before physical capacity prediction | Unidentified |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| admit_valid / admit_ready | input / output | Admission request / allocator has sufficient capacity. |
| registers_needed, shared_needed | input, signed 32-bit counts | Allocation demand, in register words and bytes respectively. |
| admitted_slot, resident_blocks | output, signed 32-bit counts | Chosen slot identifier and current allocation count. |
| retire_valid, retire_slot | input | Release pulse and previously allocated slot identity. |

**Interface protocol.** On accepted admission the caller captures admitted_slot; it must supply that slot for exactly one later retirement.

**Stored state.** Per-slot busy bit, register allocation and shared allocation. Free totals and first free slot are combinational.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| busy | SLOTS bits | Allocation ownership |
| reg_alloc / sh_alloc | SLOTS × signed 32 bits each | Per-slot resource reservations |

**Reset and cycle transitions.** Reset frees every slot. A retirement clears its busy bit; accepted admission sets a previously free slot and records its demands. Retirement does not make that slot available combinationally during the same tick.

**Invariants and failure handling.** Resource totals remain within capacities for accepted nonnegative demands. Retirement of an invalid or free slot terminates simulation.

**Linked behavioral implementation.**


**Source implementation:** [block_allocator.sv](../../components/library/block_allocator.sv)


**Verification expectation.** Add tests for capacity rejection, exact allocation/release, simultaneous distinct-slot admit/retire, and invalid retire. Not behaviorally tested yet.

**Unimplemented or unidentified.** Thread/warp limits, allocation rounding, real dispatch policy, and multi-SM placement are missing. The supplied allocation requirements must already include supported rounding.

### Implementation 17: Quantized allocation demands

This combinational component converts compiler resource usage into CUDA allocation demands before block admission. Identified cc12.0 allocation rules are 256 register words per warp and 128 shared bytes per block. Evidence and checks are in [source sweep 5](../../discovery_rounds/source_sweep_005.md). They do not identify physical bank geometry.

| Port | Direction | Meaning |
|---|---|---|
| `block_threads` | input | Threads, 1 through 1,024 |
| `registers_per_thread` | input | Compiler register count, 0 through runtime limit 255 |
| `user_shared_bytes` | input | Static plus dynamic application bytes |
| `reserved_shared_bytes` | input | Explicit runtime reservation; 1,024 in saved profiles |
| `valid` | output | Inputs satisfy the supported domain |
| `allocated_register_words` | output | Rounded per-warp words times warp count |
| `launch_check_register_words` | output | Admission demand using warp count rounded to four partitions |
| `allocated_shared_bytes` | output | Rounded application plus reserved bytes |

There is no stored state, reset, arbitration or clock delay. Outputs are combinational. Invalid inputs produce zero demands with `valid` low. Check `valid` before sending demands to the block allocator. Separately enforce launch-check and per-partition capacities: the existing allocator checks aggregate capacities only. Physical warp placement remains unknown.

For 128 threads and 40 registers per thread, allocation is 5,120 words. Application storage of 8,192 bytes plus 1,024 reserved bytes allocates 9,216 bytes. Six directed checks passed, recorded in [allocation_verification.json](../../components/allocation_verification.json). No physical timing is assigned.


**Source implementation:** [allocation_demands.sv](../../components/allocation_demands.sv)

### Implementation 18: Connected quantized block admission

This wrapper connects Section 4.17 allocation arithmetic to the existing block allocator. It enforces the queried 24 block slots, 48 resident warps, 65,536 register words, 100 KiB shared capacity and 99 KiB application shared limit per block. It does not model unknown partition placement or hardware dispatch arbitration. The default shared capacity is the device limit; actual runtime carveout selection remains a separate unresolved configuration.

| Port group | Direction | Contract |
|---|---|---|
| `clk`, `rst` | input | Clock and synchronous reset |
| `admit_valid` | input | Caller presents a request and holds its resource fields until accepted |
| `block_threads`, `registers_per_thread` | input | Compiler thread and register demand |
| `user_shared_bytes`, `reserved_shared_bytes` | input | Application and runtime shared demand |
| `admit_ready` | output | Valid demand fits current aggregate capacities |
| `admitted_slot` | output | Candidate slot, valid only when request is accepted |
| `resident_blocks`, `resident_warps` | output | Current allocated totals |
| `allocated_register_words`, `allocated_shared_bytes` | output | Rounded demand for the presented request, not resident totals |
| `retire_valid`, `retire_slot` | input | Release an allocated block at the next edge |

Acceptance is `admit_valid && admit_ready` at a rising edge. Resource demand calculation is combinational. The wrapper stores warp count per slot; the connected allocator stores register and shared allocations. Reset clears all state. Retirement of an invalid or empty slot is fatal in the allocator. Zero threads, excessive registers or excessive shared demand cannot be admitted. There is no numerical payload in this connection.

Readiness uses pre-edge allocations. If a full model retires a block at edge E, it cannot use that released capacity for another admission at E; readiness changes after E, permitting admission at a later edge. If both events are legal using pre-edge space, they update different slots. Slot selection is the existing lowest-free-slot modeling policy, not recovered NVIDIA arbitration. The one-edge transition is implementation timing, not measured dispatch latency.

Connected checks reproduce eleven resident blocks for the small saved GEMM and eight for the larger, verify resource release, and enforce block, warp and per-block shared limits. [quantized_admission_verification.json](../../components/quantized_admission_verification.json) preserves source hashes and results. This is a connected resource subsystem, not an integrated full GPU.


**Source implementation:** [quantized_block_admission.sv](../../components/quantized_block_admission.sv)

### Implementation 43: Complete tested grids through one reusable CTA context

**Question and role.** Can the connected CTA produce every coordinate of a complete matrix, rather than only the first block? The [grid controller](../../numerical/studied_gemm_grid_controller.sv) drives dynamic block coordinates through one reusable CTA instance. Block columns advance first, followed by block rows. The child runs the four-warp native operand window, coalesced input/output, output scratch and stage barriers. Only one block is active at a time. This tests global addressing and context reuse; it is not an SM scheduler or a parallel full-chip model.

**Geometry and quantitative defaults.** `M`, `N` and `K` are output rows, output columns and reduction length; defaults are 64, 96 and 64. The supported block shape is `BM = BN = BK = 32`. Whole-grid dimensions must be positive full multiples of the block dimensions; partial edge blocks are unsupported. A 64 × 96 grid has two block rows and three block columns, giving six CTAs and 6,144 FP32 output words. A 96 × 64 grid has three block rows and two block columns and the same output count. The original 2,048 × 2,112 full grid has not been validated by these receipts.

| Interface | Payload | Contract |
|---|---|---|
| Grid launch | 32-bit ID and A/B/C byte bases; valid/ready | Accepted only while idle; all bases and ID are captured |
| Grid completion | Retained grid ID; valid/ready | Held after all blocks and all output-store acknowledgments finish |
| Backing input | 32-bit ID/address, 256-bit returned sector, request/response ready-valid | Forwarded to the current CTA’s completion-driven cache |
| Masked output | 32-bit ID/address, 256-bit packet, eight-bit word mask; matching acknowledgment | Forwarded to the current CTA; only selected words are updated |
| Scalar output compatibility | Scalar request/response ports retained | Inactive because this wrapper always selects coalesced output |
| Block diagnostics | Dispatched/completed counts and accepted launch/completion coordinate events | Each event identifies the current block; counters must conserve one active context |
| Clock/reset | `clk`, `rst` | Reset cancels the grid and child work; providers discard old transactions |

**State and context reuse.** IDLE captures the grid request and starts at block (0, 0). LAUNCH_BLOCK offers the current coordinates and ordinal ID to the child until accepted. WAIT_BLOCK accepts only that ordinal’s completion, which already requires all global output acknowledgments. The controller then increments the column; after the last column it resets the column and increments the row. DONE exposes the original grid ID. If a grid request is accepted at edge `L`, the child can accept its first CTA no earlier than `L + 1`. If a child completion is accepted at edge `D`, the next CTA can be accepted no earlier than `D + 1`; for the final CTA, grid completion is registered after `D` and remains valid until the grid acknowledgment. A block ordinal is a sequence index inside the grid, independent of the external grid ID.

For the 64 × 96 case, the launch order is (0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (1, 2). One accepted block increments the dispatch counter, and its completed response increments the completion counter. A new block cannot be dispatched before the previous one completes. Captured coordinates determine all A/B/C addresses in the child, so a later coordinate change cannot redirect an already accepted CTA.

The child cache persists across blocks and ordinary grid replays. A/B backing contents must therefore remain unchanged unless reset precedes reuse; this wrapper exposes no invalidation operation. Reset cancels pending work and resets sequence IDs, so external providers must flush old returns/acknowledgments. Reset does not roll back global stores already committed by a provider. One reused context means modeled operand/scratch storage is not multiplied by the number of grid blocks.

**Independent complete-grid verification.** The [full receipt](../../numerical/studied_gemm_grid_verification.json) compares every output against an independent full integer dot product using the original A17/B13 dyadic formula with each tested grid’s global strides. It checks every distinct output coordinate, masks, delayed backing returns/stores, held packets/completion, cache-preserving replay and reset cancellation of the first pending backing read. Launch snapshot stability is established by source inspection; the fixture does not mutate the accepted launch fields to test that contract. Four accepted grid launches each dispatch and complete six CTAs and acknowledge 768 output sector packets.

| Tested matrix shape M × N × K | Grid launches | Exact output-word comparisons and acknowledgments | Backing requests over the fixture |
|---|---:|---:|---:|
| 64 × 96 × 64 | 2 | 12,288 | 640 |
| 64 × 96 × 1,536 | 1 | 6,144 | 36,864 |
| 96 × 64 × 64 | 1 | 6,144 | 640 |
| Total | 4 | 24,576 | 38,144 |

The K64 two-launch fixture makes only 640 backing requests in total, matching its 20,480 input bytes divided into 32-byte sectors. This is cache reuse under the declared model geometry, not measured RTX cache behavior. Accepted-launch-to-observed-completion cycles are 31,663 and 29,096 for its two launches, 824,467 for the 64 × 96 × K1536 launch, and 35,503 for the 96 × 64 × K64 launch. Provider delays differ between fixtures, so these values are not controlled hardware-performance comparisons. Whole-fixture cycle counts additionally include reset/setup/held completion.

**Physical boundary.** Complete small-grid values are verified for these periodic dyadic inputs; some misaddressings can preserve periodic values, and arbitrary floating-point inputs are not characterized. The original full-sized grid is not validated. All CTAs are serial. There is no multi-SM placement, concurrent block residency, overlapped global staging, hardware cache contention or calibrated runtime. Columns-first traversal, one context, cache parameters and service timing remain development choices. Physical evidence counts remain eight identified, 32 partial and 94 unknown; no new parameter is closed.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_studied_gemm_grid.py` for all fixtures, or add `--quick` for the repeated 64 × 96 × K64 grid.

**Inline behavior.**


**Source implementation:** [studied_gemm_grid_controller.sv](../../numerical/studied_gemm_grid_controller.sv)

### Implementation 44: Resident preloaded compute stages with atomic admission

**Role and scope.** The [resident stage engine](../../numerical/resident_native_stage_engine.sv) keeps two independent preloaded compute-stage contexts while sharing exactly one scalar shared-read service, one MOVM service and one HMMA service. Each context has four warp windows, its own 4,096-byte operand array, C values, instruction positions, readiness, producer tracking and service ownership. Context count does not multiply execution-unit queue capacities. This is the bounded 32-element reduction stage, not concurrent complete CTAs or a full-grid SM model.

| Interface | Payload and contract |
|---|---|
| Shared initialization | Context index plus scalar halfword write or optional 32-lane masked write; only an idle context can be written |
| Stage request | Context index, external 32-bit ID and C registers `[4][32][8]`; accepted only when that context is idle and initialized |
| Availability | Per-context ready/initialized masks; readiness is evaluated independently of request valid |
| Stage response | Retained context/ID and `[4][32][8]` result words; selected response remains stable until acknowledged |
| Per-warp conditions | Memory-safe and fully-drained masks for each context, as distinguished in section 4.40 |
| Instruction trace | Issued context, warp and instruction address; at most one instruction across all contexts per edge |

**Shared arbitration and completion ownership.** A round-robin selector scans eligible warps across both contexts. All requests compete for the same default read/MOVM/HMMA capacities of 4/4/2, with provisional interval/return settings described in section 4.40. Actual completions update only their owning context and warp. Each accepted context increments a private epoch, or reuse sequence number. Internal IDs contain that epoch plus flattened warp/instruction index; default two-context/four-warp geometry uses nine local bits and 23 epoch bits. Stale epochs and unmatched pending operations are rejected. Epoch exhaustion requires reset rather than wrap.

Each context progresses independently through IDLE, RUN, DRAIN and RESPONSE. A separate response selector latches one completed context and holds it under backpressure. Holding context zero’s result does not stop context one from issuing, draining, or completing another stage. A context remains occupied until its own actual response acknowledgment. Reset cancels all contexts and shared services; it is not a physical context-switch timing rule.

**Admission wrapper and quantities.** The [admission wrapper](../../numerical/resident_stage_admission.sv) reserves a slot through the quantized allocator and accepts the selected engine stage on the same edge. Configured budgets are 65,536 register words, 102,400 shared bytes and 48 warps, with two implementation context slots. The request has 128 threads, 40 registers per thread, 8,192 user shared bytes and 1,024 reserved bytes. Its quantized demand is **5,120 register words and 9,216 shared bytes per request**. Outputs named `allocated_register_words` and `allocated_shared_bytes` report this demand; they are not live allocation totals and remain nonzero after retirement. Live counts are `resident_blocks`, `resident_warps` and the allocator’s internal slot state. Two admitted requests mean two blocks/eight warps, with derived combined demands 10,240 words and 18,432 bytes. Nominal shared reservation includes capacity beyond the engine’s 4,096-byte operand array; it does not imply an implemented output-scratch lifetime here.

The wrapper’s `stage_req_valid` is a ready-qualified transfer strobe, not an ordinary request held while stalled. It becomes true only when the outer launch, allocator and selected engine are ready together. The engine must therefore calculate readiness independently of this valid signal. This prevents the lowest-free allocation slot from changing underneath a stalled internal offer. Outer launch fields must be held until accepted. The same transfer reserves the slot and captures the stage’s ID; neither happens alone.

A response supplies context and ID, is checked even while held, and must match a live admission. `done_ready` acknowledges the actual engine result and retires that allocation on the same edge. The allocation remains live while completion is held. Final zero assertions apply to live block/warp/engine counts, not the constant request-demand outputs. **A complete CTA may not retire at an intermediate stage acknowledgment:** its reservation must span all reductions, output scratch and acknowledged global stores. This wrapper deliberately exercises stage lifetimes and has not implemented that full lifetime.

**Verification and boundary.** The [stage receipt](../../numerical/resident_native_stage_verification.json) checks 8,192 output words against distinct context-specific direct dot products, with nonzero initial C and shared-read capacities one and two. It checks interleaved instructions, held response while another context progresses, two retained allocations/eight warps, matching retirement, final zero live counts, and reset/refill. Source hashes match the tested engine and wrapper. Arbitration, timing and this partial-stage lifetime remain hypotheses; no physical parameter is closed.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_resident_native_stage.py`.

**Inline engine.**


**Source implementation:** [resident_native_stage_engine.sv](../../numerical/resident_native_stage_engine.sv)


**Inline admission wrapper.**


**Source implementation:** [resident_stage_admission.sv](../../numerical/resident_stage_admission.sv)

### Implementation 50: Resident blocks through scratch and acknowledged global outputs

**Question and scope.** Can two resident block contexts share the implemented services and retain their allocation until every output has actually been written? The [complete resident controller](../../numerical/resident_gemm_complete.sv) extends section 4.47 from register results to producer/consumer barriers, output scratch and acknowledged global stores. It runs bounded BM32/BN32/BK32 blocks. A caller submits block coordinates; this component is not a full-grid dispatcher or a multiple-SM scheduler.

| Interface or quantity | Contract |
|---|---|
| Launch | Valid/ready, 32-bit ID, A/B/C bases and block row/column; captured on acceptance |
| Input backing | 32-bit ID/address requests, actual 256-bit sector returns |
| Output backing | 32-bit ID/address, 256-bit data and eight-bit word mask; matching acknowledgment required |
| Completion | Retained ID/context and `[4][32][8]` registers, held until acknowledgment |
| Residency | Defaults two contexts, four warps each; 5,120 register words and 9,216 shared bytes reserved per block |
| Common services | One input cache, one read hub/service, one MOVM service and one HMMA service |
| Service capacities | Defaults: two common read slots, four MOVM slots and two HMMA slots; cache has 64 sets and eight ways |
| Output actor | One scratch transaction and one warp-store transaction at a time |
| Default delays | Read return nine, MOVM 19, HMMA 73, store return one and barrier release one modeled cycle |
| Default intervals | Shared package one, MOVM one, HMMA four and scratch store package one modeled cycle |

Launch validation checks complete block bounds, even A/B bases, word-aligned C, 32-bit allocation limits and output/input nonoverlap. Accepted metadata remains captured while external launch inputs change. Cached A/B values must remain immutable until reset. The tested blocks write disjoint output tiles; concurrent conflicting output launches are outside the intended contract.

Each context carries its accumulator through K/32 actual stages. Producer barrier arrivals follow the final committed operand groups for its four warps. Consumer arrivals use memory-safe indications, while the controller separately waits for actual arithmetic results before replacing the stage. The producer and consumer barrier objects track generations separately. This whole-stage rule remains conservative and does not replay every original address-generation or synchronization instruction.

**One resource across operand and scratch work.** Native operand reads and scratch reads are separate clients of the same read hub. Neither the native engine nor scratch component has a private read service. A common write arbiter grants either one staging vector commit or one scratch bank package per edge. Operand arrays remain private per context, and scratch has its own 4,096-byte logical array. Sharing service admission does not establish actual GPU storage aliasing, bank topology, native write bandwidth or calibrated overlap.

**Scratch interface and behavior.** The [external-service scratch component](../../numerical/studied_output_scratch_shared.sv) accepts an ID and four fragments' accumulators, then captures their values. Its store preview requests permission to commit the next package; only `store_grant` commits selected pending words. Four native STS64-shaped groups per warp produce 16 groups and 1,024 committed words. The modeled bank rule selects at most one pending word per bank per granted package; its interval and return delay are hypotheses. After a collective all-writes visibility fence, 32 real warp-read grants and matching returns reconstruct `[4][256]` row-major words. This all-store-before-all-read ordering is stronger than the original per-warp ordering. The component holds its ID and row-major response until acknowledged.

A registered output owner supplies these returned scratch words to 32 warp stores. Every 32 × 32 block sends 128 masked 32-byte sector packets containing all 1,024 FP32 outputs. The store adapter waits for each actual matching backing acknowledgment. The controller releases the scratch response only with the final warp-store completion; only then does that block enter final completion. Allocation remains live while final completion is held and retires only on its acknowledgment. Section 4.47 stops at the final register result; this bounded block lifetime also includes output writes.

**A model bug found by integration.** The first connected test exposed a consumer arrival after its barrier had already released. The controller had derived new arrivals from the barrier's transient arrived mask, which clears on release, while memory-safe indications stayed asserted. That caused the same warps to arrive again before the next generation was armed. The corrected `consumer_seen` mask belongs to the compute stage: it persists across barrier release and clears only when the next compute request is accepted. Thus each warp contributes once to that stage. This correction fixes simulation ownership; it does not identify a new NVIDIA barrier property.

**Verification and limits.** The [current complete-block receipt](../../numerical/resident_complete_verification.json) checks 12,288 acknowledged global FP32 outputs: all six disjoint blocks of M64/N96 at K64 and again at K1536, admitted through two contexts. An independent integer dot product using the original A17/B13 patterns and global strides, divided by 256, supplies exact expectations. Misaligned C, overlap with A/B and C-allocation overflow are rejected. The fixture perturbs A/B metadata and C base after acceptance and checks captured values. Reset is tested at the first pending input read, not during output stores. Held completion stability is checked; progress by another context during that exact hold is not required by this test. Reset requires provider cancellation and does not undo already committed stores.

Scratch behavior is exercised through this integrated top, not an isolated scratch test. The fixture records no simultaneous eligible native/scratch read candidates and confirms that staging and scratch writes were eligible together. Its contention indicators are Boolean flags, not event counts. Therefore it does not directly test real read competition in this complete path; section 4.49’s synthetic scratch client separately exercises the common hub. The numerical checks establish this bounded value/lifecycle path. They do not validate the original large global grid, full native instruction replay, physical resident capacity or GPU runtime. Output service is conservative and serial. All queue, delay and arbitration choices remain uncalibrated; physical counts remain eight identified, 32 partial and 94 unknown.

The [connected-round record](../../discovery_rounds/resident_complete_connected.json) preserves the integration evidence and remaining gaps.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_resident_gemm_complete.py`.

**Inline scratch behavior.**


**Source implementation:** [studied_output_scratch_shared.sv](../../numerical/studied_output_scratch_shared.sv)


**Inline complete-block behavior.**


**Source implementation:** [resident_gemm_complete.sv](../../numerical/resident_gemm_complete.sv)

### Implementation 51: Whole-grid dispatch into resident block contexts

**Role and organization.** The [resident grid controller](../../numerical/resident_gemm_grid.sv) submits every complete 32 × 32 output block to one instance of section 4.50's resident complete-block model. Unlike section 4.43's serial dispatcher, this component admits another block whenever a resident context is available. The default grid is M64/N96/K64: two block rows, three block columns and six blocks. Dimensions must be positive multiples of 32; partial edge blocks are unsupported. Two resident contexts share one input cache, read hub, MOVM/HMMA service set and serial output actor. This is one modeled SM, not an RTX chip scheduler.

| Interface or quantity | Definition |
|---|---|
| Grid launch | Valid/ready and 32-bit ID/A/B/C bases; captured on acceptance |
| Grid completion | Valid/ready and retained launch ID; stable while held |
| Input backing | 32-bit sector ID/address and actual 256-bit sector response |
| Output backing | 32-bit ID/address, 256-bit data, eight-bit word mask and matching acknowledgment |
| `dispatched_blocks` | Number of accepted child block launches in this grid |
| `completed_blocks` | Number of acknowledged child completions, each after its output stores |
| `resident_blocks`/`resident_warps` | Actual live child reservations; two contexts allow up to two blocks/eight warps |
| Block trace | Acceptance/completion pulses, ordinal and derived block row/column |
| `elapsed_cycles` | 64-bit model-edge counter from accepted grid launch to registered COMPLETE |

**Dispatch and ownership.** IDLE validates base alignment, 32-bit allocation bounds and C/input nonoverlap. Acceptance captures bases/ID, clears per-block launched/completed flags and enters RUN. Block columns advance fastest, followed by block rows. The dispatch ordinal advances only on child acceptance, so offered coordinates remain stable during backpressure. Child IDs are these ordinals rather than the external grid ID. Completion looks up the returned ordinal, rejects unlaunched, duplicate or out-of-range IDs and marks that block complete. The bookkeeping permits out-of-order child IDs; numerical correctness alone does not prove every possible ordering was exercised.

The controller checks `resident_blocks = dispatched_blocks − completed_blocks` while RUN. Grid completion requires every expected block dispatched and completed and zero resident reservations. Because each child completion follows all its actual output acknowledgments, grid completion cannot precede those stores. A subsequent RUN edge observes the drained counts and registers COMPLETE; final validity then holds until grid acknowledgment. No new grid is accepted while completion is held.

**Cycle boundary.** Acceptance sets the counter to zero. Each following RUN edge increments it, including the last child retirement and the additional drain-check edge. The counter stops in COMPLETE and remains fixed during a held final response. Thus it includes one drain-check edge beyond the last retirement, but excludes reset and held-completion duration. It is a count of this model's clock edges, with no conversion to physical GPU cycles or frequency.

The [current grid receipt](../../numerical/resident_grid_verification.json) checks 24,576 global output words: two complete six-block grids at K64 and two at K1536. Each launch checks all 6,144 outputs with an independent full integer-dot-product oracle and actual provider acknowledgments. Both contexts are occupied during each launch. C misalignment, overlap with A/B and allocation overflow are rejected. Captured A/B/C bases, held completion/counter stability and reset at the first pending input read are checked. Reset during output stores is not tested. The provider must flush stale returns on reset; previously committed output words are not rolled back. A/B remain immutable between repeated launches because the cache is retained and there is no invalidation port.

| Reduction length | First launch model cycles | Repeated launch model cycles |
|---|---:|---:|
| K64 | 27,499 | 21,692 |
| K1536 | 543,444 | 543,447 |

An independent edge counter checks these values. Cache contents are retained between launches, but the provider's timing phase also changes; these comparisons do not isolate a physical cache effect. Delay, queue, arbitration and resident-capacity settings inherit section 4.50's synthetic choices. This validates complete small-grid values and acknowledgment lifetimes, not the original M2048/N2112 grid or calibrated RTX runtime. Physical counts remain eight identified, 32 partial and 94 unknown.

The [connected-round record](../../discovery_rounds/resident_grid_connected.json) records the model change, verification and remaining full-chip gaps.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_resident_gemm_grid.py`.

**Inline behavior.**


**Source implementation:** [resident_gemm_grid.sv](../../numerical/resident_gemm_grid.sv)

### Implementation 53: Whole-grid dispatch across multiple resident SM models

**Organization.** The [multi-SM controller](../../numerical/resident_gemm_multi_sm.sv) instantiates two resident complete-block models by default, each with two block contexts. Four live blocks therefore share the common backing gateway while each SM retains its own operand/scratch storage, read hub and MOVM/HMMA services. Each SM also retains its own input cache: 64 sets, eight ways, 128-byte lines and four independently valid 32-byte sectors, or 64 KiB modeled data per SM. **There is no shared global L2 cache in this organization.** The placement and physical interpretation of these private cache instances remain unspecified.

| Interface or quantity | Contract |
|---|---|
| Grid launch/completion | Valid/ready, captured 32-bit ID and A/B/C bases; final completion held until acknowledgment |
| Backing interface | Common read-sector and masked-write-sector channels from section 4.52 |
| Global ledger | Per-block launched/completed bits and dispatched/completed counters |
| Dispatch trace | Block ordinal, row/column and selected SM on actual child acceptance |
| Completion trace | Actual child ordinal/coordinate and returning SM |
| Residency | Sum of child live blocks/warps; defaults permit four blocks and 16 warps |
| Cycle counter | 64-bit model-edge count through final RUN drain check, frozen while completion is held |

Column coordinates change fastest within each block row. A round-robin search finds an SM with child launch readiness; the selected SM is registered before its request is offered and remains the owner under backpressure. Only acceptance increments the global block ordinal. A separate round-robin completion selector acknowledges at most one child per edge. Returned ordinals index the global ledger, permitting out-of-order block completion while rejecting duplicate, unissued or out-of-range IDs. The ledger validates ordinal uniqueness; it does not independently store an expected SM owner for each ordinal. Residency must equal dispatched minus completed blocks. Final completion requires all blocks complete and all SM reservations zero, which follows their actual global store acknowledgments.

The [multi-SM receipt](../../numerical/resident_multi_sm_verification.json) checks 24,576 final words: two complete M64/N96 grids at K64 and two at K1536. Each grid has six disjoint blocks and 6,144 independent exact integer-dot-product expectations. Every launch reaches four resident blocks, and both SMs issue native instructions. Four invalid-C launch cases are rejected. Launch bases are captured, completion/counter holds are checked and reset occurs at the first pending input read; reset during output stores is not covered. Inputs remain immutable across repeated cache-preserving launches. Partial tiles, the original large grid and arbitrary conflicting output launches are outside current verification.

| Reduction length | First launch model cycles | Repeated launch model cycles |
|---|---:|---:|
| K64 | 28,234 | 17,862 |
| K1536 | 424,384 | 424,392 |

These counts use the same accepted-launch-to-registered-completion boundary as section 4.51, including the final drain-check edge and excluding held completion. They are uncalibrated model outputs. Duplicated SM-local services, private caches, two contexts per SM, one serialized backing gateway and inherited service delays are hypotheses. Cache state and provider phase change between launches, so the comparison does not isolate a physical cache effect or predict RTX multi-SM scaling. Physical counts remain eight identified, 32 partial and 94 unknown.

The [connected-round record](../../discovery_rounds/multi_sm_connected.json) records the model update and remaining shared-cache and timing gaps.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_resident_gemm_multi_sm.py`.

**Inline behavior.**


**Source implementation:** [resident_gemm_multi_sm.sv](../../numerical/resident_gemm_multi_sm.sv)

### Implementation 55: Multi-SM grids with shared read-only reuse

**Organization.** The [L2-enabled multi-SM controller](../../numerical/resident_gemm_multi_sm_l2.sv) preserves two modeled SMs with two resident contexts each and their private 64 KiB input caches. Reads leaving those private caches share section 4.54's single cache after common gateway ownership. Output writes bypass the shared cache. Global dispatch, ordinal completion bookkeeping, actual store acknowledgments and final zero-residency completion retain section 4.53's contracts. The system now has executable shared read reuse; its cache hierarchy and capacities are not identified RTX microarchitecture.

The [current grid receipt](../../numerical/resident_multi_sm_l2_verification.json) checks 24,576 final FP32 outputs: two full M64/N96 grids at K64 and two at K1536. Each launch has six disjoint output blocks and 6,144 exact expectations from the independent full integer dot product. Both SMs execute work and peak residency reaches four blocks. Four invalid-C launch cases are rejected; captured bases and held completion are checked. Reset coverage remains the first pending input read, not output stores. A/B remain immutable across repeated launches. Partial blocks, the original large grid and arbitrary overlapping output launches are outside current verification.

The following counters are **cumulative since reset**, rather than per-launch traffic:

| Reduction and observation | Cumulative requests | Cumulative hits | Cumulative misses |
|---|---:|---:|---:|
| K64 first launch | 1,280 | 640 | 640 |
| K64 repeated launch | 1,280 | 640 | 640 |
| K1536 first launch | 30,720 | 3,938 | 26,782 |
| K1536 repeated launch | 61,440 | 7,875 | 53,565 |

The unchanged K64 counts show that private-cache replay produces no new ownership-to-shared-cache requests in this model. K1536 counts reflect this declared geometry and request ordering only; they do not establish physical hit rates, cache mapping or replacement policy. Backing fills contain real data, so reuse affects values through executable cache state rather than a fitted hit fraction.

| Reduction length | First launch model cycles | Repeated launch model cycles |
|---|---:|---:|
| K64 | 26,283 | 17,862 |
| K1536 | 457,918 | 457,947 |

These clock-edge counts include the final RUN drain-check edge and freeze during held completion. They are uncalibrated model outputs. Added cache-handshake work, provider phase and reuse interact, so the numbers do not isolate a physical cache effect or predict GPU speedup. Physical counts remain eight identified, 32 partial and 94 unknown; no field is closed by local integration.

The [connected-round record](../../discovery_rounds/shared_l2_connected.json) records the shared-cache model update, traffic checks and remaining concurrency and timing gaps.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_resident_gemm_multi_sm_l2.py`.

**Inline behavior.**


**Source implementation:** [resident_gemm_multi_sm_l2.sv](../../numerical/resident_gemm_multi_sm_l2.sv)

### Implementation 57: Multi-SM grids with overlapping shared-cache requests

**Organization.** The [nonblocking grid top](../../numerical/resident_gemm_multi_sm_nb_l2.sv) preserves two modeled SMs/two contexts each, private input caches, shared native services within each SM, and the whole-grid ownership ledger. Its common memory component is section 4.56 rather than the serialized gateway. Output writes bypass the read-only data cache but occupy owner records and require actual acknowledgment. The independent backing provider used for verification has four tagged records and permits out-of-order returns. None of these capacities establishes physical RTX backing concurrency.

The [current full-grid receipt](../../numerical/resident_multi_sm_nb_l2_verification.json) checks 24,576 final words: two complete M64/N96 grids at each K64/K1536, using the independent full integer-dot-product oracle. Peak residency is four blocks, and all four invalid-C launch cases are rejected. Captured launch bases and held completion are checked; reset coverage remains only the first pending input read. Output-store reset, the original large grid, partial blocks and coherence are not verified.

Cache counters below are cumulative since reset, including both launches:

| K and observation | Requests | Hits | Logical misses | Merged misses | Actual fills |
|---|---:|---:|---:|---:|---:|
| K64 first | 1,024 | 264 | 760 | 120 | 640 |
| K64 repeated | 1,280 | 520 | 760 | 120 | 640 |
| K1536 first | 33,792 | 5,140 | 28,652 | 4,076 | 24,576 |
| K1536 repeated | 67,584 | 10,283 | 57,301 | 8,149 | 49,152 |

For example, the first K64 observation has 760 logical misses but only 640 fills because 120 requests join outstanding sectors. This is executable sharing of actual returned data, not a fitted hit fraction. The request ordering and private-cache state also change which reads reach this layer; comparisons with earlier model variants do not isolate physical cache behavior.

| Reduction length | First launch model cycles | Repeated launch model cycles |
|---|---:|---:|
| K64 | 26,731 | 16,154 |
| K1536 | 582,963 | 583,000 |

The accepted-launch-to-registered-completion counter includes the final drain-check edge and freezes while completion is held. These are uncalibrated model results. More outstanding state does not guarantee fewer model cycles, and these values do not predict GPU scaling. Physical evidence remains eight identified fields, 32 partial and 94 unknown.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_resident_gemm_multi_sm_nb_l2.py`.

**Inline behavior.**


**Source implementation:** [resident_gemm_multi_sm_nb_l2.sv](../../numerical/resident_gemm_multi_sm_nb_l2.sv)

### C++ component adapters

- [block_allocator](../../cpp/block_allocator.hpp) — adapter for [the matching Verilog source](../../components/library/block_allocator.sv).
- [allocation_demands](../../cpp/allocation_demands.hpp) — adapter for [the matching Verilog source](../../components/allocation_demands.sv).
- [quantized_block_admission](../../cpp/quantized_block_admission.hpp) — adapter for [the matching Verilog source](../../components/quantized_block_admission.sv).
- [studied_gemm_grid_controller](../../cpp/studied_gemm_grid_controller.hpp) — adapter for [the matching Verilog source](../../numerical/studied_gemm_grid_controller.sv).
- [resident_native_stage_engine](../../cpp/resident_native_stage_engine.hpp) — adapter for [the matching Verilog source](../../numerical/resident_native_stage_engine.sv).
- [resident_stage_admission](../../cpp/resident_stage_admission.hpp) — adapter for [the matching Verilog source](../../numerical/resident_stage_admission.sv).
- [studied_output_scratch_shared](../../cpp/studied_output_scratch_shared.hpp) — adapter for [the matching Verilog source](../../numerical/studied_output_scratch_shared.sv).
- [resident_gemm_complete](../../cpp/resident_gemm_complete.hpp) — adapter for [the matching Verilog source](../../numerical/resident_gemm_complete.sv).
- [resident_gemm_grid](../../cpp/resident_gemm_grid.hpp) — adapter for [the matching Verilog source](../../numerical/resident_gemm_grid.sv).
- [resident_gemm_multi_sm](../../cpp/resident_gemm_multi_sm.hpp) — adapter for [the matching Verilog source](../../numerical/resident_gemm_multi_sm.sv).
- [resident_gemm_multi_sm_l2](../../cpp/resident_gemm_multi_sm_l2.hpp) — adapter for [the matching Verilog source](../../numerical/resident_gemm_multi_sm_l2.sv).
- [resident_gemm_multi_sm_nb_l2](../../cpp/resident_gemm_multi_sm_nb_l2.hpp) — adapter for [the matching Verilog source](../../numerical/resident_gemm_multi_sm_nb_l2.sv).

## 9. Verification and evidence

Retain the verification expectations and existing receipts in Section 8. The [integration and verification chapter](../integration_and_verification.md) separates existing numerical tests, new C++ smoke tests and GPU measurements. The most recent connected-grid receipt checks 24,576 output words; it does not calibrate the integrated cycle count.

## 10. Optimization implications and remaining gaps

Residency changes how much work can overlap. MIP decisions may select tile/resource demands and block assignment, subject to rounded register/shared limits. The current dispatch policy is a model choice, not recovered GPU scheduling.

A parameter checked through documentation or a transferred prior can be used provisionally. Refine it when a new end-to-end case disagrees materially or when it changes the optimization choice. Do not spend time recovering a private property that the supported execution path does not exercise.
