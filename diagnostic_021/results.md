# Cache reuse also depends on when the data arrives

## Question and setup

Does a second block reading shared data receive a quick cached response, or can it still wait while the data is arriving? This matters for GEMM, where several blocks can request the same matrix values at nearly the same time. A model that remembers only whether an address has been requested can mistake an unfinished fetch for immediately usable data.

We tested two blocks, each with four warps. A warp is a group of 32 threads. Both blocks either read the same input or separate inputs. Each issued one or four independent 16-bit loads before storing the results into shared memory. Each request read two 32-byte sectors from a different 128-byte memory line. We tested both fresh input and input warmed in L2, the cache shared by the processing units.

The first sixteen cases retained the identical compiled GPU response functions from the previous cold/cached experiment. Only the host program changed to preserve separate timings for each block and the processing-unit identifiers for every launch. Both blocks ran on different processing units in all measured launches. Nine timings at each request length were checked against independent complete checksums. No case spilled registers.

## Shared data reduces traffic without removing the wait

Eight profiles verified all requested cache states. Two blocks reading fresh shared data had exactly 50% L2 hits. Fresh separate inputs had zero hits, and warmed inputs had all hits. No profile had first-level cache hits. Every profile issued 65,536 global requests.

For each result below, we subtract the median time for 2,048 requests from the median time for 8,192 requests and divide by the added requests. Multiplying by four gives cycles per four-load group. This removes fixed launch and clock-reading costs. The two timings are preserved separately for each block.

| Four-load version | Block 0 | Block 1 |
|---|---:|---:|
| Fresh shared input | 1,010.635 cycles per group | 1,010.645 cycles per group |
| Fresh separate inputs | 1,011.559 cycles per group | 1,015.784 cycles per group |
| Warmed shared input | 398.426 cycles per group | 399.465 cycles per group |
| Warmed separate inputs | 397.879 cycles per group | 399.476 cycles per group |

Sharing fresh data roughly halved external-memory payload compared with separate inputs, but both blocks still had nearly the full cold response cost. The one-load version showed the same pattern: shared fresh input cost approximately 956 cycles per request in both blocks, while warmed input cost approximately 376–378 cycles.

These results suggest that reuse of a request does not necessarily mean its data is already available. They do not identify which block led each request or the hardware structure that combines requests.

## A controlled change in arrival time

To distinguish data already available from data still arriving, we compiled a second version with a delay before block 1 began the measured response loop. The same binary ran both the zero-delay and long-delay conditions. The delay was outside each block's response clock interval. Its length exceeded block 0's measured loop duration, giving block 0 enough time to fetch all shared input before block 1 used it.

The delay prefix can change compiler allocation, so we compare near and delayed starts within this binary. We verified the intended four-load-before-store ordering and absence of register spills. The zero-delay result also closely matches the original response function above. An initial unsupported delay-loop instruction caused a compile failure; it was repaired before any GPU measurements. That failed compilation is preserved separately.

| Start condition | Block 0, cycles per group | Block 1, cycles per group |
|---|---:|---:|
| Both start without an intentional delay | 1,005.643 | 1,005.641 |
| Block 1 starts after block 0 has finished fetching | 1,007.576 | 396.884 |

The second block is about 2.53 times faster when the data has already arrived. The intentional start delay makes the whole launch longer; this is a diagnostic experiment, not a proposed speedup. We compare the response loop's cost after it starts.

Both profiles had exactly 50% L2 hits and 65,536 global requests, with no first-level cache hits. Thus, the aggregate hit rate cannot distinguish the two response behaviors. Total DRAM read counters differed: approximately 2.097 MB for the near start and 2.443 MB for the delayed start, using one million bytes per MB. The source-specific L2 hit/miss totals were identical. We have not attributed the extra aggregate reads, so we do not claim identical total DRAM traffic. Ordinary unprofiled timings supply the table; profiler runs establish the cache observations.

## Predictions and the model change

Before the start-delay experiment, we saved predictions using the previous independent probe: 1,015.362 cycles per four-load group for cold response and 399.426 cycles for already-cached response. We predicted cold response for both near-start blocks, but cold response for block 0 and cached response for delayed block 1. The four prediction errors were 0.97%, 0.97%, 0.77%, and 0.64%, relative to the measured costs. No new timing coefficient or GEMM runtime was fitted.

The model now tracks when requested data becomes available. A first request starts a fetch and records its expected completion time. A later request that refers to the same unfinished fetch must respect that time. Once the data has arrived, a subsequent request can use the independently measured cached response cost. This is a useful performance abstraction supported by the controlled experiment; it does not prove when NVIDIA allocates a physical cache tag or identify its exact request-merging implementation.

The exported [readiness component](../model_components/readiness.py) currently covers the measured endpoints: simultaneous shared groups and groups issued after all their data is available. It rejects intermediate arrival times, partly pending groups, and partially ready sectors within one request. It also requires its caller to remove availability records when a cache model evicts data. These limits prevent a small probe from silently becoming a claim of complete cache or GEMM simulation.

## Implication and remaining work

All 180 timed output checks passed without spills, and ten profiles verified the intended cache fractions. The combined evidence shows that GEMM's memory model needs both individual request outcomes and data availability over time. A kernel-wide hit percentage misses these distinctions.

The next step is to combine the independently measured response, readiness, shared-memory, and matrix-execution components on unchanged GEMM kernels. We will save predictions before new timing runs, report their absolute errors, and identify which stage costs remain unexplained. Address calculation, instruction issue, synchronization, cross-resource overlap, and partially pending requests are still incomplete. The accurate physically grounded full GEMM model is not finished.

[analyze.py](analyze.py) reproduces [verification.json](verification.json). Raw measurements, each block's timings and processing-unit identifiers, compiled instructions, profiler counters, and the predictions saved before the start-delay test are preserved in this directory.
