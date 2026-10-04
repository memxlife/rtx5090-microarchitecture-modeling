# Improving real-GPU tile selection without replacing the MILP with a lookup table

## Abstract

The first tile-selection MILP solved its equations exactly but selected a kernel 3.14 times slower than the measured best. This revision tests whether explicit block scheduling and empirical phase costs improve choices while keeping tile dimensions independent integer variables. Matched RTX 5090 experiments showed substantial sensitivity to available resident blocks. A revised 230–244-variable MILP solved two previously unmeasured matrix shapes in about 0.25 seconds. Across their complete 144-tile domains, the new choices were 4.29 and 1.59 times faster than the original model's choices. They remained 38.8% and 18.1% slower than the measured best. The formulation improved, but does not yet establish near-optimal hardware selection.

## 1. Motivation

The initial model counted total arithmetic and requested memory traffic. It assumed one compute throughput regardless of tile dimensions, available parallel work, or how the kernel loads and synchronizes its operands. Those assumptions were insufficient. The question is whether a small, experimentally supported refinement can improve decisions without changing the fixed kernel family or using a table of measured complete-tile latencies.

## 2. Problem formulation

The target remains one RTX 5090 and the same BF16 WMMA kernel: 128 threads per block, four 32-thread warps, 16-by-16-by-16 Tensor Core fragments, row-major layouts, one shared input buffer pair, and FP32 accumulation/output. Row and column tiles range from 16 to 96; reduction tiles range from 16 to 64. Every dimension is an independent integer multiple of 16. The 144 combinations are a bounded demonstration domain, not hardware maxima.

This revision addresses performance fidelity after the original formulation experiment. It leaves the parent course simulator unchanged. L2 reuse receives no explicit model term. A complete memory-hierarchy model and generalization to other GPUs remain separate questions.

## 3. Physical priors

A kernel needs enough independent ready work to keep its multiprocessors occupied. Resource reservations limit how many thread blocks can reside simultaneously. A small grid may leave fewer blocks available than the resource limits permit. Finally, the source executes operand loading, synchronization, computation, and another synchronization sequentially; their costs cannot simply be assumed to overlap fully.

These observations predict a sensitivity to grid size and residency even when arithmetic is unchanged. They motivate matched experiments rather than arbitrary tile-specific correction factors.

## 4. Mathematical model

The revised model keeps exact ceiling division, padding, independent tile dimensions, and bounded-integer product reformulations. It derives the output block count, the maximum number of output fragments assigned to one warp, and the number of waves needed at resource-limited residency. Compiler-register envelopes depend on fragment-slot count and reduction depth, not complete tile triples or benchmark latency.

The time objective minimizes the larger of two scheduling bounds: the longest block path and service across the grid. Each bound sums calibrated stage and instruction costs. The grid bound includes a residency-dependent latency term and the final partly filled wave. Small binary indicators represent resource regimes and residency levels. They also convert division by a selected residency level into multiplication by a known constant. The remaining bounded integer products use the exact construction from the original study.

[The complete formulation](formulation.md) defines every count, gives both equations, and explains their transformation into linear constraints. The fitted coefficients are effective costs, not isolated instruction latencies or measured CUDA launch overhead. Real execution need not occur in synchronized waves; that is an approximation to be tested.

## 5. Computational implementation

[solve_revision.py](solve_revision.py) builds and solves the revised MILP through SciPy/HiGHS. [fit_model.py](fit_model.py) fits nonnegative cost coefficients using development measurements. It minimizes squared relative error separately for grids that fit simultaneous residency and those that exceed it. The fixed generator and binaries remain unchanged.

Resource allocation uses a conservative maximum compiler-register count for each fragment-slot/reduction-depth regime. An inferred allocation rule reconstructs all 144 original CUDA occupancy-API observations. It is checked on this domain, not claimed as a universal microarchitecture specification. Compiler envelopes can underestimate actual available residency for a particular tile. The shared-memory allocation granularity cannot be uniquely identified from requests that are all multiples of 512 bytes.

Tests fix every one of the 144 tiles and compare the MILP's objective, residency, and wave count with direct arithmetic. Independent enumeration also confirms each optimized objective. Enumeration remains a verifier rather than an input to the MILP.

## 6. Experimental design

The [preregistered contract](contract.json) fixes development and confirmation inputs. Fourteen tile configurations were measured on 768-by-768-by-1,024 and 2,048-by-2,048-by-1,024 shapes. Additional controls varied unused shared-memory reservation or output-grid size while keeping the kernel instructions fixed. The coefficients and selected tiles were frozen before any performance measurements on the new 640-cubed and 1,536-cubed shapes.

Confirmation evaluated all 144 tiles on each new shape. Each latency is the median of nine groups of five trials after warm-up. A 512 MiB memory sweep precedes every timed launch and is excluded from the timer. GPU 7 alone executes the trials. Outputs are checked against cuBLAS over every element. Compiler-resource metadata from the original domain were allowed; new confirmation timings were excluded from fitting and selection.

If the revised model failed to improve either ordering or selection relative to the frozen original model, its claimed refinement would be rejected. A remaining gap to the best would limit the claim to improved fidelity rather than near-optimality.

## 7. Results

### Profiling and controlled resource reservation

The profiler comparison tests whether the original model missed available ready work. Achieved occupancy was 10.15% for the original choice and 48.98% for the measured best. Their schedulers had no eligible warp during 92.75% and 65.43% of cycles. These are consistent with missing latency-hiding behavior, although this two-tile comparison does not isolate one cause.

The controlled reservation test kept the 32-by-32-by-32 kernel and its 2,048-by-2,048-by-1,024 multiplication unchanged. Allowed residency fell from 11 to four, two, and one blocks per multiprocessor. Median latency rose from 0.198 to 0.330, 0.554, and 0.993 ms. This confirms a consequential resource-reservation effect. Shared/L1 partition changes remain a possible contributor, so residency alone is not uniquely identified as the cause.

### Held-out tile selection

The full-domain measurements test whether the frozen revision selects faster kernels on new shapes. Smaller latency and smaller regret are better. Regret is the chosen tile's excess measured latency divided by the best measured latency in the 144-tile domain.

| Matrix dimensions | Original choice: measured ms | Revised choice: measured ms | Best measured ms | Original regret | Revised regret |
|---|---:|---:|---:|---:|---:|
| 640 × 640 × 640 | 0.175706 | 0.040954 | 0.029498 | 495.7% | 38.8% |
| 1,536 × 1,536 × 1,536 | 0.289574 | 0.181862 | 0.154010 | 88.0% | 18.1% |

The original and revised choices were 80-by-80-by-16 and 32-by-32-by-64 for the first shape. The best measured tile was 16-by-16-by-64. For the second shape, the original and revised choices were 96-by-96-by-32 and 32-by-64-by-32. The best was 64-by-32-by-32. Alternating-order rechecks confirmed both remaining gaps. All 288 confirmation cases produced correct outputs and reported no local-memory allocation.

The revised selections are materially faster than the original selections, but neither is the measured optimum. This supports improved selection within the tested domain, not a global GPU optimum.

### Prediction, ordering, and solve cost

Prediction error is the absolute predicted-minus-measured difference divided by measured time. Its median across all 144 tiles fell from 78.7% to 17.2% on the smaller shape, and from 33.0% to 17.1% on the larger shape. These medians do not guarantee the error of any particular tile: the smaller selected tile's prediction remained about 65% too high.

Spearman rank correlation measures whether predicted and measured tile ordering agree; one means complete agreement, while a negative value indicates reversed ordering. It improved from −0.60 to 0.76 and from 0.30 to 0.56 on the two shapes. This supports a broader ordering improvement rather than only a fortunate selected point.

Both MILPs reported a zero optimality gap. They used 230–244 variables and 406–427 constraints and solved in 0.262 and 0.245 seconds. Direct enumeration agreed with their objectives. This establishes efficient absolute solve time for the bounded revised problem, not superiority over enumeration.

## 8. Analysis

The results support the idea that available blocks, residency, and repeated kernel phases matter to tile selection. A term-removal analysis on the frozen confirmation data found that removing the residency-dependent fragment-latency term worsened the larger shape's selection regret to 40.7%. Removing the wave-stage term instead reduced that regret slightly to 15.7%. Removing the single-block path bound did not change either selected tile. Thus, not every included term is decision-critical in these two cases, and the current wave approximation needs further scrutiny.

The larger shape also exposes an exact predicted tie: 32-by-64-by-32 and 64-by-32-by-32 have identical predicted costs, but different measured times. The model merges row and column staging volume and therefore misses this orientation effect. The smaller shape's best tile uses one active warp and a deeper reduction tile, a combination not directly represented by its development timing configurations. These are identifiable residual gaps, not grounds to refit after inspecting confirmation data and relabel it held out.

## 9. Claim boundary and limitations

The evidence supports better tile ordering and selection on two new shapes using the fixed hardware and kernel. It does not support near-optimality, a complete physical GPU latency model, or portability of the coefficients. Resource envelopes are conservative and empirical phase costs are aggregated. Numerical checks use fixed exactly representable input fractions and do not prove correctness for every input distribution.

Hardware caches remain active. The model excludes an explicit L2 reuse term, but measured phase costs necessarily reflect the operating hardware's memory behavior. Requested bytes are no longer asserted to equal physical GDDR7 traffic. This restriction is an effective empirical model, not a cache-free memory experiment.

## 10. Conclusion

Adding scheduling counts and measured phase costs improved the original MILP's decisions substantially while retaining genuine tile variables and short solve times. The remaining 18–39% selection gaps prevent a near-optimal claim. The revision is a useful, evidence-bounded improvement rather than a finished hardware-performance model.

## 11. Next research question

Which measurable feature distinguishes transposed tile orientations and the small-output-tile/deep-reduction regime without adding complete-tile timing lookup? Matched orientation and active-warp experiments are justified by the specific held-out failures. New confirmation shapes would be needed after any resulting refinement.

## Reproducibility appendix

[receipt.json](receipt.json) records hashes and evidence roles. [model.json](model.json) contains frozen coefficients; [calibration.json](calibration.json) contains development observations; [confirmation.json](confirmation.json) contains all 288 new measurements; [results.json](results.json) contains comparisons and ablations. [paired_confirmation.jsonl](paired_confirmation.jsonl) preserves the alternating-order rechecks. The two `solution_*.json` files preserve pre-measurement choices and the frozen model hash.

The implementation is [solve_revision.py](solve_revision.py), [fit_model.py](fit_model.py), [confirm.py](confirm.py), and [analyze.py](analyze.py). From the project root, run `python -m unittest discover -s studies/rtx5090_gemm_milp/revision_002 -p 'test_*.py'` for exact reformulation checks. The original experiment and its negative result remain preserved in the parent study directory. Mathematics passed source validation; rendering has not been independently verified.
