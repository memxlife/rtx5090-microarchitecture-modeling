# What hardware knowledge changes our GEMM model?

The question is how to predict RTX 5090 runtime from the way the hardware executes the program. Our recent calibration predicts six new kernel/workload pairs with 2.3% median error, but its costs were learned from complete GEMM timings. That accuracy does not yet explain why the GPU takes that time.

I searched Google through Chrome for RTX Blackwell documentation, Ada memory and scheduling documentation, and detailed analytical GPU models. I then read the primary sources linked below. The useful outcome is a more specific model structure and a smaller set of unresolved measurements, rather than another fitted timing coefficient.

## Start with the right hardware

NVIDIA's RTX Blackwell whitepaper identifies the RTX 5090 as GB202 with 170 active streaming multiprocessors, 96 MiB L2, and GDDR7 device memory. A streaming multiprocessor is a processing unit that executes blocks of threads. The whitepaper distinguishes the product configuration from the full chip. It also describes unified integer and FP32 execution resources: some integer operations have higher throughput than on Ada, but integer and FP32 operations cannot use those unified cores simultaneously in a given cycle. Address calculation therefore deserves its own execution accounting. This is a reason to test instruction classes, not proof that address calculation explains our error. [NVIDIA RTX Blackwell whitepaper, pages 10–15](https://images.nvidia.com/aem-dam/Solutions/geforce/blackwell/nvidia-rtx-blackwell-gpu-architecture.pdf).

The Blackwell tuning guide separates compute capability 12.0 from 10.0. For 12.0 it lists 48 resident warps per multiprocessor and 64K 32-bit registers. Several later sections explicitly discuss B200 hardware. We must not import those sections wholesale into the RTX model. The exact shared-memory limits used by our kernel remain those queried from our installed GPU and runtime. [NVIDIA Blackwell tuning guide](https://docs.nvidia.com/cuda/blackwell-tuning-guide/index.html).

For comparison, NVIDIA's Ada guide describes a combined 128 KiB shared-memory/L1 structure and 48 resident warps. Those similarities make Ada useful for designing experiments, but they do not establish equal instruction latency or memory throughput on the RTX 5090. [NVIDIA Ada tuning guide](https://docs.nvidia.com/cuda/ada-tuning-guide/index.html).

## Memory bytes are only part of the work

NVIDIA distinguishes a memory instruction, its request, the 32-byte sectors accessed, and processing packages called wavefronts. Packages from one request may be processed on separate cycles. Equal sector counts need not mean equal wavefront counts. The documented cache line is 128 bytes with four independently valid sectors. Stall samples mark the consumer waiting for data, rather than necessarily the producer that caused the delay. [Nsight Compute profiling guide, quantities and warp-stall sections](https://docs.nvidia.com/nsight-compute/ProfilingGuide/index.html).

This directly changes our interpretation of the recent experiments. We matched cache traffic totals but had not reconstructed all the work needed to deliver each instruction's operands. Our model must distinguish the number of bytes moved from the amount of processing required to move them. We should collect request and wavefront counts alongside sectors, using metrics supported by the installed profiler. Some work can overlap, so these counts must not simply be added as independent elapsed times.

The cache geometry documentation also narrows our previous uncertainty. Both 32-byte and 128-byte allocation hypotheses matched some diagnostic sequences. That experiment did not identify the physical tag size. The documented physical model uses a 128-byte tag with separate sector validity. Preserve the old 32-byte candidate as a diagnostic comparison, rather than describing both as equally documented NVIDIA cache designs. This does not identify set mapping, replacement policy, or the size of a DRAM transfer.

## A concrete lesson from RTX 4090 measurements

A research study containing RTX 4090 measurements compares scalar FP32 accesses with four-element vector accesses. Its Table V reports shared-memory throughput of 63.7 versus 126.5 bytes per clock per multiprocessor. The authors attribute the difference to memory instruction processing limits. This is evidence that instruction form can matter even when the payload is comparable. The same paper has different L2-latency values in its prose and table, so those values should not become our constants. [Luo and colleagues, memory-throughput section](https://arxiv.org/html/2501.12084v1).

A separate RTX 4090 study measures bandwidth as the number of active workgroups changes. It also reports apparent throughput above device-memory peak and suggests duplicate-read combining as an explanation. That is a useful warning about benchmark traffic accounting; it does not prove the same mechanism or rate on RTX 5090. [Chester Lam's original RTX 4090 microbenchmarks](https://chipsandcheese.com/p/microbenchmarking-nvidias-rtx-4090).

For our next tests, the practical question is whether the relevant limit is moving data or issuing and servicing memory instructions. We can hold addresses and payload fixed while changing instruction width, then check the compiled instructions and actual request work. A changed instruction count is an intended intervention in that test, but register allocation and residency changes must still be measured. If width improves throughput while transferred sectors remain equal, a byte-only model is inadequate. If it does not, the proposed issue-limit explanation loses support under that condition.

## A model structure we can adapt

GCoM provides a concrete analytical modeling approach. It separates limits inside each execution partition, banked and sectored L1 service, and unequal work distribution within and between multiprocessors. It analyzes instruction sequences broken by dependency waits and accounts for other warps running while one waits. Its authors validated on older GPUs, not RTX 5090; their reported real-GPU error is larger than their simulator comparison error. We can adapt the decomposition, not claim their implementation is already a validated Blackwell model. [Authors' ISCA presentation, pages 14–26](https://www.iscaconf.org/isca2022/slides/isca22-lee-gcom.pdf), [authors' source repository](https://github.com/yonsei-hpcp/gcom).

Here is the concrete execution story our model needs to represent. A warp issues a load. While the memory request is in progress, independent instructions or other warps may run. A later store that needs the loaded value cannot run until the value arrives. Matrix work begins only after the block's required shared inputs are available. If one warp arrives late at a block barrier, the others wait for it. The kernel finishes when its last required block finishes.

Consider four independent loads, three fast and one slow. If the next step needs all four values, it waits for the slow one. An average of the four response times does not describe that wait. If another warp has useful work ready, however, the hardware may use part of the waiting time productively. The model therefore needs both the dependency and the competing work. This example explains why a correct average cache hit fraction can coexist with an incorrect runtime prediction; it does not assert that this exact four-load pattern explains our measured error.

## Sources that require particular caution

The July 2025 Blackwell microbenchmark paper measures RTX 5080 against H100, not RTX 5090. It is useful for experiment designs, but contains inconsistent statements about support for newer matrix instructions. Its reported low-precision instruction costs also concern a different path from our BF16 WMMA kernel. We should reproduce relevant tests locally before using its numerical costs. [Jarmusch and colleagues, July 2025 study](https://arxiv.org/html/2507.10789v2).

The December 2025 paper focuses on B200 and H200, including tensor memory and decompression. Its findings do not establish those mechanisms in our RTX kernel. We exclude its latency constants and new-instruction behavior from the present model. [Jarmusch and Chandrasekaran, December 2025 study](https://arxiv.org/html/2512.02189v1).

## The next distinguishing measurements

The literature changes the order of our work. First, audit memory instruction processing in the two unchanged kernels: requests, sectors, wavefronts, and the instructions that wait for their results. Pair those quantities with ordinary runtime. This adds information absent from the earlier profiles without changing the program.

Second, use one compiled memory probe with fixed addresses and fixed load/store instructions. Change which operands start cached, including cases with the same number of hits but the slow operand in a different position. Compare models based on average response time with models that follow the actual dependencies. Cache preparation can also change address-translation state, so controls must distinguish or explicitly retain that uncertainty. Compiler differences would defeat this comparison; runtime inputs must make the intervention wherever possible.

Third, vary ready warps while preserving work per warp and input state. This measures how much of the identified wait is hidden by other work. Test small instruction sequences first, then predict the timing changes in the original GEMM without adjusting costs to its answers.

The first full GEMM predictions from the new execution model must be saved before new confirmation measurements. We should judge both their elapsed-time error and whether they correctly predict the direction and size of controlled timing changes. A model that merely reproduces one calibrated time has not disentangled the hardware contributions.

This source review gives us relevant documented structure, experimental precedents, and explicit transfer limits. It has not established the RTX 5090's private queue sizes, exact scheduling policy, cache mapping, or per-instruction service costs. Those remain measurements or competing hypotheses rather than invented parameters.
