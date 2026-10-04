# Hardware sweep 2: remove address work and confirm bank splitting

Two independent experiments ran in parallel on idle GPUs 6 and 7. GPU 6 tested direct shared-load dependencies; GPU 7 tested new scalar bank patterns. All 81 unprofiled measured launches passed numerical checks and reported zero local memory. Four profiler launches succeeded. Timing values are not subtracted across devices.

## Direct load dependencies

The previous pointer chain calculated each next address from a loaded word index. The new array stores shared-memory byte addresses, so one native `LDS` result directly supplies the next `LDS` address. Numerical checks ensure every lane follows the expected chain. Native disassembly confirms each instruction uses the previous load's destination, including the edge returning to the loop start. Register renaming is allowed; requiring every load to use the same register would incorrectly reject a valid chain.

| Loads emitted per loop body | Cycles per load, 256 to 1,024 loads | Cycles per load, 1,024 to 4,096 loads |
|---|---:|---:|
| 1 | 29 | 29 |
| 8 | 28 | 28 |
| 32 | 28 | 28 |

Each entry is the increase in median elapsed cycles divided by the added loads. Increasing the unroll factor removes most repeated loop control. The agreement at eight and thirty-two loads supports a **28-cycle effective load-dependency path** for this compiled scalar instruction and access pattern. It does not separate the shared array's response from scheduler wakeup and issue. These tests were interpreted together as development evidence; they are not an untouched full-GEMM validation set. GPU clocks were not locked, and this round did not collect continuous telemetry.

The [calibration record](../parameter_sweep/shared_dependency_calibration.json) preserves the measured combination. It must not be assigned independently to both shared response and scheduler wakeup, which would count the delay twice. It is not yet used in integrated RTL.

## Additional bank patterns

The model counts the maximum number of distinct requested words in any one bank. GPU 7 checked four new patterns using the same independent scalar-read binary and one warp. Each case performs four reads per iteration for 2,048 iterations.

| Row spacing, words | Predicted packages per read | Predicted total wavefronts | Measured total wavefronts |
|---|---:|---:|---:|
| 8 | 2 | 16,384 | 16,384 |
| 40 | 2 | 16,384 | 16,384 |
| 48 | 4 | 32,768 | 32,768 |
| 56 | 2 | 16,384 | 16,384 |

All predictions matched. Across both hardware rounds, the executable bank rule now matches seven scalar patterns. Wider loads, stores, bank ports and request arbitration remain unverified.

## Parameter accounting and next decision

This round strengthens F052 and T027 without fully resolving either field. Newly fully identified: **0 functional and 0 timing**. Newly partial: **0**. Cumulative identified: **5 functional and 0 timing**. Remaining: **82 functional plus 47 timing = 129**, including **9 partial functional and 1 partial timing field**. No baseline fields were added.

The meaningful model update is a measured combined dependency cost and broader verification of the scalar bank rule. The next integration must preserve the combination rather than inventing its internal split. Literature research is examining whether documented contracts can resolve other fields completely.

[Raw receipts](../parameter_sweep/round_002_receipt.json) and [analysis](../parameter_sweep/round_002_analysis.json) preserve the commands, native instructions and measurements. Reproduce the analysis with `python studies/rtx5090_gemm_milp/rtl/parameter_sweep/analyze_round_002.py`.
