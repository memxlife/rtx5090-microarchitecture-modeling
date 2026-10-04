# 09. Shared-memory service

[System specification and chapter index](../../rtl_microarchitecture_spec.md) · [Approved manual structure](../../hardware_manual_structure.md)

## 1. Purpose and boundary

Shared memory stores block-local words and serves requests through a banked organization. Broadcast and conflicting addresses must be distinguished because equal bytes can require different service work.

This is a specification of the executable reconstruction. Statements about physical RTX 5090 hardware retain their source or measurement scope; helper defaults describe model configurations.

## 2. Quantitative parameters

The table assigns this chapter ownership of the following inventory entries. “Baseline” preserves the existing setting; the evidence check may instead support a scoped alternative. Source priors are usable provisional estimates, not measurements of a private circuit.

| ID | Definition | Baseline | Unit | Recorded basis | Initial check |
|---|---|---|---|---|---|
| F048 | The allowed division of on-SM storage between L1 cache and shared memory. | {"shared_KiB":32,"unified_KiB":128,"L1_usable_KiB":64} | KiB/SM | ENGINEERING_ASSUMPTION | GPU contract or effective path |
| F049 | The number of shared-memory reads one bank can serve together. | 1 | 32-bit read ports/bank | ENGINEERING_ASSUMPTION | Numerical model consistency only |
| F050 | The number of shared-memory writes one bank can serve together. | 1 | 32-bit write ports/bank | ENGINEERING_ASSUMPTION | GPU contract or effective path |
| F051 | The number of shared-memory requests that can wait for service. | 32 | warp shared requests/SM | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F052 | How one warp memory operation is divided into smaller service packages. | {"scalar":"maximum distinct words in any bank","vector64":"two 128-byte logical phases","vector128":"four 128-byte logical phases; same-vector reads count occupied 16-lane halves"} | service packages/request | ENGINEERING_ASSUMPTION | GPU contract or effective path |
| F053 | When several lanes reading the same location share one delivered value. | Same-location reads broadcast; independent-bank broadcasts multicast | functional policy | ENGINEERING_ASSUMPTION | GPU contract or effective path |
| T027 | Time from a shared-memory read being accepted to its data returning; existing dependent-chain measurements also include wakeup and scheduling. | Not specified | SM-reference cycles | partially_identified | GPU contract or effective path |
| T028 | Time from a shared-memory write being accepted to the chosen shared-memory completion point; excludes later barrier release. | Not specified | SM-reference cycles | unidentified | Transferred simulator prior |
| T029 | Extra delay caused by several lanes reading the same shared-memory word, relative to a matched ordinary read; excludes their common base delay. | Not specified | SM-reference cycles | unidentified | GPU contract or effective path |
| T030 | Time from a shared-memory result returning to its availability at an instruction’s operand input; excludes the shared read itself. | Not specified | SM-reference cycles | unidentified | Transferred simulator prior |

Use the [complete parameter table](../../parameter_master_table.md) for values, scope, evidence links and provisional alternatives. Device capacities are centralized in the system specification. Per-module tables below identify which parameters are actually consumed by each implementation.

## 3. Interfaces and transaction ownership

Global staging completion → shared writes → barrier → shared-read hub → lane operand completion. The single-bank primitive and the multi-client numerical hub are different implementations.

The exact port names, directions, widths and acceptance rules are listed in the implementation contracts in Section 8 and their linked sources. A connection must preserve both payload and ownership while stalled. The common system protocol applies unless a module contract explicitly states a pulse-only interface.

## 4. State and storage

Each linked module contract specifies its arrays, counters, masks, pointers or state machine. Those fields belong to that implementation only. A primitive helper is not an additional copy of a hardware resource inside the connected top unless that top instantiates it. Reset removes outstanding model ownership according to the specified contract; physical power-on behavior is outside this model.

## 5. Functional transitions

A primitive write updates the addressed word on acceptance and holds its response. Numerical staging commits operand frames before consumption. The read hub routes completed lane values to their owning client; shared-memory ownership is block/context-local.

Requests are accepted only when the named receiver permits acceptance. Completion must update the original owner before resources are released. The implementation contracts below describe each state transition and numerical transformation separately.

## 6. Timing and arbitration

Use completion latency, acceptance interval and queue capacity as three distinct quantities: when a result becomes available, how often a new request can start, and how many requests can remain pending. The per-module timing contract gives their actual code meaning.

For a held-response interface, observe a valid response after an edge, hold readiness low for one more edge, and verify that identity and data remain unchanged. Retirement occurs only on a later edge with both valid and ready. A receiver becoming free after an edge does not retroactively accept a request at that edge.

## 7. Invariants and failure handling

The measured scalar dependency path is 28 cycles for broadcast or conflict-free access, with about two extra cycles per additional distinct word in the busiest bank for the tested pattern. This combined path is not a separately measured SRAM access latency.

Unsupported configurations must remain explicit. A passing test of a helper establishes its tested model contract, not a GPU-wide hardware policy.

## 8. Linked implementations and detailed contracts

The following contracts retain the quantitative organization, exact interfaces, state transitions and verification scope of the existing implementations. Verilog stays in separate source files. C++ adapters expose the same generated ports and clock behavior; they do not introduce independent timing constants.

### Implementation 9: Shared-memory bank

**Role.** Contains actual 32-bit storage words. It accepts a read or write only while idle. A write updates the selected word; a read returns its stored value. Both produce a delayed response, retained until acknowledged. A caller must route each decoded bank request to the appropriate bank instance.

**Quantitative configuration.** `WORDS` is storage per modeled bank and `LATENCY` is response delay. The verified mapping uses 32 banks and four-byte words. Original kernels require 8,192 or 11,264 source-level shared bytes per block; capacity allocation is handled separately.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| WORDS | 64 | 32-bit words/bank | Positive; word index in range | Baseline |
| LATENCY | 1 | cycles | Positive | Baseline; intrinsic shared latency unknown |
| Storage at default | 256 | bytes/bank | WORDS × 4 | Derived baseline |
| Outstanding per bank | 1 | operation | Wait for prior response retirement | Baseline; not measured port capacity |
| Target bank mapping | 32 / 4 | banks / bytes per word | Decode full lane requests upstream | Supported tested ordinary-word mapping |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| req_valid / req_ready | input / output | Request present / receiver permits acceptance. |
| write | input, one bit | One selects write; zero selects read. |
| word_address | input, signed 32-bit index | Local word index within this selected bank. |
| write_data | input, 32 bits | Word to store for a write request. |
| rsp_valid / rsp_ready | output / input | Completed response present / consumer permits retirement. |
| read_data | output, 32 bits | Stored/read response word; meaningful only when response-valid. |

**Interface protocol.** Caller selects a bank and supplies its local word index. For a byte address in the 32-bank baseline, bank = floor(address/4) modulo 32 and local word = floor(address/128). Decode and conflict splitting are upstream.

**Stored state.** WORDS × 32-bit storage; occupied bit, delay countdown and registered response data.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| storage | WORDS × 32 bits | Actual stored words |
| occupied / remaining / read_data | 1 / signed 32 / 32 bits | Response ownership, delay and payload |

**Reset and cycle transitions.** Reset zeroes storage for deterministic tests. On acceptance, read or update the selected word and latch response data. Count down while occupied, then hold response until acknowledgment. A write response echoes its written word.

**Invariants and failure handling.** Only one request is outstanding per bank. A protected reader must not run before required writes complete. Address out of range terminates simulation.

**Operation lifecycle.** These state names summarize the register implementation; they are not additional RTL registers.

| Phase | Trigger | Update/output | Next phase |
|---|---|---|---|
| IDLE | request accepted | Read/write word; latch response; load countdown | WAIT |
| WAIT | countdown reaches zero | Assert response-valid | RESPONSE |
| RESPONSE | response accepted | Release occupied state | IDLE |

**Linked behavioral implementation.**


**Source implementation:** [shared_memory_bank.sv](../../components/library/shared_memory_bank.sv)


**Verification expectation.** Write 0x12345678 to word seven, then read word seven and compare exact data. Passed with LATENCY=3.

**Documented functional boundary.** Same-location shared reads broadcast, and separate-bank broadcasts can multicast. A full-warp decoder must group consumers accordingly; this single-word bank module does not itself perform that grouping. Physical broadcast delay remains unidentified.

**Unimplemented or unidentified.** This bank has one outstanding operation and does not accept another until the response retires. That is a baseline, not identified bank throughput. Full-warp decoding, multiple bank ports, broadcast behavior, buffering, and shared/L1 partition selection are missing.

### Implementation 20: Shared broadcast service-work decoder

**Purpose and supported request.** Count the service packages required by a naturally aligned 128-bit shared-memory read in which every active lane requests the same vector. A service package is the work counted by the profiler's shared-load wavefront metric. The measured count is not an intrinsic instruction latency. This component supplies a work quantity for future shared-service integration; it does not deliver stored operand values or advance a queue.

The first experiment kept the address and instruction fixed and changed the active lanes. Eight neighboring readers required one package, but eight distributed readers required two. A rule based only on bytes or access width therefore fails. The inferred rule counts occupied lane halves: lanes 0–15 and lanes 16–31. Five new masks, measured after freezing that rule, all matched. In particular, lanes 0 and 31 alone require two packages. Evidence is preserved in `parameter_sweep/masked_shared/analysis.json` and `confirmation_analysis.json`.

**Quantitative contract and interfaces.**

| Port or property | Direction or value | Definition |
|---|---|---|
| active_mask | Input, 32 bits | Bit i indicates whether lane i participates |
| common_byte_address | Input, 32 bits | Shared address requested by every participating lane; divisible by 16 |
| address_legal | Output, 1 bit | Address meets the required 16-byte alignment |
| service_packages | Output, 2 bits | 0 for no readers, 1 for one occupied lane half, 2 for both; 0 for illegal alignment |
| Stored state and reset | None | Combinational work calculation |
| Clocked latency | None introduced | No measured result latency or acceptance interval is claimed |

A caller must inspect address_legal before using the work count. Zero output on illegal alignment denotes a rejected request, not a free hardware operation. The caller must also establish that this is a same-vector LDS128 read; the interface cannot check addresses that it never receives. Ordinary vector reads with different addresses, stores, LDSM and cross-warp arbitration are outside the contract.

**Inline behavior.**


**Source implementation:** [shared_broadcast_work.sv](../../components/shared_broadcast_work.sv)


**Verification and limits.** Run `python studies/rtx5090_gemm_milp/rtl/components/verify_shared_broadcast_work.py`. Python and SystemVerilog reproduce the ten measured masks; additional checks cover no active lanes and illegal alignment. The receipt is `components/shared_broadcast_work_verification.json`. The ten observations support an inferred rule for this operation family, rather than an exhaustive test of all masks. They do not identify bank ports, physical queue capacity or cycle cost. F052 remains partially identified, and the rule is not yet connected to the complete GPU model.

### Implementation 31: Completion-driven full-warp scalar shared-read service

**Purpose and operation.** The [shared-read service](../../components/warp_shared_read_service.sv) separates request admission, bank work, return delay and response delivery. One request contains 32 four-byte-aligned addresses, 32 input words and a 32-bit ID. The provider supplies an actual memory-value snapshot when the request is accepted. The service stores that snapshot, consumes the required bank-work packages, waits its configured return delay, then offers the saved words as a completion event. It does not look up shared storage itself.

**Measured work rule versus assumed timing.** For each of 32 banks, count the distinct requested four-byte words. Repeated reads of the same address are a broadcast and count once. The bank index is address bits 6:2. The number of packages is the largest distinct-word count across the banks, from one to 32. This scalar work-count rule is supported by the saved bank probes. It does not identify physical port counts, queue sizes or intrinsic latency.

The default queue holds four requests. A single modeled service port consumes one package per cycle (`SERVICE_INTERVAL = 1`); after the last package, it applies one additional cycle of return delay (`RETURN_DELAY = 1`). Capacity, first-in-first-out arbitration and both cycle settings are explicit engineering hypotheses. Increasing package count consumes more service opportunities; increasing return delay changes completion time separately. No fixed measured load latency is added on top of these hypotheses. For an isolated request accepted at edge `a`, its first package is serviced no earlier than edge `a + 1`. The final package edge starts the return counter; after `RETURN_DELAY` later edges, the response becomes valid. A continuously ready consumer acknowledges it on the following edge. Thus a one-package request with return delay `D` has earliest acknowledgment edge `a + D + 2`. Queue waiting and consumer backpressure can add delay. These edges describe the model contract, not measured GPU cycles.

**Interfaces and state.** Request and response use ready/valid acceptance. The six-bit combinational `request_packages` output reports the current offered request’s bank-work count; it is not an additional completion event or physical latency measurement. Each live slot stores its ID, 32 words, package count, return counter and admission sequence number. The oldest unserviced request receives the next service opportunity. Completed requests become eligible for response after their return counters expire. The oldest eligible response is presented; its slot remains live until acknowledgment. Held responses retain ID and data. Thus a slow response consumer can fill the four slots even after service finishes.

Admission uses pre-edge capacity: a slot retired on an edge becomes reusable next cycle. Duplicate live request IDs and misaligned addresses are rejected. Equal addresses must carry equal supplied snapshot values; inconsistent broadcast data is rejected. Reset cancels every live request and resets pacing; providers must treat canceled requests as canceled rather than expect a later completion. This is one shared read port with a FIFO policy, not a recovered NVIDIA scheduler or general multiport shared-memory implementation.

**Verification.** The [service receipt](../../components/warp_shared_read_service_verification.json) passes 320 word comparisons under service/return settings 1/9 and 3/1 cycles. Tests cover broadcasts and 2/4/32 packages, four concurrent requests, capacity backpressure, acceptance snapshots, FIFO IDs, stable stalled outputs, the exact isolated acknowledgment edge, reset cancellation/reclamation, and rejection of misalignment, duplicate IDs or inconsistent broadcast snapshot values. Receipt hashes preserve the tested source versions. These are local functional/timing-contract checks; no physical timing parameter is identified.

Run `python studies/rtx5090_gemm_milp/rtl/components/verify_warp_shared_read_service.py` from the project root.

**Authoritative behavioral implementation.**


**Source implementation:** [warp_shared_read_service.sv](../../components/warp_shared_read_service.sv)

### Implementation 46: Actual global operand frames committed to resident shared storage

**Role and geometry.** The [resident operand stager](../../numerical/resident_operand_staging.sv) supplies the 4,096-byte operand frame for a selected resident context. One frame contains 1,024 BF16 A values and 1,024 BF16 B values for BM32/BN32/BK32. The stager computes global row-major addresses, obtains actual sector-return values through one resident loader/cache, and offers 64 groups of 32 halfwords to the external shared writer. A frame completes only after all 64 write handshakes; accepting load requests alone is insufficient.

| Interface | Contract |
|---|---|
| Frame request | Context/ID, A/B bases, block row/column and reduction-stage index, all 32 bits; captured on acceptance |
| Frame availability | Per-context ready mask and outstanding count; one frame per context |
| Shared vector write | Context, 32 byte addresses, 32 halfwords, full active mask and valid/ready; actual writer acceptance consumes the loader response |
| Frame completion | Retained context/ID; held until acknowledged after all 2,048 values commit |
| Backing input | ID-matched 256-bit sector returns via one resident loader and one shared cache |

For the A half, a group’s flat halfword index determines the output-block row and current reduction column. For the B half, it determines reduction row and output-block column. The global strides are K for A and N for B. Bases must be even; complete allocations must fit 32-bit byte addressing. Block coordinates and stage index must remain within complete 32-element tiles. Shared destinations are byte offsets 0–4,094, with adjacent low/high halfwords kept distinct.

Each context retains bases, coordinates, stage index, group position and an epoch. IDLE accepts a frame, SEND offers its next load group, WAIT_VALUES holds the returned values until the shared write is accepted, and DONE holds frame completion. Separate registered request and completion owners provide round-robin arbitration and stable payloads under backpressure. The loader’s response is not acknowledged until the actual shared writer accepts it. Group/epoch/context matching rejects an unrelated return. Default two-context geometry uses seven local tag bits and 25 epoch bits; wrap requires reset. Reset cancels all contexts/loader work and requires the provider to flush old packets. Cached inputs must remain immutable until reset.

The [staging receipt](../../numerical/resident_operand_staging_verification.json) checks 4,096 committed halfwords for two different block/stage coordinates. It verifies captured request metadata, held shared payloads, delayed packets, all-word completion, another context progressing while a done response is held, reset and zero final outstanding work. This test uses checked shared-write sinks; it does not by itself establish matrix results. Serial per-context groups, arbitration and shared vector commits remain model choices.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_resident_operand_staging.py`.

**Inline behavior.**


**Source implementation:** [resident_operand_staging.sv](../../numerical/resident_operand_staging.sv)

### Implementation 48: One shared-read service for multiple clients

**Question and organization.** How can native operands and output-scratch reads compete for the same modeled read capacity? The [shared-read hub](../../components/shared_read_candidate_hub.sv) connects multiple clients to exactly one `warp_shared_read_service`. Each granted operation contains 32 aligned word addresses and 32 input words. The underlying service computes bank/broadcast work as described in section 4.31. Client identity is retained through actual result acknowledgment; adding clients does not add read-service instances.

| Interface or parameter | Contract |
|---|---|
| Candidate input | Per-client eligibility bit, 32-bit ID, 32 addresses and 32 input words |
| Grant output | At most one client selected per edge; means the common service actually accepted its values |
| Response | Per-client valid/ready, retained external ID and 32 returned words |
| Capacity | Defaults: two clients, four owner records and four common service slots |
| Service timing | Default package interval one and return delay one modeled cycle; both hypotheses |
| Counts | Global outstanding and per-client outstanding include responses held without acknowledgment |

Candidates are **previews**, not conventional stalled ready/valid offers. Before a grant, a client may change its preview or withdraw eligibility. Only the edge with `candidate_grant` snapshots the selected addresses and words and advances that client's instruction. This distinction lets arbitration examine several eligible operations without pretending they have already entered a queue.

The hub searches clients round-robin when a free owner record exists. Actual acceptance saves the client, its external ID and a monotonically increasing internal service ID; only then does the cursor advance. The internal ID routes the eventual response to its saved owner. A held FIFO-head response blocks later service returns. The owner record remains live until that client's response handshake. Equal external IDs in different clients are legal; reusing the same live ID within one client is rejected, including reuse on its retirement edge. Capacity checks use pre-edge state. Exhausting internal IDs requires reset; reset clears all owners and the common service.

The [hub receipt](../../numerical/shared_hub_verification.json) checks 256 returned words across synthetic capacities one and two. It checks changing ungranted previews, acceptance snapshots, equal IDs across clients, held responses, per-client/global conservation and reset cancellation; a duplicate live client ID is rejected. Round-robin arbitration, FIFO blocking and timing choices are implementation contracts, not discovered RTX scheduler or queue properties.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_shared_read_candidate_hub.py`.

**Inline behavior.**


**Source implementation:** [shared_read_candidate_hub.sv](../../components/shared_read_candidate_hub.sv)

### C++ component adapters

- [shared_memory_bank](../../cpp/shared_memory_bank.hpp) — adapter for [the matching Verilog source](../../components/library/shared_memory_bank.sv).
- [shared_broadcast_work](../../cpp/shared_broadcast_work.hpp) — adapter for [the matching Verilog source](../../components/shared_broadcast_work.sv).
- [warp_shared_read_service](../../cpp/warp_shared_read_service.hpp) — adapter for [the matching Verilog source](../../components/warp_shared_read_service.sv).
- [resident_operand_staging](../../cpp/resident_operand_staging.hpp) — adapter for [the matching Verilog source](../../numerical/resident_operand_staging.sv).
- [shared_read_candidate_hub](../../cpp/shared_read_candidate_hub.hpp) — adapter for [the matching Verilog source](../../components/shared_read_candidate_hub.sv).

## 9. Verification and evidence

Retain the verification expectations and existing receipts in Section 8. The [integration and verification chapter](../integration_and_verification.md) separates existing numerical tests, new C++ smoke tests and GPU measurements. The most recent connected-grid receipt checks 24,576 output words; it does not calibrate the integrated cycle count.

## 10. Optimization implications and remaining gaps

Layout decisions change bank service work. The measured conflict rule is implemented in the effective-path estimator; it is not automatically wired into every numerical RTL helper.

A parameter checked through documentation or a transferred prior can be used provisionally. Refine it when a new end-to-end case disagrees materially or when it changes the optimization choice. Do not spend time recovering a private property that the supported execution path does not exercise.
