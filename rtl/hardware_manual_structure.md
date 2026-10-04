# Structure of the RTX 5090 microarchitecture development manual

The manual answers one question: what component behavior, resource limits, and timing rules must a kernel optimizer represent to make useful decisions on an RTX 5090? The model is a behavioral reconstruction for the tested GEMM path. Its specification must be concrete enough to implement, while distinguishing measured GPU behavior from provisional choices.

The organization follows the existing [XiangShan and Intel-inspired template](hardware_development_manual_template.md). XiangShan supplies the module, storage, pipeline, and interface organization; Intel supplies precise operation semantics and ordering conventions. Their CPU-specific structures and constants are not GPU evidence.

## Chapter 00. Whole-GPU overview

Explain the complete GPU organization, key design features, one GEMM tile’s journey, a whole-system diagram and an SM microarchitecture diagram. Distinguish documented hardware organization from the smaller connected reconstruction. Link this chapter from the system specification.

## Part I. System specification

1. **Purpose and supported execution domain.** Research objective, supported kernel and instruction families, numerical behavior, excluded operations, and the distinction between the reconstruction and the physical GPU.
2. **Quantitative configuration.** One parameter table with definitions, values, units, scope, evidence, and provisional alternatives. Separate fixed hardware limits from workload dimensions and implementation settings.
3. **Time and interface conventions.** Clock edge, reset, cycle counting, request acceptance, completion, backpressure, transaction identity, ordering, simultaneous-event priority, and ownership of shared resources.
4. **Component hierarchy and connection map.** A diagram and a connection table showing the data and control paths, the owner of each reservation and completion, and existing versus intended connections.

## Part II. Component chapters

| Chapter | Hardware function | Main implementation responsibility |
|---|---|---|
| 01 | Work distribution and block admission | Assign tiles and reserve resident resources atomically |
| 02 | Warp state and instruction supply | Maintain program position, active lanes, and barrier state |
| 03 | Scheduling and instruction issue | Select eligible instructions and reserve receivers |
| 04 | Registers, readiness, and operand collection | Store values and deliver only completed operands |
| 05 | Scalar and address execution | Compute supported control/address results and return them |
| 06 | Matrix operands and tensor execution | Map lane operands and perform ordered accumulator updates |
| 07 | Load/store execution | Coalesce lane requests, track transactions, and assemble results |
| 08 | Address translation | Map virtual addresses and account for translation service |
| 09 | Shared-memory service | Store words, split requests, broadcast, and arbitrate banks |
| 10 | L1 cache and shared partition | Define local capacity, cache behavior, and configuration |
| 11 | L2 cache and refill ownership | Lookup sectors, merge consumers, and retain pending fetches |
| 12 | Backing memory and response transport | Service numerical reads/writes and return tagged completions |
| 13 | Barriers and retirement | Enforce participant ordering and wait for required output stores |
| 14 | Clocks, event transport, and observation | Advance time consistently and report execution measurements |

### The contract repeated in every chapter

Each chapter uses the following order. An intended interface is marked separately from a port that exists in code.

1. **Purpose and boundary:** responsibility, parent, upstream/downstream components, and supported operations.
2. **Quantitative parameters:** name, definition, value or range, units, legal configurations, evidence, and which implementation consumes the value.
3. **Interfaces:** signal or C++ field, direction, width/type, meaning, request/response handshake, transaction identity, and ordering.
4. **State and storage:** arrays, queues, counters, tags, masks, ownership, and reset behavior.
5. **Functional behavior:** admission, state transitions, numerical transformation, completion, and resource release.
6. **Timing and arbitration:** result availability, acceptance interval, capacity, conflicts, backpressure, and same-edge behavior. Include a short cycle example where the ordering matters.
7. **Invariants and failure handling:** conservation, bounds, stale returns, unsupported requests, and deadlock handling.
8. **Implementations:** links to separate SystemVerilog files and C++ adapters/models, dependency files, parameter bindings, and implementation coverage. Code listings stay in their source files.
9. **Verification and evidence:** actual tests and expected results, numerical/protocol/timing comparisons, one relevant benchmark or source per provisional value, and counterexamples.
10. **Optimization meaning and remaining work:** decisions and constraints implied by the component, approximations required, and gaps that could change a runtime estimate or solver choice.

## Part III. Integration and simulator development

1. A complete transaction walk from global input values to acknowledged output stores.
2. The supported connected module hierarchy and parameter bindings.
3. The C++ simulator API, clock/update semantics, and reproducible build commands.
4. Numerical and protocol tests, cross-implementation comparison, and GPU runtime validation.
5. Execution speed measurements and any event-skipping optimization, with the conditions that preserve cycle behavior.
6. Translation of supported resources, dependencies, and timing costs into the MIP. Report solver size and time separately from model error.

## Part IV. Evidence and development record

Maintain a compact experiment-to-model change table, source provenance, rejected explanations, configuration alternatives, and remaining consequential gaps. Link raw measurements and old editions instead of repeating every historical code listing in the main manual.

## Source and implementation policy

SystemVerilog modules live in individual source files. Existing multi-module bundles remain available as legacy compatibility sources while separately named files are checked against them. The manual links the module used by the stated implementation, including any required helper modules.

C++ initially executes Verilator-generated versions of the same SystemVerilog, through small component adapters. This preserves the clocked behavior without maintaining a second handwritten copy of every state machine. Generated C++ is produced by the build; the adapter and build script are source-controlled files. A later independent event-driven C++ implementation must state its equivalence boundary and pass numerical and timing comparisons before replacing this path.

The documentation is written in this order: define this structure, establish the system contract, fill every component chapter, then check integration, code links, evidence, and build instructions. A complete manual does not imply that every intended hardware mechanism is already implemented.
