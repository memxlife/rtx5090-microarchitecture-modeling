from pathlib import Path
import json
R=Path(__file__).resolve().parents[1]
def L(name,label=None):
 p=R/name;return f'[{label or p.name}]({p})'
idx=json.loads((R/'manual/chapter_index.json').read_text())
white='https://images.nvidia.com/aem-dam/Solutions/geforce/blackwell/nvidia-rtx-blackwell-gpu-architecture.pdf'
(R/'manual/00_gpu_overview.md').write_text(f'''# 00. Whole-GPU microarchitecture overview

{L('rtl_microarchitecture_spec.md','System specification and manual index')}

## 1. What the GPU must accomplish

A matrix multiplication needs many small groups of threads to fetch operands, compute partial products, and commit results. The GPU runs those groups concurrently. Its performance depends on whether work is ready, whether execution units can accept it, and whether data reaches them fast enough. This chapter explains the whole machine before the component chapters specify its parts.

A **thread block** is a group of threads with block-local shared memory and synchronization. A **warp** is a group of 32 threads that issues an instruction together, with individual lanes potentially inactive. An **SM**, or streaming multiprocessor, holds resident blocks and executes their warps. **Residency** means a block has been admitted and occupies the resources needed to make progress; it does not mean every resident warp executes every cycle.

The physical organization below combines documented RTX Blackwell structures with the saved device query. It is a functional organization diagram, not a recovered floorplan or exact interconnect topology. The executable reconstruction is shown separately.

## 2. Quantitative organization

| Resource | Recorded organization | Meaning and evidence boundary |
|---|---:|---|
| Active SMs | 170 | Saved device query; active product configuration |
| Warp width | 32 threads | CUDA execution group |
| Architectural scheduler partitions | 4 per SM | RTX Blackwell SM diagram; exact warp assignment is not recovered |
| Architectural Tensor Core blocks | 4 per SM | Documented blocks; internal tensor pipeline count is not inferred |
| Register capacity | 65,536 32-bit words per SM = 256 KiB | Saved query; physical bank/port topology remains provisional |
| Maximum resident warps | 48 per SM | Saved device limit, subject to other resource limits |
| Maximum resident blocks | 24 per SM | Saved device limit, subject to other resource limits |
| Unified L1/shared pool | 128 KiB per SM | Documented pool; allocation preference is not an exact observed carveout |
| Reported shared-memory capacity | 102,400 bytes per SM | Saved query, distinct from the full unified pool |
| Opt-in shared-memory limit | 101,376 bytes per block | Saved query; actual launch allocation must obey its applicable limit |
| Total L2 cache | 96 MiB | Saved query; physical mapping/associativity is not identified by this number |
| Memory interface | 512 bits; sixteen 32-bit controllers | Documented interface organization; DRAM bank mapping remains provisional |
| Reference SM clock | 2.94 GHz | Chosen conversion reference; not a fixed operating clock |

Sources and detailed query scope are retained in the {L('parameter_master_table.md','master parameter table')} and {L('discovery_rounds/source_sweep_001.md','architecture-source review')}. The documented structures come from the [RTX Blackwell architecture whitepaper]({white}). Do not import B200 server-GPU structures into this RTX specification.

## 3. Whole-system organization

```mermaid
flowchart TD
    H[Host supplies kernel launch and memory bases] --> D[Grid work distribution and block admission]
    D --> S[170 active SMs: resident blocks and warps]
    S --> I[Per-SM L1 cache and shared-memory service]
    S --> X[Scalar and tensor execution within each SM]
    I --> L[Shared L2 cache: 96 MiB total]
    L --> M[Memory controllers: 512-bit aggregate interface]
    M --> G[Device backing memory]
    G --> M
    M --> L
    L --> I
    I --> S
    S --> C[Output stores acknowledged and blocks retired]
```

The arrows describe requests, data returns and work flow. They do not assert a particular number of internal links or an identified routing policy. Shared memory is block-local storage inside an SM; it is not a level between L1 and L2 on every request. A global load may use L1 or bypass it depending on the instruction policy. A hit still takes service time, and multiple misses can remain outstanding.

## 4. Inside an SM

```mermaid
flowchart LR
    W[Resident warp state and instruction position] --> R[Dependency and resource readiness]
    R --> Q[Scheduler partitions and instruction issue]
    Q --> O[Register operands and result ownership]
    O --> A[Scalar and address execution]
    O --> T[Tensor execution]
    O --> U[Load/store execution]
    U --> B[Shared-memory banks and broadcasts]
    U --> K[L1 cache and global-memory path]
    B --> O
    K --> O
    A --> O
    T --> O
    Q --> F[Barrier and completion state]
    F --> R
```

This is the microarchitecture's functional dependency diagram. The current reconstruction does not implement every box as a general instruction engine. In particular, scalar/address arithmetic is specialized to the GEMM controllers, and translation is a flat-address abstraction. Exact register banking and scheduler routing remain provisional.

An instruction can wait for three different reasons: its input has not arrived; its destination unit cannot accept another operation; or finite storage for the request/result is full. These reasons need separate state in an executable model. A single fixed delay cannot represent every combination.

## 5. Trace one GEMM tile through the machine

1. The work distributor assigns a matrix tile and reserves a resident block context. Register/shared-memory demand can prevent additional blocks from entering.
2. Warps calculate addresses and submit global loads. Lane requests sharing a 32-byte sector can be combined. Cache hits return retained data; misses reserve fetch and response ownership.
3. Completed operands are stored in shared memory. A barrier prevents matrix consumers from proceeding before the required staging is complete.
4. Shared loads or MOVM/LDSM operations map words into the matrix instruction's lane/register arrangement. Bank conflicts can increase service work even when the requested byte count is unchanged.
5. Native tensor operations update accumulators. The next dependent operation must wait for the prior result, while other eligible work may progress.
6. Output adapters construct masked stores. The block retires after required stores are acknowledged, then releases its context. Other blocks can reuse the freed resources.

**Coalescing** means combining lane accesses to the same serviced memory sector. **Backpressure** means a receiver with no available capacity prevents acceptance. **Arbitration** means choosing among simultaneously eligible requests. These mechanisms explain why the amount of arithmetic or bytes alone does not determine runtime.

## 6. Key design features the optimizer must represent

Many resident warps can hide waiting, but registers, shared memory and block slots limit residency. Tensor operations require exact operand layouts and completion ordering. Cache reuse reduces backing traffic, while hit timing, request contention and finite pending ownership still affect progress. Shared-memory banks can broadcast a common word but may serialize distinct words mapping to one bank. Completion and store acknowledgement determine when resources are genuinely reusable.

These are candidate constraints and costs for the MIP, or mixed-integer program. Discrete decisions choose tile shape, layout and schedule; resource limits bound simultaneous work; dependency rules bound start times. Parameters supported only by priors remain provisional until a consequential mismatch requires refinement.

## 7. What is actually connected in the simulator

```mermaid
flowchart TD
    D[Resident grid dispatcher] --> S0[Modeled SM 0: two resident contexts]
    D --> S1[Modeled SM 1: two resident contexts]
    S0 --> P0[Operand staging, shared reads, native matrix updates]
    S1 --> P1[Operand staging, shared reads, native matrix updates]
    P0 --> L[Shared nonblocking read cache]
    P1 --> L
    L --> B[Tagged backing-sector transport and test storage]
    P0 --> C[Masked output stores and acknowledgements]
    P1 --> C
    C --> B
    C --> D
```

The latest top implements two modeled SMs, two contexts each, a read-only shared-cache path and disjoint outputs. Its test L2 geometry is 64 KiB with eight consumer-owner slots and four pending-fetch entries. A **pending-fetch entry**, called an MSHR, tracks a miss until its data returns. These settings exercise the mechanism; they are not the physical 96 MiB L2 geometry.

The connected model passed numerical tests checking 24,576 output words. Its cycle timing remains uncalibrated. A separate phase-cost estimator predicted two new workload runtimes within 5%; that result must not be attributed to this Verilog model.

Continue to the {L('rtl_microarchitecture_spec.md','system specification')} for port contracts and chapter navigation, then follow the component chapters for exact state transitions and linked source.
''')
rows='\n'.join(f'| {i:02} | [{x["title"]}]({x["path"]}) |' for i,x in enumerate(idx,1))
(R/'rtl_microarchitecture_spec.md').write_text(f'''# RTX 5090 microarchitecture development manual

## Purpose and reading order

This manual specifies the behavioral reconstruction used to investigate whether realistic GPU kernel optimization can be expressed and solved as a mixed-integer program. It describes hardware resources, component behavior, interfaces and cycle rules, with links to executable sources. The physical GPU remains the reference for performance validation.

Start with {L('manual/00_gpu_overview.md','Chapter 00: whole-GPU overview and architecture diagrams')}. It explains the physical organization, the path of one GEMM tile, and the smaller simulator currently implemented. The system contracts below apply to every component chapter.

The organization follows the {L('hardware_development_manual_template.md','XiangShan and Intel-inspired development template')} and {L('hardware_manual_structure.md','approved documentation structure')}. The earlier inline-code edition is preserved as {L('rtl_microarchitecture_spec.inline_legacy.md','a historical reference')}; current code belongs in separate linked files.

## Component chapter index

| Chapter | Specification |
|---|---|
| 00 | {L('manual/00_gpu_overview.md','Whole-GPU microarchitecture overview')} |
{rows}

Each component chapter contains purpose, quantitative parameters, interfaces, storage, transitions, timing, invariants, separate source links, verification and optimization implications. Its per-module contracts distinguish standalone prototypes from current numerical implementations.

## Quantitative configuration and evidence

{L('parameter_master_table.md','Complete parameter table')} contains 151 entries: 134 original functional/timing entries and 17 additional recorded configuration/capacity entries. Each of the 87 functional and 47 timing entries has one owning component chapter. The table keeps baseline settings and evidence status separate from initial-check alternatives.

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

For a chosen reference frequency of 2.94 GHz, one microsecond corresponds to 2,940 reference cycles. Hardware clocks vary during execution. A conversion requires the measured clock for that run when available; it does not identify internal memory clock domains.

## Supported execution domain

The latest connected top is {L('numerical/resident_gemm_multi_sm_nb_l2.sv')}. It executes the studied BF16-input, FP32-output matrix path using explicit operand staging, native matrix mapping, reduction stages and acknowledged output stores. Its supported grid dimensions are multiples of 32. A and B are immutable during a launch; C must be aligned, bounded and disjoint from the input regions. This is not a general CUDA instruction simulator or a cache-coherent multiprocessor.

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

- {L('manual/integration_and_verification.md','Integration and verification contracts')}: connected top, source dependencies, numerical checks and timing limits.
- {L('cpp/README.md','C++ simulator API and build instructions')}: generated execution, clock adapter and reproducible tests.
- {L('manual/evidence_history.md','Evidence history and library interpretation')}: experiments, initial checks and claim boundaries.
- {L('parameter_sweep/initial_validation_20261003_222837/summary.md','Latest initial-check and performance results')}.

## Current acceptance boundary

The numerical connected model checks 24,576 output words in its saved receipt. The new C++ queue and shared-memory adapters pass capacity, FIFO/data, latency and held-response checks. These establish model behavior at their tested scope. The integrated Verilog model is not yet calibrated against RTX 5090 timing, and no C++ speedup measurement is claimed.

A separate revised phase estimator stayed within 5% on two new workloads. Future model changes should target the largest consequential mismatch and use the simplest distinguishing test. Transferred priors remain acceptable provisional inputs; an initial check does not become a claim of exact private hardware identification.
''')
(R/'manual/integration_and_verification.md').write_text(f'''# Integration and verification

{L('rtl_microarchitecture_spec.md','System specification')} · {L('manual/00_gpu_overview.md','Whole-GPU overview')}

## Connected execution contract

The latest top is {L('numerical/resident_gemm_multi_sm_nb_l2.sv')}. It assigns disjoint output tiles to two SM models, each with two resident contexts. A shared nonblocking read gateway coordinates pending fetches. Backing reads and masked writes are serviced by the numerical test harness; store acknowledgement is required before grid completion.

The source has explicit launch range, alignment and overlap checks. It captures matrix bases at acceptance so subsequent host changes do not alter an in-flight launch. The test domain uses immutable A/B inputs and disjoint C output. General coherent writes, atomics and arbitrary CUDA control flow are not implemented.

## Existing numerical receipt

{L('numerical/resident_multi_sm_nb_l2_verification.json','Connected-grid verification receipt')} records 24,576 checked output words across reductions of length 64 and 1,536, with two launches per reduction length. Each launch executes six blocks and reaches four resident blocks. Invalid launches cover misaligned C, overlap with A or B, and address overflow. Reset is tested only at the first pending input read, not during output stores.

The oracle constructs expected numerical matrix results independently of cache service and request ordering. Thus changing modeled cache timing cannot make wrong matrix values pass merely by finishing later. The receipt's elapsed cycles are model measurements, not comparisons with measured RTX timing.

## Source dependency and rebuild contract

{L('numerical/verify_resident_gemm_multi_sm_nb_l2.py','The connected-grid verifier')} is the authoritative existing dependency recipe. It imports its base source list and adds the resident-grid, shared-cache and transport modules. Preserve that dependency order and its DPI numerical support. The verifier builds a clocked Verilator testbench and checks the expected output words.

The fourteen primitive modules are separately available under the component library directory. Their bodies were extracted from {L('components/hardware_blocks.sv','the preserved compatibility bundle')}. Compile either the bundle or the corresponding split files, never both, because they define the same modules.

## C++ equivalence boundary

{L('cpp/component_model.hpp','The C++ adapter')} drives Verilator-generated components. The generated state transitions come from the linked Verilog; there is no second handwritten copy of cache or queue behavior. A connected top must be evaluated as one hierarchy. Do not tick its children separately.

The two new adapter tests passed: {L('cpp/queue_smoke.cpp','queue capacity/FIFO/held response')} and {L('cpp/shared_smoke.cpp','shared-memory write/read/latency/held response')}. Their exact build commands and source hashes are in {L('cpp/verification.json','the C++ verification receipt')}. They do not prove every generated adapter was separately compiled.

## Performance validation boundary

The phase-cost estimator and the connected numerical RTL are separate models. The former has two new workload predictions within 5%; the latter has numerical correctness and synthetic cycle timing. Preserve this distinction in plots, MIP objective comparisons and reported errors.

The synthetic backing gateway is much narrower than physical full-chip bandwidth. Numerical correctness is still meaningful, but its runtime cannot be scaled to the 170-SM GPU merely by multiplying the number of SMs. Timing calibration must preserve service demand, concurrency and dependency ownership together.

## Change procedure

When a test changes a meaningful parameter, update its evidence record, consuming implementation and chapter together. Rebuild the affected helper and one relevant connected numerical case. Compare hardware runtime only when the change is intended to affect physical prediction. Stop investigating a private detail when provisional behavior is adequate for the end-to-end optimization decision.
''')
(R/'cpp/README.md').write_text(f'''# C++ execution of the behavioral model

{L('rtl_microarchitecture_spec.md','Hardware manual')} · {L('manual/integration_and_verification.md','Integration contracts')}

## What this implementation provides

Verilator translates the linked SystemVerilog into C++. The adapters expose the generated ports and one consistent clock operation. This provides native C++ execution while retaining one behavioral specification. It is not yet an independent event-driven simulator, and no simulator speedup has been measured.

Every generated adapter header refers to its matching generated model header. Generate that header from the linked source before including the adapter. Packages supply definitions and do not have standalone clock adapters. Arrays and ports remain the generated model's types.

## Clocked API

{L('cpp/component_model.hpp')} provides the following interface:

| Operation | Behavior |
|---|---|
| `ports()` | Access the generated component's typed input/output ports |
| `settle()` | Evaluate without advancing a clock edge |
| `tick()` | Evaluate low, advance time, evaluate rising edge, advance time, evaluate low; increment model-cycle count |
| `reset()` | Assert synchronous reset for one tick, deassert, settle, reset the host-visible cycle count |
| `cycles()` | Read the host-visible count of ticks since reset |

Set inputs and settle before inspecting combinational readiness. Acceptance occurs only on the next rising edge with valid and ready. Inspect settled outputs after a tick. The generated component may count internal cycles using its own state; the host counter does not override that state.

Combinational helpers use `CombinationalModel` and `evaluate()`, with no reset or clock count. Generated Verilator time increments are host simulation steps, not a claimed physical clock period.

## Reproduce the two smoke checks

From the RTL directory:

```sh
python cpp/build_and_verify.py
```

{L('cpp/build_and_verify.py','The builder')} requires the installed Verilator and C++ compiler. It uses two parallel compile jobs, generates per-test build directories, and writes {L('cpp/verification.json','a verification receipt')}. The checks exercise a two-entry queue with four-cycle delay and a shared-memory helper with three-cycle delay. These are test configurations, not GPU parameters.

Expected terminal results are `CPP_QUEUE_PASS` and `CPP_SHARED_PASS`. The receipt captures exact source hashes and commands. Process wall time includes startup and is not a throughput benchmark.

## Integrating the complete hierarchy

Use the dependency list in {L('numerical/verify_resident_gemm_multi_sm_nb_l2.py','the existing connected-grid verifier')} to generate the full top. A C++ host must service its backing read and store ports with the same ownership and numerical memory semantics as the test harness. The current top adapter alone does not supply that external memory service.

An independent C++ event model may later skip idle cycles, but it must preserve simultaneous-edge ordering, finite ownership and held responses. Compare output values and event/cycle traces against the Verilog before using it to score optimization candidates.
''')
p=R/'hardware_manual_structure.md';s=p.read_text();s=s.replace('## Part I. System specification','## Chapter 00. Whole-GPU overview\n\nExplain the complete GPU organization, key design features, one GEMM tile’s journey, a whole-system diagram and an SM microarchitecture diagram. Distinguish documented hardware organization from the smaller connected reconstruction. Link this chapter from the system specification.\n\n## Part I. System specification');p.write_text(s)
print('Wrote chapter 00, system index, integration chapter and C++ API manual.')
