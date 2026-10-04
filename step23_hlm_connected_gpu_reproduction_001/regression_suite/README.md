# Regression checks against preserved RTX 5090 measurements

The question is whether a model correction improves the small staged matrix multiplication without breaking workloads that previously agreed with hardware. This suite compares current predictions with nine preserved GPU measurements. It does not launch GPU workloads or run Verilog.

The six staged cases use the original matrix dimensions: 128×96 with reduction lengths 12,288 and 49,152; 1,920×1,920 and 2,048×2,112 with reduction lengths 1,536 and 4,608. The three direct-load cases use 192×768 with reduction lengths 1,024, 2,048 and 3,072. The reduction length is the shared dimension of the two input matrices.

Run from the repository root:

```sh
python studies/rtx5090_gemm_milp/step23_hlm_connected_gpu_reproduction_001/regression_suite/run.py --scope full
```

This checks source and evidence hashes, replays inexpensive high-level predictions, and reuses completed C++ results only when their source, local headers, binary and inputs match the manifest. It reports existing failures instead of treating them as accepted baselines. The small staged C++ prediction is currently 40.35% below hardware. This is a regression target, not a successful timing check.

The high-level staged model and provisional direct-load adaptation are separate implementations. Likewise, staged workloads use the full-chip handwritten C++ model, while direct workloads use an instruction executor in C++ followed by a Python phase calculation. Their numerical predictions must not be described as equivalence between these implementations.

To evaluate a changed staged implementation:

```sh
python studies/rtx5090_gemm_milp/step23_hlm_connected_gpu_reproduction_001/regression_suite/run.py --scope quick --evaluate --cpp-source /absolute/path/to/full_gpu_parallel.cpp --output candidate_quick.json
```

A changed source tree is compiled into a separate local executable. The quick tier compares the small staged case and the shortest direct case, and runs two pure C++ mechanism checks. The direct result is reused if unchanged. Use `--scope full --evaluate` for all nine workloads; changed full-chip models can take several minutes. Compilation and execution logs are saved under `build/`. To run selected regressions, add `--cases staged_128_96_49152,staged_1920_1920_1536`; identifiers must match the manifest exactly.

The native mechanism check compares cycle-by-cycle and event-skipping execution for one, two and eleven resident contexts, including delayed starts. The staging check supplies a synthetic four-cycle response and verifies 128 sector requests, 64 writes and coverage of 2,048 half-word addresses. A sector is a 32-byte memory unit. These checks establish internal behavior and address coverage; they do not establish numerical matrix values or hardware timing accuracy.

Signed timing error is 100 × (prediction / measured time − 1). Negative error means the model predicts a shorter runtime. Each result records whether the absolute error is at most 5%, whether it grew relative to the preserved prediction, and whether the GPU reference passed numerical checks. C++ address coverage is reported separately because this model does not carry numerical matrix payloads. Cycle conversion uses the historical reference of 2,940 cycles per microsecond; it is not a claim that the operating clock was constant.

The immutable manifest records model identities, fixed configurations and GPU evidence hashes. Changed evidence stops the check. Changed model sources prevent reuse of their cached predictions. No check automatically accepts a correction: the focused case must meet the 5% target, relevant earlier workloads must remain satisfactory, and the correction must have a defensible mechanism. No parameter fitting is performed by this suite. The GPU measurements were already known before the staging candidate was implemented, so this comparison is a regression check rather than a blind prediction.

[First full comparison](first_replay.json) and [quick mechanism evaluation](quick_evaluation.json) retain the baseline results. The original direct executable hash was not preserved; native instruction identity and measurement receipts are available, and that provenance limit remains in the manifest.

The first staging-repair candidate completed the focused case in 994,607 simulated cycles, or 338.302 microseconds at the reference clock. Its error is −11.05%, compared with the original C++ error of −40.35%. This improvement still misses the 5% requirement. [The candidate result](candidate_quick.json) preserves the raw completion and notes that its initial mechanism check required an API repair; the expensive workload was not repeated. The repaired staging screen allows multiple pending sector returns and checks the same address and completion obligations. The two requested regression comparisons also completed. The longer small case improves from −40.87% to −11.42%, while the large 1,920×1,920 case worsens from +0.27% to +31.57%. The candidate therefore cannot be accepted: it misses the small-case accuracy target and breaks an earlier accurate case. [The consolidated comparison](candidate_summary.json) includes exact commands and all three completion receipts. Publication evidence is retained as text under `logs/`, without generated executables.
