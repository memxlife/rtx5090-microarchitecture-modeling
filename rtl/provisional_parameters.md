# Provisional hardware parameters for the RTX 5090 behavioral model

We can run a model before every private hardware detail is known by assigning explicit provisional values and keeping their uncertainty visible. This document supplies those values for the tested GEMM path. It is a development baseline, not a claim that the complete RTX 5090 has been reverse engineered.

The profile covers **134 specification fields: 87 functional fields and 47 timing fields**. Physical evidence identifies **8 fields fully**, supports **32 fields partially**, and leaves **94 fields unidentified**. Partial fields still have unresolved properties. Therefore **126 fields are not fully identified**. Giving all 134 fields a baseline does not change these evidence counts.

**118 entries include engineering assumptions**, including entries that combine a supported external contract with an assumed internal implementation. The remaining labels describe 10 source-supported entries, five measured entries, and one query-plus-measurement entry. A measured baseline applies only to its stated experiment; it does not establish every value in a broad field.

Read each entry as follows. **Baseline** is the value or rule used to construct an executable model. **Units** say what the number counts. **Range or alternatives** are sensitivity-test choices unless the basis explicitly reports supported hardware values. A two-number list is a lower and upper bound; a longer numeric list lists discrete alternatives. **Basis** separates evidence from engineering choice. **Scope** says where the rule applies and what it does not establish. Confidence describes the baseline within that scope, not confidence that an entire component matches silicon.

A CTA is a cooperative thread array: one CUDA thread block. A warp is a group of 32 threads. SRAM is static random-access memory, used for registers and on-chip storage. A bank is a separately serviced portion of a storage array. A queue entry holds one outstanding request or result. A cycle is one edge-to-edge interval of the named clock. BF16 is the 16-bit floating-point input format; FP32 is the 32-bit floating-point format used for accumulation.

Timing must preserve its meaning. A dependent instruction-chain cost may already include waiting and scheduling; adding those delays again would count the same time twice. SM means streaming multiprocessor. L1TEX is the profiler name for the first-level cache/texture unit; LTS denotes the second-level cache unit. Their cycle counters use their own clock domains. The 2.95 GHz SM reference and the observed profile with SM/L1TEX near 2.0115 GHz and LTS near 1.8146 GHz are separate operating conditions, not one universal frequency.

The machine-readable source is [provisional_hardware_profile.json](provisional_hardware_profile.json). The physical evidence inventory remains [missing_parameter_registry.json](missing_parameter_registry.json). Neither this document nor its baseline numbers promote unknown fields to measured facts.

## How timing parameters combine

Choose one timing mode for each instruction path. In effective mode, use the measured end-to-end recurrence cost and do not add operand collection, bypass, or wakeup delays already included in that measurement. In decomposed mode, use separate service and dependency delays; do not add the effective cost again. Native compiler issue controls may impose a separate lower bound on issue spacing, but an elapsed operation cost is not automatically an initiation interval. Preserve consistent address geometry, including the 2,048-byte assumed bank-row mapping.

## Quick parameter table

This table gives the executable starting choices. Read the detailed entry below before treating any number as a hardware fact. **Assumed** means an engineering baseline; **source**, **measured**, and **query + measured** retain their stated scopes.

| ID | Parameter | Baseline | Unit | Basis |
|---|---|---|---|---|
| F001 | Register allocation granularity | 256 | 32-bit register words per warp | Source |
| F002 | Shared allocation granularity | 128 | bytes per CTA | Source |
| F003 | Block placement policy | round-robin across eligible SMs | policy | Assumed |
| F004 | Dispatch arbitration policy | oldest ready CTA first | policy | Assumed |
| F005 | Instruction-cache capacity | 16384 | bytes per partition | Assumed |
| F006 | Instruction-cache sets | 64 | sets per partition | Assumed |
| F007 | Instruction-cache associativity | 4 | ways | Assumed |
| F008 | Instruction-cache mapping | set=(instruction_byte_address//64)%64; partition-private | policy | Assumed |
| F009 | Instruction-cache replacement policy | LRU | replacement policy | Assumed |
| F010 | Native decoding rules | use supported native_shared_decode, native_generic_load_decode and native_control_decode modules; unsupported opcodes rejected | policy | Measured |
| F011 | Divergence handling | active-lane mask with per-thread program counter; only enabled lanes execute | policy | Assumed |
| F012 | Reconvergence handling | explicit convergence tokens and active-mask restoration at annotated merge PCs | policy | Assumed |
| F013 | Scheduler partitions per SM | 4 | scheduler partitions per SM | Source |
| F014 | Warp-to-partition assignment | warp_id modulo 4 | partition assignment | Assumed |
| F015 | Issue slot count | 1 | instructions per scheduler per SM cycle | Source |
| F016 | Multiple-issue compatibility rules | one issue per partition per cycle; mixed classes allowed across partitions subject to resource readiness | policy | Assumed |
| F017 | Instruction-class routing | route by native opcode and generic pointer address window; shared-window LD.E uses shared path | policy | Assumed |
| F018 | Arbitration policy | oldest-ready warp per partition with round-robin ties | policy | Assumed |
| F019 | Register bank count | 4 | register banks per partition | Assumed |
| F020 | Register bank mapping | register index modulo 4 | bank mapping | Assumed |
| F021 | Read ports per register bank | 2 | 32-bit operand words per bank per cycle per lane | Assumed |
| F022 | Write ports per register bank | 1 | 32-bit write words per bank per cycle per lane | Assumed |
| F023 | Operand collector capacity | 8 | collector entries per partition | Assumed |
| F024 | Collector routing | allocate any free collector in opcode class; bank conflicts serialize reads | policy | Assumed |
| F025 | Writeback queue capacity | 8 | writeback entries per partition | Assumed |
| F026 | Writeback arbitration policy | oldest completed instruction first; tensor and scalar share final arbitration | policy | Assumed |
| F027 | Execution pipeline counts by class | FP32 INT32=32; tensor blocks=1; SFU=4; LSU=4 | logical lanes or blocks per partition | Assumed |
| F028 | Supported numerical operation semantics | PTX specified rounding/FTZ; measured BF16 exceptional cases and supported FP32 semantics retained | policy | Assumed |
| F029 | Pipeline sharing rules | FP32 and INT32 share unified execution capacity; tensor and LSU are independently scheduled logical paths | policy | Assumed |
| F030 | Tensor pipeline organization/count | 4 | architectural Tensor Core blocks per SM | Source |
| F031 | Execution partition routing | issuing scheduler routes to its partition; shared services arbitrate SM-wide | policy | Assumed |
| F032 | Native lane/register layout | use measured native_bf16_layout mapping only for supported BF16 m16n16k16 WMMA family | policy | Source |
| F033 | Native instruction-to-operation decomposition | m16n16k16 BF16 WMMA decomposes into two HMMA.16816.F32.BF16 instructions, each covering eight output columns | policy | Measured |
| F034 | Accumulation order | supported BF16 matrix oracle uses magnitude-aligned truncation before summation for tested cancellation family | policy | Assumed |
| F035 | Exceptional numerical behavior | preserve measured BF16/FP32 subnormals; overflow to infinity; use recorded NaN and zero-times-infinity results | policy | Assumed |
| F036 | Load queue capacity | 16 | load entries per partition | Assumed |
| F037 | Store queue capacity | 8 | store entries per partition | Assumed |
| F038 | Outstanding transaction limit per warp | 8 | outstanding memory instructions per warp | Assumed |
| F039 | Outstanding transaction limit per SM | 64 | outstanding requests per SM | Assumed |
| F040 | Native instruction coalescing rules | global coalescing uses touched 32-byte segments of enabled lanes; shared uses supported measured package rules | policy | Assumed |
| F041 | Memory ordering rules | preserve program dependencies and explicit scoped fences; permit independent request completion out of order | policy | Assumed |
| F042 | Return assembly rules | little-endian assembly; s8/s16 sign extension; unsigned narrow zero extension; b32 bit preservation | policy | Source |
| F043 | Supported page sizes | 4096, 65536, 2097152 | bytes/page | Assumed |
| F044 | Translation-cache organization | L1 entries=128; L1 ways=4; L2 entries=2048; L2 ways=8 | entries and ways | Assumed |
| F045 | Translation mapping/replacement rules | VPN modulo set count; LRU within set | policy | Assumed |
| F046 | Translation request capacity | 32 | outstanding translation requests/SM | Assumed |
| F047 | Page-walk organization | levels=4; walkers=4; walk cache entries=32 | levels; walkers; entries | Assumed |
| F048 | L1/shared partition configuration | shared KiB=32; unified KiB=128; L1 usable KiB=64 | KiB/SM | Assumed |
| F049 | Read ports per shared bank | 1 | 32-bit read ports/bank | Assumed |
| F050 | Write ports per shared bank | 1 | 32-bit write ports/bank | Assumed |
| F051 | Shared request queue capacity | 32 | warp shared requests/SM | Assumed |
| F052 | Warp transaction splitting rules | scalar=maximum distinct words in any bank; vector64=two 128-byte logical phases; vector128=four 128-byte logical phases; same-vector reads count occupied 16-lane halves | service packages/request | Assumed |
| F053 | Broadcast rules | Same-location reads broadcast; independent-bank broadcasts multicast | functional policy | Assumed |
| F054 | L1 capacity in selected partition | 65536 | usable L1 bytes/SM | Assumed |
| F055 | L1 set count | 64 | sets/SM | Assumed |
| F056 | L1 associativity | 8 | ways/set | Assumed |
| F057 | L1 address mapping | set=(byte_address//128)%64 | mapping rule | Assumed |
| F058 | L1 replacement policy | pseudo-LRU per set | replacement policy | Assumed |
| F059 | L1 write policy | Global store bypasses L1; no write allocation | write policy | Assumed |
| F060 | L1 pending-miss capacity | 64 | pending distinct L1 misses/SM | Assumed |
| F061 | L1 pending-consumer merging rules | Merge identical 32-byte sectors into one pending fetch; retain all consumers | merge policy | Assumed |
| F062 | L1 fill/return queue capacities | fill entries=32; return entries=64 | queue entries/SM | Assumed |
| F063 | L2 set count | 1024 | sets/L2 slice | Assumed |
| F064 | L2 associativity | 16 | ways/set | Assumed |
| F065 | L2 slice organization/count | active model slices=48; nominal reported slices=64; FBPs=8; nominal slices per FBP=8 | slices; FBPs | Assumed |
| F066 | L2 slice address mapping | slice=(byte_address//128)%active_model_slices | mapping rule | Assumed |
| F067 | L2 set address mapping | set=(byte_address//(128*active_model_slices))%sets_per_slice | mapping rule | Assumed |
| F068 | L2 lookup ports | 1 | logical lookup requests/slice/reference cycle | Assumed |
| F069 | L2 replacement policy | pseudo-LRU with persisting-line priority when policy enabled | replacement policy | Assumed |
| F070 | L2 write policy | Write-back/write-allocate; dirty eviction issues DRAM write | write policy | Assumed |
| F071 | L2 pending-miss capacity | 128 | pending distinct misses/L2 slice | Assumed |
| F072 | L2 pending-consumer merging rules | Merge requests to identical pending 32-byte sector; wake all registered consumers | merge policy | Assumed |
| F073 | L2 request queue capacity | 64 | request queue entries/L2 slice | Assumed |
| F074 | L2 fill/return queue capacities | fill entries=64; return entries=64 | entries/L2 slice | Assumed |
| F075 | Channel/bank organization | controllers=16; bits per controller=32; banks per controller=16 | controllers; bits; banks | Assumed |
| F076 | Address-to-channel/bank mapping | channel=(address//256)%16; bank=(address//32768)%16; row=address//524288; column=(address%256)+256*((address//4096)%8) | address mapping | Assumed |
| F077 | Controller queue capacities | read entries=64; write entries=64 | queue entries/controller | Assumed |
| F078 | Controller arbitration policy | FR-FCFS: ready row hits first, then oldest; fairness after64 selections | arbitration policy | Assumed |
| F079 | Row-state/command rules | row bytes=2048; open page=yes; one open row per bank=yes | bytes/row; state rules | Assumed |
| F080 | Write handling policy | write buffer entries=64; drain high watermark=48; drain low watermark=16; merge same sector=yes | entries; controller write policy | Assumed |
| F081 | Barrier participant rules | warp size=32; default participants=all live CTA threads; explicit count multiple=32; barrier slots=16 | threads; named barrier slots | Source |
| F082 | Barrier generation rules | generation initial=0; generation increment=1; release when=participant arrival count reaches configured count; reuse=clear arrivals before accepting next generation | generation counter | Assumed |
| F083 | Barrier drain obligations | release requires=all earlier participant shared/global operations complete at modeled visibility point; later memory issue=blocked until release; universal DRAM writeback required=no | ordering rule | Source |
| F084 | Output-store acknowledgment semantics | store ack=backing memory accepts and commits modeled store; pending store counter bits=16; thread exit waits for pending stores=yes | completion rule | Assumed |
| F085 | Whole-grid completion rules | grid done=all CTA threads exited and modeled pending stores returned; completion collection=central outstanding-CTA counter; stream event visible after grid done=yes | completion rule | Assumed |
| F086 | Clock-domain organization | reference SM MHz=2950; L1TEX to SM rate ratio=1.0; LTS to SM rate ratio=0.9020911965950098; globaltimer reference=documented nanosecond counter; target-specific | MHz; clock-rate ratios | Measured |
| F087 | Cross-domain transfer protocol | protocol=dual-clock ready/valid FIFO; depth=4; synchronizer stages=2; ordering=FIFO; no loss/duplication | entries; clock edges | Assumed |
| T001 | Block admission delay | 32 | SM cycles | Assumed |
| T002 | Dispatch delay | 4 | SM cycles | Assumed |
| T003 | Allocation release delay | 8 | SM cycles | Assumed |
| T004 | Instruction fetch latency | 4 | SM cycles for instruction-cache hit | Assumed |
| T005 | Instruction fetch bandwidth | 1 | 16-byte native instructions per partition per SM cycle | Assumed |
| T006 | Decode delay | 1 | SM cycles | Assumed |
| T007 | Instruction-class initiation intervals | fp32 and int32 add=1; int32 mul mad and shift=2; tensor=4; load=1; store=1; shuffle=4; MOVM=decoded issue controls and completion-dependent native barrier replay; no added4.8cycle throttle | SM cycles per warp instruction per partition | Assumed |
| T008 | Dependency wakeup delay | 1 | SM cycles after result ready | Assumed |
| T009 | Register read latency | 1 | SM cycles | Assumed |
| T010 | Register write latency | 1 | SM cycles | Assumed |
| T011 | Operand collection delay | 1 | SM cycles plus serialized bank conflicts | Assumed |
| T012 | Bypass delay | 0 | additional SM cycles for supported bypass | Assumed |
| T013 | Writeback service rate | 1 | warp destination register vectors per partition per SM cycle | Assumed |
| T014 | Instruction-class result latencies | FADD=4; FFMA=4; SHF=4; SHFL=29 | effective dependent SM cycles | Measured |
| T015 | Instruction-class initiation intervals | fp32 add mul fma=128; int32 add sub=128; int32 mul mad=64; int32 shift=64; warp shuffle=32 | maximum scalar results per SM clock cycle | Source |
| T016 | Register rearrangement delay | 29 | effective dependent MOVM SM cycles | Measured |
| T017 | Native matrix result latency | 16 | SM cycles for supported HMMA result | Assumed |
| T018 | Native matrix initiation interval | 4 | SM cycles per HMMA instruction per partition | Assumed |
| T019 | Matrix result delivery bandwidth | 4 | 32-bit result words per lane per partition per SM cycle | Assumed |
| T020 | Load issue service rate | 1 | warp load instructions per partition per SM cycle | Assumed |
| T021 | Store issue service rate | 1 | warp store instructions per partition per SM cycle | Assumed |
| T022 | Return bandwidth | 128 | return bytes per partition per SM cycle | Assumed |
| T023 | Store visibility/completion delay | 32 | SM cycles to shared-store visibility; global modeled by memory service completion | Assumed |
| T024 | Translation hit delay | 4 | SM-reference cycles | Assumed |
| T025 | Translation miss processing delay | 40 | SM-reference cycles | Assumed |
| T026 | Page-walk delay | 600 | SM-reference cycles | Assumed |
| T027 | Shared read response latency | 24 | SM-reference cycles | Assumed |
| T028 | Shared write response latency | 12 | SM-reference cycles | Assumed |
| T029 | Broadcast delay | 0 | SM-reference cycles | Assumed |
| T030 | Shared-to-operand transfer delay | 4 | SM-reference cycles | Assumed |
| T031 | L1 read-hit latency | 32 | SM-reference cycles | Assumed |
| T032 | L1 write service latency | 4 | SM-reference cycles | Assumed |
| T033 | L1 service bandwidth | 128 | bytes/SM-reference cycle | Assumed |
| T034 | L1 refill transfer delay | 40 | SM-reference cycles | Assumed |
| T035 | L2 read-hit latency | 300 | SM-reference cycles | Assumed |
| T036 | L2 write service latency | 40 | SM-reference cycles | Assumed |
| T037 | L2 service bandwidth per slice | 16 | bytes/SM-reference cycle | Assumed |
| T038 | L2 return bandwidth | 768 | bytes/SM-reference cycle | Assumed |
| T039 | Read command/response timing | 200 | SM-reference cycles | Assumed |
| T040 | Write command/response timing | 100 | SM-reference cycles | Assumed |
| T041 | Read/write turnaround | 24 | SM-reference cycles | Assumed |
| T042 | Transfer service interval | 0.0525 | SM-reference cycles/32-byte sector, aggregate bus | Assumed |
| T043 | Barrier arrival service rate | 1 | warp arrivals per SM reference cycle | Assumed |
| T044 | Barrier release delay | 2 | SM reference cycles after final accepted arrival | Assumed |
| T045 | Warp resume delay | 1 | SM reference cycles from release to scheduler eligibility | Assumed |
| T046 | Memory-domain frequencies | reported memory MHz=14001; reference SM MHz=2950; same profile SM MHz=2011.50403938; same profile L1TEX MHz=2011.50403938; same profile LTS MHz=1814.56008584 | management-reported MHz; counter-derived MHz | Query + measured |
| T047 | Cross-domain transfer delay | minimum forward latency=2; minimum return latency=2 | destination clock edges | Assumed |

## Terms used in the parameter entries

| Term | Meaning here |
|---|---|
| GEMM | General matrix multiplication, the workload covered by this profile. |
| PTX / native instruction | NVIDIA's virtual instruction representation / the compiled device instruction. A PTX instruction need not map to one native instruction. |
| LSU / SFU | Load/store unit / special-function unit. |
| FIFO / FCFS | First-in, first-out storage / first-come, first-served arbitration. |
| LRU | Least-recently-used replacement: discard the entry unused for the longest time. |
| CDC | Clock-domain crossing: transferring information between different clocks. |
| DRAM / GDDR7 | Off-chip dynamic memory / the RTX 5090 memory technology. Reported clock values alone do not specify its command timing. |
| FADD / FFMA / INT32 | Floating-point addition / fused multiply-add / signed 32-bit integer computation. |
| SHF / SHFL | Funnel-shift instruction / transfer of values between warp lanes. |
| WMMA / HMMA | Warp-level matrix-operation interface / native matrix-instruction family. |
| MOVM | Native matrix-fragment register rearrangement. |
| FTZ | Flush-to-zero handling of very small floating-point values. |
| IEEE | The floating-point standard; a numerical baseline must state which rounding and exceptional-value rules it implements. |
| XOR | Bitwise exclusive-or, sometimes used in hypothetical address mappings. |
| VPN | Virtual page number, the page-sized portion of a virtual address. |
| FBP / FR-FCFS | Memory framebuffer partition / first-ready, first-come, first-served arbitration, which serves ready row hits before older requests. |

## Block allocation and dispatch

### F001 — Register allocation granularity

**Baseline:** 256.

**Units:** 32-bit register words per warp. **Range or alternatives:** [256, 256].

**Basis:** Published or toolkit-source rule. CUDA12.8.93 occupancy header, computeMajor12. **Confidence:** high. **Physical status:** identified.

**Scope:** Round registers_per_thread*32 upward to a 256-word quantum; allocator rule, not SRAM banking.


### F002 — Shared allocation granularity

**Baseline:** 128.

**Units:** bytes per CTA. **Range or alternatives:** [128, 128].

**Basis:** Published or toolkit-source rule. CUDA12.8.93 occupancy header, computeMajor12. **Confidence:** high. **Physical status:** identified.

**Scope:** Round static+reserved+dynamic shared bytes upward to a 128-byte quantum.


### F003 — Block placement policy

**Baseline:** round-robin across eligible SMs.

**Units:** policy. **Range or alternatives:** [least resident CTAs, least resident warps].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F004 — Dispatch arbitration policy

**Baseline:** oldest ready CTA first.

**Units:** policy. **Range or alternatives:** [round robin].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T001 — Block admission delay

**Baseline:** 32.

**Units:** SM cycles. **Range or alternatives:** [8, 256].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T002 — Dispatch delay

**Baseline:** 4.

**Units:** SM cycles. **Range or alternatives:** [1, 32].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T003 — Allocation release delay

**Baseline:** 8.

**Units:** SM cycles. **Range or alternatives:** [1, 64].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


## Instruction fetch and control

### F005 — Instruction-cache capacity

**Baseline:** 16384.

**Units:** bytes per partition. **Range or alternatives:** [8192, 65536].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F006 — Instruction-cache sets

**Baseline:** 64.

**Units:** sets per partition. **Range or alternatives:** [32, 128].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F007 — Instruction-cache associativity

**Baseline:** 4.

**Units:** ways. **Range or alternatives:** [2, 8].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F008 — Instruction-cache mapping

**Baseline:** set=(instruction_byte_address//64)%64; partition-private.

**Units:** policy. **Range or alternatives:** [SM-shared instruction cache].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F009 — Instruction-cache replacement policy

**Baseline:** LRU.

**Units:** replacement policy. **Range or alternatives:** [pseudo-LRU, random].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F010 — Native decoding rules

**Baseline:** use supported native_shared_decode, native_generic_load_decode and native_control_decode modules; unsupported opcodes rejected.

**Units:** policy. **Range or alternatives:** [decode unsupported instructions from explicit trace labels].

**Basis:** Measured in the stated experiment. path: components/native_ldsm_decode_verification.json; round: hardware_sweep_005; kind: native_encoding_and_executable_decoder. **Confidence:** medium within stated supported family. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F011 — Divergence handling

**Baseline:** active-lane mask with per-thread program counter; only enabled lanes execute.

**Units:** policy. **Range or alternatives:** [warp-stack approximation].

**Basis:** Engineering assumption. url: https://docs.nvidia.com/cuda/cuda-programming-guide/03-advanced/advanced-kernel-programming.html#independent-thread-scheduling; round: source_sweep_005; kind: official_documentation. **Confidence:** medium for retained observed subcontracts; low for extension outside measured scope. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F012 — Reconvergence handling

**Baseline:** explicit convergence tokens and active-mask restoration at annotated merge PCs.

**Units:** policy. **Range or alternatives:** [immediate-postdominator warp stack].

**Basis:** Engineering assumption. url: https://docs.nvidia.com/cuda/cuda-programming-guide/03-advanced/advanced-kernel-programming.html#independent-thread-scheduling; round: source_sweep_005; kind: official_documentation. **Confidence:** medium for retained observed subcontracts; low for extension outside measured scope. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T004 — Instruction fetch latency

**Baseline:** 4.

**Units:** SM cycles for instruction-cache hit. **Range or alternatives:** [1, 16].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T005 — Instruction fetch bandwidth

**Baseline:** 1.

**Units:** 16-byte native instructions per partition per SM cycle. **Range or alternatives:** [1, 2].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T006 — Decode delay

**Baseline:** 1.

**Units:** SM cycles. **Range or alternatives:** [1, 4].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


## Warp scheduler

### F013 — Scheduler partitions per SM

**Baseline:** 4.

**Units:** scheduler partitions per SM. **Range or alternatives:** [4, 4].

**Basis:** Published or toolkit-source rule. round: source_sweep_001; kind: official_documentation; url: https://images.nvidia.com/aem-dam/Solutions/geforce/blackwell/nvidia-rtx-blackwell-gpu-architecture.pdf#page=11. **Confidence:** medium within stated supported family. **Physical status:** identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F014 — Warp-to-partition assignment

**Baseline:** warp_id modulo 4.

**Units:** partition assignment. **Range or alternatives:** [round-robin at admission].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F015 — Issue slot count

**Baseline:** 1.

**Units:** instructions per scheduler per SM cycle. **Range or alternatives:** [1, 1].

**Basis:** Published or toolkit-source rule. path: discovery_rounds/literature_sweep_036.json; kind: official_docs_and_three_queried_reports. **Confidence:** medium within stated supported family. **Physical status:** identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F016 — Multiple-issue compatibility rules

**Baseline:** one issue per partition per cycle; mixed classes allowed across partitions subject to resource readiness.

**Units:** policy. **Range or alternatives:** [serialize shared execution classes].

**Basis:** Engineering assumption. path: discovery_rounds/literature_sweep_036.json; kind: official_docs_and_queried_reports. **Confidence:** medium for retained observed subcontracts; low for extension outside measured scope. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F017 — Instruction-class routing

**Baseline:** route by native opcode and generic pointer address window; shared-window LD.E uses shared path.

**Units:** policy. **Range or alternatives:** [trace-specified routing].

**Basis:** Engineering assumption. path: parameter_sweep/generic_shared/analysis.json; round: hardware_sweep_006; kind: hardware. **Confidence:** medium for retained observed subcontracts; low for extension outside measured scope. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F018 — Arbitration policy

**Baseline:** oldest-ready warp per partition with round-robin ties.

**Units:** policy. **Range or alternatives:** [round robin].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T007 — Instruction-class initiation intervals

**Baseline:** fp32 and int32 add: 1; int32 mul mad and shift: 2; tensor: 4; load: 1; store: 1; shuffle: 4; MOVM: decoded issue controls and completion-dependent native barrier replay; no added4.8cycle throttle.

**Units:** SM cycles per warp instruction per partition. **Range or alternatives:** scalar: [1, 2]; tensor: [2, 16]; load: [1, 4]; store: [1, 4]; shuffle: [4, 8]; MOVM effective: [4, 8].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Equal distribution of scalar service across four partitions is an assumption. Prefer aggregate SM service limits T015. Tensor4 duplicates T018 and must be charged once. MOVM achieved4.8cycles/op is not an initiation interval; do not combine it with validated dependency-barrier replay.


### T008 — Dependency wakeup delay

**Baseline:** 1.

**Units:** SM cycles after result ready. **Range or alternatives:** [0, 2].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


## Registers and operand collection

### F019 — Register bank count

**Baseline:** 4.

**Units:** register banks per partition. **Range or alternatives:** [2, 8].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F020 — Register bank mapping

**Baseline:** register index modulo 4.

**Units:** bank mapping. **Range or alternatives:** [XOR register index with warp ID].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F021 — Read ports per register bank

**Baseline:** 2.

**Units:** 32-bit operand words per bank per cycle per lane. **Range or alternatives:** [1, 4].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F022 — Write ports per register bank

**Baseline:** 1.

**Units:** 32-bit write words per bank per cycle per lane. **Range or alternatives:** [1, 2].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F023 — Operand collector capacity

**Baseline:** 8.

**Units:** collector entries per partition. **Range or alternatives:** [4, 32].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F024 — Collector routing

**Baseline:** allocate any free collector in opcode class; bank conflicts serialize reads.

**Units:** policy. **Range or alternatives:** [dedicated collectors per class].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F025 — Writeback queue capacity

**Baseline:** 8.

**Units:** writeback entries per partition. **Range or alternatives:** [4, 32].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F026 — Writeback arbitration policy

**Baseline:** oldest completed instruction first; tensor and scalar share final arbitration.

**Units:** policy. **Range or alternatives:** [round-robin class arbitration].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T009 — Register read latency

**Baseline:** 1.

**Units:** SM cycles. **Range or alternatives:** [1, 3].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T010 — Register write latency

**Baseline:** 1.

**Units:** SM cycles. **Range or alternatives:** [1, 3].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T011 — Operand collection delay

**Baseline:** 1.

**Units:** SM cycles plus serialized bank conflicts. **Range or alternatives:** [0, 4].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T012 — Bypass delay

**Baseline:** 0.

**Units:** additional SM cycles for supported bypass. **Range or alternatives:** [0, 2].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T013 — Writeback service rate

**Baseline:** 1.

**Units:** warp destination register vectors per partition per SM cycle. **Range or alternatives:** [1, 2].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


## CUDA/operand execution

### F027 — Execution pipeline counts by class

**Baseline:** FP32 INT32: 32; tensor blocks: 1; SFU: 4; LSU: 4.

**Units:** logical lanes or blocks per partition. **Range or alternatives:** FP32 INT32: [16, 32]; tensor blocks: [1, 1]; SFU: [4, 8]; LSU: [4, 8].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F028 — Supported numerical operation semantics

**Baseline:** PTX specified rounding/FTZ; measured BF16 exceptional cases and supported FP32 semantics retained.

**Units:** policy. **Range or alternatives:** [strict IEEE scalar oracle; explicit matrix approximation].

**Basis:** Engineering assumption. url: https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#floating-point-instructions-fma; round: source_sweep_005; kind: official_documentation. **Confidence:** medium for retained observed subcontracts; low for extension outside measured scope. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F029 — Pipeline sharing rules

**Baseline:** FP32 and INT32 share unified execution capacity; tensor and LSU are independently scheduled logical paths.

**Units:** policy. **Range or alternatives:** [additional collector contention].

**Basis:** Engineering assumption. round: source_sweep_001; kind: official_documentation; url: https://images.nvidia.com/aem-dam/Solutions/geforce/blackwell/nvidia-rtx-blackwell-gpu-architecture.pdf#page=12. **Confidence:** medium for retained observed subcontracts; low for extension outside measured scope. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T014 — Instruction-class result latencies

**Baseline:** FADD: 4; FFMA: 4; SHF: 4; SHFL: 29.

**Units:** effective dependent SM cycles. **Range or alternatives:** FADD: [4, 4.1]; FFMA: [4, 4.1]; SHF: [4, 4.1]; SHFL: [29, 30].

**Basis:** Measured in the stated experiment. path: parameter_sweep/scalar_execution/parameter_updates.json; kind: hardware. **Confidence:** medium within stated supported family. **Physical status:** partially identified.

**Scope:** Measured dependent instruction sequence, scoped to saved benchmark. In effective dependency mode this is issue-to-next-dependent-issue recurrence; do not add T008-T012 or fixed writeback drain to it. In decomposed mode use this observation only as a validation target, not an added latency.


### T015 — Instruction-class initiation intervals

**Baseline:** fp32 add mul fma: 128; int32 add sub: 128; int32 mul mad: 64; int32 shift: 64; warp shuffle: 32.

**Units:** maximum scalar results per SM clock cycle. **Range or alternatives:** basis: official cc12 throughput; convert warp instruction demand by 32 lanes.

**Basis:** Published or toolkit-source rule. url: https://docs.nvidia.com/cuda/cuda-c-best-practices-guide/index.html#arithmetic-instructions-throughput-native-arithmetic-instructions; round: source_sweep_005; kind: official_documentation. **Confidence:** medium within stated supported family. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T016 — Register rearrangement delay

**Baseline:** 29.

**Units:** effective dependent MOVM SM cycles. **Range or alternatives:** [28.9, 30.3].

**Basis:** Measured in the stated experiment. path: discovery_rounds/movm_timing_012/model_update.json; kind: hardware_and_nativeinspection. **Confidence:** medium within stated supported family. **Physical status:** partially identified.

**Scope:** 29-cycle effective recurrence plus decoded control validated on five/seven chain cases; not bare hardware latency In effective dependency mode this is issue-to-next-dependent-issue recurrence; do not add T008-T012 or fixed writeback drain to it. In decomposed mode use this observation only as a validation target, not an added latency.


## Matrix execution

### F030 — Tensor pipeline organization/count

**Baseline:** 4.

**Units:** architectural Tensor Core blocks per SM. **Range or alternatives:** [4, 4].

**Basis:** Published or toolkit-source rule. round: source_sweep_001; kind: official_documentation; url: https://images.nvidia.com/aem-dam/Solutions/geforce/blackwell/nvidia-rtx-blackwell-gpu-architecture.pdf#page=11. **Confidence:** medium within stated supported family. **Physical status:** partially identified.

**Scope:** architectural block count; not inferred internal HMMA pipeline count.


### F031 — Execution partition routing

**Baseline:** issuing scheduler routes to its partition; shared services arbitrate SM-wide.

**Units:** policy. **Range or alternatives:** [cross-partition execution stealing].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** medium for retained observed subcontracts; low for extension outside measured scope. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F032 — Native lane/register layout

**Baseline:** use measured native_bf16_layout mapping only for supported BF16 m16n16k16 WMMA family.

**Units:** policy. **Range or alternatives:** [reject unsupported matrix families].

**Basis:** Published or toolkit-source rule. url: https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#matrix-fragments-for-wmma; round: source_sweep_005; kind: official_documentation. **Confidence:** medium within stated supported family. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F033 — Native instruction-to-operation decomposition

**Baseline:** m16n16k16 BF16 WMMA decomposes into two HMMA.16816.F32.BF16 instructions, each covering eight output columns.

**Units:** policy. **Range or alternatives:** [trace explicit HMMA decomposition for other tiles].

**Basis:** Measured in the stated experiment. round: source_sweep_003; kind: saved_native_instruction_audit; path: discovery_rounds/native_matrix_inventory.json. **Confidence:** medium within stated supported family. **Physical status:** partially identified.

**Scope:** supported row-major BF16 WMMA family only.


### F034 — Accumulation order

**Baseline:** supported BF16 matrix oracle uses magnitude-aligned truncation before summation for tested cancellation family.

**Units:** policy. **Range or alternatives:** [ideal FP32 fused accumulation; conservative error interval].

**Basis:** Engineering assumption. path: parameter_sweep/bf16_exceptions/parameter_updates.json; kind: hardware. **Confidence:** medium for retained observed subcontracts; low for extension outside measured scope. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F035 — Exceptional numerical behavior

**Baseline:** preserve measured BF16/FP32 subnormals; overflow to infinity; use recorded NaN and zero-times-infinity results.

**Units:** policy. **Range or alternatives:** [PTX-defined unsupported scalar exceptional semantics].

**Basis:** Engineering assumption. path: parameter_sweep/bf16_exceptions/parameter_updates.json; kind: hardware. **Confidence:** medium for retained observed subcontracts; low for extension outside measured scope. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T017 — Native matrix result latency

**Baseline:** 16.

**Units:** SM cycles for supported HMMA result. **Range or alternatives:** [8, 32].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T018 — Native matrix initiation interval

**Baseline:** 4.

**Units:** SM cycles per HMMA instruction per partition. **Range or alternatives:** [2, 16].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T019 — Matrix result delivery bandwidth

**Baseline:** 4.

**Units:** 32-bit result words per lane per partition per SM cycle. **Range or alternatives:** [1, 8].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


## Load/store path

### F036 — Load queue capacity

**Baseline:** 16.

**Units:** load entries per partition. **Range or alternatives:** [8, 64].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F037 — Store queue capacity

**Baseline:** 8.

**Units:** store entries per partition. **Range or alternatives:** [4, 32].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F038 — Outstanding transaction limit per warp

**Baseline:** 8.

**Units:** outstanding memory instructions per warp. **Range or alternatives:** [4, 32].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F039 — Outstanding transaction limit per SM

**Baseline:** 64.

**Units:** outstanding requests per SM. **Range or alternatives:** [32, 256].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F040 — Native instruction coalescing rules

**Baseline:** global coalescing uses touched 32-byte segments of enabled lanes; shared uses supported measured package rules.

**Units:** policy. **Range or alternatives:** [conservative separate packages for unsupported widths].

**Basis:** Engineering assumption. url: https://docs.nvidia.com/cuda/cuda-c-best-practices-guide/index.html#coalesced-access-to-global-memory; round: source_sweep_005; kind: official_documentation. **Confidence:** medium for retained observed subcontracts; low for extension outside measured scope. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F041 — Memory ordering rules

**Baseline:** preserve program dependencies and explicit scoped fences; permit independent request completion out of order.

**Units:** policy. **Range or alternatives:** [fully ordered conservative memory model].

**Basis:** Engineering assumption. round: source_sweep_002; kind: official_documentation; url: https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#memory-consistency-model. **Confidence:** medium for retained observed subcontracts; low for extension outside measured scope. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F042 — Return assembly rules

**Baseline:** little-endian assembly; s8/s16 sign extension; unsigned narrow zero extension; b32 bit preservation.

**Units:** policy. **Range or alternatives:** [reject unsupported packed return formats].

**Basis:** Published or toolkit-source rule. path: discovery_rounds/literature_sweep_017.json; kind: official_docs. **Confidence:** medium within stated supported family. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T020 — Load issue service rate

**Baseline:** 1.

**Units:** warp load instructions per partition per SM cycle. **Range or alternatives:** [0.25, 1].

**Basis:** Engineering assumption. path: parameter_sweep/ldsm_service/timing_validation_analysis.json; round: hardware_sweep_005; kind: six_fresh_frozen_timing_predictions. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T021 — Store issue service rate

**Baseline:** 1.

**Units:** warp store instructions per partition per SM cycle. **Range or alternatives:** [0.25, 1].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T022 — Return bandwidth

**Baseline:** 128.

**Units:** return bytes per partition per SM cycle. **Range or alternatives:** [32, 256].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T023 — Store visibility/completion delay

**Baseline:** 32.

**Units:** SM cycles to shared-store visibility; global modeled by memory service completion. **Range or alternatives:** [4, 128].

**Basis:** Engineering assumption. registry status: unidentified; basis: engineering prior, selected for executable simulation; not hardware evidence. **Confidence:** low; unmeasured simulator starting choice. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


## Address translation

### F043 — Supported page sizes

**Baseline:** [4096, 65536, 2097152].

**Units:** bytes/page. **Range or alternatives:** [4096, 65536, 2097152].

**Basis:** Engineering assumption. Assume 4KiB,64KiB,2MiB translation modes. CUDA allocation granularity is not proof of hardware page support.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F044 — Translation-cache organization

**Baseline:** L1 entries: 128; L1 ways: 4; L2 entries: 2048; L2 ways: 8.

**Units:** entries and ways. **Range or alternatives:** L1 entries: [32, 512]; L2 entries: [512, 8192]; ways: [2, 16].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F045 — Translation mapping/replacement rules

**Baseline:** VPN modulo set count; LRU within set.

**Units:** policy. **Range or alternatives:** [modulo, XOR-hashed indexing, LRU, pseudo-LRU, random].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F046 — Translation request capacity

**Baseline:** 32.

**Units:** outstanding translation requests/SM. **Range or alternatives:** [8, 128].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F047 — Page-walk organization

**Baseline:** levels: 4; walkers: 4; walk cache entries: 32.

**Units:** levels; walkers; entries. **Range or alternatives:** levels: [3, 5]; walkers: [1, 16]; walk cache entries: [0, 256].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T024 — Translation hit delay

**Baseline:** 4.

**Units:** SM-reference cycles. **Range or alternatives:** [1, 20].

**Basis:** Engineering assumption. Translation cache-hit delay. ENGINEERING_ASSUMPTION; sweep this range, not a confidence interval.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T025 — Translation miss processing delay

**Baseline:** 40.

**Units:** SM-reference cycles. **Range or alternatives:** [10, 200].

**Basis:** Engineering assumption. Miss dispatch/processing overhead excludes page walk. ENGINEERING_ASSUMPTION; sweep this range, not a confidence interval.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T026 — Page-walk delay

**Baseline:** 600.

**Units:** SM-reference cycles. **Range or alternatives:** [100, 3000].

**Basis:** Engineering assumption. Page-walk service delay beyond miss processing. ENGINEERING_ASSUMPTION; sweep this range, not a confidence interval.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


## Shared memory

### F048 — L1/shared partition configuration

**Baseline:** shared KiB: 32; unified KiB: 128; L1 usable KiB: 64.

**Units:** KiB/SM. **Range or alternatives:** shared KiB: [0, 8, 16, 32, 64, 100]; L1 usable KiB: [16, 128].

**Basis:** Engineering assumption. Supported shared configurations are toolkit facts; usable L1 capacity and overhead here are assumptions. Alternate 100KiB shared profile must reduce assumed L1 accordingly.. **Confidence:** low. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F049 — Read ports per shared bank

**Baseline:** 1.

**Units:** 32-bit read ports/bank. **Range or alternatives:** [1, 2].

**Basis:** Engineering assumption. One logical service port is a modeling baseline; bank wavefront measurements do not identify physical ports.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F050 — Write ports per shared bank

**Baseline:** 1.

**Units:** 32-bit write ports/bank. **Range or alternatives:** [1, 2].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F051 — Shared request queue capacity

**Baseline:** 32.

**Units:** warp shared requests/SM. **Range or alternatives:** [8, 128].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F052 — Warp transaction splitting rules

**Baseline:** scalar: maximum distinct words in any bank; vector64: two 128-byte logical phases; vector128: four 128-byte logical phases; same-vector reads count occupied 16-lane halves.

**Units:** service packages/request. **Range or alternatives:** phase bytes: [64, 128, 256]; cross warp arbitration: [round-robin, oldest-ready].

**Basis:** Engineering assumption. Retain admitted scalar/full-warp/vector128 masked-broadcast measurements. General vector partition and cross-warp rule remain an engineering extrapolation.. **Confidence:** low. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F053 — Broadcast rules

**Baseline:** Same-location reads broadcast; independent-bank broadcasts multicast.

**Units:** functional policy. **Range or alternatives:** [documented behavior fixed].

**Basis:** Engineering assumption. Official ordinary shared-read contract is identified. This entry preserves it without adding a timing claim.. **Confidence:** low. **Physical status:** identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T027 — Shared read response latency

**Baseline:** 24.

**Units:** SM-reference cycles. **Range or alternatives:** [16, 28].

**Basis:** Engineering assumption. Intrinsic shared response assumed; measured dependent chain28 includes wakeup. ENGINEERING_ASSUMPTION; sweep this range, not a confidence interval.. **Confidence:** low. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T028 — Shared write response latency

**Baseline:** 12.

**Units:** SM-reference cycles. **Range or alternatives:** [4, 32].

**Basis:** Engineering assumption. Shared write acceptance-to-service completion, not global visibility. ENGINEERING_ASSUMPTION; sweep this range, not a confidence interval.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T029 — Broadcast delay

**Baseline:** 0.

**Units:** SM-reference cycles. **Range or alternatives:** [0, 4].

**Basis:** Engineering assumption. Additional broadcast delay beyond ordinary shared service. ENGINEERING_ASSUMPTION; sweep this range, not a confidence interval.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T030 — Shared-to-operand transfer delay

**Baseline:** 4.

**Units:** SM-reference cycles. **Range or alternatives:** [1, 16].

**Basis:** Engineering assumption. Shared result to operand-consumer availability. ENGINEERING_ASSUMPTION; sweep this range, not a confidence interval.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


## L1 cache

### F054 — L1 capacity in selected partition

**Baseline:** 65536.

**Units:** usable L1 bytes/SM. **Range or alternatives:** [16384, 98304].

**Basis:** Engineering assumption. Baseline 32KiB shared +64KiB usable L1 +32KiB modeled overhead fits known128KiB unified pool; overhead not measured.. **Confidence:** low. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F055 — L1 set count

**Baseline:** 64.

**Units:** sets/SM. **Range or alternatives:** [16, 128].

**Basis:** Engineering assumption. Baseline64sets*8ways*128-byte lines=64KiB. Recompute set count when capacity or ways changes.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F056 — L1 associativity

**Baseline:** 8.

**Units:** ways/set. **Range or alternatives:** [4, 16].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F057 — L1 address mapping

**Baseline:** set=(byte_address//128)%64.

**Units:** mapping rule. **Range or alternatives:** [modulo index, XOR high/low address hash].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F058 — L1 replacement policy

**Baseline:** pseudo-LRU per set.

**Units:** replacement policy. **Range or alternatives:** [LRU, pseudo-LRU, random, round-robin].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F059 — L1 write policy

**Baseline:** Global store bypasses L1; no write allocation.

**Units:** write policy. **Range or alternatives:** [bypass/no allocation, write-through/no allocation, write-through/allocation].

**Basis:** Engineering assumption. PTX global L1 noncoherence and .cg bypass are documented. Actual native store allocation baseline is assumed.. **Confidence:** low. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F060 — L1 pending-miss capacity

**Baseline:** 64.

**Units:** pending distinct L1 misses/SM. **Range or alternatives:** [16, 256].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F061 — L1 pending-consumer merging rules

**Baseline:** Merge identical 32-byte sectors into one pending fetch; retain all consumers.

**Units:** merge policy. **Range or alternatives:** [sector merge, 128-byte line merge, no merge].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F062 — L1 fill/return queue capacities

**Baseline:** fill entries: 32; return entries: 64.

**Units:** queue entries/SM. **Range or alternatives:** fill entries: [8, 128]; return entries: [16, 256].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T031 — L1 read-hit latency

**Baseline:** 32.

**Units:** SM-reference cycles. **Range or alternatives:** [20, 43].

**Basis:** Engineering assumption. Intrinsic L1 hit assumed; compound chain43.19 includes other costs. ENGINEERING_ASSUMPTION; sweep this range, not a confidence interval.. **Confidence:** low. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T032 — L1 write service latency

**Baseline:** 4.

**Units:** SM-reference cycles. **Range or alternatives:** [1, 20].

**Basis:** Engineering assumption. L1-path store acceptance/service, bypass still consumes resources. ENGINEERING_ASSUMPTION; sweep this range, not a confidence interval.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T033 — L1 service bandwidth

**Baseline:** 128.

**Units:** bytes/SM-reference cycle. **Range or alternatives:** [32, 256].

**Basis:** Engineering assumption. L1 bytes serviced per reference cycle. ENGINEERING_ASSUMPTION; sweep this range, not a confidence interval.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T034 — L1 refill transfer delay

**Baseline:** 40.

**Units:** SM-reference cycles. **Range or alternatives:** [10, 160].

**Basis:** Engineering assumption. L2-return to L1 fill transfer, excludes L2 lookup. ENGINEERING_ASSUMPTION; sweep this range, not a confidence interval.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


## L2 cache

### F063 — L2 set count

**Baseline:** 1024.

**Units:** sets/L2 slice. **Range or alternatives:** [256, 2048].

**Basis:** Engineering assumption. 48-slice baseline:1024sets*16ways*128B*48=96MiB.64-slice alternative uses768sets to preserve96MiB; non-power-of-two indexing is assumed, not established.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F064 — L2 associativity

**Baseline:** 16.

**Units:** ways/set. **Range or alternatives:** [8, 32].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F065 — L2 slice organization/count

**Baseline:** active model slices: 48; nominal reported slices: 64; FBPs: 8; nominal slices per FBP: 8.

**Units:** slices; FBPs. **Range or alternatives:** active model slices: [48, 64].

**Basis:** Engineering assumption. 64 is queried metadata;48 is inferred counter-instance denominator. Neither establishes enabled physical organization. Run both alternatives.. **Confidence:** low. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F066 — L2 slice address mapping

**Baseline:** slice=(byte_address//128)%active_model_slices.

**Units:** mapping rule. **Range or alternatives:** [modulo stripe, XOR-hashed stripe].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F067 — L2 set address mapping

**Baseline:** set=(byte_address//(128*active_model_slices))%sets_per_slice.

**Units:** mapping rule. **Range or alternatives:** [modulo, XOR-hashed].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F068 — L2 lookup ports

**Baseline:** 1.

**Units:** logical lookup requests/slice/reference cycle. **Range or alternatives:** [1, 4].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F069 — L2 replacement policy

**Baseline:** pseudo-LRU with persisting-line priority when policy enabled.

**Units:** replacement policy. **Range or alternatives:** [LRU, pseudo-LRU, random].

**Basis:** Engineering assumption. Public priority controls exist; hidden replacement is assumed. Known maximum set-aside60MiB and access-policy-window128MiB are controls, not current allocation/cachecapacity.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F070 — L2 write policy

**Baseline:** Write-back/write-allocate; dirty eviction issues DRAM write.

**Units:** write policy. **Range or alternatives:** [write-back/write-allocate, write-back/no-write-allocate, write-through].

**Basis:** Engineering assumption. Official triage documents dirty eviction and delayed DRAM stores; physical allocation and acknowledgment details remain assumptions.. **Confidence:** low. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F071 — L2 pending-miss capacity

**Baseline:** 128.

**Units:** pending distinct misses/L2 slice. **Range or alternatives:** [32, 512].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F072 — L2 pending-consumer merging rules

**Baseline:** Merge requests to identical pending 32-byte sector; wake all registered consumers.

**Units:** merge policy. **Range or alternatives:** [sector merge, line merge, no merge].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F073 — L2 request queue capacity

**Baseline:** 64.

**Units:** request queue entries/L2 slice. **Range or alternatives:** [16, 256].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F074 — L2 fill/return queue capacities

**Baseline:** fill entries: 64; return entries: 64.

**Units:** entries/L2 slice. **Range or alternatives:** fill entries: [16, 256]; return entries: [16, 256].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T035 — L2 read-hit latency

**Baseline:** 300.

**Units:** SM-reference cycles. **Range or alternatives:** [150, 356].

**Basis:** Engineering assumption. Intrinsic L2 response assumed; compound cg path356.48 includes other costs. ENGINEERING_ASSUMPTION; sweep this range, not a confidence interval.. **Confidence:** low. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T036 — L2 write service latency

**Baseline:** 40.

**Units:** SM-reference cycles. **Range or alternatives:** [10, 160].

**Basis:** Engineering assumption. L2 store acceptance-to-cache update, not DRAM persistence. ENGINEERING_ASSUMPTION; sweep this range, not a confidence interval.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T037 — L2 service bandwidth per slice

**Baseline:** 16.

**Units:** bytes/SM-reference cycle. **Range or alternatives:** [8, 64].

**Basis:** Engineering assumption. L2 bytes serviced per slice per reference cycle. ENGINEERING_ASSUMPTION; sweep this range, not a confidence interval.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T038 — L2 return bandwidth

**Baseline:** 768.

**Units:** bytes/SM-reference cycle. **Range or alternatives:** [256, 2048].

**Basis:** Engineering assumption. Aggregate L2 return bytes per reference cycle. ENGINEERING_ASSUMPTION; sweep this range, not a confidence interval.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


## GDDR7/controller

### F075 — Channel/bank organization

**Baseline:** controllers: 16; bits per controller: 32; banks per controller: 16.

**Units:** controllers; bits; banks. **Range or alternatives:** controllers: [16]; banks per controller: [8, 16, 32].

**Basis:** Engineering assumption. 16x32-bit controllers and512-bit interface documented; bank organization assumed.. **Confidence:** low. **Physical status:** partially identified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F076 — Address-to-channel/bank mapping

**Baseline:** channel: (address//256)%16; bank: (address//32768)%16; row: address//524288; column: (address%256)+256*((address//4096)%8).

**Units:** address mapping. **Range or alternatives:** [256B interleave, 128B interleave, XOR-hashed channel/bank].

**Basis:** Engineering assumption. Mapping is an executable placeholder; neither bus width nor profiler instance counts establish it. Corrected to give 2048 bytes per modeled bank row, consistent with F079. This address mapping remains an assumption.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** 16 assumed controllers and16 assumed banks/controller; mapping must change jointly with row size, controller count or bank count.


### F077 — Controller queue capacities

**Baseline:** read entries: 64; write entries: 64.

**Units:** queue entries/controller. **Range or alternatives:** read entries: [16, 256]; write entries: [16, 256].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F078 — Controller arbitration policy

**Baseline:** FR-FCFS: ready row hits first, then oldest; fairness after64 selections.

**Units:** arbitration policy. **Range or alternatives:** [FIFO, FR-FCFS, round-robin].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F079 — Row-state/command rules

**Baseline:** row bytes: 2048; open page: yes; one open row per bank: yes.

**Units:** bytes/row; state rules. **Range or alternatives:** row bytes: [1024, 4096]; page policy: [open, closed, adaptive].

**Basis:** Engineering assumption. Engineering baseline for an executable sensitivity study; not measured or identified.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### F080 — Write handling policy

**Baseline:** write buffer entries: 64; drain high watermark: 48; drain low watermark: 16; merge same sector: yes.

**Units:** entries; controller write policy. **Range or alternatives:** write buffer entries: [16, 256]; high fraction: [0.5, 0.9]; low fraction: [0.1, 0.5].

**Basis:** Engineering assumption. Controller-specific buffering/draining is unsupported. L2 dirty policy does not identify these values.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T039 — Read command/response timing

**Baseline:** 200.

**Units:** SM-reference cycles. **Range or alternatives:** [80, 600].

**Basis:** Engineering assumption. DRAM first-data response after command acceptance, assumes row miss average. ENGINEERING_ASSUMPTION; sweep this range, not a confidence interval.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T040 — Write command/response timing

**Baseline:** 100.

**Units:** SM-reference cycles. **Range or alternatives:** [40, 300].

**Basis:** Engineering assumption. DRAM write service completion after acceptance; not cache acknowledgment. ENGINEERING_ASSUMPTION; sweep this range, not a confidence interval.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T041 — Read/write turnaround

**Baseline:** 24.

**Units:** SM-reference cycles. **Range or alternatives:** [8, 80].

**Basis:** Engineering assumption. Read/write direction turnaround delay. ENGINEERING_ASSUMPTION; sweep this range, not a confidence interval.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


### T042 — Transfer service interval

**Baseline:** 0.0525.

**Units:** SM-reference cycles/32-byte sector, aggregate bus. **Range or alternatives:** [0.0525, 0.21].

**Basis:** Engineering assumption. Aggregate transfer interval:2.94GHz/1.792TB/s=0.001640625cycles/byte, times32B. ENGINEERING_ASSUMPTION; sweep this range, not a confidence interval.. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Provisional GEMM-path simulation baseline. Preserve the stated evidence limits; unsupported structure or timing is an engineering choice, not an identified RTX5090 property.


## Synchronization and completion

### F081 — Barrier participant rules

**Baseline:** warp size: 32; default participants: all live CTA threads; explicit count multiple: 32; barrier slots: 16.

**Units:** threads; named barrier slots. **Range or alternatives:** explicit count: [32, 1024]; barrier id: [0, 15].

**Basis:** Published or toolkit-source rule. PTX ordinary named CTA barrier semantics. **Confidence:** high. **Physical status:** identified.

**Scope:** No async or cluster barriers; model uses one arrival per participating warp representing its active participants.


### F082 — Barrier generation rules

**Baseline:** generation initial: 0; generation increment: 1; release when: participant arrival count reaches configured count; reuse: clear arrivals before accepting next generation.

**Units:** generation counter. **Range or alternatives:** generation counter bits: [32, 32].

**Basis:** Engineering assumption. PTX completion/reuse is known; 32-bit model generation counter is an implementation choice. **Confidence:** mixed. **Physical status:** identified.

**Scope:** Do not interpret model counter width as hardware storage width; overlapping misuse rejected.


### F083 — Barrier drain obligations

**Baseline:** release requires: all earlier participant shared/global operations complete at modeled visibility point; later memory issue: blocked until release; universal DRAM writeback required: no.

**Units:** ordering rule. **Range or alternatives:** participant scope: same CTA.

**Basis:** Published or toolkit-source rule. PTX bar.cta.sync participant-relative memory ordering. **Confidence:** high. **Physical status:** identified.

**Scope:** Model per-warp prior-operation counter; this is a conservative executable interpretation, not a discovered drain circuit.


### F084 — Output-store acknowledgment semantics

**Baseline:** store ack: backing memory accepts and commits modeled store; pending store counter bits: 16; thread exit waits for pending stores: yes.

**Units:** completion rule. **Range or alternatives:** pending store counter bits: [8, 32].

**Basis:** Engineering assumption. No hardware store-acknowledgment point identified; conservative behavioral baseline. **Confidence:** low. **Physical status:** unidentified.

**Scope:** No claim actual GPU waits for physical DRAM commit; visibility may be established in cache.


### F085 — Whole-grid completion rules

**Baseline:** grid done: all CTA threads exited and modeled pending stores returned; completion collection: central outstanding-CTA counter; stream event visible after grid done: yes.

**Units:** completion rule. **Range or alternatives:** counter bits: [16, 32].

**Basis:** Engineering assumption. External CUDA stream/event completion contract known; central collector and store gate are provisional. **Confidence:** mixed. **Physical status:** partially identified.

**Scope:** Ordinary kernels only; no dynamic parallelism, clusters, or dependent-launch overlap.


### T043 — Barrier arrival service rate

**Baseline:** 1.

**Units:** warp arrivals per SM reference cycle. **Range or alternatives:** [0.25, 4].

**Basis:** Engineering assumption. No isolated arrival-throughput measurement; serial one-arrival baseline. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Service one ready warp arrival each reference SM cycle; parameter remains adjustable.


### T044 — Barrier release delay

**Baseline:** 2.

**Units:** SM reference cycles after final accepted arrival. **Range or alternatives:** [1, 32].

**Basis:** Engineering assumption. No isolated release measurement; registered collect/release baseline. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Excludes prior-memory completion and arrival service time.


### T045 — Warp resume delay

**Baseline:** 1.

**Units:** SM reference cycles from release to scheduler eligibility. **Range or alternatives:** [0, 16].

**Basis:** Engineering assumption. No isolated wakeup measurement; one registered eligibility update. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Issue may still wait for scheduler/resource availability; this is not total post-barrier runtime.


## Clock domains

### F086 — Clock-domain organization

**Baseline:** reference SM MHz: 2950; L1TEX to SM rate ratio: 1.0; LTS to SM rate ratio: 0.9020911965950098; globaltimer reference: documented nanosecond counter; target-specific.

**Units:** MHz; clock-rate ratios. **Range or alternatives:** SM MHz: [180, 3090]; LTS to SM rate ratio: [0.5, 1.0].

**Basis:** Measured in the stated experiment. clock_domains and unit_clock_rates receipts; official counter semantics. **Confidence:** medium. **Physical status:** partially identified.

**Scope:** Same-profile operating point SM=L1TEX=2011.50403938MHz, LTS=1814.56008584MHz. 2950MHz is a separate measured workload reference; ratios are not universal clock topology.


### F087 — Cross-domain transfer protocol

**Baseline:** protocol: dual-clock ready/valid FIFO; depth: 4; synchronizer stages: 2; ordering: FIFO; no loss/duplication.

**Units:** entries; clock edges. **Range or alternatives:** depth: [2, 16]; synchronizer stages: [2, 3].

**Basis:** Engineering assumption. No private GPU CDC protocol observed; safe simulator baseline. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Chosen asynchronous FIFO behavior, not inferred silicon circuitry.


### T046 — Memory-domain frequencies

**Baseline:** reported memory MHz: 14001; reference SM MHz: 2950; same profile SM MHz: 2011.50403938; same profile L1TEX MHz: 2011.50403938; same profile LTS MHz: 1814.56008584.

**Units:** management-reported MHz; counter-derived MHz. **Range or alternatives:** reported supported memory MHz: [405, 810, 7001, 13801, 14001]; supported SM MHz: [180, 3090].

**Basis:** Device query and scoped measurement. nvidia-smi supported clocks and same-profile unit cycle rates. **Confidence:** medium. **Physical status:** partially identified.

**Scope:** No conversion of management memory MHz into GDDR7 command clock or data rate.


### T047 — Cross-domain transfer delay

**Baseline:** minimum forward latency: 2; minimum return latency: 2.

**Units:** destination clock edges. **Range or alternatives:** forward: [2, 8]; return: [2, 8].

**Basis:** Engineering assumption. Chosen two-stage CDC baseline; no transfer-delay measurement. **Confidence:** low. **Physical status:** unidentified.

**Scope:** Queueing adds delay separately; at equal clock rates empty round trip baseline is four cycles.
