# Closing the loop: assembled model versus fresh GEMM

## Question and model update

Can the independently measured mechanisms predict the runtime of a new GEMM workload without fitting its measured time? We assembled runtime model version 2, recorded predictions, and then ran unchanged kernels on fresh workloads.

The earlier model added global-response costs, shared-memory service bounds, and matrix-arithmetic capacity. Version 2 replaces the separate shared and matrix terms with the measured operand-path cost from diagnostic 023. That compound measurement includes shared reads, register rearrangements, arithmetic, operand-address work, and two block synchronization points. Those costs must not be added a second time.

The global-response component retains the measured request-group and cache-readiness behavior from diagnostics 019–021. Other findings constrain the model: dependencies and overlap cannot be replaced by simple operation counts; compiler-erased controls supply no timing coefficients; constant-load sequence costs cannot be assigned to every parameter instruction. Their remaining timing effects are explicitly unresolved.

## Frozen test and result

Both workloads have 128 rows and 96 columns. We tested reduction lengths of 8,192 and 32,768, with warmed inputs. The model predicted the additional time for the 768 extra stages. Comparing runtime differences removes fixed launch, setup, and output terms; it does not validate absolute runtime.

| Tile | Recorded additional time | Measured additional time | Version 2 underestimate | Earlier model underestimate |
|---|---:|---:|---:|---:|
| 32 by 32 | 563.408 microseconds | 754.483 microseconds | 25.3% | 31.4% |
| 64 by 48 | 1,108.176 microseconds | 1,347.578 microseconds | 17.8% | 27.2% |

Error is the absolute prediction difference divided by measured additional time. The acceptance gate was 5%, recorded before measurement. Version 2 fails both cases and is not promoted as an accurate model. It improves the earlier composition on the same measured workloads, without a fitted GEMM correction.

All 180 full-output checks pass without register spills. Two profiles verify all input requests hit L2, zero L1 hits, the expected global-response group counts, shared-read service counts, and matrix-instruction counts. Profile clocks are 2.950 and 2.947 GHz, close to the recorded 2.940 GHz proxy. That small clock difference cannot account for the remaining error.

## What changes in the model

A machine-readable learning registry now records experiment decisions, evidence hashes, affected model components, and rejected hypotheses. The model regression check preserves prior global-response accuracy, shared-bank counts, compiler-erased control rejections, and the known scheduler counterexample. Historical early experiments still marked for reconciliation are not silently admitted as physical parameters.

The current decision is to retain the compound operand path as a diagnostic component, reject the assembled serial composition as accurate, and keep missing constant/uniform/control and mixed-resource scheduling costs explicit. We will not add the measured residual to make this validation pass. The next update must predict that missing time from independently measured execution behavior, then face another frozen test.

The separate parameter-register control in diagnostic 037 did not materially improve repeated-stage cost and changed allocation. It therefore does not justify assigning the whole remaining gap to parameter loads. Dynamic instruction counts for that control still require profiling before a more specific claim.

This closes the test-to-model loop for the new candidate, but the requested physically grounded full runtime model remains unfinished. Cold-input accuracy, startup/output timing, broader concurrency, and complete execution scheduling remain in scope.
