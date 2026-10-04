# Draft sections 4.54–4.55: shared read-only cache after gateway ownership

These component contracts await the final current-source full-grid receipt. The unit receipt is current; the full-grid receipt still has a previous comment-version hash.

## 4.54. Shared read-only sector gateway

The path is modeled SM → common ownership gateway → shared read-only sector cache → backing provider. The ownership gateway remains one combined read/write record through client acknowledgment. Read transactions access one actual `sector_read_cache`; writes bypass it. Defaults are 64 sets, eight ways, 128-byte lines and four independently valid 32-byte sectors: 64 KiB of modeled data. This development size is not the physical 96 MiB RTX L2 capacity.

Requests preserve 32-bit IDs/addresses and return actual 256-bit sectors. Valid-sector hits return saved data. Misses issue aligned 32-byte backing requests and fill only when the actual matching response arrives. The full packet, rather than only one word, returns through the ownership gateway. Replacement and one pending request inherit the cache's implementation choices.

`l2_read_requests` increments on accepted logical cache requests. Hit/miss counts increment only on the logical cache response handshake; held responses cannot double-count. The pending bit makes requests equal hits plus misses plus pending. These counters accumulate until reset, including across grid launches. Writes do not increment read counters.

The unit receipt checks 40 returned words and one hit/four misses, with four backing reads. It separately checks equal external IDs, captured write payloads, provider delay, held client responses, reset/provider flush and wrong-ID rejection. Inputs are immutable, output C is disjoint, and writes bypass the cache. There are no dirty sectors, write invalidations, coherence, multiple miss records or concurrent cache misses. Reset cancels both layers and requires provider flush; previously committed output stores remain committed.

## 4.55. Multi-SM grid using the shared read-only cache

The top preserves two modeled SMs with two resident contexts each, plus their private input caches. One shared cache after gateway ownership serves reads that miss those private caches. Native service sharing, global block ledger, output acknowledgment and cycle boundary remain as in section 4.53. Four resident contexts and every service/geometry choice remain hypotheses.

The completed first run compared 24,576 output words across two six-block launches at each K64/K1536. The final receipt must be checked against current sources before the master manual claims that verification. Counters are cumulative since reset, not per-launch totals:

| K and observation | Cumulative requests | Cumulative hits | Cumulative misses |
|---|---:|---:|---:|
| K64 first launch | 1,280 | 640 | 640 |
| K64 repeated launch | 1,280 | 640 | 640 |
| K1536 first launch | 30,720 | 3,938 | 26,782 |
| K1536 repeated launch | 61,440 | 7,875 | 53,565 |

The unchanged K64 counters mean the private-cache replay sends no new logical shared-cache reads in this model. The K1536 counts reflect this declared geometry and trace only. They do not establish physical GPU hit rates, replacement or latency. Clock-edge outputs remain uncalibrated model results; cache reuse and provider phase are not isolated. Reset during output stores and the original large grid remain outside verification. Exact code and final receipt links will be inserted after current hashes match.
