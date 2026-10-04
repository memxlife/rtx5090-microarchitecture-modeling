# Draft section 4.51: whole-grid admission to resident blocks

This is a documentation template awaiting authoritative source and current-source verification. It makes no implementation or test claim.

## Role and boundary

Explain how one accepted matrix launch generates all complete 32 × 32 block coordinates and supplies them to the resident complete-block controller. Distinguish this concurrent-context dispatcher from section 4.43's serial reusable block controller. State supported dimensions, edge-tile policy and context count from the source. Multiple contexts share the existing cache, read hub, MOVM/HMMA and output actor; a dispatcher does not create additional physical services or SMs.

## Interface and quantities

Define grid launch valid/ready, captured operation ID and A/B/C bases; define input-sector request/return and masked output-sector request/acknowledgment ports. Record exact widths, default parameters and address validation from the source. Define issued blocks, acknowledged block completions and currently resident counts before discussing their invariants.

## State and completion ordering

Explain block-coordinate traversal, the acceptance edge that advances dispatch and how child completion IDs map to issued blocks. Describe whether out-of-order completions are allowed and how duplicate, unknown or unissued completion IDs are detected. State how metadata remains stable under backpressure. Final grid completion must require all expected block completions, no remaining resident blocks and all required output acknowledgments; distinguish final completion validity from its later acknowledgment.

## Reset and memory contracts

Explain cancellation of outstanding child state and backing-provider requests. Reset cannot undo stores already committed by the provider. Inputs remain immutable while the preserved cache can return them. State whether distinct output tiles are guaranteed by dispatch and which overlapping allocation cases are rejected.

## Quantitative verification and timing limits

Only after tests pass, report exact dimensions, block/word counts, provider acknowledgments, held-response checks, reset coverage and independent output oracle. Preserve source hashes and identify any missing scenario. Report simulated cycle boundaries explicitly; service timing, arbitration and resident capacity remain model choices unless independently calibrated. Whole-grid numerical correctness does not establish actual RTX full-chip timing.

## Inline behavior

Insert the exact authoritative SystemVerilog source after its verification receipt is current. Link the runner, numerical receipt and connected-round record. Keep physical counts unchanged unless independent evidence closes a parameter.
