# Draft component contracts: multiple modeled SMs and a common backing gateway

These sections await authoritative source and current-source tests. They make no verification claim.

## Common sector gateway

Describe why multiple modeled SM clients need one owner for backing transactions. Define client read and write candidates, actual grants, 32-bit client IDs, addresses, 256-bit sector payloads, write masks, and client response acknowledgment. Record exact final port names from the source.

The intended capacity is one outstanding backing owner record across reads and writes. Define when arbitration snapshots metadata, how the internal backing tag maps to client/type/external ID, and how held request and response payloads stay stable. Ownership remains live until actual acknowledgment. Explain matching-ID rejection, pre-edge reuse policy and reset/provider cancellation from the implementation. A single serialized gateway is a model hypothesis, not identified RTX bandwidth or memory-controller organization.

## Multiple resident SM models

Describe the default two modeled SMs with two resident block contexts each. Each SM inherits its own input cache and internal operand, read, MOVM and HMMA service set. The common gateway serializes external backing traffic. No shared global L2 cache is implemented by this organization; the physical interpretation of per-SM input-cache instances remains unspecified.

Define one grid launch and its captured bases/ID, global block traversal, eligible-SM selection, and the acceptance edge that advances dispatch. Explain the global issued/completed ledger, child IDs and SM ownership, duplicate/out-of-order completion handling, resident count conservation and final completion boundary. Completion must follow every output acknowledgment and zero live block reservations across all modeled SMs.

After final sources are available, provide exact capacities and interfaces, reset/immutability/nonoverlap contracts and full inline SystemVerilog. Only after current tests pass, report dimensions, numerical oracle, output words and transaction/ownership checks. Model clock-edge comparisons must state their boundary and cannot establish actual multi-SM speed or shared-memory bandwidth.
