# A first mixed-integer search over multistage matrix multiplication

Can a small mathematical search express the tile, buffering and split-reduction choices identified in the fast cuBLASLt implementation? This first model can. It chooses a 64×64 output tile, reduction stages of 32 elements and four reduction partitions, with a provisional time of 13.566 microseconds. Buffer counts 2, 3, 4 and 6 tie; the solver returned 6, which is not evidence that six buffers are uniquely necessary. This is a structural performance proxy, not a validated CUDA implementation or hardware optimum.

The workload multiplies a 192×3072 matrix by a 3072×768 matrix, with BF16 inputs (16-bit floating point) and FP32 accumulation (32-bit floating point). Split reduction, also called split-K, assigns different portions of the 3072-element dot products to separate blocks and then combines their partial results. The domain allows tile dimensions 32 or 64, stage length 32, split counts 1, 2, 4, 8 or 16, and 1,2, 3, 4 or 6 shared-memory buffers. All 100 combinations fit the declared limits. Hardware remains fixed at 170 streaming multiprocessors (SMs), which are GPU compute clusters, and four 32-thread warps per block.

## Resource constraints

For tile dimensions m and n, stage length k=32 and buffer count b, input staging needs `2k(m+n)b` shared-memory bytes. The factor 2 is the number of bytes per BF16 input. Each selected block must fit 101,376 bytes; all its resident blocks together must fit 102,400 bytes per SM. The saved hardware specification also supplies 65,536 register words, 48 resident warps and 24 resident blocks per SM. See [the recorded capacities](../rtl/manual/00_gpu_overview.md).

Register allocation is a declared estimator, not a compiler result: 32 control words per thread, `ceil(mn/128)` FP32 accumulator words, and `ceil(k(m+n)/128)` double-buffered operand words. It reproduces the captured 64×64 configuration's 96 registers per thread but is unverified for other generated kernels. Residency is the minimum allowed by registers, shared memory, warps and blocks. For the returned 64×64, six-buffer configuration, shared allocation is 49,152 bytes and the estimated register allocation is 12,288 words per block. Registers permit five blocks, whereas shared memory permits two; residency is therefore two blocks per SM.

Split counts greater than one reserve `4×192×768×split` workspace bytes for partial FP32 outputs. The budget is 64 MiB. Four partitions need 2,359,296 bytes; the captured eight-partition configuration needs 4,718,592 bytes. This exact latter value matches the library capture. Logical task counts are 144 and 288 respectively. The library actually launched 384 main blocks, whose padding and mapping are not reconstructed here; this model does not pretend to reproduce that grid.

## How timing enters the mixed-integer program

A mixed-integer program (MIP) combines yes/no choices with numerical constraints. Here 100 binary variables select one legal configuration. For each configuration, a continuous variable represents the spacing between successive reduction stages. Two further variables represent the main kernel and reduction duration, and the objective minimizes their sum plus the launch allowance.

The model calculates demand from matrix dimensions, rather than reading measured candidate runtimes. It charges every logical staged input byte to warm L2 service at the transferred 3.444-terabyte-per-second bandwidth prior. Each active SM receives an equal share of that chip bandwidth. If fewer than 170 SMs have tasks, the model reduces available aggregate bandwidth proportionally. This fairness rule is a hypothesis about resource sharing, not a recovered cache mapping.

Each 16×8×16 matrix instruction accounts for 4,096 floating-point operations. A stage's instruction demand follows from `2mnk/4096`. Compute time is bounded by an eight-cycle acceptance interval across four assumed matrix-issue partitions, an effective 64-cycle accumulator dependency per 16-element reduction, and ideal conflict-free shared service at 128 bytes per cycle. The 64-cycle/eight-cycle prior comes from [the earlier isolated-register checks](../step18_compute_isolation_001/compute64_prospective_validation.json); transferring it to this multistage family is unvalidated. Four scheduler partitions do not independently establish four full-rate tensor pipelines.

With one buffer, stage spacing is at least copy service plus compute service. With two or more buffers, it is at least each service demand and `340/(b−1)` cycles, a provisional bound for hiding operand-return waiting. The 340-cycle prior came from a scalar-load readiness probe and is transferred here to tile arrival; that transfer is especially uncertain for asynchronous bulk copies. Per-SM task waves add startup and drain costs. Separate constraints retain the whole-chip input and workspace-write demand even when local work overlaps.

The reduction kernel charges reading all partial results, writing the final output and adding the partial values. Memory time and ideal scalar-add service are alternatives in a maximum, rather than additive wait percentages. Its launch adds another 3,346-cycle allowance. The same allowance is applied to the main kernel. It comes from the older simulator's startup convention and is not a measured CUDA launch overhead. Cycle-to-time conversion uses 2,940 cycles per microsecond.

These stage, demand and reduction bounds are conditional on the chosen binary configuration. No coefficient is a measured total runtime of a candidate. The executable formulas and exact parameter scope are in [the frozen contract](frozen_contract.json) and [solver source](solve.py). The bandwidth prior's original raw measurement receipt has not been located in this bounded round; it remains a transferred prior, not newly verified evidence.

## The exact selection and timing constraints

Let j identify one of the 100 resource-feasible profiles. A binary selector x_j is one when that profile is chosen; its continuous stage spacing p_j is zero when it is not chosen. Let T_main, T_red and T_total denote the main-kernel, reduction-kernel and total durations, in cycles. All duration variables are nonnegative and bounded by H = 10,000,000 cycles. This finite bound is only a numerical modeling horizon.

For profile j, w_j is its number of task waves, s_j its stages per task, a_j its startup cost and u_j its workspace-write cost. The constant d_j is its whole-chip copy plus workspace-write bound; r_j is its reduction plus extra-launch cost. Each c_jq is one applicable copy, compute or return-wait bound on stage spacing. These constants are derived from the preceding demand rules. The implemented constraints are:

```text
sum_j x_j = 1                         x_j is binary
0 <= p_j <= H*x_j
p_j >= c_jq*x_j                       for every applicable service bound q
T_main >= w_j*(a_j + (s_j-1)*p_j) + u_j - H*(1-x_j)
T_main >= d_j*x_j
T_red >= r_j*x_j
T_total >= 3346 + T_main + T_red
minimize T_total
```

The large horizon disables the unchosen profiles' local-duration constraints. Resource limits are checked before a profile enters this domain; this proves feasibility under the declared resource estimator, not that a compiler can produce the proposed CUDA kernel. A chosen tile dimension, split count or buffer count is recovered by summing that profile property times x_j. Buffer ties therefore remain ties rather than new hardware facts.

## Result and independent check

| Configuration represented in this model | Provisional time |
|---|---:|
| Hypothetical 32×32 staged tile, no split, one buffer |24.727 µs|
| Selected 64×64 tile, split 4, buffers 2/3/4/6 tied |13.566 µs|
| Logical configuration matching the captured 64×64, split 8, six-buffer choices |14.980 µs|

The first row is a hypothetical staged reference. It is not the original direct-load CUDA kernel, so its prediction must not be used to calculate that kernel's error. The third row uses the library's configuration choices but lacks its exact instruction schedule and padded launch mapping. The earlier physical cuBLASLt measurement of about 9.200 microseconds remains context from [the library-mechanism study](../cublas_comparison_001/winner_mechanisms.md), not a matched validation of this proxy. The solver did not consume that runtime.

SciPy 1.18.0 with HiGHS 1.12.0 solves 203 variables, including 100 binary selectors, and 662 constraints to zero reported optimality gap. Independent enumeration of all 100 configurations gives the same minimum. The initial solve with presolve enabled returned a solver error, which is preserved in [the failure receipt](initial_solver_failure.json); disabling presolve solved the unchanged physical model. [The current result](result.json) records solver time, preparation time, enumeration time and numerical constraint residual. These costs exclude Python imports and output serialization. Enumeration is cheaper for this tiny domain; this is not a claim of search acceleration.

The bounded conclusion is that resource allocation, stage overlap, split reduction and its workspace cost can be expressed and solved together. The preferred split differs from the captured library's eight partitions, and buffering depth is not identified uniquely. The next useful work is to establish compiled resource use and transfer validity for this declared kernel family before treating its selected configuration or timing as a physical recommendation. No GPU or Verilog workload was run for this search.
