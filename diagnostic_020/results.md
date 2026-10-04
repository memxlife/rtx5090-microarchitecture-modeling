# Why the same cache-hit rate can produce different runtimes

## Question and controlled experiment

If three of every four loads hit the cache, does a program run close to the average of cached and uncached response times? This matters for our RTX 5090 GEMM model: a single average cache-hit rate may hide which missing values hold up later instructions.

We used the same compiled four-load benchmark as the previous experiment. Each group issues four ordinary 16-bit global loads before storing their values in shared memory. A shared store cannot proceed until its source value arrives. Every warp, a group of 32 threads, reads 64 bytes from a different 128-byte memory line on each request.

Before measurement, a separate kernel warmed selected input lines in L2, the hardware cache shared by the GPU's processing units. The measured program, total requested bytes, number of load requests, and number of stores stayed fixed. Fresh regions from a 1 GiB initialized input allocation supplied the other lines. We used independent checksums for every timed launch, and compared compiled instructions to ensure that only cache preparation changed.

The main comparison used four warps in one block. We prepared the same 75% hit rate in two ways. In the dispersed case, every four-load group had three cache hits and one miss. In the clustered case, three entire groups hit the cache and the next entire group missed. Both cases therefore have the same number of hits and misses overall, but the missing values are needed at different points in execution.

Seven profiles verified the intended cache conditions, including the later confirmation mixtures. Hit fractions were exactly 0%, 25%, 50%, 75%, or 100%, as intended. No profile had first-level cache hits. Each made 32,768 global requests and required 32,768 shared-store processing steps. Both 75% conditions read approximately 0.5 MiB from external memory. Their compiled response functions were identical to the previous experiment.

## Same traffic, different waiting

Each timing result below is a measured slope, rather than a raw launch duration. We took the median of nine measurements at each of two request lengths, subtracted the shorter timing from the longer one, divided by the added requests, and multiplied by four to report cycles per four-load group. Fixed launch and clock-reading costs therefore do not determine the comparison.

| Preparation, four warps | L2 hit fraction | Measured cycles per group |
|---|---:|---:|
| All requests miss | 0% | 1,013.743 |
| Every group contains one miss, issued first | 75% | 969.486 |
| Every group contains one miss, issued last | 75% | 959.531 |
| Misses concentrated in a quarter of the groups | 75% | 552.993 |
| All requests hit | 100% | 398.708 |

With one miss in every group, the program remains nearly as slow as the all-miss condition. Three quick responses do not remove the need to wait for the fourth value. Concentrating the misses into fewer groups allows the other groups to finish quickly. The dispersed condition is about 1.75 times slower than the clustered condition despite matching hit rate, request count, store count, and external-memory traffic.

These timings include address calculation, loop work, stores, and scheduling. They establish a response mechanism for this instruction path, rather than isolated load latency or a hardware queue size.

## Predictions made before measurement

The previous experiment independently measured one-load and four-load response costs for pure L2 hits and pure misses. Using those costs, a model based on average cache-hit fraction predicted 553.410 cycles per group for both 75% cases. It matched the clustered case within 0.075%, but underestimated the dispersed cases by 42–43%.

The competing model treats an uncached value as the main waiting cost whenever a group contains a miss. It then adds small request-processing costs measured in the previous experiment. Before this experiment, we saved a predicted interval of 981.110 to 1,015.362 cycles for a group with one miss and three hits. The four dispersed cases, including one and eight warps as additional controls, were within 0.69–2.25% of that interval. The observed values lie slightly below its lower endpoint; we retain that discrepancy rather than treating the interval as an exact bound. All met the 5% tolerance chosen before testing.

We then tested a more explicit version of the same rule on two new mixtures. For a group containing misses, it starts with the previously measured one-miss response cost. Each additional miss adds the previously measured cold-request increment, and each hit adds the previously measured cached-request increment. No parameters were fitted to this experiment's timings.

| Fresh four-load mixture | Predicted cycles per group | Measured cycles per group | Absolute error relative to measurement |
|---|---:|---:|---:|
| One hit and three misses | 1,003.945 | 1,002.107 | 0.18% |
| Two hits and two misses | 992.528 | 980.068 | 1.27% |

The predictions were saved before running these four new cases at two request lengths. All 162 timed launches across the initial comparison and confirmation passed complete checksum checks without register spills. The confirmation binary retained the identical measured instruction body. Its profiles independently verified the 25% and 50% hit rates.

## Model change and remaining work

The response component now represents the outcomes of individual requests inside a group. It chooses the main waiting cost from the slowest required data source and adds independently measured request-processing costs. It does not assign an average cache latency to the whole group. The exported implementation accepts only the tested group sizes, warp counts, and mixed request orders; unsupported cases are rejected explicitly.

This improves the physical explanation without fitting GEMM timings. It does not yet establish full GEMM prediction accuracy. Real GEMM also has interactions between blocks, different address patterns, shared-memory work, arithmetic, and instruction scheduling. A further question is whether a second block's cache lookup can refer to data still being fetched for the first block. Such a request could have to wait even though another request has already created a cache entry. We will test that possibility before treating every lookup hit as immediately available data.

Raw timings, preparation code, compiled instructions, profiler counters, and saved predictions are preserved in this directory. [analyze.py](analyze.py) reproduces [verification.json](verification.json). The updated [response component](../model_components/global_response.py) retains independently measured parameters from the previous experiment. The accurate physically grounded full GEMM runtime model remains unfinished.
