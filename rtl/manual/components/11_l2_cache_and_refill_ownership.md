# 11. L2 cache and refill ownership

[System specification and chapter index](../../rtl_microarchitecture_spec.md) · [Approved manual structure](../../hardware_manual_structure.md)

## 1. Purpose and boundary

The shared L2 gateway retains read sectors and coordinates pending fetches from multiple SMs. A pending miss needs both fetch ownership and consumer ownership; these are separate finite resources.

This is a specification of the executable reconstruction. Statements about physical RTX 5090 hardware retain their source or measurement scope; helper defaults describe model configurations.

## 2. Quantitative parameters

The table assigns this chapter ownership of the following inventory entries. “Baseline” preserves the existing setting; the evidence check may instead support a scoped alternative. Source priors are usable provisional estimates, not measurements of a private circuit.

| ID | Definition | Baseline | Unit | Recorded basis | Initial check |
|---|---|---|---|---|---|
| F063 | The number of independently indexed L2 cache groups per relevant slice. | 1024 | sets/L2 slice | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F064 | The number of L2 lines allowed in each indexed group. | 16 | ways/set | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F065 | The number and organization of independently serviced L2 slices. | {"active_model_slices":48,"nominal_reported_slices":64,"FBPs":8,"nominal_slices_per_FBP":8} | slices; FBPs | ENGINEERING_ASSUMPTION | Scoped source or observation |
| F066 | The function assigning a memory address to an L2 slice. | slice=(byte_address//128)%active_model_slices | mapping rule | ENGINEERING_ASSUMPTION | Scoped source or observation |
| F067 | The function assigning a memory address to an L2 group and tag. | set=(byte_address//(128*active_model_slices))%sets_per_slice | mapping rule | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F068 | The number of L2 tag or data lookups that can proceed together. | 1 | logical lookup requests/slice/reference cycle | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F069 | The rule choosing an L2 line to evict when its group is full. | pseudo-LRU with persisting-line priority when policy enabled | replacement policy | ENGINEERING_ASSUMPTION | Scoped source or observation |
| F070 | Whether stores allocate or modify L2 and how dirty data is propagated. | Write-back/write-allocate; dirty eviction issues DRAM write | write policy | ENGINEERING_ASSUMPTION | Scoped source or observation |
| F071 | The number of different L2 misses that can remain unfinished. | 128 | pending distinct misses/L2 slice | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F072 | When consumers of the same missing L2 sector or line share one fetch. | Merge requests to identical pending 32-byte sector; wake all registered consumers | merge policy | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F073 | The number of incoming L2 requests that can wait for service. | 64 | request queue entries/L2 slice | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F074 | The numbers of L2 fills and consumer replies that can wait in queues. | {"fill_entries":64,"return_entries":64} | entries/L2 slice | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| T035 | Time for a load whose data is already in L2 to return; observed dependent chains also include the surrounding request and consumer path. | Not specified | SM-reference cycles | partially_identified | GPU contract or effective path |
| T036 | Time from accepting a write at L2 to the chosen cache update or acknowledgment point; excludes DRAM persistence unless specified. | Not specified | SM-reference cycles | unidentified | Transferred simulator prior |
| T037 | Number of bytes serviced by one L2 slice per cycle; requires identifying the slice and its clock domain. | Not specified | bytes/SM-reference cycle | unidentified | Transferred simulator prior |
| T038 | Number of bytes returned from L2 toward consumers per reference cycle; excludes request rate and cache-hit fraction. | Not specified | bytes/SM-reference cycle | unidentified | Transferred simulator prior |

Use the [complete parameter table](../../parameter_master_table.md) for values, scope, evidence links and provisional alternatives. Device capacities are centralized in the system specification. Per-module tables below identify which parameters are actually consumed by each implementation.

## 3. Interfaces and transaction ownership

SM requests → shared lookup → hit, merge or new fetch → backing return → consumer response. The nonblocking gateway supports multiple pending fetches and tagged returns; the older shared gateway serializes more work.

The exact port names, directions, widths and acceptance rules are listed in the implementation contracts in Section 8 and their linked sources. A connection must preserve both payload and ownership while stalled. The common system protocol applies unless a module contract explicitly states a pulse-only interface.

## 4. State and storage

Each linked module contract specifies its arrays, counters, masks, pointers or state machine. Those fields belong to that implementation only. A primitive helper is not an additional copy of a hardware resource inside the connected top unless that top instantiates it. Reset removes outstanding model ownership according to the specified contract; physical power-on behavior is outside this model.

## 5. Functional transitions

A hit returns resident data. A matching pending fetch can attach another consumer. A new miss reserves an available fetch entry and safe replacement target. Returned sectors fill the retained line and remain owned until their waiting consumers retire.

Requests are accepted only when the named receiver permits acceptance. Completion must update the original owner before resources are released. The implementation contracts below describe each state transition and numerical transformation separately.

## 6. Timing and arbitration

Use completion latency, acceptance interval and queue capacity as three distinct quantities: when a result becomes available, how often a new request can start, and how many requests can remain pending. The per-module timing contract gives their actual code meaning.

For a held-response interface, observe a valid response after an edge, hold readiness low for one more edge, and verify that identity and data remain unchanged. Retirement occurs only on a later edge with both valid and ready. A receiver becoming free after an edge does not retroactively accept a request at that edge.

## 7. Invariants and failure handling

A pinned victim cannot be reused while a live fetch or consumer needs it. Held responses preserve identity/data. Test geometry is 64 sets × 8 ways × 128 bytes = 64 KiB, distinct from the recorded physical 96 MiB total L2.

Unsupported configurations must remain explicit. A passing test of a helper establishes its tested model contract, not a GPU-wide hardware policy.

## 8. Linked implementations and detailed contracts

The following contracts retain the quantitative organization, exact interfaces, state transitions and verification scope of the existing implementations. Verilog stays in separate source files. C++ adapters expose the same generated ports and clock behavior; they do not introduce independent timing constants.

### Implementation 54: Shared read-only sector cache after gateway ownership

**Placement and geometry.** The [L2 gateway wrapper](../../numerical/multi_sm_l2_gateway.sv) connects modeled SMs → common ownership gateway → one shared read-only sector cache → backing provider. The ownership gateway still permits only one combined read/write transaction through client acknowledgment. Reads access one actual `sector_read_cache`; writes bypass it. Defaults are 64 sets, eight ways and 128-byte lines with four independently valid 32-byte sectors: **64 KiB of modeled data**. This is a development geometry, not the physical RTX L2 capacity.

| Interface or quantity | Contract |
|---|---|
| SM read/write clients | Section 4.52's valid/ready IDs, sector addresses, 256-bit packets and write masks |
| Provider reads | Actual aligned 32-byte requests and matching 256-bit returns on misses |
| Shared-cache response | Whole 256-bit sector and retained internal ID, routed through gateway ownership |
| `l2_read_requests` | Cumulative ownership-to-cache request handshakes since reset |
| `l2_read_hits`/`l2_read_misses` | Cumulative cache-to-ownership response handshakes, classified by returned hit flag |
| Cache pending record | One accepted logical cache read not yet returned to ownership |

Valid-sector hits return stored data. A miss issues a backing-sector request and fills only after the actual matching provider response. The cache returns the full sector packet through the ownership gateway. Independent sector valid bits and replacement follow section 4.25's implemented rules; a requested sector does not imply filling all four sectors of its line.

In the current behavioral cache, an accepted hit makes its registered response available immediately after that edge; ownership can accept it at the next edge. There is no separate calibrated L2 hit-delay parameter here. A miss waits for the provider, then registers its returned packet before ownership can accept it.

Request counters increment at cache acceptance, which is later than the original SM-to-gateway acceptance. Hit/miss counters increment when the cache response is accepted by ownership, even if the gateway must subsequently hold that returned response for its client. Held cache responses do not double-count. The invariant is requests = hits + misses + the pending bit. Counters persist between grid launches and clear on reset; writes never increment these read counters.

The [current L2 unit receipt](../../numerical/multi_sm_l2_gateway_verification.json) checks 40 returned read words, one hit, four misses and four actual backing reads. It checks captured write payloads, delayed provider replies, held client responses, reset/provider flush and wrong-ID rejection. Its read operations are sequential; it does not exhaustively test simultaneous L2 callers. The earlier ownership-gateway unit separately tests multiple-client ownership. The current wrapper also retains one combined transaction limit.

A/B inputs remain immutable and output C is disjoint. There is no write invalidation, dirty data, cross-SM coherence, external invalidation operation or multiple concurrent miss records. Reset cancels cache and gateway state and requires provider flush; it cannot undo committed writes. Shared geometry, replacement, serialization and service timing remain model choices.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_multi_sm_l2_gateway.py`.

**Inline behavior.**


**Source implementation:** [multi_sm_l2_gateway.sv](../../numerical/multi_sm_l2_gateway.sv)

### Implementation 56: Nonblocking shared sector ownership and refill

**Role and quantitative organization.** The [nonblocking read-only cache](../../numerical/multi_sm_nonblocking_l2.sv) replaces the single combined ownership record with multiple live client operations and tagged missing-sector fetches. A miss-status holding register, or MSHR, records one missing sector until its actual provider return. Defaults are two SM clients, **eight owner records and four MSHRs**, with 64 sets/eight ways/128-byte lines/four valid sectors: 64 KiB data. These are development choices, not identified RTX queue capacities or geometry.

| Interface or state | Contract |
|---|---|
| Client read | Per-SM valid/ready, 32-bit ID/address; whole 256-bit response |
| Client write | Per-SM valid/ready, 32-bit ID/address, 256-bit data/eight-bit mask; ID acknowledgment |
| Owner record | Client/read-write identity, external ID, completion state, data and MSHR association or tagged write |
| MSHR | Sector address/internal ID, cache set/way/sector and sent state |
| Reply owner | One retained owner index per SM read client and per SM write client |
| Backing offer | One registered read-or-write payload; multiple previously issued records may remain live |
| Counters | Accepted reads, hits, logical misses, merged misses, actual fills, live/peak owners and MSHRs |

**Acceptance and backpressure.** Round-robin admission accepts at most one client operation per edge. A read needs a free owner and either a valid-sector hit, an existing same-address MSHR to join, or a free MSHR plus an eligible cache way. A blocked read is not captured. Ways with live sector refills are pinned against replacement. Writes require a free owner and capture their payload while bypassing cache data. Read sectors must align to 32 bytes; the current code rejects an asserted unaligned request. Invalid write alignment or zero mask is rejected on acceptance. Duplicate live IDs within one read/write client are rejected; equal IDs across separate clients remain legal.

Hits snapshot sector data at acceptance. Joined misses share one fetch but retain separate owners. A new miss reserves its line/sector and tagged MSHR. Actual provider returns match sent internal IDs, fill only their sector, and copy the packet into all waiting owners. Other sectors do not become valid accidentally. A same-edge joined acceptance and refill explicitly forwards that packet into the newly accepted owner. Unknown, duplicate or unsent return IDs are rejected. Returned MSHRs are freed while completed owners can remain live waiting for their clients.

**Completion timing and ordering.** Each client selects its lowest-index completed owner and retains it under response backpressure, independently of other clients. Owner slots use pre-edge free state; retirement does not create same-edge admission capacity. The backing offer is registered and held until provider acceptance. The next offer is inserted on a later edge, giving a minimum unblocked backing-request initiation interval of **two model cycles**, not one. Sent state is registered, so a provider cannot return a newly accepted backing request on that same edge. Tagged later returns may arrive out of request order. These are simulator scheduling rules, not intrinsic GPU latency.

Read-request and hit/miss counters increment together at actual SM read acceptance; merged misses are included in logical misses. `l2_actual_fills` increments on actual tagged provider returns. Therefore requests = hits + misses at every settled edge; fills count returned fetches rather than client acknowledgments. Held replies never repeat those increments. All counts persist until reset. Reset clears ownership, pending refills and cache validity and requires provider flush before internal ID reuse. Immutable A/B and disjoint C are required: no dirty sectors, write coherence or invalidation are implemented.

The [current unit receipt](../../numerical/multi_sm_nonblocking_l2_verification.json) checks 56 returned words: one hit, six logical misses, two merged misses and four actual fills, plus wrong-return-ID rejection. Its directed operations exercise captured payloads, held client ownership and reset/provider cancellation. Backing arbitration permits at most one combined read/write request acceptance per edge while multiple previously accepted operations remain outstanding. Numerical unit coverage does not identify hardware queues or latency.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_multi_sm_nonblocking_l2.py`.

**Inline behavior.**


**Source implementation:** [multi_sm_nonblocking_l2.sv](../../numerical/multi_sm_nonblocking_l2.sv)

### C++ component adapters

- [multi_sm_l2_gateway](../../cpp/multi_sm_l2_gateway.hpp) — adapter for [the matching Verilog source](../../numerical/multi_sm_l2_gateway.sv).
- [multi_sm_nonblocking_l2](../../cpp/multi_sm_nonblocking_l2.hpp) — adapter for [the matching Verilog source](../../numerical/multi_sm_nonblocking_l2.sv).

## 9. Verification and evidence

Retain the verification expectations and existing receipts in Section 8. The [integration and verification chapter](../integration_and_verification.md) separates existing numerical tests, new C++ smoke tests and GPU measurements. The most recent connected-grid receipt checks 24,576 output words; it does not calibrate the integrated cycle count.

## 10. Optimization implications and remaining gaps

The MIP needs reuse and finite outstanding ownership where these affect costs. Exact physical indexing remains provisional; the model must not convert its synthetic geometry into a claimed 5090 cache organization.

A parameter checked through documentation or a transferred prior can be used provisionally. Refine it when a new end-to-end case disagrees materially or when it changes the optimization choice. Do not spend time recovering a private property that the supported execution path does not exercise.
