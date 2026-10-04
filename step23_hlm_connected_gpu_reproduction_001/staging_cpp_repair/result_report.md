# A C++ staging repair reduces the small-case error, but does not meet 5%

For the original staged matrix multiplication, the high-level performance model predicts 366.713 microseconds and the GPU measures 380.346 microseconds. The original C++ model predicts only 226.873 microseconds. Can representing the missing load-to-register-to-shared-store dependencies reduce that difference without fitting a delay to the full kernel runtime?

The new candidate predicts **338.302 microseconds**, an error of **−11.054%**. It removes 72.605% of the original time gap arithmetically, but still misses the requested 5% target. This is a candidate mechanism repair, not a completed calibration or a promoted default.

## The workload and unchanged configuration

The output has 128 rows and 96 columns, and each output value reduces over 12,288 input elements. The GPU kernel multiplies BF16, a 16-bit floating-point format, and accumulates FP32, a 32-bit format. Each block computes a 32-by-32 output tile using four 32-thread warps, for 12 blocks and 384 reduction stages. Each stage reduces over 32 elements.

The candidate keeps the original C++ model's 170 streaming multiprocessors, 48 cache slices, 11 resident contexts per multiprocessor, and 32 shared-read slots. A resident context holds the state of an in-flight block; a cache slice is a modeled cache subdivision. Cache initialization, arithmetic timing, output handling, and the reference conversion of 2,940 cycles per microsecond are unchanged. The old source tree and executable remain untouched. This is a handwritten C++ experiment; no Verilog or GPU run was launched by this implementation lane.

## What changed in staging

The old component fetches two 32-byte global sectors for each logical row group and then directly commits that group's 32 halfword values to shared memory. It does not expose the physical load instruction's temporary destination register or the dependent store instruction's eligibility.

The candidate instead executes the preserved kernel's compiled producer path. Its repeated stage begins at instruction address `0x220`, the target of the outer loop's branch at `0x1330`. It stops before the first block barrier at `0x1010`. The once-only kernel prologue is excluded. Per warp, the path contains 16 scalar global loads and 16 shared stores. Across four warps it issues 868 producer instructions, requests 128 distinct global sectors, and commits 64 distinct shared row groups.

Each warp has separate register-ready and register-read-ownership state. A store waits until its source register and encoded request-barrier group are ready. A load's two sector requests retain unique ownership IDs until they return. The candidate releases the loaded register at the later of:

- the issue time plus the independently measured 340-cycle readiness prior;
- the final sector-return time plus one registered edge.

Thus cache return is necessary, and the prior is not added on top of cache latency. The 340-cycle value comes from the earlier independent staged U16 load-readiness probe; it is a transferred composite readiness prior, not an intrinsic L2 latency or a value fitted to this workload. Store capture, store commit, and ordinary integer instruction readiness retain provisional one-cycle rules.

A store produces its actual contiguous 64-byte shared-memory group after eligible issue and commit. Stage completion waits for all four producer paths, outstanding loads, and shared-store handshakes. The existing compute component starts afterward. There is no assumed perfect overlap between successive staging and compute phases of the same block.

## Executable checks and measured comparison

The component tests verify 128 sectors, 64 unique commits, and the expected producer instruction count. With five-cycle cache returns, the first shared commit occurs at cycle 521 and cannot bypass the register-ready prior. With 500-cycle returns it occurs at cycle 684: the delayed return matters, but 340 cycles are not added again. Store backpressure preserves coverage, and a stale response from a completed stage is rejected. These are address and protocol tests, not numerical matrix-value tests.

| Prediction or measurement | Cycles | Runtime at the stated boundary | Error against GPU |
|---|---:|---:|---:|
| Original C++ model | 667,007 | 226.873 µs at the reference clock | −40.351% |
| Staging-repaired C++ candidate | 994,607 | 338.302 µs at the reference clock | −11.054% |
| Frozen high-level performance model | Not an instruction-cycle prediction | 366.713 µs | −3.584% |
| Original GPU measurement | Not a model-cycle prediction | 380.346 µs | Reference |

Signed error is `100 × (prediction / measurement − 1)`. The candidate adds 327,600 simulated cycles. The remaining runtime difference is 42.044 microseconds. Neither difference is installed as a new latency parameter.

The sole completed focused evaluation is preserved in [the regression receipt](../regression_suite/candidate_quick.json), with [raw output](../regression_suite/logs/candidate_focused.txt). The focused execution verifies all 12,288 output addresses and records unchanged native instruction and global request counts. The separate component screen checks 2,048 shared halfword addresses. The model carries no numerical payload; the original GPU numerical checks are separate evidence. A duplicate focused evaluation was stopped and its partial log is not treated as a result.

## Why this is not yet a complete repair

The result supports the importance of representing staging dependencies explicitly, but it does not uniquely identify the physical origin of every added cycle. The 340-cycle prior is transferred from another scoped probe. Uniform-register and predicate dependencies, constant-read timing, encoded instruction issue controls, and exact barrier behavior remain incomplete. Local register-ready state resets at each drained stage; the candidate does not numerically execute the full register/address program.

The compute component also retains its original 40-instruction template rather than replacing the entire kernel's compiled native control path. That deliberate scope boundary must not be described as exact full-kernel instruction equivalence. The earlier independently tested effective 64-cycle arithmetic candidate is not silently introduced here.

The completed regressions prevent promotion. The longer small case predicts 1,345.714 microseconds, an error of −11.420%. The previously accurate dense case predicts 321.721 microseconds, an error of +31.574%, compared with the baseline error of +0.274%. Both executions check their complete output-address coverage. [The consolidated regression receipt](../regression_suite/candidate_summary.json) preserves these results. All C++ evaluations have finished. The staging representation improves the small cases but materially worsens the dense case, so it remains an experimental component rather than a replacement for the baseline.

[The source/parameter freeze](candidate_launch_freeze.json), [component test receipt](unit_receipt.json), and [focused comparison](focused_result.json) preserve the implementation, prior provenance, results, and limits.
