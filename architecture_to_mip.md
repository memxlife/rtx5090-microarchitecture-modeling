# Reverse engineering RTX 5090 execution: from GEMM experiments to a mixed-integer formulation

## 1. Purpose: discover the hardware structure that determines kernel performance

What hardware behavior must we understand to formulate matrix multiplication optimization as a mixed-integer program? That is the purpose of this investigation. We use benchmarks to uncover how the RTX 5090 executes a kernel, construct a performance model from that understanding, and translate the supported mechanisms into mathematical decisions and constraints.

This order matters. A solver can optimize an inaccurate cost model perfectly and still choose a slow kernel. Conversely, a fitted formula can predict several runtimes accurately without explaining the hardware mechanisms needed to evaluate a new instruction schedule. We need an account of execution that explains why a kernel waits, which work can overlap, and which resources limit progress.

The investigation therefore has three connected outputs:

- An architecture description explaining the parts of RTX 5090 execution encountered by our kernel.
- A performance model whose assumptions, parameters, and limits follow from experiments.
- A mixed-integer formulation expressing kernel decisions using that physical structure.

Success requires both prediction accuracy and useful optimization decisions on cases not used to determine the parameters. The real GPU supplies the final evidence. Solver optimality establishes the best solution to the equations we gave it; it does not establish that those equations describe the GPU correctly.

This article reconstructs the discovery process before presenting the architecture and mathematics. The largest observed error of the current independently calibrated model is 5.97% within its tested domain. That is meaningful progress, but it does not establish a complete reconstruction of NVIDIA's microarchitecture or an accurate optimizer over arbitrary kernel transformations.

## 2. Experimental setup: the hardware and program we studied

### 2.1 Matrix multiplication and the work assigned to a block

GEMM means general matrix multiplication. Our program multiplies a matrix A with M rows and K columns by a matrix B with K rows and N columns. It produces a matrix C with M rows and N columns. Each output element sums K products. Inputs use BF16, a 16-bit floating-point format; accumulation and output use 32-bit floating point.

A thread block computes an output tile containing BM rows and BN columns. A block contains four warps, each a group of 32 threads. It processes BK reduction elements at a time. Most mechanism experiments fix BK at 32 and compare tiles of 32 × 32 and 64 × 48. The original formulation experiment allowed additional tile dimensions; those historical choices do not inherit the accuracy of the later two-tile model.

When dimensions divide exactly, the number of blocks is (M/BM)(N/BN), and the number of repeated reduction steps is K/BK. Partial tiles require masked accesses and sometimes padded arithmetic. They are excluded from later full-tile comparisons unless explicitly tested.

### 2.2 Hardware visible to this program

The tested RTX 5090 has 170 streaming multiprocessors, abbreviated SMs. An SM executes warps and provides their registers and shared memory. Registers hold each thread's working values. Shared memory holds values that threads in one block cooperate on. The GPU has a 96 MiB L2 cache shared across SMs and GDDR7 device memory. A MiB is 1,048,576 bytes.

Our compiled kernel uses ordinary global loads into registers followed by stores into shared memory. It then loads matrix operands from shared memory, rearranges register values, and executes Tensor Core matrix instructions. Two block barriers protect each repeated step. A barrier requires the participating threads to reach a synchronization point before they continue.

This is a particular execution path. We did not independently characterize special function units, every arithmetic instruction, all asynchronous transfer mechanisms, or every possible Tensor Core programming interface.

### 2.3 What a measurement establishes

Ordinary GPU event timings measure elapsed kernel time. Most recent validation results use the median of nine samples, each averaging five launches, with numerical outputs checked. Historical experiments sometimes use different repetition schemes, which their linked reports specify.

We inspect the compiled native instruction sequence, resource allocation, and profiler counters before transferring a probe's costs to GEMM. Profiler runs can change cache and clock conditions; their durations are not automatically interchangeable with ordinary timings. Correct numerical output alone does not establish that a benchmark preserves the execution path we intended to measure.

Prediction error is defined before comparison:

$$
\text{relative error}=\frac{|\text{predicted time}-\text{measured time}|}{\text{measured time}}.
$$

Lower error is better. We distinguish errors in complete runtime, errors in additional runtime between two reduction lengths, errors in traffic counts, and errors in a controlled probe. A small error in one quantity does not establish accuracy in the others.

## 3. Discovery method: follow the largest consequential mismatch

A large prediction error is useful because it exposes an assumption that may be missing a substantial part of execution. Our most effective investigations followed a short loop: predict, measure, identify the largest mismatch, reproduce it with the simplest benchmark, distinguish explanations, update the model, and validate the update separately.

The diagnostic must retain the error it is meant to explain. Reducing a GEMM to a synthetic loop is useful only if the relevant instruction path and waiting behavior survive. If a source change causes the compiler to remove operand loads or change load grouping, the resulting benchmark answers a different question.

Each meaningful result must change the model in one of three ways. It can supply a supported term, extend a bounded domain, or reject an explanation. A negative result is valuable when it prevents an unjustified constraint or timing coefficient. A new coefficient is not the required outcome of every test.

The principle is to prioritize errors with the greatest effect on our understanding or optimization decisions. Small discrepancies matter when they become the largest remaining error or reverse the preferred configuration. We should not spend equal effort explaining a minor effect while a much larger unexplained error remains.

The practical conjecture underlying this method is that a major timing mismatch can often be retained in a smaller controlled workload. Reproducing it supports investigating the retained path; losing it redirects attention to the removed interactions. This is faster than expanding a detailed simulator before we know which mechanism needs explanation.

## 4. How the experiments changed our understanding

### 4.1 The first MILP was mathematically correct but physically too simple

**Initial assumption.** Total arithmetic work and requested memory bytes, divided by fixed effective rates, would provide a useful performance objective. Independent integer tile dimensions represented reuse, padding, and storage limits. Explicit L2 modeling was initially excluded at the user's request, while hardware caches remained active.

**Observed failure.** On the 1,008 × 1,008 × 1,008 workload, the MILP selected an 80 × 64 × 16 tile. It measured 0.205626 milliseconds, whereas the fastest measured tile, 32 × 32 × 32, took 0.065536 milliseconds. The selected tile was about 3.14 times slower; its prediction error was 79.2%. All 144 bounded configurations compiled, produced checked outputs, and avoided register spills.

**What this established.** The integer reformulation and executable kernel family worked. The timing model did not. Treating one effective throughput as constant across tiles hid the execution structure that determines whether the GPU can sustain that throughput.

**Model consequence.** Coverage and exact product reformulations remained useful. Constant-rate timing could no longer serve as the sole objective. The original [formulation and hardware results](docs/final_report.md) preserve these separate conclusions.

### 4.2 Resource capacity and repeated staging work affect tile ordering

**Missing structure.** A larger output tile performs more useful arithmetic per input-staging step, but launches fewer blocks and uses different resources per block. Total arithmetic alone cannot express that tradeoff.

**Diagnostic.** We compared the two later tiles on full-tile GEMMs, swept output size at fixed reduction length, varied reduction length at fixed output size, and limited residency using unused shared-memory reservations. Fixed-stride controls varied one output dimension while holding input row strides unchanged.

**Result.** At M = N = K = 1,920, the smaller tile uses 3,600 blocks and the larger uses 1,200. Matrix-instruction counts are equal, but the larger tile executes about 41.7% fewer global-load instructions and 28.0% fewer total warp instructions. Increasing grid size through the smaller tile's resident-capacity boundary produced a marked runtime increase, reproduced by the fixed-stride controls. Unused reservations also slowed both kernels. Yet the faster larger tile had lower achieved occupancy.

**Architectural learning.** Capacity determines how much work can reside at once; it is not a direct measure of useful throughput. Reuse within a block reduces staging and control demand. Both effects belong in the performance model.

**Boundary.** Reservation also affects the shared-memory/L1 allocation context, and blocks do not execute in synchronized waves. These controls do not identify a pure scheduling latency. The [detailed diagnosis](diagnostic_004/final_report.md) records the matched comparisons.

### 4.3 Corrected matrix probes did not support a large accumulator-dependency penalty

**Hypothesis.** Reusing one accumulator chain might introduce substantial waiting, which multiple independent chains could hide.

**Diagnostic.** We repeated register-resident matrix operations with one to eight independent accumulator chains, keeping operation count and loop count fixed. Every output was consumed. Native instructions and register allocation were checked.

**Result.** One and four active warps each took approximately 64 cycles per matrix operation per warp. Eight warps took approximately 128. Independent chains did not materially improve these costs. An earlier apparent 10% benefit came from a flawed probe that let the compiler discard outputs and changed loop counts; it was superseded.

**Architectural learning.** Aggregate throughput initially scales with available warps, then reaches a ceiling between the tested four- and eight-warp settings. The corrected evidence does not justify a large independent-chain benefit for this primitive.

**Boundary.** This does not identify the exact limiting pipeline or intrinsic latency of one native matrix instruction. The [corrected matrix experiment](diagnostic_006/results.md) supports a bounded capacity observation.

### 4.4 Memory instruction arrangement matters more than byte counts alone

**Hypothesis.** Grouping loads could expose more simultaneous requests and shorten waiting.

**Diagnostic.** Staging-only, computation-only, and combined probes varied load arrangement. Promising probe changes were then tested in complete GEMM kernels, with residency controls and instruction inspection.

**Result.** A change that helped a probe slowed all four complete-GEMM comparisons by roughly 8–19%. Equal global-load, shared-memory, and sector counts did not imply equal runtime. The changed kernels executed more instructions and had different dependency schedules. Separate experiments also found that internal timestamps could slow the larger tile by more than 50%, even without spills or a reduced resident-block limit.

**Architectural learning.** The compiled sequence determines which requests precede their consuming stores and how independent work can overlap. A source-level optimization and an intrusive measurement can change that sequence.

**Model consequence.** We retained compiled instruction form and grouping as conditions for admitting costs. We rejected transferring the probe speedup or disturbed timestamp values into the original kernel's model. See [staging transfer tests](diagnostic_007/results.md) and [instrumentation controls](diagnostic_008/results.md).

### 4.5 L2 state requires reuse order; hit totals do not determine waiting

**Initial approximation.** A cache model could price requests from capacity or an average hit fraction.

**State experiment.** A controlled pointer traversal warmed a 16 MiB region, applied cache pressure, and optionally refreshed the region before more pressure. The refreshed case retained all cached-like reads, whereas its control retained about 47%. A recency-sensitive replacement model described these sequences better than the tested simple FIFO alternative. Two allocation-tag size candidates remained consistent with the evidence.

**Traffic result.** An interleaved trace matched source-specific L2 request, hit, and miss sector counts for a GEMM with 100 MiB of distinct inputs on the 96 MiB cache. This showed that the data requiring simultaneous reuse can be smaller than the complete input footprint.

**Boundary.** The traversal's 2.5% timing result concerns that probe, not GEMM. Its latency classes are not exact hardware hit labels. Near full capacity, address placement changed the response in ways the fully associative model did not explain. Historical cache components therefore remain bounded evidence, not universally admitted runtime parameters. See [the cache-state investigation](diagnostic_010/results.md).

**Timing experiment.** A subsequent four-load probe prepared the same 75% hit fraction in two arrangements. With one miss in every group, response cost was roughly 960–969 cycles per group. Concentrating misses into one quarter of the groups reduced cost to about 553 cycles. Requested work and source-specific cache totals were matched.

**Architectural learning.** The consumer waits for the values it needs, not an average of all values requested elsewhere. The same hit fraction can produce different dependency delays. The [mixed-cache experiment](diagnostic_020/results.md) rejected average-hit timing for that path.

A two-block control refined this further. Blocks starting together on shared fresh inputs both paid roughly the cold response cost, despite 50% aggregate L2 hits. Delaying the second block until data had arrived reduced its measured response loop to the cached cost, with the same source-specific hit fraction. The delay lengthened the launch overall; it was a diagnostic, not an optimization. This supports distinguishing data already available from a fetch still in progress, without identifying NVIDIA's exact request-merging hardware. See [data-readiness controls](diagnostic_021/results.md).

### 4.6 Accurate fitted runtimes did not finish the physical explanation

**Large mismatch.** A previous runtime model predicted 25.69 milliseconds against 18.82 milliseconds for a long-reduction smaller-tile GEMM, a 36.5% overestimate. The larger tile's error was 13.9%. Correct cache counts did not explain these timing errors.

**Diagnostic.** Reduction-length and block-count controls investigated whether the discrepancy accumulated with repeated work. Small instruction-path probes examined staging arrangement and shared inputs. Separate complete GEMMs were reserved for confirmation.

**Result.** Revised costs fitted to original-kernel development timings predicted six new full-tile cases with 2.33% median and 3.53% maximum error. Direct transfer of synthetic probe costs performed much worse, reaching 53.8–67.6% maximum error depending on the probe arrangement.

**Architectural learning.** Repeated-stage behavior was consequential, but a good calibrated stage cost was not an explanation of its origin. Fitting complete kernels and discovering transferable mechanisms must be reported separately. The [calibrated-model comparison](diagnostic_011/results.md) is retained as predictive progress rather than proof of microarchitectural reconstruction.

### 4.7 Independently measured components exposed further missing interactions

We next measured shared-bank demand, global-response grouping, operand preparation, and native dependency behavior separately. An address-derived bank model predicted shared-read processing counts closely, and an independent service measurement predicted the directions of new layout timing changes. Nevertheless, errors in those change magnitudes were about 17.5–20%. Accurate work counts were insufficient to explain all timing.

A sum of independently measured global, shared, and matrix costs missed complete-GEMM stage time by roughly 17–31%. Replacing separate operand terms with a compound operand-path measurement improved the model, but new warm GEMMs still showed 25.3% and 17.8% underestimates of additional runtime. A single-shared-resource scheduler also failed one prior primitive case by 24.7%. These failures were kept visible rather than absorbed into correction coefficients. See [bank-service tests](diagnostic_014/results.md), [failed stage composition](diagnostic_022/results.md), [scheduler counterexample](diagnostic_027/results.md), and [fresh compound-model validation](diagnostic_038/results.md).

Pointer controls provided another warning. A nominal pointer-reload removal slowed GEMM by more than twofold while changing global instruction form and load groups from four to one. It could not isolate pointer latency. A repaired comparison preserving explicit global form and four-load groups showed only a small net benefit, 3.25% and 0.86%, while other address instructions still changed. These results did not explain the large residual. The model rejected intrinsic pointer-latency attribution; see [the confounded control](diagnostic_042/results.md) and [its matched repair](diagnostic_043/results.md).

### 4.8 The largest error survived in one unchanged block

**Question.** Was competition between blocks necessary to create the remaining error?

**Minimal diagnostic.** Run one block of the unchanged kernel and compare the additional runtime between reduction lengths. The native instructions were preserved.

**Result.** Most of the smaller-tile discrepancy remained. Cross-block contention was unnecessary to create that discrepancy.

**Decision.** Prioritize the original block's staging and operand paths rather than adding concurrency coefficients. Measure three paths inside a controlled kernel family: common loop/barriers, actual staging plus common work, and actual operand computation plus common work. Compose the last two and subtract the common work once.

**Validation.** This actual-path model predicted new warm small-grid absolute runtimes within 4.20%; additional-runtime errors were within 4.36%. Independently measured cold-response differences also transferred to small-grid cold tests within 3.85%. Full-GEMM validation runtimes did not supply the coefficients. See [one-block evidence](diagnostic_045/verification.json), [smaller-tile validation](diagnostic_044/absolute_multi_verification.json), [larger-tile validation](diagnostic_046/verification.json), and [cold transfer](diagnostic_048/verification.json).

**Architectural learning.** Measuring the actual compiled path matters. This establishes an effective composition within the tested context, but it still does not divide staging into intrinsic address, request, store, and synchronization latencies.

### 4.9 Dense workloads revealed the next major error: perfect overlap

**Initial extrapolation.** Scale one-block costs by the number of resident-capacity waves and assume resident blocks overlap perfectly.

**Observed failure.** A dense smaller-tile case was underpredicted by roughly 60%. Once the single-block discrepancy was reduced, shared execution capacity became the major missing interaction.

**Diagnostic.** Measure the same isolated paths over dense grids, once with one allowed resident block per SM and once with normal residency. The first control exposes long dependency paths; the second exposes the service cost of processing many blocks through shared hardware.

**Model change.** For each path, take the larger of a latency-wave estimate and a shared-service estimate. Then compose the paths, subtracting common work once.

**Validation.** New dense smaller-tile cases had at most 5.97% error; larger-tile cases had at most 2.46%. A later unchanged-kernel control at one, four, and eleven allowed smaller-tile blocks transferred without new coefficients. At the longer reduction length, time fell from 2.981 milliseconds at one block to 0.693 milliseconds at eleven: about 4.3-fold, rather than elevenfold.

Profiles had identical dynamic instruction counts and 100% L2 hits across those residency settings. The results support finite shared service and imperfect hiding of waiting, but do not identify its exact resource. Clock differences and shared-memory/L1 partition effects remain unresolved. See [smaller dense tests](diagnostic_050/verification.json), [larger dense tests](diagnostic_051/verification.json), and [residency transfer](diagnostic_057/results.md).

### 4.10 Remaining corrections were tested rather than assumed

The composed isolated phases count about 4.1% more instructions than the original kernel. Dividing predicted time by that ratio helped shorter tests but worsened a longer case from 0.78% to 3.19% error. Aggregate counts cannot supply an admitted universal timing correction. A constant-mode probe was also rejected because compilation removed shared operand loads.

Dense tests with 128 MiB of inputs again rejected an all-miss rule based on footprint alone. After correcting overlapping timing regions, clearing the cache before every launch increased runtime by 2.24% relative to preheating. This remains an observation rather than a general dense cold-cache timing equation.

Minimal profiles reported different SM rates for staging, computation, and complete GEMM. Host clock snapshots did not measure average in-kernel frequency. A reference-clock sensitivity calculation did not justify blindly rescaling all phase costs. Consequently, none of these last tests changed the active timing coefficients or eliminated the approximately 6% largest error. See [instruction correction](diagnostic_056/results.md), [strict cache preparation](diagnostic_055/verification.json), and [clock controls](diagnostic_058/results.md).

## 5. The architecture description that follows from the evidence

### 5.1 Execution is a graph of data readiness and resource use

For each repeated step, input addresses must be produced before loads issue. A load returns a value to a register; a dependent shared store needs that value. The staging barrier protects operand consumption. Shared reads and register rearrangements prepare matrix operands; matrix instructions update accumulators. The final barrier protects the next reuse of shared storage.

This graph describes necessary ordering. It does not force unrelated operations in different warps to execute serially. Warp scheduling can make progress on ready work while another warp waits. The degree of useful overlap depends on what work is ready and which shared resources can serve it.

### 5.2 Capacity, latency, and service are different quantities

Capacity describes how much work can reside at once. Latency describes the elapsed delay along a necessary dependency path. Service describes the work a finite resource must process. A resource can admit another instruction before an earlier instruction's output is ready, so latency and initiation rate need not be equal.

The corrected matrix probe and residency controls establish that increased concurrency eventually encounters shared limits. The current dense model represents those limits through effective path service measurements. It does not determine whether a particular measured limit belongs to instruction issue, operand collection, memory processing, or another internal structure.

### 5.3 Cache contents and data availability are separate state

A cache-content approximation follows address tags, valid sectors, and reuse/replacement order. A timing model additionally needs the arrival time of data still being fetched. Requesting an address once is not sufficient evidence that its value is immediately available to another consumer.

The evidence supports recency-sensitive behavior in controlled sequences, request-group waiting determined by needed values, and possible reuse while input stages remain active. Exact replacement, address mapping, asynchronous fills, and partially ready requests remain incomplete. The active runtime model uses only bounded approximations supported by its own tests.

### 5.4 What is established and what remains an approximation

| Mechanism | Evidence-supported conclusion | Remaining boundary |
|---|---|---|
| Compiled dependencies | Load grouping and consuming stores affect execution | No complete intrinsic instruction-latency inventory |
| Shared-memory banks | Tested lane addresses predict service demand | Demand is not identical to exposed kernel delay |
| Resident blocks | Resource capacity and grid size affect runtime | Reservation does not isolate scheduling from memory partitioning |
| Matrix execution | Tested register-resident throughput saturates | Exact limiting internal resource unidentified |
| L2 reuse | Access order and reuse lifetime matter | Exact mapping and replacement not recovered |
| Pending data | Reused fresh data may still require waiting | Intermediate arrival states unvalidated |
| Actual-path composition | Independent path costs transfer in bounded cases | Interactions and measurement overhead not fully separated |
| Dense service | Perfect resident overlap is insufficient | Effective service costs are not a cycle-exact resource model |

These are the parts of execution the experiments explain. The remaining uncertainty is part of the architecture description, because it limits which kernel transformations the mathematics can price honestly.

## 6. Deriving the current performance model

### 6.1 Small grids: combine actual paths without counting common work twice

Let H be the number of reduction steps, K/32. For path p, let f_p be its effective fixed cost and h_p its measured cost per step, both in microseconds. Path 0 is common loop/barrier work, path 1 is staging plus common work, and path 2 is operand computation plus common work. Each isolated path prediction is:

$$
P_p=f_p+Hh_p.
$$

The composed full-kernel prediction is:

$$
T=P_1+P_2-P_0.
$$

For the smaller tile, the measured values are:

| Path | Fixed cost, microseconds | Cost per step, microseconds |
|---|---:|---:|
| Common work | 2.739201 | 0.037325 |
| Staging plus common work | 2.995198 | 0.780275 |
| Operand computation plus common work | 3.541333 | 0.202142 |

The composed fixed cost is 3.797330 microseconds, and the composed step cost is 0.945092 microseconds. This is a hypothesis about effective path composition, subsequently supported on listed full-GEMM cases. It is not derived by adding an assumed latency for each individual instruction.

For the validated small-grid cold context, a separately measured increment is added per dependent request group. Let g be four groups for the smaller tile or seven for the larger, and let delta be 0.2095019 microseconds per group. The cold increment per step is g times delta. This term does not describe arbitrary mixed cache states or dense cold execution.

The [small-grid implementation](model_components/runtime_v3.py) and [parameters](model_components/actual_path_parameters.json) define the accepted inputs. The implementation accepts a bounded reduction range; direct evidence is at the recorded tested lengths, so acceptance of an intermediate length is interpolation rather than a separate hardware validation.

### 6.2 Dense grids: dependency time and service work each impose a limit

Let B be total output blocks, R the allowed resident blocks per SM, and n the number of SMs, 170. For each path p, L_p is its one-resident per-step measurement normalized by the calibration grid's groups per SM. S_p is its normal-residency service measurement normalized the same way. Specifically, divide each calibration slope by ceil(B_base/170), where B_base is 3,600 blocks for the smaller tile and 1,200 for the larger. Both are effective microsecond costs derived from isolated paths.

The latency-wave estimate is:

$$
A_p=\left\lceil B/(nR)\right\rceil L_p.
$$

The shared-service estimate is:

$$
E_p=\left\lceil B/n\right\rceil S_p.
$$

The effective per-step cost is:

$$
q_p=\max(A_p,E_p).
$$

A path cannot be predicted to finish before either modeled limitation permits. With F_p the fixed path cost scaled by block count exactly as in the executable model, the path prediction becomes:

$$
P_p=F_p+Hq_p.
$$

The full prediction again uses P_1 + P_2 − P_0. Taking the maximum separately for each path is an experimentally tested approximation. It is not a theorem that those phase interactions exactly reproduce complete execution.

The [dense implementation](model_components/dense_runtime.py) restricts shapes, reduction lengths, tiles, and residency settings. It scales fixed costs with block count and retains the normal-residency fixed coefficients even when the allowed residency changes. That engineering approximation is part of the tested model, not a reconstructed law of startup behavior.

### 6.3 Reference cycles make the units consistent, not the mechanisms complete

Choose a reference SM frequency f_ref of 2.94 GHz. A GHz means one billion cycles per second. If T_us is a duration in microseconds, its reference-cycle equivalent C_ref is:

$$
C_{\mathrm{ref}}=2940T_{\mathrm{us}}.
$$

Thus the smaller tile's composed 0.945092-microsecond step equals about 2,778.57 reference cycles. These are converted time units. They are not a direct cycle-counter observation of that complete step at a constant clock, nor memory-clock cycles. Choosing another reference rescales all quantities consistently and does not change the optimizer's ranking.

To predict operation under a different physical clock, we would need to separate clock-sensitive computation from memory response and other domains. The existing clock controls do not yet support that separation.

## 7. Deriving a mixed-integer formulation from the architecture

### 7.1 The intended optimization problem

For a fixed GEMM and numerical contract, choose tile dimensions, work assignment, storage layout, and supported scheduling decisions to minimize predicted completion time. A mixed-integer program (MIP) combines integer choices with continuous quantities such as time. A MILP requires its objective and constraints to be linear after reformulation.

We distinguish three levels of readiness. Coverage and bounded-product arithmetic already have exact MILP constructions. Effective path timing supports only the tested configurations. A general instruction-scheduling formulation has identifiable physical constraints but still lacks independently validated timing and resource parameters. The following derivation keeps these levels explicit.

### 7.2 Tile variables express reuse, coverage, and padding

Let BM, BN, and BK be positive integer tile dimensions in a declared domain. Let n_M, n_N, and n_K be the integer numbers of tiles along the three matrix axes. For rows, coverage requires:

$$
n_M BM\geq M.
$$

Minimality of the tile count requires:

$$
(n_M-1)BM\leq M-1.
$$

Together they express n_M = ceil(M/BM). The column and reduction axes use the same construction. Let B equal n_M n_N and H equal n_K. For the current actual-path timing model, BK must remain 32, and tested full tiles require exact output divisibility. A future padded-work model must price masked loads and extra arithmetic instead of borrowing the full-tile coefficients.

The original kernel's single input-buffer pair and output scratch require shared-memory bytes s:

$$
s=2BK(BM+BN)+4096.
$$

The factor two is bytes per BF16 input; 4,096 bytes is this kernel family's output-fragment scratch. Layout padding or extra buffers change this equation. They must be explicit decisions with corresponding producer and consumer address calculations.

### 7.3 Resource constraints determine feasible residency

Let r be the integer allowed resident blocks per SM, g the allocated register words per block, and s the allocated shared bytes per block. Let G and S be available register words and shared bytes per SM in the specified allocation context. Necessary constraints are:

$$
rg\leq G.
$$

$$
rs\leq S.
$$

Thread, warp, and block-count limits also apply. Register allocation has granularity and depends on compiled code; g is not known from output tile area alone. The current tested implementations use compiler and occupancy evidence to admit residency settings. A wider integer tile search needs a validated resource model or compilation-based rejection for new choices.

These constraints follow from physical storage capacity. They do not imply that all admitted blocks are simultaneously productive or provide linear speedup. Section 4.9 supplies the counterexample to that assumption.

### 7.4 Data dependencies become precedence and storage-lifetime constraints

Let a_i be the issue/start time of operation i and c_i the time its required result becomes available. If operation j consumes that result, the physical dependency implies:

$$
a_j\geq c_i.
$$

A shared store's source depends on a returned load; operand consumption depends on completed staging; each accumulator update depends on the prior update on that chain. A storage buffer can be overwritten only after all its required consumers have finished. Barriers add block-wide ordering in the program being modeled.

To turn issue times into completion times, we need a supported response rule. A constant delay d_i would give c_i = a_i + d_i, but our memory experiments show why one universal d_i is inadequate: cache outcome, pending fills, request grouping, and resource contention affect availability. The dependency inequality is established structure; a general completion-time function remains incomplete.

### 7.5 Service constraints must distinguish occupied time from result latency

For a demonstrated single-capacity resource, two operations cannot occupy its service interval simultaneously. Let u_i denote the service interval length of operation i, which need not equal its result latency. A binary ordering variable y_ij selects which of operations i and j receives that resource first. With a sufficiently large, finite time bound U, one conditional ordering constraint is:

$$
a_j\geq a_i+u_i-U(1-y_{ij}).
$$

The reverse ordering is:

$$
a_i\geq a_j+u_j-Uy_{ij}.
$$

When y_ij is one, the first constraint enforces i before j; when zero, the second enforces j before i. U must be derived from a valid schedule horizon, rather than chosen without a bound. Resources with multiple slots need corresponding assignment or capacity constraints.

This explains how physical service becomes linear scheduling constraints. It does not assert that an entire SM is a single-capacity resource. Our failed scheduler case shows why we cannot yet assign these intervals and resource mappings to every native instruction. Nor can effective phase costs be added on top of such detailed intervals: that would count embedded waiting twice.

### 7.6 Cache modeling requires both access order and arrival state

If an optimization changes access order, it can change cache contents and overlap between requests. A detailed formulation would need address-derived sectors, valid/resident state, pending fill completion, and an admitted replacement/mapping rule. The experiments distinguish these state concepts, but do not supply a complete RTX 5090 cache transition system.

For the current formulation, cache context is fixed to supported conditions. The bounded small-grid cold increment may be used where validated. The fully associative recency model is a component hypothesis with retained boundary failures, not an exact constraint system for arbitrary cache scheduling. Robust scenario optimization would address uncertainty in supplied rules; it would not recover missing cache rules automatically.

### 7.7 Bounded integer products can be linearized exactly

Products such as tile count times tile size are not linear as written. The original study demonstrated an exact bounded reformulation, so this mathematical machinery need not be rediscovered.

Let x be a nonnegative bounded integer, encoded using binary bits b_j and powers 2^j. Let v be another variable with known lower bound l and upper bound u. Introduce z_j to equal b_j v. Four linear inequalities enforce that product:

$$
z_j\geq l b_j.
$$

$$
z_j\leq u b_j.
$$

$$
z_j\geq v-u(1-b_j).
$$

$$
z_j\leq v-l(1-b_j).
$$

If b_j is zero, the first two force z_j to zero; if one, the last two force z_j to v. Therefore x times v equals the sum of 2^j z_j. Repeated application represents the bounded products in coverage, storage, and work counts exactly. Exact reformulation preserves the proposed equations; it does not make an unsupported physical equation correct.

### 7.8 The effective model is usable, but its scope cannot be hidden

For the tested configurations, independently measured phase parameters produce candidate costs without using full-GEMM validation timings as coefficients. Binary choices can select these supported parameter regimes, and the solver can optimize the resulting objective. This is a useful restricted implementation, not the final reverse-engineered scheduling optimizer.

If phase maxima are modeled inside the MILP, they must be represented as equalities, not only lower bounds. The final composition subtracts common-path time. Merely requiring that subtracted quantity exceed its two bounds would let the solver inflate it and artificially reduce the objective. One safe restricted implementation calculates each supported regime's phase maximum exactly before selection. The following construction supplies the exact maximum when A and E are linear expressions with known finite bounds. Let q be their maximum, z a binary branch choice, and V a nonnegative constant at least as large as every feasible absolute difference between A and E. Enforce both lower bounds:

$$
q\geq A.
$$

$$
q\geq E.
$$

The matching upper bounds select which expression equals q:

$$
q\leq A+V(1-z).
$$

$$
q\leq E+Vz.
$$

If z is one, q equals A and the lower bounds require A to be at least E. If z is zero, q equals E and E must be at least A. Thus q equals the maximum in either case, even if it later appears with a negative coefficient. This reformulation is exact for the supplied bounds; the physical adequacy of the phase model remains a separate question.

The intended objective is to minimize complete output readiness. Let T be that time and let c_o be each required output operation's completion time. For every required output o, impose:

$$
T\geq c_o.
$$

The objective is:

$$
\min T.
$$

This event objective becomes meaningful only when completion and service rules are supplied. Until those missing rules are identified, we should report a restricted effective model and a partial structural formulation, rather than claim the complete microarchitecture-derived MILP is finished.

## 8. Worked example: hardware structure, timing, and configuration choice

Consider warmed inputs with M = N = 1,920, K = 1,536, and BK = 32. There are 48 reduction steps. The smaller tile creates 3,600 blocks, with normal resident capacity eleven; the larger creates 1,200, with capacity eight. Both compute the same output and total matrix arithmetic.

For the smaller tile, the dense calibration has ceil(3,600/170) = 22 groups per SM. Its normalized staging latency is 17.043268/22 = 0.774694 microseconds, and its normalized staging service cost is 2.700867/22 = 0.122767 microseconds.

There are ceil(3,600/(170 × 11)) = 2 resident-capacity waves. Thus the staging latency estimate is 2 × 0.774694 = 1.549388 microseconds, while the service estimate is 22 × 0.122767 = 2.700867. The latter dominates. Computation and common work are calculated in the same way.

| Dense effective quantity | Smaller tile | Larger tile |
|---|---:|---:|
| Staging cost per whole-grid step | 2.700867 microseconds | 2.065000 microseconds |
| Operand computation cost per whole-grid step | 2.338600 microseconds | 2.066667 microseconds |
| Common cost subtracted per whole-grid step | 0.132400 microseconds | 0.056200 microseconds |
| Composed fixed cost | 21.924261 microseconds | 16.164266 microseconds |
| Composed runtime at 48 steps | 257.463464 microseconds | 211.786662 microseconds |
| Saved complete-GEMM measurement | 246.540800 microseconds | 210.502404 microseconds |

For example, the smaller prediction is 21.924261 + 48 × (2.700867 + 2.338600 − 0.132400). These numbers reproduce the [dense parameter implementation](model_components/dense_parameters.json) and the saved validation comparisons; this rewrite does not present a newly executed solve.

Within a restricted two-choice MILP, let x_small and x_large be binary choices whose sum is one. Minimize 257.463464 x_small + 211.786662 x_large. Direct comparison proves that the larger tile minimizes this objective. The matching saved GPU measurements also favor the larger tile. The model's explanation is reduced staging and shared-service demand, not a change in total matrix arithmetic.

This is a retrospective ranking check on existing evidence. It shows the arithmetic and physical interpretation of a bounded choice. It does not establish new solver efficiency or validate schedules the model has never seen. The longer-term formulation must derive costs for new legal decisions from independently supported mechanisms, rather than attach a measured full-kernel time to every possible kernel.

## 9. Validation boundaries and the next consequential gap

The present independently calibrated models have the following observed errors on their recorded complete-GEMM validation cases:

| Context | Largest observed error |
|---|---:|
| Warm small grids, both tiles | 4.20% absolute runtime |
| Cold-prepared small grids, both tiles | 3.85% absolute runtime |
| Warm dense grids, smaller tile | 5.97% absolute runtime |
| Warm dense grids, larger tile | 2.46% absolute runtime |
| Preheated 128 MiB input case, both tiles | 3.40% absolute runtime |

These maxima are measurements within bounded domains, not guaranteed uncertainty bounds. The original 79.2% error, the later 36.5% error, the fitted 2.33% median result, and the current 5.97% maximum concern different models, metrics, and workloads. They demonstrate a sequence of discoveries; they are not a controlled same-case accuracy curve.

The [current model](current_physical_model.md), [one-hour synthesis](one_hour_results_20261003.md), and [learning registry](model_components/learning_registry.json) link the preserved evidence. Some historical results are explicitly marked as requiring reconciliation before admission to the current runtime. Describing them here as discoveries does not silently promote their parameters.

The largest currently validated miss is the dense smaller-tile overestimate. The residency tests show larger errors as more blocks share an SM, while preserving native instructions and source-specific cache hits. That makes concurrency-dependent execution and operating context important remaining explanations, but does not identify a unique hardware cause. Separate phase instruction overhead and clock differences remain candidates with rejected simplistic corrections.

The simplest useful next test would retain the unchanged smaller-tile kernel and the one/four/eleven residency comparison, then determine whether the residual persists under matched operating clocks and verified memory-allocation context. Such a control would test whether operating context accounts for the error before a new internal-resource model is added. It is a proposed experiment, not a launch authorization; GPU experiments remain paused.

The accumulated work has revealed substantial execution structure: compiled dependency groups, readiness rather than average cache hits, resource-limited residency, and finite shared service. It has also exposed which missing knowledge prevents a general scheduling formulation. The next model should close that specific gap and face a separate hardware prediction test. A detailed simulator is optional; the essential requirement is a justified mathematical account of the decisions we want to optimize.
