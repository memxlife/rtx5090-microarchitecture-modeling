# Hardware parameter inventory and progress

The inventory has **87 functional/structural fields and 47 timing fields**. Currently **8 functional fields are identified** and **79 remain**; **0 timing fields are identified** and **47 remain**. Thus **126 fields remain**, including 24 partially identified functional fields and 8 partially identified timing fields. The [provisional parameter profile](provisional_parameters.md) assigns a development baseline to every field; those assignments do not close physical evidence gaps.

Each field may be a vector by instruction class or queue family. A partial field still counts as remaining. These are current GEMM-path specification entries, not every scalar property inside the GPU. Implementation-only tasks and already-known device capacities are excluded.

| Component | Functional baseline | Functional identified | Functional remaining | Timing baseline | Timing identified | Timing remaining |
|---|---:|---:|---:|---:|---:|---:|
| Block allocation and dispatch | 4 | 2 | 2 | 3 | 0 | 3 |
| Instruction fetch and control | 8 | 0 | 8 | 3 | 0 | 3 |
| Warp scheduler | 6 | 2 | 4 | 2 | 0 | 2 |
| Registers and operand collection | 8 | 0 | 8 | 5 | 0 | 5 |
| CUDA/operand execution | 3 | 0 | 3 | 3 | 0 | 3 |
| Matrix execution | 6 | 0 | 6 | 3 | 0 | 3 |
| Load/store path | 7 | 0 | 7 | 4 | 0 | 4 |
| Address translation | 5 | 0 | 5 | 3 | 0 | 3 |
| Shared memory | 6 | 1 | 5 | 4 | 0 | 4 |
| L1 cache | 9 | 0 | 9 | 4 | 0 | 4 |
| L2 cache | 12 | 0 | 12 | 4 | 0 | 4 |
| GDDR7/controller | 6 | 0 | 6 | 4 | 0 | 4 |
| Synchronization and completion | 5 | 3 | 2 | 3 | 0 | 3 |
| Clock domains | 2 | 0 | 2 | 2 | 0 | 2 |
| **Total** | **87** | **8** | **79** | **47** | **0** | **47** |

[Source sweep 5](discovery_rounds/source_sweep_005.md) resolves allocation granularities. [Hardware sweep 1](discovery_rounds/hardware_sweep_001.md) adds measured shared-memory evidence. [Round 3 findings](discovery_rounds/source_sweep_003.md) record the saved native instruction audit. [Round 2 findings](discovery_rounds/source_sweep_002.md) cover cache and ordering constraints. [Round 1 findings](discovery_rounds/source_sweep_001.md) explain the evidence and limits. The [machine-readable registry](missing_parameter_registry.json) preserves values, scope and source links. Counts are reproduced by `python studies/rtx5090_gemm_milp/rtl/parameter_progress.py`.

## Block allocation and dispatch

| Identity | Category | Field | Current evidence status |
|---|---|---|---|
| F001 | functional | Register allocation granularity | identified |
| F002 | functional | Shared allocation granularity | identified |
| F003 | functional | Block placement policy | unidentified |
| F004 | functional | Dispatch arbitration policy | unidentified |
| T001 | timing | Block admission delay | unidentified |
| T002 | timing | Dispatch delay | unidentified |
| T003 | timing | Allocation release delay | unidentified |

## Instruction fetch and control

| Identity | Category | Field | Current evidence status |
|---|---|---|---|
| F005 | functional | Instruction-cache capacity | unidentified |
| F006 | functional | Instruction-cache sets | unidentified |
| F007 | functional | Instruction-cache associativity | unidentified |
| F008 | functional | Instruction-cache mapping | unidentified |
| F009 | functional | Instruction-cache replacement policy | unidentified |
| F010 | functional | Native decoding rules | partially_identified |
| F011 | functional | Divergence handling | partially_identified |
| F012 | functional | Reconvergence handling | partially_identified |
| T004 | timing | Instruction fetch latency | unidentified |
| T005 | timing | Instruction fetch bandwidth | unidentified |
| T006 | timing | Decode delay | unidentified |

## Warp scheduler

| Identity | Category | Field | Current evidence status |
|---|---|---|---|
| F013 | functional | Scheduler partitions per SM | identified |
| F014 | functional | Warp-to-partition assignment | unidentified |
| F015 | functional | Issue slot count | identified |
| F016 | functional | Multiple-issue compatibility rules | partially_identified |
| F017 | functional | Instruction-class routing | partially_identified |
| F018 | functional | Arbitration policy | unidentified |
| T007 | timing | Instruction-class initiation intervals | unidentified |
| T008 | timing | Dependency wakeup delay | unidentified |

## Registers and operand collection

| Identity | Category | Field | Current evidence status |
|---|---|---|---|
| F019 | functional | Register bank count | unidentified |
| F020 | functional | Register bank mapping | unidentified |
| F021 | functional | Read ports per register bank | unidentified |
| F022 | functional | Write ports per register bank | unidentified |
| F023 | functional | Operand collector capacity | unidentified |
| F024 | functional | Collector routing | unidentified |
| F025 | functional | Writeback queue capacity | unidentified |
| F026 | functional | Writeback arbitration policy | unidentified |
| T009 | timing | Register read latency | unidentified |
| T010 | timing | Register write latency | unidentified |
| T011 | timing | Operand collection delay | unidentified |
| T012 | timing | Bypass delay | unidentified |
| T013 | timing | Writeback service rate | unidentified |

## CUDA/operand execution

| Identity | Category | Field | Current evidence status |
|---|---|---|---|
| F027 | functional | Execution pipeline counts by class | unidentified |
| F028 | functional | Supported numerical operation semantics | partially_identified |
| F029 | functional | Pipeline sharing rules | partially_identified |
| T014 | timing | Instruction-class result latencies | partially_identified |
| T015 | timing | Instruction-class initiation intervals | partially_identified |
| T016 | timing | Register rearrangement delay | partially_identified |

## Matrix execution

| Identity | Category | Field | Current evidence status |
|---|---|---|---|
| F030 | functional | Tensor pipeline organization/count | partially_identified |
| F031 | functional | Execution partition routing | unidentified |
| F032 | functional | Native lane/register layout | partially_identified |
| F033 | functional | Native instruction-to-operation decomposition | partially_identified |
| F034 | functional | Accumulation order | partially_identified |
| F035 | functional | Exceptional numerical behavior | partially_identified |
| T017 | timing | Native matrix result latency | unidentified |
| T018 | timing | Native matrix initiation interval | unidentified |
| T019 | timing | Matrix result delivery bandwidth | unidentified |

## Load/store path

| Identity | Category | Field | Current evidence status |
|---|---|---|---|
| F036 | functional | Load queue capacity | unidentified |
| F037 | functional | Store queue capacity | unidentified |
| F038 | functional | Outstanding transaction limit per warp | unidentified |
| F039 | functional | Outstanding transaction limit per SM | unidentified |
| F040 | functional | Native instruction coalescing rules | partially_identified |
| F041 | functional | Memory ordering rules | partially_identified |
| F042 | functional | Return assembly rules | partially_identified |
| T020 | timing | Load issue service rate | partially_identified |
| T021 | timing | Store issue service rate | unidentified |
| T022 | timing | Return bandwidth | unidentified |
| T023 | timing | Store visibility/completion delay | unidentified |

## Address translation

| Identity | Category | Field | Current evidence status |
|---|---|---|---|
| F043 | functional | Supported page sizes | unidentified |
| F044 | functional | Translation-cache organization | unidentified |
| F045 | functional | Translation mapping/replacement rules | unidentified |
| F046 | functional | Translation request capacity | unidentified |
| F047 | functional | Page-walk organization | unidentified |
| T024 | timing | Translation hit delay | unidentified |
| T025 | timing | Translation miss processing delay | unidentified |
| T026 | timing | Page-walk delay | unidentified |

## Shared memory

| Identity | Category | Field | Current evidence status |
|---|---|---|---|
| F048 | functional | L1/shared partition configuration | partially_identified |
| F049 | functional | Read ports per shared bank | unidentified |
| F050 | functional | Write ports per shared bank | unidentified |
| F051 | functional | Shared request queue capacity | unidentified |
| F052 | functional | Warp transaction splitting rules | partially_identified |
| F053 | functional | Broadcast rules | identified |
| T027 | timing | Shared read response latency | partially_identified |
| T028 | timing | Shared write response latency | unidentified |
| T029 | timing | Broadcast delay | unidentified |
| T030 | timing | Shared-to-operand transfer delay | unidentified |

## L1 cache

| Identity | Category | Field | Current evidence status |
|---|---|---|---|
| F054 | functional | L1 capacity in selected partition | partially_identified |
| F055 | functional | L1 set count | unidentified |
| F056 | functional | L1 associativity | unidentified |
| F057 | functional | L1 address mapping | unidentified |
| F058 | functional | L1 replacement policy | unidentified |
| F059 | functional | L1 write policy | partially_identified |
| F060 | functional | L1 pending-miss capacity | unidentified |
| F061 | functional | L1 pending-consumer merging rules | unidentified |
| F062 | functional | L1 fill/return queue capacities | unidentified |
| T031 | timing | L1 read-hit latency | partially_identified |
| T032 | timing | L1 write service latency | unidentified |
| T033 | timing | L1 service bandwidth | unidentified |
| T034 | timing | L1 refill transfer delay | unidentified |

## L2 cache

| Identity | Category | Field | Current evidence status |
|---|---|---|---|
| F063 | functional | L2 set count | unidentified |
| F064 | functional | L2 associativity | unidentified |
| F065 | functional | L2 slice organization/count | partially_identified |
| F066 | functional | L2 slice address mapping | unidentified |
| F067 | functional | L2 set address mapping | unidentified |
| F068 | functional | L2 lookup ports | unidentified |
| F069 | functional | L2 replacement policy | unidentified |
| F070 | functional | L2 write policy | partially_identified |
| F071 | functional | L2 pending-miss capacity | unidentified |
| F072 | functional | L2 pending-consumer merging rules | unidentified |
| F073 | functional | L2 request queue capacity | unidentified |
| F074 | functional | L2 fill/return queue capacities | unidentified |
| T035 | timing | L2 read-hit latency | partially_identified |
| T036 | timing | L2 write service latency | unidentified |
| T037 | timing | L2 service bandwidth per slice | unidentified |
| T038 | timing | L2 return bandwidth | unidentified |

## GDDR7/controller

| Identity | Category | Field | Current evidence status |
|---|---|---|---|
| F075 | functional | Channel/bank organization | partially_identified |
| F076 | functional | Address-to-channel/bank mapping | unidentified |
| F077 | functional | Controller queue capacities | unidentified |
| F078 | functional | Controller arbitration policy | unidentified |
| F079 | functional | Row-state/command rules | unidentified |
| F080 | functional | Write handling policy | unidentified |
| T039 | timing | Read command/response timing | unidentified |
| T040 | timing | Write command/response timing | unidentified |
| T041 | timing | Read/write turnaround | unidentified |
| T042 | timing | Transfer service interval | unidentified |

## Synchronization and completion

| Identity | Category | Field | Current evidence status |
|---|---|---|---|
| F081 | functional | Barrier participant rules | identified |
| F082 | functional | Barrier generation rules | identified |
| F083 | functional | Barrier drain obligations | identified |
| F084 | functional | Output-store acknowledgment semantics | unidentified |
| F085 | functional | Whole-grid completion rules | partially_identified |
| T043 | timing | Barrier arrival service rate | unidentified |
| T044 | timing | Barrier release delay | unidentified |
| T045 | timing | Warp resume delay | unidentified |

## Clock domains

| Identity | Category | Field | Current evidence status |
|---|---|---|---|
| F086 | functional | Clock-domain organization | partially_identified |
| F087 | functional | Cross-domain transfer protocol | unidentified |
| T046 | timing | Memory-domain frequencies | partially_identified |
| T047 | timing | Cross-domain transfer delay | unidentified |


## Native matrix mapping and integration update

For the tested BF16 16 × 16 × 16 operation, measurements establish where all A, B and C elements reside in the warp registers and how two native matrix instructions cover the output. The [connected adapter](numerical/native_bf16_adapter.sv) uses those positions to run the numerical component. Its [verification](numerical/native_matrix_verification.json) checks 3,072 output words under two synthetic timing configurations. This strengthens F032 and F033; both broad fields remain partially identified because other operation families and private routing remain unknown. The total remains 80 functional and 47 timing fields.

## LDSM service and timing update

Round 5 resolves two narrower contracts while leaving the broad inventory unchanged: the supported native LDSM descriptor fields and its additional conflict delay. The decoder recognizes eight measured descriptors. A group-aware service rule matches 24 development cases and six new address cases. Six further, untouched cases match the frozen prediction of two additional SM cycles per extra service package in the tested dependent loop. This is not a measurement of intrinsic load latency or independent issue rate. F010 and T020 therefore become partial, bringing partial totals to 17 functional and 3 timing fields. **80 functional and 47 timing fields remain.**

## Sprint numerical and timing update

The reconstructed aligned-dot arithmetic rule now runs in the RTL/DPI component as ARITHMETIC_MODE=1. It reproduces 1,536 saved hardware output words; the older sequential FP32 reference fails the same finite cancellation comparison. F034 records this supported arithmetic family, while F035 records measured exceptional/subnormal observations without claiming a complete numerical contract. Scalar dependency/service measurements partially identify T014 and strengthen T015; they include compiler scheduling and do not separately prove intrinsic execution latency. Generic memory routing and documented scalar load extension strengthen functional return-path contracts. The current inventory remains **80 functional and 47 timing fields**, including **21 functional and 4 timing partials**.
