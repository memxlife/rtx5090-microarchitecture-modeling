# Round 4: verify actual matrix instruction counts

This round compares a source-derived instruction count with the saved profiler records for diagnostic 042. It answers whether the model counts the matrix work correctly before trying to explain its runtime. No new GPU experiment ran.

Each supported block contains 16 × 16 output subtiles. Each reduction stage covers 32 elements, so each subtile invokes two 16 × 16 × 16 WMMA operations. The saved compiled family uses two native HMMA instructions per WMMA operation. Multiplying these quantities by the number of stages and blocks gives the expected warp-level instruction count. A warp-level count records each instruction issued by a warp once, rather than counting its 32 threads separately.

| Output tile | Blocks | Reduction stages | WMMA operations per block per stage | Predicted native instructions | Profiled native instructions |
|---|---:|---:|---:|---:|---:|
| 32 × 32 | 6 | 512 | 8 | 49,152 | 49,152 |
| 64 × 48 | 2 | 512 | 24 | 49,152 | 49,152 |

For the first case, the calculation is 6 × 512 × 8 × 2 = 49,152. For the second, it is 2 × 512 × 24 × 2 = 49,152. Launch dimensions come from the raw profiler records, and executed counts come from the instruction-level records. Both use a reduction length of 16,384 and 128 threads per block. File hashes preserve the exact evidence used.

The executable counter in [audit_dynamic_matrix.py](audit_dynamic_matrix.py) rejects unverified tile families. These two matches support the instruction-work calculation, not a hardware timing prediction. Other workload dimensions have not been physically checked by this audit. Native lane mapping, internal execution and result latency remain unknown, so F033 remains partial.

No additional field became identified or partial. Totals remain **5 of 87 functional fields identified**, **0 of 47 timing fields identified**, and **129 fields remaining**, including eight partially identified functional fields. The round strengthens one existing partial field. No timing coefficients changed.

Run `python studies/rtx5090_gemm_milp/rtl/discovery_rounds/audit_dynamic_matrix.py` to reproduce both comparisons. [dynamic_matrix_inventory.json](dynamic_matrix_inventory.json) contains the launch dimensions, counts and source hashes.
