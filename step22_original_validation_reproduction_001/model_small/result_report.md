# Repeating the original small-grid model validation

The preserved C++ host reproduces all four original cases exactly. The separately relinked Verilog testbench also reproduces the original cycles, cache counters, and numerical checks. Neither model parameters nor source files were changed.

Each case multiplies a 64-by-K input matrix by a K-by-96 input matrix. Six blocks produce 6,144 output values per launch. The harness checks every value against its numerical reference for both the initial cold-cache launch and the subsequent retained-cache launch: 12,288 checked values per case. K is the number of elements reduced to form each output.

| K | Cold-launch cycles | Retained-cache launch cycles | Preserved C++ host | Relinked original testbench |
|---:|---:|---:|---|---|
| 64 | 19,491 | 13,852 | Exact original result | Exact original result |
| 128 | 30,111 | 19,408 | Exact original result | Exact original result |
| 768 | 136,311 | 74,968 | Exact original result | Exact original result |
| 1536 | 263,751 | 141,639 | Exact original result | Exact original result |

The original configuration represents six active streaming multiprocessors, the GPU units hosting blocks, with one resident block per unit. It uses the preserved per-unit cache geometry and a 96 MiB modeled shared cache. The exact original arguments are `+hit_delay=4 +setup_cycles=3346`. The four-cycle additional cache return delay and the 3,346-cycle setup contribution remain the original calibrated model settings; this repeat does not identify them as intrinsic hardware properties.

All source hashes recorded in the original frozen candidate and its transitive-source receipt matched before execution. [The source identity record](source_identity.json) preserves that comparison. Each C++ repeat receipt records the executable hash, command, original metrics, repeated metrics, and output-check result: [K64](cpp_repeat_k64.json), [K128](cpp_repeat_k128.json), [K768](cpp_repeat_k768.json), and [K1536](cpp_repeat_k1536.json).

There is one provenance limit. The historical C++ verification script reused the original build directories and overwrote the separate Verilator-generated testbench executable. Its generated main function, model archive, and runtime objects survive. We compiled that preserved main and relinked those objects into a new executable in this reproduction directory. This is a repeat of the original testbench behavior, not execution of the original testbench binary. The relink receipts record every command and input hash: [K64](verilog_repeat_k64.json), [K128](verilog_repeat_k128.json), [K768](verilog_repeat_k768.json), and [K1536](verilog_repeat_k1536.json).

Both execution paths use the same Verilator-generated model. Their agreement is therefore host-versus-testbench consistency, not independent handwritten C++ versus Verilog microarchitecture validation. The earlier two-unit, small-cache smoke test is inventoried separately in [the smoke inventory](smoke_inventory.json); it was not substituted for this calibrated six-block test.

No new GPU measurement was made in this lane. This result establishes reproducibility of the earlier model outputs and timing; comparison with the new physical repeat belongs to the coordinator’s combined report.
