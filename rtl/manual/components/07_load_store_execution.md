# 07. Load/store execution

[System specification and chapter index](../../rtl_microarchitecture_spec.md) · [Approved manual structure](../../hardware_manual_structure.md)

## 1. Purpose and boundary

Load/store execution converts lane addresses into requests and converts returned sectors into lane values. Stores carry word masks and remain outstanding until acknowledged.

This is a specification of the executable reconstruction. Statements about physical RTX 5090 hardware retain their source or measurement scope; helper defaults describe model configurations.

## 2. Quantitative parameters

The table assigns this chapter ownership of the following inventory entries. “Baseline” preserves the existing setting; the evidence check may instead support a scoped alternative. Source priors are usable provisional estimates, not measurements of a private circuit.

| ID | Definition | Baseline | Unit | Recorded basis | Initial check |
|---|---|---|---|---|---|
| F036 | The number of load instructions or requests that can wait in the load queue. | 16 | load entries per partition | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F037 | The number of store instructions or requests that can wait in the store queue. | 8 | store entries per partition | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F038 | The maximum unfinished memory requests allowed for one warp. | 8 | outstanding memory instructions per warp | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F039 | The maximum unfinished memory requests allowed across one SM. | 64 | outstanding requests per SM | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F040 | How active lane addresses and access widths form memory sectors or transactions. | global coalescing uses touched 32-byte segments of enabled lanes; shared uses supported measured package rules | policy | ENGINEERING_ASSUMPTION | Scoped source or observation |
| F041 | Which reads, writes and fences must become visible before other operations proceed. | preserve program dependencies and explicit scoped fences; permit independent request completion out of order | policy | ENGINEERING_ASSUMPTION | Scoped source or observation |
| F042 | How returned memory pieces become destination-register values for each lane. | little-endian assembly; s8/s16 sign extension; unsigned narrow zero extension; b32 bit preservation | policy | KNOWN_SOURCE | Scoped source or observation |
| T020 | Number of warp load instructions accepted per cycle on a specified path; excludes waiting for their data. | Not specified | warp load instructions per partition per SM cycle | partially_identified | GPU contract or effective path |
| T021 | Number of warp store instructions accepted per cycle on a specified path; excludes waiting for visibility or acknowledgment. | Not specified | warp store instructions per partition per SM cycle | unidentified | GPU contract or effective path |
| T022 | Number of loaded bytes delivered from the load/store path to consumers per cycle; excludes request acceptance and cache-hit rates. | Not specified | return bytes per partition per SM cycle | unidentified | Transferred simulator prior |
| T023 | Time from an accepted store to a specified observer being able to read its value; the observer and memory scope must be stated. | Not specified | SM cycles to shared-store visibility; global modeled by memory service completion | unidentified | GPU contract or effective path |

Use the [complete parameter table](../../parameter_master_table.md) for values, scope, evidence links and provisional alternatives. Device capacities are centralized in the system specification. Per-module tables below identify which parameters are actually consumed by each implementation.

## 3. Interfaces and transaction ownership

Lane addresses → 32-byte sector requests → tagged returns → lane assembly or acknowledged write. The token transaction queue has no numerical coalescing; the numerical warp adapters implement bounded load/store families.

The exact port names, directions, widths and acceptance rules are listed in the implementation contracts in Section 8 and their linked sources. A connection must preserve both payload and ownership while stalled. The common system protocol applies unless a module contract explicitly states a pulse-only interface.

## 4. State and storage

Each linked module contract specifies its arrays, counters, masks, pointers or state machine. Those fields belong to that implementation only. A primitive helper is not an additional copy of a hardware resource inside the connected top unless that top instantiates it. Reset removes outstanding model ownership according to the specified contract; physical power-on behavior is outside this model.

## 5. Functional transitions

The load adapter groups participating lane words by sector and assembles the returned data using the original lane mapping. The store adapter constructs eight-word sectors and masks. Disjoint output regions avoid a general coherence protocol.

Requests are accepted only when the named receiver permits acceptance. Completion must update the original owner before resources are released. The implementation contracts below describe each state transition and numerical transformation separately.

## 6. Timing and arbitration

Use completion latency, acceptance interval and queue capacity as three distinct quantities: when a result becomes available, how often a new request can start, and how many requests can remain pending. The per-module timing contract gives their actual code meaning.

For a held-response interface, observe a valid response after an edge, hold readiness low for one more edge, and verify that identity and data remain unchanged. Retirement occurs only on a later edge with both valid and ready. A receiver becoming free after an edge does not retroactively accept a request at that edge.

## 7. Invariants and failure handling

Pending identities must be unique within their routing domain. A return must match an outstanding request. Request acceptance and store acknowledgement are separate events; a block cannot retire merely because its store was submitted.

Unsupported configurations must remain explicit. A passing test of a helper establishes its tested model contract, not a GPU-wide hardware policy.

## 8. Linked implementations and detailed contracts

The following contracts retain the quantitative organization, exact interfaces, state transitions and verification scope of the existing implementations. Verilog stays in separate source files. C++ adapters expose the same generated ports and clock behavior; they do not introduce independent timing constants.

### Implementation 7: Load/store outstanding transactions

**Role.** Tracks accepted transaction identities until their timed completion can be returned. It provides finite outstanding capacity and response backpressure. The caller must first construct transactions from actual lane accesses and associate them with parent instructions.

**Quantitative configuration.** `SLOTS`, `LATENCY`, and `INTERVAL` must be supplied for the studied path. Measured response groups of four loads cost 399.426 cached or 1,015.362 cold cycles in one probe, including non-load work.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| SLOTS | 4 | transactions | Positive | Baseline; actual queues unknown |
| LATENCY | 1 | cycles | Positive | Baseline; real completion should use return events |
| INTERVAL | 1 | cycles/acceptance | Positive | Baseline |
| Transaction identity | 32 | bits | Maintain consumer/byte-mask mapping | Interface choice |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| req_valid / req_ready | input / output | Request present / receiver permits acceptance. |
| req_id | input, 32-bit transaction identity | Operation or transaction identity retained until return. |
| rsp_valid / rsp_ready | output / input | Completed response present / consumer permits retirement. |
| rsp_id | output, same identity | Identity of the completed operation or transaction. |

**Interface protocol.** Caller maintains the mapping from transaction identities to their instruction consumers and byte masks.

**Stored state.** Inherited bounded FIFO state.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| Inherited timed_queue arrays | Configured by SLOTS | Transaction storage and completion |

**Reset and cycle transitions.** Reset clears outstanding transactions. Accepted transactions reserve capacity; responses retain their identity until acknowledged.

**Invariants and failure handling.** No silent transaction loss; no acceptance beyond queue capacity. Do not assume one warp instruction equals one transaction.

**Linked behavioral implementation.**


**Source implementation:** [transaction_queue.sv](../../components/library/transaction_queue.sv)


**Verification expectation.** Queue primitive capacity and backpressure passed; instruction/transaction assembly is not implemented.

**Unimplemented or unidentified.** Coalescing, store visibility, instruction-to-transaction expansion, actual load/store queue depths, and return assembly are missing. Compound group timings are not hardware queue depths or single-load delays.

### Implementation 38: Coalesced 32-lane BF16 global reads

**Purpose.** The [coalesced load module](../../numerical/coalesced_u16_warp_load.sv) obtains up to 32 aligned 16-bit values while requesting each distinct 32-byte sector once per warp request. For example, 32 contiguous BF16 values occupy 64 bytes and need two sectors; 32 lanes reading the same halfword need one. This implements functional request grouping without asserting the GPU’s physical issue rate or number of concurrent memory requests.

**Ports and state.** An accepted request captures a 32-bit ID, 32 byte addresses and a 32-bit active mask. Only active addresses must be even. The response supplies 32 halfwords, the retained ID and the number of unique sectors; inactive lanes return zero. Backing interfaces carry actual ID-matched 256-bit packets through the cache in section 4.25. `SETS = 64` and `WAYS = 8` are configurable hypotheses. One warp is outstanding.

IDLE constructs a list of unique sectors in first-lane order. SEND offers one cache request; WAIT_PACKET accepts its actual response and extracts the relevant halfwords. A halfword at byte offset 30 uses the final 16 bits of the packet, so no aligned value crosses a sector boundary. The next sector starts only after the current packet completes. An empty mask enters RESPONSE without cache traffic. Returned values remain stable under backpressure. Reset cancels outstanding work, and the provider must discard pre-reset returns. Cached backing data must remain immutable between requests unless the cache is reset.

**Verification and timing boundary.** The [standalone receipt](../../numerical/coalesced_u16_warp_load_verification.json) checks 224 lane values across seven cases: contiguous input, cached replay, broadcast, eight-sector scatter, 32-sector scatter, a partial mask and an empty mask. Their unique-sector counts are 2, 2, 1, 8, 32, 1 and 0. Alignment and wrong completion IDs are rejected. The connected CTA verification in section 4.34 then checks the original full reduction and output stores. Serial unique-sector service, a blocking cache and ideal vector shared commits are implementation choices. They do not establish hardware queue capacities, coalescing latency or physical runtime accuracy, and no parameter closure is added.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_coalesced_u16_warp_load.py` for the standalone check. Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_studied_gemm_cta.py --native-stage --coalesced-staging` for the connected original CTA.

**Inline behavior.**


**Source implementation:** [coalesced_u16_warp_load.sv](../../numerical/coalesced_u16_warp_load.sv)

### Implementation 39: Masked sector writes from 32 FP32 lane values

**Purpose and interface.** The [coalesced store module](../../numerical/coalesced_fp32_warp_store.sv) groups up to 32 aligned 32-bit stores into unique 32-byte sectors. An accepted request captures a 32-bit ID, 32 byte addresses, 32 FP32 words and an active-lane mask. Each outgoing sector contains a 256-bit packet and an eight-bit word mask. The backing provider updates only the selected words, leaving every unselected word unchanged. A matching acknowledgment is required before another sector advances; a final response with the original request ID means all selected sector writes have been acknowledged.

Active addresses must be divisible by four and distinct. Duplicate active addresses are rejected even if values agree: this is the simulator’s explicit no-race policy, not a recovered NVIDIA restriction. Inactive addresses are ignored. An empty mask produces a completion without writing memory. The module has no adjustable queue capacity or fitted physical latency; it serializes sectors with one outstanding acknowledgment.

**Behavior and reset.** IDLE groups and snapshots the entire accepted payload. SEND holds the sector address, data, mask and ID until accepted. WAIT_ACK consumes only an ID-matched acknowledgment, then either advances to the next sector or enters RESPONSE. RESPONSE holds completion under backpressure. Reset cancels pending work and requires the provider to discard old acknowledgments. It does not undo writes that the provider has already committed. There is no write cache, external coherence or inferred DRAM persistence guarantee.

**Original output layout.** The controller’s optional `COALESCED_OUTPUT = 1` mode uses this interface instead of scalar output stores. The original kernel first places matrix results in row-major shared scratch, then each lane reads scratch element `lane + 32 × iteration` for its global store. The controller gathers those same values directly from the measured accumulator layout. In direct-gather mode it therefore preserves output addresses and values but bypasses scratch stores, scratch reads and the intervening synchronization. Section 4.41’s optional scratch mode restores the stored/read values while retaining an assumed stronger phase fence. For the 32 × 32 CTA, four 16 × 16 fragments issue eight warp requests each: 32 warp requests, 128 sector packets and 1,024 words. The provider’s actual acknowledgment, rather than a timestamp, controls progress. This is not native output-path timing replay.

**Independent verification.** The [standalone receipt](../../numerical/coalesced_fp32_warp_store_verification.json) compares 20,480 memory words, including untouched words, across five address/mask cases with 4, 8, 32, 1 and 0 sectors. A separate direct lane-update oracle supplies expected memory contents. The tests include payload changes after acceptance, held requests and acknowledgments, reset, and rejection of misalignment, duplicate active addresses and wrong acknowledgment IDs. These checks establish masked updates and completion ordering, not hardware throughput or cache policy.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_coalesced_fp32_warp_store.py` for the component checks. The connected controller command adds `--coalesced-output` to the native/coalesced-input mode.

The [connected original-CTA receipt](../../numerical/studied_gemm_cta_coalesced_output_verification.json) adds 5,120 exact final-output comparisons through coalesced input staging, the native operand window and these masked output packets. Each launch verifies 128 packet acknowledgments for all 1,024 output values, including the full K1536 first CTA. No hardware timing or additional physical parameter is identified.

**Inline behavior.**


**Source implementation:** [coalesced_fp32_warp_store.sv](../../numerical/coalesced_fp32_warp_store.sv)

### Implementation 41: Original output values through committed shared scratch and reads

**Question and role.** Does global output come from the values that were actually stored in shared scratch and returned by its read service? The [output-scratch component](../../numerical/studied_output_scratch_pipeline.sv) restores that data path. It accepts the four fragments’ native accumulator words, commits them into row-major scratch, then obtains the 32-lane groups used by global stores through actual shared-read responses. Global store payloads no longer bypass those intermediate values in the enabled mode.

The saved original epilogue has four `STS.64` groups per warp at instruction addresses 0x17c0, 0x1810, 0x1850 and 0x1880. They carry accumulator pairs 0/1, 2/3, 4/5 and 6/7 respectively. The model preserves those groups and the measured C element mapping. It does not replay their encoded issue controls or infer a physical 64-bit store latency. All four warps finish all stores before any scratch read begins: a deliberate whole-phase visibility fence, stronger than the original per-warp synchronization.

| Interface or state | Quantitative content | Contract |
|---|---|---|
| Request | 32-bit ID; C registers `[4][32][8]`, 32 bits each; valid/ready | One batch accepted while idle; all C values captured on acceptance |
| Response | Retained ID; `row_major_words[4][256]`, 32 bits each; valid/ready | Visible after all actual scratch reads complete; stable until accepted |
| Scratch storage | 1,024 FP32 words, 4,096 bytes; one initialization bit per word | Every returned coordinate must have been committed in this batch |
| Pending store group | 64 word addresses/data entries and pending bits | One group contains two FP32 words from each of 32 lanes |
| Read service | One separate scalar shared-read instance; four slots by default | Each accepted read captures actual scratch values and returns 32 words |
| Diagnostics | Store-group count, committed-word count, read-request count, read-completion count | A completed batch has 16, 1,024, 32 and 32 respectively |
| Reset | Synchronous reset of state, scratch and read child | Cancels partial work; no old response is produced |

**State, bank work and ordering.** IDLE captures C and clears initialization. STORE_PREP constructs one native-shaped pair group using the measured accumulator-to-element mapping. STORE_SERVICE selects at most one pending word per modeled bank and commits the selected words. A bank is the scratch word index modulo 32. STORE_RETURN applies the configured completion delay, then advances to the next pair or warp. Only after all 16 groups and all 1,024 words are committed can READ_SEND begin.

For this mapping, each 64-word pair group uses 16 banks with four distinct words per bank. The one-word-per-bank rule therefore needs four store packages per group, or 64 packages for all 16 groups. For example, scratch word indices 0, 32, 64 and 96 all select bank zero and must be committed in separate packages under that rule. This is a quantitative consequence of the model’s assumed write service, not an independently measured RTX `STS.64` work or timing rule.

There are eight row-major read groups per warp. Group iteration `j` requests element `lane + 32 × j`; each of the 32 lanes reads one actual initialized word. READ_WAIT uses the ID-matched read response to fill the corresponding row-major result entries. It advances only after completion, so reads are serial even though the child service has configurable capacity. RESPONSE holds all four fragments until acknowledged. Mutating input C after acceptance cannot change the captured batch.

**Timing and resource boundary.** Default store package interval and return delay are both one cycle. Read capacity is four, with interval/return delay 1/1. All are development settings. The separate output and operand arrays total 8,192 logical bytes in the model; they do not reproduce the kernel’s original shared allocation, reserved prefix, phase reuse or occupancy. The scratch read service is a different instance from the operand read service. The controller runs the entire output phase only after all operand work has drained, so the implementation makes no claim that two independent shared services operate concurrently on an SM. Actual WARPSYNC arrival semantics and shared-store/read overlap remain absent.

**Verification.** The [component receipt](../../numerical/studied_output_scratch_verification.json) compares 4,096 returned words against coordinate-specific FP32 identities. Two settings use synthetic store/read delays 7/11 and 19/23 with read capacities one and two. It checks captured input values, all-word visibility before the first read, exact 16/1,024/32/32 counts, held responses, reset during partial stores and replay. The [connected receipt](../../numerical/studied_gemm_cta_output_scratch_verification.json) adds 5,120 original first-CTA output comparisons, including K1536, after those actual scratch returns feed masked global stores. Every launch waits for all 128 global packet acknowledgments. These receipts retain their tested component/controller versions; the later dynamically addressed controller is covered by section 4.43’s current grid and CTA regression receipts. No physical parameter is newly identified, and no hardware runtime accuracy is established.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_studied_output_scratch.py` for the component. Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_studied_gemm_cta.py --output-scratch` for the connected original CTA; that option enables the required four-warp/coalesced modes.

**Inline behavior.**


**Source implementation:** [studied_output_scratch_pipeline.sv](../../numerical/studied_output_scratch_pipeline.sv)

### C++ component adapters

- [transaction_queue](../../cpp/transaction_queue.hpp) — adapter for [the matching Verilog source](../../components/library/transaction_queue.sv).
- [coalesced_u16_warp_load](../../cpp/coalesced_u16_warp_load.hpp) — adapter for [the matching Verilog source](../../numerical/coalesced_u16_warp_load.sv).
- [coalesced_fp32_warp_store](../../cpp/coalesced_fp32_warp_store.hpp) — adapter for [the matching Verilog source](../../numerical/coalesced_fp32_warp_store.sv).
- [studied_output_scratch_pipeline](../../cpp/studied_output_scratch_pipeline.hpp) — adapter for [the matching Verilog source](../../numerical/studied_output_scratch_pipeline.sv).

## 9. Verification and evidence

Retain the verification expectations and existing receipts in Section 8. The [integration and verification chapter](../integration_and_verification.md) separates existing numerical tests, new C++ smoke tests and GPU measurements. The most recent connected-grid receipt checks 24,576 output words; it does not calibrate the integrated cycle count.

## 10. Optimization implications and remaining gaps

Addresses and masks determine transaction counts. Bound outstanding work by modeled ownership/queue capacity; a guessed per-warp transaction cap is not a documented hardware fact.

A parameter checked through documentation or a transferred prior can be used provisionally. Refine it when a new end-to-end case disagrees materially or when it changes the optimization choice. Do not spend time recovering a private property that the supported execution path does not exercise.
