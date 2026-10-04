# 08. Address translation

[System specification and chapter index](../../rtl_microarchitecture_spec.md) · [Approved manual structure](../../hardware_manual_structure.md)

## 1. Purpose and boundary

Translation maps program addresses to serviced memory addresses. The present primitive is an identity mapping with queued timing, suitable for the controlled flat-address test domain.

This is a specification of the executable reconstruction. Statements about physical RTX 5090 hardware retain their source or measurement scope; helper defaults describe model configurations.

## 2. Quantitative parameters

The table assigns this chapter ownership of the following inventory entries. “Baseline” preserves the existing setting; the evidence check may instead support a scoped alternative. Source priors are usable provisional estimates, not measurements of a private circuit.

| ID | Definition | Baseline | Unit | Recorded basis | Initial check |
|---|---|---|---|---|---|
| F043 | The memory-page sizes supported by address translation. | [4096,65536,2097152] | bytes/page | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F044 | The capacities, groups, ways and sharing of caches holding address translations. | {"L1_entries":128,"L1_ways":4,"L2_entries":2048,"L2_ways":8} | entries and ways | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F045 | How a virtual address selects a translation entry and which entry is evicted. | VPN modulo set count; LRU within set | policy | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F046 | The number of address-translation requests that can remain unfinished. | 32 | outstanding translation requests/SM | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F047 | The steps and resources used to obtain a missing virtual-to-physical translation. | {"levels":4,"walkers":4,"walk_cache_entries":32} | levels; walkers; entries | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| T024 | Time to obtain a physical address when the address-translation entry is already cached; excludes page walking and data access. | Not specified | SM-reference cycles | unidentified | Transferred simulator prior |
| T025 | Time spent handling a missing translation before or around the page walk; excludes separately counted page-walk work. | Not specified | SM-reference cycles | unidentified | Transferred simulator prior |
| T026 | Time to fetch and interpret page-table entries for a missing translation; excludes the requested program-data access. | Not specified | SM-reference cycles | unidentified | Transferred simulator prior |

Use the [complete parameter table](../../parameter_master_table.md) for values, scope, evidence links and provisional alternatives. Device capacities are centralized in the system specification. Per-module tables below identify which parameters are actually consumed by each implementation.

## 3. Interfaces and transaction ownership

Virtual-address token → identity translation queue → unchanged address. The connected GEMM backing-memory model uses flat bounded addresses and does not instantiate a physical page walker or TLB.

The exact port names, directions, widths and acceptance rules are listed in the implementation contracts in Section 8 and their linked sources. A connection must preserve both payload and ownership while stalled. The common system protocol applies unless a module contract explicitly states a pulse-only interface.

## 4. State and storage

Each linked module contract specifies its arrays, counters, masks, pointers or state machine. Those fields belong to that implementation only. A primitive helper is not an additional copy of a hardware resource inside the connected top unless that top instantiates it. Reset removes outstanding model ownership according to the specified contract; physical power-on behavior is outside this model.

## 5. Functional transitions

Accepted addresses retain their identity through the configured queue delay. Output equals input. Page permissions, faults, physical indexing and invalidation are not implemented.

Requests are accepted only when the named receiver permits acceptance. Completion must update the original owner before resources are released. The implementation contracts below describe each state transition and numerical transformation separately.

## 6. Timing and arbitration

Use completion latency, acceptance interval and queue capacity as three distinct quantities: when a result becomes available, how often a new request can start, and how many requests can remain pending. The per-module timing contract gives their actual code meaning.

For a held-response interface, observe a valid response after an edge, hold readiness low for one more edge, and verify that identity and data remain unchanged. Retirement occurs only on a later edge with both valid and ready. A receiver becoming free after an edge does not retroactively accept a request at that edge.

## 7. Invariants and failure handling

Do not attribute this identity mapping to the RTX 5090. A guessed TLB capacity does not make translation behavior executable. Test-domain bounds and launch overflow checks remain enforced.

Unsupported configurations must remain explicit. A passing test of a helper establishes its tested model contract, not a GPU-wide hardware policy.

## 8. Linked implementations and detailed contracts

The following contracts retain the quantitative organization, exact interfaces, state transitions and verification scope of the existing implementations. Verilog stays in separate source files. C++ adapters expose the same generated ports and clock behavior; they do not introduce independent timing constants.

### Implementation 8: Address translation

**Role.** Passes an address through a bounded timing queue. The virtual address is returned unchanged as the physical address. This makes identity translation an explicit baseline assumption.

**Quantitative configuration.** `LATENCY` is configurable; no RTX translation delay has been identified. Four slots and one-cycle initiation are modeling choices in this baseline.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| LATENCY | 1 | cycles | Positive | Baseline; translation timing unknown |
| Queue slots | 4 | addresses | Fixed in wrapper | Baseline |
| Address width | 32 | bits | Upper physical address bits cannot be represented | Interface limitation |
| Mapping | Identity | address rule | Admit only as explicit diagnostic assumption | Not measured translation hardware |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| req_valid / req_ready | input / output | Request present / receiver permits acceptance. |
| virtual_address | input, 32 bits | Untranslated byte address supplied to the baseline. |
| rsp_valid / rsp_ready | output / input | Completed response present / consumer permits retirement. |
| physical_address | output, 32 bits | Returned byte address; identical in this baseline. |

**Interface protocol.** Identity translation is explicitly selected by using this baseline module; addresses must fit the 32-bit interface.

**Stored state.** Four-slot timing queue carrying addresses.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| Inherited timed_queue arrays | Four entries | Identity-mapped address storage |

**Reset and cycle transitions.** After an accepted address, return the same address through the configured timed handshake. There is no TLB or page walk.

**Invariants and failure handling.** The module never changes address bits. It must not be used to claim realistic virtual-to-physical mapping.

**Linked behavioral implementation.**


**Source implementation:** [address_translation.sv](../../components/library/address_translation.sv)


**Verification expectation.** Test exact address retention and configured delay. Not behaviorally tested yet.

**Unimplemented or unidentified.** Page size, translation tags/sets/ways, page walks, access permissions, mappings, faults, and translation contention are unimplemented. Use only where identity translation is an admitted diagnostic assumption.

### C++ component adapters

- [address_translation](../../cpp/address_translation.hpp) — adapter for [the matching Verilog source](../../components/library/address_translation.sv).

## 9. Verification and evidence

Retain the verification expectations and existing receipts in Section 8. The [integration and verification chapter](../integration_and_verification.md) separates existing numerical tests, new C++ smoke tests and GPU measurements. The most recent connected-grid receipt checks 24,576 output words; it does not calibrate the integrated cycle count.

## 10. Optimization implications and remaining gaps

Translation can be omitted from the current fixed-domain cost only as a stated abstraction. Large-footprint cases that reveal translation delays require an expanded model.

A parameter checked through documentation or a transferred prior can be used provisionally. Refine it when a new end-to-end case disagrees materially or when it changes the optimization choice. Do not spend time recovering a private property that the supported execution path does not exercise.
