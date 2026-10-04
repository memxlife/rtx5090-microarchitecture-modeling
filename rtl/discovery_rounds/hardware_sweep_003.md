# Hardware sweep 3: wide shared-memory operations

This round tested scalar, 64-bit and 128-bit shared reads and stores on separate GPUs. It covered contiguous full-warp accesses, same-vector read broadcasts and distinct same-bank stores. Addresses were naturally aligned, and stores never overlapped between lanes. The admitted measurements include 144 correct unprofiled launches and 24 successful profiler cases. No reported local memory was allocated.

## Compiler control and repair

The initial read probe used C++ `asm volatile` with ordinary PTX shared loads. The compiler moved invariant loads out of the loop, even though outputs remained correct. Dynamic wavefront counts exposed this: repeated tests produced only one native load's work. Those twelve read profiles were rejected and preserved. Store profiles retained their repeated accesses and remained valid.

The repaired read probe uses PTX `ld.volatile.shared` while retaining the native LDS width. Twelve replacement profiles confirmed repeated service work. The [documentation review](literature_sweep_008.json) explains why C++ assembly retention during PTX generation did not guarantee retention through native compilation. Volatile instructions still do not guarantee one physical memory transaction each.

## Measured work

For each pattern, subtracting the zero-iteration profile from the 2,048-iteration profile removes initialization and output-check work. Dividing by 2,048 gives service wavefronts per repeated operation.

| Operation | 32-bit | 64-bit | 128-bit |
|---|---:|---:|---:|
| Contiguous full-warp read | 1 | 2 | 4 |
| All lanes read the same vector | 1 | 1 | 2 |
| Contiguous full-warp store | 1 | 2 | 4 |
| Distinct stores concentrated in the same banks | 32 | 32 | 32 |

The important counterexample is the 128-bit broadcast. Counting distinct words per bank across the whole warp predicts one package, but hardware reports two. The scalar rule therefore cannot describe every wide instruction. This observation does not uniquely identify fixed lane groups or physical bank ports.

## Model update and next rounds

[shared_vector_packages](../parameter_sweep/shared_work.py) now distinguishes the measured widths and patterns. All twelve admitted cases match the updated rule. This is consistency with development evidence, not independent validation. Unverified wide patterns raise an error rather than silently using the scalar rule. The 128-bit broadcast correction is a measured work rule; it is not a latency coefficient, and the full Verilog operand path remains incomplete.

The next benchmark should compare neighboring versus spread active lanes reading identical vectors to distinguish subgroup effects. Online research is checking the documented request/wavefront and volatile contracts. Library inspection found mixed 64-bit stores and 128-bit reads in an actual optimized GEMM and is validating native matrix lane mapping. These three tracks are updated from this round's findings.

Newly fully identified: **0 functional and 0 timing**. Newly partial: **0**. One existing partial field, F052, gained stronger evidence. Totals remain **7 functional fields identified, 0 timing fields identified, 80 functional and 47 timing fields remaining = 127**, including **16 partial functional and 2 partial timing fields**. No fields were added.

[Raw admitted receipts](../parameter_sweep/wide_shared/receipt.json), [initial failed controls](../parameter_sweep/wide_shared/initial_receipt.json), [analysis](../parameter_sweep/wide_shared/analysis.json) and [model checks](../parameter_sweep/wide_shared/model_verification.json) preserve the evidence. Reproduce with `python studies/rtx5090_gemm_milp/rtl/parameter_sweep/wide_shared/analyze.py`.
