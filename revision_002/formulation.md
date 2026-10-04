# A MILP that accounts for how a tile occupies the GPU

The first model counted total arithmetic and requested memory bytes, but assumed that every tile could achieve the same throughput. That failed on the real RTX 5090. This revision asks whether a small model of block scheduling and the kernel's sequential phases can improve tile selection on new matrix sizes. It retains independent integer tile dimensions and excludes an explicit L2-cache reuse term.

## What the hardware measurements changed

Profiling the original 80-by-64-by-16 choice and the fastest 32-by-32-by-32 configuration gave the following measurements. Profiling changes execution conditions, so these durations are diagnostic and do not replace ordinary benchmark timing.

| Measurement | Original choice | Measured best |
|---|---:|---:|
| Achieved occupancy: fraction of available warp slots active | 10.15% | 48.98% |
| Scheduler cycles with no eligible warp | 92.75% | 65.43% |
| SM compute throughput relative to profiler reference | 12.11% | 55.59% |
| Profiled duration | 0.259 ms | 0.085 ms |

A warp is a group of 32 threads. An eligible warp has an instruction ready to execute. These observations show that the original choice frequently left the GPU without ready work. They do not independently assign the cause to any single instruction or memory mechanism. [The profiler records](profiles_summary.json) preserve both observations.

A controlled experiment kept the 32-by-32-by-32 kernel and its 2,048-by-2,048-by-1,024 multiplication unchanged, while reserving more unused shared memory. The CUDA occupancy API reported allowed residency of 11, four, two, and one blocks per multiprocessor. Their measured median latencies were approximately 0.198, 0.330, 0.554, and 0.993 ms. Reserving enough space to admit only one block made the same instructions about five times slower. This supports modeling resource-limited residency. Shared-memory reservation can also change the shared/L1 partition, so the experiment does not isolate residency from every possible memory-system effect.

A second control changed matrix row and column sizes while fixing reduction depth and tile size. Small output grids had almost constant latency; latency increased once the grid required more block waves. Thus, total arithmetic alone cannot explain the measurements.

## The physical counts

The unchanged kernel uses 128 threads, four warps, BF16 WMMA 16-by-16-by-16 instructions, row-major layouts, and one input buffering stage. It loads the staged operands, synchronizes, computes, and synchronizes before reusing shared memory. Those steps are sequential in the source. Their fitted costs are summed rather than assumed to overlap completely.

Let $M$, $N$, and $K$ denote matrix row, column, and reduction sizes. Let $q_M$, $q_N$, and $q_K$ denote tile dimensions in units of 16; each tile dimension is 16 times its corresponding quotient. Let $n_M$, $n_N$, and $n_K$ be the ceiling-divided tile counts. As before, coverage and minimality define each ceiling exactly.

The number of output blocks, called $G$, is:

$$
G=n_Mn_N.
$$

Let $F=q_Mq_N$ be the number of 16-by-16 output fragments in a block. Four warps share them in cyclic order. The maximum number owned by one warp, called $s$, is:

$$
s=\lceil F/4\rceil.
$$

This captures the longest warp's accumulation work, including uneven assignment. Let $r$ denote the maximum allowed block residency per multiprocessor. The model calculates it from threads, allocated registers, and shared memory. With 170 multiprocessors, the block-wave count $w$ is:

$$
w=\lceil G/(170r)\rceil.
$$

This ceiling charges for a partly filled final wave. It is a scheduling approximation: real blocks need not execute in perfectly synchronized waves.

Three counts describe a block's repeated phases. Let $H$ count short reduction stages, which have a distinct observed cost when $q_K=1$:

$$
H=n_K\mathbf{1}_{q_K=1}.
$$

The indicator is one for a 16-deep tile and zero otherwise. Let $U$ count Tensor Core fragment steps on the most heavily loaded warp:

$$
U=n_Ks q_K.
$$

Let $V$ count staged operand volume in units of 512 bytes:

$$
V=n_K(q_M+q_N)q_K.
$$

These are counts derived from the source, not measured whole-tile costs. Their coefficients are empirical effective service costs; they are not isolated hardware instruction latencies.

## Two scheduling bounds, with sequential phase costs

Let $T$ be predicted kernel latency in milliseconds. The first bound estimates the longest block path, called $T_{path}$. It combines a fixed path cost $c_0$, short-stage cost $c_H$, fragment-step cost $c_U$, and staging cost $c_V$:

$$
T_{path}=c_0+c_HH+c_UU+c_VV.
$$

The second bound estimates service across the whole grid, called $T_{grid}$. Its nonnegative empirical coefficients are $a_0$ for a fixed aggregate cost, $a_W$ for wave-stage cost, $a_R$ for residency-dependent fragment service, $a_I$ for aggregate instruction service, and $a_H$ for aggregate short-stage service:

$$
T_{grid}=a_0+a_Wwn_K+a_R\frac{GU}{170r}+a_I\frac{GU}{170}+a_H\frac{GH}{170}.
$$

The fixed costs are fitted intercepts, not measurements of CUDA launch overhead. The reciprocal residency term expresses the hypothesis that concurrent blocks hide some latency. The wave term represents repeated stage costs when the grid exceeds simultaneous capacity. Aggregate instruction work still consumes service even when latency is hidden.

The optimization minimizes $T$ while enforcing both bounds:

$$
T\ge T_{path}.
$$

The grid bound supplies the second constraint:

$$
T\ge T_{grid}.
$$

Taking the larger of these scheduling bounds does not claim overlap between loading, synchronization, and computation inside a block. Those contributions are already summed within each bound. Other candidate terms received zero coefficients during the declared fit and remain recorded in [model.json](model.json).

## Resource limits and MILP reformulation

The register model uses a conservative compiler-derived envelope indexed by fragment-slot count and reduction-depth regime. These 36 resource regimes are not complete tile triples and contain no benchmark latency. Many row/column combinations share one regime. The model rounds register allocation to a consistent per-warp granularity, includes the shared-memory block reservation, and selects the exact minimum of thread, register, and shared-memory residency bounds. The reconstructed resource rule matches all 144 original CUDA occupancy-API observations. It is an inference checked on this domain, not a claim about every NVIDIA GPU. Shared-memory granularity is not uniquely identified by these allocations, which are all multiples of 512 bytes.

One-hot variables represent the small residency levels from one through 12. They enforce feasibility and require a resource to block the next residency level. Each reciprocal term is then a linear sum of products with residency indicators: within level $r$, division by $r$ is multiplication by a known constant. Bounded-integer binary products express $G$, $s$, $U$, $V$, and the wave ceiling exactly. No binary variable selects a complete tile or its measured performance.

The resulting MILPs used 230–244 variables and 406–427 constraints. Both held-out shapes solved with zero reported optimality gap in approximately 0.25 seconds. Independent enumeration agreed with the optimum. Tests fixed every one of the 144 tiles and verified its objective, residency, and wave count against direct calculation.

## Calibration and confirmation boundary

[contract.json](contract.json) records the experiment before new measurements. Fourteen development tile configurations were measured on 768-by-768-by-1,024 and 2,048-by-2,048-by-1,024 shapes. Four shared-memory-reservation controls and six output-grid controls completed the development data. Models were fitted separately to grids that fit simultaneous residency and grids that exceeded it, using nonnegative least squares weighted by inverse measured latency. This minimizes squared relative error in each declared subset. Repeated controlled conditions retain their declared observations and weights.

The coefficients and solver choices were frozen before measuring all 144 tiles on each new 640-cubed and 1,536-cubed shape. Compiler-resource metadata from the original domain were permitted inputs; new confirmation timings were excluded from fitting and selection. This tests new shapes, not an entirely unseen GPU or kernel family.

## Memory-model boundary

The revision removes the claim that all requested bytes must be serviced at GDDR7 bandwidth. Requested bytes are not necessarily physical off-chip traffic. The staging terms instead use measured effective phase costs on the actual hardware. These costs can reflect behavior of the existing memory hierarchy, although no explicit L2-capacity, hit-rate, or reuse term is modeled. This is not a cache-free experiment and is not a complete GDDR7 transaction model. The 512 MiB sweep precedes every timed launch but cannot prevent reuse within a launch.

The held-out results determine whether this restricted empirical model improves selection. They do not establish an isolated causal decomposition of every fitted coefficient. A future memory-traffic model must account for this evidence boundary rather than insert an arbitrary tile-specific correction factor.
