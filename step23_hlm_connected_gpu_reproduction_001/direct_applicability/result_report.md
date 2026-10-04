# Which model predicts the direct-load benchmarks?

The large direct-load errors belong to the instruction-level timing model, not to an evaluated prediction from the earlier high-level phase model. The earlier phase model and the full-chip handwritten C++ simulator do not currently represent this direct operand path. Their table entries must therefore say **no applicable prediction**, rather than display an extrapolated number.

These benchmarks multiply BF16 inputs, a 16-bit floating-point format, and accumulate FP32 results, a 32-bit format. The original general-purpose direct kernel uses M=192 output rows, N=768 output columns, four 32-thread warps per block, and 144 blocks covering the full output. K is the reduction length. It loads matrix operands directly from global memory, without first copying them into shared memory.

| K | GPU runtime (µs) | Earlier high-level phase model | Full-chip handwritten C++ simulator | Separate instruction-model prediction (µs) | Signed error |
|---:|---:|---|---|---:|---:|
| 1024 | 15.1331 | No applicable prediction | No applicable prediction | 11.7643 | −22.26% |
| 2048 | 29.2510 | No applicable prediction | No applicable prediction | 20.7735 | −28.98% |
| 3072 | 43.5147 | No applicable prediction | No applicable prediction | 29.7966 | −31.53% |

Signed error is prediction minus measurement, divided by measurement. Negative values mean underprediction. GPU times are CUDA-event medians. Predictions convert reference cycles at 2,940 cycles per microsecond; profiler durations are not substituted for those event measurements.

The separate prediction executes the compiled instruction sequence in handwritten C++, tracking register readiness and limited pending operations. Python then combines the resulting duration with an approximate 7,607-cycle startup/output contribution and a nonbinding aggregate cache-service bound. It does not execute 144 complete streaming-multiprocessor models with explicit cache and network traffic. A streaming multiprocessor is the GPU unit that hosts thread blocks. The model uses a uniform 352-cycle composite load-readiness prior. That prior is a transferred estimate, not an identified intrinsic cache latency.

The preserved instruction-executor, runner, and prediction-script hashes still match their frozen receipt. The exact invocation supplies the instruction file, A and B readiness values of 352 cycles, and constant/special-register placeholders of one cycle. The historical temporary executable hash was not recorded, so this audit does not claim its binary identity. [The comparison receipt](direct_comparison_receipt.json) records source hashes, commands, model composition, and the original measurement receipts.

Why are the other predictions unavailable? The earlier high-level model was calibrated from global-to-shared staging, shared operand loading, arithmetic, and common control phases. Removing shared staging also changes instruction order, operand conversion, load geometry, and dependency overlap. Subtracting a measured shared-memory phase would not establish the direct path’s duration. The full-chip C++ simulator likewise routes global sectors through its staging frontend into shared memory. It has no direct global operand frontend for WMMA, the warp-level matrix-operation API.

A later paired experiment compiled new ordinary-load and cache-bypass implementations. Those six measurements are included separately in the JSON receipt. Their specialized ordinary kernel takes 29.42 µs at K=3072, while the cache-bypass version takes 42.53 µs. They differ from the original general-purpose kernel and from each other in compiled instructions and scheduling; they must not replace the original three rows above.

No new measurement, calibration, or path adaptation was performed for this audit. The approximately 5% accuracy target remains unmet for the instruction model on these original direct-load cases. These results do not establish a high-level-model error on an unsupported kernel.
