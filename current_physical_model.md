# What the RTX 5090 model currently explains

Our question is whether separately measured hardware behavior can predict a complete matrix multiplication. Matching a complete kernel by tuning its runtime is easier, but does not establish that we understand the hardware.

The tested program multiplies BF16 input matrices and produces FP32 output. Each block uses four warps and repeatedly processes 32 values along the reduction dimension. We test output tiles of 32 × 32 and 64 × 48 on one RTX 5090. All results below concern this program; they are not accuracy claims for arbitrary GPU programs.

## Why the predictions improved

The earlier model used simplified memory probes to price input staging—the step that reads inputs and writes them into shared memory. That price did not transfer accurately to the compiled GEMM. We reproduced most of the error with a single unchanged block, so interaction between blocks was not necessary to create it.

We then measured three paths independently: the repeated loop and synchronization alone, actual input staging with that common work, and actual operand loading and matrix computation with that common work. Adding the last two and subtracting the first avoids counting the common work twice. Each path has a measured startup cost and cost per repeated step. Complete GEMM runtimes were reserved for subsequent tests, rather than used as coefficients.

The separately measured extra cost of waiting for a cold global-memory request also transferred to small-grid GEMMs. It adds 0.20950 microseconds per dependent four-load group, or four groups for the smaller tile and seven for the larger tile. This is an experimentally supported response cost, not a reconstruction of every cache replacement decision.

## Why larger workloads needed another model term

A small grid mainly exposes the time one block waits for its work. A large grid also exposes how quickly shared hardware can serve many blocks. Eleven resident blocks cannot simply execute eleven times as much work in the same time.

We measured the same three paths with many blocks, first allowing one resident block per SM and then the normal resident limit. An SM is one of the GPU's processing units. The dense-workload model uses the larger of two costs for each path: the time required for successive groups of blocks to finish, and the time required to serve all their work. It then combines the paths as above. These service costs come from isolated paths, not full GEMM fitting. They do not yet identify the exact internal queue or pipeline responsible for the limit.

## Accuracy on new complete GEMM tests

Error means the absolute difference between prediction and measurement divided by the measurement. Lower is better. Each measured time is the median of nine samples, each averaging five launches; all outputs were checked.

| Tested context | Largest observed error |
|---|---:|
| Small grid, warmed inputs, both tiles | 4.20% absolute runtime; 4.36% runtime increase |
| Small grid, cold input preparation, both tiles | 3.85% absolute runtime |
| Large grids, warmed inputs, 32 × 32 tile | 5.97% absolute runtime |
| Large grids, warmed inputs, 64 × 48 tile | 2.46% absolute runtime |

The simple extension that assumed perfect overlap across resident blocks missed the larger small-tile workload by roughly 60%. Independent service measurements reduced that miss to about 4–6%. This is the largest improvement from the latest tests.

The current largest measured miss is 5.97%. The phase-measurement version itself runs within 0.5% of the original GEMM, but adding the separate paths counts about 4.1% more instructions than the original executes. That is a candidate explanation for part of the remaining overestimate. Profile clocks differed, so their times are not used as calibration. A probe without repeated mode-selection branches was rejected: the compiler removed its shared operand loads. Its better-looking costs do not describe the original hardware path. A retrospective [instruction-count correction test](diagnostic_056/results.md) also worsened the long-reduction case from 0.78% to 3.19% error. Aggregate counts alone are not an admitted physical timing correction.

The large-grid model also transferred to a 1920 × 1920 multiplication with reduction length 16,384: errors were 0.78% and 3.40% for the preheated smaller and larger tiles. The inputs occupy 128 MiB, exceeding the 96 MiB L2 capacity. Omitting preheating increased runtime by about 1.2%. The first profiled launch had 98.24% L2 hits without preheating, versus 99.27% with preheating. Ordinary timing regions overlap across launches, so the 1.2% comparison does not establish a strictly cold starting state. A separate control clears 2 GiB of cache traffic before every timed launch. It preserves the original native GEMM instructions and increases runtime by 2.24% relative to preheating; the warm service estimate differs from this strict-cold runtime by 1.43%. This is a bounded validation result, not yet a separate physical model of dense cold-cache timing. The observed result rejects the simple assumption that a total footprint above capacity makes all requests cold.

## Evidence and remaining limits

The executable components are [the small-grid model](model_components/runtime_v3.py) and [the dense-grid model](model_components/dense_runtime.py). Evidence is in [small-tile warm tests](diagnostic_044/absolute_multi_verification.json), [large-tile warm tests](diagnostic_046/verification.json), [cold tests](diagnostic_047/verification.json), [cold transfer tests](diagnostic_048/verification.json), [dense small-tile tests](diagnostic_050/verification.json), [dense large-tile tests](diagnostic_051/verification.json), and [instruction accounting](diagnostic_052/profile_analysis.json).

The components reject unvalidated shapes rather than silently claiming accuracy. Dense cold workloads, larger working sets than L2, other tile shapes, and exact internal resource ownership remain unresolved. The overall physical model is unfinished. The next correction must reduce the largest error on fresh full kernels without using their times to fit its coefficients.


## Final set before the requested stop

The unchanged-kernel resident-capacity test validated predictions at one, four, and eleven allowed blocks per SM. All 270 full-GEMM checks passed. Errors ranged from roughly 1% at one block to 5% at eleven; profiles measured identical dynamic instruction counts and 100% L2 hits. The model now supports these bounded capacity settings without new timing coefficients. [The results](diagnostic_057/results.md) explain the limitations.

A further clock check passed 90 full-GEMM checks and 270 phase-control checks. Minimal profiles agreed with the dominant-path ordinary timings within 0.7%, while reported SM counter rates differed between staging, computation, and full GEMM. Host-side snapshots did not measure average in-kernel clock rates. A sensitivity calculation did not justify a blind clock correction, so active timing coefficients remain unchanged. [The clock results](diagnostic_058/results.md) preserve the assumptions and unresolved interactions.

The largest validated absolute runtime error remains 5.97%. The user requested stopping after this set; the complete physical model remains unfinished.
