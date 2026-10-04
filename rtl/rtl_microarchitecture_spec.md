# RTX 5090 microarchitecture development manual

## Purpose and reading order

This manual specifies the behavioral reconstruction used to investigate whether realistic GPU kernel optimization can be expressed and solved as a mixed-integer program. It describes hardware resources, component behavior, interfaces and cycle rules, with links to executable sources. The physical GPU remains the reference for performance validation.

Start with [Chapter 00: whole-GPU overview and architecture diagrams](manual/00_gpu_overview.md). It explains the physical organization, the path of one GEMM tile, and the smaller simulator currently implemented. The system contracts below apply to every component chapter.

The organization follows the [XiangShan and Intel-inspired development template](hardware_development_manual_template.md) and [approved documentation structure](hardware_manual_structure.md). The earlier inline-code edition is preserved as [a historical reference](rtl_microarchitecture_spec.inline_legacy.md); current code belongs in separate linked files.

## Component chapter index

| Chapter | Specification |
|---|---|
| 00 | [Whole-GPU microarchitecture overview](manual/00_gpu_overview.md) |
| 01 | [Work distribution and block admission](manual/components/01_work_distribution_and_block_admission.md) |
| 02 | [Warp state and instruction supply](manual/components/02_warp_state_and_instruction_supply.md) |
| 03 | [Scheduling and instruction issue](manual/components/03_scheduling_and_instruction_issue.md) |
| 04 | [Registers, readiness, and operand collection](manual/components/04_registers_readiness_and_operand_collection.md) |
| 05 | [Scalar and address execution](manual/components/05_scalar_and_address_execution.md) |
| 06 | [Matrix operands and tensor execution](manual/components/06_matrix_operands_and_tensor_execution.md) |
| 07 | [Load/store execution](manual/components/07_load_store_execution.md) |
| 08 | [Address translation](manual/components/08_address_translation.md) |
| 09 | [Shared-memory service](manual/components/09_shared_memory_service.md) |
| 10 | [L1 cache and shared partition](manual/components/10_l1_cache_and_shared_partition.md) |
| 11 | [L2 cache and refill ownership](manual/components/11_l2_cache_and_refill_ownership.md) |
| 12 | [Backing memory and response transport](manual/components/12_backing_memory_and_response_transport.md) |
| 13 | [Barriers and retirement](manual/components/13_barriers_and_retirement.md) |
| 14 | [Clocks, event transport, and observation](manual/components/14_clocks_event_transport_and_observation.md) |

Each component chapter contains purpose, quantitative parameters, interfaces, storage, transitions, timing, invariants, separate source links, verification and optimization implications. Its per-module contracts distinguish standalone prototypes from current numerical implementations.

## Quantitative configuration and evidence

[Complete parameter table](parameter_master_table.md) contains 151 entries: 134 original functional/timing entries and 17 additional recorded configuration/capacity entries. Each of the 87 functional and 47 timing entries has one owning component chapter. The table keeps baseline settings and evidence status separate from initial-check alternatives.

| Quantity | Physical record | Connected reconstruction |
|---|---:|---:|
| SMs | 170 active | 2 |
| Resident block contexts | At most 24 per SM, resource-dependent | 2 per modeled SM |
| Warp width | 32 lanes | 32 lanes on numerical warp paths |
| Register capacity | 65,536 32-bit words per SM | Specialized contexts and bounded helpers |
| Shared memory | 102,400 bytes per SM reported | Configured operand frames and numerical shared helpers |
| Total L2 | 96 MiB | 64 KiB test geometry |
| Pending shared-cache fetches | Provisional physical estimate | 4 MSHR entries |
| Shared-cache consumers | Provisional physical estimate | 8 ownership entries |
| Reference clock | 2.94 GHz conversion reference | One discrete model clock |

### Executable top defaults: synthetic timing settings

| Parameter | Default | Meaning |
|---|---:|---|
| `M`, `N`, `K` | 64, 96, 64 | Matrix dimensions, configurable multiples of 32 |
| `READ_SLOTS` | 2 | Configured read ownership capacity |
| `RETURN_DELAY` | 9 cycles | Configured local read return delay |
| `MOVM_LATENCY` | 19 cycles | Configured matrix-operand completion delay |
| `HMMA_LATENCY` | 73 cycles | Configured native matrix completion delay |
| `SERVICE_INTERVAL`, `MOVM_INTERVAL` | 1 cycle | Configured acceptance spacing |
| `HMMA_INTERVAL` | 4 cycles | Configured native matrix acceptance spacing |
| `STORE_INTERVAL`, `STORE_RETURN_DELAY` | 1 cycle | Store acceptance spacing and return delay |
| `BARRIER_RELEASE_DELAY` | 1 cycle | Configured barrier release delay |

These defaults come from the connected top's parameter declaration. They are not the fresh GPU probe results and are not silently replaced by the effective-path estimator. Calibrating this connected model remains separate work.

For a chosen reference frequency of 2.94 GHz, one microsecond corresponds to 2,940 reference cycles. Hardware clocks vary during execution. A conversion requires the measured clock for that run when available; it does not identify internal memory clock domains.

## Supported execution domain

The latest connected top is [resident_gemm_multi_sm_nb_l2.sv](numerical/resident_gemm_multi_sm_nb_l2.sv). It executes the studied BF16-input, FP32-output matrix path using explicit operand staging, native matrix mapping, reduction stages and acknowledged output stores. Its supported grid dimensions are multiples of 32. A and B are immutable during a launch; C must be aligned, bounded and disjoint from the input regions. This is not a general CUDA instruction simulator or a cache-coherent multiprocessor.

The top's ports are the authoritative executable interface. Launch transfers a 32-bit identity and three 32-bit base addresses. Backing reads carry an identity and byte address; responses carry an identity and 256-bit sector. Stores additionally carry a 256-bit sector and eight-bit word mask, then receive an identity acknowledgement. Completion returns the captured launch identity. Counters report resident/dispatched/completed blocks, elapsed cycles and shared-cache events.

## Common clock and interface contract

1. A request transfers at a rising edge when its valid and ready signals are both asserted. Payload belongs to the receiver after that transfer.
2. A response becomes observable after state updates settle. It retires only at an edge where response valid and ready are both asserted. Held responses retain their identity and data.
3. Clocked modules use synchronous active-high reset unless their source says otherwise. Reset cancels modeled ownership; only tested reset scenarios are claimed.
4. Do not reuse a live transaction identity within its routing domain. A return must route to its original owner even if other operations have completed first.
5. Acceptance interval, completion latency and outstanding capacity are separate parameters. A full queue may require an extra edge before accepting a replacement; inspect its actual same-edge rules.
6. A C++ host advances the whole connected model on one shared edge. Sequentially ticking child components would change causality and is not an equivalent implementation.

## System connections and ownership

| Producer | Consumer | Transaction | Ownership ends when |
|---|---|---|---|
| Grid dispatcher | Resident SM context | Tile identity, coordinates and bases | Required stores complete and block completion transfers |
| Global operand adapter | Cache/read transport | Sector address and return identity | Returned words are accepted by the original staging owner |
| Staging controller | Shared storage | Operand frame writes | Required data is committed before consumer release |
| Shared-read hub | Operand mapping | Lane words and client identity | Matching result is accepted |
| Matrix issue | Accumulator storage | Native operand update | Result is available to its next dependent consumer |
| SM read paths | Shared L2 gateway | Sector request | Consumer accepts hit/refill response |
| Shared L2 gateway | Backing transport | Pending sector fetch | Tagged fill returns and ownership is safely released |
| Output adapter | Backing storage | Masked sector write | Store acknowledgement returns |

Refer to Chapter 00 for the organization diagrams. Each component chapter gives exact signal tables and state transitions for its available modules. Helpers are implementation alternatives, not extra physical resources to count alongside the connected top.

## Implementation, build and evidence navigation

- [Integration and verification contracts](manual/integration_and_verification.md): connected top, source dependencies, numerical checks and timing limits.
- [C++ simulator API and build instructions](cpp/README.md): generated execution, clock adapter and reproducible tests.
- [Evidence history and library interpretation](manual/evidence_history.md): experiments, initial checks and claim boundaries.
- [Latest initial-check and performance results](parameter_sweep/initial_validation_20261003_222837/summary.md).

## Current acceptance boundary

The numerical connected model checks 24,576 output words in its saved receipt. The new C++ queue and shared-memory adapters pass capacity, FIFO/data, latency and held-response checks. These establish model behavior at their tested scope. The integrated Verilog model is not yet calibrated against RTX 5090 timing, and no C++ speedup measurement is claimed.

A separate revised phase estimator stayed within 5% on two new workloads. Future model changes should target the largest consequential mismatch and use the simplest distinguishing test. Transferred priors remain acceptable provisional inputs; an initial check does not become a claim of exact private hardware identification.
