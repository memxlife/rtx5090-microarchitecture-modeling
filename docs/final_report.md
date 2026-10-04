# Integer GEMM tile selection on an RTX 5090: a bounded MILP experiment

## Abstract

Can a mixed-integer linear program choose the dimensions of a real GPU matrix-multiplication tile without selecting from a prepared table? This experiment answers yes for a reduced, bounded model. Independent tile variables and exact product reformulations produced a 73-variable MILP that solved in approximately 0.021 seconds. Every one of the 144 configurations in its bounded hardware domain compiled, produced correct outputs, and avoided register spills. Mathematical domains containing up to 32,768 combinations also solved in under 0.1 seconds. However, the simple performance model selected a tile about 3.14 times slower than the fastest measured configuration. Efficient formulation and accurate prediction are separate achievements.

## 1. Motivation

A solver that chooses one entry from a table of complete tile configurations has not constructed the tile from its dimensions. The question here is whether the dimensions themselves can remain integer decisions while coverage, padding, and storage become linear constraints. This distinction matters when the eventual goal is to express GPU resource tradeoffs mathematically rather than enumerate conventional kernels.

## 2. Problem formulation

The experiment multiplies a 1,008-by-1,008 matrix by another of the same size on one RTX 5090. BF16 inputs use 16 bits per number; accumulation and output use 32-bit floating point. The three tile dimensions are rows $B_M$, columns $B_N$, and reduction depth $B_K$. Each is an independent positive integer multiple of 16. Rows and columns range from 16 to 96; reduction depth ranges from 16 to 64. These are assumed demonstration bounds, not maximum hardware capabilities.

The current question is terminal at this scope: can this reduced model be represented and searched as a MILP, with a real executable realization? Predicting the fastest kernel is a separate, unresolved question. This study does not change the parent homework simulator or its optimization objective.

## 3. Physical priors

Larger output tiles reuse their staged input values across more multiply-add operations. Tiles that do not divide the matrix dimensions execute extra zero-padded arithmetic. The staged input buffers and output-fragment scratch must fit shared memory. These observations motivate the traffic, work, and capacity equations.

A further hypothesis treats measured compute and memory service rates as constant across tiles. That assumption is deliberately coarse and can fail when tile dimensions change the number of available thread blocks, register demand, or instruction scheduling. L2-cache reuse receives no model term, as requested by the user.

## 4. Mathematical model

Let $M$, $N$, and $K$ be the matrix row, column, and reduction dimensions. Let $n_M$, $n_N$, and $n_K$ be the required tile counts. For each axis, coverage requires at least the original extent, and one fewer tile must fall short. For rows this gives:

$$
n_MB_M\ge M.
$$

Minimality supplies the companion condition:

$$
(n_M-1)B_M\le M-1.
$$

Positive integer variables make these conditions exactly equivalent to ceiling division. The covered extents, denoted $\widetilde M$, $\widetilde N$, and $\widetilde K$, are the tile counts times their dimensions. Executed floating-point work $W$ includes padding:

$$
W=2\widetilde M\widetilde N\widetilde K.
$$

The fixed kernel uses one staged input buffer pair and 4,096 bytes of output-fragment scratch. Its shared-memory demand $S$ is:

$$
S=2B_K(B_M+B_N)+4096.
$$

The queried per-block limit is 101,376 bytes. The model enforces that limit and a mapping-derived minimum accumulator-register bound. Compilation checks total register demand separately.

Masked loads preserve the original matrix interfaces. Requested global bytes $D$, without credit for cross-block cache reuse, are:

$$
D=2K(n_NM+n_MN)+4MN.
$$

Let $P$ be the effective throughput measured for a separate fixed-kernel development workload, and let $BW$ be sustained bandwidth measured with a large device copy. The estimated time $T$ is minimized subject to compute service:

$$
T\ge W/P.
$$

Memory service provides another lower bound:

$$
T\ge D/BW.
$$

The products are reformulated exactly by binary encoding of one bounded integer factor and auxiliary variables for binary-times-bounded-variable products. When the binary variable is zero, four linear inequalities force the auxiliary product to zero; when it is one, they force equality with the other factor. Recursive application handles three-factor products. No variable selects a complete tile triple. The full four-inequality derivation and a numerical ceiling example appear in [the study explanation](../README.md).

## 5. Computational implementation

The fixed kernel has 128 threads per block, four warps, row-major global and shared layouts, one buffering stage, and BF16 WMMA 16-by-16-by-16 instructions. Warps receive output fragments in cyclic order. A single template accepts all three tile dimensions, including 48 and 80.

The solver uses SciPy's HiGHS MILP interface. Independent verification calculates the same equations directly, after optimization. Unit tests also fix every one of the 144 triples and compare its MILP objective with direct arithmetic. Actual GPU output is compared with an independent cuBLAS BF16/FP32 multiplication over every output element.

## 6. Experimental design

Device queries and a 512 MiB-per-buffer copy test characterize resources and bandwidth. The fixed 64-by-64-by-32 kernel on a 3,072-cubed workload supplies the coarse compute rate. Those development measurements are fixed before solving and before inspecting the 1,008-cubed confirmation timings.

The smallest falsification test compares the solver's optimum with an independently calculated optimum. A discrepancy would reject the reformulation. Compilation or incorrect output would reject executable realization. The complete 144-tile confirmation sweep tests the entire bounded generator domain, rather than only conventional baselines.

Each timing uses ten warm-up launches and nine groups of five trials. A separate 512 MiB read sweep precedes every measured launch and lies outside its timing interval. This reduces reuse between launches; it does not disable hardware L2 caching during a launch. The input matrices use fixed, exactly representable BF16 fractions. Correctness for these inputs is not proof for all possible numerical inputs.

## 7. Results

### 7.1 Exact formulation and search

The test asks whether the independent-variable MILP agrees with direct arithmetic. Agreement is expected if the reformulation is correct; a different optimum or fixed-tile objective would falsify it. The 144-combination model used 73 variables and 146 constraints, selected 80-by-64-by-16, and solved in approximately 0.021 seconds with zero reported optimality gap and no constraint violation. Direct calculation agreed. All primitive tests and all 144 fixed-tile objective checks also succeeded.

Domains with 1,152 and 32,768 combinations used 85 and 102 variables and solved in approximately 0.026 and 0.079 seconds, respectively. Directly calculated optima agreed. These are single timing observations. Enumeration was faster for these small domains, so the result establishes compact representation and short absolute solve time, not superiority over enumeration. The larger domains were mathematical scaling tests and were not fully compiled on hardware.

### 7.2 Executable realization

The test asks whether every configuration in the bounded hardware domain has a legal, correct kernel. Any compile failure, spill, or incorrect output would identify a missing generator condition. All 144 compiled and matched the reference; none spilled. Actual register use ranged from 26 to 168 words per thread. The complete sweep took about 92 seconds. The bounded domain therefore has real device realizations, although the input check does not establish universal floating-point correctness.

### 7.3 Performance prediction

The test asks whether the model's optimum is near the fastest observed kernel. The selected tile measured 0.205626 ms, while 32-by-32-by-32 measured 0.065536 ms. Both values are medians of nine groups of five trials; smaller is better. An alternating-order recheck measured each tile three more times and confirmed the ordering.

The prediction error is the absolute estimated-minus-measured difference divided by measured time: 79.2%. Regret is the selected tile's excess measured time divided by the fastest tile's time: 213.8%. Thus, the model did not select a near-best kernel. This failure concerns the declared time model, not the exact transformation of that model into linear constraints.

## 8. Analysis

The model correctly exposes the intended variables and expresses its coverage and padding tradeoffs. Removing padding or memory traffic changes the selected optimum. Removing shared capacity does not, because the small domain already fits. Multiple tiles tie under this coarse objective, so the solver's particular choice is not a unique architectural conclusion.

The performance failure suggests that total work and requested bytes are insufficient. One plausible explanation is available parallel work: the selected tile launches 208 blocks, while the fastest tile launches 1,024 on a 170-multiprocessor device. More blocks may better hide instruction and synchronization latency. This is a hypothesis, not an isolated causal finding. Different warp utilization, compiler scheduling, and hardware reuse during a launch remain alternative explanations.

## 9. Claim boundary and limitations

The supported conclusion concerns an exact MILP for the stated reduced equations and a fully compiled 144-tile domain. It does not establish an exact model of GPU latency, an isolated Tensor Core peak rate, register-allocation behavior outside that domain, or spill-free realization of every larger-domain solution. The shared-memory query is used even though the CUDA 12.8 guide lists a larger per-multiprocessor capacity for this device class; the discrepancy is recorded explicitly. Hardware caches remain active, while cache benefits are excluded from the model.

## 10. Conclusion

Genuine integer GEMM tile dimensions can be searched quickly as a compact MILP and converted to correct, spill-free RTX 5090 kernels in this bounded experiment. The simple performance model needs refinement before its optimum can be trusted as a fast hardware configuration.

## 11. Next research question

Can a small, experimentally validated model of available blocks and compute utilization explain the measured ordering while retaining a compact MILP? This is separate because the present experiment already answers formulation and realization, while a matched utilization experiment is needed to identify why the performance ordering failed.

## Reproducibility appendix

[experiment.json](../experiment.json) records the GPU allocation, model scope, measurement settings, evidence labels, and hashes. [solution.json](../solution.json) preserves the selected tile and optimality evidence. [domain_validation.json](../domain_validation.json) preserves all 144 compilations and timing groups; [paired_recheck.jsonl](../paired_recheck.jsonl) preserves the alternating-order confirmation.

The implementation files are [milp_core.py](../milp_core.py), [solve.py](../solve.py), [gemm.cu](../gemm.cu), and [validate_domain.py](../validate_domain.py). CUDA compilation uses `-O3 -arch=sm_120 -Xptxas=-v` and links cuBLAS. Only GPU 7 executes kernels; compilation uses four CPU workers. The original source design remains in source_design.original.txt (not distributed).

From the project root, `python studies/rtx5090_gemm_milp/solve.py` reruns the local solve, and `python -m unittest discover -s studies/rtx5090_gemm_milp -p 'test_*.py'` runs the mathematical checks. Remote credentials are read outside the study and are absent from its records. Historical warm-cache diagnostics are preserved but are not confirmation measurements. Markdown mathematics passed source validation; rendering has not been independently verified.
