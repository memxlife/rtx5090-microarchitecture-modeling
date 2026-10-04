# Why the staging repair regresses the dense workload

Does the repaired C++ staging component lose overlap between resident blocks, or does it impose a new resource bottleneck? Short model traces show that the repair introduces a strong instruction-issue limit. They do not show a blanket loss of early overlap. No GPU experiment or latency adjustment was made for this diagnosis. All four instrumented prefixes exactly match the preserved executable’s elapsed cycles, read/hit/miss/fill counts and native issue counts at the same boundary.

The baseline and repaired model were copied into separate instrumented trees. Both retain 170 streaming multiprocessors (SMs), 11 resident block contexts per SM, 48 cache slices and 32 shared-read slots. A resident context holds the state of one unfinished block. Each run stops after 10,000 cycles, including the unchanged 3,346-cycle startup. The repaired register-ready prior remains 340 cycles; a returned load becomes ready at the later of that interval and its actual return boundary. [The receipt](prefix_comparison.json) records the commands, fields, source hashes and complete snapshots.

## What the short traces show

The table reports state at cycle 10,000. Stage completions count completed operand-staging frames, not completed blocks.

| Workload and model | Staging contexts | Compute contexts | Completed staging frames | Global reads accepted |
|---|---:|---:|---:|---:|
| 128 × 96, reduction length 12,288; baseline | 0 | 12 | 48 | 6,144 |
| Same workload; repaired | 12 | 0 | 24 | 4,224 |
| 1,920 × 1,920, reduction length 1,536; baseline | 1,870 | 2 | 2 | 117,373 |
| Same workload; repaired | 1,841 | 29 | 117 | 119,848 |

The small workload is delayed by the repaired path. The dense repaired model, however, has already started more compute work in this prefix. The proposed explanation that it simply prevents blocks from overlapping is therefore too broad. Startup transients differ substantially, and these snapshots do not measure steady-state throughput.

At the dense endpoint, the repaired model has 5,139 pending global-load instructions. Of these, 4,834 still await sector returns, and only 299, or 5.8%, have returned but remain below the 340-cycle readiness floor. There are 4,776 load instructions with unsent sectors. These categories overlap: an unsent load also lacks its return. They show that the floor is not the dominant pending-load state at this endpoint. They do not establish a physical cache latency.

The same endpoint has 6,600 dependency-eligible warp instructions, of which 3,777 also satisfy the pending-queue capacity limits. A warp is a group of 32 threads executing one instruction together. All these eligible instructions compete for the candidate's single staging issue port on their respective SM. The trace counts eligible warps, not independent issue cycles, so it must not be interpreted as a direct utilization percentage. No store-source overwrite blocker is observed in these prefixes.

## A stronger full-run structural bound

The repaired producer contains 217 instructions per warp, or 868 instructions for the four-warps-per-block stage. The dense grid has 3,600 blocks; at least one SM must handle 22 blocks, because 3,600 blocks cannot be distributed across 170 SMs with only 21 blocks each. Each block performs 48 reduction stages. Under the candidate's single staging issue port, the necessary producer issue count is therefore:

`22 blocks × 48 stages × 868 instructions = 916,608 cycles`.

The completed repaired dense run takes 945,861 cycles. Producer issue alone requires 96.9% of that total under this model rule. This is a lower bound for the candidate implementation, not for an RTX 5090. In particular, it neither proves the hardware uses one such issue port nor accounts for native-compute issue ownership on a shared physical scheduler.

This explains why adding explicit staging dependencies can improve the small workload while creating a severe dense bottleneck. The component parity test confirms that Verilog follows this candidate rule; it cannot confirm that the rule represents the GPU scheduler. A separate scheduler-partition candidate is being investigated by the coordinator. These traced copies retain the original single-port rule.

## What remains unresolved

The traces do not independently identify physical request acceptance, register return or instruction service durations. The 340-cycle prior is still a transferred composite estimate. The baseline does not represent these register states at all, so its zero readiness columns mean an absent mechanism, not zero physical cost. No readiness residual is fitted or installed here, and the regressing candidate is not promoted.

## Encoded instruction delays are also missing

A separate read-only audit checks the captured producer instructions against the existing native control decoder. Each instruction's upper-word bits 41–44 agree with its numeric `trans` or `WAIT` annotation. The producer descriptor preserves source registers, destination registers and barrier tags, but discards this field. The repaired executor treats all non-load operations as one-cycle operations and does not apply an encoded per-warp issue cooldown.

Across the 217 producer instructions per warp, the encoded fields sum to 615, compared with 217 for a one-cycle-per-instruction sequence. This difference is not an additional 398 cycles of GPU time: readiness waits and issue intervals overlap, four warps interact, and field semantics are not independently established for every opcode.

[The reproducible audit](audit_producer_controls.py) constructs a dependency-only timeline for one warp with the unchanged 340-cycle load floor and one-cycle arithmetic/store priors. Its completion estimate is 1,523 cycles without encoded cooldowns. Applying only the independently tested integer-add classes under a conditional absolute-field interpretation gives 1,542 cycles. Applying all fields as cooldowns gives 1,851 cycles. The last result is an unvalidated mechanism screen, not an admitted correction or full-stage prediction. It contains no cache service or inter-warp issue competition.

The largest sums above one cycle come from predicate comparison instructions (86), integer multiply/address instructions (66), constant loads (42), branches (34), permutation instructions (34), and shared stores (32). Integer adds contribute 27 in total: 21 belong to the tested native opcode class and 6 to an untested variant. Thus most of the potentially consequential cooldown contribution belongs to classes not covered by the earlier controlled integer-add tests. [Per-instruction issue times and the longest binding dependency chain](producer_control_audit.json) preserve the evidence without assigning the untested fields physical latency.


## Four-partition candidate and Verilog consistency

The separate four-partition C++ candidate preserves the 340-cycle prior and reserves native-compute partitions before staging issue. Both completed workload evaluations pass their request and output-address conservation checks:

| Workload | Four-partition cycles | Prediction at 2.94 GHz | Error against the preserved GPU result |
|---|---:|---:|---:|
| 128 × 96, reduction length 12,288 | 810,287 | 275.608 µs | −27.538% |
| 1,920 × 1,920, reduction length 1,536 | 793,684 | 269.961 µs | +10.405% |

Signed error is `100 × (prediction / measurement − 1)`. The dense error falls from +31.574% under one staging issue port to +10.405% under four partitions, while the small prediction becomes less accurate. The single-port rule improved one case while worsening the other. This is consistent with compensation for missing costs, but does not identify those costs. Neither case reaches 5%, and the candidate is not promoted.

[The four-partition Verilog receipt](partition_rtl/parity_receipt.json) passes 943,985 protocol, address and counter comparisons and 49,152 separate operand-value checks. Its fourth scenario reserves native partitions and also blocks all partitions. These are component tests against the frozen C++ implementation, not full-chip Verilog or hardware equivalence. Host multiplication checks the delivered operands; no Verilog matrix arithmetic is executed.
