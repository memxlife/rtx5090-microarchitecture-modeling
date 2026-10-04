# Round 3: native matrix instruction audit

This local evidence round asks how many native matrix instructions occur in the saved GEMM binaries. It re-read four SM120 disassemblies from diagnostic 042, preserved their hashes and instruction addresses, and checked both the original p0 variant and the p2 pointer-retention variant. No GPU benchmark ran.

| Output tile | p0 static HMMA instructions | p2 static HMMA instructions |
|---|---:|---:|
| 32 × 32 | 4 | 4 |
| 64 × 48 | 12 | 12 |

All instructions use `HMMA.16816.F32.BF16`. These are distinct instruction addresses in the compiled code, not counts of instructions executed at runtime. Loop repetition, warp predicates and workload dimensions determine dynamic counts. The CUDA source uses 16 × 16 × 16 WMMA operations with a reduction-stage length of 32, so the source operation and the native instruction must remain separate units in the model.

F033, native matrix decomposition, is now partially identified for these saved binaries. Internal execution, lane mapping and native result latency remain unknown. Cumulative totals stay at **5 identified functional fields and 0 identified timing fields**. **82 functional and 47 timing fields remain**, or **129 total**; eight functional fields now have partial evidence. No fields were added.

The simulator's numerical matrix module computes a source-level operation. It must not use a single native instruction cost for that whole operation. This audit supplies a reproducible instruction inventory for later mapping, but does not add the missing native execution machinery or change a timing coefficient.

Run `python studies/rtx5090_gemm_milp/rtl/discovery_rounds/audit_native_matrix.py` to reproduce the inventory. The machine-readable evidence is [native_matrix_inventory.json](native_matrix_inventory.json).
