# Hardware development manual template

This template specifies a clocked behavioral hardware model. It follows the module, storage, pipeline and interface organization of the supplied XiangShan manual, and the explicit operation semantics of the supplied Intel manual. A completed manual must explain what the model implements and what the target hardware evidence actually establishes.

## 1. Purpose, scope, and build status

State the hardware question, supported workloads, modeled device, implementation language, executable entry point and present integration status. Distinguish numerical functionality, protocol correctness and timing accuracy. Identify separate prototypes so their verification is not attributed to the current implementation.

### 1.1 Reference-manual conventions

Name the format references and the sections examined. State which conventions were adopted. Keep reference-device facts separate from target-device measurements.

## 2. Quantitative configuration and evidence classes

Give device-wide and per-component capacities before behavioral details. Define units and the clock domain for every timing quantity.

| Property | Value and unit | Measurement/configuration context | Evidence location | Classification |
|---|---|---|---|---|
| Named resource | Measured value, documented value, or unknown | Device/version, operation and concurrency | Exact source or saved experiment | Documented, queried, measured, inferred, baseline, or unknown |

A baseline is a simulation choice. An inferred value follows from stated assumptions. Neither is a measured physical fact. Distinguish latency, acceptance interval and outstanding capacity: they describe different limits. Compound benchmark durations must retain their measurement boundaries.

## 3. System interfaces and integration plan

### 3.1 Common clock and transfer convention

Define clock domains, reset polarity and sampling edge; request acceptance; response completion and retirement; payload stability under stalls; simultaneous-event priority; and cycle-count convention.

### 3.2 Intended data/control connections

Provide a block diagram. Label existing and planned connections. Name the component that owns each completion event and prevent counting its delay twice.

### 3.3 Integrator-owned obligations

For each connection, state data identity, resource reservation, dependency update and completion obligations. Explain absent interfaces that block integration.

### 3.4 Submodule hierarchy and resource ownership

List parents, children, stored state and shared resources. Identify missing modules explicitly.

## 4. Component reference

Repeat the following contract for **every component**, including unimplemented components. For an unimplemented component, supply the intended contract and mark its behavioral implementation absent rather than presenting invented target hardware.

### 4.N Component name

**Role.** Explain the hardware function, upstream/downstream connections and supported operations.

**Quantitative configuration.** Describe capacity, widths, service rate and timing domain.

**Design specification and parameter restrictions.**

| Field | Implemented default / physical value | Unit | Legal range or restriction | Evidence class and source |
|---|---|---|---|---|
| Parameter | Explicit value or unknown | Bits, entries, bytes, or cycles | Positive bound, alignment, supported configuration | Baseline or target evidence |

**Ports and interface protocol.**

| Signal | Direction and width | Meaning and handshake rule |
|---|---|---|
| Named port | Input/output, exact bits | Payload validity, acceptance and retention |

**Stored state and internal storage organization.**

| Array/register | Entries × width | Ownership and purpose | Reset value |
|---|---|---|---|
| Named state | Exact organization | What is remembered | Defined reset, invalid, or unspecified |

**Reset and cycle transitions.** Specify the update at each accepted event, simultaneous-event ordering, full/empty behavior and stalled response behavior. Explain whether outputs are combinational or registered.

**Operation lifecycle.** For a multi-stage or queued operation, describe allocation, waiting, execution, response and release. A descriptive phase must not be mistaken for an implemented state register.

| Phase | Trigger | State update / output | Next phase |
|---|---|---|---|
| Named phase | Exact condition | Explicit transfer | Next condition |

**Timing and contention.** Describe earliest response, acceptance interval, outstanding limits, arbitration, head-of-line blocking and dependencies. Include an edge-by-edge example where event ordering is consequential. Mark unknown physical timing separately from implemented timing.

**Invariants and failure handling.** Define conservation, capacity bounds, legal indices, unique completion and invalid-request behavior. State which conditions code enforces and which the caller must enforce.

**Linked behavioral implementations.** Put each Verilog/SystemVerilog module in a separately named source file and link it from the chapter. Link the corresponding C++ adapter or model and its build dependencies. State whether C++ is generated from the same RTL or independently implemented. Specify the input/output and update-order equivalence expected between them. Keep full code in the source files, rather than inline listings in the manual. If numerical computation is absent, identify token-only behavior. State whether the RTL is simulation-only or synthesis-qualified.

**Verification expectations.** Give expected outputs, boundary/stall tests, tests actually run and tests still missing. Distinguish module verification from target-device timing validation.

**Missing physical parameters.** Name unknown capacities, timing, policies or structural rules. Explain the consequence of each unknown; do not silently substitute demonstration values.

## 5. Build and verification procedure

Provide reproducible local build and execution instructions, tool version when recorded, expected results and test coverage. Include interface timing examples and minimum integration checks. Report warnings and untested paths honestly.

## 6. Operation semantics and unsupported behavior

For each operation, specify required inputs/state, affected state, completion/ordering and unsupported forms. Include data widths, address interpretation and invalid behavior. Distinguish modeled faults from target-device exceptions.

## 7. Configuration admission and development limits

Summarize missing hardware properties, remaining implementation work and the conditions needed before claiming predictive accuracy. Tie each meaningful experiment to the property it constrains and the model change it justifies. Record rejected explanations. State whether new experiments are authorized.

## Appendix A. Reference-format provenance

List references, inspected sections and adopted format conventions. State the reading scope. Target hardware facts require target evidence, even when the reference supplies an attractive example.

## Appendix B. Template compliance and evidence navigation

Map template sections to the completed manual, source code, evidence and verification receipts. Any absent component or unknown physical property must remain visible.

Before delivery, read the manual without chat context. Verify definitions, units, quantitative claims, code/source agreement and honest separation of implemented behavior from physical inference. A complete document structure does not establish a complete target-device model.
