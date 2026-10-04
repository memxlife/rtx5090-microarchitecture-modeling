# Can a richer GEMM model choose the fastest tile?

A mixed-integer linear program (MILP) can search this real GPU tile space quickly, but its mathematical optimum is only as useful as its time estimate. This revision asks whether distinguishing the two input orientations, the number of warps doing matrix arithmetic, and the reduction-loop depth improves that estimate. The answer is mixed: it selected the fastest tested tile on one new matrix size, but remained 24.5% slower than the fastest tested tile on the other.

## The hardware experiment

We multiply a matrix with M rows and K columns by a matrix with K rows and N columns. Inputs use BF16, a 16-bit floating-point format; accumulation and output use 32-bit floating point. One RTX 5090, device 7 on the authorized server, executes every trial. Its queried resources include 170 streaming multiprocessors, each with 102,400 bytes of shared memory and 65,536 register words.

One block has 128 threads organized into four warps of 32 threads. It computes an output tile using 16-by-16-by-16 WMMA matrix instructions. Warps take output fragments cyclically. The kernel uses row-major inputs, one shared input-buffer stage, and a 4,096-byte output scratch buffer. These choices remain fixed; this is a tile-selection experiment rather than a comparison of different kernel families.

The block's row and column tile dimensions each range from 16 to 96 in steps of 16. Its reduction dimension ranges from 16 to 64 in steps of 16. There are 144 possible triples. The MILP chooses the dimensions independently; it does not select from a table of measured tile times.

We exclude an explicit L2 reuse or cache-capacity term, following the user's scope. Hardware caches remain active. A 512 MiB read sweep precedes each timed launch and is excluded from the timing. It reduces reuse between launches but cannot remove reuse within a launch. Each reported sweep time is the median of nine groups of five launches, following ten warm-up launches. Lower time is better. All outputs are checked against cuBLAS, NVIDIA's matrix library, using the study's deterministic inputs.

## What the matched tests revealed

Swapping the row and column tile widths preserves arithmetic work and shared-buffer bytes on a square matrix. It nevertheless changes how threads access the operands. On the previously investigated 1,536-cubed case, profiles of 32-by-64-by-32 and 64-by-32-by-32 recorded approximately 35.63 million and 21.60 million shared-load bank conflicts. These are extra accesses caused when simultaneous requests compete for shared-memory banks. The profiled times were 0.2556 and 0.2183 ms. Instruction counts and measured DRAM reads were nearly equal. This supports treating input orientation as consequential; it does not isolate bank conflicts as the sole cause or measure their individual cost.

Reduction depth also changes more than the total arithmetic count. For a 16-by-16 output tile on the previously investigated 640-cubed case, depths 32, 48, and 64 recorded approximately 20.25, 23.32, and 15.59 million instructions. Their profiled times were 0.0739, 0.0768, and 0.0375 ms. Depth 64 was fastest despite having the most shared-load bank conflicts among these three. A conflict count alone therefore cannot serve as the objective. Fewer loop stages, instruction scheduling, and shared accesses interact.

These five profiles are diagnostic observations on earlier cases, not new test-set results. Profile instrumentation changes execution time. The timing conclusions below come from the ordinary measurement sweep. The profiler's zero recorded DRAM-write count also does not mean that the kernel writes no output: stores can remain buffered outside the counter window. [Raw profiles and their extracted counters](profiles_summary.json) preserve the observations.

## Turning those details into a model

Let BM, BN, and BK denote the block's row, column, and reduction dimensions. Their integer quotients in units of 16 are qM, qN, and qK. Let nM, nN, and nK count the tiles needed to cover the matrix in each direction; each is the corresponding matrix extent divided by its tile extent and rounded upward. The total number of output blocks is G = nM times nN.

Each block owns F = qM times qN output fragments. Its largest arithmetic burden per warp is s = ceiling(F/4). Only p = minimum(4,F) warps have output fragments to compute. All four warps still participate in staging and synchronization. For example, a 16-by-32 output tile has two fragments and two arithmetic-producing warps; a 32-by-32 tile has four fragments and four such warps. These classes can have different costs even when their maximum per-warp fragment burden is one.

The model uses compiler register observations grouped by s, qK, and p. Within each group it takes a conservative maximum register count, rather than a measured performance for each tile triple. Let R denote this count rounded upward to a multiple of eight words per thread. The predicted number r of simultaneously resident blocks per multiprocessor is:

$$
r=\min\left(12,\left\lfloor\frac{65536}{128R}\right\rfloor,\left\lfloor\frac{102400}{4096+2BK(BM+BN)+1024}\right\rfloor\right).
$$

The three limits represent threads, registers, and shared memory. The additional 1,024 bytes are the measured launch reservation used in this study. This resource envelope is conservative and does not establish exact occupancy for every tile. Define w, the number of whole-device block waves, as the ceiling of G divided by 170r. A wave represents enough blocks to fill the predicted resident capacity once.

The model counts reduction stages separately from matrix-instruction steps. Define H as nK when qK is one, and zero otherwise; define O as nK when qK is three, and zero otherwise. These distinguish the short and odd-depth cases seen in the calibration. Define U = nK times s times qK as the maximum per-warp matrix-step count. Define A = nK times qM times qK and B = nK times qN times qK as separate staging counts for the two operands. These are operation-count features, not physical byte counters.

For each productive-warp class p, a nonnegative coefficient vector weights the following sequential features:

$$
[1,nK,H,U,A,B,O].
$$

A second coefficient vector weights the following aggregate features:

$$
[1,wnK,GU/(170r),GU/170,GA/170,GB/170,GH/170,GO/170].
$$

The first estimate describes a block's sequential work. The second describes the total work distributed across available multiprocessors and resident blocks. The predicted latency is the larger estimate. Minimizing a continuous time variable constrained above both estimates expresses that maximum with linear inequalities.

There are separate coefficients for each of the four productive-warp classes and each of these two estimates. We fitted them with nonnegative least squares, weighting errors by inverse measured latency so the fit minimizes squared relative error. Calibration cases whose grids fit within one predicted wave train the sequential estimate; larger grids train the aggregate estimate. These are empirical summaries of interacting costs, not individually measured hardware latencies. Several counts are correlated, and every development case uses K = 1,024. A zero coefficient does not establish that a physical mechanism is absent.

### Why the integer construction remains linear

Coverage ceilings, fragment counts, residency, waves, and coefficient selection contain products. All integer quantities have finite bounds. Binary expansion of one factor converts each product into sums of binary-times-bounded-variable terms, each represented exactly by four linear inequalities. The original [derivation](../README.md#why-this-is-a-milp-rather-than-nonlinear-optimization) explains those inequalities. Binary indicators choose productive-warp and resource classes, rather than complete tile triples. A finite selection over residency levels one through twelve handles reciprocal residency.

Independent enumeration checks the answer after the MILP runs. Fixing each of the 144 tiles also checks every MILP objective against direct evaluation on both new shapes. Enumeration is a verifier here; these small-domain timings do not demonstrate that MILP is faster than enumeration.

## Calibration, numerical repair, and confirmation

The coefficient fit used 96 measurements across three development shapes: 128-by-128-by-1,024, 896-by-896-by-1,024, and 1,792-by-1,792-by-1,024. Before confirmation, we added twelve measurements because the three-productive-warp class lacked short and odd-depth observations. We also included the generic stage count, motivated by the kernel's two synchronizations per reduction stage. The [experiment contract](contract.json) and earlier versions preserve these changes.

A first numerical encoding reported an optimum despite a better directly calculated feasible tile, and some fixed tiles were incorrectly rejected. We preserved [that failure](numerical_failure_before_repair.json). The repair tightened integer-product bounds, expressed time internally in microseconds, removed conditional time constraints with large constants, and used the direct HiGHS 1.15.1 API with primal and integer feasibility tolerances of one billionth. The final tests agree for all 144 fixed tiles on both new shapes. This is evidence for the repaired implementation; it is not an isolated diagnosis of an upstream solver defect. A reported zero solver gap alone was insufficient verification.

We saved coefficients, source hashes, and both selected tiles before measuring either confirmation shape. The model hash is `d10d437c8d04070888a8a22763e2c2202de08675945b61f705cde5c17fe18cb0`. The [freeze record](frozen_manifest.json) states that confirmation had not started at the time it was written. Its test script was subsequently expanded to check both shapes; the fitted model and solver sources remained unchanged. We did not refit on the confirmation results.

## Results on two new matrix sizes

Excess latency is the selected tile's measured time divided by the best measured time, minus one. Zero means the selected tile equals the fastest observed configuration in this bounded domain. It does not mean globally optimal GEMM across all possible implementations.

| Square matrix size | New selected tile | Selected time | Best measured tile | Best time | Excess latency | MILP solve time |
|---|---|---:|---|---:|---:|---:|
| 800 | 16 × 32 × 64 | 0.043008 ms | 16 × 32 × 64 | 0.043008 ms | 0% | 0.308 s |
| 1,920 | 32 × 32 × 32 | 0.316211 ms | 64 × 48 × 32 | 0.253946 ms | 24.5% | 0.835 s |

An alternating-order recheck repeated both comparisons three times. The 800-sized new choice remained about 0.0430 ms versus 0.0512 ms for the previous choice. At size 1,920, the MILP choice remained about 0.3150 ms versus 0.2531–0.2540 ms for the sweep winner. These [separate measurements](paired_recheck.jsonl) support the observed ordering.

All 288 runs matched the reference and had no register spills. Both MILP answers agreed with independent enumeration of the declared objective and had a reported zero optimality gap. For the larger case, the model contains 429 variables and 830 constraints. [Complete results](results.json), [hardware measurements](confirmation.json), and the two solver receipts retain the evidence.

On the same new shapes, revision 002 selected 32-by-32-by-48 and 32-by-32-by-32. Their excess latencies were 19.0% and 24.5%. Thus the new revision fixes the smaller decision but does not improve the larger decision. Its median absolute relative timing error across the full domain is 12.0% on the smaller shape and 19.4% on the larger; the previous model gave 19.2% and 18.6%. Better average prediction on one shape is not general accuracy.

The larger failure is particularly informative. The model predicts 0.3210 ms for its selected tile, close to the observed 0.3162 ms. However, it predicts 0.3338 ms for the actual best tile, which measured 0.2539 ms. Accurate prediction of the chosen tile therefore does not establish accurate selection. The model underestimates the advantage of the alternative, which fits within one predicted wave, while the chosen tile needs two. The winner was second in the model's ordering. This local comparison identifies a concrete next diagnostic, rather than a reason to discard the MILP formulation.

## What remains missing

Orientation is represented by separate staging counts, but the model does not explicitly derive shared-memory bank addresses or the WMMA lane mapping. Reduction depth and productive-warps are represented by empirical classes, but the model does not derive instruction issue, overlap, barrier arrival, or the cost of partially filled final waves. Compiler register envelopes can also obscure differences within a class. Fixed development reduction length and correlated counts limit our ability to distinguish those mechanisms.

The next useful experiment would compare 32-by-32-by-32 and 64-by-48-by-32 across several grid sizes around their resident-capacity boundaries, while separately changing reduction length. Profiling their shared accesses, barrier waiting, eligible warps, and instruction counts would test whether the missing benefit comes from wave utilization, access layout, or scheduling. This is a proposed experiment, not a measured conclusion. L2 reuse remains excluded from the requested model.

The bounded conclusion is that richer hardware details can be encoded in a genuine MILP and solved in under a second here. The model now finds the measured optimum on one new shape, but still cannot guarantee the fastest hardware tile. The residual error belongs to the time model: the repaired solver correctly minimizes the equations we supplied.
