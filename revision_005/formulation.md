# A tile model with staging, control, and partial-wave costs

This revision asks whether the physical differences observed between two correct GEMM kernels can improve tile selection on new workloads. Earlier profiling found equal matrix arithmetic but substantially less operand staging and loop control for a larger output tile. A separate experiment found sharp time increases near resident-block capacity. The model therefore distinguishes arithmetic demand, staging demand, shared-memory service demand, and scheduling capacity. It excludes an explicit L2 term.

## Fixed setup and independent decisions

GEMM multiplies an M-by-K input by a K-by-N input. Each block has 128 threads and stages BF16 inputs in shared memory before computing FP32 accumulators with 16-by-16-by-16 WMMA instructions. Row-major layouts, one input-buffer stage, and cyclic distribution of output fragments across four warps remain fixed.

Let BM, BN, and BK denote a block's output rows, output columns, and reduction depth. The independent integer decisions qM, qN, and qK express these dimensions in units of sixteen. The first two quotients range from one to six; the third from one to four. There are 144 combinations, but no binary variable selects a complete tile triple.

Let nM, nN, and nK count tiles along each matrix dimension, with each count obtained by dividing the matrix extent by its tile extent and rounding upward. Let G = nM × nN be the number of output blocks. Let F = qM × qN be the output fragments per block; s = ceiling(F/4) is the largest fragment burden of any warp, and p = minimum(4,F) counts warps that compute output fragments. All four warps still stage data and synchronize.

Let r be predicted resident blocks per multiprocessor. We retain the earlier conservative compiler register envelope, indexed by s, qK, and p. Registers round to multiples of eight words per thread. Residency is the minimum allowed by 1,536 threads, 65,536 register words, and 102,400 shared bytes per multiprocessor. Shared demand includes the input buffers, 4,096 bytes of output scratch, and the measured 1,024-byte launch reservation. Let w = ceiling(G/(170r)) be rounded whole-device waves. The 170 is the queried multiprocessor count.

## Deriving the demand counts

Each reduction stage performs qK instruction-depth steps. The largest per-warp matrix burden, U, is therefore:

$$
U=nK\,s\,qK.
$$

The exact total fragment-step count per block, Z, instead uses every output fragment:

$$
Z=nK\,F\,qK.
$$

Across the whole grid, four compiled matrix instructions per fragment step give 4GZ matrix instructions for this kernel. Profiling the diagnosed pair confirmed equal matrix-instruction counts despite different staging counts.

Define A = nK × qM × qK and B = nK × qN × qK as first- and second-operand staging counts. One source stage has 256qMqK first-operand scalar elements and 256qNqK second-operand elements. With thirty-two participating lanes per warp, the full-block global-load demand on interior blocks is 8(A+B) warp instructions. Across the grid it is 8G(A+B). Shared staging writes have the same leading count. Edge predicates and output stores add work; this is not a physical DRAM-byte count.

The source executes two block barriers per stage. Across G blocks the block-stage synchronization count is 2GnK. Loop and address overhead also recurs with stages and staging accesses. The aggregate control feature GnK represents this recurring demand; its fitted coefficient is not the isolated latency of a barrier.

Let H equal nK when qK is one and zero otherwise. Let O equal nK when qK is three and zero otherwise. These retain the measured short- and odd-depth distinctions from the earlier model.

## Shared-memory service approximation

Let dK be the greatest common divisor of qK and four, and dN the greatest common divisor of qN and four. The proposed per-block shared-load service proxy is Z(dK+dN). It summarizes row-alignment patterns for the unpadded source, rather than reconstructing individual WMMA lane addresses. A twelve-profile development check fits measured shared-load service wavefronts using GF for output work and GZ dK and GZ dN for the two operand contributions. Its maximum relative count error was 0.33% on those profiles. All profiles use the same 384-by-512-by-256 development workload, so this is a bounded approximation check, not universal validation.

Define V = U(dK+dN) for the sequential per-warp estimate. Define Q = Z(dK+dN) for the actual per-block aggregate count. Cost coefficients absorb the fixed scale between these units and measured service wavefronts. We do not minimize conflict count in isolation: the earlier padding controls showed that reducing conflicts can worsen execution time through other effects.

## Sequential path and aggregate service

For each productive-warp class p, fit nonnegative sequential coefficients to the feature vector:

$$
[1,nK,U,A,B,H,O,V].
$$

Their weighted sum is a sequential time estimate S. The first coefficient is fixed overhead. Let P be the remaining sum, excluding that fixed overhead. S and P are time estimates in milliseconds, not isolated instruction latencies.

The aggregate estimate uses another nonnegative coefficient vector on:

$$
[1,wP,GP/(170r),GZ/170,G(A+B)/170,GnK/170,GQ/170,GH/170,GO/170].
$$

The rounded-wave term wP and fractional-capacity term GP/(170r) allow partial waves to have a different cost from full waves. Their coefficients are learned separately; they are not constrained to sum to one. The remaining terms represent whole-device arithmetic issue, staging, control, and shared service. This is a richer approximation of scheduling, not a discrete simulation of block arrival and completion.

The predicted time is the larger of S and the aggregate estimate. A continuous time variable above both expressions, minimized by the MILP, implements that maximum. Inverse-residency selection ranges over one through twelve. Greatest-common-divisor values use finite quotient indicators. Bounded integer products use exact binary expansions and binary-times-bounded-variable constraints. Because P is a weighted sum of integer counts with fixed coefficients, multiplying it by w or G/r distributes into these same exact count products. No nonlinear time variable is multiplied by a decision.

## Fitting, verification, and boundaries

The fit combines sixty new timings at three development shapes with preserved revision 003 and unmodified diagnostic 004 measurements. Repeated conditions are merged by their median. There are 194 distinct conditions from 236 timing executions. Sequential coefficients use grids fitting within predicted resident capacity; aggregate coefficients use larger grids. Both fits minimize squared relative time error with nonnegative least squares.

The feature matrices are not all full rank. Several physical demands remain correlated, especially in the smaller productive-warp classes. Consequently, fitted coefficients are effective costs and zero coefficients do not prove a mechanism absent. Good count reconstruction alone does not identify its latency contribution.

Independent direct evaluation checks both the unconstrained optimum and all 144 fixed tiles on each new confirmation shape. The first backend setting, feasibility tolerance one billionth, rejected a known fixed feasible tile; both presolve settings showed that failure. Using one hundred-millionth tolerance made all fixed-tile checks agree to six decimal places in milliseconds. The failed case is preserved. Neither solver status nor a reported zero gap substitutes for these independent checks.

The model, solver sources, and selected tiles are hashed before hardware confirmation. Confirmation shapes are 960-by-1,152-by-640 and 1,728-by-2,112-by-2,304. The current hardware has not supplied timings for either shape at the time of freezing. All 144 tiles on both shapes will be measured; their results will test selection accuracy rather than refine the coefficients after the fact.

The model remains limited to this kernel family and bounded tile domain. Compiler register envelopes, imperfect wave scheduling, edge effects, correlated coefficients, and unmodeled cache behavior can still reverse ordering. The experiment tests whether the measured physical distinctions improve decisions, not whether every cycle of GPU execution has been explained.
