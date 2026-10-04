# Removing pointer reloads changes the whole memory schedule

We asked whether repeated 64-bit pointer loads explain the remaining GEMM timing error. The earlier control removed scalar parameter loads but retained those pointer loads. This control reads the two base pointers from device memory before the reduction loop, preventing the compiler from repeatedly reloading them from kernel parameters. Host metadata updates occur before timing starts.

We compared unchanged and retained-pointer variants on both output tiles, with 64 output rows, 96 columns, warmed inputs, and inner dimensions 4,096 and 16,384. Subtracting their median runtimes and dividing by 384 additional reduction stages estimates repeated-stage cost. This comparison removes fixed setup costs, including the two new metadata reads; it does not prove that all interaction with setup is absent.

| Tile | Original stage time | Retained-pointer stage time | Slowdown | Registers per thread, original / variant | Resident blocks, both |
|---|---:|---:|---:|---:|---:|
| 32 by 32 | 0.981 microseconds | 2.483 microseconds | 2.53 times | 40 / 39 | 11 |
| 64 by 48 | 1.721 microseconds | 4.151 microseconds | 2.41 times | 64 / 64 | 8 |

All 360 full-output comparisons with cuBLAS succeeded. Neither variant spills registers. Thus increased register allocation or a reduced resident-block limit cannot explain the slowdown.

## The intended control changes more than pointer loads

Two source-level profiles confirm that the repeated 64-bit parameter loads are absent. However, the input loads change from global-specific instructions to generic-address instructions. More importantly, every observed input load is followed by its dependent shared store: the smaller tile has 16 one-load groups per stage and the larger has 28. The originals have four and seven four-load groups, respectively. These groups describe loads issued before their consuming stores; they are not a measurement of all outstanding requests inside the hardware.

The total repeated instruction counts are 270 and 634 per warp per stage, compared with corrected original counts of 268 and 617. Matrix instructions, register rearrangements, and mathematical work remain present. Both profiles have zero L1 hits; almost all global read sectors hit L2, with one missing sector associated with the added setup traffic. The cache counts therefore do not supply a simple explanation for the slowdown.

This experiment establishes that removing pointer reloads can make the compiler produce a substantially different execution schedule. It does not measure intrinsic pointer-load latency, and it does not establish whether instruction form, reduced load overlap, or another changed dependency is the unique cause.

## What changes in the model

The executable comparison check now records input-load forms and refuses to admit this intervention as an isolated pointer-latency measurement. Regression checks preserve that refusal. The runtime model explicitly retains instruction form and pointer provenance as unresolved conditions; the measured slowdown is not added as a correction coefficient.

The key structural lesson is that response groups belong to the compiled kernel, not just its tile dimensions. Reusing the original four-load costs for a transformed kernel with one-load groups would misdescribe its execution. The next useful control must preserve explicit global-load instructions while changing pointer retention, and verify the resulting groups before interpreting timing.

The existing independently tested GEMM model still underestimates additional runtime by 25.3% and 17.8%. This experiment does not improve those numbers or complete the physically grounded runtime model.

Evidence: [measurement verification](verification.json), [dynamic instruction and request analysis](profile_analysis.json), and [compiled comparison](compiled_admission.json).
