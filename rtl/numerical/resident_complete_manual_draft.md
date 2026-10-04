# Draft contract: resident GEMM through acknowledged output stores

This draft describes inspected code, not a verified implementation. The complete top connects resident operand staging, native register computations, output scratch and global stores while retaining resource allocation through actual completion.

The default geometry is two contexts, M64/N96/K64, with each context computing a 32 × 32 block and a reduction stage of 32. Each accepted launch captures its ID, A/B/C bases and block coordinates. Launches reject misaligned bases, out-of-bounds blocks, allocation overflow and output overlap with input allocations. The declared reservation remains 128 threads, 5,120 register words and 9,216 shared bytes per context.

One input cache serves resident staging. Native operand reads and scratch reads share one candidate/grant read hub. A preview can change before grant; only actual grant accepts its values. One MOVM and one HMMA service serve resident computations. A common modeled write edge selects either a staging vector commit or a scratch store package. These choices bound shared capacity but are not recovered RTX port topology.

Each context moves from staging through compute for every reduction stage. Producer release follows actual final operand commits. Consumer arrivals use memory-safe indications, distinct from completed register results; stage replacement still waits for actual compute completion. Separate context barrier objects track producer and consumer generations. This is a conservative lifecycle model, not complete native barrier replay.

After the last reduction stage, a registered output owner supplies its accumulators to scratch. Actual scratch read returns provide row-major output words. Thirty-two warp output requests cover all 1,024 FP32 words. Each masked sector store must receive its matching backing acknowledgment before the next operation; only the last completed warp store permits the final result. Resource allocation remains live until the final result is acknowledged, including while completion is held.

Read backing requests carry a 32-bit ID/address and return a 256-bit sector. Output packets carry a 32-bit ID/address, 256-bit data and an eight-bit word mask. The provider must flush pending requests on reset. Reset does not undo already committed output stores. Cached A/B data must remain immutable until reset; the wrapper has no invalidation interface.

Defaults use read capacity two, return delay nine, MOVM delay 19, HMMA delay 73 and HMMA interval four; store and barrier delays are one. All are synthetic implementation settings. This bounded top does not implement a full-grid dispatcher, multiple SMs or a calibrated hardware runtime. Verification results and exact inline sources must be added only after current-source tests complete.
