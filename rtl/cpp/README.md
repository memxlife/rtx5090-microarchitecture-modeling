# C++ execution of the behavioral model

[Hardware manual](../rtl_microarchitecture_spec.md) · [Integration contracts](../manual/integration_and_verification.md)

## What this implementation provides

Verilator translates the linked SystemVerilog into C++. The adapters expose the generated ports and one consistent clock operation. This provides native C++ execution while retaining one behavioral specification. It is not yet an independent event-driven simulator, and no simulator speedup has been measured.

Every generated adapter header refers to its matching generated model header. Generate that header from the linked source before including the adapter. Packages supply definitions and do not have standalone clock adapters. Arrays and ports remain the generated model's types.

## Clocked API

[component_model.hpp](component_model.hpp) provides the following interface:

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

[The builder](build_and_verify.py) requires the installed Verilator and C++ compiler. It uses two parallel compile jobs, generates per-test build directories, and writes [a verification receipt](verification.json). The checks exercise a two-entry queue with four-cycle delay and a shared-memory helper with three-cycle delay. These are test configurations, not GPU parameters.

Expected terminal results are `CPP_QUEUE_PASS` and `CPP_SHARED_PASS`. The receipt captures exact source hashes and commands. Process wall time includes startup and is not a throughput benchmark.

## Integrating the complete hierarchy

Use the dependency list in [the existing connected-grid verifier](../numerical/verify_resident_gemm_multi_sm_nb_l2.py) to generate the full top. A C++ host must service its backing read and store ports with the same ownership and numerical memory semantics as the test harness. The current top adapter alone does not supply that external memory service.

An independent C++ event model may later skip idle cycles, but it must preserve simultaneous-edge ordering, finite ownership and held responses. Compare output values and event/cycle traces against the Verilog before using it to score optimization candidates.
