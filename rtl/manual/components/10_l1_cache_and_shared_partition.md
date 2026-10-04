# 10. L1 cache and shared partition

[System specification and chapter index](../../rtl_microarchitecture_spec.md) · [Approved manual structure](../../hardware_manual_structure.md)

## 1. Purpose and boundary

L1 caching retains local data near an SM. Shared-memory configuration competes for the documented combined storage budget, while cache policies and capacity determine hit behavior.

This is a specification of the executable reconstruction. Statements about physical RTX 5090 hardware retain their source or measurement scope; helper defaults describe model configurations.

## 2. Quantitative parameters

The table assigns this chapter ownership of the following inventory entries. “Baseline” preserves the existing setting; the evidence check may instead support a scoped alternative. Source priors are usable provisional estimates, not measurements of a private circuit.

| ID | Definition | Baseline | Unit | Recorded basis | Initial check |
|---|---|---|---|---|---|
| F054 | The usable L1 data capacity under the selected shared-memory partition. | 65536 | usable L1 bytes/SM | ENGINEERING_ASSUMPTION | GPU contract or effective path |
| F055 | The number of independently indexed L1 cache groups. | 64 | sets/SM | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F056 | The number of L1 lines allowed in each indexed group. | 8 | ways/set | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F057 | The function assigning a memory address to an L1 group and tag. | set=(byte_address//128)%64 | mapping rule | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F058 | The rule choosing an L1 line to evict when its group is full. | pseudo-LRU per set | replacement policy | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F059 | Whether stores allocate, update or bypass L1 and when modified data leaves it. | Global store bypasses L1; no write allocation | write policy | ENGINEERING_ASSUMPTION | Scoped source or observation |
| F060 | The number of different L1 misses that can remain unfinished. | 64 | pending distinct L1 misses/SM | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F061 | When consumers of the same missing L1 data share one fetch. | Merge identical 32-byte sectors into one pending fetch; retain all consumers | merge policy | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F062 | The numbers of returned L1 fills and consumer replies that can wait in queues. | {"fill_entries":32,"return_entries":64} | queue entries/SM | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| T031 | Time for a load whose data is already in L1 to return; observed dependent chains also include issue, address work and wakeup. | Not specified | SM-reference cycles | partially_identified | GPU contract or effective path |
| T032 | Time from accepting an L1-path write to its chosen local service-completion point; excludes downstream DRAM persistence. | Not specified | SM-reference cycles | unidentified | Transferred simulator prior |
| T033 | Number of bytes served from L1 per cycle under a stated access pattern; achieved rates do not identify physical cache ports. | Not specified | bytes/SM-reference cycle | unidentified | Transferred simulator prior |
| T034 | Time from a lower-level return reaching the L1 refill path to that data being installed or forwarded; excludes the lower-level lookup. | Not specified | SM-reference cycles | unidentified | Transferred simulator prior |

Use the [complete parameter table](../../parameter_master_table.md) for values, scope, evidence links and provisional alternatives. Device capacities are centralized in the system specification. Per-module tables below identify which parameters are actually consumed by each implementation.

## 3. Interfaces and transaction ownership

Local sector lookup → cached data or backing request → staging completion. The original blocking tag-only cache is a prototype; sector caches carry actual data. The connected model uses configured per-SM cache geometry, not a measured physical set map.

The exact port names, directions, widths and acceptance rules are listed in the implementation contracts in Section 8 and their linked sources. A connection must preserve both payload and ownership while stalled. The common system protocol applies unless a module contract explicitly states a pulse-only interface.

## 4. State and storage

Each linked module contract specifies its arrays, counters, masks, pointers or state machine. Those fields belong to that implementation only. A primitive helper is not an additional copy of a hardware resource inside the connected top unless that top instantiates it. Reset removes outstanding model ownership according to the specified contract; physical power-on behavior is outside this model.

## 5. Functional transitions

A hit supplies retained data according to its modeled timing. A miss waits for the configured return path. Reset invalidates tags. Replacement and write policy must be read from the selected implementation, not inferred from an unrelated helper.

Requests are accepted only when the named receiver permits acceptance. Completion must update the original owner before resources are released. The implementation contracts below describe each state transition and numerical transformation separately.

## 6. Timing and arbitration

Use completion latency, acceptance interval and queue capacity as three distinct quantities: when a result becomes available, how often a new request can start, and how many requests can remain pending. The per-module timing contract gives their actual code meaning.

For a held-response interface, observe a valid response after an edge, hold readiness low for one more edge, and verify that identity and data remain unchanged. Retirement occurs only on a later edge with both valid and ready. A receiver becoming free after an edge does not retroactively accept a request at that edge.

## 7. Invariants and failure handling

Inputs are immutable in the supported GEMM tests. Configuration preference is not a guarantee of exact physical carveout. The 8 KiB dependent .ca test measured about 43.21 cycles; its scope is the full tested path.

Unsupported configurations must remain explicit. A passing test of a helper establishes its tested model contract, not a GPU-wide hardware policy.

## 8. Linked implementations and detailed contracts

The following contracts retain the quantitative organization, exact interfaces, state transitions and verification scope of the existing implementations. Verilog stays in separate source files. C++ adapters expose the same generated ports and clock behavior; they do not introduce independent timing constants.

### Implementation 10: Read-cache building block for L1 and L2

**Role.** Performs set/tag lookup on a 32-byte sector address. It records valid tags and recency. A hit schedules a response after the configured hit delay. A miss replaces a selected entry and schedules a response after the configured miss delay. It blocks further requests until the response retires, making early tag insertion unobservable to another requester.

**Quantitative configuration.** Demonstration geometry is 16 sets × 2 ways × 32 bytes = 1 KiB. Actual L2 capacity is 96 MiB. Documented lines contain four 32-byte sectors; this small sector-tag implementation is a diagnostic approximation, not the recovered tag geometry.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| SETS | 16 | sets | Positive | Baseline; L2 set count unknown |
| WAYS | 2 | ways | Positive | Baseline; L2 associativity unknown |
| Sector/tag unit | 32 | bytes | Set from sector index modulo SETS | Baseline tag approximation |
| Capacity at default | 1,024 | bytes | SETS × WAYS × 32 | Derived baseline, not 96 MiB hardware L2 |
| HIT_DELAY / MISS_DELAY | 1 / 1 | cycles | Positive | Baseline; intrinsic hardware delays unknown |
| Outstanding requests | 1 | request | Blocking until response retirement | Baseline |
| Write policy | Unsupported | policy | No stores accepted | Hardware policy unidentified |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| req_valid / req_ready | input / output | Request present / receiver permits acceptance. |
| byte_address | input, 32 bits | Byte address queried by the timing cache. |
| rsp_valid / rsp_ready | output / input | Completed response present / consumer permits retirement. |
| hit | output, one bit | Whether the accepted read found a valid tag. |
| response_address | output, 32 bits | Original address returned as identity; not fetched data. |

**Interface protocol.** Blocking read-only timing cache. response_address identifies the request; it is not fetched memory data.

**Stored state.** Tag, valid bit and recency timestamp per set/way; occupied bit, delay countdown, hit flag and response address.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| tags / age | SETS × WAYS × signed 32 bits each | Address identity and recency |
| valid | SETS × WAYS bits | Allocated tag state |
| occupied / remaining / response_address / hit | 1 / signed 32 / 32 / 1 bits | Blocking transaction state |

**Reset and cycle transitions.** Reset invalidates entries. Accepted lookup chooses set/tag from 32-byte sector index. Hit updates recency; miss replaces an entry. Hold the response until acknowledged. Further lookups are blocked during the whole request.

**Invariants and failure handling.** No concurrent pending lookup is possible. No dirty write state or external miss transaction exists. Early tag insertion is unobservable because the cache is blocking.

**Operation lifecycle.** These state names summarize the register implementation; they are not additional RTL registers.

| Phase | Trigger | Update/output | Next phase |
|---|---|---|---|
| IDLE | accepted valid-tag lookup | Update recency; schedule hit response | WAIT |
| IDLE | accepted absent-tag lookup | Allocate victim tag; schedule miss response | WAIT |
| WAIT | countdown reaches zero | Assert response-valid | RESPONSE |
| RESPONSE | response accepted | Release transaction | IDLE |

**Linked behavioral implementation.**


**Source implementation:** [read_cache.sv](../../components/library/read_cache.sv)


**Verification expectation.** First access to address 0x100 misses; a later access hits. Passed. This does not test true device cache organization.

**Unimplemented or unidentified.** Instantiate separate configured copies only as explicit L1/L2 hypotheses. L1/shared partition, L2 sets/ways/hash/slices, write-back/write-through behavior, dirty state, asynchronous miss requests, concurrent pending consumers, and fill/return queues are missing. Unlike the earlier monolithic prototype, this blocking component does not exercise overlapping pending hits.

### Implementation 25: Completion-driven numerical sector cache

**Role and configuration.** This separate cache replaces neither the original timing-only read_cache nor the entire GPU hierarchy. It stores actual data under a 128-byte line tag with four independently valid 32-byte sectors. SETS and WAYS are configurable baseline choices; their physical RTX values remain unknown. The directed test uses two sets, one way and one pending request. Requests read one naturally aligned 32-bit word and return both that word and its complete 256-bit sector. The sector output lets a consumer extract multiple requested halfwords from one actual return. Stores, coherence, atomics, concurrent misses and sector-consumer merging are unsupported.

| Interface | Signals and widths | Acceptance/completion rule |
|---|---|---|
| Word request | req_valid/req_ready; req_id and req_byte_address, 32 bits each | Accepted only while idle; address must be divisible by four |
| Word response | rsp_valid/rsp_ready; rsp_id/rsp_data, 32 bits each; rsp_sector_data, 256 bits; rsp_hit, one bit | Word and complete containing sector remain stable until consumed; identifies hit or filled miss |
| Backing sector request | backing_req_valid/backing_req_ready; ID/address, 32 bits each | Address is rounded down to 32 bytes; retained until accepted |
| Backing sector return | backing_rsp_valid/backing_rsp_ready; ID, 32 bits; data, 256 bits | Accepted only while waiting for the matching actual completion |
| Clock/reset | clk/rst, one bit each | Rising-edge updates; synchronous reset cancels pending work and invalidates all sectors |

**Stored state and transitions.** Each set and way owns a line-valid bit, tag, four sector-valid bits and four 256-bit data sectors. A pending record retains the selected set, way, sector, word, ID and tag. IDLE accepts a word request. A valid sector produces a registered response; an absent sector enters SEND, where the backing request remains stable under backpressure. After acceptance, WAIT_RETURN holds the request without producing data. Only an ID-matched backing response writes sector data and its validity bit, then enters RESPONSE. RESPONSE keeps data and ID stable until the consumer accepts them. A full pending slot never accepts a same-edge replacement.

A different sector under an existing tag is still a miss until that sector returns. A new tag clears the victim’s previous sector-valid bits on fill. Selection prefers an invalid way and otherwise uses a rotating victim pointer; this is a model policy, not recovered NVIDIA replacement. Reset discards pending work, and late returns are not accepted while idle. The backing provider must cancel old obligations or retain unique IDs across reset before admitting new work.

**Timing and invariants.** The cache assigns no fitted miss timestamp: its backing component owns miss service and the actual return determines completion. Registered hit response timing is an implementation choice. No RTX lookup latency, queue depth, set count or associativity is inferred. Every accepted request produces one matching response unless reset cancels it; a backing completion with the wrong ID and an unaligned word request terminate simulation.

**Inline behavior.**


**Source implementation:** [sector_read_cache.sv](../../components/sector_read_cache.sv)


**Verification.** Run `python studies/rtx5090_gemm_milp/rtl/components/verify_sector_read_cache.py`. Two different sectors of one line miss separately, then repeated reads hit and return the correct word. Additional checks delay backing acceptance and completion, hold result backpressure, evict the line, cancel a pending request on reset, reject a stale idle return, and check request/response conservation including cancellation. Wrong-ID and unaligned-address controls fail as expected. `components/sector_read_cache_verification.json` preserves source hashes and outputs. This verifies numerical cache behavior and its interfaces; integration with the GPU’s memory controller and physical timing remains incomplete.

### Implementation 26: Connected cached-word staging and numerical matrix execution

**Purpose and scope.** The [cached shared matrix pipeline](../../numerical/cached_shared_matrix_pipeline.sv) connects returned backing-memory data to actual shared-memory values, then to one warp's 16 × 16 × 16 BF16 matrix operation with FP32 accumulation. A backing response carries a complete 32-byte sector. The cache extracts one 32-bit word, and the wrapper writes its two BF16 halfwords into shared storage on successive clock edges. Matrix inputs use the supported LDSM operand mapping described in section 4.21. This is a behavioral integration path; it does not implement the actual cuBLASLt generic `LD.E`/`MOVM` input path, a complete SM, or full-chip scheduling.

**Quantitative starting configuration.** The defaults are 64 sets, eight ways, 128 bytes per cache line and four independently valid 32-byte sectors: 65,536 bytes of cache data. Shared storage has 32,768 bytes. There is one staged word in flight; its 32-bit payload becomes two 16-bit writes. The numerical child allows two outstanding matrix requests. Its default latency is 17 clock cycles and its initiation interval is three cycles. These values are development choices, not calibrated RTX 5090 latencies. Arithmetic mode zero preserves the existing sequential-FP32 reference; mode one selects the experimentally bounded aligned-dot candidate from section 4.16. The arithmetic mode must be selected for its supported input domain.

| Interface | Payload and direction | Acceptance or completion |
|---|---|---|
| Word staging request | Input: 32-bit ID, global byte address and shared byte address | Accepted only when `stage_valid && stage_ready` at a clock edge; global address must be four-byte aligned, shared address two-byte aligned and fit both halfwords |
| Staging completion | Output: 32-bit original ID and cache-hit flag | Held with `stage_done_valid` until `stage_done_ready`; reports completion of both shared writes |
| Backing request | Output: 32-bit ID and sector-aligned byte address | Ready/valid handshake is owned by the completion-driven cache; request remains stable under backpressure |
| Backing return | Input: matching 32-bit ID and 256-bit sector data | Cache fills only after actual response acceptance; provider must retain payload while not ready |
| Matrix request | Input: 32-bit ID; 32 A-row addresses, 32 B-row addresses, and 32 × 8 FP32 accumulator registers | Accepted through the shared/numerical child only when addresses are legal, operands initialized and request capacity available |
| Matrix return | Output: 32-bit ID and 32 × 8 FP32 result registers | Numerical child holds valid ID and values until `rsp_ready` |

**Clocked behavior and ordering.** In `IDLE`, an accepted staging request saves its ID and destination, then enters `LOW_HALF`. That state waits for an actual cache response and writes bits 15:0. `HIGH_HALF` writes bits 31:16 at destination plus two bytes. The cache response is acknowledged only with this second accepted write, so both writes consume one stable word. `DONE` holds the staging completion. After its acceptance, the wrapper returns to `IDLE`. A cache miss therefore cannot produce shared values merely because a guessed delay elapsed.

An accepted staging request wins over a matrix request on the same edge. Matrix admission is blocked while staging or its completion is pending. The shared child reads pre-edge storage, so an operation cannot use a final halfword write on that same edge. Already accepted matrix operations have captured their operands; later staging does not change those operands. This does not implement a hardware-wide ordering rule for arbitrary kernels.

**Reset and protocol obligations.** Reset clears the wrapper, invalidates the cache and shared initialization state, and resets the numerical child. Pending work is canceled. The backing provider must flush pre-reset requests and returns; numeric request IDs do not encode reset generations. A stale response arriving during a new transaction with a reused ID cannot be distinguished by this model. Invalid staging addresses and mismatched active response IDs are fatal protocol errors.

**Verification boundary.** The [connected verification receipt](../../numerical/cached_shared_matrix_verification.json) passes 14,336 FP32 output-word comparisons: 24 sequential-reference cases and four exact-integer identity cases in aligned-dot mode, each with synthetic backing delays of two and 13 cycles. The extra 11 cycles per sector request propagate exactly: 768 requests add 8,448 cycles, and 128 requests add 1,408 cycles. Checks cover initialized-operand gating, sector reuse and request conservation, IDs, held staging and numerical completions, reset invalidation, and rejection of unaligned or wrong-ID requests. Source hashes match the tested sources. This validates the connected numerical fixture and completion-driven timing behavior; it does not establish universal NVIDIA arithmetic, physical cache latency, or independent RTX 5090 runtime accuracy.

**Authoritative behavioral implementation.** The following source is copied exactly from `numerical/cached_shared_matrix_pipeline.sv`.


**Source implementation:** [cached_shared_matrix_pipeline.sv](../../numerical/cached_shared_matrix_pipeline.sv)

### Implementation 45: Two resident load contexts sharing one sector cache

**Role.** The [resident U16 loader](../../numerical/resident_u16_warp_load.sv) keeps two independently accepted warp-load requests while sharing exactly one blocking sector cache. Each request has up to 32 aligned BF16 halfword addresses and an active mask. Context state and returned values are separate; cache sets/ways and backing capacity are not duplicated. This component is not yet connected to section 4.44’s resident compute engine into concurrent full CTAs.

| Interface | Payload and contract |
|---|---|
| Load request | 32-bit context and ID, 32 byte addresses and active mask; accepted only for an idle context with legal active addresses |
| Availability | One ready bit per context; outstanding counts non-idle load contexts |
| Load response | Retained context/ID, 32 halfwords and unique-sector count; held until acknowledged |
| Shared backing | ID-matched 256-bit packets through one cache; actual returns supply the halfwords |
| Reset | Cancels contexts and cache; external provider flushes pre-reset returns |

Each context captures accepted addresses and mask, constructs its unique 32-byte sectors, and progresses through IDLE, SEND, WAIT_PACKET and RESPONSE. A round-robin cache owner is latched before request valid is asserted. This keeps ID/address stable if another context becomes eligible during backpressure. After one actual packet completes, relevant active halfwords are extracted and the cursor can select another context. A separate response owner holds completed values without blocking the other context’s cache progress. Empty masks return zeros without traffic; inactive lanes return zero and their addresses are ignored.

Per-context epochs distinguish reused operations. Default two-context geometry uses six local ID bits for context/sector ordinal and 26 epoch bits. Matching IDs are checked on actual packet return; epochs cannot wrap. Reset resets epochs, so provider flushing is still required. Inputs must remain immutable across cache-preserving requests, or the cache must be reset; no invalidation port is exposed. Defaults of 64 sets/eight ways and serial unique-sector service remain model choices rather than recovered L2 organization or throughput.

The [loader receipt](../../numerical/resident_u16_verification.json) checks 128 lane values against the independently accepted address formula. It covers snapshots, masks/empty requests, cache reuse across contexts, delayed matching packets, held response with other-context progress, reset/provider cancellation and accepted-minus-retired conservation. The saved post-reset fixture makes two backing misses; that is fixture behavior, not a hardware bandwidth result. Frozen source hashes match the receipt. Timing is uncalibrated, and physical evidence remains eight identified fields, 32 partial and 94 unknown.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_resident_u16_warp_load.py`.

**Inline behavior.**


**Source implementation:** [resident_u16_warp_load.sv](../../numerical/resident_u16_warp_load.sv)

### C++ component adapters

- [read_cache](../../cpp/read_cache.hpp) — adapter for [the matching Verilog source](../../components/library/read_cache.sv).
- [sector_read_cache](../../cpp/sector_read_cache.hpp) — adapter for [the matching Verilog source](../../components/sector_read_cache.sv).
- [cached_shared_matrix_pipeline](../../cpp/cached_shared_matrix_pipeline.hpp) — adapter for [the matching Verilog source](../../numerical/cached_shared_matrix_pipeline.sv).
- [resident_u16_warp_load](../../cpp/resident_u16_warp_load.hpp) — adapter for [the matching Verilog source](../../numerical/resident_u16_warp_load.sv).

## 9. Verification and evidence

Retain the verification expectations and existing receipts in Section 8. The [integration and verification chapter](../integration_and_verification.md) separates existing numerical tests, new C++ smoke tests and GPU measurements. The most recent connected-grid receipt checks 24,576 output words; it does not calibrate the integrated cycle count.

## 10. Optimization implications and remaining gaps

Reuse, footprint and partition preference can change staging cost. Exact associativity or replacement need only be refined when current validation contradicts the provisional model.

A parameter checked through documentation or a transferred prior can be used provisionally. Refine it when a new end-to-end case disagrees materially or when it changes the optimization choice. Do not spend time recovering a private property that the supported execution path does not exercise.
