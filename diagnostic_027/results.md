# A scheduler model that exposes a missing mechanism

## Question and model

Can one shared processing resource, together with operand readiness, explain our register-rearrangement measurements? We implemented an executable model in which each warp issues instructions in order. An instruction waits until its input registers are ready and the processing resource is available. Its output becomes ready after a specified delay. Independent instructions can overlap because the processing resource need not remain occupied for that entire delay.

The model accepts explicit costs rather than containing hidden hardware constants. Missing input readiness or instruction costs cause an error. Simple checks verify a dependent chain, overlapping independent work, and rejection of an unspecified input.

## Comparison with existing evidence

We used three earlier primitive measurements to set three effective parameters: approximately 29 cycles until a dependent result is ready, 7.25 cycles between issues within one warp, and 2 cycles between issues on the shared resource. These values include compiled-loop effects. They are candidate effective parameters, not established intrinsic hardware latencies.

On the remaining existing cases, five predictions differ by less than 0.1%. One fails: four warps with eight independent chains measure 10.625 cycles per operation, while the model predicts about 8.0. The underestimate is 24.7%. These are checks against previously collected measurements, not new untouched validation workloads.

## Consequence

The simple shared-resource hypothesis is insufficient and is not adopted as an accurate GPU model. Adding a coefficient for this one failing case would conceal the missing explanation. The next investigation must compare the emitted instruction ordering, register allocation, and dependency-control behavior for four versus eight chains. Scheduler partitioning and register-resource interactions remain competing explanations; neither is proven here.

The executable model provides a place to test those explanations without fitting full GEMM timings. It currently excludes complete barrier behavior, cache timing, register-bank mapping, and scheduler partitions. Full-GEMM stage errors remain about 17–31%, and the overall physically grounded model remains unfinished.
