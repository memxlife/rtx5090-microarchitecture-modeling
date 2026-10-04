# Draft hardware contract: nonblocking shared read-only sectors

This component template awaits authoritative implementation and current-source verification. The capacities below are requested development defaults, not measured RTX properties.

## Organization and quantitative state

Record eight client-owner records and four miss-status records (MSHRs). An MSHR retains one outstanding missing-sector transaction and its response tag. Shared data geometry remains 64 sets × eight ways × 128 bytes = 64 KiB, with four 32-byte valid sectors per line. Record exact waiter storage, replacement state, pin counts and response queue capacities from final code rather than inventing them.

## Ports and acceptance

Define per-client read valid/ready, ID/address and returned 256-bit sector ports; write address/data/mask and acknowledgment ports; tagged backing read request/response and output-write channels. Explain which acceptance edge allocates an owner and whether accepted writes serialize with reads. Capture IDs and payloads only on actual acceptance. Describe independent backpressure from exhausted owner slots, exhausted MSHRs, pinned replacement candidates and held replies.

## Missing-sector sharing and actual fill

Different reads to the same missing sector may join an existing MSHR. Define the exact join key and maximum waiter count. Reads to a different sector of the same line must not inherit validity accidentally. Pin any line needed by an outstanding refill so replacement cannot redirect its tagged return. A matching actual provider response supplies the data; acceptance alone does not fill a sector. Define tag reuse, wrong or duplicate response rejection, and completion handling for responses arriving out of request order.

## Completion and held ownership

Explain how a completed sector releases waiters, how per-client result ordering is chosen, and which reply advances on acknowledgment. Owner records remain live while results are held. Distinguish releasing a returned MSHR from releasing an unacknowledged client owner. Define whether a freed slot is reusable on the same edge or only the following edge. State acceptance-to-first-service and return-to-visible-response edge boundaries from code; do not assign intrinsic hardware latency.

## Counters and conservation

Define request, valid-sector hit, new miss, joined miss, backing request/refill and retired-response counters at their exact handshake edges. State whether totals persist across grid launches. Give conservation relationships for live owners, MSHRs, waiters and filled responses. Joins are not extra backing transactions; held replies must not double-count.

## Reset, write bypass and scope

Reset cancels owners, pending refills and cache state and requires provider flush before ID reuse. It does not undo committed output stores. A/B are immutable and C is disjoint; output writes bypass the read-only cache. No write coherence or invalidation is implied. Multiple outstanding records are executable concurrency hypotheses, not identified physical queue counts, bandwidth or latency.

## Verification and inline source

After current tests pass, report distinct-miss overlap, same-sector joins, pinned-fill protection, tagged out-of-order returns, held ownership, queue saturation/backpressure, reset and independent data checks. Insert exact authoritative SystemVerilog and current receipt paths. Keep unit behavior separate from full-grid numerical and cycle observations. Do not close hardware parameters from local tests.
