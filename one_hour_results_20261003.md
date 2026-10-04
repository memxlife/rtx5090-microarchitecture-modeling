# One-hour RTX 5090 model improvement

The objective was to reduce the largest prediction error quickly, using simple tests that teach the model something about real execution. The model now predicts the tested small-grid and dense-grid GEMMs with a largest observed absolute runtime error of 5.97%. This is a bounded result for two tile shapes and the listed workloads, not a complete NVIDIA microarchitecture model.

## What changed, in order

1. **Reproduce the error with one unchanged block.** Most of the small-tile error remained when only one block ran. Interaction between blocks was therefore unnecessary to create it. The native kernel instructions were unchanged.
2. **Measure the actual input-moving and compute paths separately.** The old synthetic input-moving costs did not transfer. We measured input staging, operand loading and computation, and their common loop and synchronization work. Adding the first two and subtracting the common work reduced small-grid prediction errors to roughly 0–4.4%. Complete GEMM runtimes were reserved for validation.
3. **Test the independent cold-request penalty.** A penalty measured in earlier memory probes predicted new small-grid GEMMs under cold input preparation within 3.85%, without fitting their full runtimes.
4. **Expose the much larger concurrency error.** Assuming resident blocks overlap perfectly underpredicted a dense-grid GEMM by roughly 60%. Independent measurements with one and normal resident block limits supplied latency and shared service costs. The revised model predicted fresh dense GEMMs within 5.97% for the smaller tile and 2.46% for the larger tile.
5. **Investigate the remaining 6% discrepancy.** The combined measurement version runs within 0.5% of the original, but adding the isolated phases counts about 4.1% more instructions. We did not turn that correlation into a fitted correction. Probes with constant mode selection were rejected because the compiler removed shared operand loads and changed the computation.
6. **Challenge the L2-capacity assumption.** With 128 MiB of inputs on a 96 MiB L2 GPU, the first no-preheat profile still showed 98.24% L2 hits. Repeated requests reuse data within a smaller active working set; total input size does not imply all misses. After fixing overlapping timing regions with a 2 GiB flush before each launch, the original kernel was 2.24% slower than the preheated case. The existing service estimate differed from that strict-cold runtime by 1.43%. Dense cold-cache timing is still not separately explained by the physical model.

## Accuracy and evidence

Error is the absolute prediction difference divided by measured runtime. Each runtime is a median of nine samples, each averaging five launches. All tested outputs were checked. The latest validation used predictions saved before measuring the complete GEMMs. Full GEMM times did not supply model coefficients.

| Updated model and tested context | Largest error |
|---|---:|
| Small grids, warmed inputs, both tiles | 4.20% absolute runtime |
| Small grids, cold input preparation, both tiles | 3.85% absolute runtime |
| Dense warmed grids, smaller tile | 5.97% absolute runtime |
| Dense warmed grids, larger tile | 2.46% absolute runtime |
| Preheated 128 MiB input case, both tiles | 3.40% absolute runtime |

The executable model now contains independently calibrated actual-path costs, the small-grid cold-request penalty, and dense-grid latency and service limits. Every meaningful new result is recorded as a model update, a supported scope, or a rejected correction in the [learning registry](model_components/learning_registry.json). The [current model explanation](current_physical_model.md) links the raw verification evidence. Regression checks reproduce the saved predictions and retain earlier counterexamples.

The main remaining measured error is the smaller tile's dense-grid overestimate. Instruction accounting is a candidate contributor, but the exact cause remains unproven. Other tile shapes, broad grid sizes, and a complete explanation of internal queues, cache timing, and resource contention remain outside the validated model. No whole-kernel timing fit was used to hide these gaps.
