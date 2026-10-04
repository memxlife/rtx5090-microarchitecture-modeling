# Round 2: cache policies and memory ordering

This documentation round asks what PTX guarantees about memory behavior before we assign physical cache rules to the simulator. It used the official PTX ISA 9.4 sections on [cache operators](https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#cache-operators) and the [memory consistency model](https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#memory-consistency-model). No GPU benchmark ran.

PTX distinguishes cache choices from ordering guarantees. Cache operators are performance hints; they do not change memory consistency. A global load can request L1 bypass with `.cg`. Global L1 caches are not mutually coherent. Default stores request write-back at coherent levels, while the documented write-through operator applies to system memory. None of these statements identifies the physical store buffers, eviction procedure, acknowledgement boundary or delay on our RTX 5090.

| Field | What this round adds | What remains unknown |
|---|---|---|
| F041: memory ordering | Required consistency depends on synchronization and scope; cache hints do not strengthen it | Native request and return ordering |
| F059: L1 write policy | L1 bypass and lack of mutual coherence constrain legal behavior | Store allocation and write buffering |
| F070: L2 write policy | PTX distinguishes write-back from system-memory write-through hints | Physical allocation, eviction and acknowledgement |

All three fields are partially identified and still count as remaining. No field became fully identified: cumulative totals stay at **5 of 87 functional fields** and **0 of 47 timing fields**, leaving **82 functional and 47 timing fields**, or **129 total**. Seven functional fields now have partial evidence, up from four. No fields were added to the baseline.

The model contract must carry the instruction's cache operator and address space with each memory request, and keep ordering obligations separate from cache policy. This is a specification requirement; the current blocking read-cache module does not implement a calibrated writable cache. No timing coefficient or executable cache behavior changed in this round.
