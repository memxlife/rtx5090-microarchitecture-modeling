# Hardware development manual: parameterized GPU timing components

[Complete parameter table: definitions, values, evidence and difficulty](parameter_master_table.md)

The [complete provisional parameter profile](provisional_parameters.md) now supplies baselines for all 134 fields. Physical evidence still identifies only 8 fully, supports 32 partially, and leaves 94 unidentified. The configuration exporter currently connects five profile fields to executable parameters; 129 remain unwired. Full profile coverage is distinct from implementation coverage. Its 118 assumption-bearing entries are executable development choices, not calibrated RTX 5090 facts.

## 1. Purpose, scope, and build status

This manual follows the [hardware development manual template](hardware_development_manual_template.md). Use this manual to implement and inspect a clocked hardware model of the studied GEMM execution path. It specifies signal contracts, quantitative configuration, stored state, acceptance rules, cycle transitions, inline SystemVerilog, integration obligations, and verification expectations.

The library is a **structural modeling baseline**, not recovered NVIDIA RTL. It supplies fourteen original module definitions, a completion-driven register file and a numerical matrix pipeline. Six behavior categories have been exercised in the original component testbench. Eight additional cases verify a connected register/completion path. The modules are not yet connected into a complete GPU; full-kernel numerical execution and several memory functions are missing. The numerical subsystem now connects clocked shared storage through measured native operand maps to BF16/FP32 matrix arithmetic; 18,432 output checks cover two storage capacities. Global memory, native instruction scheduling and full-kernel retirement remain unconnected. This manual does not claim that a complete RTX 5090 has been implemented.

SystemVerilog is used for typed ports and clocked processes. The examples contain simulation checks and are not qualified as a synthesizable design. The authoritative sources are [hardware_blocks.sv](components/hardware_blocks.sv) , [completion_register_file.sv](components/completion_register_file.sv), and [numerical_matrix_pipeline.sv](numerical/numerical_matrix_pipeline.sv); the inline implementations below match them exactly. The earlier [monolithic timing prototype](gpu_timing.sv) is a separate executable and must not be confused with this library.

### 1.1 Reference-manual conventions

This edition adopts the module-documentation organization of the XiangShan Kunminghu design manual: module hierarchy, quantitative design specifications, parameter restrictions, internal arrays, functional subsections, pipeline/interface timing, and transaction lifecycles. It adopts Intel SDM conventions for explicit operation semantics, supported operand forms, affected state, and invalid-operation behavior. The attached Intel document primarily specifies software-visible architecture; it does not supply RTL or a universal cycle-latency specification.

The reference review covered XiangShan instruction-cache, issue-queue, LSU/data-cache, and L2/MSHR sections, and Intel instruction-description, ADD/MOV semantics, memory-ordering, and cache-control sections. CPU organizations and constants are format references only. They are not evidence for RTX 5090 resources or scheduling.

Use the tables below as design contracts. “Baseline” means an explicit implementation assumption. “Queried” means a recorded runtime/device value. “Unknown” is a missing physical quantity, not permission to use the baseline as a hardware measurement. An operation that the model cannot represent must remain outside its supported domain.

## 2. Quantitative configuration and evidence classes

| Field | Value | How to use it |
|---|---:|---|
| Device SM count | 170 | Recorded device fact; multi-SM distributor remains unimplemented |
| Register words/SM | 65,536 × 32 bits | Saved query; 256-word per-warp allocation quantum is implemented in Section 4.17 |
| Shared capacity/SM | 102,400 bytes | Saved runtime allocation context |
| Opt-in shared bytes/block | 101,376 | Saved query; also check verified launch context |
| L2 capacity | 96 MiB | Recorded device fact; not instantiated by the 1 KiB demo cache |
| Warp width | 32 threads | Lane trace must retain this structure |
| Tested block width | 128 threads = 4 warps | Prototype and component examples |
| Observed resident blocks/SM | 11 smaller-tile; 8 larger-tile | Bounds for tested compiled kernels, not arbitrary register requirements |
| Shared bank mapping | 32 banks, 4-byte words | Supported tested ordinary-word accesses |
| Reference frequency | 2.94 GHz | Reporting units only; 0.340136 ns/reference cycle |

[The numerical evidence tables](quantitative_microarchitecture.md) give compound response costs and measured service rates. Three evidence classes must remain distinct: queried/documented capacities, effective experimental costs with their measurement boundaries, and uncalibrated module defaults. In particular, a code default of one-cycle latency is not an RTX measurement.

No hardware default is inferred from a compound duration. The approximately 399-cycle cached four-load response includes stores, address work and scheduling; it cannot be copied into a single L2 lookup delay. Unknown queues, policies and clocks remain explicit configuration/identification work.

## 3. System interfaces and integration plan

### 3.1 Common clock and transfer convention

All modules use `clk` and synchronous active-high `rst`. Assert reset across at least one rising edge. Inputs are sampled at rising edges; registered outputs update afterward. The component testbench changes stimulus on falling edges to avoid races.

A request is accepted only when valid and ready are both asserted at the rising edge. Keep its payload stable while valid is asserted and ready is low. A response is retired only under the corresponding response handshake. Payload outputs when response-valid is low are not meaningful.

For the timing queue, LATENCY counts edge intervals from accepted request to the earliest permitted response handshake. INTERVAL limits accepted request edges, independently of response latency. A full queue does not exploit simultaneous retirement to accept a replacement at the same edge. This conservative rule is an implementation choice and must be included when interpreting throughput.

For shared/cache countdown models, the registered response becomes eligible before its handshake edge. For the barrier, release is a registered pulse; a connected warp_context samples that pulse at the following edge. Include that wiring delay in an integration timing check rather than assuming release and resume occur combinationally.

### 3.2 Intended data/control connections

The intended integration, not an existing wired top, follows this structure:

```text
block dispatch -> block_allocator -> warp_context instances
                                      |
register_scoreboard -> eligibility -> warp_scheduler
                                      |
                  accepted operation + destination identity
                   /                  |                  \
          ALU / operand pipe      matrix pipe       load/store queue
                   \                  |                  |
                    result completions          translation / cache
                                      |                  |
                              register readiness   controller returns
                                      |
                         shared bank requests and values
                                      |
                           block barrier / buffer reuse
                                      |
                         output stores -> completion_tracker
                                      |
                          allocator retirement / grid completion
```

Readiness feedback must name the operation and destination version it completes. The original scoreboard predicts deterministic availability; it must not control variable-latency memory readiness. Section 4.15 adds a completion-driven register file that stores actual returned values and requires a matching reservation identity. Its connected test exercises delayed returns, but the complete GPU wiring and return arbitration are still absent.

The blocking read_cache internally prices its miss and does not expose an external miss port. Do not connect a memory_controller downstream and add its delay a second time. An integrated hierarchy requires a cache miss interface, pending records, and return handling. Those are implementation requirements, not hidden in the diagram.

### 3.3 Integrator-owned obligations

| Connection | Required obligation |
|---|---|
| Allocation to warp admission | Atomically reserve rounded register/shared/thread capacity and remember the block slot |
| Trace to eligibility | Supply true source/destination dependencies and legal register indices |
| Scheduler to execution | Admit only when all required resources and receiver queues accept |
| Execution/memory to scoreboard | Return correct destination/version exactly once; replace deterministic timing for variable responses |
| Lane addresses to transactions | Preserve active masks, byte coverage, bank conflicts and request consumers |
| Shared stores to protected loads | Update actual stored words and respect write completion/barrier ordering |
| Cache to controller | Add miss request/return interfaces; conserve every completion obligation |
| Output stores to block retirement | Keep allocations until required outputs complete |

There is no complete top-level interconnect in the library today. These obligations define what an implementer must add; they must not be reported as verified behavior.

### 3.4 Submodule hierarchy and resource ownership

| Parent function | Library submodules | Owned storage or resource | Required but absent submodules |
|---|---|---|---|
| SM admission | block_allocator, warp_context | Resident-slot reservations and per-warp position | Grid dispatcher and private placement rules; Section 4.18 supplies rounded aggregate admission |
| Issue and readiness | warp_scheduler, register_scoreboard, completion_register_file | Issue cursor and destination availability | Scheduler partitions, operand collector, complete warp-wide wakeup wiring |
| Arithmetic service | execution_pipeline instances | Outstanding operation identities and service spacing | Complete native decode, numerical ALU and writeback arbitration; matrix values are implemented separately |
| Memory execution | transaction_queue, address_translation | Outstanding identities and address delay | Lane coalescer, request masks, load assembly, store completion |
| Shared storage | shared_memory_bank instances | Stored 32-bit words and pending response | Bank decoder, multi-lane transaction splitter, L1/shared partition |
| Cache service | read_cache instances | Tags, recency and blocking-response state | Sector validity per line, pending-miss consumers, external refill/writeback |
| Device memory | memory_controller | Timed FIFO request identities | GDDR7 channels, commands, numerical data and clock crossing |
| Synchronization/retirement | barrier_controller, completion_tracker | Arrival mask, release countdown, completion flag | Output-store acknowledgments and complete block/grid wiring |

Ownership matters: a miss may hold one cache transaction record and one controller record, but its elapsed delay must not be charged independently twice. Data availability must be driven by the actual owning completion event when variable-latency resources are integrated.

## 4. Component reference

Every subsection uses the same order: role and quantitative configuration, ports, stored state, reset/cycle rules, invariants, inline code, and verification expectations. Inputs of type `int` are signed 32-bit simulation fields; identifiers and counts must be supplied within their documented ranges. Callers must validate register indices and use positive bounded capacities and delays. The modules do not yet enforce every such precondition internally.

In each component, the parameter table separates implemented settings from missing physical values. Reset and transition rules, lifecycle tables where applicable, and the complete inline module define the implemented cycle behavior. Section 5.3 works through interface timing at individual clock edges. The linked quantitative specification supplies measured costs; it does not turn library defaults into physical delays.

### 4.1. Shared timing and completion queue

**Role.** Stores accepted operation identities and their due cycles. It admits requests only when there is an unused slot and the initiation interval has expired. It retains a completed response until its receiver accepts it. Results retire in FIFO order; variable-latency out-of-order returns require a different completion structure.

**Quantitative configuration.** `SLOTS`: outstanding operations; `LATENCY`: cycles from acceptance to modeled completion; `INTERVAL`: cycles between acceptances. All must be positive. Default values are engineering test settings, not RTX parameters.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| SLOTS | 4 | entries | Positive | Baseline; hardware depth unknown |
| LATENCY | 1 | cycles | Positive | Baseline; resource-specific delay unknown |
| INTERVAL | 1 | cycles/acceptance | Positive | Baseline; measured service depends on operation class |
| req_id/rsp_id | 32 | bits | Caller assigns unique outstanding identities | Interface choice |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| req_valid / req_ready | input / output | Request present / receiver permits acceptance. |
| req_id | input, 32 bits | Operation or transaction identity retained until return. |
| rsp_valid / rsp_ready | output / input | Completed response present / consumer permits retirement. |
| rsp_id | output, 32 bits | Identity of the completed operation or transaction. |

**Interface protocol.** Request and response handshake; payload is an operation identity, not a numerical result.

**Stored state.** cycle, count, head, tail, next_accept; per-slot identity and due time.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| ids | SLOTS × 32 bits | Accepted identities |
| due | SLOTS × signed 32 bits | Due cycle of each identity |
| head/tail/count/next_accept | Signed 32-bit fields | FIFO and service admission |

**Reset and cycle transitions.** Reset clears count, pointers, cycle and initiation state. Empty queues ignore payload storage. An accepted request sets its slot due time to the acceptance cycle plus LATENCY. A held response remains stable until accepted.

**Invariants and failure handling.** 0 <= count <= SLOTS. Each accepted identity returns once, in acceptance order. A full queue does not accept a request even if a response will retire at the same edge.

**Operation lifecycle.** These state names summarize the register implementation; they are not additional RTL registers.

| Phase | Trigger | Update/output | Next phase |
|---|---|---|---|
| RESET | rst | Clear ownership count, pointers and service cycle | EMPTY |
| READY | valid && ready | Record identity/due time; increment occupancy | ACTIVE |
| ACTIVE | head due but rsp_ready=0 | Hold valid and identity | RESPONSE_HELD |
| RESPONSE_HELD | rsp_valid && rsp_ready | Retire head and free one entry | READY/ACTIVE |

**Inline behavioral implementation.**

```systemverilog
module timed_queue #(
  parameter int SLOTS=4, LATENCY=1, INTERVAL=1
)(input logic clk,rst, input logic req_valid, output logic req_ready,
  input logic [31:0] req_id, output logic rsp_valid,input logic rsp_ready,
  output logic [31:0] rsp_id);
  int cycle,count,head,tail,next_accept;
  int due[SLOTS]; logic [31:0] ids[SLOTS];
  wire push=req_valid&&req_ready, pop=rsp_valid&&rsp_ready;
  assign req_ready=(count<SLOTS)&&(cycle>=next_accept);
  assign rsp_valid=(count>0)&&(cycle>=due[head]);
  assign rsp_id=ids[head];
  initial if(SLOTS<1||LATENCY<1||INTERVAL<1) $fatal(1,"Invalid timing queue configuration");
  always_ff @(posedge clk) begin
    if(rst) begin cycle<=0;count<=0;head<=0;tail<=0;next_accept<=0;end
    else begin
      cycle<=cycle+1;
      if(push) begin ids[tail]<=req_id;due[tail]<=cycle+LATENCY;tail<=(tail+1)%SLOTS;next_accept<=cycle+INTERVAL;end
      if(pop) head<=(head+1)%SLOTS;
      case({push,pop}) 2'b10:count<=count+1;2'b01:count<=count-1;default:count<=count;endcase
    end
  end
endmodule
```

**Verification expectation.** Test queue capacity, return ordering, and response stability with rsp_ready held low. These cases passed in components_tb.

**Unimplemented or unidentified.** Actual per-resource queue capacities and initiation/return limits are unknown. This queue is used by the simple pipeline and controller wrappers below.

### 4.2. Block resource allocator

**Role.** Records register and shared allocations for each admitted block. Combinational logic calculates free capacity and selects a free slot. Admission reserves both resources; valid retirement releases the corresponding allocation. Admission and retirement do not reuse the same occupied slot in one cycle.

**Quantitative configuration.** Queried capacity is 65,536 register words and 102,400 shared bytes per SM. The configurable block slots default to four solely for this component test model. Original GEMM occupancy was eleven smaller-tile or eight larger-tile blocks per SM.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| SLOTS | 4 | resident slots | Positive; admission needs a free slot | Baseline; tested occupancy is 11/8 |
| REG_WORDS | 65,536 | 32-bit words | Accepted total cannot exceed capacity | Queried |
| SHARED_BYTES | 102,400 | bytes | Accepted total cannot exceed capacity | Queried allocation context |
| Allocation granularity | Unknown | words/bytes | Must be supplied before physical capacity prediction | Unidentified |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| admit_valid / admit_ready | input / output | Admission request / allocator has sufficient capacity. |
| registers_needed, shared_needed | input, signed 32-bit counts | Allocation demand, in register words and bytes respectively. |
| admitted_slot, resident_blocks | output, signed 32-bit counts | Chosen slot identifier and current allocation count. |
| retire_valid, retire_slot | input | Release pulse and previously allocated slot identity. |

**Interface protocol.** On accepted admission the caller captures admitted_slot; it must supply that slot for exactly one later retirement.

**Stored state.** Per-slot busy bit, register allocation and shared allocation. Free totals and first free slot are combinational.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| busy | SLOTS bits | Allocation ownership |
| reg_alloc / sh_alloc | SLOTS × signed 32 bits each | Per-slot resource reservations |

**Reset and cycle transitions.** Reset frees every slot. A retirement clears its busy bit; accepted admission sets a previously free slot and records its demands. Retirement does not make that slot available combinationally during the same tick.

**Invariants and failure handling.** Resource totals remain within capacities for accepted nonnegative demands. Retirement of an invalid or free slot terminates simulation.

**Inline behavioral implementation.**

```systemverilog
module block_allocator #(
 parameter int SLOTS=4, REG_WORDS=65536, SHARED_BYTES=102400
)(input logic clk,rst, input logic admit_valid,output logic admit_ready,
 input int registers_needed,shared_needed, output int admitted_slot,
 input logic retire_valid,input int retire_slot,output int resident_blocks);
 logic busy[SLOTS]; int reg_alloc[SLOTS],sh_alloc[SLOTS]; int free_regs,free_shared,slot;
 always_comb begin
  free_regs=REG_WORDS;free_shared=SHARED_BYTES;resident_blocks=0;slot=-1;
  for(int i=0;i<SLOTS;i++) begin
   if(busy[i]) begin free_regs-=reg_alloc[i];free_shared-=sh_alloc[i];resident_blocks++;end
   else if(slot<0) slot=i;
  end
  admitted_slot=slot;
  admit_ready=slot>=0&&registers_needed>=0&&shared_needed>=0&&registers_needed<=free_regs&&shared_needed<=free_shared;
 end
 always_ff @(posedge clk) begin
  if(rst) for(int i=0;i<SLOTS;i++) begin busy[i]<=0;reg_alloc[i]<=0;sh_alloc[i]<=0;end
  else begin
   if(retire_valid) begin
    if(retire_slot<0||retire_slot>=SLOTS) $fatal(1,"Invalid retire slot");
    else if(!busy[retire_slot]) $fatal(1,"Retiring unallocated block");
    else busy[retire_slot]<=0;
   end
   if(admit_valid&&admit_ready) begin busy[slot]<=1;reg_alloc[slot]<=registers_needed;sh_alloc[slot]<=shared_needed;end
  end
 end
endmodule
```

**Verification expectation.** Add tests for capacity rejection, exact allocation/release, simultaneous distinct-slot admit/retire, and invalid retire. Not behaviorally tested yet.

**Unimplemented or unidentified.** Thread/warp limits, allocation rounding, real dispatch policy, and multi-SM placement are missing. The supplied allocation requirements must already include supported rounding.

### 4.3. Warp instruction context

**Role.** Stores a program counter and barrier/end state. It advances exactly once for an accepted instruction, stops at a barrier, resumes on release, and stops issuing after end. Instruction storage and decoding are provided by the caller.

**Quantitative configuration.** `DEPTH` is the trace instruction limit, default 256. The test workload has four warps of 32 threads, but this module represents one warp.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| DEPTH | 256 | trace positions | Positive; PC must stay below depth on issue | Baseline |
| pc | 32 | signed bits | Nonnegative legal program position | Interface choice |
| Warp width | 32 | threads | Native lane trace required upstream | Recorded execution structure |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| issue_fire, barrier_instruction, end_instruction | input | Accepted issue pulse and classifications of that instruction. |
| barrier_release | input | Release pulse for this warp’s waiting barrier. |
| pc | output, signed 32-bit index | Index of the next instruction to present. |
| waiting, ended | output, one bit each | Barrier wait and permanent end state. |

**Interface protocol.** issue_fire is the accepted-instruction pulse. The caller must not issue while waiting or ended.

**Stored state.** Program counter, waiting bit, ended bit.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| pc | Signed 32 bits | Next trace instruction |
| waiting / ended | One bit each | Issue inhibition |

**Reset and cycle transitions.** Reset selects instruction zero. Accepted instruction increments the counter; barrier sets waiting and end sets ended. Release clears waiting. The incoming barrier/end classification belongs to that accepted instruction.

**Invariants and failure handling.** Counter advances only on issue_fire. Illegal issue during waiting/end or beyond the configured depth terminates simulation.

**Operation lifecycle.** These state names summarize the register implementation; they are not additional RTL registers.

| Phase | Trigger | Update/output | Next phase |
|---|---|---|---|
| RUN | accepted ordinary instruction | Increment PC | RUN |
| RUN | accepted barrier | Increment PC and set waiting | WAIT_BARRIER |
| WAIT_BARRIER | barrier_release | Clear waiting | RUN |
| RUN | accepted end | Set ended | ENDED |

**Inline behavioral implementation.**

```systemverilog
module warp_context #(parameter int DEPTH=256)(
 input logic clk,rst, input logic issue_fire,barrier_instruction,end_instruction,
 input logic barrier_release, output int pc,output logic waiting,ended);
 always_ff @(posedge clk) begin
  if(rst) begin pc<=0;waiting<=0;ended<=0;end
  else begin
   if(barrier_release) waiting<=0;
   if(issue_fire) begin
    if(waiting||ended||pc>=DEPTH) $fatal(1,"Illegal warp advance");
    pc<=pc+1;
    if(barrier_instruction) waiting<=1;
    if(end_instruction) ended<=1;
   end
  end
 end
endmodule
```

**Verification expectation.** Test stalled counter, barrier wait/release, end, and depth overflow. Not behaviorally tested yet.

**Unimplemented or unidentified.** Fetch/cache delays, divergence, reconvergence, native decoding, and the real instruction trace are missing.

### 4.4. Warp scheduler

**Role.** Scans eligible warps starting at its round-robin cursor. It chooses one candidate, presents its identity, and advances the cursor only when the receiver accepts that candidate. Eligibility must be computed upstream from dependencies and receiver capacity.

**Quantitative configuration.** `WARPS` defaults to four, matching the tested block. The model issues at most one warp instruction each cycle; that is an explicit hypothesis, not an identified hardware issue width.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| WARPS | 4 | candidates | Positive | Tested block width |
| Issue width | 1 | warp instruction/cycle | Receiver must accept selected instruction | Baseline; not recovered hardware width |
| Partition count | 4 | partitions/SM | Instantiate separate scheduler contexts; warp assignment still unknown | Documented RTX whitepaper Figure 5 |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| eligible | input, WARPS bits | One readiness bit per candidate warp. |
| issue_valid / issue_ready | output / input | Selected instruction present / destination accepts issue. |
| issue_warp | output, signed 32-bit index | Index of the selected eligible warp. |

**Interface protocol.** eligible is supplied by the dependency/resource logic. Receiver acceptance authorizes the selected instruction.

**Stored state.** Round-robin cursor; selection is combinational.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| cursor | Signed 32 bits | Next starting candidate |

**Reset and cycle transitions.** Reset sets cursor zero. Scan from the cursor and choose the first eligible warp. Advance cursor only on issue_valid && issue_ready.

**Invariants and failure handling.** Never select an ineligible warp. No issue is valid if eligibility is empty. Cursor is stable during nonacceptance.

**Inline behavioral implementation.**

```systemverilog
module warp_scheduler #(parameter int WARPS=4)(
 input logic clk,rst,input logic [WARPS-1:0] eligible,
 output logic issue_valid,input logic issue_ready,output int issue_warp);
 int cursor;
 always_comb begin
  issue_valid=0;issue_warp=0;
  for(int k=0;k<WARPS;k++) begin
   if(!issue_valid&&eligible[(cursor+k)%WARPS]) begin issue_valid=1;issue_warp=(cursor+k)%WARPS;end
  end
 end
 always_ff @(posedge clk) begin
  if(rst) cursor<=0;
  else if(issue_valid&&issue_ready) cursor<=(issue_warp+1)%WARPS;
 end
endmodule
```

**Verification expectation.** Selection begins at warp zero, then rotates to warp one; holding issue_ready low preserves the cursor. Passed.

**Unimplemented or unidentified.** Four architectural scheduler partitions are documented. Warp assignment, multiple-issue rules, class-specific routing and arbitration policy remain unknown. This single-instance module does not yet implement the four-partition SM.

### 4.5. Register readiness scoreboard

**Role.** Maintains when each register identity becomes available. Two optional source checks determine operand readiness. A destination cannot be overwritten while a previous write is pending. Accepted issue reserves its destination until the supplied result delay expires.

**Quantitative configuration.** `REGS` defaults to 64 abstract identities per modeled warp. Register zero starts ready. Queried physical storage is 65,536 32-bit words per SM; the abstract identity count does not model that capacity.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| REGS | 64 | register identities | Source/destination indices in range | Baseline, not physical storage capacity |
| result_delay | Runtime input | cycles | Positive deterministic delay only | Operation-specific hardware value unknown |
| Initially defined register | 0 | register index | Other values require explicit producers | Test initialization convention |
| Register bank/port counts | Unknown | banks/ports | Needed for operand collection | Unidentified |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| source_a, source_b, destination | input, register indices | Register identities queried or reserved. |
| use_a, use_b, write_destination | input, flags | Enable source checks and destination reservation. |
| operands_ready, destination_free | output, flags | Sources available and no conflicting unfinished destination write. |
| issue_fire, result_delay | input | Accepted issue pulse and configured destination-availability delay in cycles. |

**Interface protocol.** Use valid in-range indices. result_delay is positive and deterministic for the accepted operation; the module cannot ingest a variable-latency completion event.

**Stored state.** Cycle counter, defined bit and availability cycle per register identity.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| defined | REGS bits | Whether a producer exists |
| available_at | REGS × signed 32 bits | Result readiness cycle |

**Reset and cycle transitions.** Reset marks only register zero defined. Source queries check definition and due time. An accepted writer marks its destination defined but unavailable until cycle + result_delay.

**Invariants and failure handling.** No accepted instruction reads unavailable sources or overwrites an unfinished destination. Such acceptance terminates simulation.

**Inline behavioral implementation.**

```systemverilog
module register_scoreboard #(parameter int REGS=64)(
 input logic clk,rst,input int source_a,source_b,destination,
 input logic use_a,use_b,write_destination,
 output logic operands_ready,destination_free,
 input logic issue_fire,input int result_delay);
 int cycle,available_at[REGS]; logic defined[REGS];
 always_comb begin
  operands_ready=(!use_a||(defined[source_a]&&cycle>=available_at[source_a]))&&
                 (!use_b||(defined[source_b]&&cycle>=available_at[source_b]));
  destination_free=!write_destination||!defined[destination]||cycle>=available_at[destination];
 end
 always_ff @(posedge clk) begin
  if(rst) begin
   cycle<=0;
   for(int r=0;r<REGS;r++) begin defined[r]<=(r==0);available_at[r]<=0;end
  end else begin
   cycle<=cycle+1;
   if(issue_fire) begin
    if(!operands_ready||!destination_free||result_delay<1) $fatal(1,"Illegal register issue");
    if(write_destination) begin defined[destination]<=1;available_at[destination]<=cycle+result_delay;end
   end
  end
 end
endmodule
```

**Verification expectation.** Test dependent versus independent operations and overlapping writes in this module. Not behaviorally tested; related checks exist in the older integrated prototype.

**Unimplemented or unidentified.** Banking, physical register values, ports, operand collection, writeback queues, allocation granularity, and variable-latency completion feedback remain missing. Its timestamp result is valid only for the supplied deterministic delay.

### 4.6. ALU, operand-preparation, and matrix service

**Role.** This module is instantiated separately for each modeled operation class. It delegates admission, outstanding storage, delay, and return backpressure to the explicit timing queue above. Separate instances avoid assuming every instruction uses one resource.

**Quantitative configuration.** `SLOTS`, `LATENCY`, and `INTERVAL` are explicit configuration fields. The corrected register-resident matrix probe measured approximately 64 cycles per operation per warp at four warps and 128 at eight. Those compound costs are not assigned as this module's intrinsic latency.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| SLOTS | 4 | operations | Positive | Baseline |
| LATENCY | 1 | cycles | Positive | Baseline; native result latency unknown |
| INTERVAL | 1 | cycles/acceptance | Positive | Baseline; native service interval unknown |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| req_valid / req_ready | input / output | Request present / receiver permits acceptance. |
| req_id | input, 32 bits | Operation or transaction identity retained until return. |
| rsp_valid / rsp_ready | output / input | Completed response present / consumer permits retirement. |
| rsp_id | output, 32 bits | Identity of the completed operation or transaction. |

**Interface protocol.** Accepted identity is returned after service timing. Instantiate separately for each declared operation class.

**Stored state.** Inherited from timed_queue; this wrapper adds no state.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| Inherited timed_queue arrays | Configured by SLOTS | Operation storage and completion |

**Reset and cycle transitions.** Reset, accept, initiation spacing, due time and retirement follow timed_queue exactly.

**Invariants and failure handling.** Never reinterpret a completion token as computed arithmetic data. Dependencies and operation-class assignment are supplied upstream.

**Inline behavioral implementation.**

```systemverilog
module execution_pipeline #(parameter int SLOTS=4,LATENCY=1,INTERVAL=1)(
 input logic clk,rst,req_valid,output logic req_ready,input logic [31:0] req_id,
 output logic rsp_valid,input logic rsp_ready,output logic [31:0] rsp_id);
 // Instantiate separately for ALU, operand rearrangement, and matrix operations.
 timed_queue #(.SLOTS(SLOTS),.LATENCY(LATENCY),.INTERVAL(INTERVAL)) pipe(.*);
endmodule
```

**Verification expectation.** Verify each configured instance against latency and service expectations. Wrapper is compiled; class-specific behavior is not separately tested.

**Unimplemented or unidentified.** Functional arithmetic is not performed. Native CUDA/Integer/Tensor pipeline counts, instruction semantics, operand routing, and per-instruction delays are unidentified. This module emits timed completion tokens, not numerical matrix outputs.

### 4.7. Load/store outstanding transactions

**Role.** Tracks accepted transaction identities until their timed completion can be returned. It provides finite outstanding capacity and response backpressure. The caller must first construct transactions from actual lane accesses and associate them with parent instructions.

**Quantitative configuration.** `SLOTS`, `LATENCY`, and `INTERVAL` must be supplied for the studied path. Measured response groups of four loads cost 399.426 cached or 1,015.362 cold cycles in one probe, including non-load work.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| SLOTS | 4 | transactions | Positive | Baseline; actual queues unknown |
| LATENCY | 1 | cycles | Positive | Baseline; real completion should use return events |
| INTERVAL | 1 | cycles/acceptance | Positive | Baseline |
| Transaction identity | 32 | bits | Maintain consumer/byte-mask mapping | Interface choice |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| req_valid / req_ready | input / output | Request present / receiver permits acceptance. |
| req_id | input, 32-bit transaction identity | Operation or transaction identity retained until return. |
| rsp_valid / rsp_ready | output / input | Completed response present / consumer permits retirement. |
| rsp_id | output, same identity | Identity of the completed operation or transaction. |

**Interface protocol.** Caller maintains the mapping from transaction identities to their instruction consumers and byte masks.

**Stored state.** Inherited bounded FIFO state.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| Inherited timed_queue arrays | Configured by SLOTS | Transaction storage and completion |

**Reset and cycle transitions.** Reset clears outstanding transactions. Accepted transactions reserve capacity; responses retain their identity until acknowledged.

**Invariants and failure handling.** No silent transaction loss; no acceptance beyond queue capacity. Do not assume one warp instruction equals one transaction.

**Inline behavioral implementation.**

```systemverilog
module transaction_queue #(parameter int SLOTS=4,LATENCY=1,INTERVAL=1)(
 input logic clk,rst,req_valid,output logic req_ready,input logic [31:0] req_id,
 output logic rsp_valid,input logic rsp_ready,output logic [31:0] rsp_id);
 // Capacity and return backpressure; lane coalescing must be supplied upstream.
 timed_queue #(.SLOTS(SLOTS),.LATENCY(LATENCY),.INTERVAL(INTERVAL)) queue(.*);
endmodule
```

**Verification expectation.** Queue primitive capacity and backpressure passed; instruction/transaction assembly is not implemented.

**Unimplemented or unidentified.** Coalescing, store visibility, instruction-to-transaction expansion, actual load/store queue depths, and return assembly are missing. Compound group timings are not hardware queue depths or single-load delays.

### 4.8. Address translation

**Role.** Passes an address through a bounded timing queue. The virtual address is returned unchanged as the physical address. This makes identity translation an explicit baseline assumption.

**Quantitative configuration.** `LATENCY` is configurable; no RTX translation delay has been identified. Four slots and one-cycle initiation are modeling choices in this baseline.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| LATENCY | 1 | cycles | Positive | Baseline; translation timing unknown |
| Queue slots | 4 | addresses | Fixed in wrapper | Baseline |
| Address width | 32 | bits | Upper physical address bits cannot be represented | Interface limitation |
| Mapping | Identity | address rule | Admit only as explicit diagnostic assumption | Not measured translation hardware |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| req_valid / req_ready | input / output | Request present / receiver permits acceptance. |
| virtual_address | input, 32 bits | Untranslated byte address supplied to the baseline. |
| rsp_valid / rsp_ready | output / input | Completed response present / consumer permits retirement. |
| physical_address | output, 32 bits | Returned byte address; identical in this baseline. |

**Interface protocol.** Identity translation is explicitly selected by using this baseline module; addresses must fit the 32-bit interface.

**Stored state.** Four-slot timing queue carrying addresses.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| Inherited timed_queue arrays | Four entries | Identity-mapped address storage |

**Reset and cycle transitions.** After an accepted address, return the same address through the configured timed handshake. There is no TLB or page walk.

**Invariants and failure handling.** The module never changes address bits. It must not be used to claim realistic virtual-to-physical mapping.

**Inline behavioral implementation.**

```systemverilog
module address_translation #(parameter int LATENCY=1)(
 input logic clk,rst,req_valid,output logic req_ready,input logic [31:0] virtual_address,
 output logic rsp_valid,input logic rsp_ready,output logic [31:0] physical_address);
 // Explicit identity-mapping baseline. Not a measured translation cache.
 timed_queue #(.SLOTS(4),.LATENCY(LATENCY),.INTERVAL(1)) translation(
  .clk,.rst,.req_valid,.req_ready,.req_id(virtual_address),.rsp_valid,.rsp_ready,.rsp_id(physical_address));
endmodule
```

**Verification expectation.** Test exact address retention and configured delay. Not behaviorally tested yet.

**Unimplemented or unidentified.** Page size, translation tags/sets/ways, page walks, access permissions, mappings, faults, and translation contention are unimplemented. Use only where identity translation is an admitted diagnostic assumption.

### 4.9. Shared-memory bank

**Role.** Contains actual 32-bit storage words. It accepts a read or write only while idle. A write updates the selected word; a read returns its stored value. Both produce a delayed response, retained until acknowledged. A caller must route each decoded bank request to the appropriate bank instance.

**Quantitative configuration.** `WORDS` is storage per modeled bank and `LATENCY` is response delay. The verified mapping uses 32 banks and four-byte words. Original kernels require 8,192 or 11,264 source-level shared bytes per block; capacity allocation is handled separately.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| WORDS | 64 | 32-bit words/bank | Positive; word index in range | Baseline |
| LATENCY | 1 | cycles | Positive | Baseline; intrinsic shared latency unknown |
| Storage at default | 256 | bytes/bank | WORDS × 4 | Derived baseline |
| Outstanding per bank | 1 | operation | Wait for prior response retirement | Baseline; not measured port capacity |
| Target bank mapping | 32 / 4 | banks / bytes per word | Decode full lane requests upstream | Supported tested ordinary-word mapping |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| req_valid / req_ready | input / output | Request present / receiver permits acceptance. |
| write | input, one bit | One selects write; zero selects read. |
| word_address | input, signed 32-bit index | Local word index within this selected bank. |
| write_data | input, 32 bits | Word to store for a write request. |
| rsp_valid / rsp_ready | output / input | Completed response present / consumer permits retirement. |
| read_data | output, 32 bits | Stored/read response word; meaningful only when response-valid. |

**Interface protocol.** Caller selects a bank and supplies its local word index. For a byte address in the 32-bank baseline, bank = floor(address/4) modulo 32 and local word = floor(address/128). Decode and conflict splitting are upstream.

**Stored state.** WORDS × 32-bit storage; occupied bit, delay countdown and registered response data.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| storage | WORDS × 32 bits | Actual stored words |
| occupied / remaining / read_data | 1 / signed 32 / 32 bits | Response ownership, delay and payload |

**Reset and cycle transitions.** Reset zeroes storage for deterministic tests. On acceptance, read or update the selected word and latch response data. Count down while occupied, then hold response until acknowledgment. A write response echoes its written word.

**Invariants and failure handling.** Only one request is outstanding per bank. A protected reader must not run before required writes complete. Address out of range terminates simulation.

**Operation lifecycle.** These state names summarize the register implementation; they are not additional RTL registers.

| Phase | Trigger | Update/output | Next phase |
|---|---|---|---|
| IDLE | request accepted | Read/write word; latch response; load countdown | WAIT |
| WAIT | countdown reaches zero | Assert response-valid | RESPONSE |
| RESPONSE | response accepted | Release occupied state | IDLE |

**Inline behavioral implementation.**

```systemverilog
module shared_memory_bank #(parameter int WORDS=64,LATENCY=1)(
 input logic clk,rst,req_valid,output logic req_ready,input logic write,
 input int word_address,input logic [31:0] write_data,output logic rsp_valid,
 input logic rsp_ready,output logic [31:0] read_data);
 logic [31:0] storage[WORDS]; logic occupied;int remaining;
 assign req_ready=!occupied;
 assign rsp_valid=occupied&&remaining==0;
 always_ff @(posedge clk) begin
  if(rst) begin occupied<=0;remaining<=0;read_data<=0;for(int i=0;i<WORDS;i++) storage[i]<=0;end
  else begin
   if(occupied&&remaining>0) remaining<=remaining-1;
   if(rsp_valid&&rsp_ready) occupied<=0;
   if(req_valid&&req_ready) begin
    if(word_address<0||word_address>=WORDS||LATENCY<1) $fatal(1,"Invalid shared access");
    else begin
     occupied<=1;remaining<=LATENCY-1;
     if(write) begin storage[word_address]<=write_data;read_data<=write_data;end
     else read_data<=storage[word_address];
    end
   end
  end
 end
endmodule
```

**Verification expectation.** Write 0x12345678 to word seven, then read word seven and compare exact data. Passed with LATENCY=3.

**Documented functional boundary.** Same-location shared reads broadcast, and separate-bank broadcasts can multicast. A full-warp decoder must group consumers accordingly; this single-word bank module does not itself perform that grouping. Physical broadcast delay remains unidentified.

**Unimplemented or unidentified.** This bank has one outstanding operation and does not accept another until the response retires. That is a baseline, not identified bank throughput. Full-warp decoding, multiple bank ports, broadcast behavior, buffering, and shared/L1 partition selection are missing.

### 4.10. Read-cache building block for L1 and L2

**Role.** Performs set/tag lookup on a 32-byte sector address. It records valid tags and recency. A hit schedules a response after the configured hit delay. A miss replaces a selected entry and schedules a response after the configured miss delay. It blocks further requests until the response retires, making early tag insertion unobservable to another requester.

**Quantitative configuration.** Demonstration geometry is 16 sets × 2 ways × 32 bytes = 1 KiB. Actual L2 capacity is 96 MiB. Documented lines contain four 32-byte sectors; this small sector-tag implementation is a diagnostic approximation, not the recovered tag geometry.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| SETS | 16 | sets | Positive | Baseline; L2 set count unknown |
| WAYS | 2 | ways | Positive | Baseline; L2 associativity unknown |
| Sector/tag unit | 32 | bytes | Set from sector index modulo SETS | Baseline tag approximation |
| Capacity at default | 1,024 | bytes | SETS × WAYS × 32 | Derived baseline, not 96 MiB hardware L2 |
| HIT_DELAY / MISS_DELAY | 1 / 1 | cycles | Positive | Baseline; intrinsic hardware delays unknown |
| Outstanding requests | 1 | request | Blocking until response retirement | Baseline |
| Write policy | Unsupported | policy | No stores accepted | Hardware policy unidentified |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| req_valid / req_ready | input / output | Request present / receiver permits acceptance. |
| byte_address | input, 32 bits | Byte address queried by the timing cache. |
| rsp_valid / rsp_ready | output / input | Completed response present / consumer permits retirement. |
| hit | output, one bit | Whether the accepted read found a valid tag. |
| response_address | output, 32 bits | Original address returned as identity; not fetched data. |

**Interface protocol.** Blocking read-only timing cache. response_address identifies the request; it is not fetched memory data.

**Stored state.** Tag, valid bit and recency timestamp per set/way; occupied bit, delay countdown, hit flag and response address.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| tags / age | SETS × WAYS × signed 32 bits each | Address identity and recency |
| valid | SETS × WAYS bits | Allocated tag state |
| occupied / remaining / response_address / hit | 1 / signed 32 / 32 / 1 bits | Blocking transaction state |

**Reset and cycle transitions.** Reset invalidates entries. Accepted lookup chooses set/tag from 32-byte sector index. Hit updates recency; miss replaces an entry. Hold the response until acknowledged. Further lookups are blocked during the whole request.

**Invariants and failure handling.** No concurrent pending lookup is possible. No dirty write state or external miss transaction exists. Early tag insertion is unobservable because the cache is blocking.

**Operation lifecycle.** These state names summarize the register implementation; they are not additional RTL registers.

| Phase | Trigger | Update/output | Next phase |
|---|---|---|---|
| IDLE | accepted valid-tag lookup | Update recency; schedule hit response | WAIT |
| IDLE | accepted absent-tag lookup | Allocate victim tag; schedule miss response | WAIT |
| WAIT | countdown reaches zero | Assert response-valid | RESPONSE |
| RESPONSE | response accepted | Release transaction | IDLE |

**Inline behavioral implementation.**

```systemverilog
module read_cache #(parameter int SETS=16,WAYS=2,HIT_DELAY=1,MISS_DELAY=1)(
 input logic clk,rst,req_valid,output logic req_ready,input logic [31:0] byte_address,
 output logic rsp_valid,input logic rsp_ready,output logic hit,output logic [31:0] response_address);
 int tags[SETS][WAYS],age[SETS][WAYS],cycle,remaining,set_id,tag,found,victim;
 logic valid[SETS][WAYS],occupied;
 assign req_ready=!occupied;assign rsp_valid=occupied&&remaining==0;
 always_comb begin
  set_id=int'((byte_address>>5)%SETS);tag=int'((byte_address>>5)/SETS);found=-1;victim=0;
  for(int a=0;a<WAYS;a++) begin
   if(valid[set_id][a]&&tags[set_id][a]==tag) found=a;
   if(!valid[set_id][a]||age[set_id][a]<age[set_id][victim]) victim=a;
  end
 end
 always_ff @(posedge clk) begin
  if(rst) begin
   cycle<=0;remaining<=0;occupied<=0;hit<=0;response_address<=0;
   for(int s=0;s<SETS;s++) for(int a=0;a<WAYS;a++) begin valid[s][a]<=0;tags[s][a]<=0;age[s][a]<=0;end
  end else begin
   cycle<=cycle+1;
   if(occupied&&remaining>0) remaining<=remaining-1;
   if(rsp_valid&&rsp_ready) occupied<=0;
   if(req_valid&&req_ready) begin
    if(HIT_DELAY<1||MISS_DELAY<1) $fatal(1,"Invalid cache delay");
    occupied<=1;hit<=found>=0;response_address<=byte_address;
    if(found>=0) begin remaining<=HIT_DELAY-1;age[set_id][found]<=cycle;end
    else begin remaining<=MISS_DELAY-1;valid[set_id][victim]<=1;tags[set_id][victim]<=tag;age[set_id][victim]<=cycle;end
   end
  end
 end
 // Blocking read-only cache: no request accepted until response retires.
endmodule
```

**Verification expectation.** First access to address 0x100 misses; a later access hits. Passed. This does not test true device cache organization.

**Unimplemented or unidentified.** Instantiate separate configured copies only as explicit L1/L2 hypotheses. L1/shared partition, L2 sets/ways/hash/slices, write-back/write-through behavior, dirty state, asynchronous miss requests, concurrent pending consumers, and fill/return queues are missing. Unlike the earlier monolithic prototype, this blocking component does not exercise overlapping pending hits.

### 4.11. Device-memory controller baseline

**Role.** Receives transaction identities into a finite timed queue and returns them after modeled delay, with finite initiation capacity and backpressure. It provides an executable baseline contract for request and return behavior.

**Quantitative configuration.** `SLOTS`, `LATENCY`, and `INTERVAL` are unresolved hardware parameters. Saved large-copy throughput was 1.4737 TB/s; it does not establish per-request controller latency.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| SLOTS | 4 | transactions | Positive | Baseline; physical queue depth unknown |
| LATENCY | 1 | cycles | Positive | Baseline; GDDR7 response not identified |
| INTERVAL | 1 | cycles/acceptance | Positive | Baseline; channel service not identified |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| req_valid / req_ready | input / output | Request present / receiver permits acceptance. |
| req_id | input, 32-bit transaction identity | Operation or transaction identity retained until return. |
| rsp_valid / rsp_ready | output / input | Completed response present / consumer permits retirement. |
| rsp_id | output, same identity | Identity of the completed operation or transaction. |

**Interface protocol.** Caller must provide addresses, byte masks and data through an additional transaction record; this baseline only times identities.

**Stored state.** Inherited timed_queue state.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| Inherited timed_queue arrays | Configured by SLOTS | Request identity and response state |

**Reset and cycle transitions.** Accept through finite slots and initiation spacing; return through FIFO completion/backpressure.

**Invariants and failure handling.** This module does not model GDDR7 command timing or numerical memory contents.

**Inline behavioral implementation.**

```systemverilog
module memory_controller #(parameter int SLOTS=4,LATENCY=1,INTERVAL=1)(
 input logic clk,rst,req_valid,output logic req_ready,input logic [31:0] req_id,
 output logic rsp_valid,input logic rsp_ready,output logic [31:0] rsp_id);
 // FIFO timed-service baseline, not a GDDR7 bank/command implementation.
 timed_queue #(.SLOTS(SLOTS),.LATENCY(LATENCY),.INTERVAL(INTERVAL)) controller(.*);
endmodule
```

**Verification expectation.** FIFO primitive checks passed. Memory-controller physical behavior is unimplemented.

**Unimplemented or unidentified.** GDDR7 channels, bank/row state, address mapping, command constraints, read/write turnaround, transfer buses, numerical memory contents, and clock-domain crossings are missing.

### 4.12. Block barrier controller

**Role.** Collects one arrival bit per participating warp. It begins release only when every participant has arrived and the caller reports protected operations complete. After the supplied release delay, it pulses release and resets arrival state for the next generation.

**Quantitative configuration.** `WARPS` is four for the tested block; there are two barrier instructions per reduction step. `RELEASE_DELAY` is unknown on RTX and is a configuration value.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| WARPS | 4 | participants | All required arrival bits collected | Tested block width |
| RELEASE_DELAY | 1 | cycles | Positive | Baseline; intrinsic release unknown |
| Barrier instances in kernel | 2 | per reduction step | Protect staging and storage reuse | Source/compiled execution structure |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| arrivals | input, WARPS one-cycle arrival bits | One-cycle arrival pulses from the participating warps. |
| protected_operations_complete | input, one bit | External confirmation that barrier-protected work completed. |
| release_warps | output, one-cycle release pulse | Registered pulse releasing the waiting participant set. |

**Documented functional boundary.** Ordinary CTA barrier participation, reuse and participant-relative memory visibility are now identified from PTX. Protected completion means the required prior reads have returned and writes are visible to participants; it is not a universal DRAM flush. Explicit-count and exited-thread cases require caller-side participant tracking that this four-bit baseline does not yet supply. Release/resume delays remain unknown physical timings.

**Interface protocol.** One barrier generation is outstanding. Clear old arrival pulses. The caller supplies a justified protected-completion condition and distributes release to the correct block warps.

**Stored state.** Arrival mask, releasing bit and remaining release delay.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| arrived | WARPS bits | Arrivals in current generation |
| releasing / remaining | 1 / signed 32 bits | Release phase and delay |

**Reset and cycle transitions.** Reset clears arrivals. Accumulate arrival bits while collecting. When all participants arrived and protected work completed, enter release countdown. Pulse release, clear arrivals, and return to collection.

**Invariants and failure handling.** Never release before both arrival and completion conditions. Do not reuse stale arrival bits for a new generation.

**Operation lifecycle.** These state names summarize the register implementation; they are not additional RTL registers.

| Phase | Trigger | Update/output | Next phase |
|---|---|---|---|
| COLLECT | arrival bits | Accumulate participant mask | COLLECT |
| COLLECT | all arrived and protected work complete | Load release delay | RELEASING |
| RELEASING | countdown expires | Pulse release and clear generation | COLLECT |

**Inline behavioral implementation.**

```systemverilog
module barrier_controller #(parameter int WARPS=4,RELEASE_DELAY=1)(
 input logic clk,rst,input logic [WARPS-1:0] arrivals,
 input logic protected_operations_complete,output logic release_warps);
 logic [WARPS-1:0] arrived;logic releasing;int remaining;
 always_ff @(posedge clk) begin
  if(rst) begin arrived<=0;releasing<=0;remaining<=0;release_warps<=0;end
  else begin
   release_warps<=0;
   if(!releasing) begin
    arrived<=arrived|arrivals;
    if(&(arrived|arrivals)&&protected_operations_complete) begin
     if(RELEASE_DELAY<1) $fatal(1,"Invalid barrier delay");
     releasing<=1;remaining<=RELEASE_DELAY-1;
    end
   end else if(remaining>0) remaining<=remaining-1;
   else begin release_warps<=1;arrived<=0;releasing<=0;end
  end
 end
endmodule
```

**Verification expectation.** Partial arrivals do not release. All arrivals without protected completion do not release. Completing protected work permits release. Passed with RELEASE_DELAY=2.

**Unimplemented or unidentified.** The completion input defines the modeled drain obligation externally. Actual NVIDIA memory-ordering obligations, arrival throughput, release timing, partial participants, and asynchronous barrier semantics remain unidentified.

### 4.13. Block completion

**Role.** Retires the modeled block only after every warp ends and the caller reports output stores complete. Completion remains asserted until reset.

**Quantitative configuration.** Four warp-end bits for the example. Output completion comes from the store path; it is not implied by instruction issue.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| WARPS | 4 | end flags | All must be true before retirement | Tested block width |
| Output completion | External flag | boolean | Must reflect all required stores | Integration requirement, unimplemented return path |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| ended | input, WARPS end flags | Persistent completion flag from each warp. |
| all_output_stores_complete | input, one bit | External confirmation that required output stores completed. |
| block_complete | output, one bit | Latched block retirement eligibility. |

**Interface protocol.** End flags remain asserted after each warp ends. Output completion must come from the store completion path.

**Stored state.** Latched block completion bit.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| block_complete | One bit | Latched completion |

**Reset and cycle transitions.** Reset clears completion. When all ended flags and output completion hold, latch completion until reset.

**Invariants and failure handling.** Instruction end alone cannot retire the block. Return the completed block slot to the allocator only once.

**Operation lifecycle.** These state names summarize the register implementation; they are not additional RTL registers.

| Phase | Trigger | Update/output | Next phase |
|---|---|---|---|
| INCOMPLETE | all ended && stores complete | Latch completion | COMPLETE |
| COMPLETE | until reset | Hold completion | COMPLETE |

**Inline behavioral implementation.**

```systemverilog
module completion_tracker #(parameter int WARPS=4)(
 input logic clk,rst,input logic [WARPS-1:0] ended,
 input logic all_output_stores_complete,output logic block_complete);
 always_ff @(posedge clk) begin
  if(rst) block_complete<=0;
  else if((&ended)&&all_output_stores_complete) block_complete<=1;
 end
endmodule
```

**Verification expectation.** Test incomplete warps and pending output stores prevent retirement. Not behaviorally tested yet.

**Unimplemented or unidentified.** Whole-grid completion, output-store acknowledgments, allocation release wiring, and end-to-end integration are missing.

### 4.14. Reference clock and cycle accounting

**Role.** Counts rising clock edges after reset. Other components use that same reference domain in this baseline. Observed completion-cycle differences provide timing output.

**Quantitative configuration.** Chosen reporting reference is 2.94 GHz, corresponding to 0.340136 ns/cycle. Final profile rates ranged from 2.66450 GHz for staging to 2.93218 GHz for computation.

**Design specification and parameter restrictions.**

| Field | Library default or recorded value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| Counter width | 64 | bits | Wrap is outside admitted run horizon | Interface choice |
| Reporting reference | 2.94 | GHz | Unit conversion, not physical clock lock | Chosen reference |
| Domain count | 1 | clock | All current modules share clk | Baseline; memory domains missing |

| Signal | Direction and width | Function |
|---|---|---|
| clk, rst | Input, one bit each | Rising-edge clock and synchronous active-high reset. |
| cycles | output, 64-bit unsigned counter | Reference clock edges counted since reset. |

**Interface protocol.** Counter is observational and must not control arbitration. Clock and reset are common inputs.

**Stored state.** 64-bit cycle counter.

**Internal storage organization.**

| Array/register | Implemented organization | Function |
|---|---|---|
| cycles | 64 bits | Reference tick count |

**Reset and cycle transitions.** Synchronous reset sets zero; every other rising edge increments by one.

**Invariants and failure handling.** All timed components in this baseline must share the same reset/clock convention. This does not implement memory-clock crossings.

**Inline behavioral implementation.**

```systemverilog
module reference_clock_counter(input logic clk,rst,output logic [63:0] cycles);
 always_ff @(posedge clk) begin if(rst) cycles<=0;else cycles<=cycles+1;end
endmodule
```

**Verification expectation.** Test reset and monotonic increment. Not separately behaviorally tested.

**Unimplemented or unidentified.** Memory-clock domains and cross-domain transfer rules are missing. The reference is a reporting convention; it does not identify intrinsic response timing.

### 4.15. Completion-driven register storage

**Role.** Store 32-bit values and prevent a dependent instruction from using a destination until its producer actually returns. This is the replacement readiness contract for variable-latency operations. The original timestamp scoreboard remains available for its older deterministic tests; the new path does not consult it.

**Design specification and parameter restrictions.**

| Field | Implemented value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| REGS | 64 default; 8 in connected test | logical registers | At least 2 | Baseline; not physical register allocation |
| Data width | 32 | bits/register | One word per logical identity | Interface choice |
| Read views | 2 | sources | Valid indices when enabled | Baseline; not physical bank ports |
| Reservation/completion width | 32 | bits/identity | Unique among pending destinations | Interface choice |
| Completion inputs | 1 | result/edge | Must match a pending destination and identity | Baseline; physical writeback capacity unknown |
| Return-to-readiness delay | Registered update at completion edge | edge boundary | No same-edge issue bypass | Model rule; physical bypass delay unknown |

**Ports and interface protocol.**

| Signal | Direction and width | Meaning |
|---|---|---|
| clk, rst | Input, 1 bit each | Rising-edge clock, synchronous reset |
| source_a, source_b; use_a, use_b | Input, signed 32-bit indices; 1-bit enables | Select required operands |
| operands_ready; operand_a, operand_b | Output, 1 bit; 32 bits each | Data may be consumed only when all enabled sources are ready |
| reserve_valid, reserve_ready | Input/output, 1 bit | Accept a destination reservation when both are high |
| destination, reservation_id | Input, signed 32-bit index; 32-bit identity | Writable destination and producer identity |
| complete_valid | Input, 1 bit | Actual completion event; upstream arbitration must present at most one |
| complete_destination, complete_id, complete_data | Input, index and two 32-bit values | Destination, matching producer identity and returned data |
| pending_count | Output, signed 32 bits | Number of reserved destinations awaiting completion |

The completion input has no ready signal: every valid legal completion is consumed. A future shared return network must arbitrate and buffer competing producers before this port. Source selection is a combinational read view, not an independent ready/valid request. Its values are meaningful only when operands_ready is true. Downstream execution acceptance and destination reservation must occur atomically; the connected test exercises that obligation.

**Stored state and internal storage organization.**

| Array | Organization | Function | Reset |
|---|---|---|---|
| values | REGS × 32 bits | Actual returned words | Zeroed |
| owners | REGS × 32 bits | Pending producer identity | Zeroed |
| pending | REGS × 1 bit | Prevent early reads/overwrites | Cleared |
| initialized | REGS × 1 bit | Distinguish valid values from absent producers | Only register zero initialized |

Register zero is an immutable zero source in this model. Its identity is a trace convention, not a claim about physical NVIDIA register allocation. Undefined sources remain unready.

**Reset and cycle transitions.** A reservation sets pending and remembers the identity. A legal completion writes data, marks the destination initialized and clears pending. Readiness follows this stored state rather than elapsed time. Concurrent reservation and completion on different destinations are permitted. A destination pending before an edge cannot accept a replacement on its completion edge; a held reservation can enter at the next edge. Reset discards all reservations and nonzero-register validity.

**Operation lifecycle and timing.**

| Phase | Trigger | State/update | Next phase |
|---|---|---|---|
| Undefined/free | Legal reservation handshake | Remember identity; set pending | Pending |
| Ready/free | Legal reservation handshake | Old value becomes unavailable | Pending |
| Pending | No matching completion | Hold identity; dependent instructions stay blocked | Pending |
| Pending | Matching completion at edge k | Store value; clear pending after edge | Ready/free |
| Ready/free | Consumer accepted at edge k+1 or later | Consumer captures value | Ready/free unless reserved again |

A producer may wait arbitrarily long. No result-delay parameter releases its destination. Physical register ports, bypass behavior and bank contention are not identified by this implementation.

**Invariants and failure handling.** A completion must name a writable index, pending reservation and matching identity. Duplicate outstanding identities, stale or duplicate completions, and invalid reservation indices terminate simulation. Pending overwrites are blocked by reserve_ready. Invalid source indices produce unready operands without indexing outside the array. Upstream code must ensure instruction acceptance cannot occur without every required operand and destination reservation. Old completions arriving after reset are invalid; an integrated reset protocol must drain or discard them upstream.

**Inline behavioral implementation.** Simulation contract; synthesis qualification is not established.

```systemverilog
// Simulation contract, not a recovered RTX register-bank implementation.
module completion_register_file #(parameter int REGS=64)(
 input logic clk,rst,
 input int source_a,source_b,input logic use_a,use_b,
 output logic operands_ready,output logic [31:0] operand_a,operand_b,
 input logic reserve_valid,output logic reserve_ready,
 input int destination,input logic [31:0] reservation_id,
 input logic complete_valid,input int complete_destination,
 input logic [31:0] complete_id,complete_data,
 output int pending_count
);
 logic initialized[REGS],pending[REGS];
 logic [31:0] values[REGS],owners[REGS];
 logic sources_in_range,destination_in_range;
 initial if(REGS<2) $fatal(1,"Register capacity must be at least two");
 always_comb begin
  operand_a=0;operand_b=0;operands_ready=!rst;
  sources_in_range=(!use_a||(source_a>=0&&source_a<REGS))&&
                   (!use_b||(source_b>=0&&source_b<REGS));
  if(!sources_in_range) operands_ready=0;
  if(use_a&&source_a>=0&&source_a<REGS) begin
   operand_a=values[source_a];
   operands_ready=operands_ready&&initialized[source_a]&&!pending[source_a];
  end
  if(use_b&&source_b>=0&&source_b<REGS) begin
   operand_b=values[source_b];
   operands_ready=operands_ready&&initialized[source_b]&&!pending[source_b];
  end
  destination_in_range=destination>0&&destination<REGS;
  reserve_ready=0;
  if(destination_in_range) reserve_ready=!rst&&!pending[destination];
  pending_count=0;
  for(int r=0;r<REGS;r++) if(pending[r]) pending_count++;
 end
 always_ff @(posedge clk) begin
  if(rst) begin
   for(int r=0;r<REGS;r++) begin
    initialized[r]<=(r==0);pending[r]<=0;values[r]<=0;owners[r]<=0;
   end
  end else begin
   // A completion must match an existing reservation before this edge.
   if(complete_valid) begin
    if(complete_destination<=0||complete_destination>=REGS)
     $fatal(1,"Completion destination outside writable register range");
    else if(!pending[complete_destination]||owners[complete_destination]!=complete_id)
     $fatal(1,"Completion has no matching pending reservation");
    else begin
     values[complete_destination]<=complete_data;
     initialized[complete_destination]<=1;pending[complete_destination]<=0;
    end
   end
   if(reserve_valid) begin
    if(!destination_in_range) $fatal(1,"Reservation destination outside writable register range");
    else if(reserve_ready) begin
     for(int r=1;r<REGS;r++)
      if(pending[r]&&owners[r]==reservation_id)
       $fatal(1,"Duplicate outstanding reservation identity");
     owners[destination]<=reservation_id;pending[destination]<=1;
    end
   end
  end
 end
 // No same-edge completion bypass. A held reservation may proceed next edge.
 // Register zero is the model's immutable zero source, not an RTX allocation fact.
endmodule
```

**Verification expectations.** [The connected test](components/completion_path_tb.sv) joins timed memory/execution queues to this register file and checks actual data flow through a dependent addition. Three synthetic memory delays (2, 12 and 40 cycles) exercise delayed returns, held results, downstream stalls, concurrent updates and reset. Five rejection cases cover invalid destinations, unreserved returns, wrong identities, duplicate outstanding identities and duplicate completion. All eight cases passed in [the receipt](components/completion_verification.json). Integer addition in the test is not BF16 matrix emulation.

**Missing physical parameters.** Register-bank organization, port counts, collector capacity, bypass latency and writeback arbitration remain unknown. Warp-wide values, multiple completion sources and a full native instruction path remain unimplemented. This test establishes a necessary functional rule; it does not reduce or validate RTX runtime prediction error.

### 4.16. Numerical BF16/FP32 matrix pipeline

**Role.** Accept a row-major 16 × 16 BF16 matrix A, a row-major 16 × 16 BF16 matrix B and a 16 × 16 FP32 accumulator C. Compute C plus the product of A and B. The ARITHMETIC_MODE parameter selects either the older sequential FP32 reference (0) or the experimentally reconstructed aligned-dot candidate (1). The older reference is now falsified for a broader finite input domain: the measured operation preserves the unit in 2^24 + 1 − 2^24, whereas sequential FP32 rounding loses it. Mode 1 fixes this tested failure by aligning contributions before summation; it is not a complete reconstruction of every Tensor Core arithmetic case. Section 4.19 adds the measured lane mapping for one BF16 operation family; bitwise agreement with this arithmetic reference remains unproven for NVIDIA's general Tensor Core accumulation behavior.

**Design specification and parameter restrictions.**

| Field | Implemented value | Unit | Restriction | Evidence class |
|---|---:|---|---|---|
| Matrix dimensions | 16 × 16 × 16 | rows × columns × reduction elements | Fixed supported operation | Same primitive shape as corrected matrix probe; not a single native-instruction mapping |
| A/B storage at interface | 256 × 16 each | bits | BF16 words, row-major | Explicit operation contract |
| C/result storage at interface | 256 × 32 each | bits | FP32 words, row-major | Explicit operation contract |
| SLOTS | 2 default | operations | Positive | Synthetic capacity; physical matrix queue unknown |
| LATENCY | 17 default | edge intervals | Positive | Synthetic timing; not measured native latency |
| INTERVAL | 3 default | edge intervals/acceptance | Positive | Synthetic timing; not measured native issue interval |
| ARITHMETIC_MODE | 0 default; 1 candidate | Configuration | Only 0 or 1 | 0 preserves old reference; 1 uses measured aligned-dot rule |
| Arithmetic domain | Finite normal values and zero | BF16/FP32 | Reject nonfinite/subnormal operands or results | Candidate hardware validation covers the measured cancellation family; arbitrary finite reductions remain unverified |

**Ports and interface protocol.**

| Signal | Direction and width | Meaning |
|---|---|---|
| clk, rst | Input, 1 bit each | Clock and synchronous reset |
| req_valid, req_ready | Input/output, 1 bit | Accept the complete operand packet at a rising edge |
| req_id | Input, 32 bits | Unique identity while outstanding |
| a_words, b_words | Input, 256 × 16 bits each | Complete row-major A and B matrices |
| accumulator_words | Input, 256 × 32 bits | Initial C values |
| rsp_valid, rsp_ready | Output/input, 1 bit | Retire the complete result packet |
| rsp_id, result_words | Output, 32 bits and 256 × 32 bits | Returned operation identity and numerical results |
| outstanding | Output, signed 32 bits | Accepted operations not yet retired |

The input packet must remain stable while req_valid is asserted and req_ready is low. The output packet is meaningful only while rsp_valid is asserted and remains stable under backpressure. These wide logical ports describe the operation boundary; they do not assert a physical 256-word register-read or writeback capability.

**Stored state and internal storage organization.**

| State | Organization | Function | Reset |
|---|---|---|---|
| results | SLOTS × 256 × 32 bits | Captured arithmetic results | Invalid until accepted work completes |
| ids, due | SLOTS × 32 bits each | Identity and eligibility cycle | Zeroed |
| occupied | SLOTS × 1 bit | Outstanding identity checks | Cleared |
| cycle, head, tail, next_accept, outstanding | Signed 32-bit fields | Clocked FIFO and service admission | Zeroed |

**Reset and cycle transitions.** At request acceptance, calculate the numerical result from the captured packet and store it in a queue slot. Set its due cycle to acceptance cycle plus LATENCY. The result cannot be consumed before that due cycle. Each response retirement releases exactly one FIFO slot. A full queue does not admit a replacement on the same edge that frees its head. Reset discards pending results.

The host evaluates the arithmetic at acceptance through [a simulation-only DPI helper](numerical/bf16_reference.cpp). DPI is the simulator interface used to call the C++ arithmetic routine. Numerical computation time on the host is not the modeled hardware duration. Internal multiplier/addition pipeline stages are not represented. This makes the unit useful for numerical integration while leaving its physical implementation and calibration explicit.

**Operation lifecycle and timing.**

| Phase | Trigger | Update | Next phase |
|---|---|---|---|
| Free slot | Packet handshake | Capture identity, evaluate and store results, set due cycle | Pending |
| Pending | Before due cycle or behind earlier result | Hold data; no early return | Pending |
| Head pending | Due cycle reached | Assert response valid | Available |
| Available | Receiver stalled | Preserve identity and all result words | Available |
| Available | Response handshake | Release head and decrement outstanding | Free slot |

LATENCY counts acceptance-to-earliest-response-handshake edge intervals. INTERVAL constrains separate accepted request edges. Capacity and FIFO blocking can increase observed delay; they are not folded into a fitted whole-operation latency. These controls remain synthetic until matched hardware measurements constrain them.

**Invariants and failure handling.** Outstanding count stays between zero and SLOTS. Identities must be unique while pending. Every accepted packet returns once in FIFO order unless reset cancels it. Duplicate pending identities terminate simulation. The arithmetic helper rejects nonfinite/subnormal operands and results, rather than silently claiming unsupported GPU semantics. The model requires bounded runs before signed cycle-counter overflow.

**Inline behavioral implementation.** This module uses simulation-only C++ arithmetic and is not synthesis-qualified.

```systemverilog
// 16x16x16 BF16/FP32 operation-level model. Mode0 sequential reference;
// mode1 measured aligned-dot candidate, validated only in its scoped domain.
module numerical_matrix_pipeline #(
 parameter int SLOTS=2,LATENCY=17,INTERVAL=3,ARITHMETIC_MODE=0
)(
 input logic clk,rst,req_valid,output logic req_ready,
 input logic [31:0] req_id,
 input logic [15:0] a_words[256],b_words[256],
 input logic [31:0] accumulator_words[256],
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,result_words[256],output int outstanding
);
 import "DPI-C" function int unsigned reference_bf16_fma(
   input int unsigned a,b,c);
 import "DPI-C" function int unsigned reference_bf16_aligned_dot(
   input int unsigned a[],b[], input int unsigned c);
 int cycle,head,tail,next_accept,due[SLOTS];
 logic occupied[SLOTS];logic [31:0] ids[SLOTS],results[SLOTS][256];
 logic push,pop;
 assign req_ready=!rst&&outstanding<SLOTS&&cycle>=next_accept;
 assign rsp_valid=!rst&&outstanding>0&&cycle>=due[head];
 assign rsp_id=ids[head];
 assign push=req_valid&&req_ready;
 assign pop=rsp_valid&&rsp_ready;
 for(genvar i=0;i<256;i++) assign result_words[i]=results[head][i];
 initial if(SLOTS<1||LATENCY<1||INTERVAL<1||ARITHMETIC_MODE<0||ARITHMETIC_MODE>1) $fatal(1,"Invalid matrix pipeline configuration");
 always_ff @(posedge clk) begin
  if(rst) begin
   cycle<=0;head<=0;tail<=0;next_accept<=0;outstanding<=0;
   for(int s=0;s<SLOTS;s++) begin occupied[s]<=0;ids[s]<=0;due[s]<=0;end
  end else begin
   cycle<=cycle+1;
   if(push) begin
    for(int s=0;s<SLOTS;s++)
     if(occupied[s]&&ids[s]==req_id) $fatal(1,"Duplicate pending matrix identity");
    for(int m=0;m<16;m++) for(int n=0;n<16;n++) begin
     logic [31:0] sum;
     int unsigned dot_a[16],dot_b[16];
     sum=accumulator_words[m*16+n];
     for(int k=0;k<16;k++) begin
      dot_a[k]={16'b0,a_words[m*16+k]};dot_b[k]={16'b0,b_words[k*16+n]};
      if(ARITHMETIC_MODE==0) sum=reference_bf16_fma(dot_a[k],dot_b[k],sum);
     end
     if(ARITHMETIC_MODE==1)
      sum=reference_bf16_aligned_dot(dot_a,dot_b,accumulator_words[m*16+n]);
     results[tail][m*16+n]<=sum;
    end
    ids[tail]<=req_id;due[tail]<=cycle+LATENCY;occupied[tail]<=1;
    tail<=(tail+1)%SLOTS;next_accept<=cycle+INTERVAL;
   end
   if(pop) begin occupied[head]<=0;head<=(head+1)%SLOTS;end
   case({push,pop})
    2'b10:outstanding<=outstanding+1;
    2'b01:outstanding<=outstanding-1;
    default:outstanding<=outstanding;
   endcase
  end
 end
 // Results are evaluated at acceptance, then hidden until modeled completion.
 // FIFO service, no same-edge full replacement, no intrinsic timing claim.
endmodule
```

**Verification expectations.** [The verifier](numerical/verify_numerical_matrix.py) constructs identity, zero-product, signed-integer, fractional-rounding, cancellation and varied-exponent cases. Its independent oracle uses exact rational products and additions with explicit nearest-even FP32 rounding. Two synthetic timing configurations run six matrix packets each, checking 3,072 result words bitwise, acceptance intervals, no early completion, queue bounds, FIFO order, stalled response stability and reset. Three expected failures reject duplicate identities, NaN operands and subnormal operands. All five verification cases passed in [the receipt](numerical/verification.json). Build logs retain permitted warnings.

**Missing physical parameters.** Native lane/register layout, instruction decomposition, internal accumulation order, execution partition routing, operand collection, intrinsic result latency, initiation interval and output bandwidth remain unresolved. Full GEMM input staging, barriers, multi-block scheduling and output stores are not supplied by this standalone arithmetic unit.

**Measured arithmetic candidate and validation.** For each output, mode 1 computes the sixteen exact BF16 products in double precision, includes the FP32 input accumulator, and finds the exponent of the largest absolute contribution. Its alignment quantum is two raised to that exponent minus 25. It truncates each signed contribution toward zero to an integer multiple of the quantum, sums those integers, then rounds the resulting value to FP32. The number 25 describes this measured behavioral alignment rule; it does not establish a private accumulator bit width.

The rule was developed from magnitude-gap and signed-small-term probes, then frozen before 162 new hardware cases that vary small products, a small FP32 accumulator, and two separate half-sized products. Every prediction matched. The implemented clocked RTL/DPI candidate reproduces 1,536 saved hardware outputs from six of those cases. Running the older reference against the same expectations produces a preserved numerical failure. NaN and subnormal rejection checks pass in candidate mode. Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_aligned_dot.py`; the receipt is `numerical/aligned_dot_verification.json`. Matrix latency and issue interval remain synthetic.

The validated family contains two opposite power-of-two products plus small products or an initial accumulator. General product distributions, repeated accumulation, exceptional values and other shapes remain unverified. Default mode 0 is retained for earlier reference tests; neither mode should be described as universally hardware-correct.

### 4.17. Quantized allocation demands

This combinational component converts compiler resource usage into CUDA allocation demands before block admission. Identified cc12.0 allocation rules are 256 register words per warp and 128 shared bytes per block. Evidence and checks are in [source sweep 5](discovery_rounds/source_sweep_005.md). They do not identify physical bank geometry.

| Port | Direction | Meaning |
|---|---|---|
| `block_threads` | input | Threads, 1 through 1,024 |
| `registers_per_thread` | input | Compiler register count, 0 through runtime limit 255 |
| `user_shared_bytes` | input | Static plus dynamic application bytes |
| `reserved_shared_bytes` | input | Explicit runtime reservation; 1,024 in saved profiles |
| `valid` | output | Inputs satisfy the supported domain |
| `allocated_register_words` | output | Rounded per-warp words times warp count |
| `launch_check_register_words` | output | Admission demand using warp count rounded to four partitions |
| `allocated_shared_bytes` | output | Rounded application plus reserved bytes |

There is no stored state, reset, arbitration or clock delay. Outputs are combinational. Invalid inputs produce zero demands with `valid` low. Check `valid` before sending demands to the block allocator. Separately enforce launch-check and per-partition capacities: the existing allocator checks aggregate capacities only. Physical warp placement remains unknown.

For 128 threads and 40 registers per thread, allocation is 5,120 words. Application storage of 8,192 bytes plus 1,024 reserved bytes allocates 9,216 bytes. Six directed checks passed, recorded in [allocation_verification.json](components/allocation_verification.json). No physical timing is assigned.

```systemverilog
// CUDA allocation-model arithmetic for cc12.0; not physical warp placement.
module allocation_demands #(
 parameter int REG_QUANTUM_WORDS=256,
 parameter int SHARED_QUANTUM_BYTES=128,
 parameter int WARP_THREADS=32,
 parameter int PARTITIONS=4,
 parameter int MAX_THREADS=1024,
 parameter int MAX_REGS_PER_THREAD=255
)(
 input int block_threads,registers_per_thread,user_shared_bytes,reserved_shared_bytes,
 output logic valid,
 output int allocated_register_words,launch_check_register_words,allocated_shared_bytes
);
 int warps,register_words_per_warp;
 always_comb begin
  valid=block_threads>0 && block_threads<=MAX_THREADS &&
        registers_per_thread>=0 && registers_per_thread<=MAX_REGS_PER_THREAD &&
        user_shared_bytes>=0 && reserved_shared_bytes>=0 &&
        REG_QUANTUM_WORDS>0 && SHARED_QUANTUM_BYTES>0 && WARP_THREADS>0 && PARTITIONS>0;
  warps=0;register_words_per_warp=0;
  allocated_register_words=0;launch_check_register_words=0;allocated_shared_bytes=0;
  if(valid) begin
   warps=(block_threads+WARP_THREADS-1)/WARP_THREADS;
   register_words_per_warp=((registers_per_thread*WARP_THREADS+REG_QUANTUM_WORDS-1)/REG_QUANTUM_WORDS)*REG_QUANTUM_WORDS;
   allocated_register_words=register_words_per_warp*warps;
   launch_check_register_words=register_words_per_warp*((warps+PARTITIONS-1)/PARTITIONS)*PARTITIONS;
   allocated_shared_bytes=((user_shared_bytes+reserved_shared_bytes+SHARED_QUANTUM_BYTES-1)/SHARED_QUANTUM_BYTES)*SHARED_QUANTUM_BYTES;
  end
 end
endmodule
```

### 4.18. Connected quantized block admission

This wrapper connects Section 4.17 allocation arithmetic to the existing block allocator. It enforces the queried 24 block slots, 48 resident warps, 65,536 register words, 100 KiB shared capacity and 99 KiB application shared limit per block. It does not model unknown partition placement or hardware dispatch arbitration. The default shared capacity is the device limit; actual runtime carveout selection remains a separate unresolved configuration.

| Port group | Direction | Contract |
|---|---|---|
| `clk`, `rst` | input | Clock and synchronous reset |
| `admit_valid` | input | Caller presents a request and holds its resource fields until accepted |
| `block_threads`, `registers_per_thread` | input | Compiler thread and register demand |
| `user_shared_bytes`, `reserved_shared_bytes` | input | Application and runtime shared demand |
| `admit_ready` | output | Valid demand fits current aggregate capacities |
| `admitted_slot` | output | Candidate slot, valid only when request is accepted |
| `resident_blocks`, `resident_warps` | output | Current allocated totals |
| `allocated_register_words`, `allocated_shared_bytes` | output | Rounded demand for the presented request, not resident totals |
| `retire_valid`, `retire_slot` | input | Release an allocated block at the next edge |

Acceptance is `admit_valid && admit_ready` at a rising edge. Resource demand calculation is combinational. The wrapper stores warp count per slot; the connected allocator stores register and shared allocations. Reset clears all state. Retirement of an invalid or empty slot is fatal in the allocator. Zero threads, excessive registers or excessive shared demand cannot be admitted. There is no numerical payload in this connection.

Readiness uses pre-edge allocations. If a full model retires a block at edge E, it cannot use that released capacity for another admission at E; readiness changes after E, permitting admission at a later edge. If both events are legal using pre-edge space, they update different slots. Slot selection is the existing lowest-free-slot modeling policy, not recovered NVIDIA arbitration. The one-edge transition is implementation timing, not measured dispatch latency.

Connected checks reproduce eleven resident blocks for the small saved GEMM and eight for the larger, verify resource release, and enforce block, warp and per-block shared limits. [quantized_admission_verification.json](components/quantized_admission_verification.json) preserves source hashes and results. This is a connected resource subsystem, not an integrated full GPU.

```systemverilog
// Connected aggregate resource model; private partition placement and dispatch timing unknown.
module quantized_block_admission #(
 parameter int BLOCK_SLOTS=24,REG_WORDS=65536,SHARED_BYTES=102400,
 parameter int MAX_WARPS=48,MAX_SHARED_PER_BLOCK=101376
)(
 input logic clk,rst,admit_valid,
 input int block_threads,registers_per_thread,user_shared_bytes,reserved_shared_bytes,
 output logic admit_ready,
 output int admitted_slot,resident_blocks,resident_warps,
 output int allocated_register_words,allocated_shared_bytes,
 input logic retire_valid,input int retire_slot
);
 logic demands_valid,base_ready,pass_budget;
 int launch_register_words,requested_warps,slot_warps[BLOCK_SLOTS];
 allocation_demands demands(
  .block_threads,.registers_per_thread,.user_shared_bytes,.reserved_shared_bytes,
  .valid(demands_valid),.allocated_register_words,
  .launch_check_register_words(launch_register_words),.allocated_shared_bytes
 );
 always_comb begin
  resident_warps=0;
  for(int i=0;i<BLOCK_SLOTS;i++)resident_warps+=slot_warps[i];
  requested_warps=demands_valid?(block_threads+31)/32:0;
  pass_budget=demands_valid && user_shared_bytes<=MAX_SHARED_PER_BLOCK &&
              launch_register_words<=REG_WORDS && resident_warps+requested_warps<=MAX_WARPS;
  admit_ready=base_ready && pass_budget;
 end
 block_allocator #(.SLOTS(BLOCK_SLOTS),.REG_WORDS(REG_WORDS),.SHARED_BYTES(SHARED_BYTES)) allocator(
  .clk,.rst,.admit_valid(admit_valid && pass_budget),.admit_ready(base_ready),
  .registers_needed(allocated_register_words),.shared_needed(allocated_shared_bytes),
  .admitted_slot,.retire_valid,.retire_slot,.resident_blocks
 );
 always_ff @(posedge clk) begin
  if(rst) begin
   for(int i=0;i<BLOCK_SLOTS;i++)slot_warps[i]<=0;
  end else begin
   if(retire_valid && retire_slot>=0 && retire_slot<BLOCK_SLOTS)slot_warps[retire_slot]<=0;
   if(admit_valid && admit_ready)slot_warps[admitted_slot]<=requested_warps;
  end
 end
endmodule
```

### 4.19. Native BF16 operand adapter

**Role and supported operation.** Connect the register contents recovered on RTX 5090 to the numerical component in Section 4.16. Each of the 32 lanes supplies four packed 32-bit A words, four packed B words and eight FP32 accumulator words. The adapter rearranges these values into row-major matrices and places the returned values in the measured lane/register positions. This covers the CUDA 12.8 sm120 BF16 row-major 16 × 16 × 16 operation. It does not model private register banks or a physical Tensor Core pipeline.

The hardware experiment in `discovery_rounds/functional_mapping_002` observed two HMMA instructions. Each computes a 16 × 8 output half from four A words and two B words per lane. The adapter accepts both halves together. Its single completion therefore represents the operation boundary, rather than independently scheduled native instructions. The official PTX comparison in `discovery_rounds/literature_sweep_009.json` agrees with all 768 measured A/B/C element positions.

**Quantitative parameters and ports.**

| Port or parameter | Direction or value | Meaning and evidence |
|---|---|---|
| clk, rst | Input, 1 bit each | Common model clock and synchronous reset |
| req_valid, req_ready | Input/output, 1 bit each | Whole packet accepted on a rising edge when both are high |
| req_id | Input, 32 bits | Identity unique among outstanding requests |
| a_registers, b_registers | Input, 32 lanes × 4 words × 32 bits each | Two BF16 elements per word; measured native operand contents |
| c_registers | Input, 32 lanes × 8 words × 32 bits | FP32 accumulators in measured result positions |
| rsp_valid, rsp_ready | Output/input, 1 bit each | Whole result retires when both are high at an edge |
| rsp_id | Output, 32 bits | Accepted request identity |
| result_registers | Output, 32 lanes × 8 words × 32 bits | Returned FP32 values in measured positions |
| outstanding | Output, signed 32 bits | Accepted operations not yet retired |
| SLOTS | Default 2 | Positive synthetic queue capacity inherited from Section 4.16 |
| LATENCY, INTERVAL | Defaults 17 and 3 cycles | Positive synthetic completion delay and acceptance interval; uncalibrated |

**Storage, transition and timing contract.** The adapter itself has no stored state. Its wiring is combinational; the matrix component owns the queue and captures the entire input at acceptance. Inputs must remain stable while a valid request waits. Returned words and identity remain stable while a valid response waits. Reset clears the downstream queue, so neither request acceptance nor response validity is asserted during reset. No additional cycle is charged for rearrangement. Physical operand delivery and native issue timing remain unknown.

For example, lane 0's first packed A word contains row 0, columns 0 and 1. Its second A word contains row 8, columns 0 and 1. Its first B word contains rows 0 and 1, column 0. The first returned FP32 word is row 0, column 0. These mappings describe values; they do not imply that NVIDIA physically routes all words in one cycle.

**Inline behavior.** The package below defines the recovered positions. Element indices identify row-major matrix words; the index is sixteen times the row plus the column.

```systemverilog
// Observed sm120/CUDA12.8 BF16 WMMA row-major m16n16k16 layout.
// Describes operand contents, not physical register-bank routing or latency.
package native_bf16_layout;
  function automatic int a_element_index(input int lane, input int element);
    int row, col;
    row = lane / 4 + 8 * ((element / 2) % 2);
    col = 2 * (lane % 4) + element % 2 + 8 * (element / 4);
    return row * 16 + col;
  endfunction
  function automatic int b_element_index(input int lane, input int element);
    int row, col;
    row = 2 * (lane % 4) + element % 2 + 8 * ((element / 2) % 2);
    col = lane / 4 + 8 * (element / 4);
    return row * 16 + col;
  endfunction
  function automatic int c_element_index(input int lane, input int element);
    return a_element_index(lane, element);
  endfunction
  function automatic int native_c_element(input int hmma_half, input int word);
    return 4 * hmma_half + word;
  endfunction
  function automatic int native_b_word(input int hmma_half, input int word);
    return 2 * hmma_half + word;
  endfunction
endpackage
```

The adapter connects those positions to the arithmetic component.

```systemverilog
// Supported sm120 BF16 WMMA operand layout recovered in functional_mapping_002.
// Timing and accumulation convention are inherited from numerical_matrix_pipeline.
// This is an operation-level adapter, not a model of two physical HMMA pipelines.
module native_bf16_adapter #(
 parameter int SLOTS=2,LATENCY=17,INTERVAL=3,ARITHMETIC_MODE=0
)(
 input logic clk,rst,req_valid,output logic req_ready,
 input logic [31:0] req_id,
 input logic [31:0] a_registers[32][4],b_registers[32][4],
 input logic [31:0] c_registers[32][8],
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,result_registers[32][8],output int outstanding
);
 import native_bf16_layout::*;
 logic [15:0] a_words[256],b_words[256];
 logic [31:0] accumulator_words[256],result_words[256];
 for(genvar lane=0;lane<32;lane++) begin: lanes
  for(genvar element=0;element<8;element++) begin: elements
   assign a_words[a_element_index(lane,element)] =
     a_registers[lane][element/2][16*(element%2)+:16];
   assign b_words[b_element_index(lane,element)] =
     b_registers[lane][element/2][16*(element%2)+:16];
   assign accumulator_words[c_element_index(lane,element)] = c_registers[lane][element];
   assign result_registers[lane][element] = result_words[c_element_index(lane,element)];
  end
 end
 numerical_matrix_pipeline #(.SLOTS(SLOTS),.LATENCY(LATENCY),.INTERVAL(INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) matrix (
  .clk,.rst,.req_valid,.req_ready,.req_id,.a_words,.b_words,.accumulator_words,
  .rsp_valid,.rsp_ready,.rsp_id,.result_words,.outstanding
 );
endmodule
```

**Verification and remaining gaps.** Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_native_matrix.py` from the project root. Six matrix patterns run under two synthetic timing configurations. The test uses the saved hardware position tables independently of the package formulas and compares 3,072 output words with an exact rational arithmetic oracle. It also checks queue bounds, identity, stalled-response values, minimum configured delay, reset and duplicate-identity rejection. The receipt is `numerical/native_matrix_verification.json`.

The default numerical oracle still uses sequential FP32 fused multiply-add. ARITHMETIC_MODE=1 propagates to the measured aligned-dot candidate; see Section 4.16 for its supported domain and counterexample. Successful tests establish the adapter's connection to that reference, rather than hardware equivalence for arbitrary floating-point inputs. Other shapes, numerical formats, layouts, physical operand queues and separate HMMA completions remain unsupported. These results strengthen F032 and F033 without closing either broad parameter field.

### 4.20. Shared broadcast service-work decoder

**Purpose and supported request.** Count the service packages required by a naturally aligned 128-bit shared-memory read in which every active lane requests the same vector. A service package is the work counted by the profiler's shared-load wavefront metric. The measured count is not an intrinsic instruction latency. This component supplies a work quantity for future shared-service integration; it does not deliver stored operand values or advance a queue.

The first experiment kept the address and instruction fixed and changed the active lanes. Eight neighboring readers required one package, but eight distributed readers required two. A rule based only on bytes or access width therefore fails. The inferred rule counts occupied lane halves: lanes 0–15 and lanes 16–31. Five new masks, measured after freezing that rule, all matched. In particular, lanes 0 and 31 alone require two packages. Evidence is preserved in `parameter_sweep/masked_shared/analysis.json` and `confirmation_analysis.json`.

**Quantitative contract and interfaces.**

| Port or property | Direction or value | Definition |
|---|---|---|
| active_mask | Input, 32 bits | Bit i indicates whether lane i participates |
| common_byte_address | Input, 32 bits | Shared address requested by every participating lane; divisible by 16 |
| address_legal | Output, 1 bit | Address meets the required 16-byte alignment |
| service_packages | Output, 2 bits | 0 for no readers, 1 for one occupied lane half, 2 for both; 0 for illegal alignment |
| Stored state and reset | None | Combinational work calculation |
| Clocked latency | None introduced | No measured result latency or acceptance interval is claimed |

A caller must inspect address_legal before using the work count. Zero output on illegal alignment denotes a rejected request, not a free hardware operation. The caller must also establish that this is a same-vector LDS128 read; the interface cannot check addresses that it never receives. Ordinary vector reads with different addresses, stores, LDSM and cross-warp arbitration are outside the contract.

**Inline behavior.**

```systemverilog
// Measured/inferred service work for naturally aligned same-vector LDS.128.
// Zero-cycle combinational work decoder; neither latency nor bank-port model.
module shared_broadcast_work(
 input logic [31:0] active_mask,
 input logic [31:0] common_byte_address,
 output logic address_legal,
 output logic [1:0] service_packages
);
 assign address_legal=common_byte_address[3:0]==0;
 assign service_packages=address_legal?
   ({1'b0,|active_mask[15:0]}+{1'b0,|active_mask[31:16]}):2'b00;
endmodule
```

**Verification and limits.** Run `python studies/rtx5090_gemm_milp/rtl/components/verify_shared_broadcast_work.py`. Python and SystemVerilog reproduce the ten measured masks; additional checks cover no active lanes and illegal alignment. The receipt is `components/shared_broadcast_work_verification.json`. The ten observations support an inferred rule for this operation family, rather than an exhaustive test of all masks. They do not identify bank ports, physical queue capacity or cycle cost. F052 remains partially identified, and the rule is not yet connected to the complete GPU model.

### 4.21. Clocked shared storage connected to matrix execution

**Role and connections.** This subsystem connects stored BF16 values to the measured normal and transposed LDSM x4 operand maps, then to Section 4.19's numerical adapter. Shared writes initialize actual words. A matrix request waits until every word referenced by its row addresses is initialized. Once accepted, the numerical component captures the operands, so subsequent writes cannot change the in-flight result. This closes a value-delivery connection; it does not implement the complete instruction, cache, barrier or block-dispatch path.

The input supplies 32 row addresses for A and 32 for B. Each address points to eight contiguous 16-bit values and must be divisible by 16. A uses the normal shared-to-register map; B uses its transposed form. All 32 lanes participate. Reversed, swapped and repeated row addresses are supported. The recovered map is backed by 518 hardware cases in `discovery_rounds/ldsm_mapping_003`, not by an assumed general vector-load layout.

**Quantitative configuration.**

| Parameter or structure | Value | Evidence and restriction |
|---|---:|---|
| SHARED_BYTES | 102400 default | Queried maximum shared allocation per SM; a caller selects the modeled region, not an inferred carveout policy |
| Tested regions | 1024 and 102400 bytes | The 1024-byte operand buffers sit at each region's upper boundary; simulation configurations |
| Region restrictions | At least 1024 bytes, multiple of 16 | Explicit model requirement |
| Stored words | SHARED_BYTES / 2 | 16-bit values, each with one initialization bit |
| Logical write interface | 1 halfword per accepted edge | Simulation interface; not a physical shared-bank port count |
| Collective operand read | 256 halfwords for A and 256 for B | Functional value selection; physical service and return delay are not modeled here |
| SLOTS | 2 default | Synthetic matrix queue capacity inherited from Section 4.16 |
| LATENCY, INTERVAL | 17 and 3 cycles default | Synthetic matrix delay and acceptance interval; no LDSM timing has been calibrated |

**Interfaces and admission.**

| Port | Direction and width | Meaning |
|---|---|---|
| clk, rst | Input, 1 bit each | Common clock and synchronous reset |
| write_valid, write_ready | Input/output, 1 bit each | Accept one shared halfword at a rising edge when both are high |
| write_byte_address | Input, 32 bits | Even byte address wholly inside the modeled region |
| write_data | Input, 16 bits | BF16 bits stored at that address |
| req_valid, req_ready | Input/output, 1 bit each | Accept one complete matrix operand/address packet |
| req_id | Input, 32 bits | Unique identity while outstanding |
| a_row_addresses, b_row_addresses | Input, 32 × 32 bits each | Per-lane row pointers; each complete 16-byte row must lie inside the region |
| c_registers | Input, 32 lanes × 8 FP32 words | Initial accumulators in the measured result positions |
| operands_initialized | Output, 1 bit | Every referenced shared halfword has been written since reset |
| addresses_legal | Output, 1 bit | Every row has legal alignment and bounds |
| rsp_valid, rsp_ready | Output/input, 1 bit each | Return and retirement handshake |
| rsp_id, result_registers | Output, 32 bits and 32 × 8 × 32 bits | Captured identity and computed values |
| outstanding | Output, signed 32 bits | Accepted matrix requests not yet retired |

Request addresses, accumulators and identity must remain stable while a valid request waits. The write interface may fill missing operands during that wait. Invalid writes or valid requests with illegal row addresses terminate simulation explicitly. Valid row addresses with uninitialized words instead cause a readiness stall. Duplicate rows are legal reads. A valid stalled result keeps its identity and values stable.

**State, reset and simultaneous events.** The subsystem stores halfwords and initialization bits. Reset clears the bits and the downstream matrix queue; memory bits themselves need not be zeroed because unwritten values cannot be consumed. Combinational address selection produces packed operand words from the pre-edge storage. The downstream component owns accepted work and numerical result storage.

A same-edge write does not bypass storage. Suppose one referenced word is missing before edge E. The matrix request is not accepted at E, even if the write at E initializes that word. The new value is available after E, so the request may be accepted at E+1 if the matrix queue allows it. If an already initialized word is overwritten at an acceptance edge, the captured operand uses its pre-edge value. These are explicit simulation ordering rules, not measurements of an RTX bypass path.

No extra physical delay is assigned to LDSM selection. Its separate request queue, bank service, return timing and native completion remain missing. The shared service-work decoder in Section 4.20 applies to ordinary LDS128 broadcasts and must not be substituted for LDSM.

**Inline functional address map.**

```systemverilog
// Functional address placement observed on sm120, four 8x8 b16 matrices.
// Each source lane supplies one 16-byte-aligned row address.
// No latency, pipeline or physical bank-port assumptions are introduced.
package ldsm_x4_layout;
 function automatic int source_lane(input bit transpose, input int out_lane, input int word, input int halfword);
  if(transpose) return word*8 + 2*(out_lane%4) + halfword;
  return word*8 + out_lane/4;
 endfunction
 function automatic int byte_offset(input bit transpose, input int out_lane, input int halfword);
  if(transpose) return 2*(out_lane/4);
  return 4*(out_lane%4)+2*halfword;
 endfunction
endpackage
```

**Inline connected behavior.**

```systemverilog
// Clocked shared-value storage connected to measured LDSM operand placement.
// Logical single-halfword write port and ideal collective reads are model choices.
// Shared-service latency, bank arbitration and separate LDSM completion are absent.
module shared_matrix_pipeline #(
 parameter int SHARED_BYTES=102400,SLOTS=2,LATENCY=17,INTERVAL=3,ARITHMETIC_MODE=0
)(
 input logic clk,rst,
 input logic write_valid,output logic write_ready,
 input logic [31:0] write_byte_address,input logic [15:0] write_data,
 input logic req_valid,output logic req_ready,input logic [31:0] req_id,
 input logic [31:0] a_row_addresses[32],b_row_addresses[32],
 input logic [31:0] c_registers[32][8],
 output logic operands_initialized,addresses_legal,
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,result_registers[32][8],output int outstanding
);
 localparam int HALFWORDS=SHARED_BYTES/2;
 logic [15:0] memory[HALFWORDS];logic initialized[HALFWORDS];
 logic [31:0] a_registers[32][4],b_registers[32][4];
 logic matrix_ready;
 initial if(SHARED_BYTES<1024||SHARED_BYTES%16)
  $fatal(1,"Shared region must be a multiple of16 bytes and at least1024 bytes");
 assign write_ready=!rst&&write_byte_address[0]==0&&write_byte_address<=SHARED_BYTES-2;
 assign req_ready=!rst&&addresses_legal&&operands_initialized&&matrix_ready;
 always_comb begin
  addresses_legal=1;operands_initialized=1;
  for(int lane=0;lane<32;lane++) begin
   if(a_row_addresses[lane][3:0]!=0||a_row_addresses[lane]>SHARED_BYTES-16||
      b_row_addresses[lane][3:0]!=0||b_row_addresses[lane]>SHARED_BYTES-16)
    addresses_legal=0;
  end
  for(int lane=0;lane<32;lane++) for(int word=0;word<4;word++) begin
   a_registers[lane][word]=0;b_registers[lane][word]=0;
   if(addresses_legal) for(int halfword=0;halfword<2;halfword++) begin
    int a_index,b_index;
    a_index=int'(a_row_addresses[ldsm_x4_layout::source_lane(0,lane,word,halfword)])/2+
      ldsm_x4_layout::byte_offset(0,lane,halfword)/2;
    b_index=int'(b_row_addresses[ldsm_x4_layout::source_lane(1,lane,word,halfword)])/2+
      ldsm_x4_layout::byte_offset(1,lane,halfword)/2;
    operands_initialized=operands_initialized&&initialized[a_index]&&initialized[b_index];
    if(initialized[a_index]) a_registers[lane][word][16*halfword+:16]=memory[a_index];
    if(initialized[b_index]) b_registers[lane][word][16*halfword+:16]=memory[b_index];
   end
  end
  if(!addresses_legal) operands_initialized=0;
 end
 always_ff @(posedge clk) begin
  if(rst) begin
   for(int i=0;i<HALFWORDS;i++) initialized[i]<=0;
  end else begin
   if(write_valid&&!write_ready) $fatal(1,"Invalid shared write address");
   if(req_valid&&!addresses_legal) $fatal(1,"Invalid LDSM row address");
   if(write_valid&&write_ready) begin
    memory[write_byte_address/2]<=write_data;initialized[write_byte_address/2]<=1;
   end
  end
 end
 native_bf16_adapter #(.SLOTS(SLOTS),.LATENCY(LATENCY),.INTERVAL(INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) matrix (
  .clk,.rst,.req_valid(req_valid&&addresses_legal&&operands_initialized),.req_ready(matrix_ready),
  .req_id,.a_registers,.b_registers,.c_registers,
  .rsp_valid,.rsp_ready,.rsp_id,.result_registers,.outstanding
 );
 // Reads and initialization checks use pre-edge storage. A same-edge final
 // write cannot admit a waiting matrix operation until a later edge.
endmodule
```

**Verification and remaining gaps.** Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_shared_matrix.py`. Six arithmetic patterns each use four row-address arrangements under two synthetic timing configurations and two storage capacities, for 72 operations and 18,432 checked FP32 outputs. The test places the buffers against the upper address boundary, keeps a genuinely referenced word until the final write, checks that issue waits, overwrites an operand after acceptance, holds the result response, retires it, and resets storage validity. Three negative cases reject odd write addresses, unaligned rows and out-of-range rows. Evidence and source hashes are in `numerical/shared_matrix_verification.json`.

An initial test incorrectly required unrelated words to be initialized before a repeated-row request could proceed. The corrected test delays a word actually referenced by that request; the model's readiness rule did not change. This failure is preserved in `numerical/shared_initial_test_failure.json`.

ARITHMETIC_MODE propagates through shared storage and native operand mapping to the numerical component. Existing integration checks use mode 0; separate mode-1 checks match saved hardware results for the cancellation family. Full arbitrary-input arithmetic remains unresolved. These checks establish connected reference execution and the measured value map, rather than independent RTX timing accuracy. Global-memory input/output, register allocation and operand collection, instruction scheduling, separate native matrix completions, barriers, caches, shared-bank contention and multi-block execution still need integration.

### 4.22. Supported native LDSM descriptor decoder

**Role and connections.** This combinational decoder takes the two 64-bit words of a native instruction and exposes the register-direct shared matrix-load descriptor. It does not fetch instructions, track a program counter or issue a load. The downstream instruction controller must enforce active-lane and readiness conditions before accepting the decoded request.

| Port | Direction and width | Meaning |
|---|---|---|
| low_word, high_word | Input, 64 bits each | Native instruction encoding |
| supported | Output, 1 bit | Descriptor lies within the implemented subset |
| transpose | Output, 1 bit | Normal or transposed shared-to-register map |
| register_words | Output, 3 bits | One, two or four destination words per lane |
| destination_register, address_register | Output, 8 bits each | Destination base and shared-address register numbers |

**Functional rule.** The low 16-bit signature is `0x783b`; destination and address registers occupy low-word bits 23:16 and 31:24. High-word bits 9:8 encode one, two or four destination words, and bit 14 selects transpose. Other admitted formatting bits must match the inline mask. Register 255 is not a legal address register here, and the destination span cannot extend into it. Eight observed encodings verify these fields. Scheduling-control bits are not interpreted. This does not establish a complete decoder for all combinations that the mask would admit.

**State and timing.** There is no stored state, clock, reset or handshake. Outputs recompute from input bits. No physical decode delay is assigned. Treat `supported=0` as rejection rather than an operation with zero latency. Predicated forms, address offsets, other opcodes and full scheduling controls remain unsupported.

**Inline behavior.**

```systemverilog
// Partial descriptor decoder for six measured direct-register sm120 LDSM forms.
// Does not decode predicates, address offsets, scheduling controls or other opcodes.
module native_ldsm_decode(
 input logic [63:0] low_word,high_word,
 output logic supported,transpose,
 output logic [2:0] register_words,
 output logic [7:0] destination_register,address_register
);
 always_comb begin
  supported=0;transpose=0;register_words=0;
  destination_register=low_word[23:16];address_register=low_word[31:24];
  if(low_word[15:0]==16'h783b&&low_word[63:32]==0&&
     (high_word[15:0]&16'hbcff)==0&&high_word[9:8]!=3) begin
   register_words=3'(1<<high_word[9:8]);transpose=high_word[14];
   supported=int'(destination_register)+int'(register_words)<=255&&address_register!=255;
  end
 end
endmodule
```

**Verification.** `python studies/rtx5090_gemm_milp/rtl/components/verify_native_ldsm_decode.py` checks eight measured descriptors and five unsupported controls. Source hashes and exact encodings are preserved in `components/native_ldsm_decode_verification.json`. F010 is partially identified; neither physical decode delay nor the complete instruction vocabulary is established.

### 4.23. LDSM shared service-work decoder

**Role and connections.** This combinational block calculates the shared-memory work of an aligned all-lane native LDSM request. It receives row addresses and the number of matrices, and supplies a work count to a future clocked shared service controller. It is separate from value mapping in Section 4.21. An address group cannot be replaced by a generic LDS128 broadcast rule.

| Port | Direction and width | Meaning |
|---|---|---|
| row_byte_addresses | Input, 32 × 32 bits | Shared byte address supplied by each lane |
| matrix_count | Input, 3 bits | One, two or four matrices |
| request_legal | Output, 1 bit | Supported matrix count and 16-byte alignment |
| service_packages | Output, 6 bits | Sum of group service work, at most 32 |

**Functional rule and state.** Each active group has eight provider lanes. Equal row addresses within a group merge. Address bits 6:4 identify a bank quartet; count distinct rows in each quartet and use the maximum count as that group’s work. Sum the work of the first one, two or four groups. Equal addresses in different groups remain separate. The block has no stored state, reset or arbitration. It does not validate shared capacity or partial-lane legality; callers must supply those checks.

**Timing meaning.** The work count is not an intrinsic result latency. In the measured single-warp x4 load-and-sum loop, an extra package adds two SM cycles relative to the four-package case. Six fresh timing predictions match this incremental rule. The baseline includes consuming arithmetic and loop scheduling. Independent issue rate, queue depth, cross-warp contention and base return delay remain unknown. Do not apply the two-cycle increment to a GEMM unless its relevant execution path has been verified.

**Inline behavior.**

```systemverilog
// Inferred LDSM x1/x2/x4 all-lane aligned-row service work, not latency.
// Count provider groups separately; identical rows within a group are merged.
module ldsm_service_work(
 input logic [31:0] row_byte_addresses[32],
 input logic [2:0] matrix_count,
 output logic request_legal,output logic [5:0] service_packages
);
 always_comb begin
  request_legal=matrix_count==1||matrix_count==2||matrix_count==4;
  for(int lane=0;lane<32;lane++)
   if(row_byte_addresses[lane][3:0]!=0) request_legal=0;
  service_packages=0;
  if(request_legal) for(int group=0;group<4;group++) begin
   int group_max;group_max=0;
   if(group<int'(matrix_count)) begin
    for(int quartet=0;quartet<8;quartet++) begin
     int distinct_rows;distinct_rows=0;
     for(int row=0;row<8;row++) begin
      bit unique_row;unique_row=1;
      for(int earlier=0;earlier<row;earlier++)
       if(row_byte_addresses[group*8+row]==row_byte_addresses[group*8+earlier]) unique_row=0;
      if(unique_row&&int'(row_byte_addresses[group*8+row][6:4])==quartet)
       distinct_rows++;
     end
     if(distinct_rows>group_max) group_max=distinct_rows;
    end
    service_packages=6'(int'(service_packages)+group_max);
   end
  end
 end
endmodule
```

**Verification and transfer limits.** `python studies/rtx5090_gemm_milp/rtl/components/verify_ldsm_service_work.py` checks the 24 original measured configurations and invalid alignment/count controls. Hardware confirmation adds six new address cases, and six additional untouched timing cases verify the incremental delay. The confirmation evidence supports duplicate-row merging within a group; the original component receipt predates that confirmation. These narrow results strengthen F052 and partially identify T020. They do not establish intrinsic shared-bank ports or a full-chip timing model.

### 4.24. Optimized-library evidence boundary

A disassembled forward-compatible cuBLASLt kernel contains LDSM, but its presence in the shipped library does not establish that a particular workload selects it. The later `discovery_rounds/executed_library_006` experiment records an actually executed cuBLASLt kernel and numerical output. Its LDS128 sites belong to the output epilogue. Its input path uses scalar `LD.E` descriptors whose detailed interpretation is still being investigated. Consequently neither those LDS128 sites nor the unselected forward-compatible LDSM path may be used to explain current GEMM input timing without further evidence.

### 4.25. Completion-driven numerical sector cache

**Role and configuration.** This separate cache replaces neither the original timing-only read_cache nor the entire GPU hierarchy. It stores actual data under a 128-byte line tag with four independently valid 32-byte sectors. SETS and WAYS are configurable baseline choices; their physical RTX values remain unknown. The directed test uses two sets, one way and one pending request. Requests read one naturally aligned 32-bit word and return both that word and its complete 256-bit sector. The sector output lets a consumer extract multiple requested halfwords from one actual return. Stores, coherence, atomics, concurrent misses and sector-consumer merging are unsupported.

| Interface | Signals and widths | Acceptance/completion rule |
|---|---|---|
| Word request | req_valid/req_ready; req_id and req_byte_address, 32 bits each | Accepted only while idle; address must be divisible by four |
| Word response | rsp_valid/rsp_ready; rsp_id/rsp_data, 32 bits each; rsp_sector_data, 256 bits; rsp_hit, one bit | Word and complete containing sector remain stable until consumed; identifies hit or filled miss |
| Backing sector request | backing_req_valid/backing_req_ready; ID/address, 32 bits each | Address is rounded down to 32 bytes; retained until accepted |
| Backing sector return | backing_rsp_valid/backing_rsp_ready; ID, 32 bits; data, 256 bits | Accepted only while waiting for the matching actual completion |
| Clock/reset | clk/rst, one bit each | Rising-edge updates; synchronous reset cancels pending work and invalidates all sectors |

**Stored state and transitions.** Each set and way owns a line-valid bit, tag, four sector-valid bits and four 256-bit data sectors. A pending record retains the selected set, way, sector, word, ID and tag. IDLE accepts a word request. A valid sector produces a registered response; an absent sector enters SEND, where the backing request remains stable under backpressure. After acceptance, WAIT_RETURN holds the request without producing data. Only an ID-matched backing response writes sector data and its validity bit, then enters RESPONSE. RESPONSE keeps data and ID stable until the consumer accepts them. A full pending slot never accepts a same-edge replacement.

A different sector under an existing tag is still a miss until that sector returns. A new tag clears the victim’s previous sector-valid bits on fill. Selection prefers an invalid way and otherwise uses a rotating victim pointer; this is a model policy, not recovered NVIDIA replacement. Reset discards pending work, and late returns are not accepted while idle. The backing provider must cancel old obligations or retain unique IDs across reset before admitting new work.

**Timing and invariants.** The cache assigns no fitted miss timestamp: its backing component owns miss service and the actual return determines completion. Registered hit response timing is an implementation choice. No RTX lookup latency, queue depth, set count or associativity is inferred. Every accepted request produces one matching response unless reset cancels it; a backing completion with the wrong ID and an unaligned word request terminate simulation.

**Inline behavior.**

```systemverilog
// Blocking numerical sector cache. Physical geometry:128B line,4x32B sectors.
// SETS/WAYS/replacement and single pending slot are explicit model choices.
module sector_read_cache #(parameter int SETS=2,WAYS=2)(
 input logic clk,rst,req_valid,output logic req_ready,
 input logic [31:0] req_id,req_byte_address,
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,rsp_data,output logic [255:0] rsp_sector_data,output logic rsp_hit,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic [31:0] backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic [31:0] backing_rsp_id,input logic [255:0] backing_rsp_data
);
 typedef enum logic [1:0]{IDLE,SEND,WAIT_RETURN,RESPONSE} state_t;
 state_t state;
 logic line_valid[SETS][WAYS];logic [31:0] tags[SETS][WAYS];
 logic [3:0] sector_valid[SETS][WAYS];logic [255:0] sectors[SETS][WAYS][4];
 int next_victim[SETS],pending_set,pending_way,pending_sector,pending_word;
 logic pending_newline;logic [31:0] pending_tag,pending_id,pending_address;
 logic [31:0] result_data;logic [255:0] result_sector_data;logic result_hit;
 int selected_set,selected_sector,selected_word,selected_way;
 logic [31:0] selected_tag;logic tag_found,selected_hit;
 initial if(SETS<1||WAYS<1||(SETS&(SETS-1))!=0) $fatal(1,"Invalid sector cache geometry");
 always_comb begin
  selected_set=int'((req_byte_address>>7)%SETS);
  selected_tag=req_byte_address>>(7+$clog2(SETS));
  selected_sector=int'((req_byte_address>>5)&3);
  selected_word=int'((req_byte_address>>2)&7);
  selected_way=next_victim[selected_set];tag_found=0;selected_hit=0;
  // A matching line owns all four sectors even when the requested sector is absent.
  for(int w=0;w<WAYS;w++)if(line_valid[selected_set][w]&&tags[selected_set][w]==selected_tag)begin
   selected_way=w;tag_found=1;selected_hit=sector_valid[selected_set][w][selected_sector];
  end
  if(!tag_found)for(int w=WAYS-1;w>=0;w--)if(!line_valid[selected_set][w])selected_way=w;
 end
 assign req_ready=!rst&&state==IDLE;
 assign rsp_valid=!rst&&state==RESPONSE;
 assign rsp_id=pending_id;assign rsp_data=result_data;assign rsp_sector_data=result_sector_data;assign rsp_hit=result_hit;
 assign backing_req_valid=!rst&&state==SEND;
 assign backing_req_id=pending_id;assign backing_req_byte_address=pending_address;
 assign backing_rsp_ready=!rst&&state==WAIT_RETURN;
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;pending_id<=0;pending_address<=0;result_data<=0;result_sector_data<=0;result_hit<=0;
   pending_set<=0;pending_way<=0;pending_sector<=0;pending_word<=0;pending_tag<=0;pending_newline<=0;
   for(int s=0;s<SETS;s++)begin next_victim[s]<=0;for(int w=0;w<WAYS;w++)begin
    line_valid[s][w]<=0;tags[s][w]<=0;sector_valid[s][w]<=0;
   end end
  end else case(state)
   IDLE:if(req_valid&&req_ready)begin
    if(req_byte_address[1:0]!=0)$fatal(1,"Unaligned cache word request");
    pending_id<=req_id;pending_address<={req_byte_address[31:5],5'b0};
    pending_set<=selected_set;pending_way<=selected_way;pending_sector<=selected_sector;pending_word<=selected_word;
    pending_tag<=selected_tag;pending_newline<=!tag_found;result_hit<=selected_hit;
    if(selected_hit)begin result_sector_data<=sectors[selected_set][selected_way][selected_sector];result_data<=sectors[selected_set][selected_way][selected_sector][selected_word*32+:32];state<=RESPONSE;end
    else state<=SEND;
   end
   SEND:if(backing_req_valid&&backing_req_ready)state<=WAIT_RETURN;
   WAIT_RETURN:if(backing_rsp_valid&&backing_rsp_ready)begin
    if(backing_rsp_id!=pending_id)$fatal(1,"Cache backing completion identity mismatch");
    if(pending_newline)begin
     line_valid[pending_set][pending_way]<=1;tags[pending_set][pending_way]<=pending_tag;
     sector_valid[pending_set][pending_way]<=4'(1<<pending_sector);
     next_victim[pending_set]<=(pending_way+1)%WAYS;
    end else sector_valid[pending_set][pending_way][pending_sector]<=1;
    sectors[pending_set][pending_way][pending_sector]<=backing_rsp_data;
    result_sector_data<=backing_rsp_data;result_data<=backing_rsp_data[pending_word*32+:32];state<=RESPONSE;
   end
   RESPONSE:if(rsp_valid&&rsp_ready)state<=IDLE;
   default:$fatal(1,"Invalid cache state");
  endcase
 end
 // No result becomes valid before actual backing completion. No duplicate miss
 // service is charged here; the connected backing component owns its timing.
endmodule
```

**Verification.** Run `python studies/rtx5090_gemm_milp/rtl/components/verify_sector_read_cache.py`. Two different sectors of one line miss separately, then repeated reads hit and return the correct word. Additional checks delay backing acceptance and completion, hold result backpressure, evict the line, cancel a pending request on reset, reject a stale idle return, and check request/response conservation including cancellation. Wrong-ID and unaligned-address controls fail as expected. `components/sector_read_cache_verification.json` preserves source hashes and outputs. This verifies numerical cache behavior and its interfaces; integration with the GPU’s memory controller and physical timing remains incomplete.

### 4.26. Connected cached-word staging and numerical matrix execution

**Purpose and scope.** The [cached shared matrix pipeline](numerical/cached_shared_matrix_pipeline.sv) connects returned backing-memory data to actual shared-memory values, then to one warp's 16 × 16 × 16 BF16 matrix operation with FP32 accumulation. A backing response carries a complete 32-byte sector. The cache extracts one 32-bit word, and the wrapper writes its two BF16 halfwords into shared storage on successive clock edges. Matrix inputs use the supported LDSM operand mapping described in section 4.21. This is a behavioral integration path; it does not implement the actual cuBLASLt generic `LD.E`/`MOVM` input path, a complete SM, or full-chip scheduling.

**Quantitative starting configuration.** The defaults are 64 sets, eight ways, 128 bytes per cache line and four independently valid 32-byte sectors: 65,536 bytes of cache data. Shared storage has 32,768 bytes. There is one staged word in flight; its 32-bit payload becomes two 16-bit writes. The numerical child allows two outstanding matrix requests. Its default latency is 17 clock cycles and its initiation interval is three cycles. These values are development choices, not calibrated RTX 5090 latencies. Arithmetic mode zero preserves the existing sequential-FP32 reference; mode one selects the experimentally bounded aligned-dot candidate from section 4.16. The arithmetic mode must be selected for its supported input domain.

| Interface | Payload and direction | Acceptance or completion |
|---|---|---|
| Word staging request | Input: 32-bit ID, global byte address and shared byte address | Accepted only when `stage_valid && stage_ready` at a clock edge; global address must be four-byte aligned, shared address two-byte aligned and fit both halfwords |
| Staging completion | Output: 32-bit original ID and cache-hit flag | Held with `stage_done_valid` until `stage_done_ready`; reports completion of both shared writes |
| Backing request | Output: 32-bit ID and sector-aligned byte address | Ready/valid handshake is owned by the completion-driven cache; request remains stable under backpressure |
| Backing return | Input: matching 32-bit ID and 256-bit sector data | Cache fills only after actual response acceptance; provider must retain payload while not ready |
| Matrix request | Input: 32-bit ID; 32 A-row addresses, 32 B-row addresses, and 32 × 8 FP32 accumulator registers | Accepted through the shared/numerical child only when addresses are legal, operands initialized and request capacity available |
| Matrix return | Output: 32-bit ID and 32 × 8 FP32 result registers | Numerical child holds valid ID and values until `rsp_ready` |

**Clocked behavior and ordering.** In `IDLE`, an accepted staging request saves its ID and destination, then enters `LOW_HALF`. That state waits for an actual cache response and writes bits 15:0. `HIGH_HALF` writes bits 31:16 at destination plus two bytes. The cache response is acknowledged only with this second accepted write, so both writes consume one stable word. `DONE` holds the staging completion. After its acceptance, the wrapper returns to `IDLE`. A cache miss therefore cannot produce shared values merely because a guessed delay elapsed.

An accepted staging request wins over a matrix request on the same edge. Matrix admission is blocked while staging or its completion is pending. The shared child reads pre-edge storage, so an operation cannot use a final halfword write on that same edge. Already accepted matrix operations have captured their operands; later staging does not change those operands. This does not implement a hardware-wide ordering rule for arbitrary kernels.

**Reset and protocol obligations.** Reset clears the wrapper, invalidates the cache and shared initialization state, and resets the numerical child. Pending work is canceled. The backing provider must flush pre-reset requests and returns; numeric request IDs do not encode reset generations. A stale response arriving during a new transaction with a reused ID cannot be distinguished by this model. Invalid staging addresses and mismatched active response IDs are fatal protocol errors.

**Verification boundary.** The [connected verification receipt](numerical/cached_shared_matrix_verification.json) passes 14,336 FP32 output-word comparisons: 24 sequential-reference cases and four exact-integer identity cases in aligned-dot mode, each with synthetic backing delays of two and 13 cycles. The extra 11 cycles per sector request propagate exactly: 768 requests add 8,448 cycles, and 128 requests add 1,408 cycles. Checks cover initialized-operand gating, sector reuse and request conservation, IDs, held staging and numerical completions, reset invalidation, and rejection of unaligned or wrong-ID requests. Source hashes match the tested sources. This validates the connected numerical fixture and completion-driven timing behavior; it does not establish universal NVIDIA arithmetic, physical cache latency, or independent RTX 5090 runtime accuracy.

**Authoritative behavioral implementation.** The following source is copied exactly from `numerical/cached_shared_matrix_pipeline.sv`.

```systemverilog
// Behavioral integration: backing return -> cached word -> two shared halfwords.
// Geometry, blocking staging, and LATENCY are explicit model choices, not RTX timing.
module cached_shared_matrix_pipeline #(
 parameter int SETS=64,WAYS=8,SHARED_BYTES=32768,SLOTS=2,
 parameter int LATENCY=17,INTERVAL=3,ARITHMETIC_MODE=0
)(
 input logic clk,rst,
 input logic stage_valid,output logic stage_ready,
 input logic [31:0] stage_id,stage_global_byte_address,stage_shared_byte_address,
 output logic stage_done_valid,input logic stage_done_ready,
 output logic [31:0] stage_done_id,output logic stage_done_hit,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic [31:0] backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic [31:0] backing_rsp_id,input logic [255:0] backing_rsp_data,
 input logic req_valid,output logic req_ready,input logic [31:0] req_id,
 input logic [31:0] a_row_addresses[32],b_row_addresses[32],
 input logic [31:0] c_registers[32][8],
 output logic operands_initialized,addresses_legal,
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,result_registers[32][8],output int outstanding
);
 typedef enum logic [1:0] {IDLE,LOW_HALF,HIGH_HALF,DONE} state_t;
 state_t state;
 logic cache_req_ready,cache_rsp_valid,cache_rsp_ready,cache_rsp_hit;
 logic [31:0] cache_rsp_id,cache_rsp_data,saved_id,saved_shared_address;
 logic saved_hit,write_valid,write_ready,matrix_ready,matrix_admit;
 logic [31:0] write_byte_address;logic [15:0] write_data;
 logic stage_legal,stage_accept;
 initial if(SHARED_BYTES<1024||SHARED_BYTES%16!=0)
  $fatal(1,"Shared region must be a multiple of16 bytes and at least1024 bytes");
 assign stage_legal=stage_global_byte_address[1:0]==0 &&
                    stage_shared_byte_address[0]==0 &&
                    stage_shared_byte_address<=SHARED_BYTES-4;
 assign stage_ready=!rst&&state==IDLE&&cache_req_ready&&stage_legal;
 assign stage_accept=stage_valid&&stage_ready;
 assign stage_done_valid=!rst&&state==DONE;
 assign stage_done_id=saved_id;
 assign stage_done_hit=saved_hit;
 assign write_valid=!rst&&cache_rsp_valid&&(state==LOW_HALF||state==HIGH_HALF);
 assign write_byte_address=saved_shared_address+(state==HIGH_HALF?32'd2:32'd0);
 assign write_data=state==HIGH_HALF?cache_rsp_data[31:16]:cache_rsp_data[15:0];
 // Keep the cache response stable until its second halfword is stored.
 assign cache_rsp_ready=!rst&&state==HIGH_HALF&&write_ready;
 // A same-edge stage admission has priority over a matrix admission.
 assign matrix_admit=!rst&&state==IDLE&&!stage_accept;
 assign req_ready=matrix_admit&&matrix_ready;
 always_ff @(posedge clk) begin
  if(rst)begin state<=IDLE;saved_id<=0;saved_shared_address<=0;saved_hit<=0;end
  else begin
   if(stage_valid&&state==IDLE&&!stage_legal)
    $fatal(1,"Unaligned or out-of-bounds staging address");
   if(cache_rsp_valid&&(state==LOW_HALF||state==HIGH_HALF)&&cache_rsp_id!=saved_id)
    $fatal(1,"Stage/cache response identity mismatch");
   case(state)
    IDLE:if(stage_accept)begin
     saved_id<=stage_id;saved_shared_address<=stage_shared_byte_address;state<=LOW_HALF;
    end
    LOW_HALF:if(write_valid&&write_ready)state<=HIGH_HALF;
    HIGH_HALF:if(write_valid&&write_ready)begin saved_hit<=cache_rsp_hit;state<=DONE;end
    DONE:if(stage_done_valid&&stage_done_ready)state<=IDLE;
    default:$fatal(1,"Invalid staging state");
   endcase
  end
 end
 sector_read_cache #(.SETS(SETS),.WAYS(WAYS)) cache(
  .clk,.rst,.req_valid(stage_valid&&state==IDLE&&stage_legal),.req_ready(cache_req_ready),
  .req_id(stage_id),.req_byte_address(stage_global_byte_address),
  .rsp_valid(cache_rsp_valid),.rsp_ready(cache_rsp_ready),.rsp_id(cache_rsp_id),
  .rsp_data(cache_rsp_data),.rsp_hit(cache_rsp_hit),
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,
  .backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data
 );
 shared_matrix_pipeline #(.SHARED_BYTES(SHARED_BYTES),.SLOTS(SLOTS),
  .LATENCY(LATENCY),.INTERVAL(INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) shared_matrix(
  .clk,.rst,.write_valid,.write_ready,.write_byte_address,.write_data,
  .req_valid(req_valid&&matrix_admit),.req_ready(matrix_ready),.req_id,
  .a_row_addresses,.b_row_addresses,.c_registers,.operands_initialized,.addresses_legal,
  .rsp_valid,.rsp_ready,.rsp_id,.result_registers,.outstanding
 );
endmodule
```

### 4.27. One-tile GEMM reduction and acknowledged output stores

**Purpose.** The [tile controller](numerical/gemm_tile_controller.sv) computes one 16 × 16 output tile, starting with zero FP32 accumulators. Let `STAGES` be the number of 16-element reduction steps. The reduction length is `K = 16 × STAGES`. Each step obtains actual input values through section 4.26, waits for an actual matrix result and carries that result into the next step. After the final step, 256 FP32 words are stored through an acknowledged output interface. There is one active launch. This is a serialized functional reproducer with cycle-driven interfaces, not a recovered native GPU schedule, full-chip scheduling, or the inspected cuBLASLt generic `LD.E`/`MOVM` kernel.

**Input layout and capacities.** Each step consumes 1,024 bytes: 512 bytes for its 16 × 16 BF16 A fragment, followed by 512 bytes for its B fragment. Each fragment is packed as four row-major 8 × 8 subtiles. For an element at row `r` and column `c`, both from zero to 15, its halfword index inside the fragment is `64 × (floor(r/8) + 2 × floor(c/8)) + 8 × (r modulo 8) + (c modulo 8)`. Multiply by two to obtain its byte offset. This is explicitly not ordinary 16 × 16 row-major storage. Step `s` starts at `input_base + 1024 × s`; B adds another 512 bytes. The global input base must be 1,024-byte aligned. The output is ordinary row-major FP32 storage, occupies 1,024 bytes and must have a four-byte-aligned base. Input and output address spans must not wrap 32-bit addressing or overlap; overlap is rejected because write-cache coherence is absent.

The controller defaults to two steps (`K = 32`), 32 KiB shared storage, a 64-set/eight-way sector cache, two numerical request slots, arithmetic mode one, a 16-cycle numerical delay and a four-cycle issue interval. Geometry and timing defaults are provisional choices. The serial controller uses only one matrix request at a time, so the two request slots do not imply concurrent matrix execution in this path.

| Interface | Payload | Contract |
|---|---|---|
| Launch | 32-bit ID, input base and output base | Accepted on `launch_valid && launch_ready`; readiness is limited to idle state |
| Backing read | 32-bit request ID and aligned sector address; returned 256-bit data | Connected directly to section 4.26; actual responses drive cache filling and staging |
| Output store | 32-bit ID, byte address and FP32 value | Accepted on `store_req_valid && store_req_ready`; payload remains stable while stalled |
| Output acknowledgment | 32-bit matching store ID | One outstanding store; acknowledgment must represent the provider's actual defined completion, not merely issuance |
| Launch completion | Original 32-bit launch ID | Held until `done_ready`; cannot precede acknowledgment of the final output word |

**State transitions.** `STAGE_SEND` issues one of the step's 256 packed 32-bit input words. `STAGE_WAIT` waits until both shared halfwords are stored and the staging ID matches. After word 255, `MATRIX_SEND` submits the current accumulator. `MATRIX_WAIT` waits for a matching result and copies all 32 × 8 result registers into the accumulator. It then starts the next reduction step or begins output retirement. `STORE_SEND` and `STORE_WAIT` issue and acknowledge each of the 256 output values, using the supported native accumulator-to-row-major mapping. Only the last matching acknowledgment transitions to `DONE`.

Reset clears the controller, accumulator and connected path and cancels outstanding work. External read and store providers must flush pre-reset transactions. IDs contain no reset epoch. Replay launches may reuse cache entries only while backing input data remains unchanged; external writes to cached inputs require invalidation that this controller does not implement.

**Verification.** The [tile verification receipt](numerical/gemm_tile_verification.json) passes 2,048 FP32 output comparisons across reduction lengths 32 and 48, two launches per configuration, and synthetic backing delays of two and 13 cycles. Replay launches reuse cached sectors. Added delay propagates exactly: 64 sector requests add 704 cycles; 96 requests add 1,056 cycles. Tests stall output-store acceptance for two cycles per word, check actual output-store acknowledgments, and reject a wrong store ID, unaligned base and overlapping input/output spans. Source hashes match the tested files. Numerical fixtures use small integers with exact intermediate sums; they do not characterize general NVIDIA floating-point behavior. Runtime has not been validated against hardware.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_gemm_tile.py` from the project root.

**Authoritative behavioral implementation.** The following source is copied exactly from `numerical/gemm_tile_controller.sv`.

```systemverilog
// One 16x16 GEMM tile with K=16*STAGES and zero initial accumulator.
// Input per stage: A512B then B512B, each four row-major 8x8 tiles in
// tile order (row-half + 2*column-half), not ordinary matrix storage.
// Serialized staging/stores and latency defaults are simulation choices.
module gemm_tile_controller #(
 parameter int STAGES=2,SETS=64,WAYS=8,SHARED_BYTES=32768,SLOTS=2,
 parameter int LATENCY=16,INTERVAL=4,ARITHMETIC_MODE=1
)(
 input logic clk,rst,launch_valid,output logic launch_ready,
 input logic [31:0] launch_id,input_base,output_base,
 output logic done_valid,input logic done_ready,output logic [31:0] done_id,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic [31:0] backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic [31:0] backing_rsp_id,input logic [255:0] backing_rsp_data,
 output logic store_req_valid,input logic store_req_ready,
 output logic [31:0] store_req_id,store_req_byte_address,store_req_data,
 input logic store_rsp_valid,output logic store_rsp_ready,
 input logic [31:0] store_rsp_id
);
 typedef enum logic [3:0]{IDLE,STAGE_SEND,STAGE_WAIT,MATRIX_SEND,
  MATRIX_WAIT,STORE_SEND,STORE_WAIT,DONE} state_t;
 state_t state;
 logic [31:0] saved_launch_id,saved_input_base,saved_output_base;
 int stage_number,word_number,store_number;
 logic stage_valid,stage_ready,stage_done_valid,stage_done_ready,stage_done_hit;
 logic [31:0] stage_id,stage_global_address,stage_shared_address,stage_done_id;
 logic matrix_valid,matrix_ready,matrix_rsp_valid,matrix_rsp_ready;
 logic [31:0] matrix_id,matrix_rsp_id;
 logic [31:0] a_addresses[32],b_addresses[32];
 logic [31:0] accumulator[32][8],matrix_results[32][8];
 logic operands_initialized,addresses_legal;int outstanding;
 initial if(STAGES<1||STAGES>65535)$fatal(1,"Invalid stage count");
 assign launch_ready=!rst&&state==IDLE;
 assign done_valid=!rst&&state==DONE;assign done_id=saved_launch_id;
 assign stage_valid=!rst&&state==STAGE_SEND;
 assign stage_id=32'(stage_number*256+word_number);
 assign stage_global_address=saved_input_base+32'(stage_number*1024+word_number*4);
 assign stage_shared_address=32'(word_number*4);
 assign stage_done_ready=!rst&&state==STAGE_WAIT;
 assign matrix_valid=!rst&&state==MATRIX_SEND;assign matrix_id=32'(stage_number);
 assign matrix_rsp_ready=!rst&&state==MATRIX_WAIT;
 assign store_req_valid=!rst&&state==STORE_SEND;
 assign store_req_id=32'(store_number);
 assign store_rsp_ready=!rst&&state==STORE_WAIT;
 assign store_req_byte_address=saved_output_base+
  32'(4*native_bf16_layout::c_element_index(store_number/8,store_number%8));
 assign store_req_data=accumulator[store_number/8][store_number%8];
 always_comb begin
  for(int lane=0;lane<32;lane++)begin
   a_addresses[lane]=32'(lane*16);b_addresses[lane]=32'(512+lane*16);
  end
 end
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;saved_launch_id<=0;saved_input_base<=0;saved_output_base<=0;
   stage_number<=0;word_number<=0;store_number<=0;
   for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)accumulator[lane][word]<=0;
  end else case(state)
   IDLE:if(launch_valid&&launch_ready)begin
    if(input_base[9:0]!=0||output_base[1:0]!=0)
     $fatal(1,"Unaligned GEMM launch base address");
    if({1'b0,input_base}+33'(STAGES*1024)>33'h100000000 ||
       {1'b0,output_base}+33'd1024>33'h100000000)
     $fatal(1,"GEMM address span exceeds 32-bit address space");
    if({1'b0,output_base}<{1'b0,input_base}+33'(STAGES*1024)&&
       {1'b0,input_base}<{1'b0,output_base}+33'd1024)
     $fatal(1,"Overlapping input/output requires unsupported cache write coherence");
    saved_launch_id<=launch_id;saved_input_base<=input_base;saved_output_base<=output_base;
    stage_number<=0;word_number<=0;store_number<=0;
    for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)accumulator[lane][word]<=0;
    state<=STAGE_SEND;
   end
   STAGE_SEND:if(stage_valid&&stage_ready)state<=STAGE_WAIT;
   STAGE_WAIT:if(stage_done_valid&&stage_done_ready)begin
    if(stage_done_id!=stage_id)$fatal(1,"Staging completion identity mismatch");
    if(word_number==255)begin word_number<=0;state<=MATRIX_SEND;end
    else begin word_number<=word_number+1;state<=STAGE_SEND;end
   end
   MATRIX_SEND:if(matrix_valid&&matrix_ready)state<=MATRIX_WAIT;
   MATRIX_WAIT:if(matrix_rsp_valid&&matrix_rsp_ready)begin
    if(matrix_rsp_id!=matrix_id)$fatal(1,"Matrix completion identity mismatch");
    for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)
     accumulator[lane][word]<=matrix_results[lane][word];
    if(stage_number==STAGES-1)begin store_number<=0;state<=STORE_SEND;end
    else begin stage_number<=stage_number+1;word_number<=0;state<=STAGE_SEND;end
   end
   STORE_SEND:if(store_req_valid&&store_req_ready)state<=STORE_WAIT;
   STORE_WAIT:if(store_rsp_valid&&store_rsp_ready)begin
    if(store_rsp_id!=store_req_id)$fatal(1,"Store completion identity mismatch");
    if(store_number==255)state<=DONE;
    else begin store_number<=store_number+1;state<=STORE_SEND;end
   end
   DONE:if(done_valid&&done_ready)state<=IDLE;
   default:$fatal(1,"Invalid GEMM controller state");
  endcase
 end
 cached_shared_matrix_pipeline #(.SETS(SETS),.WAYS(WAYS),.SHARED_BYTES(SHARED_BYTES),
  .SLOTS(SLOTS),.LATENCY(LATENCY),.INTERVAL(INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) path(
  .clk,.rst,.stage_valid,.stage_ready,.stage_id,
  .stage_global_byte_address(stage_global_address),.stage_shared_byte_address(stage_shared_address),
  .stage_done_valid,.stage_done_ready,.stage_done_id,.stage_done_hit,
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,
  .backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data,
  .req_valid(matrix_valid),.req_ready(matrix_ready),.req_id(matrix_id),
  .a_row_addresses(a_addresses),.b_row_addresses(b_addresses),.c_registers(accumulator),
  .operands_initialized,.addresses_legal,
  .rsp_valid(matrix_rsp_valid),.rsp_ready(matrix_rsp_ready),.rsp_id(matrix_rsp_id),
  .result_registers(matrix_results),.outstanding
 );
 // Backing provider must flush pre-reset transactions; IDs have no reset epoch.
 // Store acknowledgement means actual externally defined completion, not launch.
endmodule
```

### 4.28. Compiled-library shared-address layout package

**Purpose and evidence boundary.** The [library shared layout package](numerical/library_shared_layout.sv) implements the reconstructed software address rules of the selected non-transposed library kernel family. It is separate from the LDSM-based tile controller in section 4.27. These rules describe where compiled code puts operands, not GPU memory capacity, physical bank organization or instruction latency. The actual library input path uses scalar generic `LD.E` reads and register rearrangement; this package alone does not execute that instruction schedule.

**Constants and index domains.** The reconstructed shared footprint is 37,376 bytes. A has 32 rows with 528-byte pitch; B has 128 rows with 80-byte pitch. B begins at byte 16,896 and its second slot adds 10,240 bytes. Both pitches contain 16 bytes of row padding. The two A slots instead differ by 256 bytes inside the packed row. Each stage has eight matrix reduction steps of 16 elements. Producer thread IDs range from zero to 127; slot IDs are zero or one; producer group IDs are zero to three. Consumer warp IDs are zero to three, lanes zero to 31, reduction-step IDs zero to seven and word IDs zero to three. Invalid indices cause a fatal error.

| Function | Returned value |
|---|---|
| `producer_a(thread_id, slot, group_id)` | Shared byte address of a thread's 16-byte A producer fragment |
| `producer_b(thread_id, slot, group_id)` | Shared byte address of its 16-byte B producer fragment |
| `consumer_a(warp_id, lane, slot, kstep, word_id)` | Shared byte address of one scalar four-byte A consumer word |
| `consumer_b(warp_id, lane, slot, kstep, word_id)` | Shared byte address of one scalar four-byte B consumer word before the separately modeled register permutation |

**Behavior and timing.** These are deterministic integer address functions. They store no state and perform no ready/valid transaction. Evaluating a function does not assign physical address-generation latency. A native instruction model must charge the compiled arithmetic, dependency and memory-service work at its own boundaries, rather than treating these functions as a measured zero-cycle GPU instruction.

**Verification status.** The [verification receipt](numerical/library_shared_layout_verification.json) passes 18,432 address comparisons against the reconstructed Python layout and rejects an invalid index. Both source hashes match the verified files. This validates the ported software functions; it does not establish dynamic native execution timing or a complete library kernel model. The separately extracted [static native operand schedule](discovery_rounds/compiled_operand_schedule.json) contains 333 instructions, including 72 `LD.E`, 36 `MOVM` and 16 `HMMA` instructions. Its dynamic loop replay remains incomplete because pointer and control dependencies are unresolved.

**Authoritative behavioral implementation.** The following source is copied exactly from `numerical/library_shared_layout.sv`.

```systemverilog
// Software address layout reconstructed from the selected library kernel.
// These constants do not identify private GPU hardware capacities.
package library_shared_layout;
  localparam integer SHARED_BYTES=37376;
  localparam integer A_PITCH=528, A_ROWS=32, A_STAGE_K=128;
  localparam integer B_PITCH=80, B_ROWS=128, B_COLUMNS=32;
  localparam integer B_START=16896, B_SLOT=10240;
  function automatic integer producer_a(input integer thread_id, slot, group_id);
    begin
      if(thread_id<0 || thread_id>=128 || slot<0 || slot>=2 || group_id<0 || group_id>=4)
        $fatal(1,"producer_a index outside layout contract");
      producer_a=A_PITCH*(thread_id/16)+16*(thread_id%16)+256*slot+4224*group_id;
    end
  endfunction
  function automatic integer producer_b(input integer thread_id, slot, group_id);
    begin
      if(thread_id<0 || thread_id>=128 || slot<0 || slot>=2 || group_id<0 || group_id>=4)
        $fatal(1,"producer_b index outside layout contract");
      producer_b=B_START+B_PITCH*(thread_id/4)+16*(thread_id%4)+B_SLOT*slot+2560*group_id;
    end
  endfunction
  function automatic integer consumer_a(input integer warp_id, lane, slot, kstep, word_id);
    integer delta;
    begin
      if(warp_id<0 || warp_id>=4 || lane<0 || lane>=32 || slot<0 || slot>=2 || kstep<0 || kstep>=8 || word_id<0 || word_id>=4)
        $fatal(1,"consumer_a index outside layout contract");
      case(word_id) 0:delta=0;1:delta=4224;2:delta=16;3:delta=4240;endcase
      consumer_a=8448*(warp_id%2)+256*slot+32*kstep+A_PITCH*(lane/4)+4*(lane%4)+delta;
    end
  endfunction
  function automatic integer consumer_b(input integer warp_id, lane, slot, kstep, word_id);
    integer delta;
    begin
      if(warp_id<0 || warp_id>=4 || lane<0 || lane>=32 || slot<0 || slot>=2 || kstep<0 || kstep>=8 || word_id<0 || word_id>=4)
        $fatal(1,"consumer_b index outside layout contract");
      case(word_id) 0:delta=0;1:delta=640;2:delta=16;3:delta=656;endcase
      consumer_b=32*(warp_id/2)+B_SLOT*slot+1280*kstep+B_START+B_PITCH*(lane/4)+4*(lane%4)+delta;
    end
  endfunction
endpackage
```

### 4.29. Selected-library generic shared operands and measured register permutation

**Purpose and distinction from section 4.26.** The [generic matrix pipeline](numerical/library_generic_matrix_pipeline.sv) replaces the earlier LDSM operand path with the selected library's scalar shared-word addresses and measured `MOVM` halfword permutation. It stores actual BF16 values, gathers A and B operands, and passes them to the existing numerical matrix adapter. This corrects a functional input-path mismatch. It does not reproduce the native instructions' issue timing: the scalar reads are modeled as one ideal collective snapshot, and the permutation is an ideal function.

**Storage and request fields.** Shared storage defaults to 37,376 bytes, the reconstructed software footprint from section 4.28. Each write supplies a two-byte-aligned 16-bit value. Each matrix request contains a 32-bit ID, two-bit warp ID, one-bit slot ID, three-bit reduction-step ID, and 32 × 8 FP32 accumulator words. Warp IDs zero to three select four 16 × 16 output tiles: row half is `warp_id modulo 2`, and column half is `floor(warp_id/2)`. Each of two slots contains eight steps of 16 reduction elements, giving 256 reduction elements across both slots. A request returns 32 × 8 FP32 words in the supported native accumulator layout.

The defaults are two numerical request slots, a 16-cycle numerical delay, a four-cycle issue interval and arithmetic mode one. Delay and issue interval are synthetic. The shared read and register permutation have no separately calibrated latency, bandwidth limit, queue or arbitration here. Their omission must remain visible when comparing this model with GPU time.

**Operand construction.** For each of 32 lanes and four packed words, the pipeline evaluates `consumer_a` and `consumer_b` from section 4.28. Each word reads two adjacent BF16 halfwords. A is packed directly. B first creates a 256-halfword raw vector, indexed by `8 × lane + 2 × word + halfword`. The measured permutation maps each destination halfword after `MOVM` to its raw source index before `MOVM`. The destination values are then packed into four 32-bit B registers per lane. The 256-entry table is a bijection and matches the saved measured mapping exactly.

**Interfaces and clocked state.** Write and matrix interfaces use ready/valid acceptance at the clock edge. A matrix request is ready only when every referenced halfword is initialized, every address is legal, reset is inactive and the numerical child can accept it. That child snapshots A, B and C on acceptance. Later shared writes therefore do not change an in-flight computation. A same-edge write uses pre-edge storage; the final initializing write cannot enable admission until a later edge. Result IDs and values remain held while the consumer applies backpressure. Reset invalidates shared initialization and cancels pending numerical results. Memory payload bits need not be cleared because invalid words cannot supply accepted operands.

**Independent verification.** The [generic-path receipt](numerical/library_generic_matrix_verification.json) passes 66,048 FP32 output comparisons under two synthetic timing configurations: delay/interval 16/4 and 37/9 cycles. Each configuration checks 129 operations. Ordinary matrix multiplication supplies expectations independently of the consumer-address and permutation implementation. Four warp tiles and 16 reduction steps assemble a 32 × 32 output with reduction length 256. Fixtures use small integer BF16 inputs and exact FP32 sums; this is not a test of general NVIDIA rounding behavior. Protocol checks cover a missing final operand delaying admission, request IDs, accepted snapshots surviving shared overwrite, held outputs, carried accumulation and reset cancellation. An odd-byte shared write is rejected. Receipt source hashes match the verified files.

The scalar shared-read and `MOVM` **functional value path** is now connected to numerical accumulation. Global staging/cache delivery, output stores and native multiwarp scheduling are not connected to this adapter. No new physical parameter identification, GPU measurement or timing calibration follows from these local checks.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_library_generic_matrix.py` from the project root.

**Authoritative library address wrapper.** The shared storage, readiness and numerical snapshot now live in the common explicit-address module; this wrapper supplies the padded compiled-library addresses.

```systemverilog
// Address wrapper for the verified cuBLASLt nn shared layout; software layout only.
module library_generic_matrix_pipeline #(
 parameter int SHARED_BYTES=37376,SLOTS=2,LATENCY=16,INTERVAL=4,ARITHMETIC_MODE=1
)(
 input logic clk,rst,
 input logic write_valid,output logic write_ready,
 input logic [31:0] write_byte_address,input logic [15:0] write_data,
 input logic req_valid,output logic req_ready,input logic [31:0] req_id,
 input logic [1:0] warp_id,input logic slot,input logic [2:0] k_step,
 input logic [31:0] c_registers[32][8],
 output logic operands_initialized,addresses_legal,
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,result_registers[32][8],output int outstanding
);
 logic [31:0] a_word_addresses[32][4],b_word_addresses[32][4];
 initial if(SHARED_BYTES<37376)$fatal(1,"Library shared storage too small");
 always_comb begin
  for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)begin
   a_word_addresses[lane][word]=32'(library_shared_layout::consumer_a(int'(warp_id),lane,int'(slot),int'(k_step),word));
   b_word_addresses[lane][word]=32'(library_shared_layout::consumer_b(int'(warp_id),lane,int'(slot),int'(k_step),word));
  end
 end
 generic_shared_matrix_pipeline #(.SHARED_BYTES(SHARED_BYTES),.SLOTS(SLOTS),
  .LATENCY(LATENCY),.INTERVAL(INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) path(
  .clk,.rst,.write_valid,.write_ready,.write_byte_address,.write_data,
  .req_valid,.req_ready,.req_id,.a_word_addresses,.b_word_addresses,.c_registers,
  .operands_initialized,.addresses_legal,.rsp_valid,.rsp_ready,.rsp_id,.result_registers,.outstanding
 );
endmodule
```

**Authoritative common generic shared-word module.** This module accepts 32 × 4 explicit byte addresses for each operand. The library wrapper and original studied-kernel wrapper share its initialization, address checks, measured permutation and numerical snapshot behavior.

```systemverilog
// Functional generic shared-word operand delivery with measured MOVM mapping.
// Plain generic shared-word reads and measured MOVM permutation; no LDSM.
// Reads are ideal collective snapshots. Generic-load/MOVM service timing,
// native hot-loop control, and private queues are NOT implemented here.
module generic_shared_matrix_pipeline #(
 parameter int SHARED_BYTES=37376,SLOTS=2,LATENCY=16,INTERVAL=4,ARITHMETIC_MODE=1
)(
 input logic clk,rst,
 input logic write_valid,output logic write_ready,
 input logic [31:0] write_byte_address,input logic [15:0] write_data,
 input logic req_valid,output logic req_ready,input logic [31:0] req_id,
 input logic [31:0] a_word_addresses[32][4],b_word_addresses[32][4],
 input logic [31:0] c_registers[32][8],
 output logic operands_initialized,addresses_legal,
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,result_registers[32][8],output int outstanding
);
 localparam int HALFWORDS=SHARED_BYTES/2;
 logic [15:0] memory[HALFWORDS];logic initialized[HALFWORDS];
 logic [15:0] raw_b[256];
 logic [31:0] a_registers[32][4],b_registers[32][4];
 int a_indices[32][4],b_indices[32][4];
 logic matrix_ready;
 initial if(SHARED_BYTES<4||SHARED_BYTES%2!=0)
  $fatal(1,"Library shared storage too small or not halfword aligned");
 assign write_ready=!rst&&write_byte_address[0]==0&&write_byte_address<=SHARED_BYTES-2;
 assign req_ready=!rst&&addresses_legal&&operands_initialized&&matrix_ready;
 always_comb begin
  addresses_legal=1;operands_initialized=1;
  for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)begin
   a_indices[lane][word]=int'(a_word_addresses[lane][word]/2);
   b_indices[lane][word]=int'(b_word_addresses[lane][word]/2);
   if(a_word_addresses[lane][word][1:0]!=0||b_word_addresses[lane][word][1:0]!=0||
      a_word_addresses[lane][word]>SHARED_BYTES-4||b_word_addresses[lane][word]>SHARED_BYTES-4||
      a_indices[lane][word]<0||a_indices[lane][word]+1>=HALFWORDS||
      b_indices[lane][word]<0||b_indices[lane][word]+1>=HALFWORDS)addresses_legal=0;
  end
  for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)begin
   a_registers[lane][word]=0;b_registers[lane][word]=0;
   for(int halfword=0;halfword<2;halfword++)begin
    raw_b[lane*8+word*2+halfword]=0;
    if(addresses_legal)begin
     operands_initialized=operands_initialized&&
      initialized[a_indices[lane][word]+halfword]&&initialized[b_indices[lane][word]+halfword];
     if(initialized[a_indices[lane][word]+halfword])
      a_registers[lane][word][halfword*16+:16]=memory[a_indices[lane][word]+halfword];
     if(initialized[b_indices[lane][word]+halfword])
      raw_b[lane*8+word*2+halfword]=memory[b_indices[lane][word]+halfword];
    end
   end
  end
  // The table maps each post-transpose destination halfword to a raw source.
  for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)
   for(int halfword=0;halfword<2;halfword++)
    b_registers[lane][word][halfword*16+:16]=
     raw_b[library_movm_permutation::pre_index(lane*8+word*2+halfword)];
  if(!addresses_legal)operands_initialized=0;
 end
 always_ff @(posedge clk)begin
  if(rst)begin for(int i=0;i<HALFWORDS;i++)initialized[i]<=0;end
  else begin
   if(write_valid&&!write_ready)$fatal(1,"Invalid library shared write address");
   if(req_valid&&!addresses_legal)$fatal(1,"Invalid library matrix operand address");
   if(write_valid&&write_ready)begin
    memory[write_byte_address/2]<=write_data;initialized[write_byte_address/2]<=1;
   end
  end
 end
 native_bf16_adapter #(.SLOTS(SLOTS),.LATENCY(LATENCY),.INTERVAL(INTERVAL),
  .ARITHMETIC_MODE(ARITHMETIC_MODE)) matrix(
  .clk,.rst,.req_valid(req_valid&&addresses_legal&&operands_initialized),.req_ready(matrix_ready),
  .req_id,.a_registers,.b_registers,.c_registers,
  .rsp_valid,.rsp_ready,.rsp_id,.result_registers,.outstanding
 );
 // Adapter snapshots all values at acceptance. Same-edge writes use pre-edge
 // memory: a final initializing write permits admission only on a later edge.
endmodule
```

**Authoritative measured permutation package.** The literal table preserves the measured mapping without assuming an undocumented hardware transpose network.

```systemverilog
// Measured post-MOVM halfword position -> pre-MOVM position.
// Evidence SHA256 4a6b7aaeeb23a3f8812ec3f8f37982a777ba5220bd2d41937362c07a00a30096
// Functional lane/register contents only; no physical latency or routing claim.
package library_movm_permutation;
 function automatic int pre_index(input int post_index);
  case(post_index)
   0: return 0;
   1: return 32;
   2: return 2;
   3: return 34;
   4: return 4;
   5: return 36;
   6: return 6;
   7: return 38;
   8: return 64;
   9: return 96;
   10: return 66;
   11: return 98;
   12: return 68;
   13: return 100;
   14: return 70;
   15: return 102;
   16: return 128;
   17: return 160;
   18: return 130;
   19: return 162;
   20: return 132;
   21: return 164;
   22: return 134;
   23: return 166;
   24: return 192;
   25: return 224;
   26: return 194;
   27: return 226;
   28: return 196;
   29: return 228;
   30: return 198;
   31: return 230;
   32: return 1;
   33: return 33;
   34: return 3;
   35: return 35;
   36: return 5;
   37: return 37;
   38: return 7;
   39: return 39;
   40: return 65;
   41: return 97;
   42: return 67;
   43: return 99;
   44: return 69;
   45: return 101;
   46: return 71;
   47: return 103;
   48: return 129;
   49: return 161;
   50: return 131;
   51: return 163;
   52: return 133;
   53: return 165;
   54: return 135;
   55: return 167;
   56: return 193;
   57: return 225;
   58: return 195;
   59: return 227;
   60: return 197;
   61: return 229;
   62: return 199;
   63: return 231;
   64: return 8;
   65: return 40;
   66: return 10;
   67: return 42;
   68: return 12;
   69: return 44;
   70: return 14;
   71: return 46;
   72: return 72;
   73: return 104;
   74: return 74;
   75: return 106;
   76: return 76;
   77: return 108;
   78: return 78;
   79: return 110;
   80: return 136;
   81: return 168;
   82: return 138;
   83: return 170;
   84: return 140;
   85: return 172;
   86: return 142;
   87: return 174;
   88: return 200;
   89: return 232;
   90: return 202;
   91: return 234;
   92: return 204;
   93: return 236;
   94: return 206;
   95: return 238;
   96: return 9;
   97: return 41;
   98: return 11;
   99: return 43;
   100: return 13;
   101: return 45;
   102: return 15;
   103: return 47;
   104: return 73;
   105: return 105;
   106: return 75;
   107: return 107;
   108: return 77;
   109: return 109;
   110: return 79;
   111: return 111;
   112: return 137;
   113: return 169;
   114: return 139;
   115: return 171;
   116: return 141;
   117: return 173;
   118: return 143;
   119: return 175;
   120: return 201;
   121: return 233;
   122: return 203;
   123: return 235;
   124: return 205;
   125: return 237;
   126: return 207;
   127: return 239;
   128: return 16;
   129: return 48;
   130: return 18;
   131: return 50;
   132: return 20;
   133: return 52;
   134: return 22;
   135: return 54;
   136: return 80;
   137: return 112;
   138: return 82;
   139: return 114;
   140: return 84;
   141: return 116;
   142: return 86;
   143: return 118;
   144: return 144;
   145: return 176;
   146: return 146;
   147: return 178;
   148: return 148;
   149: return 180;
   150: return 150;
   151: return 182;
   152: return 208;
   153: return 240;
   154: return 210;
   155: return 242;
   156: return 212;
   157: return 244;
   158: return 214;
   159: return 246;
   160: return 17;
   161: return 49;
   162: return 19;
   163: return 51;
   164: return 21;
   165: return 53;
   166: return 23;
   167: return 55;
   168: return 81;
   169: return 113;
   170: return 83;
   171: return 115;
   172: return 85;
   173: return 117;
   174: return 87;
   175: return 119;
   176: return 145;
   177: return 177;
   178: return 147;
   179: return 179;
   180: return 149;
   181: return 181;
   182: return 151;
   183: return 183;
   184: return 209;
   185: return 241;
   186: return 211;
   187: return 243;
   188: return 213;
   189: return 245;
   190: return 215;
   191: return 247;
   192: return 24;
   193: return 56;
   194: return 26;
   195: return 58;
   196: return 28;
   197: return 60;
   198: return 30;
   199: return 62;
   200: return 88;
   201: return 120;
   202: return 90;
   203: return 122;
   204: return 92;
   205: return 124;
   206: return 94;
   207: return 126;
   208: return 152;
   209: return 184;
   210: return 154;
   211: return 186;
   212: return 156;
   213: return 188;
   214: return 158;
   215: return 190;
   216: return 216;
   217: return 248;
   218: return 218;
   219: return 250;
   220: return 220;
   221: return 252;
   222: return 222;
   223: return 254;
   224: return 25;
   225: return 57;
   226: return 27;
   227: return 59;
   228: return 29;
   229: return 61;
   230: return 31;
   231: return 63;
   232: return 89;
   233: return 121;
   234: return 91;
   235: return 123;
   236: return 93;
   237: return 125;
   238: return 95;
   239: return 127;
   240: return 153;
   241: return 185;
   242: return 155;
   243: return 187;
   244: return 157;
   245: return 189;
   246: return 159;
   247: return 191;
   248: return 217;
   249: return 249;
   250: return 219;
   251: return 251;
   252: return 221;
   253: return 253;
   254: return 223;
   255: return 255;
   default: begin $fatal(1,"MOVM permutation index out of range"); return 0; end
  endcase
 endfunction
endpackage
```

### 4.30. Original studied-GEMM shared operands and full reduction values

**Question and concrete target.** Does the original kernel that produced the largest model error deliver the correct matrix operands through its own generic shared-load path? The [studied wrapper](numerical/studied_gemm_matrix_pipeline.sv) reconstructs that path from [diagnostic 050 source](../diagnostic_050/gemm_checked.cu), rather than borrowing the padded cuBLASLt layout. Both use scalar generic shared reads and `MOVM`, but their shared addresses differ. This distinction matters: correct arithmetic with the wrong operand layout would not reproduce the workload being modeled.

**Geometry and storage.** `BM` and `BN` are the output-block row and column counts; `BK` is the reduction width held in one shared stage. Defaults are 32, 32 and 32. A occupies `2 × BM × BK` bytes, stored without row padding. B follows A and occupies `2 × BK × BN` bytes, also without padding. Shared operand storage is therefore 4,096 bytes for 32 × 32 output blocks and 7,168 bytes for 64 × 48 blocks at `BK = 32`. This is operand storage only; it excludes the original kernel's additional output scratch and does not establish total CTA allocation.

Each request selects one 16 × 16 fragment using `tile_index` and one 16-element reduction slice using `k_step`. There are `(BM/16) × (BN/16)` fragment tiles and `BK/16` slices. Fragment tiles are enumerated by output row first, with the column varying inside a row. Tile and reduction indices are checked before acceptance. `BM`, `BN` and `BK` must be positive multiples of 16; storage must fit the two operands. The wrapper computes explicit scalar word addresses and delegates actual value reads, measured `MOVM` permutation, initialization, result IDs and snapshot/reset behavior to the common module in section 4.29. Its default `TIMED_READS = 0` retains that path; selecting `TIMED_READS = 1` uses the completion-driven service wrapper in section 4.32. Read slots, package interval and return delay remain engineering choices. No LDSM operand path is used.

**Interfaces and timing.** Inputs are halfword shared writes, a ready/valid matrix request with 32-bit ID, tile/reduction indices, and 32 × 8 FP32 accumulator words. Outputs are readiness/initialization flags, held result ID and values, and numerical outstanding-request count. Acceptance snapshots the operands and accumulator. Later shared overwrites do not modify that request. Reset invalidates shared words and cancels numerical results. Defaults remain two numerical slots, synthetic delay/interval 16/4 cycles and the bounded arithmetic candidate. They are not physical generic-load or `MOVM` delays.

**Independent original-workload value checks.** The [verification receipt](numerical/studied_gemm_matrix_verification.json) passes **393,216 intermediate FP32 result-word comparisons** through reduction length 1,536. It tests the first CTA, at coordinate (0,0), for both 32 × 32 and 64 × 48 output blocks in the original global shape 2,048 × 2,112 × 1,536. Each has 48 shared stage frames and two 16-element slices per frame. The smaller block checks 384 fragment operations; the larger checks 1,152. These are first-CTA checks, not the entire global matrix output.

Inputs reproduce the original dyadic patterns: A's element at flattened global index `i` is `((i modulo 17) - 8)/16`; B's element is `((i modulo 13) - 6)/16`, using the original global strides. The independent oracle computes integer dot products and divides by 256; it does not call the consumer-address functions. Actual result registers supply each later accumulator. Invalid fragment and reduction indices are rejected for both geometries. All receipt source hashes match the verified files. The refactored library path retains its separate 66,048-word regression checks.

This closes a functional operand/value-path mismatch for the workload that motivated the error investigation. Global cache delivery, staging instructions, native warp scheduling, load/permutation service, barriers, residency and output stores remain unconnected for this wrapper. No hardware runtime prediction has been validated by these local checks. Physical evidence counts remain eight identified, 32 partial and 94 unknown fields.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_studied_gemm_matrix.py` for the untimed path, or add `--timed-reads` for completion-driven scalar reads. Both pass the 393,216-word original-workload checks.

**Authoritative studied-kernel address wrapper.**

```systemverilog
// Unpadded shared operand layout of diagnostic_050/gemm_checked.cu.
// Generic shared-word reads + measured MOVM; no LDSM or native service timing.
module studied_gemm_matrix_pipeline #(
 parameter int BM=32,BN=32,BK=32,SHARED_BYTES=2*BK*(BM+BN),
 parameter int SLOTS=2,LATENCY=16,INTERVAL=4,ARITHMETIC_MODE=1,
 parameter bit TIMED_READS=0,parameter int READ_SLOTS=4,SERVICE_INTERVAL=1,RETURN_DELAY=1
)(
 input logic clk,rst,
 input logic write_valid,output logic write_ready,
 input logic [31:0] write_byte_address,input logic [15:0] write_data,
 input logic req_valid,output logic req_ready,input logic [31:0] req_id,
 input logic [31:0] tile_index,k_step,
 input logic [31:0] c_registers[32][8],
 output logic operands_initialized,addresses_legal,
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,result_registers[32][8],output int outstanding
);
 localparam int TN=BN/16,TILES=(BM/16)*TN;
 logic [31:0] a_word_addresses[32][4],b_word_addresses[32][4];
 logic selection_legal,inner_ready,inner_addresses_legal,inner_initialized;
 initial if(BM<16||BN<16||BK<16||BM%16!=0||BN%16!=0||BK%16!=0||
  SHARED_BYTES<2*BK*(BM+BN))$fatal(1,"Invalid studied GEMM geometry");
 assign selection_legal=tile_index<TILES&&k_step<BK/16;
 assign req_ready=!rst&&selection_legal&&inner_ready;
 assign addresses_legal=selection_legal&&inner_addresses_legal;
 assign operands_initialized=selection_legal&&inner_initialized;
 always_comb begin
  for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)begin
   a_word_addresses[lane][word]=0;b_word_addresses[lane][word]=0;
   if(selection_legal)begin
    a_word_addresses[lane][word]=32'(2*BK*(16*(tile_index/TN)+lane/4)+
     32*k_step+4*(lane%4)+(word%2)*16*BK+(word/2)*16);
    b_word_addresses[lane][word]=32'(2*BM*BK+2*BN*(16*k_step+lane/4)+
     32*(tile_index%TN)+4*(lane%4)+(word%2)*16*BN+(word/2)*16);
   end
  end
 end
 always_ff @(posedge clk)if(!rst&&req_valid&&!selection_legal)
  $fatal(1,"Studied GEMM tile or reduction-step index out of bounds");
 generate if(TIMED_READS)begin:timed_path
 timed_generic_shared_matrix_pipeline #(.SHARED_BYTES(SHARED_BYTES),.SLOTS(SLOTS),
  .LATENCY(LATENCY),.INTERVAL(INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE),
  .READ_SLOTS(READ_SLOTS),.SERVICE_INTERVAL(SERVICE_INTERVAL),.RETURN_DELAY(RETURN_DELAY)) path(
  .clk,.rst,.write_valid,.write_ready,.write_byte_address,.write_data,
  .req_valid(req_valid&&selection_legal),.req_ready(inner_ready),.req_id,
  .a_word_addresses,.b_word_addresses,.c_registers,
  .operands_initialized(inner_initialized),.addresses_legal(inner_addresses_legal),
  .rsp_valid,.rsp_ready,.rsp_id,.result_registers,.outstanding
 );
 end else begin:ideal_path
 generic_shared_matrix_pipeline #(.SHARED_BYTES(SHARED_BYTES),.SLOTS(SLOTS),
  .LATENCY(LATENCY),.INTERVAL(INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) path(
  .clk,.rst,.write_valid,.write_ready,.write_byte_address,.write_data,
  .req_valid(req_valid&&selection_legal),.req_ready(inner_ready),.req_id,
  .a_word_addresses,.b_word_addresses,.c_registers,
  .operands_initialized(inner_initialized),.addresses_legal(inner_addresses_legal),
  .rsp_valid,.rsp_ready,.rsp_id,.result_registers,.outstanding
 );
 end endgenerate
endmodule
```

### 4.31. Completion-driven full-warp scalar shared-read service

**Purpose and operation.** The [shared-read service](components/warp_shared_read_service.sv) separates request admission, bank work, return delay and response delivery. One request contains 32 four-byte-aligned addresses, 32 input words and a 32-bit ID. The provider supplies an actual memory-value snapshot when the request is accepted. The service stores that snapshot, consumes the required bank-work packages, waits its configured return delay, then offers the saved words as a completion event. It does not look up shared storage itself.

**Measured work rule versus assumed timing.** For each of 32 banks, count the distinct requested four-byte words. Repeated reads of the same address are a broadcast and count once. The bank index is address bits 6:2. The number of packages is the largest distinct-word count across the banks, from one to 32. This scalar work-count rule is supported by the saved bank probes. It does not identify physical port counts, queue sizes or intrinsic latency.

The default queue holds four requests. A single modeled service port consumes one package per cycle (`SERVICE_INTERVAL = 1`); after the last package, it applies one additional cycle of return delay (`RETURN_DELAY = 1`). Capacity, first-in-first-out arbitration and both cycle settings are explicit engineering hypotheses. Increasing package count consumes more service opportunities; increasing return delay changes completion time separately. No fixed measured load latency is added on top of these hypotheses. For an isolated request accepted at edge `a`, its first package is serviced no earlier than edge `a + 1`. The final package edge starts the return counter; after `RETURN_DELAY` later edges, the response becomes valid. A continuously ready consumer acknowledges it on the following edge. Thus a one-package request with return delay `D` has earliest acknowledgment edge `a + D + 2`. Queue waiting and consumer backpressure can add delay. These edges describe the model contract, not measured GPU cycles.

**Interfaces and state.** Request and response use ready/valid acceptance. The six-bit combinational `request_packages` output reports the current offered request’s bank-work count; it is not an additional completion event or physical latency measurement. Each live slot stores its ID, 32 words, package count, return counter and admission sequence number. The oldest unserviced request receives the next service opportunity. Completed requests become eligible for response after their return counters expire. The oldest eligible response is presented; its slot remains live until acknowledgment. Held responses retain ID and data. Thus a slow response consumer can fill the four slots even after service finishes.

Admission uses pre-edge capacity: a slot retired on an edge becomes reusable next cycle. Duplicate live request IDs and misaligned addresses are rejected. Equal addresses must carry equal supplied snapshot values; inconsistent broadcast data is rejected. Reset cancels every live request and resets pacing; providers must treat canceled requests as canceled rather than expect a later completion. This is one shared read port with a FIFO policy, not a recovered NVIDIA scheduler or general multiport shared-memory implementation.

**Verification.** The [service receipt](components/warp_shared_read_service_verification.json) passes 320 word comparisons under service/return settings 1/9 and 3/1 cycles. Tests cover broadcasts and 2/4/32 packages, four concurrent requests, capacity backpressure, acceptance snapshots, FIFO IDs, stable stalled outputs, the exact isolated acknowledgment edge, reset cancellation/reclamation, and rejection of misalignment, duplicate IDs or inconsistent broadcast snapshot values. Receipt hashes preserve the tested source versions. These are local functional/timing-contract checks; no physical timing parameter is identified.

Run `python studies/rtx5090_gemm_milp/rtl/components/verify_warp_shared_read_service.py` from the project root.

**Authoritative behavioral implementation.**

```systemverilog
// Behavioral scalar shared-memory service. One request is one full warp.
// Bank-work rule is measured; capacities and cycle parameters are hypotheses.
// input_words are the memory snapshot supplied on the acceptance edge.
module warp_shared_read_service #(
 parameter int SLOTS=4,SERVICE_INTERVAL=1,RETURN_DELAY=1
)(
 input logic clk,rst,
 input logic req_valid,output logic req_ready,input logic [31:0] req_id,
 input logic [31:0] byte_addresses[32],input_words[32],
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,output_words[32],
 output int outstanding,output logic [5:0] request_packages
);
 logic live[SLOTS],serviced[SLOTS];
 logic [31:0] ids[SLOTS],values[SLOTS][32];
 int remaining[SLOTS],delay_left[SLOTS];
 longint unsigned sequence_number[SLOTS],next_sequence;
 int free_slot,service_slot,response_slot,pacing;
 logic legal;
 initial if(SLOTS<1||SERVICE_INTERVAL<1||RETURN_DELAY<1)
  $fatal(1,"Invalid shared service parameters");
 always_comb begin
  int largest;
  legal=1;largest=0;
  for(int lane=0;lane<32;lane++)if(byte_addresses[lane][1:0]!=0)legal=0;
  for(int bank=0;bank<32;bank++)begin
   int distinct_words;distinct_words=0;
   for(int lane=0;lane<32;lane++)begin
    bit first;first=1;
    for(int earlier=0;earlier<lane;earlier++)
     if(byte_addresses[lane]==byte_addresses[earlier])first=0;
    if(first&&int'(byte_addresses[lane][6:2])==bank)distinct_words++;
   end
   if(distinct_words>largest)largest=distinct_words;
  end
  request_packages=6'(largest);
  free_slot=-1;service_slot=-1;response_slot=-1;outstanding=0;
  for(int slot=0;slot<SLOTS;slot++)begin
   if(!live[slot]&&free_slot==-1)free_slot=slot;
   if(live[slot])begin
    outstanding++;
    if(!serviced[slot])begin
     if(service_slot==-1)service_slot=slot;
     else if(sequence_number[slot]<sequence_number[service_slot])service_slot=slot;
    end
    if(serviced[slot]&&delay_left[slot]==0)begin
     if(response_slot==-1)response_slot=slot;
     else if(sequence_number[slot]<sequence_number[response_slot])response_slot=slot;
    end
   end
  end
  req_ready=!rst&&legal&&free_slot!=-1;
  rsp_valid=!rst&&response_slot!=-1;rsp_id=0;
  for(int lane=0;lane<32;lane++)output_words[lane]=0;
  if(response_slot!=-1)begin
   rsp_id=ids[response_slot];
   for(int lane=0;lane<32;lane++)output_words[lane]=values[response_slot][lane];
  end
 end
 always_ff @(posedge clk)begin
  if(rst)begin
   next_sequence<=0;pacing<=0;
   for(int slot=0;slot<SLOTS;slot++)begin
    live[slot]<=0;serviced[slot]<=0;remaining[slot]<=0;delay_left[slot]<=0;
    sequence_number[slot]<=0;ids[slot]<=0;
   end
  end else begin
   if(req_valid&&!legal)$fatal(1,"Misaligned scalar shared request");
   if(pacing>0)pacing<=pacing-1;
   if(service_slot!=-1&&pacing==0)begin
    remaining[service_slot]<=remaining[service_slot]-1;
    pacing<=SERVICE_INTERVAL-1;
    if(remaining[service_slot]==1)begin
     serviced[service_slot]<=1;delay_left[service_slot]<=RETURN_DELAY;
    end
   end
   for(int slot=0;slot<SLOTS;slot++)
    if(live[slot]&&serviced[slot]&&delay_left[slot]>0)
     delay_left[slot]<=delay_left[slot]-1;
   if(rsp_valid&&rsp_ready)live[response_slot]<=0;
   // Admission uses pre-edge capacity. A retiring slot becomes free next cycle.
   if(req_valid&&req_ready)begin
    for(int lane=0;lane<32;lane++)for(int earlier=0;earlier<lane;earlier++)
     if(byte_addresses[lane]==byte_addresses[earlier]&&input_words[lane]!=input_words[earlier])
      $fatal(1,"Inconsistent shared broadcast snapshot");
    for(int slot=0;slot<SLOTS;slot++)
     if(live[slot]&&ids[slot]==req_id)$fatal(1,"Duplicate live shared request ID");
    live[free_slot]<=1;serviced[free_slot]<=0;ids[free_slot]<=req_id;
    remaining[free_slot]<=int'(request_packages);delay_left[free_slot]<=0;
    sequence_number[free_slot]<=next_sequence;next_sequence<=next_sequence+1;
    for(int lane=0;lane<32;lane++)values[free_slot][lane]<=input_words[lane];
   end
  end
 end
endmodule
```

### 4.32. Generic matrix operands delivered by shared-read completions

**Purpose.** The [timed generic matrix wrapper](numerical/timed_generic_shared_matrix_pipeline.sv) connects section 4.31's scalar bank-service events to numerical matrix operands. One external request generates eight full-warp scalar reads: four A word groups, then four B word groups. A numerical operation cannot be admitted merely because its addresses were computed; all eight matching read responses must arrive first.

**Quantitative configuration and interfaces.** Defaults are 4,096 bytes of shared storage, one external matrix request in flight, four shared-read slots, a one-cycle package service interval and one-cycle return delay. The numerical child has two request slots, synthetic latency/interval 16/4 and arithmetic mode one. An external request provides a 32-bit ID, 32 × 4 A byte addresses, 32 × 4 B byte addresses and 32 × 8 accumulator words. Each read-group response carries 32 words and a group ID from zero to seven. Final output has the original request ID and 256 FP32 result words. These quantities describe the model, not discovered silicon capacities.

**Snapshot and completion rules.** On external request acceptance, the wrapper snapshots every address, memory word and accumulator. This early snapshot is an engineering contract: it does not reproduce the memory-read time of each later native instruction or establish the GPU's read/write hazard behavior. Subsequent writes and changes to external addresses/C do not alter saved inputs. Reads are offered to the service queue in group order; capacity can stall admission. Each accepted completion sets one bit in an eight-bit received mask and stores the returned words. Duplicate, unissued or unknown read IDs are rejected. Only a complete mask allows matrix admission. B uses the measured permutation from section 4.29. The final numerical result remains held until acknowledgment, after which the wrapper accepts another external request.

All referenced input halfwords must be initialized and all scalar addresses aligned and in bounds before acceptance. Same-edge writes use pre-edge values. Reset invalidates shared words, cancels read and matrix requests, clears the completion mask and discards the saved external operation. Read-only service does not arbitrate concurrent writes for a physical shared-memory port.

**Verification.** The [timed-wrapper receipt](numerical/timed_generic_shared_matrix_verification.json) passes 256 output comparisons against an independent identity-matrix-times-column-values oracle. Checks verify eight actual read responses feeding arithmetic, accepted snapshots surviving intervening shared writes/address/C changes, held numerical output, uninitialized inputs blocking acceptance, and reset invalidation. Receipt hashes match the verified sources. The [timed original-workload receipt](numerical/studied_gemm_matrix_timed_verification.json) also passes 393,216 intermediate result-word checks for the first CTA of both original output-block geometries through reduction length 1,536. The untimed baseline separately reruns the same 393,216 checks after the refactor. Thus actual shared-read completions now gate the original workload's numerical accumulation; these synthetic-service tests do not validate hardware time. Generic instruction scheduling, calibrated shared return delay, `MOVM` timing and native queue structure remain absent. Physical evidence counts are unchanged.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_timed_generic_shared_matrix.py` from the project root.

**Authoritative behavioral implementation.**

```systemverilog
// Functional generic shared reads with explicit bank-service completion events.
// SERVICE_INTERVAL/RETURN_DELAY and matrix timing are engineering choices.
// One external matrix request collects eight independent scalar warp reads.
// All memory values snapshot at external matrix acceptance, not each later
// native load issue; intervening writes cannot affect this operation. This
// isolation is a model contract, not a discovered GPU memory hazard rule.
module timed_generic_shared_matrix_pipeline #(
 parameter int SHARED_BYTES=4096,SLOTS=2,LATENCY=16,INTERVAL=4,ARITHMETIC_MODE=1,
 parameter int READ_SLOTS=4,SERVICE_INTERVAL=1,RETURN_DELAY=1
)(
 input logic clk,rst,
 input logic write_valid,output logic write_ready,
 input logic [31:0] write_byte_address,input logic [15:0] write_data,
 input logic req_valid,output logic req_ready,input logic [31:0] req_id,
 input logic [31:0] a_word_addresses[32][4],b_word_addresses[32][4],
 input logic [31:0] c_registers[32][8],
 output logic operands_initialized,addresses_legal,
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,result_registers[32][8],output int outstanding
);
 localparam int HALFWORDS=SHARED_BYTES/2;
 typedef enum logic [1:0]{IDLE,COLLECT,MATRIX_SEND,MATRIX_WAIT} state_t;
 state_t state;
 logic [15:0] memory[HALFWORDS];logic initialized[HALFWORDS];
 logic [31:0] saved_addresses[8][32],saved_words[8][32],returned_words[8][32];
 logic [31:0] saved_c[32][8],saved_id;
 logic [7:0] received;int next_read;
 logic read_req_valid,read_req_ready,read_rsp_valid,read_rsp_ready;
 logic [31:0] read_req_id,read_rsp_id,read_addresses[32],read_inputs[32],read_outputs[32];
 logic [31:0] a_registers[32][4],b_registers[32][4];
 logic [15:0] raw_b[256];logic matrix_ready;int matrix_outstanding;
 initial if(SHARED_BYTES<4||SHARED_BYTES%2!=0)$fatal(1,"Invalid shared storage size");
 assign write_ready=!rst&&write_byte_address[0]==0&&write_byte_address<=SHARED_BYTES-2;
 assign req_ready=!rst&&state==IDLE&&addresses_legal&&operands_initialized;
 assign outstanding=state==IDLE?0:1;
 always_comb begin
  addresses_legal=1;operands_initialized=1;
  for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)begin
   if(a_word_addresses[lane][word][1:0]!=0||b_word_addresses[lane][word][1:0]!=0||
      a_word_addresses[lane][word]>SHARED_BYTES-4||b_word_addresses[lane][word]>SHARED_BYTES-4)
    addresses_legal=0;
  end
  if(addresses_legal)begin
   for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)
    operands_initialized=operands_initialized&&
     initialized[a_word_addresses[lane][word]/2]&&initialized[a_word_addresses[lane][word]/2+1]&&
     initialized[b_word_addresses[lane][word]/2]&&initialized[b_word_addresses[lane][word]/2+1];
  end else operands_initialized=0;
  for(int lane=0;lane<32;lane++)begin
   read_addresses[lane]=0;read_inputs[lane]=0;
   if(next_read<8)begin read_addresses[lane]=saved_addresses[next_read][lane];read_inputs[lane]=saved_words[next_read][lane];end
   for(int word=0;word<4;word++)begin
    a_registers[lane][word]=returned_words[word][lane];
    raw_b[lane*8+word*2]=returned_words[4+word][lane][15:0];
    raw_b[lane*8+word*2+1]=returned_words[4+word][lane][31:16];
   end
  end
  for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)for(int h=0;h<2;h++)
   b_registers[lane][word][16*h+:16]=raw_b[library_movm_permutation::pre_index(lane*8+word*2+h)];
 end
 assign read_req_valid=!rst&&state==COLLECT&&next_read<8;
 assign read_req_id=32'(next_read);
 assign read_rsp_ready=!rst&&state==COLLECT;
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;next_read<=0;received<=0;saved_id<=0;
   for(int i=0;i<HALFWORDS;i++)initialized[i]<=0;
   for(int r=0;r<8;r++)for(int lane=0;lane<32;lane++)begin
    saved_addresses[r][lane]<=0;saved_words[r][lane]<=0;returned_words[r][lane]<=0;
   end
   for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)saved_c[lane][word]<=0;
  end else begin
   if(write_valid&&!write_ready)$fatal(1,"Invalid shared write address");
   if(req_valid&&!addresses_legal)$fatal(1,"Invalid packed shared read address");
   if(write_valid&&write_ready)begin memory[write_byte_address/2]<=write_data;initialized[write_byte_address/2]<=1;end
   case(state)
    IDLE:if(req_valid&&req_ready)begin
     saved_id<=req_id;next_read<=0;received<=0;state<=COLLECT;
     for(int lane=0;lane<32;lane++)begin
      for(int word=0;word<8;word++)saved_c[lane][word]<=c_registers[lane][word];
      for(int word=0;word<4;word++)begin
       saved_addresses[word][lane]<=a_word_addresses[lane][word];
       saved_addresses[word+4][lane]<=b_word_addresses[lane][word];
       saved_words[word][lane]<={memory[a_word_addresses[lane][word]/2+1],memory[a_word_addresses[lane][word]/2]};
       saved_words[word+4][lane]<={memory[b_word_addresses[lane][word]/2+1],memory[b_word_addresses[lane][word]/2]};
      end
     end
    end
    COLLECT:begin
     if(read_req_valid&&read_req_ready)next_read<=next_read+1;
     if(read_rsp_valid&&read_rsp_ready)begin
      if(read_rsp_id>=8)$fatal(1,"Unknown warp-read response identity");
      else if(received[read_rsp_id]||read_rsp_id>=next_read)$fatal(1,"Duplicate or unissued warp-read completion");
      else begin
       received[read_rsp_id]<=1;
       for(int lane=0;lane<32;lane++)returned_words[read_rsp_id][lane]<=read_outputs[lane];
       if((received|(8'b1<<read_rsp_id))==8'hff)state<=MATRIX_SEND;
      end
     end
    end
    MATRIX_SEND:if(matrix_ready)state<=MATRIX_WAIT;
    MATRIX_WAIT:if(rsp_valid&&rsp_ready)state<=IDLE;
    default:$fatal(1,"Invalid timed operand state");
   endcase
  end
 end
 warp_shared_read_service #(.SLOTS(READ_SLOTS),.SERVICE_INTERVAL(SERVICE_INTERVAL),.RETURN_DELAY(RETURN_DELAY)) reads(
  .clk,.rst,.req_valid(read_req_valid),.req_ready(read_req_ready),.req_id(read_req_id),
  .byte_addresses(read_addresses),.input_words(read_inputs),
  .rsp_valid(read_rsp_valid),.rsp_ready(read_rsp_ready),.rsp_id(read_rsp_id),.output_words(read_outputs)
 );
 native_bf16_adapter #(.SLOTS(SLOTS),.LATENCY(LATENCY),.INTERVAL(INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) matrix(
  .clk,.rst,.req_valid(state==MATRIX_SEND&&!rst),.req_ready(matrix_ready),.req_id(saved_id),
  .a_registers,.b_registers,.c_registers(saved_c),.rsp_valid,.rsp_ready,.rsp_id,.result_registers,.outstanding(matrix_outstanding)
 );
endmodule
```

### 4.33. Native instruction admission from decoded controls and actual completions

This component answers a narrow question: may a presented native instruction start now, or must it wait for an earlier operation? The instruction's control bits name the producer groups it must wait for and the groups it allocates. A group is called a *barrier identifier* here. Several operations can share one identifier. The model keeps that identifier busy until every tracked operation assigned to it reports completion.

The [issue gate](components/decoded_native_issue_gate.sv) uses the decoded fields from the original GEMM's native instructions and the existing [producer tracker](discovery_rounds/native_barrier_015/producer_barrier_tracker.sv). It does not execute instructions. A downstream execution component accepts the admitted operation and later returns matching completion events. The gate never predicts those events from a fixed completion time.

#### Quantitative configuration and control fields

| Parameter or field | Value | Meaning and evidence boundary |
|---|---:|---|
| `MAX_OPS` | 16 by default | Number of operation identities the simulation tracks; not a measured hardware queue depth |
| `TAG_W` | 5 bits by default | Width of an operation identity; only values 0–15 are legal with the default capacity |
| `COUNT_W` | 5 bits by default | Counter width sufficient to represent 0–16 pending producers per group |
| Allocatable barrier identifiers | 0–5 | Six identifiers observed in compiled native controls; not six execution pipelines |
| No-allocation encoding | 7 | The presented instruction allocates no barrier in that namespace |
| Unsupported encoding | 6 | Admission is blocked and an error is recorded |
| Wait mask | 6 bits | Each set bit requires the corresponding read and write producer groups to be empty |
| Encoded issue delay | 0–15 cycles | Native field `high[44:41]`; this model uses an issue spacing of the greater of one and this value |
| Write/read barrier fields | 3 bits each | Native fields `high[48:46]` and `high[51:49]` |
| Group-control flag | 1 bit | Native field `high[45]` is preserved but its scheduling meaning is not implemented |

A zero delay cannot produce two admissions on the same edge because this interface admits at most one instruction per cycle. The one-cycle minimum therefore comes from the interface's width. It does not identify the intrinsic execution initiation interval. Interpreting nonzero encoded delays as issue spacing is the bounded reconstruction used here, rather than a claim about every native scheduler behavior.

#### Interface contract

All signals below use the same clock. Inputs marked as valid must remain stable until their ready signal permits acceptance. `TAG_W` is the configured identity width defined above.

| Signals | Direction | Contract |
|---|---|---|
| `clk`, `reset` | Input | Rising-edge clock and synchronous reset |
| `instr_valid`, `instr_ready` | Input/output | The source offers one instruction; their conjunction accepts it |
| `operation_id[TAG_W-1:0]`, `control` | Input | Accepted identity and decoded control record; both remain stable while held |
| `dispatch_valid`, `dispatch_ready` | Output/input | Admission offered to the execution component; allocation occurs only when both are true |
| `issued` | Output | Acceptance pulse, identical to the dispatch handshake |
| `write_complete_valid`, `write_complete_tag` | Input | An actual result-ready event releases this operation's allocated write barrier |
| `read_complete_valid`, `read_complete_tag` | Input | An actual operands-consumed event releases this operation's allocated read barrier |
| `busy_write_mask`, `busy_read_mask` | Output | Six bits identify producer groups with outstanding operations |
| `cooldown[3:0]` | Output | Remaining cycles of the encoded admission delay |
| `error_sticky` | Output | Invalid identities, unsupported barrier encoding, or unexpected completion events set this flag until reset |

The two completion inputs have no ready signal. The connected execution component must deliver each event once, using an active identity that allocated the corresponding barrier. If an instruction allocated no read barrier, it must not send a read completion to this tracker. One operation can allocate both namespaces and complete them on the same edge. An identity remains unavailable for reuse while either namespace still tracks it.

#### State transitions and cycle ordering

Before each edge, the gate tests the wait mask, both trackers' identity availability, the encoded delay and downstream readiness. It offers dispatch only if all required conditions hold. When accepted, the instruction adds a producer to each allocated group. The same acceptance loads `cooldown` with the encoded delay minus one, or zero when the delay is zero. Each later idle issue edge decrements a nonzero count. For example, an encoded delay of four permits the next admission four edges after the accepted instruction.

Actual completion removes the matching producer. Waiting consumers see the changed group state in the following cycle. There is no same-edge completion bypass or identity reuse. A completion for one identity and an admission using another identity can update together; neither update loses the other. Downstream backpressure allocates no producer and starts no delay.

For example, original GEMM instructions at PCs `0x1370` and `0x1380` both allocate write barrier 5 without waiting for it to become empty. Both may therefore remain outstanding. The instruction at `0x14e0` waits for barrier 5: completing only the first load is insufficient, while completing both makes this modeled dependency ready. This example tests the reconstructed control contract; it does not establish NVIDIA's private counter implementation.

#### Inline behavior model

```systemverilog
// Native control issue gate; no opcode execution or predetermined completion.
// Barrier all-producers-complete behavior is a reconstruction hypothesis.
// MAX_OPS bounds simulation tags, not physical hardware queue capacity.
// Read completion means operands consumed; write completion means result ready.
// Clients emit each event only for its allocated read/write barrier namespace.
// Completion effects become usable next cycle; same-edge tag reuse is blocked.
// A held instruction/control/tag must remain stable until instr_ready handshake.
module decoded_native_issue_gate #(
 parameter int MAX_OPS=16,TAG_W=$clog2(MAX_OPS+1),COUNT_W=$clog2(MAX_OPS+1)
)(
 input logic clk,reset,
 input logic instr_valid,output logic instr_ready,
 input logic [TAG_W-1:0] operation_id,
 input native_control_decode::control_t control,
 output logic dispatch_valid,input logic dispatch_ready,output logic issued,
 input logic write_complete_valid,input logic [TAG_W-1:0] write_complete_tag,
 input logic read_complete_valid,input logic [TAG_W-1:0] read_complete_tag,
 output logic [5:0] busy_write_mask,busy_read_mask,
 output logic [3:0] cooldown,output logic error_sticky
);
 logic write_ready,read_ready,write_wait_ready,read_wait_ready;
 logic write_error,read_error,local_error;
 logic [5:0][COUNT_W-1:0] write_counts,read_counts;
 logic valid_control,write_allocate,read_allocate,eligible;
 assign write_allocate=control.write_barrier!=7;
 assign read_allocate=control.read_barrier!=7;
 assign valid_control=control.write_barrier!=6&&control.read_barrier!=6&&int'(operation_id)<MAX_OPS;
 assign eligible=!reset&&valid_control&&cooldown==0&&write_wait_ready&&read_wait_ready&&
                 write_ready&&read_ready;
 assign dispatch_valid=instr_valid&&eligible;
 assign instr_ready=eligible&&dispatch_ready;
 assign issued=dispatch_valid&&dispatch_ready;
 assign error_sticky=write_error||read_error||local_error;
 always_ff @(posedge clk)begin
  if(reset)begin cooldown<=0;local_error<=0;end
  else begin
   if(instr_valid&&!valid_control)local_error<=1;
   if(issued)cooldown<=control.issue_delay>0?control.issue_delay-1'b1:4'd0;
   else if(cooldown!=0)cooldown<=cooldown-1'b1;
  end
 end
 producer_barrier_tracker #(.MAX_OPS(MAX_OPS),.TAG_W(TAG_W),.COUNT_W(COUNT_W)) writes(
  .clk,.reset,.issue_valid(issued&&write_allocate),.issue_ready(write_ready),
  .issue_tag(operation_id),.issue_barrier(write_allocate?control.write_barrier:3'd0),
  .complete_valid(write_complete_valid),.complete_tag(write_complete_tag),
  .wait_mask(control.wait_mask),.wait_ready(write_wait_ready),
  .busy_mask(busy_write_mask),.pending_count(write_counts),.error_sticky(write_error)
 );
 producer_barrier_tracker #(.MAX_OPS(MAX_OPS),.TAG_W(TAG_W),.COUNT_W(COUNT_W)) reads(
  .clk,.reset,.issue_valid(issued&&read_allocate),.issue_ready(read_ready),
  .issue_tag(operation_id),.issue_barrier(read_allocate?control.read_barrier:3'd0),
  .complete_valid(read_complete_valid),.complete_tag(read_complete_tag),
  .wait_mask(control.wait_mask),.wait_ready(read_wait_ready),
  .busy_mask(busy_read_mask),.pending_count(read_counts),.error_sticky(read_error)
 );
 // group_continue is preserved in control but not interpreted as another stall.
endmodule
```

#### Verification and remaining scope

Run `python components/verify_decoded_native_issue_gate.py` from this RTL directory. The [verification receipt](components/decoded_native_issue_gate_verification.json) reports 13 passing checks. Five raw instruction records are checked against the original kernel schedule before compilation. Directed cases cover delayed actual returns, multiple producers sharing one barrier, the first completion failing to clear their shared dependency, held dispatch, separate read/write events, simultaneous completion of both namespaces, simultaneous completion and distinct-identity admission, invalid control encoding, and reset.

The gate still lacks opcode execution, implicit register dependencies, branch execution, and a full register scoreboard. Results from instructions with no allocated barrier require another mechanism to represent their dependencies. The wait-mask treatment of both namespaces and the all-producers-complete rule are explicit reconstruction hypotheses. The group-control flag is not acted on. Passing these checks adds an executable admission mechanism; it does not close a complete hardware parameter field or establish GPU runtime accuracy.

### 4.34. One original CTA from global input values to acknowledged output

**Purpose and supported scope.** The [studied CTA controller](numerical/studied_gemm_cta_controller.sv) connects one complete in-bounds output block of the original GEMM: global row-major A/B inputs, completion-driven read-cache values, scalar halfword staging, the timed generic shared/MOVM path, carried matrix accumulation, and actual acknowledged output stores. It uses a deliberately serial development schedule. It is neither native SASS replay nor a full-grid GPU simulation; the optional `USE_NATIVE_STAGE` mode now uses section 4.37's bounded decoded operand window. Global staging remains serial. Fragment execution is sequential by default; section 4.40’s optional batch shares services across four active fragment warps. Optional `COALESCED_STAGING` groups 32 logical BF16 loads by their unique sectors and commits their returned halfwords together; it still services sectors serially.

**Parameters and quantities.** `M`, `N` and `K` are the global output-row, output-column and reduction dimensions. `BM` and `BN` are output-block dimensions; `BK` is the reduction width staged at once. Defaults are `M = 2048`, `N = 2112`, `K = 1536`, `BM = BN = BK = 32`, and CTA coordinates zero. `USE_NATIVE_STAGE = 0` keeps the prior timed operand path. `DYNAMIC_CTA_COORDS = 0` retains constant `CTA_ROW`/`CTA_COL`. With it enabled, the controller captures 32-bit `launch_cta_row`/`launch_cta_col` at acceptance and checks complete-block bounds using 64-bit arithmetic. These coordinates count blocks, not individual elements. For a 64 × 96 output and 32 × 32 block, block coordinate (1, 2) covers rows 32–63 and columns 64–95. Section 4.43 drives these inputs across a complete tested grid. `USE_CTA_BARRIERS = 0` retains the prior stage sequencing. Enabling it requires four-warp execution and coalesced staging, and inserts section 4.42’s producer/consumer generations. `BARRIER_RELEASE_DELAY = 1` is a model setting. `USE_OUTPUT_SCRATCH = 0` retains the direct output gather. Enabling it requires four-warp native execution and coalesced output, and inserts section 4.41’s actual scratch stores/read returns before global retirement. `MULTIWARP_NATIVE_STAGE = 0` keeps sequential fragment calls. Enabling it requires native geometry and updates all four fragment accumulators from one batch per shared stage, as specified in section 4.40. `COALESCED_OUTPUT = 0` keeps scalar output retirement; enabling it uses section 4.39’s masked sector-store interface. `COALESCED_STAGING = 0` keeps scalar staging; enabling it requires `USE_NATIVE_STAGE = 1`, so the supported coalesced geometry is also 32 × 32 with BK32. The native operand mode is supported only for `BM = BN = BK = 32`; the 64 × 48 native variant is rejected. Each native call computes both 16-element slices for one 32-element fragment step using four actual HMMA service requests. Geometry must produce a complete in-bounds block; partial edge blocks are rejected. Input bases must be 128-byte aligned, the FP32 output base four-byte aligned, and complete allocations must fit 32-bit byte addressing. Output and input allocations must not overlap because cache write coherence is absent.

| Full-reduction property | 32 × 32 output block | 64 × 48 output block |
|---|---:|---:|
| Shared stage frames at BK = 32, K = 1536 | 48 | 48 |
| Staged BF16 halfwords per frame | 2,048 | 3,584 |
| Total logical halfword loads | 98,304 | 172,032 |
| Cold backing-sector requests, verified | 6,144 | 10,752 |
| 16 × 16 fragment tiles | 4 | 12 |
| Baseline 16-element numerical fragment operations over full K | 384 | 1,152 |
| Baseline scalar warp-read groups, eight per operation | 3,072 | 9,216 |
| Final FP32 output words, each acknowledged | 1,024 | 3,072 |

The blocking read cache defaults to 64 sets, eight ways and 128-byte lines with four independently valid 32-byte sectors: 64 KiB of modeled data. Shared operand storage is 4,096 or 7,168 bytes for the two geometries. This excludes output scratch and is not the original CTA's complete allocation/occupancy model. Read queue capacity four, package interval one cycle, return delay one cycle, numerical delay/interval 16/4 and arithmetic mode one remain provisional choices. Serial staging does not reproduce native coalesced-load issue or overlap.

**Ports and ordering.** A launch supplies a 32-bit ID and three 32-bit byte bases `a_base`, `b_base`, `c_base`, plus 32-bit block row/column inputs when dynamic coordinates are enabled. Accepted coordinates and bases are retained for every input and output address in that CTA. Backing requests/returns use matching IDs and 256-bit sector data. The output-store interface supplies a 32-bit retirement ID, global byte address and FP32 word; a separate matching acknowledgment means the provider's actual defined completion. Launch completion retains the original ID and is held until acknowledged.

In scalar staging mode, for each logical BF16 load the controller computes its original global row-major address, requests the containing aligned 32-bit word from the cache, waits for an actual matching return, selects the low or high 16 bits, then writes the shared halfword. Both halves of a word are therefore selected independently; they are not interchangeable. After a whole shared frame is initialized, each fragment and each 16-element reduction slice waits for its actual arithmetic response before carrying C forward. All fragments finish before the frame is overwritten. This enforces serial producer visibility and consumer drain, not a recovered 128-thread barrier implementation.

In coalesced mode, each stage contains 64 groups of 32 BF16 loads for the supported 32 × 32 block. The controller computes every lane’s original global row-major address. Section 4.38 returns their halfwords after all unique sector requests complete, then the optional shared vector port writes 32 distinct stage addresses on one accepted edge. A full K1536 launch contains 3,072 such groups, 6,144 cold sector returns and 192 native fragment-window requests (768 HMMA operations). Two adjacent halfwords remain separate values even when they share a 32-bit word. One-edge vector commits and serial sector service are development assumptions, not measured GPU store or load throughput.

Scalar output retirement follows native fragment/lane/element order. Retirement IDs are ordinals, not row-major coordinate indices. The native accumulator mapping supplies the global output row and column separately. In scalar mode, one store is outstanding, and no later store or launch completion can precede its matching acknowledgment. Coalesced output mode waits for every masked sector acknowledgment within a warp request before advancing; all warp requests finish before launch completion. Backpressure must preserve IDs, addresses and data. Reset cancels the controller and children; external providers must discard pre-reset requests and returns because IDs lack reset generations. Cache contents persist between normal launches. **A/B backing contents must remain unchanged across cache-preserving launches; reset or explicit invalidation is required before changed input data can be reused.** External write coherence is not modeled.

**Independent end-to-end value checks.** The [full-target receipt](numerical/studied_gemm_cta_verification.json) passes 4,096 final output-word comparisons: all 1,024 words of the first 32 × 32 CTA and all 3,072 words of the first 64 × 48 CTA, both through `K = 1536`. The test provider builds every returned sector from the original A17/B13 patterns and global strides. An independent full integer dot product divided by 256 supplies exact FP32 expectations for these dyadic fixtures. Every distinct output address, word and store acknowledgment is checked. The cold sector counts exactly equal `2 × K × (BM + BN) / 32`: 6,144 and 10,752. This counts each logical input once in these aligned row-major fixtures; it does not establish native warp coalescing or concurrent memory service. These are complete first-CTA outputs, not just intermediate fragment comparisons and not the entire global matrix.

The [quick protocol receipt](numerical/studied_gemm_cta_quick_verification.json) separately passes 4,096 output comparisons for `K = 64`: two repeated launches each at synthetic backing delays two and 13. Across each pair of K64 launches, the provider observes 256 sector requests, equal to the unique cold input count; the repeated inputs remain cache-resident in this declared configuration. It rejects wrong backing/store response IDs. All configurations cancel an initial real pending read, flush the provider on reset, impose read/store acceptance backpressure, check stable held stores, delay actual store acknowledgments, and hold final launch completion. The [native-window end-to-end receipt](numerical/studied_gemm_cta_native_verification.json) additionally passes 5,120 final output comparisons: two repeated K64 launches at each backing delay and one K1536 32 × 32 CTA. Wrong backing/store IDs are rejected. These receipts preserve the hashes of their tested sources. The two full geometries use different backing delays and therefore do not provide a controlled runtime comparison. Recorded harness cycles include reset and testbench holds and are not GPU performance predictions.

The earlier [coalesced-input receipt](numerical/studied_gemm_cta_coalesced_verification.json), before the added sector-output interface, separately verifies 5,120 output words: two K64 replays at each synthetic backing delay of 2 and 13 cycles, followed by one K1536 first CTA. The full-reduction case requests 6,144 cold sectors. Every output store is acknowledged before completion, and wrong backing/store IDs are rejected. `testbench_total_cycles` include setup, reset and held completion; they are not isolated kernel runtimes or hardware predictions.

That coalesced-input receipt also checks conservation of accepted coalesced requests and shared commits: K1536 has 3,072 of each, plus 6,144 returned sector references. Its `logical_loads` counter counts 32-lane requests rather than individual halfwords. `returned_sectors` includes cache-hit packet returns; backing-sector requests count actual misses, so a warm replay can return 256 sectors while making zero new backing requests.

`completion_cycles` measures accepted launch to the first observed completion edge, excluding setup, reset and time holding the completed response. Under the declared synthetic service choices, the K64 cold/warm launches take 9,419/8,393 cycles with backing delay two, and 12,485/8,393 cycles with delay 13. The K1536 cold launch takes 84,698 cycles with delay two. These are execution times of this serialized behavioral model, not validated RTX 5090 predictions.

The earlier single-warp [coalesced input/output receipt](numerical/studied_gemm_cta_coalesced_output_verification.json) verifies another 5,120 final values using masked sector output. Each 32 × 32 launch emits 32 warp output requests containing 128 sector packets and requires all 128 matching packet acknowledgments before completion. The full K1536 case retains 3,072 input requests/commits and 6,144 cold input sectors, and takes 79,701 accepted-launch-to-completion cycles under the declared synthetic choices. It preserves the tested single-warp controller version. The [native scalar-output regression](numerical/studied_gemm_cta_native_quick_verification.json) also compares 4,096 output words after those interface extensions. Earlier receipts retain their own tested source versions. Section 4.39 explains why the original scratch layout is preserved functionally but its timing is bypassed.

The earlier [four-warp connected receipt](numerical/studied_gemm_cta_multiwarp_verification.json) checks 5,120 final output words with shared finite services. Its K1536 launch accepts and completes 48 four-warp batches, 3,072 coalesced input requests/shared commits, 6,144 returned input sectors and 128 output-sector acknowledgments. The accepted-launch-to-observed-completion count is 67,389 cycles under the synthetic choices. That receipt retains the pre-scratch implementation hashes; this model count is not a GPU timing validation.

The earlier [output-scratch connected receipt](numerical/studied_gemm_cta_output_scratch_verification.json) checks 5,120 final words after restoring scratch values to the output path. Every launch commits 16 scratch-store groups containing 1,024 words and receives 32 real warp-read completions before its 128 global sector packets are retired. The full K1536 launch retains 48 operand batches and 6,144 cold input sectors; accepted-launch-to-observed-completion takes 67,617 synthetic cycles. That receipt retains its tested pre-barrier source version. The operand and scratch arrays are separate in the model: 4,096 bytes each, or 8,192 logical bytes, excluding the original kernel’s 1,024-byte reserved allocation. Shared allocation/reuse and occupancy are not implemented by summing these arrays. The output phase has a separate shared-read service instance, and never overlaps the operand phase; this does not claim simultaneous extra physical bandwidth.

The earlier [barrier-connected receipt](numerical/studied_gemm_cta_barriers_verification.json) verifies 5,120 final words after producer visibility and consumer drain become explicit generation transactions. At K1536, all 48 stages account for 192 producer warp arrivals, 192 consumer warp arrivals and 96 acknowledged releases. These are individual warp participants, not necessarily 192 distinct interface transfers: one mask can report several consumer warps together. The complete launch takes 67,832 synthetic cycles from accepted launch to observed completion. That receipt binds its tested pre-grid-input version; the arrival conditions and release delay remain conservative model policies, not recovered NVIDIA synchronization latency.

The latest [grid receipt](numerical/studied_gemm_grid_verification.json) verifies complete small matrices by reusing this dynamically addressed CTA controller. It checks 24,576 acknowledged words across four grid launches with six distinct block coordinates each. A fresh [single-CTA quick regression](numerical/studied_gemm_cta_barriers_quick_verification.json) also checks 4,096 words after the dynamic inputs are added. Section 4.43 distinguishes complete tested-grid values from unmodeled SM concurrency.

**Remaining limit.** Numerical global-to-output behavior is connected for one original CTA. Complete native instruction scheduling, calibrated cache/controller timing, multi-CTA/multi-SM contention, real barrier arbitration, complete arithmetic semantics and independent hardware runtime validation remain absent. Physical evidence counts are unchanged: eight identified fields, 32 partial and 94 unknown. No model-accuracy claim follows from these synthetic timing tests.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_studied_gemm_cta.py --full-only` for baseline full-reduction fixtures, `--quick` for baseline replay/protocol fixtures, or `--native-stage` for the bounded native-window integration fixtures. Add `--coalesced-staging` to the native mode for grouped global reads and vector shared writes. `--multiwarp` selects the four-warp batch and enables both coalesced input and output. `--output-scratch` additionally routes values through the scratch component before global stores. `--cta-barriers` enables the explicit producer/consumer generations and the required connected modes.

**Authoritative behavioral implementation.**

```systemverilog
// Complete in-bounds output block of the studied row-major BF16 GEMM.
// Serial staging and optional four-warp execution are development schedules,
// not full native instruction replay. The cache is a blocking read-cache hypothesis, not recovered L2.
module studied_gemm_cta_controller #(
 parameter int BM=32,BN=32,BK=32,M=2048,N=2112,K=1536,CTA_ROW=0,CTA_COL=0,
 parameter int SETS=64,WAYS=8,LATENCY=16,INTERVAL=4,READ_SLOTS=4,
 parameter int SERVICE_INTERVAL=1,RETURN_DELAY=1,ARITHMETIC_MODE=1,
 parameter bit USE_NATIVE_STAGE=0,COALESCED_STAGING=0,COALESCED_OUTPUT=0,MULTIWARP_NATIVE_STAGE=0,USE_OUTPUT_SCRATCH=0,USE_CTA_BARRIERS=0,DYNAMIC_CTA_COORDS=0,
 parameter int BARRIER_RELEASE_DELAY=1,MOVM_LATENCY=1,MOVM_INTERVAL=1
)(
 input logic clk,rst,launch_valid,output logic launch_ready,
 input logic [31:0] launch_id,a_base,b_base,c_base,launch_cta_row,launch_cta_col,
 output logic done_valid,input logic done_ready,output logic [31:0] done_id,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic [31:0] backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic [31:0] backing_rsp_id,input logic [255:0] backing_rsp_data,
 output logic store_req_valid,input logic store_req_ready,
 output logic [31:0] store_req_id,store_req_byte_address,store_req_data,
 input logic store_rsp_valid,output logic store_rsp_ready,
 input logic [31:0] store_rsp_id,
 output logic sector_store_req_valid,input logic sector_store_req_ready,
 output logic [31:0] sector_store_req_id,sector_store_req_byte_address,
 output logic [255:0] sector_store_req_data,output logic [7:0] sector_store_req_word_mask,
 input logic sector_store_rsp_valid,output logic sector_store_rsp_ready,
 input logic [31:0] sector_store_rsp_id
);
 localparam int TN=BN/16,TILES=(BM/16)*TN,HALFWORDS=BK*(BM+BN),STAGES=K/BK;
 typedef enum logic[3:0]{IDLE,PRODUCER_ARM,PRODUCER_WAIT,CONSUMER_ARM,CONSUMER_WAIT,LOAD_SEND,LOAD_WAIT,SHARED_WRITE,MATRIX_SEND,
  MATRIX_WAIT,SCRATCH_SEND,SCRATCH_WAIT,STORE_SEND,STORE_WAIT,DONE} state_t;
 state_t state;
 logic [31:0] saved_id,saved_a,saved_b,saved_c,saved_row,saved_col;
 logic[31:0]accepted_row,accepted_col;
 assign accepted_row=DYNAMIC_CTA_COORDS?launch_cta_row:32'(CTA_ROW);
 assign accepted_col=DYNAMIC_CTA_COORDS?launch_cta_col:32'(CTA_COL);
 int stage_number,halfword_number,tile_number,k_step,store_number;
 logic [15:0] loaded_halfword;
 logic [15:0] loaded_halfwords[32],warp_halfwords[32];
 logic [31:0] warp_global_addresses[32],warp_shared_addresses[32];
 logic warp_write_valid,warp_write_ready;int warp_sector_count;
 logic cache_req_valid,cache_req_ready,cache_rsp_valid,cache_rsp_ready,cache_rsp_hit;
 logic [31:0] cache_req_id,cache_req_address,cache_rsp_id,cache_rsp_word;
 logic [31:0] global_halfword_address;
 logic write_valid,write_ready,matrix_req_valid,matrix_req_ready,matrix_rsp_valid,matrix_rsp_ready;
 logic [31:0] matrix_req_id,matrix_rsp_id,write_byte_address;
 logic [31:0] accumulators[TILES][32][8],matrix_c[32][8],matrix_results[32][8];
 logic initialized,legal;int matrix_outstanding;
 logic[31:0]batch_c[4][32][8],batch_results[4][32][8];
 logic[3:0]warp_drained,warp_memory_safe,consumer_sent,barrier_arrival_mask,barrier_arrived_mask,barrier_release_mask;
 logic barrier_arm_valid,barrier_arm_ready,barrier_arrival_valid,barrier_arrival_ready,barrier_release_valid,barrier_release_ready,barrier_active;
 logic[31:0]barrier_arm_generation,barrier_arrival_generation,barrier_generation;
 int producer_arrival_count,consumer_arrival_count,barrier_release_count;
 logic scratch_req_valid,scratch_req_ready,scratch_rsp_valid,scratch_rsp_ready;
 logic[31:0]scratch_rsp_id,scratch_words[4][256],saved_scratch_words[4][256];int scratch_outstanding;
 int scratch_store_requests,scratch_store_commit_words,scratch_read_requests,scratch_read_completions;
 logic output_warp_valid,output_warp_ready,output_done_valid,output_done_ready;
 logic [31:0] output_done_id,output_addresses[32],output_words[32];int output_sectors;
 initial if(BM<16||BN<16||BK<16||BM%16!=0||BN%16!=0||BK%16!=0||K< BK||K%BK!=0||
  BM>M||BN>N||(!DYNAMIC_CTA_COORDS&&(CTA_ROW<0||CTA_COL<0||(CTA_ROW+1)*BM>M||(CTA_COL+1)*BN>N)))
  $fatal(1,"Unsupported studied CTA geometry or partial output block");
 initial if(2*64'(M)*K>64'h100000000||2*64'(K)*N>64'h100000000||4*64'(M)*N>64'h100000000)
  $fatal(1,"Studied matrix allocation too large");
 initial if(USE_NATIVE_STAGE&&(BM!=32||BN!=32||BK!=32))
  $fatal(1,"Native stage controls support only original BM32 BN32 BK32");
 initial if(USE_CTA_BARRIERS&&(!MULTIWARP_NATIVE_STAGE||!COALESCED_STAGING))
  $fatal(1,"CTA barriers require four-warp stage and warp staging");
 initial if(USE_OUTPUT_SCRATCH&&(!MULTIWARP_NATIVE_STAGE||!COALESCED_OUTPUT))
  $fatal(1,"Output scratch requires multiwarp stage and warp output interface");
 initial if(MULTIWARP_NATIVE_STAGE&&!USE_NATIVE_STAGE)
  $fatal(1,"Multiwarp native stage requires supported native geometry");
 initial if(COALESCED_STAGING&&!USE_NATIVE_STAGE)
  $fatal(1,"Coalesced staging requires native stage vector write port");
 function automatic logic [31:0] input_address(input int index);
  int offset;offset=index-BM*BK;
  if(index<BM*BK)return saved_a+32'(2*((int'(saved_row)*BM+index/BK)*K+stage_number*BK+index%BK));
  return saved_b+32'(2*((stage_number*BK+offset/BN)*N+int'(saved_col)*BN+offset%BN));
 endfunction
 always_comb begin
  barrier_arm_valid=USE_CTA_BARRIERS&&!rst&&(state==PRODUCER_ARM||state==CONSUMER_ARM);
  barrier_arm_generation=32'(2*stage_number+(state==CONSUMER_ARM?1:0));
  barrier_arrival_valid=0;barrier_arrival_mask=0;barrier_arrival_generation=32'(2*stage_number);
  if(USE_CTA_BARRIERS&&!rst)begin
   if(state==SHARED_WRITE&&warp_write_valid&&warp_write_ready&&halfword_number>=HALFWORDS-128)begin
    barrier_arrival_valid=1;barrier_arrival_mask[ (halfword_number/32)%4 ]=1;
   end else if(state==MATRIX_WAIT&&(warp_memory_safe&~consumer_sent)!=0)begin
    barrier_arrival_valid=1;barrier_arrival_mask=warp_memory_safe&~consumer_sent;
    barrier_arrival_generation=32'(2*stage_number+1);
   end
  end
  barrier_release_ready=USE_CTA_BARRIERS&&!rst&&(state==PRODUCER_WAIT||state==CONSUMER_WAIT);
 end
 always_ff @(posedge clk)begin
  if(rst||state==IDLE)begin consumer_sent<=0;producer_arrival_count<=0;consumer_arrival_count<=0;barrier_release_count<=0;end
  else begin
   if(barrier_arm_valid&&barrier_arm_ready&&state==CONSUMER_ARM)consumer_sent<=0;
   if(barrier_arrival_valid)begin
    if(!barrier_arrival_ready)$fatal(1,"CTA arrival offered to unavailable generation");
    if(barrier_arrival_ready)begin
     if(state==SHARED_WRITE)producer_arrival_count<=producer_arrival_count+$countones(barrier_arrival_mask);
     else begin consumer_sent<=consumer_sent|barrier_arrival_mask;consumer_arrival_count<=consumer_arrival_count+$countones(barrier_arrival_mask);end
    end
   end
   if(barrier_release_valid&&barrier_release_ready)begin
    if(barrier_generation!=32'(2*stage_number+(state==CONSUMER_WAIT?1:0))||barrier_release_mask!=4'hf)
     $fatal(1,"CTA release generation or participant mismatch");
    barrier_release_count<=barrier_release_count+1;
   end
  end
 end
 assign launch_ready=!rst&&state==IDLE;
 assign done_valid=!rst&&state==DONE;assign done_id=saved_id;
 assign cache_req_valid=!rst&&state==LOAD_SEND;
 assign cache_rsp_ready=!rst&&state==LOAD_WAIT;
 assign cache_req_id=32'(stage_number*HALFWORDS+halfword_number);
 always_comb begin
  global_halfword_address=input_address(halfword_number);
  for(int lane=0;lane<32;lane++)begin
   warp_global_addresses[lane]=input_address(halfword_number+lane);
   warp_shared_addresses[lane]=32'(2*(halfword_number+lane));
  end
  for(int warp=0;warp<4;warp++)for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)
   batch_c[warp][lane][word]=warp<TILES?accumulators[warp][lane][word]:32'd0;
  // Original logical load is16bits; cache adapter obtains the containing word.
  cache_req_address={global_halfword_address[31:2],2'b00};
  for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)
   matrix_c[lane][word]=accumulators[tile_number][lane][word];
 end
 assign write_valid=!rst&&state==SHARED_WRITE&&!COALESCED_STAGING;
 assign warp_write_valid=!rst&&state==SHARED_WRITE&&COALESCED_STAGING;
 assign write_byte_address=32'(2*halfword_number);
 assign matrix_req_valid=!rst&&state==MATRIX_SEND;
 assign matrix_rsp_ready=!rst&&state==MATRIX_WAIT;
 assign matrix_req_id=32'((stage_number*TILES+tile_number)*(BK/16)+k_step);
 assign scratch_req_valid=!rst&&state==SCRATCH_SEND;
 assign scratch_rsp_ready=!rst&&state==SCRATCH_WAIT;
 assign store_req_valid=!rst&&state==STORE_SEND&&!COALESCED_OUTPUT;
 assign output_warp_valid=!rst&&state==STORE_SEND&&COALESCED_OUTPUT;
 assign output_done_ready=!rst&&state==STORE_WAIT&&COALESCED_OUTPUT;
 assign store_rsp_ready=!rst&&state==STORE_WAIT&&!COALESCED_OUTPUT;
 assign store_req_id=32'(store_number);
 always_comb begin
  int fragment,element,row,column;
  fragment=store_number/256;
  element=native_bf16_layout::c_element_index((store_number%256)/8,store_number%8);
  row=int'(saved_row)*BM+16*(fragment/TN)+element/16;
  column=int'(saved_col)*BN+16*(fragment%TN)+element%16;
  store_req_byte_address=saved_c+32'(4*(row*N+column));
  store_req_data=accumulators[fragment][(store_number%256)/8][store_number%8];
  for(int lane=0;lane<32;lane++)begin
   // Original global store reads row-major scratch at lane+32*iteration.
   // Gather equivalent values from measured fragment layout; scratch service
   // is bypassed only when USE_OUTPUT_SCRATCH is disabled. Service timing
   // remains provisional in both modes.
   element=lane+32*((store_number%256)/32);
   row=int'(saved_row)*BM+16*(fragment/TN)+element/16;
   column=int'(saved_col)*BN+16*(fragment%TN)+element%16;
   output_addresses[lane]=saved_c+32'(4*(row*N+column));
   output_words[lane]=0;
   if(USE_OUTPUT_SCRATCH)output_words[lane]=saved_scratch_words[fragment][element];
   else for(int owner=0;owner<32;owner++)for(int word=0;word<8;word++)
    if(native_bf16_layout::c_element_index(owner,word)==element)
     output_words[lane]=accumulators[fragment][owner][word];
  end
 end
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;saved_id<=0;saved_a<=0;saved_b<=0;saved_c<=0;saved_row<=0;saved_col<=0;
   stage_number<=0;halfword_number<=0;tile_number<=0;k_step<=0;store_number<=0;loaded_halfword<=0;
   for(int lane=0;lane<32;lane++)loaded_halfwords[lane]<=0;
   for(int warp=0;warp<4;warp++)for(int element=0;element<256;element++)saved_scratch_words[warp][element]<=0;
   for(int tile=0;tile<TILES;tile++)for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)
    accumulators[tile][lane][word]<=0;
  end else case(state)
   IDLE:if(launch_valid&&launch_ready)begin
    if(({32'b0,accepted_row}+64'd1)*64'(BM)>64'(M)||({32'b0,accepted_col}+64'd1)*64'(BN)>64'(N))
     $fatal(1,"Dynamic CTA coordinate outside complete output grid");
    if(a_base[6:0]!=0||b_base[6:0]!=0||c_base[1:0]!=0)$fatal(1,"Unaligned studied CTA base");
    if({1'b0,a_base}+33'(2*64'(M)*K)>33'h100000000||
       {1'b0,b_base}+33'(2*64'(K)*N)>33'h100000000||
       {1'b0,c_base}+33'(4*64'(M)*N)>33'h100000000)
     $fatal(1,"Studied CTA allocation exceeds 32-bit address space");
    // Input/output separation is required while cache write coherence is absent.
    if(({1'b0,c_base}<{1'b0,a_base}+33'(2*64'(M)*K)&&
        {1'b0,a_base}<{1'b0,c_base}+33'(4*64'(M)*N))||
       ({1'b0,c_base}<{1'b0,b_base}+33'(2*64'(K)*N)&&
        {1'b0,b_base}<{1'b0,c_base}+33'(4*64'(M)*N)))
     $fatal(1,"Overlapping studied output/input allocation");
    saved_id<=launch_id;saved_a<=a_base;saved_b<=b_base;saved_c<=c_base;saved_row<=accepted_row;saved_col<=accepted_col;
    stage_number<=0;halfword_number<=0;tile_number<=0;k_step<=0;store_number<=0;
    for(int tile=0;tile<TILES;tile++)for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)
     accumulators[tile][lane][word]<=0;
    state<=USE_CTA_BARRIERS?PRODUCER_ARM:LOAD_SEND;
   end
   PRODUCER_ARM:if(barrier_arm_valid&&barrier_arm_ready)state<=LOAD_SEND;
   PRODUCER_WAIT:if(barrier_release_valid&&barrier_release_ready)state<=CONSUMER_ARM;
   CONSUMER_ARM:if(barrier_arm_valid&&barrier_arm_ready)state<=MATRIX_SEND;
   CONSUMER_WAIT:if(barrier_release_valid&&barrier_release_ready)begin
    if(stage_number<STAGES-1)begin stage_number<=stage_number+1;halfword_number<=0;state<=PRODUCER_ARM;end
    else begin store_number<=0;state<=USE_OUTPUT_SCRATCH?SCRATCH_SEND:STORE_SEND;end
   end
   LOAD_SEND:if(cache_req_valid&&cache_req_ready)state<=LOAD_WAIT;
   LOAD_WAIT:if(cache_rsp_valid&&cache_rsp_ready)begin
    if(cache_rsp_id!=cache_req_id)$fatal(1,"Studied load completion identity mismatch");
    if(COALESCED_STAGING)for(int lane=0;lane<32;lane++)loaded_halfwords[lane]<=warp_halfwords[lane];
    else loaded_halfword<=global_halfword_address[1]?cache_rsp_word[31:16]:cache_rsp_word[15:0];
    state<=SHARED_WRITE;
   end
   SHARED_WRITE:if((write_valid&&write_ready)||(warp_write_valid&&warp_write_ready))begin
    if(halfword_number==HALFWORDS-(COALESCED_STAGING?32:1))begin tile_number<=0;k_step<=0;state<=USE_CTA_BARRIERS?PRODUCER_WAIT:MATRIX_SEND;end
    else begin halfword_number<=halfword_number+(COALESCED_STAGING?32:1);state<=LOAD_SEND;end
   end
   MATRIX_SEND:if(matrix_req_valid&&matrix_req_ready)state<=MATRIX_WAIT;
   MATRIX_WAIT:if(matrix_rsp_valid&&matrix_rsp_ready)begin
    if(matrix_rsp_id!=matrix_req_id)$fatal(1,"Studied arithmetic completion identity mismatch");
    if(MULTIWARP_NATIVE_STAGE)begin
     for(int warp=0;warp<4;warp++)for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)
      accumulators[warp][lane][word]<=batch_results[warp][lane][word];
    end else for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)
     accumulators[tile_number][lane][word]<=matrix_results[lane][word];
    if(USE_CTA_BARRIERS)state<=CONSUMER_WAIT;
    else if(!USE_NATIVE_STAGE&&k_step<BK/16-1)begin k_step<=k_step+1;state<=MATRIX_SEND;end
    else if(!MULTIWARP_NATIVE_STAGE&&tile_number<TILES-1)begin tile_number<=tile_number+1;k_step<=0;state<=MATRIX_SEND;end
    else if(stage_number<STAGES-1)begin stage_number<=stage_number+1;halfword_number<=0;state<=LOAD_SEND;end
    else begin store_number<=0;state<=USE_OUTPUT_SCRATCH?SCRATCH_SEND:STORE_SEND;end
   end
   SCRATCH_SEND:if(scratch_req_valid&&scratch_req_ready)state<=SCRATCH_WAIT;
   SCRATCH_WAIT:if(scratch_rsp_valid&&scratch_rsp_ready)begin
    if(scratch_rsp_id!=saved_id)$fatal(1,"Output scratch completion identity mismatch");
    for(int warp=0;warp<4;warp++)for(int element=0;element<256;element++)
     saved_scratch_words[warp][element]<=scratch_words[warp][element];
    state<=STORE_SEND;
   end
   STORE_SEND:if((store_req_valid&&store_req_ready)||(output_warp_valid&&output_warp_ready))state<=STORE_WAIT;
   STORE_WAIT:if((store_rsp_valid&&store_rsp_ready)||(output_done_valid&&output_done_ready))begin
    if(COALESCED_OUTPUT ? output_done_id!=32'(store_number/32) : store_rsp_id!=store_req_id)$fatal(1,"Studied store completion identity mismatch");
    if(store_number==BM*BN-(COALESCED_OUTPUT?32:1))state<=DONE;
    else begin store_number<=store_number+(COALESCED_OUTPUT?32:1);state<=STORE_SEND;end
   end
   DONE:if(done_valid&&done_ready)state<=IDLE;
   default:$fatal(1,"Invalid studied CTA controller state");
  endcase
 end
 generate if(COALESCED_STAGING)begin:warp_load_path
 coalesced_u16_warp_load #(.SETS(SETS),.WAYS(WAYS)) cache(
  .clk,.rst,.req_valid(cache_req_valid),.req_ready(cache_req_ready),.req_id(cache_req_id),
  .byte_addresses(warp_global_addresses),.active_mask(32'hffffffff),
  .rsp_valid(cache_rsp_valid),.rsp_ready(cache_rsp_ready),.rsp_id(cache_rsp_id),
  .halfwords(warp_halfwords),.sector_count(warp_sector_count),
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,
  .backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data
 );
 end else begin:scalar_load_path
 sector_read_cache #(.SETS(SETS),.WAYS(WAYS)) cache(
  .clk,.rst,.req_valid(cache_req_valid),.req_ready(cache_req_ready),.req_id(cache_req_id),.req_byte_address(cache_req_address),
  .rsp_valid(cache_rsp_valid),.rsp_ready(cache_rsp_ready),.rsp_id(cache_rsp_id),.rsp_data(cache_rsp_word),.rsp_hit(cache_rsp_hit),
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,
  .backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data
 );
 end endgenerate
 generate if(MULTIWARP_NATIVE_STAGE)begin:multiwarp_stage_path
 native_multiwarp_stage_pipeline #(.READ_SLOTS(READ_SLOTS),.SERVICE_INTERVAL(SERVICE_INTERVAL),
  .RETURN_DELAY(RETURN_DELAY),.MOVM_LATENCY(MOVM_LATENCY),.MOVM_INTERVAL(MOVM_INTERVAL),
  .HMMA_LATENCY(LATENCY),.HMMA_INTERVAL(INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE),
  .ALLOW_WARP_WRITES(COALESCED_STAGING)) path(
  .clk,.rst,.write_valid,.write_ready,.write_byte_address,.write_data(loaded_halfword),
  .write_warp_valid(warp_write_valid),.write_warp_ready(warp_write_ready),
  .write_warp_byte_addresses(warp_shared_addresses),.write_warp_halfwords(loaded_halfwords),.write_warp_mask(32'hffffffff),
  .req_valid(matrix_req_valid),.req_ready(matrix_req_ready),.req_id(matrix_req_id),.c_registers(batch_c),
  .operands_initialized(initialized),.addresses_legal(legal),
  .rsp_valid(matrix_rsp_valid),.rsp_ready(matrix_rsp_ready),.rsp_id(matrix_rsp_id),
  .result_registers(batch_results),.outstanding(matrix_outstanding),.warp_drained(warp_drained),.warp_memory_safe(warp_memory_safe)
 );
 end else if(USE_NATIVE_STAGE)begin:native_stage_path
 native_studied_stage_pipeline #(.READ_SLOTS(READ_SLOTS),.SERVICE_INTERVAL(SERVICE_INTERVAL),
  .RETURN_DELAY(RETURN_DELAY),.MOVM_LATENCY(MOVM_LATENCY),.MOVM_INTERVAL(MOVM_INTERVAL),
  .HMMA_LATENCY(LATENCY),.HMMA_INTERVAL(INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE),
  .ALLOW_WARP_WRITES(COALESCED_STAGING)) path(
  .clk,.rst,.write_valid,.write_ready,.write_byte_address,.write_data(loaded_halfword),
  .write_warp_valid(warp_write_valid),.write_warp_ready(warp_write_ready),
  .write_warp_byte_addresses(warp_shared_addresses),.write_warp_halfwords(loaded_halfwords),.write_warp_mask(32'hffffffff),
  .req_valid(matrix_req_valid),.req_ready(matrix_req_ready),.req_id(matrix_req_id),
  .tile_index(32'(tile_number)),.c_registers(matrix_c),
  .operands_initialized(initialized),.addresses_legal(legal),
  .rsp_valid(matrix_rsp_valid),.rsp_ready(matrix_rsp_ready),.rsp_id(matrix_rsp_id),
  .result_registers(matrix_results),.outstanding(matrix_outstanding)
 );
 end else begin:generic_stage_path
 studied_gemm_matrix_pipeline #(.BM(BM),.BN(BN),.BK(BK),.TIMED_READS(1),
  .LATENCY(LATENCY),.INTERVAL(INTERVAL),.READ_SLOTS(READ_SLOTS),
  .SERVICE_INTERVAL(SERVICE_INTERVAL),.RETURN_DELAY(RETURN_DELAY),.ARITHMETIC_MODE(ARITHMETIC_MODE)) path(
  .clk,.rst,.write_valid,.write_ready,.write_byte_address,.write_data(loaded_halfword),
  .req_valid(matrix_req_valid),.req_ready(matrix_req_ready),.req_id(matrix_req_id),
  .tile_index(32'(tile_number)),.k_step(32'(k_step)),.c_registers(matrix_c),
  .operands_initialized(initialized),.addresses_legal(legal),
  .rsp_valid(matrix_rsp_valid),.rsp_ready(matrix_rsp_ready),.rsp_id(matrix_rsp_id),
  .result_registers(matrix_results),.outstanding(matrix_outstanding)
 );
 end endgenerate
 generate if(USE_OUTPUT_SCRATCH)begin:scratch_path
 studied_output_scratch_pipeline #(.STORE_INTERVAL(SERVICE_INTERVAL),.STORE_RETURN_DELAY(RETURN_DELAY),
  .READ_SLOTS(READ_SLOTS),.READ_INTERVAL(SERVICE_INTERVAL),.READ_RETURN_DELAY(RETURN_DELAY)) path(
  .clk,.rst,.req_valid(scratch_req_valid),.req_ready(scratch_req_ready),.req_id(saved_id),.c_registers(batch_c),
  .rsp_valid(scratch_rsp_valid),.rsp_ready(scratch_rsp_ready),.rsp_id(scratch_rsp_id),
  .row_major_words(scratch_words),.outstanding(scratch_outstanding),
  .store_requests(scratch_store_requests),.store_commit_words(scratch_store_commit_words),
  .read_requests(scratch_read_requests),.read_completions(scratch_read_completions)
 );
 end else begin:no_scratch_path
 assign scratch_store_requests=0;assign scratch_store_commit_words=0;assign scratch_read_requests=0;assign scratch_read_completions=0;
 assign scratch_req_ready=0;assign scratch_rsp_valid=0;assign scratch_rsp_id=0;assign scratch_outstanding=0;
 for(genvar warp=0;warp<4;warp++)for(genvar element=0;element<256;element++)assign scratch_words[warp][element]=0;
 end endgenerate
 generate if(COALESCED_OUTPUT)begin:warp_store_path
 coalesced_fp32_warp_store output_path(
  .clk,.rst,.req_valid(output_warp_valid),.req_ready(output_warp_ready),.req_id(32'(store_number/32)),
  .byte_addresses(output_addresses),.words(output_words),.active_mask(32'hffffffff),
  .rsp_valid(output_done_valid),.rsp_ready(output_done_ready),.rsp_id(output_done_id),.sector_count(output_sectors),
  .backing_req_valid(sector_store_req_valid),.backing_req_ready(sector_store_req_ready),
  .backing_req_id(sector_store_req_id),.backing_req_byte_address(sector_store_req_byte_address),
  .backing_req_data(sector_store_req_data),.backing_req_word_mask(sector_store_req_word_mask),
  .backing_rsp_valid(sector_store_rsp_valid),.backing_rsp_ready(sector_store_rsp_ready),.backing_rsp_id(sector_store_rsp_id)
 );
 end else begin:no_warp_store
 assign output_warp_ready=0;assign output_done_valid=0;assign output_done_id=0;assign output_sectors=0;
 assign sector_store_req_valid=0;assign sector_store_req_id=0;assign sector_store_req_byte_address=0;
 assign sector_store_req_data=0;assign sector_store_req_word_mask=0;assign sector_store_rsp_ready=0;
 end endgenerate
 generate if(USE_CTA_BARRIERS)begin:cta_barrier_path
 cta_generation_barrier #(.WARPS(4),.RELEASE_DELAY(BARRIER_RELEASE_DELAY)) barrier(
  .clk,.rst(rst||state==IDLE),.arm_valid(barrier_arm_valid),.arm_ready(barrier_arm_ready),
  .arm_generation(barrier_arm_generation),.expected_mask(4'hf),
  .arrival_valid(barrier_arrival_valid),.arrival_ready(barrier_arrival_ready),
  .arrival_generation(barrier_arrival_generation),.arrival_mask(barrier_arrival_mask),
  .release_valid(barrier_release_valid),.release_ready(barrier_release_ready),
  .generation(barrier_generation),.release_mask(barrier_release_mask),.arrived_mask(barrier_arrived_mask),.active(barrier_active)
 );
 end else begin:no_cta_barrier
 assign barrier_arm_ready=0;assign barrier_arrival_ready=0;assign barrier_release_valid=0;
 assign barrier_generation=0;assign barrier_release_mask=0;assign barrier_arrived_mask=0;assign barrier_active=0;
 end endgenerate
 // Serial stage boundaries enforce producer visibility and consumer drain,
 // but are not a reconstruction of128thread CTA barrier arbitration.
 // Providers must discard pre-reset traffic; IDs have no reset generation.
endmodule
```

### 4.35. Numerical service for one supported native HMMA instruction

The original GEMM uses native matrix instructions rather than a single indivisible matrix-multiplication call. This service computes the numerical result of one supported `HMMA.16816.F32.BF16` operation: a 16-row by 8-column output, with 16 products contributing to each output value. BF16 supplies the multiplicands; FP32 supplies the initial and resulting accumulator. The service is a numerical instruction adapter, not a claim about how many physical Tensor Core pipelines execute it.

#### Operand organization and quantitative configuration

Each of the 32 lanes presents four packed 32-bit A words, two packed 32-bit B words, and four FP32 C words. Each packed input word contains two BF16 values. Across lanes these encode the 16 × 16 A operand and one 16 × 8 B column half, together with its 16 × 8 C accumulator. The [measured layout](discovery_rounds/functional_mapping_002/analysis.json) defines where each value belongs; the arrays below describe contents rather than physical register-bank routing.

| Parameter or quantity | Default or supported value | Meaning |
|---|---:|---|
| Lanes | 32 | One complete participating warp; partial-lane matrix operations are unsupported |
| A words per lane | 4 | Eight BF16 values |
| B words per lane | 2 | Four BF16 values for the selected output-column half |
| C/D words per lane | 4 | Four FP32 accumulators/results |
| `SLOTS` | 2 | Configured operation-buffer capacity, not a measured physical depth |
| `LATENCY` | 16 cycles | Chosen response delay inherited from the numerical matrix service; not measured HMMA latency |
| `INTERVAL` | 4 cycles | Chosen minimum admission interval; not identified native throughput |
| `ARITHMETIC_MODE` | 1 | Existing magnitude-aligned matrix arithmetic approximation; exceptional and general rounding coverage remain limited |

The adapter supplies B words 0–1 and C words 0–3 to the complete numerical matrix operation, zeros the unused B/C column half, and returns D words 0–3. Each output dot product is independent of the unused columns. To compute the upper half of a full WMMA operation, the caller instead supplies its original B words 2–3 and C words 4–7 through the same small interface, then places the four returned words in full-result slots 4–7. Thus two applications cover the full 16 × 16 output.

#### Interfaces and cycle behavior

| Signals | Direction | Contract |
|---|---|---|
| `clk`, `rst` | Input | Rising-edge clock and synchronous reset |
| `req_valid`, `req_ready` | Input/output | Their conjunction accepts a numerical operation |
| `req_id[31:0]` | Input | Identity preserved until the result is accepted; duplicate live identities are invalid under the underlying numerical service contract |
| `a_registers[32][4]`, `b_registers[32][2]` | Input | Packed BF16 operands, captured on request acceptance |
| `c_registers[32][4]` | Input | FP32 initial accumulator, captured on the same edge |
| `rsp_valid`, `rsp_ready` | Output/input | Their conjunction retires the result |
| `rsp_id[31:0]`, `result_registers[32][4]` | Output | Matching identity and result words; usable when response valid is asserted |
| `outstanding` | Output | Number of buffered operations that have not retired |

Inputs may change after request acceptance. The inherited operation buffer keeps captured values and preserves response order. Backpressure holds the visible response and keeps its buffer occupied. Reset discards pending operations. The configured response delay is a model timing choice; this adapter contains no native issue-control decoder, shared-load service, register-bank arbitration, or physical execution-unit scheduler.

#### Inline behavior model

```systemverilog
// Numerical instruction-family adapter: one HMMA.16816.F32.BF16 half.
// Measured supported mapping: two B words and four C words per lane.
// Reusing a full matrix oracle does not model two physical pipelines.
module native_hmma16816_adapter #(
 parameter int SLOTS=2,LATENCY=16,INTERVAL=4,ARITHMETIC_MODE=1
)(
 input logic clk,rst,req_valid,output logic req_ready,
 input logic [31:0] req_id,
 input logic [31:0] a_registers[32][4],b_registers[32][2],c_registers[32][4],
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,result_registers[32][4],output int outstanding
);
 logic [31:0] full_b[32][4],full_c[32][8],full_result[32][8];
 for(genvar lane=0;lane<32;lane++)begin:lanes
  for(genvar word=0;word<4;word++)begin:words
   if(word<2)begin:used_b
    assign full_b[lane][word]=b_registers[lane][word];
   end else begin:unused_b
    assign full_b[lane][word]=32'b0;
   end
   assign full_c[lane][word]=c_registers[lane][word];
   assign full_c[lane][word+4]=32'b0;
   assign result_registers[lane][word]=full_result[lane][word];
  end
 end
 native_bf16_adapter #(.SLOTS(SLOTS),.LATENCY(LATENCY),.INTERVAL(INTERVAL),
  .ARITHMETIC_MODE(ARITHMETIC_MODE)) operation(
  .clk,.rst,.req_valid,.req_ready,.req_id,.a_registers,.b_registers(full_b),.c_registers(full_c),
  .rsp_valid,.rsp_ready,.rsp_id,.result_registers(full_result),.outstanding
 );
endmodule
```

#### Verification and limits

Run `python numerical/verify_native_hmma16816.py` from the RTL directory. The [receipt](numerical/native_hmma16816_verification.json) reports 512 output comparisons against independent, direct sixteen-term dot products. The inputs are exactly representable fractions with power-of-two denominators, so the reference calculation has no ambiguous rounding in these cases. Four half operations cover lower and upper columns with zero and nonzero initial accumulators. A further 512 comparisons check that the two returned halves equal the complete WMMA adapter's results. Acceptance capture, response backpressure and reset are also exercised.

These cases validate supported numerical contents and the half-operation interface. They do not identify general native accumulation semantics, exceptional-value behavior, physical pipeline count, HMMA latency or initiation interval. The underlying complete matrix oracle is reused internally; native execution resources are not duplicated merely because the source instantiates an adapter.

### 4.36. Measured lane-word transformation for one MOVM instruction

The same native GEMM prepares some B operands with `MOVM.16.MT88`. This service accepts one 32-bit word from each of 32 lanes and returns the transformed word for each lane. It moves the two 16-bit halves among lanes according to the supported measured permutation. It performs no arithmetic conversion and does not read shared memory.

#### Mapping and configuration

The literal table in [the permutation package](numerical/library_movm_permutation.sv) maps each destination halfword position to its original source position. Its original 256 positions cover four words in every lane. Review of all 256 entries confirms two necessary properties: each mapping preserves the source word number, and the source-lane/source-halfword rule is identical for all four word numbers. A one-word instruction service can therefore use the entries for word zero to transform any selected word in this supported family.

| Parameter or quantity | Default | Meaning and evidence boundary |
|---|---:|---|
| Lanes | 32 | A full collective lane group; inactive-lane masks are not modeled |
| Word width | 32 bits | Two 16-bit halves per lane |
| `SLOTS` | 4 | Configured FIFO capacity; a simulation choice |
| `LATENCY` | 1 cycle | Synthetic return delay; not the measured 29-cycle effective dependent recurrence |
| `INTERVAL` | 1 cycle | Synthetic minimum request spacing; not a private hardware initiation interval |
| Request/response identity | 32 bits | Distinguishes live operations; duplicate live identities are rejected |

The earlier 29-cycle MOVM result is an effective dependent recurrence measured with compiled scheduling controls. It must not be silently substituted for this module's intrinsic latency or added again as a separate dependency delay. Physical latency and service interval remain unseparated. The module permits controlled synthetic timing while preserving the measured value transformation.

#### Interface, storage and transition rules

| Signals | Direction | Contract |
|---|---|---|
| `clk`, `rst` | Input | Rising-edge clock and synchronous reset |
| `req_valid`, `req_ready` | Input/output | Accept one word from every lane when both are asserted |
| `req_id[31:0]`, `input_words[32]` | Input | Identity and captured 32-bit lane values |
| `rsp_valid`, `rsp_ready` | Output/input | Return/retire the oldest accepted operation |
| `rsp_id[31:0]`, `output_words[32]` | Output | Matching identity and transformed words, valid only with `rsp_valid` |
| `outstanding` | Output | Number of occupied FIFO slots |

At acceptance, the service applies the measured permutation and stores the result, identity and synthetic due cycle in the FIFO tail. Each slot stores 32 result words, one identity, one due-cycle counter and an occupied flag. The admission interval determines the next eligible acceptance cycle. The head becomes visible only when its configured due cycle has arrived. A held response remains in the head slot; retirement releases it and advances the head.

Simultaneous acceptance and retirement preserve the outstanding count. A full queue does not accept a replacement on its retirement edge, so reuse waits one cycle. Duplicate identities are checked against pre-edge occupied slots, including an identity being retired on that edge. Reset clears the queue and its cycle state. The signed cycle counter limits the current implementation to short simulation runs; counter wrap is outside the supported contract.

#### Inline behavior model

```systemverilog
// One MOVM.16.MT88 over one32-bit register per lane. Mapping is measured;
// latency, initiation interval, FIFO policy and capacity are model choices.
module native_movm_word_pipeline #(
 parameter int SLOTS=4,LATENCY=1,INTERVAL=1
)(
 input logic clk,rst,req_valid,output logic req_ready,input logic [31:0] req_id,
 input logic [31:0] input_words[32],
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,output_words[32],output int outstanding
);
 int cycle,head,tail,next_accept,due[SLOTS];
 logic occupied[SLOTS];logic [31:0] ids[SLOTS],values[SLOTS][32];
 logic push,pop;
 initial if(SLOTS<1||LATENCY<1||INTERVAL<1)$fatal(1,"Invalid MOVM model parameters");
 assign req_ready=!rst&&outstanding<SLOTS&&cycle>=next_accept;
 assign rsp_valid=!rst&&outstanding>0&&cycle>=due[head];
 assign rsp_id=ids[head];
 assign push=req_valid&&req_ready;assign pop=rsp_valid&&rsp_ready;
 for(genvar lane=0;lane<32;lane++)assign output_words[lane]=values[head][lane];
 always_ff @(posedge clk)begin
  if(rst)begin
   cycle<=0;head<=0;tail<=0;next_accept<=0;outstanding<=0;
   for(int slot=0;slot<SLOTS;slot++)begin occupied[slot]<=0;ids[slot]<=0;due[slot]<=0;end
  end else begin
   cycle<=cycle+1;
   if(push)begin
    for(int slot=0;slot<SLOTS;slot++)if(occupied[slot]&&ids[slot]==req_id)
     $fatal(1,"Duplicate live MOVM identity");
    for(int lane=0;lane<32;lane++)for(int halfword=0;halfword<2;halfword++)begin
     int source;source=library_movm_permutation::pre_index(lane*8+halfword);
     values[tail][lane][16*halfword+:16]<=input_words[source/8][16*(source%2)+:16];
    end
    ids[tail]<=req_id;due[tail]<=cycle+LATENCY;occupied[tail]<=1;
    tail<=(tail+1)%SLOTS;next_accept<=cycle+INTERVAL;
   end
   if(pop)begin occupied[head]<=0;head<=(head+1)%SLOTS;end
   case({push,pop})
    2'b10:outstanding<=outstanding+1;
    2'b01:outstanding<=outstanding-1;
    default:outstanding<=outstanding;
   endcase
  end
 end
 // Values snapshot at admission and remain hidden until unit return becomes
 // valid. A full queue does not admit replacement on the retirement edge.
endmodule
```

#### Verification and limits

Run `python numerical/verify_native_movm_word.py` from the RTL directory. The [receipt](numerical/native_movm_word_verification.json) reports 131,840 output-word comparisons using 515 saved GPU mapping cases. Each case supplies four individual word operations. The reference outputs are actual saved post-MOVM BF16 fragments; the raw input words are reconstructed independently from the original coordinate, identity and basis inputs and ordinary load addresses. Two synthetic configurations, latency/interval 1/1 and 7/3, each check 65,920 words. These are local simulations replaying preserved measurements; no new GPU experiment was launched.

The evidence supports the tested finite BF16 lane/register mapping. It does not establish arbitrary exceptional-bit behavior, partial-warp behavior, intrinsic MOVM latency, FIFO capacity, or physical arbitration policy. The response can supply an actual completion event to the issue gate, but connecting these components does not by itself recover the original instruction schedule or GPU runtime.


### 4.37. Original operand hot-loop window with decoded native controls

**Purpose and exact boundary.** PC means program counter, the byte address of an instruction inside the compiled function. The [native stage pipeline](numerical/native_studied_stage_pipeline.sv) executes the supported operand/value sequence at native addresses `0x1350` through `0x15c0` from the [original kernel schedule](discovery_rounds/original_native_schedule/original_kernel_schedule.json). It covers one 16 × 16 output fragment through a 32-element reduction step of the original 32 × 32 block. It is not the complete kernel: instructions before and after this window, branch replay, global-load issue, block scheduling and native address-arithmetic dependencies are absent.

One accepted external request supplies a fragment index zero to three, a 32-bit ID and 32 × 8 initial FP32 accumulators. Shared storage is 4,096 bytes, written through a halfword ready/valid port. All referenced words must be initialized before acceptance. The request computes two 16-element slices and returns 256 FP32 accumulator words. Four native HMMA services perform the lower/upper output halves of each slice; a whole-WMMA delay is not substituted for them.

**Generated instruction descriptors.** `generate_native_studied_stage.py` selects exactly 40 contiguous native instructions from the saved JSON and copies every 128-bit instruction encoding. The decoder from section 4.33 interprets the original wait masks, read/write barrier assignments and issue-delay fields; controls are not hand-retyped. The generated package binds instruction operands to semantic A/B word groups using the saved explicit register operands.

| Window work | Count per fragment step | Numerical action |
|---|---:|---|
| Scalar `LD.E` | 16 | Eight warp words for each of two reduction slices, using original shared offsets |
| `MOVM.16.MT88` | 8 | Four B words per slice, using the measured per-word permutation |
| `HMMA.16816.F32.BF16` | 4 | Lower and upper 16 × 8 results for both slices; actual returned C carries forward |
| Remaining address/control instructions | 12 | Preserve decoded issue controls; no additional numerical result is produced here |

B's second-slice loads occur in the original nonsequential word order 0, 3, 1, 2, interleaved with A loads and address/control instructions. A/B addresses are precomputed from the supported unpadded shared layout. `UMOV`, `IADD.64`, `LEA` and `LEA.HI.X` therefore preserve their controls but do not replay an address ALU or its register dependencies. `WARPSYNC.ALL` represents an already participating full warp in this bounded model; it does not model missing-lane arrivals or CTA barrier machinery. Producer/barrier context before the window is assumed complete at its entry. All saved read-barrier fields inside the window are disabled; the generator rejects a different unsupported contract.

**Actual completion and implicit readiness.** Native issue advances only after the decoded gate and selected service both accept an instruction. Shared reads sample memory at each actual `LD.E` acceptance, rather than snapshotting every value when the external request begins. Writes receive backpressure while a read request is offered, so its addresses and input words stay stable if the read queue is full. Each load completion updates its A or raw-B group. Each MOVM completion updates the transformed B group. Each HMMA completion updates its four C words. Explicit ready flags prevent use before completion even when an instruction has no encoded write barrier.

The semantic group arrays preserve the values required by this specific instruction sequence. They do not reproduce a physical GPR file, register-bank routing or all alias hazards. For example, later MOVM destinations alias registers used earlier for A; earlier HMMA services have already captured those operands. The selected sequence and snapshots make that bounded reuse safe, without claiming a general register model.

A common completion arbiter prioritizes shared reads, then MOVM, then HMMA. It acknowledges only one service response per edge. The same selected handshake commits returned values and emits a write-barrier completion event if that instruction allocated one. Unselected services hold their outputs. This prevents simultaneous returns from losing an event at the issue gate's one-completion interface. At the end of the 40-instruction window, the controller drains all service requests, ready C halves, tracked producers and issue cooldown before exposing the result. A held result blocks a new external operation. Reset invalidates shared words, clears the window and cancels all service/gate state.

**Provisional quantitative choices.** Defaults are four shared-read slots with one-cycle package spacing and one-cycle return delay; four MOVM slots with delay/interval 1/1; and two HMMA slots with delay/interval 16/4. The decoded producer gate holds at most 64 simulation operation tags, using one tag per selected instruction index; that is not a physical queue capacity. These service settings and the all-producers-complete barrier interpretation are hypotheses. The original encoded issue controls are source evidence. Do not add the measured compound MOVM recurrence of about 29 cycles on top of synthetic MOVM latency plus decoded controls: that would combine effective and decomposed costs without a matching calibration experiment.

**Optional vector shared writes.** `ALLOW_WARP_WRITES = 0` disables the added interface for legacy callers. When enabled, `write_warp_valid/write_warp_ready` accepts 32 byte addresses, 32 halfwords and a 32-bit active mask. Every active address must be even and at most 4,094, and active addresses must be distinct. A scalar write offer or held native load offer blocks acceptance. An accepted packet updates all active halfwords on one edge; inactive neighboring halfwords remain unchanged. An empty mask is a no-op. This is an ideal commit interface, not a modeled native shared-store pipeline. The [vector-write receipt](numerical/native_studied_stage_warp_write_verification.json) verifies 1,024 numerical outputs and 160 issued instruction addresses after 64 packets initialize all 2,048 halfwords, plus masked-neighbor preservation, scalar priority and invalid alignment/duplicate rejection.

**Independent verification.** The [window receipt](numerical/native_studied_stage_verification.json) checks 1,024 output words across all four fragments, with nonzero initial C, against a direct 32-element dot product. It verifies every one of 160 issued instruction addresses in exact native order, initialized-operand gating, held output and reset. Synthetic read-return/MOVM/HMMA delays are 9/19/73 cycles. Deliberately long operation delays exercise explicit completion readiness beyond the encoded instruction spacing; they are not latency estimates.

The [end-to-end native CTA receipt](numerical/studied_gemm_cta_native_verification.json) checks another 5,120 final output words through global sector returns, staging, this native operand window, all accumulation and acknowledged stores. Its supported full-reduction case is the first 32 × 32 CTA through K1536. Global loads and fragment scheduling remain serial; the 64 × 48 block continues to use the baseline path. Source hashes match the tested files. No hardware timing comparison or new physical field closure has been made.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_native_studied_stage.py` for the window check and `python studies/rtx5090_gemm_milp/rtl/numerical/verify_studied_gemm_cta.py --native-stage` for integration.

**Authoritative native stage implementation.**

```systemverilog
// Bounded original BM32/BN32/BK32 PC1350..15c0 operand hot loop.
// Actual decoded issue controls and service completions; address ALU instructions
// are control-only with precomputed shared offsets, not native address replay.
module native_studied_stage_pipeline #(
 parameter bit ALLOW_WARP_WRITES=0,
 parameter int READ_SLOTS=4,SERVICE_INTERVAL=1,RETURN_DELAY=1,
 parameter int MOVM_SLOTS=4,MOVM_LATENCY=1,MOVM_INTERVAL=1,
 parameter int HMMA_SLOTS=2,HMMA_LATENCY=16,HMMA_INTERVAL=4,ARITHMETIC_MODE=1
)(
 input logic clk,rst,
 input logic write_valid,output logic write_ready,
 input logic[31:0]write_byte_address,input logic[15:0]write_data,
 input logic write_warp_valid,output logic write_warp_ready,
 input logic[31:0]write_warp_byte_addresses[32],
 input logic[15:0]write_warp_halfwords[32],input logic[31:0]write_warp_mask,
 input logic req_valid,output logic req_ready,input logic[31:0]req_id,tile_index,
 input logic[31:0]c_registers[32][8],
 output logic operands_initialized,addresses_legal,
 output logic rsp_valid,input logic rsp_ready,
 output logic[31:0]rsp_id,result_registers[32][8],output int outstanding,
 output logic native_issue_valid,output logic[31:0]native_issue_pc
);
 import native_studied_stage_schedule::*;
 localparam int HALFWORDS=2048;
 typedef enum logic[1:0]{IDLE,RUN,DRAIN,RESPONSE} state_t;
 state_t state;int pc;logic[31:0]saved_id,saved_tile;
 logic[15:0]memory[HALFWORDS];logic initialized[HALFWORDS];
 logic[31:0]a_words[2][32][4],b_raw[2][32][4],b_moved[2][32][4],accumulator[32][8];
 logic a_ready[2][4],b_ready[2][4],mov_ready[2][4],c_ready[2];
 descriptor_t desc,completion_desc;
 native_control_decode::control_t control,completion_control;
 logic dependencies_ready,gate_valid,gate_ready,dispatch_valid,dispatch_ready,issued,gate_error;
 logic[5:0]busy_write,busy_read;logic[3:0]cooldown;
 logic write_complete_valid;logic[6:0]write_complete_tag;
 logic read_req_valid,read_req_ready,read_rsp_valid,read_rsp_ready;
 logic[31:0]read_req_id,read_rsp_id,read_addresses[32],read_inputs[32],read_outputs[32];int read_outstanding;
 logic mov_req_valid,mov_req_ready,mov_rsp_valid,mov_rsp_ready;
 logic[31:0]mov_req_id,mov_rsp_id,mov_inputs[32],mov_outputs[32];int mov_outstanding;
 logic h_req_valid,h_req_ready,h_rsp_valid,h_rsp_ready;
 logic[31:0]h_req_id,h_rsp_id,h_a[32][4],h_b[32][2],h_c[32][4],h_results[32][4];int h_outstanding;
 logic completion_valid,write_address_legal,write_warp_legal;logic[31:0]completion_id;
 function automatic int address(input bit operand_b,input int kk,word_index,lane,tile);
  if(operand_b)return 2048+64*(16*kk+lane/4)+32*(tile%2)+4*(lane%4)+(word_index%2)*512+(word_index/2)*16;
  return 64*(16*(tile/2)+lane/4)+32*kk+4*(lane%4)+(word_index%2)*512+(word_index/2)*16;
 endfunction
 assign write_address_legal=write_byte_address[0]==0&&write_byte_address<=4094;
 // Memory is read at native LD.E issue, not at external stage acceptance.
 // Block writes while that request is offered so a stalled read payload stays stable.
 assign write_ready=!rst&&write_address_legal&&!read_req_valid;
 // Optional ideal vector commit port. It does not model a native STS issue rate.
 // Disabled by default so legacy callers need not drive the optional inputs.
 always_comb begin
  write_warp_legal=1;
  if(ALLOW_WARP_WRITES)begin
   for(int lane=0;lane<32;lane++)if(write_warp_mask[lane])begin
    if(write_warp_byte_addresses[lane][0]!=0||write_warp_byte_addresses[lane]>4094)write_warp_legal=0;
    for(int other=0;other<lane;other++)if(write_warp_mask[other]&&
     write_warp_byte_addresses[lane]==write_warp_byte_addresses[other])write_warp_legal=0;
   end
  end
 end
 assign write_warp_ready=ALLOW_WARP_WRITES&&!rst&&write_warp_legal&&!write_valid&&!read_req_valid;
 assign req_ready=!rst&&state==IDLE&&addresses_legal&&operands_initialized;
 assign rsp_valid=!rst&&state==RESPONSE;assign rsp_id=saved_id;
 assign outstanding=state==IDLE?0:1;
 assign native_issue_valid=issued;assign native_issue_pc=32'h1350+32'(16*pc);
 always_comb begin
  addresses_legal=tile_index<4;operands_initialized=addresses_legal;
  if(addresses_legal)for(int kk=0;kk<2;kk++)for(int lane=0;lane<32;lane++)for(int word_index=0;word_index<4;word_index++)begin
   operands_initialized=operands_initialized&&
    initialized[address(0,kk,word_index,lane,int'(tile_index))/2]&&
    initialized[address(0,kk,word_index,lane,int'(tile_index))/2+1]&&
    initialized[address(1,kk,word_index,lane,int'(tile_index))/2]&&
    initialized[address(1,kk,word_index,lane,int'(tile_index))/2+1];
  end
  desc='0;if(pc<INSTRUCTIONS)desc=descriptor(pc);
  control=native_control_decode::decode(desc.raw);
  dependencies_ready=1;
  if(desc.kind==2)dependencies_ready=b_ready[desc.kk][desc.word_index];
  if(desc.kind==3)begin
   dependencies_ready=c_ready[desc.upper_half];
   for(int w=0;w<4;w++)dependencies_ready=dependencies_ready&&a_ready[desc.kk][w];
   for(int w=0;w<2;w++)dependencies_ready=dependencies_ready&&mov_ready[desc.kk][2*int'(desc.upper_half)+w];
  end
  dispatch_ready=1;
  case(desc.kind)
   1:dispatch_ready=read_req_ready;
   2:dispatch_ready=mov_req_ready;
   3:dispatch_ready=h_req_ready;
   default:dispatch_ready=1;
  endcase
  for(int lane=0;lane<32;lane++)begin
   int location;location=address(desc.operand_b,int'(desc.kk),int'(desc.word_index),lane,int'(saved_tile));
   read_addresses[lane]=32'(location);
   read_inputs[lane]={memory[location/2+1],memory[location/2]};
   mov_inputs[lane]=b_raw[desc.kk][lane][desc.word_index];
   for(int w=0;w<4;w++)begin
    h_a[lane][w]=a_words[desc.kk][lane][w];
    h_c[lane][w]=accumulator[lane][4*int'(desc.upper_half)+w];
   end
   for(int w=0;w<2;w++)h_b[lane][w]=b_moved[desc.kk][lane][2*int'(desc.upper_half)+w];
   for(int w=0;w<8;w++)result_registers[lane][w]=accumulator[lane][w];
  end
  // One completion is acknowledged per edge so the barrier gate receives one
  // actual write-completion event. Other services retain their response slots.
  read_rsp_ready=!rst&&(state==RUN||state==DRAIN);
  mov_rsp_ready=read_rsp_ready&&!read_rsp_valid;
  h_rsp_ready=mov_rsp_ready&&!mov_rsp_valid;
  completion_valid=(read_rsp_valid&&read_rsp_ready)||(mov_rsp_valid&&mov_rsp_ready)||(h_rsp_valid&&h_rsp_ready);
  completion_id=read_rsp_valid?read_rsp_id:(mov_rsp_valid?mov_rsp_id:h_rsp_id);
  completion_desc='0;
  if(completion_valid&&completion_id<INSTRUCTIONS)completion_desc=descriptor(int'(completion_id));
  completion_control=native_control_decode::decode(completion_desc.raw);
  write_complete_valid=completion_valid&&completion_control.write_barrier!=7;
  write_complete_tag=7'(completion_id);
 end
 assign gate_valid=!rst&&state==RUN&&pc<INSTRUCTIONS&&dependencies_ready;
 assign read_req_valid=dispatch_valid&&desc.kind==1;assign read_req_id=32'(pc);
 assign mov_req_valid=dispatch_valid&&desc.kind==2;assign mov_req_id=32'(pc);
 assign h_req_valid=dispatch_valid&&desc.kind==3;assign h_req_id=32'(pc);
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;pc<=0;saved_id<=0;saved_tile<=0;
   for(int i=0;i<HALFWORDS;i++)initialized[i]<=0;
   for(int kk=0;kk<2;kk++)for(int w=0;w<4;w++)begin a_ready[kk][w]<=0;b_ready[kk][w]<=0;mov_ready[kk][w]<=0;end
   for(int h=0;h<2;h++)c_ready[h]<=0;
   for(int lane=0;lane<32;lane++)for(int w=0;w<8;w++)accumulator[lane][w]<=0;
  end else begin
   if(write_valid&&!write_address_legal)$fatal(1,"Invalid native stage shared write");
   if(ALLOW_WARP_WRITES&&write_warp_valid&&!write_warp_legal)$fatal(1,"Invalid native stage warp write");
   if(req_valid&&!addresses_legal)$fatal(1,"Invalid native stage tile index");
   if(gate_error)$fatal(1,"Native stage issue/barrier tracking error");
   if(write_valid&&write_ready)begin memory[write_byte_address/2]<=write_data;initialized[write_byte_address/2]<=1;end
   if(ALLOW_WARP_WRITES&&write_warp_valid&&write_warp_ready)
    for(int lane=0;lane<32;lane++)if(write_warp_mask[lane])begin
     memory[write_warp_byte_addresses[lane]/2]<=write_warp_halfwords[lane];
     initialized[write_warp_byte_addresses[lane]/2]<=1;
    end
   if(completion_valid&&completion_id>=INSTRUCTIONS)$fatal(1,"Unknown native stage completion ID");
   if(read_rsp_valid&&read_rsp_ready)begin
    if(completion_desc.kind!=1)$fatal(1,"Read completion ID is not a load");
    for(int lane=0;lane<32;lane++)begin
     if(completion_desc.operand_b)b_raw[completion_desc.kk][lane][completion_desc.word_index]<=read_outputs[lane];
     else a_words[completion_desc.kk][lane][completion_desc.word_index]<=read_outputs[lane];
    end
    if(completion_desc.operand_b)b_ready[completion_desc.kk][completion_desc.word_index]<=1;
    else a_ready[completion_desc.kk][completion_desc.word_index]<=1;
   end
   if(mov_rsp_valid&&mov_rsp_ready)begin
    if(completion_desc.kind!=2)$fatal(1,"MOVM completion ID is not MOVM");
    for(int lane=0;lane<32;lane++)b_moved[completion_desc.kk][lane][completion_desc.word_index]<=mov_outputs[lane];
    mov_ready[completion_desc.kk][completion_desc.word_index]<=1;
   end
   if(h_rsp_valid&&h_rsp_ready)begin
    if(completion_desc.kind!=3)$fatal(1,"HMMA completion ID is not HMMA");
    for(int lane=0;lane<32;lane++)for(int w=0;w<4;w++)accumulator[lane][4*int'(completion_desc.upper_half)+w]<=h_results[lane][w];
    c_ready[completion_desc.upper_half]<=1;
   end
   case(state)
    IDLE:if(req_valid&&req_ready)begin
     saved_id<=req_id;saved_tile<=tile_index;pc<=0;state<=RUN;
     for(int kk=0;kk<2;kk++)for(int w=0;w<4;w++)begin a_ready[kk][w]<=0;b_ready[kk][w]<=0;mov_ready[kk][w]<=0;end
     for(int h=0;h<2;h++)c_ready[h]<=1;
     for(int lane=0;lane<32;lane++)for(int w=0;w<8;w++)accumulator[lane][w]<=c_registers[lane][w];
    end
    RUN:if(issued)begin
     if(desc.kind==3)c_ready[desc.upper_half]<=0;
     if(pc==INSTRUCTIONS-1)begin pc<=INSTRUCTIONS;state<=DRAIN;end
     else pc<=pc+1;
    end
    DRAIN:if(read_outstanding==0&&mov_outstanding==0&&h_outstanding==0&&busy_write==0&&busy_read==0&&cooldown==0&&c_ready[0]&&c_ready[1])state<=RESPONSE;
    RESPONSE:if(rsp_valid&&rsp_ready)state<=IDLE;
    default:$fatal(1,"Invalid native stage state");
   endcase
  end
 end
 decoded_native_issue_gate #(.MAX_OPS(64),.TAG_W(7),.COUNT_W(7)) gate(
  .clk,.reset(rst||state==IDLE),.instr_valid(gate_valid),.instr_ready(gate_ready),
  .operation_id(7'(pc)),.control,.dispatch_valid,.dispatch_ready,.issued,
  .write_complete_valid,.write_complete_tag,.read_complete_valid(1'b0),.read_complete_tag(7'd0),
  .busy_write_mask(busy_write),.busy_read_mask(busy_read),.cooldown,.error_sticky(gate_error)
 );
 warp_shared_read_service #(.SLOTS(READ_SLOTS),.SERVICE_INTERVAL(SERVICE_INTERVAL),.RETURN_DELAY(RETURN_DELAY)) reads(
  .clk,.rst,.req_valid(read_req_valid),.req_ready(read_req_ready),.req_id(read_req_id),
  .byte_addresses(read_addresses),.input_words(read_inputs),.rsp_valid(read_rsp_valid),.rsp_ready(read_rsp_ready),
  .rsp_id(read_rsp_id),.output_words(read_outputs),.outstanding(read_outstanding)
 );
 native_movm_word_pipeline #(.SLOTS(MOVM_SLOTS),.LATENCY(MOVM_LATENCY),.INTERVAL(MOVM_INTERVAL)) moves(
  .clk,.rst,.req_valid(mov_req_valid),.req_ready(mov_req_ready),.req_id(mov_req_id),.input_words(mov_inputs),
  .rsp_valid(mov_rsp_valid),.rsp_ready(mov_rsp_ready),.rsp_id(mov_rsp_id),.output_words(mov_outputs),.outstanding(mov_outstanding)
 );
 native_hmma16816_adapter #(.SLOTS(HMMA_SLOTS),.LATENCY(HMMA_LATENCY),.INTERVAL(HMMA_INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) tensor(
  .clk,.rst,.req_valid(h_req_valid),.req_ready(h_req_ready),.req_id(h_req_id),.a_registers(h_a),.b_registers(h_b),.c_registers(h_c),
  .rsp_valid(h_rsp_valid),.rsp_ready(h_rsp_ready),.rsp_id(h_rsp_id),.result_registers(h_results),.outstanding(h_outstanding)
 );
endmodule
```

**Generated descriptor package.** The source JSON hash is retained in the generated header and [generation receipt](numerical/native_studied_stage_schedule_generation.json).

```systemverilog
// Generated from original_kernel_schedule.json; do not hand-edit controls.
// Source SHA256 caf4f615c0c29d25558d721963f78172b22923d91fdb4258539d2994dbb8af5b
package native_studied_stage_schedule;
 localparam int INSTRUCTIONS=40;
 typedef struct packed {logic[127:0] raw;logic[1:0] kind;logic operand_b;logic kk;logic[1:0] word_index;logic upper_half;} descriptor_t;
 function automatic descriptor_t descriptor(input int index);
  descriptor_t d;d='0;
  case(index)
   0:begin d.raw=128'h000ee8000c1019000008000a221c7980;d.kind=2'd1;d.operand_b=1'b1;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x1350 LD.E
   1:begin d.raw=128'h000f28000c101900000a000a221d7980;d.kind=2'd1;d.operand_b=1'b1;d.kk=1'b0;d.word_index=2'd1;d.upper_half=1'b0;end // 0x1360 LD.E
   2:begin d.raw=128'h000f68000c1019000008100a22187980;d.kind=2'd1;d.operand_b=1'b1;d.kk=1'b0;d.word_index=2'd2;d.upper_half=1'b0;end // 0x1370 LD.E
   3:begin d.raw=128'h000f62000c101900000a100a22197980;d.kind=2'd1;d.operand_b=1'b1;d.kk=1'b0;d.word_index=2'd3;d.upper_half=1'b0;end // 0x1380 LD.E
   4:begin d.raw=128'h000fe200080000000000000600067c82;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x1390 UMOV
   5:begin d.raw=128'h004fc400080000000000000900077c82;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x13a0 UMOV
   6:begin d.raw=128'h000fe4000f8e02000000000608087c35;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x13b0 IADD.64
   7:begin d.raw=128'h000ea6000c101900000c000a22057980;d.kind=2'd1;d.operand_b=1'b1;d.kk=1'b1;d.word_index=2'd0;d.upper_half=1'b0;end // 0x13c0 LD.E
   8:begin d.raw=128'h040fe200078210ff0000000806207211;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x13d0 LEA
   9:begin d.raw=128'h000ea6000c101900000e100a221a7980;d.kind=2'd1;d.operand_b=1'b1;d.kk=1'b1;d.word_index=2'd3;d.upper_half=1'b0;end // 0x13e0 LD.E
   10:begin d.raw=128'h000fe400008f14070000000906217211;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x13f0 LEA.HI.X
   11:begin d.raw=128'h000ea8000c101900000e000a22067980;d.kind=2'd1;d.operand_b=1'b1;d.kk=1'b1;d.word_index=2'd1;d.upper_half=1'b0;end // 0x1400 LD.E
   12:begin d.raw=128'h000ea8000c1019000000000a200c7980;d.kind=2'd1;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x1410 LD.E
   13:begin d.raw=128'h000ea8000c1019000002000a200d7980;d.kind=2'd1;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd1;d.upper_half=1'b0;end // 0x1420 LD.E
   14:begin d.raw=128'h000ea8000c1019000000100a200e7980;d.kind=2'd1;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd2;d.upper_half=1'b0;end // 0x1430 LD.E
   15:begin d.raw=128'h000ea8000c1019000002100a200f7980;d.kind=2'd1;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd3;d.upper_half=1'b0;end // 0x1440 LD.E
   16:begin d.raw=128'h000ea8000c101900000c100a22077980;d.kind=2'd1;d.operand_b=1'b1;d.kk=1'b1;d.word_index=2'd2;d.upper_half=1'b0;end // 0x1450 LD.E
   17:begin d.raw=128'h000ea8000c1019000000200a20087980;d.kind=2'd1;d.operand_b=1'b0;d.kk=1'b1;d.word_index=2'd0;d.upper_half=1'b0;end // 0x1460 LD.E
   18:begin d.raw=128'h000ea8000c1019000002200a20097980;d.kind=2'd1;d.operand_b=1'b0;d.kk=1'b1;d.word_index=2'd1;d.upper_half=1'b0;end // 0x1470 LD.E
   19:begin d.raw=128'h000ea8000c1019000000300a200a7980;d.kind=2'd1;d.operand_b=1'b0;d.kk=1'b1;d.word_index=2'd2;d.upper_half=1'b0;end // 0x1480 LD.E
   20:begin d.raw=128'h000ea2000c1019000002300a200b7980;d.kind=2'd1;d.operand_b=1'b0;d.kk=1'b1;d.word_index=2'd3;d.upper_half=1'b0;end // 0x1490 LD.E
   21:begin d.raw=128'h000fea00038000000000000000007948;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x14a0 WARPSYNC.ALL
   22:begin d.raw=128'h000fe200000000000000000000007918;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x14b0 NOP
   23:begin d.raw=128'h008fe80000000000000000001c1c723a;d.kind=2'd2;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x14c0 MOVM.16.MT88
   24:begin d.raw=128'h010ea80000000000000000001d1d723a;d.kind=2'd2;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd1;d.upper_half=1'b0;end // 0x14d0 MOVM.16.MT88
   25:begin d.raw=128'h020fe80000000000000000001818723a;d.kind=2'd2;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd2;d.upper_half=1'b0;end // 0x14e0 MOVM.16.MT88
   26:begin d.raw=128'h000e220000000000000000001919723a;d.kind=2'd2;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd3;d.upper_half=1'b0;end // 0x14f0 MOVM.16.MT88
   27:begin d.raw=128'h004fde00000418140000001c0c14723c;d.kind=2'd3;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x1500 HMMA.16816.F32.BF16
   28:begin d.raw=128'h000fe200000000000000000000007918;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x1510 NOP
   29:begin d.raw=128'h001fe20000041810000000180c10723c;d.kind=2'd3;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b1;end // 0x1520 HMMA.16816.F32.BF16
   30:begin d.raw=128'h000fe8000000000000000000050c723a;d.kind=2'd2;d.operand_b=1'b0;d.kk=1'b1;d.word_index=2'd0;d.upper_half=1'b0;end // 0x1530 MOVM.16.MT88
   31:begin d.raw=128'h000e28000000000000000000060d723a;d.kind=2'd2;d.operand_b=1'b0;d.kk=1'b1;d.word_index=2'd1;d.upper_half=1'b0;end // 0x1540 MOVM.16.MT88
   32:begin d.raw=128'h000fe8000000000000000000070e723a;d.kind=2'd2;d.operand_b=1'b0;d.kk=1'b1;d.word_index=2'd2;d.upper_half=1'b0;end // 0x1550 MOVM.16.MT88
   33:begin d.raw=128'h000e660000000000000000001a0f723a;d.kind=2'd2;d.operand_b=1'b0;d.kk=1'b1;d.word_index=2'd3;d.upper_half=1'b0;end // 0x1560 MOVM.16.MT88
   34:begin d.raw=128'h001fde00000418140000000c0814723c;d.kind=2'd3;d.operand_b=1'b0;d.kk=1'b1;d.word_index=2'd0;d.upper_half=1'b0;end // 0x1570 HMMA.16816.F32.BF16
   35:begin d.raw=128'h000fe200000000000000000000007918;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x1580 NOP
   36:begin d.raw=128'h002fde00000418100000000e0810723c;d.kind=2'd3;d.operand_b=1'b0;d.kk=1'b1;d.word_index=2'd0;d.upper_half=1'b1;end // 0x1590 HMMA.16816.F32.BF16
   37:begin d.raw=128'h000fdc00000000000000000000007918;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x15a0 NOP
   38:begin d.raw=128'h000fea00038000000000000000007948;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x15b0 WARPSYNC.ALL
   39:begin d.raw=128'h000fe200000000000000000000007918;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x15c0 NOP
   default:$fatal(1,"Native stage instruction index out of range");
  endcase
  return d;
 endfunction
endpackage
```

### 4.38. Coalesced 32-lane BF16 global reads

**Purpose.** The [coalesced load module](numerical/coalesced_u16_warp_load.sv) obtains up to 32 aligned 16-bit values while requesting each distinct 32-byte sector once per warp request. For example, 32 contiguous BF16 values occupy 64 bytes and need two sectors; 32 lanes reading the same halfword need one. This implements functional request grouping without asserting the GPU’s physical issue rate or number of concurrent memory requests.

**Ports and state.** An accepted request captures a 32-bit ID, 32 byte addresses and a 32-bit active mask. Only active addresses must be even. The response supplies 32 halfwords, the retained ID and the number of unique sectors; inactive lanes return zero. Backing interfaces carry actual ID-matched 256-bit packets through the cache in section 4.25. `SETS = 64` and `WAYS = 8` are configurable hypotheses. One warp is outstanding.

IDLE constructs a list of unique sectors in first-lane order. SEND offers one cache request; WAIT_PACKET accepts its actual response and extracts the relevant halfwords. A halfword at byte offset 30 uses the final 16 bits of the packet, so no aligned value crosses a sector boundary. The next sector starts only after the current packet completes. An empty mask enters RESPONSE without cache traffic. Returned values remain stable under backpressure. Reset cancels outstanding work, and the provider must discard pre-reset returns. Cached backing data must remain immutable between requests unless the cache is reset.

**Verification and timing boundary.** The [standalone receipt](numerical/coalesced_u16_warp_load_verification.json) checks 224 lane values across seven cases: contiguous input, cached replay, broadcast, eight-sector scatter, 32-sector scatter, a partial mask and an empty mask. Their unique-sector counts are 2, 2, 1, 8, 32, 1 and 0. Alignment and wrong completion IDs are rejected. The connected CTA verification in section 4.34 then checks the original full reduction and output stores. Serial unique-sector service, a blocking cache and ideal vector shared commits are implementation choices. They do not establish hardware queue capacities, coalescing latency or physical runtime accuracy, and no parameter closure is added.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_coalesced_u16_warp_load.py` for the standalone check. Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_studied_gemm_cta.py --native-stage --coalesced-staging` for the connected original CTA.

**Inline behavior.**

```systemverilog
// Functional 32-byte-sector coalescing of up to32 active aligned u16 loads.
// Unique sectors are serviced serially through a blocking cache hypothesis.
// This does not identify GPU request issue rate, arbitration, or L2 geometry.
module coalesced_u16_warp_load #(parameter int SETS=64,WAYS=8)(
 input logic clk,rst,req_valid,output logic req_ready,input logic[31:0]req_id,
 input logic[31:0]byte_addresses[32],input logic[31:0]active_mask,
 output logic rsp_valid,input logic rsp_ready,output logic[31:0]rsp_id,
 output logic[15:0]halfwords[32],output int sector_count,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data
);
 typedef enum logic[1:0]{IDLE,SEND,WAIT_PACKET,RESPONSE}state_t;
 state_t state;
 logic[31:0]saved_id,saved_addresses[32],saved_mask,sector_list[32],candidate_sectors[32];
 int candidate_count,current_sector;logic addresses_legal;logic lane_found[32];
 logic cache_req_valid,cache_req_ready,cache_rsp_valid,cache_rsp_ready,cache_rsp_hit;
 logic[31:0]cache_id,cache_rsp_id,cache_rsp_word;logic[255:0]cache_packet;
 always_comb begin
  candidate_count=0;addresses_legal=1;
  for(int i=0;i<32;i++)begin candidate_sectors[i]=0;lane_found[i]=0;end
  for(int lane=0;lane<32;lane++)if(active_mask[lane])begin
   if(byte_addresses[lane][0])addresses_legal=0;
   for(int i=0;i<32;i++)if(i<candidate_count&&candidate_sectors[i]=={byte_addresses[lane][31:5],5'b0})lane_found[lane]=1;
   if(!lane_found[lane])begin candidate_sectors[candidate_count]={byte_addresses[lane][31:5],5'b0};candidate_count=candidate_count+1;end
  end
 end
 assign req_ready=!rst&&state==IDLE&&addresses_legal;
 assign rsp_valid=!rst&&state==RESPONSE;assign rsp_id=saved_id;
 assign cache_req_valid=!rst&&state==SEND;
 assign cache_rsp_ready=!rst&&state==WAIT_PACKET;
 // XOR with0..31 is injective for this single inflight warp; external ID is retained.
 assign cache_id=saved_id^32'(current_sector);
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;saved_id<=0;saved_mask<=0;sector_count<=0;current_sector<=0;
   for(int lane=0;lane<32;lane++)begin saved_addresses[lane]<=0;halfwords[lane]<=0;sector_list[lane]<=0;end
  end else begin
   if(req_valid&&state==IDLE&&!addresses_legal)$fatal(1,"Unaligned active u16 lane address");
   case(state)
    IDLE:if(req_valid&&req_ready)begin
     saved_id<=req_id;saved_mask<=active_mask;sector_count<=candidate_count;current_sector<=0;
     for(int lane=0;lane<32;lane++)begin
      saved_addresses[lane]<=byte_addresses[lane];sector_list[lane]<=candidate_sectors[lane];halfwords[lane]<=0;
     end
     if(candidate_count==0)state<=RESPONSE;else state<=SEND;
    end
    SEND:if(cache_req_valid&&cache_req_ready)state<=WAIT_PACKET;
    WAIT_PACKET:if(cache_rsp_valid&&cache_rsp_ready)begin
     if(cache_rsp_id!=cache_id)$fatal(1,"Warp sector completion identity mismatch");
     for(int lane=0;lane<32;lane++)if(saved_mask[lane]&&
       {saved_addresses[lane][31:5],5'b0}==sector_list[current_sector])
      halfwords[lane]<=cache_packet[int'(saved_addresses[lane][4:0])*8+:16];
     if(current_sector==sector_count-1)state<=RESPONSE;
     else begin current_sector<=current_sector+1;state<=SEND;end
    end
    RESPONSE:if(rsp_valid&&rsp_ready)state<=IDLE;
    default:$fatal(1,"Invalid coalesced warp state");
   endcase
  end
 end
 sector_read_cache #(.SETS(SETS),.WAYS(WAYS)) cache(
  .clk,.rst,.req_valid(cache_req_valid),.req_ready(cache_req_ready),.req_id(cache_id),
  .req_byte_address(sector_list[current_sector]),.rsp_valid(cache_rsp_valid),.rsp_ready(cache_rsp_ready),
  .rsp_id(cache_rsp_id),.rsp_data(cache_rsp_word),.rsp_sector_data(cache_packet),.rsp_hit(cache_rsp_hit),
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,
  .backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data
 );
 // Empty masks return32zeros without cache traffic. Inactive addresses ignored.
 // Inputs snapshot at acceptance. Providers flush pre-reset traffic; IDs have no epoch.
 // Across requests the cache assumes backing data remains immutable or is reset.
endmodule
```

### 4.39. Masked sector writes from 32 FP32 lane values

**Purpose and interface.** The [coalesced store module](numerical/coalesced_fp32_warp_store.sv) groups up to 32 aligned 32-bit stores into unique 32-byte sectors. An accepted request captures a 32-bit ID, 32 byte addresses, 32 FP32 words and an active-lane mask. Each outgoing sector contains a 256-bit packet and an eight-bit word mask. The backing provider updates only the selected words, leaving every unselected word unchanged. A matching acknowledgment is required before another sector advances; a final response with the original request ID means all selected sector writes have been acknowledged.

Active addresses must be divisible by four and distinct. Duplicate active addresses are rejected even if values agree: this is the simulator’s explicit no-race policy, not a recovered NVIDIA restriction. Inactive addresses are ignored. An empty mask produces a completion without writing memory. The module has no adjustable queue capacity or fitted physical latency; it serializes sectors with one outstanding acknowledgment.

**Behavior and reset.** IDLE groups and snapshots the entire accepted payload. SEND holds the sector address, data, mask and ID until accepted. WAIT_ACK consumes only an ID-matched acknowledgment, then either advances to the next sector or enters RESPONSE. RESPONSE holds completion under backpressure. Reset cancels pending work and requires the provider to discard old acknowledgments. It does not undo writes that the provider has already committed. There is no write cache, external coherence or inferred DRAM persistence guarantee.

**Original output layout.** The controller’s optional `COALESCED_OUTPUT = 1` mode uses this interface instead of scalar output stores. The original kernel first places matrix results in row-major shared scratch, then each lane reads scratch element `lane + 32 × iteration` for its global store. The controller gathers those same values directly from the measured accumulator layout. In direct-gather mode it therefore preserves output addresses and values but bypasses scratch stores, scratch reads and the intervening synchronization. Section 4.41’s optional scratch mode restores the stored/read values while retaining an assumed stronger phase fence. For the 32 × 32 CTA, four 16 × 16 fragments issue eight warp requests each: 32 warp requests, 128 sector packets and 1,024 words. The provider’s actual acknowledgment, rather than a timestamp, controls progress. This is not native output-path timing replay.

**Independent verification.** The [standalone receipt](numerical/coalesced_fp32_warp_store_verification.json) compares 20,480 memory words, including untouched words, across five address/mask cases with 4, 8, 32, 1 and 0 sectors. A separate direct lane-update oracle supplies expected memory contents. The tests include payload changes after acceptance, held requests and acknowledgments, reset, and rejection of misalignment, duplicate active addresses and wrong acknowledgment IDs. These checks establish masked updates and completion ordering, not hardware throughput or cache policy.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_coalesced_fp32_warp_store.py` for the component checks. The connected controller command adds `--coalesced-output` to the native/coalesced-input mode.

The [connected original-CTA receipt](numerical/studied_gemm_cta_coalesced_output_verification.json) adds 5,120 exact final-output comparisons through coalesced input staging, the native operand window and these masked output packets. Each launch verifies 128 packet acknowledgments for all 1,024 output values, including the full K1536 first CTA. No hardware timing or additional physical parameter is identified.

**Inline behavior.**

```systemverilog
// Functional grouping of up to32 independent aligned32-bit lane stores.
// Duplicate active addresses are forbidden by this simulator no-race policy.
// Serial sector service and one outstanding acknowledgement are model choices.
module coalesced_fp32_warp_store(
 input logic clk,rst,req_valid,output logic req_ready,input logic[31:0]req_id,
 input logic[31:0]byte_addresses[32],words[32],input logic[31:0]active_mask,
 output logic rsp_valid,input logic rsp_ready,output logic[31:0]rsp_id,
 output int sector_count,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 output logic[255:0]backing_req_data,output logic[7:0]backing_req_word_mask,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic[31:0]backing_rsp_id
);
 typedef enum logic[1:0]{IDLE,SEND,WAIT_ACK,RESPONSE}state_t;
 state_t state;
 logic[31:0]saved_id,sector_addresses[32],candidate_addresses[32];
 logic[255:0]sector_data[32],candidate_data[32];
 logic[7:0]sector_masks[32],candidate_masks[32];
 int candidate_count,current_sector,chosen_index[32];logic legal,duplicates;
 always_comb begin
  candidate_count=0;legal=1;duplicates=0;
  for(int i=0;i<32;i++)begin
   candidate_addresses[i]=0;candidate_data[i]=0;candidate_masks[i]=0;chosen_index[i]=-1;
  end
  for(int lane=0;lane<32;lane++)if(active_mask[lane])begin
   if(byte_addresses[lane][1:0]!=0)legal=0;
   for(int earlier=0;earlier<32;earlier++)if(earlier<lane&&active_mask[earlier]&&byte_addresses[earlier]==byte_addresses[lane])duplicates=1;
   for(int i=0;i<32;i++)if(i<candidate_count&&candidate_addresses[i]=={byte_addresses[lane][31:5],5'b0})chosen_index[lane]=i;
   if(chosen_index[lane]<0)begin
    chosen_index[lane]=candidate_count;candidate_addresses[candidate_count]={byte_addresses[lane][31:5],5'b0};candidate_count=candidate_count+1;
   end
   candidate_masks[chosen_index[lane]][byte_addresses[lane][4:2]]=1;
   candidate_data[chosen_index[lane]][int'(byte_addresses[lane][4:2])*32+:32]=words[lane];
  end
 end
 assign req_ready=!rst&&state==IDLE&&legal&&!duplicates;
 assign rsp_valid=!rst&&state==RESPONSE;assign rsp_id=saved_id;
 assign backing_req_valid=!rst&&state==SEND;
 assign backing_req_id=saved_id^32'(current_sector);
 assign backing_req_byte_address=sector_addresses[current_sector];
 assign backing_req_data=sector_data[current_sector];
 assign backing_req_word_mask=sector_masks[current_sector];
 assign backing_rsp_ready=!rst&&state==WAIT_ACK;
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;saved_id<=0;sector_count<=0;current_sector<=0;
   for(int i=0;i<32;i++)begin sector_addresses[i]<=0;sector_data[i]<=0;sector_masks[i]<=0;end
  end else begin
   if(req_valid&&state==IDLE&&!legal)$fatal(1,"Unaligned active FP32 store address");
   if(req_valid&&state==IDLE&&duplicates)$fatal(1,"Duplicate active FP32 store address");
   case(state)
    IDLE:if(req_valid&&req_ready)begin
     saved_id<=req_id;sector_count<=candidate_count;current_sector<=0;
     for(int i=0;i<32;i++)begin sector_addresses[i]<=candidate_addresses[i];sector_data[i]<=candidate_data[i];sector_masks[i]<=candidate_masks[i];end
     if(candidate_count==0)state<=RESPONSE;else state<=SEND;
    end
    SEND:if(backing_req_valid&&backing_req_ready)state<=WAIT_ACK;
    WAIT_ACK:if(backing_rsp_valid&&backing_rsp_ready)begin
     if(backing_rsp_id!=backing_req_id)$fatal(1,"Warp store acknowledgement identity mismatch");
     if(current_sector==sector_count-1)state<=RESPONSE;
     else begin current_sector<=current_sector+1;state<=SEND;end
    end
    RESPONSE:if(rsp_valid&&rsp_ready)state<=IDLE;
    default:$fatal(1,"Invalid coalesced store state");
   endcase
  end
 end
 // Empty masks acknowledge with no backing traffic. Inactive addresses ignored.
 // Full payloads snapshot at admission and remain stable under backpressure.
 // Providers must flush pre-reset writes/acks; IDs have no reset generation.
endmodule
```

### 4.40. Four native operand windows sharing finite services

**Question and role.** Can the four fragment warps make progress together while contending for the same modeled shared-read, MOVM and HMMA services? The [multiwarp stage](numerical/native_multiwarp_stage_pipeline.sv) replaces four sequential fragment calls with one batch. Each warp retains its own instruction position, operand values, readiness flags and decoded producer tracking. The services are instantiated once for the entire batch. This makes resource contention executable rather than giving every warp an independent copy of each unit.

The default batch has four warps, each with 32 lanes and one 16 × 16 output fragment. Warp indices zero through three select the four quadrants of the original 32 × 32 output block. Each warp executes section 4.37’s 40-instruction window at addresses 0x1350–0x15c0. The batch therefore issues 160 instructions: 64 shared loads, 32 MOVM operations, 16 HMMA operations and 48 control-only instructions. The latter preserve decoded spacing but use precomputed addresses instead of replaying address arithmetic.

| Interface | Payload | Acceptance or completion |
|---|---|---|
| Clock and reset | `clk`, `rst` | Rising-edge updates; reset cancels all warp and service work |
| Scalar shared write | Byte address, 32 bits; data, 16 bits; valid/ready | An aligned address within the 4,096-byte stage is accepted when no read is being issued |
| Optional vector shared write | 32 byte addresses; 32 halfwords; 32-bit mask; valid/ready | Enabled by `ALLOW_WARP_WRITES`; active addresses must be legal and distinct; scalar/read offers take priority |
| Batch request | 32-bit ID; C registers `[WARPS][32][8]`, 32 bits each; valid/ready | Accepted only while idle and all required shared halfwords are initialized |
| Batch result | Retained ID; result registers `[WARPS][32][8]`; valid/ready | Exposed only after all warps and shared services drain; held until accepted |
| Readiness outputs | `operands_initialized`, `addresses_legal`, `outstanding` | Initialization covers every requested fragment; addresses are fixed by the supported geometry; at most one batch is outstanding |
| Per-warp memory/result conditions | `warp_memory_safe` and `warp_drained`, one bit per warp each | Memory-safe requires the bounded instruction window/cooldown and actual shared reads to finish; fully drained additionally requires tracked producers, C readiness and all accepted service requests to finish; reset/new acceptance clears both |
| Issued-instruction trace | Valid, warp index and instruction address | Reports the one actual decoded instruction issued on that edge |

**State and organization.** One shared array stores 2,048 BF16 halfwords, or 4,096 bytes, with one initialization flag per halfword. Each warp has 256 C words and separate A, raw B and transformed B groups. These semantic arrays preserve supported operation values; their size is not a recovered physical register-file capacity. `WARPS = 4` is the default; the implementation accepts one through four, but the recorded checks exercise four. State advances through IDLE, RUN, DRAIN and RESPONSE. Admission captures all initial C values and resets each warp’s instruction position and local readiness. Shared values are sampled at each accepted native load, not copied at batch admission.

**Issue and completion arbitration.** The issue selector scans warps from a rotating starting index. A warp is eligible only when its decoded control gate and operand readiness permit progress, and its destination service can accept the operation. An accepted-minus-retired shared-read counter limits admission and is checked against the shared service’s outstanding count. At most one instruction issues per edge across the batch. After an accepted issue, the starting index moves to the following warp. A stalled warp can therefore yield to another eligible warp, while each warp’s instruction order stays intact. One global issue port and this round-robin policy are development choices, not discovered RTX scheduler topology or throughput.

Requests carry `warp × 40 + instruction_index` as their internal completion ID. The common response arbiter acknowledges at most one result per edge, prioritizing shared reads, then MOVM, then HMMA. That same acknowledged result updates only its owning warp’s semantic values and readiness and reports the corresponding producer completion to that warp’s gate. Other responses remain held. Explicit readiness still handles operations without encoded write barriers. DRAIN waits for every instruction position, producer tracker, cooldown, C half and service queue before presenting the complete batch result. This preserves completion ownership even when several services finish together. Each warp now also tracks accepted-minus-acknowledged service requests and pending instruction identities. A completion must match an accepted operation, and the sum of per-warp live counts must equal the three shared services’ outstanding counts. The registered `warp_drained` bit rises only after its instruction index reaches 40, all decoded producers/cooldowns clear, both C halves are ready and its live count is zero. A separate registered `warp_memory_safe` bit requires the bounded instruction position/cooldown to finish and its accepted shared reads to retire, but does not require independent MOVM/HMMA results to retire. Per-warp read counts are checked against the shared service’s total count. Register-result readiness and memory-reuse safety are therefore different conditions.

**Quantitative timing choices.** Defaults are one shared-read service with four slots, one-cycle package spacing and one-cycle return delay; one MOVM service with four slots and delay/interval 1/1; and one HMMA service with two slots and delay/interval 16/4. These are model settings. Encoded instruction controls come from the saved compiled kernel; the queue sizes, arbitration, unit timing and producer-wait interpretation remain hypotheses. No compound MOVM recurrence cost is added again on top of decoded controls and service latency.

**Verification and limits.** The [unit receipt](numerical/native_multiwarp_stage_verification.json) checks 4,096 output words against an independent direct dot product with nonzero input C. Two tests use shared-read capacities one and two; each test performs two four-warp batches. Across the tests, 16 warp windows issue all 40 instructions in order. At least two warps issue before any finishes its instruction window, confirming modeled overlap rather than four serial copies. Synthetic shared-return/MOVM/HMMA delays of 9/19/73 cycles force readiness waits and finite-service contention. This is functional verification, not a measured GPU timing result.

`MULTIWARP_NATIVE_STAGE = 1` selects this batch in the CTA controller. It requires the native BM32/BN32/BK32 geometry. A K1536 CTA has 48 batch requests, one after each complete shared stage, rather than 192 single-fragment requests. Input staging, whole-stage replacement and output retirement remain serialized. Missing address-ALU replay, scratch service, actual barrier implementation, multiple CTAs/SMs and physical timing validation remain unchanged.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_native_multiwarp_stage.py` for the component checks. The connected controller command uses `--multiwarp`, which also enables native operand execution and coalesced input/output.

The [connected receipt](numerical/studied_gemm_cta_multiwarp_verification.json) then checks 5,120 original first-CTA outputs: two K64 replays at each backing delay of 2 and 13, and one K1536 launch. The full reduction completes 48 accepted batches with all four fragments carried between stages and waits for all 128 output-sector acknowledgments. Its 67,389-cycle execution boundary is accepted launch to observed completion under synthetic settings. Final component and connected receipts use the warning-clean source; the initial numerically correct but warning-bearing build is preserved separately. No physical evidence field is closed by these simulations.

**Inline behavior.**

```systemverilog
// Four-warp bounded BM32/BN32/BK32 native operand stage, one shared service set.
// Round-robin ONE global issue port and read>move>matrix return priority are
// simulation hypotheses, not RTX5090 scheduler topology or bandwidth facts.
// Address ALU is control-only; offsets precomputed, entry barrier assumed.
module native_multiwarp_stage_pipeline #(
 parameter int WARPS=4,parameter bit ALLOW_WARP_WRITES=0,
 parameter int READ_SLOTS=4,SERVICE_INTERVAL=1,RETURN_DELAY=1,
 parameter int MOVM_SLOTS=4,MOVM_LATENCY=1,MOVM_INTERVAL=1,
 parameter int HMMA_SLOTS=2,HMMA_LATENCY=16,HMMA_INTERVAL=4,ARITHMETIC_MODE=1
)(
 input logic clk,rst,
 input logic write_valid,output logic write_ready,
 input logic[31:0]write_byte_address,input logic[15:0]write_data,
 input logic write_warp_valid,output logic write_warp_ready,
 input logic[31:0]write_warp_byte_addresses[32],
 input logic[15:0]write_warp_halfwords[32],input logic[31:0]write_warp_mask,
 input logic req_valid,output logic req_ready,input logic[31:0]req_id,
 input logic[31:0]c_registers[WARPS][32][8],
 output logic operands_initialized,addresses_legal,
 output logic rsp_valid,input logic rsp_ready,
 output logic[31:0]rsp_id,result_registers[WARPS][32][8],output int outstanding,
 output logic[WARPS-1:0] warp_drained,warp_memory_safe,
 output logic native_issue_valid,output logic[31:0]native_issue_warp,native_issue_pc
);
 import native_studied_stage_schedule::*;
 localparam int HALFWORDS=2048;
 typedef enum logic[1:0]{IDLE,RUN,DRAIN,RESPONSE}state_t;state_t state;
 int read_live_perwarp[WARPS];
 int warp_service_live[WARPS];logic service_pending[WARPS][INSTRUCTIONS];
 int pc[WARPS],round_robin,selected,read_live_count;int read_locations[32];
 logic[31:0]saved_id;logic[15:0]memory[HALFWORDS];logic initialized[HALFWORDS];
 logic[31:0]a_words[WARPS][2][32][4],b_raw[WARPS][2][32][4],b_moved[WARPS][2][32][4],accumulator[WARPS][32][8];
 logic a_ready[WARPS][2][4],b_ready[WARPS][2][4],mov_ready[WARPS][2][4],c_ready[WARPS][2];
 descriptor_t desc[WARPS],chosen_desc,completion_desc;
 native_control_decode::control_t control[WARPS],completion_control;
 logic dependencies_ready[WARPS],gate_valid[WARPS],gate_ready[WARPS],dispatch_valid[WARPS],dispatch_ready[WARPS],issued[WARPS],gate_error[WARPS];
 logic[5:0]busy_write[WARPS],busy_read[WARPS];logic[3:0]cooldown[WARPS];
 logic read_req_valid,read_req_ready,read_rsp_valid,read_rsp_ready;
 logic[31:0]read_req_id,read_rsp_id,read_addresses[32],read_inputs[32],read_outputs[32];int read_outstanding;
 logic mov_req_valid,mov_req_ready,mov_rsp_valid,mov_rsp_ready;
 logic[31:0]mov_req_id,mov_rsp_id,mov_inputs[32],mov_outputs[32];int mov_outstanding;
 logic h_req_valid,h_req_ready,h_rsp_valid,h_rsp_ready;
 logic[31:0]h_req_id,h_rsp_id,h_a[32][4],h_b[32][2],h_c[32][4],h_results[32][4];int h_outstanding;
 logic completion_valid,write_legal,warp_write_legal,all_issued,all_drained,selected_issued;
 logic[31:0]completion_id;int completion_warp,completion_pc;
 function automatic int address(input bit operand_b,input int kk,word_index,lane,tile);
  if(operand_b)return 2048+64*(16*kk+lane/4)+32*(tile%2)+4*(lane%4)+(word_index%2)*512+(word_index/2)*16;
  return 64*(16*(tile/2)+lane/4)+32*kk+4*(lane%4)+(word_index%2)*512+(word_index/2)*16;
 endfunction
 initial if(WARPS<1||WARPS>4)$fatal(1,"Native stage supports one through four warps");
 assign write_legal=write_byte_address[0]==0&&write_byte_address<=4094;
 assign write_ready=!rst&&write_legal&&!read_req_valid;
 always_comb begin
  warp_write_legal=1;
  if(ALLOW_WARP_WRITES)for(int lane=0;lane<32;lane++)if(write_warp_mask[lane])begin
   if(write_warp_byte_addresses[lane][0]!=0||write_warp_byte_addresses[lane]>4094)warp_write_legal=0;
   for(int other=0;other<lane;other++)if(write_warp_mask[other]&&write_warp_byte_addresses[lane]==write_warp_byte_addresses[other])warp_write_legal=0;
  end
 end
 assign write_warp_ready=ALLOW_WARP_WRITES&&!rst&&warp_write_legal&&!write_valid&&!read_req_valid;
 assign addresses_legal=1;
 assign req_ready=!rst&&state==IDLE&&operands_initialized;
 assign rsp_valid=!rst&&state==RESPONSE;assign rsp_id=saved_id;
 assign outstanding=state==IDLE?0:1;
 always_comb begin
  operands_initialized=1;
  for(int warp=0;warp<WARPS;warp++)begin
   for(int kk=0;kk<2;kk++)for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)
    operands_initialized=operands_initialized&&initialized[address(0,kk,word,lane,warp)/2]&&initialized[address(0,kk,word,lane,warp)/2+1]&&initialized[address(1,kk,word,lane,warp)/2]&&initialized[address(1,kk,word,lane,warp)/2+1];
   desc[warp]='0;if(pc[warp]<INSTRUCTIONS)desc[warp]=descriptor(pc[warp]);
   control[warp]=native_control_decode::decode(desc[warp].raw);
   dependencies_ready[warp]=1;
   if(desc[warp].kind==2)dependencies_ready[warp]=b_ready[warp][desc[warp].kk][desc[warp].word_index];
   if(desc[warp].kind==3)begin
    dependencies_ready[warp]=c_ready[warp][desc[warp].upper_half];
    for(int word=0;word<4;word++)dependencies_ready[warp]=dependencies_ready[warp]&&a_ready[warp][desc[warp].kk][word];
    for(int word=0;word<2;word++)dependencies_ready[warp]=dependencies_ready[warp]&&mov_ready[warp][desc[warp].kk][2*int'(desc[warp].upper_half)+word];
   end
   gate_valid[warp]=!rst&&state==RUN&&pc[warp]<INSTRUCTIONS&&dependencies_ready[warp];
   for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)result_registers[warp][lane][word]=accumulator[warp][lane][word];
  end
 end
 always_comb begin
  all_issued=1;all_drained=1;
  for(int warp=0;warp<WARPS;warp++)begin
   if(pc[warp]!=INSTRUCTIONS)all_issued=0;
   if(pc[warp]!=INSTRUCTIONS||busy_write[warp]!=0||busy_read[warp]!=0||cooldown[warp]!=0||!c_ready[warp][0]||!c_ready[warp][1]||warp_service_live[warp]!=0)all_drained=0;
  end
 end
 always_comb begin
  selected=-1;
  for(int offset=0;offset<WARPS;offset++)begin
   int candidate;candidate=(round_robin+offset)%WARPS;
   if(selected<0&&dispatch_valid[candidate])begin
    case(desc[candidate].kind)
     // All precomputed load addresses are aligned; capacity is readiness here.
     1:if(read_live_count<READ_SLOTS)selected=candidate;
     2:if(mov_req_ready)selected=candidate;
     3:if(h_req_ready)selected=candidate;
     default:selected=candidate;
    endcase
   end
  end
  chosen_desc='0;if(selected>=0)chosen_desc=desc[selected];
 end
 always_comb begin
  for(int warp=0;warp<WARPS;warp++)begin
   dispatch_ready[warp]=0;
   if(selected==warp)begin
    case(desc[warp].kind)
     1:dispatch_ready[warp]=read_req_ready;
     2:dispatch_ready[warp]=mov_req_ready;
     3:dispatch_ready[warp]=h_req_ready;
     default:dispatch_ready[warp]=1;
    endcase
   end
  end
 end
 always_comb begin
  selected_issued=0;
  for(int warp=0;warp<WARPS;warp++)if(issued[warp])selected_issued=1;
 end
 always_comb begin
  read_req_valid=0;mov_req_valid=0;h_req_valid=0;
  read_req_id=0;mov_req_id=0;h_req_id=0;
  native_issue_valid=selected_issued;native_issue_warp=0;native_issue_pc=0;
  if(selected>=0)begin
   native_issue_warp=32'(selected);native_issue_pc=32'h1350+32'(16*pc[selected]);
   read_req_id=32'(selected*INSTRUCTIONS+pc[selected]);mov_req_id=read_req_id;h_req_id=read_req_id;
   read_req_valid=issued[selected]&&chosen_desc.kind==1;
   mov_req_valid=issued[selected]&&chosen_desc.kind==2;
   h_req_valid=issued[selected]&&chosen_desc.kind==3;
  end
 end
 always_comb begin
  for(int lane=0;lane<32;lane++)begin
   read_locations[lane]=0;
   read_addresses[lane]=0;read_inputs[lane]=0;mov_inputs[lane]=0;
   for(int word=0;word<4;word++)begin h_a[lane][word]=0;h_c[lane][word]=0;end
   for(int word=0;word<2;word++)h_b[lane][word]=0;
   if(selected>=0)begin
    read_locations[lane]=address(chosen_desc.operand_b,int'(chosen_desc.kk),int'(chosen_desc.word_index),lane,selected);
    read_addresses[lane]=32'(read_locations[lane]);read_inputs[lane]={memory[read_locations[lane]/2+1],memory[read_locations[lane]/2]};
    mov_inputs[lane]=b_raw[selected][chosen_desc.kk][lane][chosen_desc.word_index];
    for(int word=0;word<4;word++)begin h_a[lane][word]=a_words[selected][chosen_desc.kk][lane][word];h_c[lane][word]=accumulator[selected][lane][4*int'(chosen_desc.upper_half)+word];end
    for(int word=0;word<2;word++)h_b[lane][word]=b_moved[selected][chosen_desc.kk][lane][2*int'(chosen_desc.upper_half)+word];
   end
  end
 end
 always_comb begin
  read_rsp_ready=!rst&&(state==RUN||state==DRAIN);
  mov_rsp_ready=read_rsp_ready&&!read_rsp_valid;
  h_rsp_ready=mov_rsp_ready&&!mov_rsp_valid;
  completion_valid=(read_rsp_valid&&read_rsp_ready)||(mov_rsp_valid&&mov_rsp_ready)||(h_rsp_valid&&h_rsp_ready);
  completion_id=read_rsp_valid?read_rsp_id:(mov_rsp_valid?mov_rsp_id:h_rsp_id);
  completion_warp=int'(completion_id)/INSTRUCTIONS;completion_pc=int'(completion_id)%INSTRUCTIONS;
  completion_desc='0;if(completion_valid&&completion_id<WARPS*INSTRUCTIONS)completion_desc=descriptor(completion_pc);
  completion_control=native_control_decode::decode(completion_desc.raw);
 end
 always_ff @(posedge clk)begin
  if(rst)begin
   warp_drained<='0;warp_memory_safe<='0;
   state<=IDLE;saved_id<=0;round_robin<=0;read_live_count<=0;
   for(int i=0;i<HALFWORDS;i++)initialized[i]<=0;
   for(int warp=0;warp<WARPS;warp++)begin
    read_live_perwarp[warp]<=0;warp_service_live[warp]<=0;for(int op=0;op<INSTRUCTIONS;op++)service_pending[warp][op]<=0;
    pc[warp]<=0;for(int kk=0;kk<2;kk++)for(int word=0;word<4;word++)begin a_ready[warp][kk][word]<=0;b_ready[warp][kk][word]<=0;mov_ready[warp][kk][word]<=0;end
    for(int half=0;half<2;half++)c_ready[warp][half]<=0;
    for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)accumulator[warp][lane][word]<=0;
   end
  end else begin
   // Memory reuse safety is separate from register-only service drain.
   // This bounded-window signal does not replay the following native BAR PCs.
   begin
    integer total_reads;total_reads=0;
    for(int warp=0;warp<WARPS;warp++)begin
     bit accepted_read,retired_read;integer delta;
     accepted_read=read_req_valid&&read_req_ready&&int'(read_req_id)/INSTRUCTIONS==warp;
     retired_read=read_rsp_valid&&read_rsp_ready&&int'(read_rsp_id)/INSTRUCTIONS==warp;
     delta=int'(accepted_read)-int'(retired_read);
     total_reads+=read_live_perwarp[warp];
     if(read_live_perwarp[warp]<0||read_live_perwarp[warp]>READ_SLOTS)$fatal(1,"Per-warp shared-read liveness out of bounds");
     if(retired_read&&read_live_perwarp[warp]==0)$fatal(1,"Shared-read completion lacks warp credit");
     read_live_perwarp[warp]<=read_live_perwarp[warp]+delta;
     if((state==RUN||state==DRAIN)&&pc[warp]==INSTRUCTIONS&&cooldown[warp]==0&&read_live_perwarp[warp]==0)
      warp_memory_safe[warp]<=1;
     if(warp_memory_safe[warp]&&(state==RUN||state==DRAIN||state==RESPONSE)&&read_live_perwarp[warp]!=0)$fatal(1,"Memory-safe warp retains pending shared read");
    end
    if(total_reads!=read_outstanding)$fatal(1,"Per-warp shared-read conservation failed");
   end
   // Per-warp liveness follows accepted service operations and actual retired
   // responses. Decoded barrier bits alone do not cover every pending operation.
   begin
    integer total_live;total_live=0;
    for(int warp=0;warp<WARPS;warp++)begin
     integer delta;bit accepted,retired;delta=0;
     accepted=(read_req_valid&&read_req_ready&&int'(read_req_id)/INSTRUCTIONS==warp)||
              (mov_req_valid&&mov_req_ready&&int'(mov_req_id)/INSTRUCTIONS==warp)||
              (h_req_valid&&h_req_ready&&int'(h_req_id)/INSTRUCTIONS==warp);
     retired=completion_valid&&completion_warp==warp;
     total_live+=warp_service_live[warp];
     if(warp_service_live[warp]<0||warp_service_live[warp]>READ_SLOTS+MOVM_SLOTS+HMMA_SLOTS)$fatal(1,"Warp service liveness out of bounds");
     if(accepted)begin
      if(pc[warp]>=INSTRUCTIONS||service_pending[warp][pc[warp]])$fatal(1,"Duplicate/out-of-range warp service acceptance");
      service_pending[warp][pc[warp]]<=1;delta++;
     end
     if(retired)begin
      if(!service_pending[warp][completion_pc]||warp_service_live[warp]==0)$fatal(1,"Warp completion without accepted operation");
      service_pending[warp][completion_pc]<=0;delta--;
     end
     warp_service_live[warp]<=warp_service_live[warp]+delta;
     if((state==RUN||state==DRAIN)&&pc[warp]==INSTRUCTIONS&&busy_read[warp]==0&&busy_write[warp]==0&&cooldown[warp]==0&&c_ready[warp][0]&&c_ready[warp][1]&&warp_service_live[warp]==0)
      warp_drained[warp]<=1;
     if(warp_drained[warp]&&(state==RUN||state==DRAIN||state==RESPONSE)&&warp_service_live[warp]!=0)$fatal(1,"Drained warp retains pending service");
     if(state==RESPONSE&&warp_service_live[warp]!=0)$fatal(1,"Batch response retains warp service");
    end
    if(total_live!=read_outstanding+mov_outstanding+h_outstanding)$fatal(1,"Per-warp/global service conservation failed");
   end
   // Local admission credits are exact transfer counts, not capacity estimates.
   if(read_live_count!=read_outstanding)$fatal(1,"Shared read credit conservation failed");
   if(read_req_valid&&!read_req_ready)$fatal(1,"Granted read lacks actual service readiness");
   case({read_req_valid&&read_req_ready,read_rsp_valid&&read_rsp_ready})
    2'b10:read_live_count<=read_live_count+1;
    2'b01:read_live_count<=read_live_count-1;
    default:read_live_count<=read_live_count;
   endcase
   if(write_valid&&!write_legal)$fatal(1,"Invalid multiwarp shared write");
   if(ALLOW_WARP_WRITES&&write_warp_valid&&!warp_write_legal)$fatal(1,"Invalid multiwarp vector write");
   for(int warp=0;warp<WARPS;warp++)if(gate_error[warp])$fatal(1,"Multiwarp barrier error");
   if(write_valid&&write_ready)begin memory[write_byte_address/2]<=write_data;initialized[write_byte_address/2]<=1;end
   if(ALLOW_WARP_WRITES&&write_warp_valid&&write_warp_ready)for(int lane=0;lane<32;lane++)if(write_warp_mask[lane])begin memory[write_warp_byte_addresses[lane]/2]<=write_warp_halfwords[lane];initialized[write_warp_byte_addresses[lane]/2]<=1;end
   if(completion_valid&&completion_id>=WARPS*INSTRUCTIONS)$fatal(1,"Unknown multiwarp completion ID");
   if(read_rsp_valid&&read_rsp_ready)begin
    if(completion_desc.kind!=1)$fatal(1,"Wrong multiwarp read completion class");
    for(int lane=0;lane<32;lane++)begin
     if(completion_desc.operand_b)b_raw[completion_warp][completion_desc.kk][lane][completion_desc.word_index]<=read_outputs[lane];
     else a_words[completion_warp][completion_desc.kk][lane][completion_desc.word_index]<=read_outputs[lane];
    end
    if(completion_desc.operand_b)b_ready[completion_warp][completion_desc.kk][completion_desc.word_index]<=1;
    else a_ready[completion_warp][completion_desc.kk][completion_desc.word_index]<=1;
   end
   if(mov_rsp_valid&&mov_rsp_ready)begin
    if(completion_desc.kind!=2)$fatal(1,"Wrong multiwarp MOVM completion class");
    for(int lane=0;lane<32;lane++)b_moved[completion_warp][completion_desc.kk][lane][completion_desc.word_index]<=mov_outputs[lane];
    mov_ready[completion_warp][completion_desc.kk][completion_desc.word_index]<=1;
   end
   if(h_rsp_valid&&h_rsp_ready)begin
    if(completion_desc.kind!=3)$fatal(1,"Wrong multiwarp HMMA completion class");
    for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)accumulator[completion_warp][lane][4*int'(completion_desc.upper_half)+word]<=h_results[lane][word];
    c_ready[completion_warp][completion_desc.upper_half]<=1;
   end
   case(state)
    IDLE:if(req_valid&&req_ready)begin
     warp_drained<='0;warp_memory_safe<='0;
     state<=RUN;saved_id<=req_id;round_robin<=0;
     for(int warp=0;warp<WARPS;warp++)begin
      read_live_perwarp[warp]<=0;warp_service_live[warp]<=0;for(int op=0;op<INSTRUCTIONS;op++)service_pending[warp][op]<=0;
      pc[warp]<=0;for(int kk=0;kk<2;kk++)for(int word=0;word<4;word++)begin a_ready[warp][kk][word]<=0;b_ready[warp][kk][word]<=0;mov_ready[warp][kk][word]<=0;end
      for(int half=0;half<2;half++)c_ready[warp][half]<=1;
      for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)accumulator[warp][lane][word]<=c_registers[warp][lane][word];
     end
    end
    RUN:begin
     for(int warp=0;warp<WARPS;warp++)if(issued[warp])begin pc[warp]<=pc[warp]+1;if(desc[warp].kind==3)c_ready[warp][desc[warp].upper_half]<=0;round_robin<=(warp+1)%WARPS;end
     if(all_issued)state<=DRAIN;
    end
    DRAIN:if(all_drained&&read_outstanding==0&&mov_outstanding==0&&h_outstanding==0)state<=RESPONSE;
    RESPONSE:if(rsp_valid&&rsp_ready)state<=IDLE;
    default:$fatal(1,"Invalid multiwarp state");
   endcase
  end
 end
 for(genvar warp=0;warp<WARPS;warp++)begin:warps
  decoded_native_issue_gate #(.MAX_OPS(64),.TAG_W(7),.COUNT_W(7)) gate(
   .clk,.reset(rst||state==IDLE),.instr_valid(gate_valid[warp]),.instr_ready(gate_ready[warp]),
   .operation_id(7'(pc[warp])),.control(control[warp]),.dispatch_valid(dispatch_valid[warp]),.dispatch_ready(dispatch_ready[warp]),.issued(issued[warp]),
   .write_complete_valid(completion_valid&&completion_warp==warp&&completion_control.write_barrier!=7),.write_complete_tag(7'(completion_pc)),
   .read_complete_valid(1'b0),.read_complete_tag(7'd0),.busy_write_mask(busy_write[warp]),.busy_read_mask(busy_read[warp]),.cooldown(cooldown[warp]),.error_sticky(gate_error[warp])
  );
 end
 warp_shared_read_service #(.SLOTS(READ_SLOTS),.SERVICE_INTERVAL(SERVICE_INTERVAL),.RETURN_DELAY(RETURN_DELAY)) reads(
  .clk,.rst,.req_valid(read_req_valid),.req_ready(read_req_ready),.req_id(read_req_id),.byte_addresses(read_addresses),.input_words(read_inputs),
  .rsp_valid(read_rsp_valid),.rsp_ready(read_rsp_ready),.rsp_id(read_rsp_id),.output_words(read_outputs),.outstanding(read_outstanding),.request_packages()
 );
 native_movm_word_pipeline #(.SLOTS(MOVM_SLOTS),.LATENCY(MOVM_LATENCY),.INTERVAL(MOVM_INTERVAL)) moves(
  .clk,.rst,.req_valid(mov_req_valid),.req_ready(mov_req_ready),.req_id(mov_req_id),.input_words(mov_inputs),
  .rsp_valid(mov_rsp_valid),.rsp_ready(mov_rsp_ready),.rsp_id(mov_rsp_id),.output_words(mov_outputs),.outstanding(mov_outstanding)
 );
 native_hmma16816_adapter #(.SLOTS(HMMA_SLOTS),.LATENCY(HMMA_LATENCY),.INTERVAL(HMMA_INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) tensor(
  .clk,.rst,.req_valid(h_req_valid),.req_ready(h_req_ready),.req_id(h_req_id),.a_registers(h_a),.b_registers(h_b),.c_registers(h_c),
  .rsp_valid(h_rsp_valid),.rsp_ready(h_rsp_ready),.rsp_id(h_rsp_id),.result_registers(h_results),.outstanding(h_outstanding)
 );
 // Shared values sampled on accepted LD.E issue. No full native register file,
 // address-ALU scoreboard, original missing scratch/barrier protocol or full SM.
endmodule
```

### 4.41. Original output values through committed shared scratch and reads

**Question and role.** Does global output come from the values that were actually stored in shared scratch and returned by its read service? The [output-scratch component](numerical/studied_output_scratch_pipeline.sv) restores that data path. It accepts the four fragments’ native accumulator words, commits them into row-major scratch, then obtains the 32-lane groups used by global stores through actual shared-read responses. Global store payloads no longer bypass those intermediate values in the enabled mode.

The saved original epilogue has four `STS.64` groups per warp at instruction addresses 0x17c0, 0x1810, 0x1850 and 0x1880. They carry accumulator pairs 0/1, 2/3, 4/5 and 6/7 respectively. The model preserves those groups and the measured C element mapping. It does not replay their encoded issue controls or infer a physical 64-bit store latency. All four warps finish all stores before any scratch read begins: a deliberate whole-phase visibility fence, stronger than the original per-warp synchronization.

| Interface or state | Quantitative content | Contract |
|---|---|---|
| Request | 32-bit ID; C registers `[4][32][8]`, 32 bits each; valid/ready | One batch accepted while idle; all C values captured on acceptance |
| Response | Retained ID; `row_major_words[4][256]`, 32 bits each; valid/ready | Visible after all actual scratch reads complete; stable until accepted |
| Scratch storage | 1,024 FP32 words, 4,096 bytes; one initialization bit per word | Every returned coordinate must have been committed in this batch |
| Pending store group | 64 word addresses/data entries and pending bits | One group contains two FP32 words from each of 32 lanes |
| Read service | One separate scalar shared-read instance; four slots by default | Each accepted read captures actual scratch values and returns 32 words |
| Diagnostics | Store-group count, committed-word count, read-request count, read-completion count | A completed batch has 16, 1,024, 32 and 32 respectively |
| Reset | Synchronous reset of state, scratch and read child | Cancels partial work; no old response is produced |

**State, bank work and ordering.** IDLE captures C and clears initialization. STORE_PREP constructs one native-shaped pair group using the measured accumulator-to-element mapping. STORE_SERVICE selects at most one pending word per modeled bank and commits the selected words. A bank is the scratch word index modulo 32. STORE_RETURN applies the configured completion delay, then advances to the next pair or warp. Only after all 16 groups and all 1,024 words are committed can READ_SEND begin.

For this mapping, each 64-word pair group uses 16 banks with four distinct words per bank. The one-word-per-bank rule therefore needs four store packages per group, or 64 packages for all 16 groups. For example, scratch word indices 0, 32, 64 and 96 all select bank zero and must be committed in separate packages under that rule. This is a quantitative consequence of the model’s assumed write service, not an independently measured RTX `STS.64` work or timing rule.

There are eight row-major read groups per warp. Group iteration `j` requests element `lane + 32 × j`; each of the 32 lanes reads one actual initialized word. READ_WAIT uses the ID-matched read response to fill the corresponding row-major result entries. It advances only after completion, so reads are serial even though the child service has configurable capacity. RESPONSE holds all four fragments until acknowledged. Mutating input C after acceptance cannot change the captured batch.

**Timing and resource boundary.** Default store package interval and return delay are both one cycle. Read capacity is four, with interval/return delay 1/1. All are development settings. The separate output and operand arrays total 8,192 logical bytes in the model; they do not reproduce the kernel’s original shared allocation, reserved prefix, phase reuse or occupancy. The scratch read service is a different instance from the operand read service. The controller runs the entire output phase only after all operand work has drained, so the implementation makes no claim that two independent shared services operate concurrently on an SM. Actual WARPSYNC arrival semantics and shared-store/read overlap remain absent.

**Verification.** The [component receipt](numerical/studied_output_scratch_verification.json) compares 4,096 returned words against coordinate-specific FP32 identities. Two settings use synthetic store/read delays 7/11 and 19/23 with read capacities one and two. It checks captured input values, all-word visibility before the first read, exact 16/1,024/32/32 counts, held responses, reset during partial stores and replay. The [connected receipt](numerical/studied_gemm_cta_output_scratch_verification.json) adds 5,120 original first-CTA output comparisons, including K1536, after those actual scratch returns feed masked global stores. Every launch waits for all 128 global packet acknowledgments. These receipts retain their tested component/controller versions; the later dynamically addressed controller is covered by section 4.43’s current grid and CTA regression receipts. No physical parameter is newly identified, and no hardware runtime accuracy is established.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_studied_output_scratch.py` for the component. Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_studied_gemm_cta.py --output-scratch` for the connected original CTA; that option enables the required four-warp/coalesced modes.

**Inline behavior.**

```systemverilog
// Original BM32 output scratch: four STS64 groups per warp, then eight LDS
// warp reads per warp. Native C layout is measured; serial service and bank
// write interval/return delays are simulation choices, not identified timing.
// Collective visibility fence substitutes for native WARPSYNC arrival rules.
module studied_output_scratch_pipeline #(
 parameter int STORE_INTERVAL=1,STORE_RETURN_DELAY=1,
 parameter int READ_SLOTS=4,READ_INTERVAL=1,READ_RETURN_DELAY=1
)(
 input logic clk,rst,req_valid,output logic req_ready,input logic[31:0]req_id,
 input logic[31:0]c_registers[4][32][8],
 output logic rsp_valid,input logic rsp_ready,output logic[31:0]rsp_id,
 output logic[31:0]row_major_words[4][256],output int outstanding,
 output int store_requests,store_commit_words,read_requests,read_completions
);
 typedef enum logic[2:0]{IDLE,STORE_PREP,STORE_SERVICE,STORE_RETURN,
  READ_SEND,READ_WAIT,RESPONSE}state_t;
 state_t state;
 logic[31:0]saved_id,saved_c[4][32][8],scratch[1024];logic initialized[1024];
 int store_warp,store_group,remaining_words,pacing,return_delay,read_ordinal;
 logic pending_entry[64];int entry_address[64];logic[31:0]entry_data[64];
 int selected_entry[32],selected_words;
 logic read_req_valid,read_req_ready,read_rsp_valid,read_rsp_ready;
 logic[31:0]read_req_id,read_rsp_id,read_addresses[32],read_inputs[32],read_outputs[32];int read_outstanding;
 initial if(STORE_INTERVAL<1||STORE_RETURN_DELAY<1||READ_SLOTS<1||READ_INTERVAL<1||READ_RETURN_DELAY<1)
  $fatal(1,"Invalid output scratch timing configuration");
 assign req_ready=!rst&&state==IDLE;
 assign rsp_valid=!rst&&state==RESPONSE;assign rsp_id=saved_id;
 assign outstanding=state==IDLE?0:1;
 always_comb begin
  selected_words=0;
  for(int bank=0;bank<32;bank++)begin
   selected_entry[bank]=-1;
   for(int entry=0;entry<64;entry++)if(pending_entry[entry]&&entry_address[entry]%32==bank&&selected_entry[bank]<0)selected_entry[bank]=entry;
   if(selected_entry[bank]>=0)selected_words++;
  end
 end
 assign read_req_valid=!rst&&state==READ_SEND;
 assign read_rsp_ready=!rst&&state==READ_WAIT;
 assign read_req_id=32'(read_ordinal);
 always_comb begin
  for(int lane=0;lane<32;lane++)begin
   read_addresses[lane]=32'(1024*(read_ordinal/8)+4*(lane+32*(read_ordinal%8)));
   read_inputs[lane]=scratch[256*(read_ordinal/8)+lane+32*(read_ordinal%8)];
  end
 end
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;saved_id<=0;store_warp<=0;store_group<=0;remaining_words<=0;pacing<=0;return_delay<=0;read_ordinal<=0;
   store_requests<=0;store_commit_words<=0;read_requests<=0;read_completions<=0;
   for(int i=0;i<1024;i++)begin scratch[i]<=0;initialized[i]<=0;end
   for(int entry=0;entry<64;entry++)begin pending_entry[entry]<=0;entry_address[entry]<=0;entry_data[entry]<=0;end
   for(int warp=0;warp<4;warp++)begin
    for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)saved_c[warp][lane][word]<=0;
    for(int word=0;word<256;word++)row_major_words[warp][word]<=0;
   end
  end else case(state)
   IDLE:if(req_valid&&req_ready)begin
    saved_id<=req_id;store_warp<=0;store_group<=0;read_ordinal<=0;state<=STORE_PREP;
    store_requests<=0;store_commit_words<=0;read_requests<=0;read_completions<=0;
    for(int i=0;i<1024;i++)initialized[i]<=0;
    for(int warp=0;warp<4;warp++)begin
     for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)saved_c[warp][lane][word]<=c_registers[warp][lane][word];
     for(int word=0;word<256;word++)row_major_words[warp][word]<=0;
    end
   end
   STORE_PREP:begin
    // Pairs0/1,2/3,4/5,6/7 have native byte offsets0,512,32,544.
    for(int lane=0;lane<32;lane++)for(int half=0;half<2;half++)begin
     pending_entry[2*lane+half]<=1;
     entry_address[2*lane+half]<=256*store_warp+native_bf16_layout::c_element_index(lane,2*store_group+half);
     entry_data[2*lane+half]<=saved_c[store_warp][lane][2*store_group+half];
    end
    remaining_words<=64;pacing<=0;store_requests<=store_requests+1;state<=STORE_SERVICE;
   end
   STORE_SERVICE:begin
    if(pacing>0)pacing<=pacing-1;
    else begin
     if(selected_words<1||selected_words>remaining_words)$fatal(1,"Invalid output scratch bank work");
     for(int bank=0;bank<32;bank++)if(selected_entry[bank]>=0)begin
      scratch[entry_address[selected_entry[bank]]]<=entry_data[selected_entry[bank]];
      initialized[entry_address[selected_entry[bank]]]<=1;pending_entry[selected_entry[bank]]<=0;
     end
     store_commit_words<=store_commit_words+selected_words;
     remaining_words<=remaining_words-selected_words;pacing<=STORE_INTERVAL-1;
     if(remaining_words==selected_words)begin return_delay<=STORE_RETURN_DELAY-1;state<=STORE_RETURN;end
    end
   end
   STORE_RETURN:begin
    if(return_delay>0)return_delay<=return_delay-1;
    else if(store_group<3)begin store_group<=store_group+1;state<=STORE_PREP;end
    else if(store_warp<3)begin store_warp<=store_warp+1;store_group<=0;state<=STORE_PREP;end
    else begin
     if(store_commit_words!=1024||store_requests!=16)$fatal(1,"Scratch visibility fence reached before all stores");
     read_ordinal<=0;state<=READ_SEND;
    end
   end
   READ_SEND:if(read_req_valid&&read_req_ready)begin
    for(int lane=0;lane<32;lane++)if(!initialized[256*(read_ordinal/8)+lane+32*(read_ordinal%8)])$fatal(1,"Scratch load precedes write visibility");
    read_requests<=read_requests+1;state<=READ_WAIT;
   end
   READ_WAIT:if(read_rsp_valid&&read_rsp_ready)begin
    if(read_rsp_id!=read_req_id)$fatal(1,"Scratch read completion identity mismatch");
    for(int lane=0;lane<32;lane++)row_major_words[read_ordinal/8][lane+32*(read_ordinal%8)]<=read_outputs[lane];
    read_completions<=read_completions+1;
    if(read_ordinal==31)state<=RESPONSE;
    else begin read_ordinal<=read_ordinal+1;state<=READ_SEND;end
   end
   RESPONSE:if(rsp_valid&&rsp_ready)state<=IDLE;
   default:$fatal(1,"Invalid output scratch state");
  endcase
 end
 warp_shared_read_service #(.SLOTS(READ_SLOTS),.SERVICE_INTERVAL(READ_INTERVAL),.RETURN_DELAY(READ_RETURN_DELAY)) reads(
  .clk,.rst,.req_valid(read_req_valid),.req_ready(read_req_ready),.req_id(read_req_id),
  .byte_addresses(read_addresses),.input_words(read_inputs),.rsp_valid(read_rsp_valid),.rsp_ready(read_rsp_ready),
  .rsp_id(read_rsp_id),.output_words(read_outputs),.outstanding(read_outstanding),.request_packages()
 );
 // Actual shared words feed response reads; no C-to-output bypass. Each batch
 // drains all writes then all32 reads. Reset discards pending service events.
endmodule
```

### 4.42. Explicit producer and consumer barrier generations

**Question and role.** What prevents a fragment warp from reading an incompletely staged operand frame, or the next stage from overwriting values still in use? The [generation barrier](components/cta_generation_barrier.sv) makes those obligations explicit. An owner first arms one generation with an expected participant mask, then submits arrivals for those participants. A registered release becomes available only after the entire expected mask has arrived, and remains held until acknowledged. The CTA controller uses two generations per reduction stage: producer visibility before computation and consumer memory-use completion before stage replacement.

A generation is a 32-bit sequence number identifying one barrier use. The default participant count is four modeled warps. Arrival granularity is therefore a warp, not 128 independently modeled threads. The component is an executable synchronization hypothesis; its masks, capacity and release delay do not identify private NVIDIA barrier hardware.

| Interface | Signals and widths | Contract |
|---|---|---|
| Arm | Valid/ready; 32-bit generation; `WARPS`-bit expected mask | Accepted only while idle; generation must be the next sequence number and mask nonempty |
| Arrival | Valid/ready; 32-bit generation; `WARPS`-bit arrival mask | An event for an already armed generation; nonempty expected subset, with no previously arrived bit |
| Release | Valid/ready; retained 32-bit generation and expected mask | Available after all participants arrive and the configured registered delay; stable until acknowledged |
| Diagnostics | Arrived mask and active flag | Show which participants have arrived and whether collection/delay/release is active |
| Clock/reset | `clk`, `rst` | Rising-edge transitions; reset cancels active work and restarts sequence at zero |

**State and timing.** IDLE accepts one arm transaction. COLLECT records distinct participant bits until the accumulated mask equals the expected mask. DELAY applies `RELEASE_DELAY`, whose default is one cycle, then RELEASE holds the generation and mask. Only actual release acknowledgment increments the next-generation counter and clears the state. A new arm cannot be accepted on that same edge; it is eligible in the following cycle. Generation wrap is unsupported.

For a final arrival accepted at edge `a`, release becomes visible after edge `a + RELEASE_DELAY`. With a continuously ready consumer, acknowledgment occurs at edge `a + RELEASE_DELAY + 1`. These are model timing rules. A held arm may be backpressured while active. Arrivals are events for an existing arm, not speculative requests held before one: simultaneous idle arm and arrival, stale generation, duplicate/unexpected participants and arrivals after collection closes are rejected.

**Connection to actual producer and consumer progress.** For zero-based reduction stage `s`, producer generation is `2 × s` and consumer generation is `2 × s + 1`. The controller arms the producer before loading. A producer warp arrives on its final actual vector shared-write commit: the final four 32-halfword groups, numbered 60–63 in the 2,048-halfword stage, belong to warps zero through three. Computation cannot start before producer release is acknowledged.

The consumer generation is armed before the four-warp batch starts. An arrival mask includes only newly registered `warp_memory_safe` participants, as defined in section 4.40. The controller remembers sent bits so a persistent memory-safe indication cannot produce duplicate arrivals. The controller separately waits for and captures the batch’s actual C results, then acknowledges consumer release before overwriting shared input or entering the output phase. At K1536, 48 stages require 192 producer warp arrivals, 192 consumer warp arrivals and 96 releases, with generations zero through 95.

**Memory visibility versus register results.** NVIDIA’s [PTX barrier definition](https://docs.nvidia.com/cuda/parallel-thread-execution/index.html#parallel-synchronization-and-communication-instructions-bar) orders participating memory accesses. A performed read has supplied a value that another participant can no longer change; a performed write is visible to other participants. It does not specify a universal flush of independent matrix register results. [Literature receipt 44](discovery_rounds/literature_sweep_044.json) records that distinction.

Consumer arrival therefore uses shared-read completion rather than the all-service `warp_drained` flag. The model still uses a conservative proxy for native arrival: the entire bounded 40-instruction window and cooldown must finish, and shared reads must reach actual response retirement. Original instructions between this window and BAR at address 0x15f0, including LDC/UIADD3, are not replayed. The controller also waits for the full batch result before acknowledging consumer release, independently of memory safety. This change separates the obligations; it does not establish a faster hardware barrier or remove the conservative whole-stage schedule.

The release delay, one-active-generation capacity and warp-granularity participation remain model choices. These stage barriers also do not replace the output scratch component’s stronger whole-phase fence or recover its WARPSYNC semantics.

**Verification.** The [barrier component receipt](components/cta_generation_barrier_verification.json) has 20 positive checks under release delays one and five, plus nine rejected protocol cases. It checks partial arrivals, mask matching, held release, generation sequencing, busy-arm backpressure and reset during collection, delay and release. The refreshed [multiwarp receipt](numerical/native_multiwarp_stage_verification.json) checks 4,096 numerical words with service ownership and drain tracking. The [connected receipt](numerical/studied_gemm_cta_barriers_verification.json) checks 5,120 first-CTA outputs, including K1536, and exact 192/192/96 full-reduction counts. The 5,120-word connected receipt retains its pre-dynamic-coordinate controller version. The current [quick CTA regression](numerical/studied_gemm_cta_barriers_quick_verification.json) checks 4,096 words, and the current [complete-grid receipt](numerical/studied_gemm_grid_verification.json) checks 24,576 words including K1536 with the dynamically addressed controller. Physical evidence remains eight identified fields, 32 partial and 94 unknown; no barrier latency or other field is newly closed.

Run `python studies/rtx5090_gemm_milp/rtl/components/verify_cta_generation_barrier.py` for the component. Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_studied_gemm_cta.py --cta-barriers` for the connected first CTA.

**Inline behavior.**

```systemverilog
// Warp-granularity CTA barrier hypothesis: explicit arm, arrivals and release.
// WARPS and registered release delay do not identify private GPU barrier state.
// One generation at a time. Completed release increments the next generation.
module cta_generation_barrier #(parameter int WARPS=4,RELEASE_DELAY=1)(
 input logic clk,rst,
 input logic arm_valid,output logic arm_ready,input logic[31:0]arm_generation,
 input logic[WARPS-1:0]expected_mask,
 input logic arrival_valid,output logic arrival_ready,input logic[31:0]arrival_generation,
 input logic[WARPS-1:0]arrival_mask,
 output logic release_valid,input logic release_ready,output logic[31:0]generation,
 output logic[WARPS-1:0]release_mask,arrived_mask,output logic active
);
 typedef enum logic[1:0]{IDLE,COLLECT,DELAY,RELEASE}state_t;
 state_t state;logic[WARPS-1:0]saved_expected;logic[31:0]next_generation;
 int delay_left;logic arrival_legal;
 initial if(WARPS<1||RELEASE_DELAY<1)$fatal(1,"Invalid CTA generation barrier parameters");
 assign arm_ready=!rst&&state==IDLE;
 assign active=!rst&&state!=IDLE;
 assign arrival_legal=arrival_generation==generation&&arrival_mask!='0&&
  (arrival_mask&~saved_expected)=='0&&(arrival_mask&arrived_mask)=='0;
 assign arrival_ready=!rst&&state==COLLECT&&arrival_legal;
 assign release_valid=!rst&&state==RELEASE;assign release_mask=saved_expected;
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;generation<=0;next_generation<=0;saved_expected<='0;arrived_mask<='0;delay_left<=0;
  end else begin
   // Arrival is an event for an already armed generation, never a speculative
   // operation held before arm. Same-edge arm/arrival is therefore invalid.
   if(arrival_valid)begin
    if(state==IDLE)$fatal(1,"CTA arrival before generation arm");
    else if(arrival_generation!=generation)$fatal(1,"CTA arrival generation mismatch");
    else if(arrival_mask=='0)$fatal(1,"Empty CTA arrival mask");
    else if((arrival_mask&~saved_expected)!='0)$fatal(1,"Unexpected CTA arrival warp");
    else if((arrival_mask&arrived_mask)!='0)$fatal(1,"Duplicate CTA generation arrival");
    else if(state!=COLLECT)$fatal(1,"CTA arrival after collection closed");
   end
   case(state)
    IDLE:if(arm_valid&&arm_ready)begin
     if(arm_generation!=next_generation)$fatal(1,"CTA arm generation out of sequence");
     if(expected_mask=='0)$fatal(1,"Empty CTA expected mask");
     generation<=arm_generation;saved_expected<=expected_mask;arrived_mask<='0;state<=COLLECT;
    end
    COLLECT:if(arrival_valid&&arrival_ready)begin
     arrived_mask<=arrived_mask|arrival_mask;
     if((arrived_mask|arrival_mask)==saved_expected)begin delay_left<=RELEASE_DELAY-1;state<=DELAY;end
    end
    DELAY:if(delay_left>0)delay_left<=delay_left-1;else state<=RELEASE;
    RELEASE:if(release_valid&&release_ready)begin
     if(next_generation==32'hffffffff)$fatal(1,"CTA generation counter overflow unsupported");
     next_generation<=next_generation+1;arrived_mask<='0;saved_expected<='0;state<=IDLE;
    end
    default:$fatal(1,"Invalid CTA generation state");
   endcase
  end
 end
 // A held arm is backpressured during active/release. Release acknowledgement
 // cannot also accept a new arm; the next arm is eligible the following cycle.
 // Reset cancels active arrivals/release and resets the sequence to generation0.
endmodule
```

### 4.43. Complete tested grids through one reusable CTA context

**Question and role.** Can the connected CTA produce every coordinate of a complete matrix, rather than only the first block? The [grid controller](numerical/studied_gemm_grid_controller.sv) drives dynamic block coordinates through one reusable CTA instance. Block columns advance first, followed by block rows. The child runs the four-warp native operand window, coalesced input/output, output scratch and stage barriers. Only one block is active at a time. This tests global addressing and context reuse; it is not an SM scheduler or a parallel full-chip model.

**Geometry and quantitative defaults.** `M`, `N` and `K` are output rows, output columns and reduction length; defaults are 64, 96 and 64. The supported block shape is `BM = BN = BK = 32`. Whole-grid dimensions must be positive full multiples of the block dimensions; partial edge blocks are unsupported. A 64 × 96 grid has two block rows and three block columns, giving six CTAs and 6,144 FP32 output words. A 96 × 64 grid has three block rows and two block columns and the same output count. The original 2,048 × 2,112 full grid has not been validated by these receipts.

| Interface | Payload | Contract |
|---|---|---|
| Grid launch | 32-bit ID and A/B/C byte bases; valid/ready | Accepted only while idle; all bases and ID are captured |
| Grid completion | Retained grid ID; valid/ready | Held after all blocks and all output-store acknowledgments finish |
| Backing input | 32-bit ID/address, 256-bit returned sector, request/response ready-valid | Forwarded to the current CTA’s completion-driven cache |
| Masked output | 32-bit ID/address, 256-bit packet, eight-bit word mask; matching acknowledgment | Forwarded to the current CTA; only selected words are updated |
| Scalar output compatibility | Scalar request/response ports retained | Inactive because this wrapper always selects coalesced output |
| Block diagnostics | Dispatched/completed counts and accepted launch/completion coordinate events | Each event identifies the current block; counters must conserve one active context |
| Clock/reset | `clk`, `rst` | Reset cancels the grid and child work; providers discard old transactions |

**State and context reuse.** IDLE captures the grid request and starts at block (0, 0). LAUNCH_BLOCK offers the current coordinates and ordinal ID to the child until accepted. WAIT_BLOCK accepts only that ordinal’s completion, which already requires all global output acknowledgments. The controller then increments the column; after the last column it resets the column and increments the row. DONE exposes the original grid ID. If a grid request is accepted at edge `L`, the child can accept its first CTA no earlier than `L + 1`. If a child completion is accepted at edge `D`, the next CTA can be accepted no earlier than `D + 1`; for the final CTA, grid completion is registered after `D` and remains valid until the grid acknowledgment. A block ordinal is a sequence index inside the grid, independent of the external grid ID.

For the 64 × 96 case, the launch order is (0, 0), (0, 1), (0, 2), (1, 0), (1, 1), (1, 2). One accepted block increments the dispatch counter, and its completed response increments the completion counter. A new block cannot be dispatched before the previous one completes. Captured coordinates determine all A/B/C addresses in the child, so a later coordinate change cannot redirect an already accepted CTA.

The child cache persists across blocks and ordinary grid replays. A/B backing contents must therefore remain unchanged unless reset precedes reuse; this wrapper exposes no invalidation operation. Reset cancels pending work and resets sequence IDs, so external providers must flush old returns/acknowledgments. Reset does not roll back global stores already committed by a provider. One reused context means modeled operand/scratch storage is not multiplied by the number of grid blocks.

**Independent complete-grid verification.** The [full receipt](numerical/studied_gemm_grid_verification.json) compares every output against an independent full integer dot product using the original A17/B13 dyadic formula with each tested grid’s global strides. It checks every distinct output coordinate, masks, delayed backing returns/stores, held packets/completion, cache-preserving replay and reset cancellation of the first pending backing read. Launch snapshot stability is established by source inspection; the fixture does not mutate the accepted launch fields to test that contract. Four accepted grid launches each dispatch and complete six CTAs and acknowledge 768 output sector packets.

| Tested matrix shape M × N × K | Grid launches | Exact output-word comparisons and acknowledgments | Backing requests over the fixture |
|---|---:|---:|---:|
| 64 × 96 × 64 | 2 | 12,288 | 640 |
| 64 × 96 × 1,536 | 1 | 6,144 | 36,864 |
| 96 × 64 × 64 | 1 | 6,144 | 640 |
| Total | 4 | 24,576 | 38,144 |

The K64 two-launch fixture makes only 640 backing requests in total, matching its 20,480 input bytes divided into 32-byte sectors. This is cache reuse under the declared model geometry, not measured RTX cache behavior. Accepted-launch-to-observed-completion cycles are 31,663 and 29,096 for its two launches, 824,467 for the 64 × 96 × K1536 launch, and 35,503 for the 96 × 64 × K64 launch. Provider delays differ between fixtures, so these values are not controlled hardware-performance comparisons. Whole-fixture cycle counts additionally include reset/setup/held completion.

**Physical boundary.** Complete small-grid values are verified for these periodic dyadic inputs; some misaddressings can preserve periodic values, and arbitrary floating-point inputs are not characterized. The original full-sized grid is not validated. All CTAs are serial. There is no multi-SM placement, concurrent block residency, overlapped global staging, hardware cache contention or calibrated runtime. Columns-first traversal, one context, cache parameters and service timing remain development choices. Physical evidence counts remain eight identified, 32 partial and 94 unknown; no new parameter is closed.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_studied_gemm_grid.py` for all fixtures, or add `--quick` for the repeated 64 × 96 × K64 grid.

**Inline behavior.**

```systemverilog
// Complete in-bounds GEMM grid through one reused CTA context.
// Block columns advance first, then rows. This serial development schedule
// is not a multi-SM model, native block-placement rule or GPU timing claim.
module studied_gemm_grid_controller #(
 parameter int BM=32,BN=32,BK=32,M=64,N=96,K=64,
 parameter int SETS=64,WAYS=8,LATENCY=16,INTERVAL=4,READ_SLOTS=4,
 parameter int SERVICE_INTERVAL=1,RETURN_DELAY=1,ARITHMETIC_MODE=1,
 parameter int BARRIER_RELEASE_DELAY=1,MOVM_LATENCY=1,MOVM_INTERVAL=1
)(
 input logic clk,rst,launch_valid,output logic launch_ready,
 input logic[31:0]launch_id,a_base,b_base,c_base,
 output logic done_valid,input logic done_ready,output logic[31:0]done_id,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data,
 output logic store_req_valid,input logic store_req_ready,
 output logic[31:0]store_req_id,store_req_byte_address,store_req_data,
 input logic store_rsp_valid,output logic store_rsp_ready,input logic[31:0]store_rsp_id,
 output logic sector_store_req_valid,input logic sector_store_req_ready,
 output logic[31:0]sector_store_req_id,sector_store_req_byte_address,
 output logic[255:0]sector_store_req_data,output logic[7:0]sector_store_req_word_mask,
 input logic sector_store_rsp_valid,output logic sector_store_rsp_ready,
 input logic[31:0]sector_store_rsp_id,
 output int dispatched_blocks,completed_blocks,
 output logic block_launch_valid,output logic[31:0]block_launch_row,block_launch_col,
 output logic block_done_valid,output logic[31:0]block_done_row,block_done_col
);
 localparam int BLOCK_ROWS=M/BM,BLOCK_COLS=N/BN,BLOCKS=BLOCK_ROWS*BLOCK_COLS;
 typedef enum logic[1:0]{IDLE,LAUNCH_BLOCK,WAIT_BLOCK,DONE}state_t;
 state_t state;int block_row,block_col,block_ordinal;
 logic[31:0]saved_id,saved_a,saved_b,saved_c;
 logic cta_launch_valid,cta_launch_ready,cta_done_valid,cta_done_ready;
 logic[31:0]cta_done_id;
 initial if(BM!=32||BN!=32||BK!=32||M<32||N<32||M%BM!=0||N%BN!=0||K<BK||K%BK!=0)
  $fatal(1,"Unsupported native studied full-grid geometry");
 assign launch_ready=!rst&&state==IDLE;
 assign done_valid=!rst&&state==DONE;assign done_id=saved_id;
 assign cta_launch_valid=!rst&&state==LAUNCH_BLOCK;
 assign cta_done_ready=!rst&&state==WAIT_BLOCK;
 assign block_launch_valid=cta_launch_valid&&cta_launch_ready;
 assign block_launch_row=32'(block_row);assign block_launch_col=32'(block_col);
 assign block_done_valid=cta_done_valid&&cta_done_ready;
 assign block_done_row=32'(block_row);assign block_done_col=32'(block_col);
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;block_row<=0;block_col<=0;block_ordinal<=0;
   saved_id<=0;saved_a<=0;saved_b<=0;saved_c<=0;dispatched_blocks<=0;completed_blocks<=0;
  end else case(state)
   IDLE:if(launch_valid&&launch_ready)begin
    saved_id<=launch_id;saved_a<=a_base;saved_b<=b_base;saved_c<=c_base;
    block_row<=0;block_col<=0;block_ordinal<=0;dispatched_blocks<=0;completed_blocks<=0;
    state<=LAUNCH_BLOCK;
   end
   LAUNCH_BLOCK:if(cta_launch_valid&&cta_launch_ready)begin
    if(dispatched_blocks!=block_ordinal||completed_blocks!=block_ordinal)$fatal(1,"Grid block dispatch conservation failed");
    dispatched_blocks<=dispatched_blocks+1;state<=WAIT_BLOCK;
   end
   WAIT_BLOCK:if(cta_done_valid&&cta_done_ready)begin
    if(cta_done_id!=32'(block_ordinal))$fatal(1,"Grid CTA completion identity mismatch");
    if(dispatched_blocks!=completed_blocks+1)$fatal(1,"Grid CTA completion conservation failed");
    completed_blocks<=completed_blocks+1;
    if(block_ordinal==BLOCKS-1)state<=DONE;
    else begin
     block_ordinal<=block_ordinal+1;
     if(block_col==BLOCK_COLS-1)begin block_col<=0;block_row<=block_row+1;end
     else block_col<=block_col+1;
     state<=LAUNCH_BLOCK;
    end
   end
   DONE:if(done_valid&&done_ready)state<=IDLE;
   default:$fatal(1,"Invalid studied GEMM grid state");
  endcase
 end
 studied_gemm_cta_controller #(.BM(BM),.BN(BN),.BK(BK),.M(M),.N(N),.K(K),
  .DYNAMIC_CTA_COORDS(1),.SETS(SETS),.WAYS(WAYS),.LATENCY(LATENCY),.INTERVAL(INTERVAL),.READ_SLOTS(READ_SLOTS),
  .SERVICE_INTERVAL(SERVICE_INTERVAL),.RETURN_DELAY(RETURN_DELAY),.ARITHMETIC_MODE(ARITHMETIC_MODE),
  .USE_NATIVE_STAGE(1),.COALESCED_STAGING(1),.COALESCED_OUTPUT(1),.MULTIWARP_NATIVE_STAGE(1),
  .USE_OUTPUT_SCRATCH(1),.USE_CTA_BARRIERS(1),.BARRIER_RELEASE_DELAY(BARRIER_RELEASE_DELAY),.MOVM_LATENCY(MOVM_LATENCY),.MOVM_INTERVAL(MOVM_INTERVAL)) cta(
  .clk,.rst,.launch_valid(cta_launch_valid),.launch_ready(cta_launch_ready),.launch_id(32'(block_ordinal)),
  .launch_cta_row(32'(block_row)),.launch_cta_col(32'(block_col)),.a_base(saved_a),.b_base(saved_b),.c_base(saved_c),
  .done_valid(cta_done_valid),.done_ready(cta_done_ready),.done_id(cta_done_id),
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,
  .backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data,
  .store_req_valid,.store_req_ready,.store_req_id,.store_req_byte_address,.store_req_data,
  .store_rsp_valid,.store_rsp_ready,.store_rsp_id,
  .sector_store_req_valid,.sector_store_req_ready,.sector_store_req_id,.sector_store_req_byte_address,.sector_store_req_data,.sector_store_req_word_mask,
  .sector_store_rsp_valid,.sector_store_rsp_ready,.sector_store_rsp_id
 );
 // CTA done already requires every output store acknowledgement. Cache persists
 // between contexts: backing inputs must stay immutable until reset/invalidate.
 // Reset providers flush old transactions; identities contain no reset epoch.
endmodule
```

### 4.44. Resident preloaded compute stages with atomic admission

**Role and scope.** The [resident stage engine](numerical/resident_native_stage_engine.sv) keeps two independent preloaded compute-stage contexts while sharing exactly one scalar shared-read service, one MOVM service and one HMMA service. Each context has four warp windows, its own 4,096-byte operand array, C values, instruction positions, readiness, producer tracking and service ownership. Context count does not multiply execution-unit queue capacities. This is the bounded 32-element reduction stage, not concurrent complete CTAs or a full-grid SM model.

| Interface | Payload and contract |
|---|---|
| Shared initialization | Context index plus scalar halfword write or optional 32-lane masked write; only an idle context can be written |
| Stage request | Context index, external 32-bit ID and C registers `[4][32][8]`; accepted only when that context is idle and initialized |
| Availability | Per-context ready/initialized masks; readiness is evaluated independently of request valid |
| Stage response | Retained context/ID and `[4][32][8]` result words; selected response remains stable until acknowledged |
| Per-warp conditions | Memory-safe and fully-drained masks for each context, as distinguished in section 4.40 |
| Instruction trace | Issued context, warp and instruction address; at most one instruction across all contexts per edge |

**Shared arbitration and completion ownership.** A round-robin selector scans eligible warps across both contexts. All requests compete for the same default read/MOVM/HMMA capacities of 4/4/2, with provisional interval/return settings described in section 4.40. Actual completions update only their owning context and warp. Each accepted context increments a private epoch, or reuse sequence number. Internal IDs contain that epoch plus flattened warp/instruction index; default two-context/four-warp geometry uses nine local bits and 23 epoch bits. Stale epochs and unmatched pending operations are rejected. Epoch exhaustion requires reset rather than wrap.

Each context progresses independently through IDLE, RUN, DRAIN and RESPONSE. A separate response selector latches one completed context and holds it under backpressure. Holding context zero’s result does not stop context one from issuing, draining, or completing another stage. A context remains occupied until its own actual response acknowledgment. Reset cancels all contexts and shared services; it is not a physical context-switch timing rule.

**Admission wrapper and quantities.** The [admission wrapper](numerical/resident_stage_admission.sv) reserves a slot through the quantized allocator and accepts the selected engine stage on the same edge. Configured budgets are 65,536 register words, 102,400 shared bytes and 48 warps, with two implementation context slots. The request has 128 threads, 40 registers per thread, 8,192 user shared bytes and 1,024 reserved bytes. Its quantized demand is **5,120 register words and 9,216 shared bytes per request**. Outputs named `allocated_register_words` and `allocated_shared_bytes` report this demand; they are not live allocation totals and remain nonzero after retirement. Live counts are `resident_blocks`, `resident_warps` and the allocator’s internal slot state. Two admitted requests mean two blocks/eight warps, with derived combined demands 10,240 words and 18,432 bytes. Nominal shared reservation includes capacity beyond the engine’s 4,096-byte operand array; it does not imply an implemented output-scratch lifetime here.

The wrapper’s `stage_req_valid` is a ready-qualified transfer strobe, not an ordinary request held while stalled. It becomes true only when the outer launch, allocator and selected engine are ready together. The engine must therefore calculate readiness independently of this valid signal. This prevents the lowest-free allocation slot from changing underneath a stalled internal offer. Outer launch fields must be held until accepted. The same transfer reserves the slot and captures the stage’s ID; neither happens alone.

A response supplies context and ID, is checked even while held, and must match a live admission. `done_ready` acknowledges the actual engine result and retires that allocation on the same edge. The allocation remains live while completion is held. Final zero assertions apply to live block/warp/engine counts, not the constant request-demand outputs. **A complete CTA may not retire at an intermediate stage acknowledgment:** its reservation must span all reductions, output scratch and acknowledged global stores. This wrapper deliberately exercises stage lifetimes and has not implemented that full lifetime.

**Verification and boundary.** The [stage receipt](numerical/resident_native_stage_verification.json) checks 8,192 output words against distinct context-specific direct dot products, with nonzero initial C and shared-read capacities one and two. It checks interleaved instructions, held response while another context progresses, two retained allocations/eight warps, matching retirement, final zero live counts, and reset/refill. Source hashes match the tested engine and wrapper. Arbitration, timing and this partial-stage lifetime remain hypotheses; no physical parameter is closed.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_resident_native_stage.py`.

**Inline engine.**

```systemverilog
// Resident bounded native stages: independent context storage/state, ONE shared service set.
// Epoch tags isolate reused context windows. Global RR and timing remain hypotheses.
// Round-robin ONE global issue port and read>move>matrix return priority are
// simulation hypotheses, not RTX5090 scheduler topology or bandwidth facts.
// Address ALU is control-only; offsets precomputed, entry barrier assumed.
module resident_native_stage_engine #(
 parameter int CONTEXTS=2,
 parameter int WARPS=4,parameter bit ALLOW_WARP_WRITES=0,
 parameter int READ_SLOTS=4,SERVICE_INTERVAL=1,RETURN_DELAY=1,
 parameter int MOVM_SLOTS=4,MOVM_LATENCY=1,MOVM_INTERVAL=1,
 parameter int HMMA_SLOTS=2,HMMA_LATENCY=16,HMMA_INTERVAL=4,ARITHMETIC_MODE=1
)(
 input logic clk,rst,
 input logic[31:0]write_context,
 input logic write_valid,output logic write_ready,
 input logic[31:0]write_byte_address,input logic[15:0]write_data,
 input logic write_warp_valid,output logic write_warp_ready,
 input logic[31:0]write_warp_byte_addresses[32],
 input logic[15:0]write_warp_halfwords[32],input logic[31:0]write_warp_mask,
 input logic req_valid,output logic req_ready,input logic[31:0]req_context,req_id,
 input logic[31:0]c_registers[WARPS][32][8],
 output logic operands_initialized,addresses_legal,
 output logic[CONTEXTS-1:0]context_ready,context_initialized,
 output logic rsp_valid,input logic rsp_ready,
 output logic[31:0]rsp_context,rsp_id,result_registers[WARPS][32][8],output int outstanding,
 output logic[WARPS-1:0] warp_drained[CONTEXTS],warp_memory_safe[CONTEXTS],
 output logic native_issue_valid,output logic[31:0]native_issue_context,native_issue_warp,native_issue_pc
);
 import native_studied_stage_schedule::*;
 localparam int HALFWORDS=2048,TOTAL_WARPS=CONTEXTS*WARPS;
 localparam int LOCAL_BITS=$clog2(TOTAL_WARPS*INSTRUCTIONS),EPOCH_BITS=32-LOCAL_BITS;
 logic[EPOCH_BITS-1:0]epoch[CONTEXTS];
 int response_owner,response_cursor;
 typedef enum logic[1:0]{IDLE,RUN,DRAIN,RESPONSE}state_t;state_t state[CONTEXTS];
 int read_live_perwarp[TOTAL_WARPS];
 int warp_service_live[TOTAL_WARPS];logic service_pending[TOTAL_WARPS][INSTRUCTIONS];
 int pc[TOTAL_WARPS],round_robin,selected,read_live_count;int read_locations[32];
 logic[31:0]saved_id[CONTEXTS];logic[15:0]memory[CONTEXTS][HALFWORDS];logic initialized[CONTEXTS][HALFWORDS];
 logic[31:0]a_words[TOTAL_WARPS][2][32][4],b_raw[TOTAL_WARPS][2][32][4],b_moved[TOTAL_WARPS][2][32][4],accumulator[TOTAL_WARPS][32][8];
 logic a_ready[TOTAL_WARPS][2][4],b_ready[TOTAL_WARPS][2][4],mov_ready[TOTAL_WARPS][2][4],c_ready[TOTAL_WARPS][2];
 descriptor_t desc[TOTAL_WARPS],chosen_desc,completion_desc;
 native_control_decode::control_t control[TOTAL_WARPS],completion_control;
 logic dependencies_ready[TOTAL_WARPS],gate_valid[TOTAL_WARPS],gate_ready[TOTAL_WARPS],dispatch_valid[TOTAL_WARPS],dispatch_ready[TOTAL_WARPS],issued[TOTAL_WARPS],gate_error[TOTAL_WARPS];
 logic[5:0]busy_write[TOTAL_WARPS],busy_read[TOTAL_WARPS];logic[3:0]cooldown[TOTAL_WARPS];
 logic read_req_valid,read_req_ready,read_rsp_valid,read_rsp_ready;
 logic[31:0]read_req_id,read_rsp_id,read_addresses[32],read_inputs[32],read_outputs[32];int read_outstanding;
 logic mov_req_valid,mov_req_ready,mov_rsp_valid,mov_rsp_ready;
 logic[31:0]mov_req_id,mov_rsp_id,mov_inputs[32],mov_outputs[32];int mov_outstanding;
 logic h_req_valid,h_req_ready,h_rsp_valid,h_rsp_ready;
 logic[31:0]h_req_id,h_rsp_id,h_a[32][4],h_b[32][2],h_c[32][4],h_results[32][4];int h_outstanding;
 logic completion_valid,write_legal,warp_write_legal,selected_issued;
 logic[31:0]completion_id;int completion_warp,completion_pc,completion_context;
 logic[EPOCH_BITS-1:0]completion_epoch;
 logic all_issued[CONTEXTS],all_drained[CONTEXTS];
 function automatic int address(input bit operand_b,input int kk,word_index,lane,tile);
  if(operand_b)return 2048+64*(16*kk+lane/4)+32*(tile%2)+4*(lane%4)+(word_index%2)*512+(word_index/2)*16;
  return 64*(16*(tile/2)+lane/4)+32*kk+4*(lane%4)+(word_index%2)*512+(word_index/2)*16;
 endfunction
 initial if(CONTEXTS<1||WARPS<1||WARPS>4||EPOCH_BITS<1)$fatal(1,"Native stage supports one through four warps");
 assign write_legal=write_context<CONTEXTS&&write_byte_address[0]==0&&write_byte_address<=4094;
 assign write_ready=!rst&&write_legal&&(write_context<CONTEXTS?state[write_context]==IDLE:0)&&!read_req_valid;
 always_comb begin
  warp_write_legal=write_context<CONTEXTS;
  if(ALLOW_WARP_WRITES)for(int lane=0;lane<32;lane++)if(write_warp_mask[lane])begin
   if(write_warp_byte_addresses[lane][0]!=0||write_warp_byte_addresses[lane]>4094)warp_write_legal=0;
   for(int other=0;other<lane;other++)if(write_warp_mask[other]&&write_warp_byte_addresses[lane]==write_warp_byte_addresses[other])warp_write_legal=0;
  end
 end
 assign write_warp_ready=ALLOW_WARP_WRITES&&!rst&&warp_write_legal&&(write_context<CONTEXTS?state[write_context]==IDLE:0)&&!write_valid&&!read_req_valid;
 assign addresses_legal=req_context<CONTEXTS;
 assign req_ready=!rst&&(addresses_legal?context_ready[req_context]:0);
 assign operands_initialized=addresses_legal?context_initialized[req_context]:0;
 assign rsp_valid=!rst&&response_owner>=0;
 assign rsp_context=response_owner>=0?32'(response_owner):0;
 assign rsp_id=response_owner>=0?saved_id[response_owner]:0;
 always_comb begin
  outstanding=0;
  for(int ctx=0;ctx<CONTEXTS;ctx++)begin
   context_initialized[ctx]=1;
   for(int warp=0;warp<WARPS;warp++)for(int kk=0;kk<2;kk++)for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)
    context_initialized[ctx]=context_initialized[ctx]&&initialized[ctx][address(0,kk,word,lane,warp)/2]&&initialized[ctx][address(0,kk,word,lane,warp)/2+1]&&initialized[ctx][address(1,kk,word,lane,warp)/2]&&initialized[ctx][address(1,kk,word,lane,warp)/2+1];
   context_ready[ctx]=!rst&&state[ctx]==IDLE&&context_initialized[ctx];
   if(state[ctx]!=IDLE)outstanding++;
  end
  for(int warp=0;warp<WARPS;warp++)for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)
   result_registers[warp][lane][word]=response_owner>=0?accumulator[response_owner*WARPS+warp][lane][word]:0;
 end
 always_comb begin
  for(int warp=0;warp<TOTAL_WARPS;warp++)begin
   desc[warp]='0;if(pc[warp]<INSTRUCTIONS)desc[warp]=descriptor(pc[warp]);
   control[warp]=native_control_decode::decode(desc[warp].raw);
   dependencies_ready[warp]=1;
   if(desc[warp].kind==2)dependencies_ready[warp]=b_ready[warp][desc[warp].kk][desc[warp].word_index];
   if(desc[warp].kind==3)begin
    dependencies_ready[warp]=c_ready[warp][desc[warp].upper_half];
    for(int word=0;word<4;word++)dependencies_ready[warp]=dependencies_ready[warp]&&a_ready[warp][desc[warp].kk][word];
    for(int word=0;word<2;word++)dependencies_ready[warp]=dependencies_ready[warp]&&mov_ready[warp][desc[warp].kk][2*int'(desc[warp].upper_half)+word];
   end
   gate_valid[warp]=!rst&&state[warp/WARPS]==RUN&&pc[warp]<INSTRUCTIONS&&dependencies_ready[warp];
  end
 end
 always_comb begin
  for(int ctx=0;ctx<CONTEXTS;ctx++)begin
   all_issued[ctx]=1;all_drained[ctx]=1;
   for(int localwarp=0;localwarp<WARPS;localwarp++)begin
    int warp;warp=ctx*WARPS+localwarp;
    if(pc[warp]!=INSTRUCTIONS)all_issued[ctx]=0;
    if(pc[warp]!=INSTRUCTIONS||busy_write[warp]!=0||busy_read[warp]!=0||cooldown[warp]!=0||!c_ready[warp][0]||!c_ready[warp][1]||warp_service_live[warp]!=0)all_drained[ctx]=0;
   end
  end
 end
 always_comb begin
  selected=-1;
  for(int offset=0;offset<TOTAL_WARPS;offset++)begin
   int candidate;candidate=(round_robin+offset)%TOTAL_WARPS;
   if(selected<0&&dispatch_valid[candidate])begin
    case(desc[candidate].kind)
     // All precomputed load addresses are aligned; capacity is readiness here.
     1:if(read_live_count<READ_SLOTS)selected=candidate;
     2:if(mov_req_ready)selected=candidate;
     3:if(h_req_ready)selected=candidate;
     default:selected=candidate;
    endcase
   end
  end
  chosen_desc='0;if(selected>=0)chosen_desc=desc[selected];
 end
 always_comb begin
  for(int warp=0;warp<TOTAL_WARPS;warp++)begin
   dispatch_ready[warp]=0;
   if(selected==warp)begin
    case(desc[warp].kind)
     1:dispatch_ready[warp]=read_req_ready;
     2:dispatch_ready[warp]=mov_req_ready;
     3:dispatch_ready[warp]=h_req_ready;
     default:dispatch_ready[warp]=1;
    endcase
   end
  end
 end
 always_comb begin
  selected_issued=0;
  for(int warp=0;warp<TOTAL_WARPS;warp++)if(issued[warp])selected_issued=1;
 end
 always_comb begin
  read_req_valid=0;mov_req_valid=0;h_req_valid=0;
  read_req_id=0;mov_req_id=0;h_req_id=0;
  native_issue_valid=selected_issued;native_issue_context=0;native_issue_warp=0;native_issue_pc=0;
  if(selected>=0)begin
   native_issue_context=32'(selected/WARPS);native_issue_warp=32'(selected%WARPS);native_issue_pc=32'h1350+32'(16*pc[selected]);
   read_req_id=(32'(epoch[selected/WARPS])<<LOCAL_BITS)|32'(selected*INSTRUCTIONS+pc[selected]);mov_req_id=read_req_id;h_req_id=read_req_id;
   read_req_valid=issued[selected]&&chosen_desc.kind==1;
   mov_req_valid=issued[selected]&&chosen_desc.kind==2;
   h_req_valid=issued[selected]&&chosen_desc.kind==3;
  end
 end
 always_comb begin
  for(int lane=0;lane<32;lane++)begin
   read_locations[lane]=0;
   read_addresses[lane]=0;read_inputs[lane]=0;mov_inputs[lane]=0;
   for(int word=0;word<4;word++)begin h_a[lane][word]=0;h_c[lane][word]=0;end
   for(int word=0;word<2;word++)h_b[lane][word]=0;
   if(selected>=0)begin
    read_locations[lane]=address(chosen_desc.operand_b,int'(chosen_desc.kk),int'(chosen_desc.word_index),lane,selected%WARPS);
    read_addresses[lane]=32'(read_locations[lane]);read_inputs[lane]={memory[selected/WARPS][read_locations[lane]/2+1],memory[selected/WARPS][read_locations[lane]/2]};
    mov_inputs[lane]=b_raw[selected][chosen_desc.kk][lane][chosen_desc.word_index];
    for(int word=0;word<4;word++)begin h_a[lane][word]=a_words[selected][chosen_desc.kk][lane][word];h_c[lane][word]=accumulator[selected][lane][4*int'(chosen_desc.upper_half)+word];end
    for(int word=0;word<2;word++)h_b[lane][word]=b_moved[selected][chosen_desc.kk][lane][2*int'(chosen_desc.upper_half)+word];
   end
  end
 end
 always_comb begin
  read_rsp_ready=!rst;
  mov_rsp_ready=read_rsp_ready&&!read_rsp_valid;
  h_rsp_ready=mov_rsp_ready&&!mov_rsp_valid;
  completion_valid=(read_rsp_valid&&read_rsp_ready)||(mov_rsp_valid&&mov_rsp_ready)||(h_rsp_valid&&h_rsp_ready);
  completion_id=read_rsp_valid?read_rsp_id:(mov_rsp_valid?mov_rsp_id:h_rsp_id);
  completion_warp=int'(completion_id & ((32'b1<<LOCAL_BITS)-1))/INSTRUCTIONS;completion_pc=int'(completion_id & ((32'b1<<LOCAL_BITS)-1))%INSTRUCTIONS;
  completion_context=completion_warp/WARPS;completion_epoch=EPOCH_BITS'(completion_id>>LOCAL_BITS);
  completion_desc='0;if(completion_valid&&completion_warp<TOTAL_WARPS)completion_desc=descriptor(completion_pc);
  completion_control=native_control_decode::decode(completion_desc.raw);
 end
 always_ff @(posedge clk)begin
  if(rst)begin
   response_owner<=-1;response_cursor<=0;round_robin<=0;read_live_count<=0;
   for(int ctx=0;ctx<CONTEXTS;ctx++)begin state[ctx]<=IDLE;saved_id[ctx]<=0;epoch[ctx]<=0;warp_drained[ctx]<='0;warp_memory_safe[ctx]<='0;for(int i=0;i<HALFWORDS;i++)initialized[ctx][i]<=0;end
   for(int warp=0;warp<TOTAL_WARPS;warp++)begin
    read_live_perwarp[warp]<=0;warp_service_live[warp]<=0;for(int op=0;op<INSTRUCTIONS;op++)service_pending[warp][op]<=0;
    pc[warp]<=0;for(int kk=0;kk<2;kk++)for(int word=0;word<4;word++)begin a_ready[warp][kk][word]<=0;b_ready[warp][kk][word]<=0;mov_ready[warp][kk][word]<=0;end
    for(int half=0;half<2;half++)c_ready[warp][half]<=0;
    for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)accumulator[warp][lane][word]<=0;
   end
  end else begin
   // Memory reuse safety is separate from register-only service drain.
   // This bounded-window signal does not replay the following native BAR PCs.
   begin
    integer total_reads;total_reads=0;
    for(int warp=0;warp<TOTAL_WARPS;warp++)begin
     bit accepted_read,retired_read;integer delta;
     accepted_read=read_req_valid&&read_req_ready&&int'(read_req_id & ((32'b1<<LOCAL_BITS)-1))/INSTRUCTIONS==warp;
     retired_read=read_rsp_valid&&read_rsp_ready&&int'(read_rsp_id & ((32'b1<<LOCAL_BITS)-1))/INSTRUCTIONS==warp;
     delta=int'(accepted_read)-int'(retired_read);
     total_reads+=read_live_perwarp[warp];
     if(read_live_perwarp[warp]<0||read_live_perwarp[warp]>READ_SLOTS)$fatal(1,"Per-warp shared-read liveness out of bounds");
     if(retired_read&&read_live_perwarp[warp]==0)$fatal(1,"Shared-read completion lacks warp credit");
     read_live_perwarp[warp]<=read_live_perwarp[warp]+delta;
     if((state[warp/WARPS]==RUN||state[warp/WARPS]==DRAIN)&&pc[warp]==INSTRUCTIONS&&cooldown[warp]==0&&read_live_perwarp[warp]==0)
      warp_memory_safe[warp/WARPS][warp%WARPS]<=1;
     if(warp_memory_safe[warp/WARPS][warp%WARPS]&&(state[warp/WARPS]==RUN||state[warp/WARPS]==DRAIN||state[warp/WARPS]==RESPONSE)&&read_live_perwarp[warp]!=0)$fatal(1,"Memory-safe warp retains pending shared read");
    end
    if(total_reads!=read_outstanding)$fatal(1,"Per-warp shared-read conservation failed");
   end
   // Per-warp liveness follows accepted service operations and actual retired
   // responses. Decoded barrier bits alone do not cover every pending operation.
   begin
    integer total_live;total_live=0;
    for(int warp=0;warp<TOTAL_WARPS;warp++)begin
     integer delta;bit accepted,retired;delta=0;
     accepted=(read_req_valid&&read_req_ready&&int'(read_req_id & ((32'b1<<LOCAL_BITS)-1))/INSTRUCTIONS==warp)||
              (mov_req_valid&&mov_req_ready&&int'(mov_req_id & ((32'b1<<LOCAL_BITS)-1))/INSTRUCTIONS==warp)||
              (h_req_valid&&h_req_ready&&int'(h_req_id & ((32'b1<<LOCAL_BITS)-1))/INSTRUCTIONS==warp);
     retired=completion_valid&&completion_warp==warp;
     total_live+=warp_service_live[warp];
     if(warp_service_live[warp]<0||warp_service_live[warp]>READ_SLOTS+MOVM_SLOTS+HMMA_SLOTS)$fatal(1,"Warp service liveness out of bounds");
     if(accepted)begin
      if(pc[warp]>=INSTRUCTIONS||service_pending[warp][pc[warp]])$fatal(1,"Duplicate/out-of-range warp service acceptance");
      service_pending[warp][pc[warp]]<=1;delta++;
     end
     if(retired)begin
      if(!service_pending[warp][completion_pc]||warp_service_live[warp]==0)$fatal(1,"Warp completion without accepted operation");
      service_pending[warp][completion_pc]<=0;delta--;
     end
     warp_service_live[warp]<=warp_service_live[warp]+delta;
     if((state[warp/WARPS]==RUN||state[warp/WARPS]==DRAIN)&&pc[warp]==INSTRUCTIONS&&busy_read[warp]==0&&busy_write[warp]==0&&cooldown[warp]==0&&c_ready[warp][0]&&c_ready[warp][1]&&warp_service_live[warp]==0)
      warp_drained[warp/WARPS][warp%WARPS]<=1;
     if(warp_drained[warp/WARPS][warp%WARPS]&&(state[warp/WARPS]==RUN||state[warp/WARPS]==DRAIN||state[warp/WARPS]==RESPONSE)&&warp_service_live[warp]!=0)$fatal(1,"Drained warp retains pending service");
     if(state[warp/WARPS]==RESPONSE&&warp_service_live[warp]!=0)$fatal(1,"Batch response retains warp service");
    end
    if(total_live!=read_outstanding+mov_outstanding+h_outstanding)$fatal(1,"Per-warp/global service conservation failed");
   end
   // Local admission credits are exact transfer counts, not capacity estimates.
   if(read_live_count!=read_outstanding)$fatal(1,"Shared read credit conservation failed");
   if(read_req_valid&&!read_req_ready)$fatal(1,"Granted read lacks actual service readiness");
   case({read_req_valid&&read_req_ready,read_rsp_valid&&read_rsp_ready})
    2'b10:read_live_count<=read_live_count+1;
    2'b01:read_live_count<=read_live_count-1;
    default:read_live_count<=read_live_count;
   endcase
   if(write_valid&&!write_legal)$fatal(1,"Invalid multiwarp shared write");
   if(ALLOW_WARP_WRITES&&write_warp_valid&&!warp_write_legal)$fatal(1,"Invalid multiwarp vector write");
   for(int warp=0;warp<TOTAL_WARPS;warp++)if(gate_error[warp])$fatal(1,"Multiwarp barrier error");
   if(write_valid&&write_ready)begin memory[write_context][write_byte_address/2]<=write_data;initialized[write_context][write_byte_address/2]<=1;end
   if(ALLOW_WARP_WRITES&&write_warp_valid&&write_warp_ready)for(int lane=0;lane<32;lane++)if(write_warp_mask[lane])begin memory[write_context][write_warp_byte_addresses[lane]/2]<=write_warp_halfwords[lane];initialized[write_context][write_warp_byte_addresses[lane]/2]<=1;end
   if(completion_valid)begin
    if(completion_warp>=TOTAL_WARPS)$fatal(1,"Unknown resident completion ID");
    else if(completion_epoch!=epoch[completion_context]||state[completion_context]==IDLE||state[completion_context]==RESPONSE)$fatal(1,"Stale resident completion epoch");
   end
   if(read_rsp_valid&&read_rsp_ready)begin
    if(completion_desc.kind!=1)$fatal(1,"Wrong multiwarp read completion class");
    for(int lane=0;lane<32;lane++)begin
     if(completion_desc.operand_b)b_raw[completion_warp][completion_desc.kk][lane][completion_desc.word_index]<=read_outputs[lane];
     else a_words[completion_warp][completion_desc.kk][lane][completion_desc.word_index]<=read_outputs[lane];
    end
    if(completion_desc.operand_b)b_ready[completion_warp][completion_desc.kk][completion_desc.word_index]<=1;
    else a_ready[completion_warp][completion_desc.kk][completion_desc.word_index]<=1;
   end
   if(mov_rsp_valid&&mov_rsp_ready)begin
    if(completion_desc.kind!=2)$fatal(1,"Wrong multiwarp MOVM completion class");
    for(int lane=0;lane<32;lane++)b_moved[completion_warp][completion_desc.kk][lane][completion_desc.word_index]<=mov_outputs[lane];
    mov_ready[completion_warp][completion_desc.kk][completion_desc.word_index]<=1;
   end
   if(h_rsp_valid&&h_rsp_ready)begin
    if(completion_desc.kind!=3)$fatal(1,"Wrong multiwarp HMMA completion class");
    for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)accumulator[completion_warp][lane][4*int'(completion_desc.upper_half)+word]<=h_results[lane][word];
    c_ready[completion_warp][completion_desc.upper_half]<=1;
   end
   if(req_valid&&!addresses_legal)$fatal(1,"Invalid request context");
   for(int warp=0;warp<TOTAL_WARPS;warp++)if(issued[warp])begin
    pc[warp]<=pc[warp]+1;if(desc[warp].kind==3)c_ready[warp][desc[warp].upper_half]<=0;
    round_robin<=(warp+1)%TOTAL_WARPS;
   end
   for(int ctx=0;ctx<CONTEXTS;ctx++)begin
    case(state[ctx])
     IDLE:if(req_valid&&req_ready&&req_context==ctx)begin
      if(&epoch[ctx])$fatal(1,"Resident epoch exhausted; reset required");
      epoch[ctx]<=epoch[ctx]+1;state[ctx]<=RUN;saved_id[ctx]<=req_id;
      warp_drained[ctx]<='0;warp_memory_safe[ctx]<='0;
      for(int localwarp=0;localwarp<WARPS;localwarp++)begin
       int warp;warp=ctx*WARPS+localwarp;
       read_live_perwarp[warp]<=0;warp_service_live[warp]<=0;
       for(int op=0;op<INSTRUCTIONS;op++)service_pending[warp][op]<=0;
       pc[warp]<=0;
       for(int kk=0;kk<2;kk++)for(int word=0;word<4;word++)begin a_ready[warp][kk][word]<=0;b_ready[warp][kk][word]<=0;mov_ready[warp][kk][word]<=0;end
       for(int half=0;half<2;half++)c_ready[warp][half]<=1;
       for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)accumulator[warp][lane][word]<=c_registers[localwarp][lane][word];
      end
     end
     RUN:if(all_issued[ctx])state[ctx]<=DRAIN;
     DRAIN:if(all_drained[ctx])state[ctx]<=RESPONSE;
     RESPONSE:if(rsp_valid&&rsp_ready&&response_owner==ctx)state[ctx]<=IDLE;
     default:$fatal(1,"Invalid resident context state");
    endcase
   end
   if(response_owner<0)begin
    int choice;choice=-1;
    for(int offset=0;offset<CONTEXTS;offset++)begin
     int candidate;candidate=(response_cursor+offset)%CONTEXTS;
     if(choice<0&&state[candidate]==RESPONSE)choice=candidate;
    end
    if(choice>=0)response_owner<=choice;
   end else if(rsp_valid&&rsp_ready)begin response_cursor<=(response_owner+1)%CONTEXTS;response_owner<=-1;end

  end
 end
 for(genvar warp=0;warp<TOTAL_WARPS;warp++)begin:warps
  decoded_native_issue_gate #(.MAX_OPS(64),.TAG_W(7),.COUNT_W(7)) gate(
   .clk,.reset(rst||state[warp/WARPS]==IDLE),.instr_valid(gate_valid[warp]),.instr_ready(gate_ready[warp]),
   .operation_id(7'(pc[warp])),.control(control[warp]),.dispatch_valid(dispatch_valid[warp]),.dispatch_ready(dispatch_ready[warp]),.issued(issued[warp]),
   .write_complete_valid(completion_valid&&completion_warp==warp&&completion_control.write_barrier!=7),.write_complete_tag(7'(completion_pc)),
   .read_complete_valid(1'b0),.read_complete_tag(7'd0),.busy_write_mask(busy_write[warp]),.busy_read_mask(busy_read[warp]),.cooldown(cooldown[warp]),.error_sticky(gate_error[warp])
  );
 end
 warp_shared_read_service #(.SLOTS(READ_SLOTS),.SERVICE_INTERVAL(SERVICE_INTERVAL),.RETURN_DELAY(RETURN_DELAY)) reads(
  .clk,.rst,.req_valid(read_req_valid),.req_ready(read_req_ready),.req_id(read_req_id),.byte_addresses(read_addresses),.input_words(read_inputs),
  .rsp_valid(read_rsp_valid),.rsp_ready(read_rsp_ready),.rsp_id(read_rsp_id),.output_words(read_outputs),.outstanding(read_outstanding),.request_packages()
 );
 native_movm_word_pipeline #(.SLOTS(MOVM_SLOTS),.LATENCY(MOVM_LATENCY),.INTERVAL(MOVM_INTERVAL)) moves(
  .clk,.rst,.req_valid(mov_req_valid),.req_ready(mov_req_ready),.req_id(mov_req_id),.input_words(mov_inputs),
  .rsp_valid(mov_rsp_valid),.rsp_ready(mov_rsp_ready),.rsp_id(mov_rsp_id),.output_words(mov_outputs),.outstanding(mov_outstanding)
 );
 native_hmma16816_adapter #(.SLOTS(HMMA_SLOTS),.LATENCY(HMMA_LATENCY),.INTERVAL(HMMA_INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) tensor(
  .clk,.rst,.req_valid(h_req_valid),.req_ready(h_req_ready),.req_id(h_req_id),.a_registers(h_a),.b_registers(h_b),.c_registers(h_c),
  .rsp_valid(h_rsp_valid),.rsp_ready(h_rsp_ready),.rsp_id(h_rsp_id),.result_registers(h_results),.outstanding(h_outstanding)
 );
 // Shared values sampled on accepted LD.E issue. No full native register file,
 // address-ALU scoreboard, original missing scratch/barrier protocol or full SM.
endmodule
```

**Inline admission wrapper.**

```systemverilog
// Resource reservation for a preloaded resident native stage.
// One stage represents a bounded compute window, not an entire CTA lifetime.
// Do not use stage response retirement as full-GEMM block retirement.
module resident_stage_admission #(
 parameter int CONTEXTS=2,REG_WORDS=65536,SHARED_BYTES=102400,MAX_WARPS=48,
 parameter int THREADS=128,REGS_PER_THREAD=40,USER_SHARED_BYTES=8192,RESERVED_SHARED_BYTES=1024
)(
 input logic clk,rst,
 input logic launch_valid,output logic launch_ready,input logic[31:0]launch_id,
 output logic stage_req_valid,input logic stage_req_ready,
 output int stage_req_context,output logic[31:0]stage_req_id,
 input logic stage_rsp_valid,output logic stage_rsp_ready,
 input int stage_rsp_context,input logic[31:0]stage_rsp_id,
 output logic done_valid,input logic done_ready,
 output int done_context,output logic[31:0]done_id,
 output int resident_blocks,resident_warps,allocated_register_words,allocated_shared_bytes
);
 logic allocator_ready,admit_fire,retire_fire;
 int admitted_slot;
 logic live[CONTEXTS];logic[31:0]ids[CONTEXTS];
 initial if(CONTEXTS<1)$fatal(1,"Invalid resident context capacity");
 assign stage_req_context=admitted_slot;
 assign stage_req_id=launch_id;
 // The engine must evaluate readiness independently of stage_req_valid for
 // the selected context. This ready-qualified transfer strobe avoids offering
 // a stalled request whose lowest-free context could change on retirement.
 // Reservation and stage acceptance happen at the same edge, or neither does.
 assign stage_req_valid=!rst&&launch_valid&&allocator_ready&&stage_req_ready;
 assign launch_ready=!rst&&allocator_ready&&stage_req_ready;
 assign admit_fire=launch_valid&&launch_ready;
 assign done_valid=!rst&&stage_rsp_valid;
 assign done_context=stage_rsp_context;assign done_id=stage_rsp_id;
 assign stage_rsp_ready=!rst&&done_ready;
 assign retire_fire=stage_rsp_valid&&stage_rsp_ready;
 quantized_block_admission #(.BLOCK_SLOTS(CONTEXTS),.REG_WORDS(REG_WORDS),
  .SHARED_BYTES(SHARED_BYTES),.MAX_WARPS(MAX_WARPS)) admission(
  .clk,.rst,.admit_valid(admit_fire),.block_threads(THREADS),
  .registers_per_thread(REGS_PER_THREAD),.user_shared_bytes(USER_SHARED_BYTES),
  .reserved_shared_bytes(RESERVED_SHARED_BYTES),.admit_ready(allocator_ready),
  .admitted_slot,.resident_blocks,.resident_warps,.allocated_register_words,.allocated_shared_bytes,
  .retire_valid(retire_fire),.retire_slot(stage_rsp_context)
 );
 always_ff @(posedge clk)begin
  if(rst)for(int c=0;c<CONTEXTS;c++)begin live[c]<=0;ids[c]<=0;end
  else begin
   // Check even a held response: malformed completion must never escape.
   if(stage_rsp_valid)begin
    if(stage_rsp_context<0||stage_rsp_context>=CONTEXTS)$fatal(1,"Resident response context outside capacity");
    else if(!live[stage_rsp_context]||ids[stage_rsp_context]!=stage_rsp_id)$fatal(1,"Resident response has no matching admitted operation");
   end
   if(retire_fire)live[stage_rsp_context]<=0;
   if(admit_fire)begin
    if(admitted_slot<0||admitted_slot>=CONTEXTS)$fatal(1,"Resident admission context outside capacity");
    else if(live[admitted_slot])$fatal(1,"Resident admission overwrote a live context");
    else begin live[admitted_slot]<=1;ids[admitted_slot]<=launch_id;end
   end
  end
 end
endmodule
```

### 4.45. Two resident load contexts sharing one sector cache

**Role.** The [resident U16 loader](numerical/resident_u16_warp_load.sv) keeps two independently accepted warp-load requests while sharing exactly one blocking sector cache. Each request has up to 32 aligned BF16 halfword addresses and an active mask. Context state and returned values are separate; cache sets/ways and backing capacity are not duplicated. This component is not yet connected to section 4.44’s resident compute engine into concurrent full CTAs.

| Interface | Payload and contract |
|---|---|
| Load request | 32-bit context and ID, 32 byte addresses and active mask; accepted only for an idle context with legal active addresses |
| Availability | One ready bit per context; outstanding counts non-idle load contexts |
| Load response | Retained context/ID, 32 halfwords and unique-sector count; held until acknowledged |
| Shared backing | ID-matched 256-bit packets through one cache; actual returns supply the halfwords |
| Reset | Cancels contexts and cache; external provider flushes pre-reset returns |

Each context captures accepted addresses and mask, constructs its unique 32-byte sectors, and progresses through IDLE, SEND, WAIT_PACKET and RESPONSE. A round-robin cache owner is latched before request valid is asserted. This keeps ID/address stable if another context becomes eligible during backpressure. After one actual packet completes, relevant active halfwords are extracted and the cursor can select another context. A separate response owner holds completed values without blocking the other context’s cache progress. Empty masks return zeros without traffic; inactive lanes return zero and their addresses are ignored.

Per-context epochs distinguish reused operations. Default two-context geometry uses six local ID bits for context/sector ordinal and 26 epoch bits. Matching IDs are checked on actual packet return; epochs cannot wrap. Reset resets epochs, so provider flushing is still required. Inputs must remain immutable across cache-preserving requests, or the cache must be reset; no invalidation port is exposed. Defaults of 64 sets/eight ways and serial unique-sector service remain model choices rather than recovered L2 organization or throughput.

The [loader receipt](numerical/resident_u16_verification.json) checks 128 lane values against the independently accepted address formula. It covers snapshots, masks/empty requests, cache reuse across contexts, delayed matching packets, held response with other-context progress, reset/provider cancellation and accepted-minus-retired conservation. The saved post-reset fixture makes two backing misses; that is fixture behavior, not a hardware bandwidth result. Frozen source hashes match the receipt. Timing is uncalibrated, and physical evidence remains eight identified fields, 32 partial and 94 unknown.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_resident_u16_warp_load.py`.

**Inline behavior.**

```systemverilog
// Independent warp-load contexts share exactly one blocking sector cache.
// RR arbitration and serial sector service are simulation hypotheses.
module resident_u16_warp_load #(
 parameter int CONTEXTS=2,SETS=64,WAYS=8
)(
 input logic clk,rst,req_valid,output logic req_ready,
 input logic[31:0]req_context,req_id,byte_addresses[32],active_mask,
 output logic[CONTEXTS-1:0]context_ready,output int outstanding,
 output logic rsp_valid,input logic rsp_ready,
 output logic[31:0]rsp_context,rsp_id,
 output logic[15:0]halfwords[32],output int sector_count,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data
);
 localparam int LOCAL_BITS=$clog2(CONTEXTS*32),EPOCH_BITS=32-LOCAL_BITS;
 typedef enum logic[1:0]{IDLE,SEND,WAIT_PACKET,RESPONSE}state_t;
 state_t state[CONTEXTS];
 logic[EPOCH_BITS-1:0]epoch[CONTEXTS];
 logic[31:0]saved_id[CONTEXTS],saved_addresses[CONTEXTS][32],saved_mask[CONTEXTS],sector_list[CONTEXTS][32],candidate_sectors[32];
 logic[15:0]saved_halfwords[CONTEXTS][32];
 int counts[CONTEXTS],current_sector[CONTEXTS],candidate_count;
 int cache_owner,cache_cursor,response_owner,response_cursor;
 logic addresses_legal,lane_found[32];
 logic cache_req_valid,cache_req_ready,cache_rsp_valid,cache_rsp_ready,cache_rsp_hit;
 logic[31:0]cache_id,cache_address,cache_rsp_id,cache_rsp_word;
 logic[255:0]cache_packet;
 initial if(CONTEXTS<1||EPOCH_BITS<1)$fatal(1,"Invalid resident loader context capacity");
 always_comb begin
  candidate_count=0;addresses_legal=1;
  for(int i=0;i<32;i++)begin candidate_sectors[i]=0;lane_found[i]=0;end
  for(int lane=0;lane<32;lane++)if(active_mask[lane])begin
   if(byte_addresses[lane][0])addresses_legal=0;
   for(int i=0;i<32;i++)if(i<candidate_count&&candidate_sectors[i]=={byte_addresses[lane][31:5],5'b0})lane_found[lane]=1;
   if(!lane_found[lane])begin candidate_sectors[candidate_count]={byte_addresses[lane][31:5],5'b0};candidate_count++;end
  end
 end
 always_comb begin
  outstanding=0;
  for(int ctx=0;ctx<CONTEXTS;ctx++)begin
   context_ready[ctx]=!rst&&state[ctx]==IDLE;
   if(state[ctx]!=IDLE)outstanding++;
  end
 end
 assign req_ready=!rst&&addresses_legal&&(req_context<CONTEXTS?context_ready[req_context]:0);
 assign rsp_valid=!rst&&response_owner>=0;
 assign rsp_context=response_owner>=0?32'(response_owner):0;
 assign rsp_id=response_owner>=0?saved_id[response_owner]:0;
 assign sector_count=response_owner>=0?counts[response_owner]:0;
 always_comb for(int lane=0;lane<32;lane++)halfwords[lane]=response_owner>=0?saved_halfwords[response_owner][lane]:0;
 // Owners latch before valid is asserted. Payload therefore cannot change when
 // another context becomes eligible while the cache/provider is backpressured.
 assign cache_req_valid=!rst&&cache_owner>=0&&(cache_owner>=0?state[cache_owner]==SEND:0);
 assign cache_rsp_ready=!rst&&cache_owner>=0&&(cache_owner>=0?state[cache_owner]==WAIT_PACKET:0);
 assign cache_id=cache_owner>=0?(32'(epoch[cache_owner])<<LOCAL_BITS)|32'(cache_owner*32+current_sector[cache_owner]):0;
 assign cache_address=cache_owner>=0?sector_list[cache_owner][current_sector[cache_owner]]:0;
 always_ff @(posedge clk)begin
  if(rst)begin
   cache_owner<=-1;cache_cursor<=0;response_owner<=-1;response_cursor<=0;
   for(int ctx=0;ctx<CONTEXTS;ctx++)begin
    state[ctx]<=IDLE;epoch[ctx]<=0;saved_id[ctx]<=0;saved_mask[ctx]<=0;counts[ctx]<=0;current_sector[ctx]<=0;
    for(int lane=0;lane<32;lane++)begin saved_addresses[ctx][lane]<=0;saved_halfwords[ctx][lane]<=0;sector_list[ctx][lane]<=0;end
   end
  end else begin
   if(req_valid&&req_context>=CONTEXTS)$fatal(1,"Resident load context out of bounds");
   if(req_valid&&req_context<CONTEXTS&&state[req_context]==IDLE&&!addresses_legal)$fatal(1,"Unaligned active resident u16 address");
   if(req_valid&&req_ready)begin
    if(&epoch[req_context])$fatal(1,"Resident loader epoch exhausted; reset required");
    epoch[req_context]<=epoch[req_context]+1;
    saved_id[req_context]<=req_id;saved_mask[req_context]<=active_mask;
    counts[req_context]<=candidate_count;current_sector[req_context]<=0;
    for(int lane=0;lane<32;lane++)begin
     saved_addresses[req_context][lane]<=byte_addresses[lane];sector_list[req_context][lane]<=candidate_sectors[lane];saved_halfwords[req_context][lane]<=0;
    end
    state[req_context]<=candidate_count==0?RESPONSE:SEND;
   end
   if(cache_owner<0)begin
    int choice;choice=-1;
    for(int offset=0;offset<CONTEXTS;offset++)begin
     int candidate;candidate=(cache_cursor+offset)%CONTEXTS;
     if(choice<0&&state[candidate]==SEND)choice=candidate;
    end
    if(choice>=0)cache_owner<=choice;
   end else begin
    if(cache_req_valid&&cache_req_ready)state[cache_owner]<=WAIT_PACKET;
    if(cache_rsp_valid&&cache_rsp_ready)begin
     if(cache_rsp_id!=cache_id)$fatal(1,"Resident sector completion identity mismatch");
     for(int lane=0;lane<32;lane++)if(saved_mask[cache_owner][lane]&&{saved_addresses[cache_owner][lane][31:5],5'b0}==sector_list[cache_owner][current_sector[cache_owner]])
      saved_halfwords[cache_owner][lane]<=cache_packet[int'(saved_addresses[cache_owner][lane][4:0])*8+:16];
     if(current_sector[cache_owner]==counts[cache_owner]-1)state[cache_owner]<=RESPONSE;
     else begin current_sector[cache_owner]<=current_sector[cache_owner]+1;state[cache_owner]<=SEND;end
     cache_cursor<=(cache_owner+1)%CONTEXTS;cache_owner<=-1;
    end
   end
   if(response_owner<0)begin
    int choice;choice=-1;
    for(int offset=0;offset<CONTEXTS;offset++)begin
     int candidate;candidate=(response_cursor+offset)%CONTEXTS;
     if(choice<0&&state[candidate]==RESPONSE)choice=candidate;
    end
    if(choice>=0)response_owner<=choice;
   end else if(rsp_valid&&rsp_ready)begin
    state[response_owner]<=IDLE;response_cursor<=(response_owner+1)%CONTEXTS;response_owner<=-1;
   end
  end
 end
 sector_read_cache #(.SETS(SETS),.WAYS(WAYS)) cache(
  .clk,.rst,.req_valid(cache_req_valid),.req_ready(cache_req_ready),.req_id(cache_id),.req_byte_address(cache_address),
  .rsp_valid(cache_rsp_valid),.rsp_ready(cache_rsp_ready),.rsp_id(cache_rsp_id),.rsp_data(cache_rsp_word),.rsp_sector_data(cache_packet),.rsp_hit(cache_rsp_hit),
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,
  .backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data
 );
 // Immutable backing storage between requests, or cache reset required. Reset
 // cancels contexts/cache; the external provider must flush pre-reset returns.
 // Empty requests return zeros without traffic; inactive lane addresses ignored.
endmodule
```

### 4.46. Actual global operand frames committed to resident shared storage

**Role and geometry.** The [resident operand stager](numerical/resident_operand_staging.sv) supplies the 4,096-byte operand frame for a selected resident context. One frame contains 1,024 BF16 A values and 1,024 BF16 B values for BM32/BN32/BK32. The stager computes global row-major addresses, obtains actual sector-return values through one resident loader/cache, and offers 64 groups of 32 halfwords to the external shared writer. A frame completes only after all 64 write handshakes; accepting load requests alone is insufficient.

| Interface | Contract |
|---|---|
| Frame request | Context/ID, A/B bases, block row/column and reduction-stage index, all 32 bits; captured on acceptance |
| Frame availability | Per-context ready mask and outstanding count; one frame per context |
| Shared vector write | Context, 32 byte addresses, 32 halfwords, full active mask and valid/ready; actual writer acceptance consumes the loader response |
| Frame completion | Retained context/ID; held until acknowledged after all 2,048 values commit |
| Backing input | ID-matched 256-bit sector returns via one resident loader and one shared cache |

For the A half, a group’s flat halfword index determines the output-block row and current reduction column. For the B half, it determines reduction row and output-block column. The global strides are K for A and N for B. Bases must be even; complete allocations must fit 32-bit byte addressing. Block coordinates and stage index must remain within complete 32-element tiles. Shared destinations are byte offsets 0–4,094, with adjacent low/high halfwords kept distinct.

Each context retains bases, coordinates, stage index, group position and an epoch. IDLE accepts a frame, SEND offers its next load group, WAIT_VALUES holds the returned values until the shared write is accepted, and DONE holds frame completion. Separate registered request and completion owners provide round-robin arbitration and stable payloads under backpressure. The loader’s response is not acknowledged until the actual shared writer accepts it. Group/epoch/context matching rejects an unrelated return. Default two-context geometry uses seven local tag bits and 25 epoch bits; wrap requires reset. Reset cancels all contexts/loader work and requires the provider to flush old packets. Cached inputs must remain immutable until reset.

The [staging receipt](numerical/resident_operand_staging_verification.json) checks 4,096 committed halfwords for two different block/stage coordinates. It verifies captured request metadata, held shared payloads, delayed packets, all-word completion, another context progressing while a done response is held, reset and zero final outstanding work. This test uses checked shared-write sinks; it does not by itself establish matrix results. Serial per-context groups, arbitration and shared vector commits remain model choices.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_resident_operand_staging.py`.

**Inline behavior.**

```systemverilog
// Fixed BM32/BN32/BK32 operand frames. Global row-major u16 values reach
// context-local shared memory only through actual cache returns and vector commits.
// RR requests, blocking cache and serial per-context groups are hypotheses.
module resident_operand_staging #(
 parameter int CONTEXTS=2,M=64,N=96,K=64,SETS=64,WAYS=8
)(
 input logic clk,rst,req_valid,output logic req_ready,
 input logic[31:0]req_context,req_id,a_base,b_base,cta_row,cta_col,stage_index,
 output logic[CONTEXTS-1:0]context_ready,output int outstanding,
 output logic write_warp_valid,input logic write_warp_ready,
 output logic[31:0]write_context,write_warp_byte_addresses[32],write_warp_mask,
 output logic[15:0]write_warp_halfwords[32],
 output logic done_valid,input logic done_ready,output logic[31:0]done_context,done_id,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data
);
 localparam int LOCAL_BITS=$clog2(CONTEXTS*64),EPOCH_BITS=32-LOCAL_BITS;
 typedef enum logic[1:0]{IDLE,SEND,WAIT_VALUES,DONE}state_t;
 state_t state[CONTEXTS];
 logic[EPOCH_BITS-1:0]epoch[CONTEXTS];
 logic[31:0]ids[CONTEXTS],abase[CONTEXTS],bbase[CONTEXTS],rows[CONTEXTS],cols[CONTEXTS],stages[CONTEXTS];
 int group_index[CONTEXTS],request_owner,request_cursor,done_owner,done_cursor;
 logic request_legal;
 logic load_req_valid,load_req_ready,load_rsp_valid,load_rsp_ready;
 logic[31:0]load_req_context,load_req_id,load_addresses[32],load_rsp_context,load_rsp_id;
 logic[15:0]load_halfwords[32];logic[CONTEXTS-1:0]load_context_ready;
 int load_outstanding,load_sector_count;
 function automatic logic[31:0]tag(input int ctx);
  return (32'(epoch[ctx])<<LOCAL_BITS)|32'(ctx*64+group_index[ctx]);
 endfunction
 function automatic logic[31:0]global_address(input int ctx,lane);
  longint unsigned h,r,c,index_value;
  h=64'(group_index[ctx]*32+lane);
  if(h<1024)begin
   r=64'(rows[ctx])*32+h/32;c=64'(stages[ctx])*32+h%32;
   index_value=64'(abase[ctx])+2*(r*64'(K)+c);
  end else begin
   h-=1024;r=64'(stages[ctx])*32+h/32;c=64'(cols[ctx])*32+h%32;
   index_value=64'(bbase[ctx])+2*(r*64'(N)+c);
  end
  return 32'(index_value);
 endfunction
 initial if(CONTEXTS<1||EPOCH_BITS<1||M<32||N<32||K<32||M%32||N%32||K%32)$fatal(1,"Only complete BM32/BN32/BK32 frames supported");
 always_comb begin
  request_legal=req_context<CONTEXTS&&cta_row<M/32&&cta_col<N/32&&stage_index<K/32&&!a_base[0]&&!b_base[0];
  if(64'(a_base)+2*64'(M)*64'(K)>64'h100000000||64'(b_base)+2*64'(K)*64'(N)>64'h100000000)request_legal=0;
  outstanding=0;
  for(int ctx=0;ctx<CONTEXTS;ctx++)begin
   context_ready[ctx]=!rst&&state[ctx]==IDLE;
   if(state[ctx]!=IDLE)outstanding++;
  end
 end
 assign req_ready=!rst&&request_legal&&(req_context<CONTEXTS?context_ready[req_context]:0);
 assign load_req_valid=!rst&&request_owner>=0;
 assign load_req_context=request_owner>=0?32'(request_owner):0;
 assign load_req_id=request_owner>=0?tag(request_owner):0;
 always_comb for(int lane=0;lane<32;lane++)load_addresses[lane]=request_owner>=0?global_address(request_owner,lane):0;
 // A loader response stays held until the external shared-vector writer accepts.
 assign write_warp_valid=!rst&&load_rsp_valid;
 assign load_rsp_ready=!rst&&write_warp_ready;
 assign write_context=load_rsp_context;
 assign write_warp_mask='1;
 always_comb begin
  for(int lane=0;lane<32;lane++)begin
   write_warp_halfwords[lane]=load_halfwords[lane];
   write_warp_byte_addresses[lane]=load_rsp_context<CONTEXTS?32'(2*(group_index[load_rsp_context]*32+lane)):0;
  end
 end
 assign done_valid=!rst&&done_owner>=0;
 assign done_context=done_owner>=0?32'(done_owner):0;
 assign done_id=done_owner>=0?ids[done_owner]:0;
 always_ff @(posedge clk)begin
  if(rst)begin
   request_owner<=-1;request_cursor<=0;done_owner<=-1;done_cursor<=0;
   for(int ctx=0;ctx<CONTEXTS;ctx++)begin
    state[ctx]<=IDLE;epoch[ctx]<=0;ids[ctx]<=0;abase[ctx]<=0;bbase[ctx]<=0;rows[ctx]<=0;cols[ctx]<=0;stages[ctx]<=0;group_index[ctx]<=0;
   end
  end else begin
   if(req_valid&&!request_legal)$fatal(1,"Invalid resident operand frame");
   if(req_valid&&req_ready)begin
    if(&epoch[req_context])$fatal(1,"Staging epoch exhausted; reset required");
    epoch[req_context]<=epoch[req_context]+1;ids[req_context]<=req_id;
    abase[req_context]<=a_base;bbase[req_context]<=b_base;rows[req_context]<=cta_row;cols[req_context]<=cta_col;stages[req_context]<=stage_index;
    group_index[req_context]<=0;state[req_context]<=SEND;
   end
   if(request_owner<0)begin
    int choice;choice=-1;
    for(int offset=0;offset<CONTEXTS;offset++)begin
     int candidate;candidate=(request_cursor+offset)%CONTEXTS;
     if(choice<0&&state[candidate]==SEND&&load_context_ready[candidate])choice=candidate;
    end
    if(choice>=0)request_owner<=choice;
   end else if(load_req_valid&&load_req_ready)begin
    state[request_owner]<=WAIT_VALUES;request_cursor<=(request_owner+1)%CONTEXTS;request_owner<=-1;
   end
   if(load_rsp_valid)begin
    if(load_rsp_context>=CONTEXTS)$fatal(1,"Staging return context outside capacity");
    else if(state[load_rsp_context]!=WAIT_VALUES||load_rsp_id!=tag(int'(load_rsp_context)))$fatal(1,"Staging return without matching frame/group");
   end
   if(load_rsp_valid&&load_rsp_ready)begin
    if(group_index[load_rsp_context]==63)state[load_rsp_context]<=DONE;
    else begin group_index[load_rsp_context]<=group_index[load_rsp_context]+1;state[load_rsp_context]<=SEND;end
   end
   if(done_owner<0)begin
    int choice;choice=-1;
    for(int offset=0;offset<CONTEXTS;offset++)begin
     int candidate;candidate=(done_cursor+offset)%CONTEXTS;
     if(choice<0&&state[candidate]==DONE)choice=candidate;
    end
    if(choice>=0)done_owner<=choice;
   end else if(done_valid&&done_ready)begin
    state[done_owner]<=IDLE;done_cursor<=(done_owner+1)%CONTEXTS;done_owner<=-1;
   end
  end
 end
 resident_u16_warp_load #(.CONTEXTS(CONTEXTS),.SETS(SETS),.WAYS(WAYS)) loader(
  .clk,.rst,.req_valid(load_req_valid),.req_ready(load_req_ready),.req_context(load_req_context),.req_id(load_req_id),
  .byte_addresses(load_addresses),.active_mask(32'hffffffff),.context_ready(load_context_ready),.outstanding(load_outstanding),
  .rsp_valid(load_rsp_valid),.rsp_ready(load_rsp_ready),.rsp_context(load_rsp_context),.rsp_id(load_rsp_id),.halfwords(load_halfwords),.sector_count(load_sector_count),
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,.backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data
 );
 // Exactly64 accepted32-halfword commits per frame. Provider flushes reset-era
 // transactions; immutable backing data/cache-reset contract inherited from loader.
endmodule
```

### 4.47. Resident complete reductions from global data to register results

**Role and limit.** The [resident reduction controller](numerical/resident_gemm_reduction.sv) connects section 4.46’s actual global-to-shared frames to section 4.44’s shared native stage engine. Two resident contexts can retain different block coordinates, stage positions and accumulators while sharing **one input cache and one read/MOVM/HMMA service set**. Each context carries C through every 32-element stage of K. Its result is four fragments’ register values, not an acknowledged global output matrix. Output scratch, global stores and explicit CTA barrier generations are absent from this path.

| Interface or state | Contract |
|---|---|
| Launch | 32-bit ID, A/B bases and block coordinates; accepted into a free resource slot |
| Result | Context, retained ID and `[4][32][8]` FP32 registers; held until actual result acknowledgment |
| Backing input | Shared completion-driven sector request/return interface |
| Residency | Live block/warp counts; one context uses four warps and the 5,120-register-word/9,216-shared-byte request demand |
| Instruction trace | Actual selected native context/warp/instruction address across the shared engine |

Launch validation rejects odd A/B bases and input allocations extending beyond the 32-bit byte-address space before resource reservation. Admission reserves the context before staging begins and captures its metadata. Each context then progresses through STAGE_SEND, STAGE_WAIT, COMPUTE_SEND, COMPUTE_WAIT and RESULT. Registered round-robin staging/compute owners retain payloads while stalled. A staging completion must match the context and reduction-stage number; it permits compute admission only after actual shared commits. The engine snapshots that context’s carried C at acceptance. An ID-matched actual arithmetic response replaces C and either increments the stage or exposes the final register result.

The next frame in a context is not staged until its prior compute result has returned. This is a conservative whole-stage lifetime rule, not a recovered native barrier protocol. Another context can stage or compute meanwhile, subject to the same shared capacities and arbitration. Defaults are two contexts, M64/N96/K64, shared-read capacity two with return delay nine, MOVM delay/interval 19/1 and HMMA delay/interval 73/4. Those deliberately long service delays exercise ownership/readiness; they are not calibrated RTX latency estimates. K64 uses two stages; K1536 uses 48 per context.

A final result owner is latched and held until acknowledgment. The allocator remains live through all stages and a held result; the active-context count must equal live blocks, with four live warps per context. Result acknowledgment frees this **reduction** allocation. It must not be substituted for full-CTA retirement: the original kernel still owes output scratch, synchronization and acknowledged global stores. Reset cancels contexts, staging, engine and pending provider work; cached backing input is immutable until reset.

The [reduction receipt](numerical/resident_reduction_verification.json) checks 4,096 FP32 register values: two distinct 32 × 32 block coordinates at K64 and the same two contexts at K1536, using an independent complete integer-dot-product oracle. The current guarded version also rejects odd-base and allocation-overflow launches. The earlier positive-only receipt is retained in `numerical/failure_receipts/resident_reduction_launch_boundary_001`; it does not prove those admission boundaries. These checks connect returned global values, shared commits, measured operand transformations and all carried reduction stages. Held results and resource counts are checked for stability; this reduction test does not prove new issue progress during that hold. The separate stage-engine test in section 4.44 does prove another context completing while a result is held. They do not validate output-store completion, a complete concurrent grid, multiple SMs or hardware runtime. Physical evidence remains eight identified fields, 32 partial and 94 unknown; no field is closed by this integration.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_resident_gemm_reduction.py`.

**Inline behavior.**

```systemverilog
// Concurrent complete-reduction operand/compute path for native BM32/BN32.
// One shared input cache and one shared read/MOVM/HMMA service set.
// Results are registers only: output scratch, global stores and CTA barriers
// are not reconstructed here. Result acknowledgement is NOT full CTA retirement.
module resident_gemm_reduction #(
 parameter int CONTEXTS=2,M=64,N=96,K=64,SETS=64,WAYS=8,
 parameter int READ_SLOTS=2,RETURN_DELAY=9,MOVM_LATENCY=19,HMMA_LATENCY=73,
 parameter int SERVICE_INTERVAL=1,MOVM_INTERVAL=1,HMMA_INTERVAL=4,ARITHMETIC_MODE=1
)(
 input logic clk,rst,launch_valid,output logic launch_ready,
 input logic[31:0]launch_id,a_base,b_base,cta_row,cta_col,
 output logic done_valid,input logic done_ready,
 output logic[31:0]done_id,done_context,result_registers[4][32][8],
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data,
 output int resident_blocks,resident_warps,
 output logic native_issue_valid,output logic[31:0]native_issue_context,native_issue_warp,native_issue_pc
);
 localparam int STAGES=K/32;
 typedef enum logic[2:0]{IDLE,STAGE_SEND,STAGE_WAIT,COMPUTE_SEND,COMPUTE_WAIT,RESULT}state_t;
 state_t state[CONTEXTS];
 logic[31:0]ids[CONTEXTS],rows[CONTEXTS],cols[CONTEXTS],abase[CONTEXTS],bbase[CONTEXTS];
 logic[31:0]accumulators[CONTEXTS][4][32][8];
 int stage_number[CONTEXTS],stage_owner,stage_cursor,compute_owner,compute_cursor,result_owner,result_cursor;
 int admitted_slot,allocated_register_words,allocated_shared_bytes;
 logic allocator_ready,launch_legal,admit_fire,retire_fire;
 logic staging_valid,staging_ready,staging_done_valid,staging_done_ready;
 logic[31:0]staging_context,staging_id,staging_done_context,staging_done_id;
 logic[CONTEXTS-1:0]staging_context_ready;int staging_outstanding;
 logic write_warp_valid,write_warp_ready;logic[31:0]write_context,write_warp_byte_addresses[32],write_warp_mask;
 logic[15:0]write_warp_halfwords[32];
 logic compute_valid,compute_ready,compute_rsp_valid,compute_rsp_ready;
 logic[31:0]compute_context,compute_id,compute_rsp_context,compute_rsp_id;
 logic[31:0]compute_c[4][32][8],compute_result[4][32][8];
 logic[CONTEXTS-1:0]compute_context_ready,compute_context_initialized;
 logic[3:0]warp_drained[CONTEXTS],warp_memory_safe[CONTEXTS];
 logic initialized,legal;int compute_outstanding;
 initial if(CONTEXTS<1||M<32||N<32||K<32||M%32||N%32||K%32)$fatal(1,"Unsupported resident reduction geometry");
 assign launch_legal=({32'b0,cta_row}+64'd1)*64'd32<=64'(M)&&
                     ({32'b0,cta_col}+64'd1)*64'd32<=64'(N)&&
                     !a_base[0]&&!b_base[0]&&
                     {32'b0,a_base}+64'd2*64'(M)*64'(K)<=64'h100000000&&
                     {32'b0,b_base}+64'd2*64'(K)*64'(N)<=64'h100000000;
 assign launch_ready=!rst&&allocator_ready&&launch_legal;
 assign admit_fire=launch_valid&&launch_ready;
 assign done_valid=!rst&&result_owner>=0;
 assign done_context=result_owner>=0?32'(result_owner):0;
 assign done_id=result_owner>=0?ids[result_owner]:0;
 assign retire_fire=done_valid&&done_ready;
 always_comb begin
  for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)begin
   result_registers[w][l][e]=result_owner>=0?accumulators[result_owner][w][l][e]:0;
   compute_c[w][l][e]=compute_owner>=0?accumulators[compute_owner][w][l][e]:0;
  end
 end
 assign staging_valid=!rst&&stage_owner>=0;
 assign staging_context=stage_owner>=0?32'(stage_owner):0;
 assign staging_id=stage_owner>=0?32'(stage_number[stage_owner]):0;
 assign staging_done_ready=!rst&&staging_done_context<CONTEXTS&&
                           (staging_done_context<CONTEXTS?state[staging_done_context]==STAGE_WAIT:0);
 assign compute_valid=!rst&&compute_owner>=0;
 assign compute_context=compute_owner>=0?32'(compute_owner):0;
 assign compute_id=compute_owner>=0?32'(stage_number[compute_owner]):0;
 assign compute_rsp_ready=!rst&&compute_rsp_context<CONTEXTS&&
                         (compute_rsp_context<CONTEXTS?state[compute_rsp_context]==COMPUTE_WAIT:0);
 quantized_block_admission #(.BLOCK_SLOTS(CONTEXTS)) admission(
  .clk,.rst,.admit_valid(admit_fire),.block_threads(128),.registers_per_thread(40),
  .user_shared_bytes(8192),.reserved_shared_bytes(1024),.admit_ready(allocator_ready),
  .admitted_slot,.resident_blocks,.resident_warps,.allocated_register_words,.allocated_shared_bytes,
  .retire_valid(retire_fire),.retire_slot(result_owner)
 );
 always_ff @(posedge clk)begin
  if(rst)begin
   stage_owner<=-1;stage_cursor<=0;compute_owner<=-1;compute_cursor<=0;result_owner<=-1;result_cursor<=0;
   for(int c=0;c<CONTEXTS;c++)begin
    state[c]<=IDLE;ids[c]<=0;rows[c]<=0;cols[c]<=0;abase[c]<=0;bbase[c]<=0;stage_number[c]<=0;
    for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)accumulators[c][w][l][e]<=0;
   end
  end else begin
   integer active;active=0;for(int c=0;c<CONTEXTS;c++)if(state[c]!=IDLE)active++;
   if(active!=resident_blocks||resident_warps!=4*active)$fatal(1,"Reduction resource/context conservation failed");
   if(launch_valid&&!launch_legal)$fatal(1,"Invalid resident reduction launch geometry or input allocation");
   if(admit_fire)begin
    if(admitted_slot<0||admitted_slot>=CONTEXTS||state[admitted_slot]!=IDLE)$fatal(1,"Reduction slot admission mismatch");
    state[admitted_slot]<=STAGE_SEND;ids[admitted_slot]<=launch_id;rows[admitted_slot]<=cta_row;cols[admitted_slot]<=cta_col;
    abase[admitted_slot]<=a_base;bbase[admitted_slot]<=b_base;stage_number[admitted_slot]<=0;
    for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)accumulators[admitted_slot][w][l][e]<=0;
   end
   // Owners are registered before a request is offered; stalled payloads stay fixed.
   if(stage_owner<0)begin
    integer choice;choice=-1;
    for(int off=0;off<CONTEXTS;off++)begin integer c;c=(stage_cursor+off)%CONTEXTS;
     if(choice<0&&state[c]==STAGE_SEND)choice=c;
    end
    if(choice>=0)stage_owner<=choice;
   end else if(staging_valid&&staging_ready)begin
    state[stage_owner]<=STAGE_WAIT;stage_cursor<=(stage_owner+1)%CONTEXTS;stage_owner<=-1;
   end
   if(staging_done_valid)begin
    if(staging_done_context>=CONTEXTS)$fatal(1,"Unknown staging completion context");
    else if(state[staging_done_context]!=STAGE_WAIT||staging_done_id!=32'(stage_number[staging_done_context]))$fatal(1,"Staging completion ownership mismatch");
   end
   if(staging_done_valid&&staging_done_ready)state[staging_done_context]<=COMPUTE_SEND;
   if(compute_owner<0)begin
    integer choice;choice=-1;
    for(int off=0;off<CONTEXTS;off++)begin integer c;c=(compute_cursor+off)%CONTEXTS;
     if(choice<0&&state[c]==COMPUTE_SEND)choice=c;
    end
    if(choice>=0)compute_owner<=choice;
   end else if(compute_valid&&compute_ready)begin
    state[compute_owner]<=COMPUTE_WAIT;compute_cursor<=(compute_owner+1)%CONTEXTS;compute_owner<=-1;
   end
   if(compute_rsp_valid)begin
    if(compute_rsp_context>=CONTEXTS)$fatal(1,"Unknown compute completion context");
    else if(state[compute_rsp_context]!=COMPUTE_WAIT||compute_rsp_id!=32'(stage_number[compute_rsp_context]))$fatal(1,"Compute completion ownership mismatch");
   end
   if(compute_rsp_valid&&compute_rsp_ready)begin
    for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)accumulators[compute_rsp_context][w][l][e]<=compute_result[w][l][e];
    if(stage_number[compute_rsp_context]==STAGES-1)state[compute_rsp_context]<=RESULT;
    else begin stage_number[compute_rsp_context]<=stage_number[compute_rsp_context]+1;state[compute_rsp_context]<=STAGE_SEND;end
   end
   if(result_owner<0)begin
    integer choice;choice=-1;
    for(int off=0;off<CONTEXTS;off++)begin integer c;c=(result_cursor+off)%CONTEXTS;
     if(choice<0&&state[c]==RESULT)choice=c;
    end
    if(choice>=0)result_owner<=choice;
   end else if(retire_fire)begin
    state[result_owner]<=IDLE;result_cursor<=(result_owner+1)%CONTEXTS;result_owner<=-1;
   end
  end
 end
 resident_operand_staging #(.CONTEXTS(CONTEXTS),.M(M),.N(N),.K(K),.SETS(SETS),.WAYS(WAYS)) staging(
  .clk,.rst,.req_valid(staging_valid),.req_ready(staging_ready),.req_context(staging_context),.req_id(staging_id),
  .a_base(stage_owner>=0?abase[stage_owner]:0),.b_base(stage_owner>=0?bbase[stage_owner]:0),
  .cta_row(stage_owner>=0?rows[stage_owner]:0),.cta_col(stage_owner>=0?cols[stage_owner]:0),
  .stage_index(stage_owner>=0?32'(stage_number[stage_owner]):0),
  .context_ready(staging_context_ready),.outstanding(staging_outstanding),
  .write_warp_valid,.write_warp_ready,.write_context,.write_warp_byte_addresses,.write_warp_halfwords,.write_warp_mask,
  .done_valid(staging_done_valid),.done_ready(staging_done_ready),.done_context(staging_done_context),.done_id(staging_done_id),
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,
  .backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data
 );
 resident_native_stage_engine #(.CONTEXTS(CONTEXTS),.ALLOW_WARP_WRITES(1),.READ_SLOTS(READ_SLOTS),
  .SERVICE_INTERVAL(SERVICE_INTERVAL),.RETURN_DELAY(RETURN_DELAY),.MOVM_LATENCY(MOVM_LATENCY),.MOVM_INTERVAL(MOVM_INTERVAL),
  .HMMA_LATENCY(HMMA_LATENCY),.HMMA_INTERVAL(HMMA_INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) engine(
  .clk,.rst,.write_context,.write_valid(1'b0),.write_ready(),.write_byte_address(32'd0),.write_data(16'd0),
  .write_warp_valid,.write_warp_ready,.write_warp_byte_addresses,.write_warp_halfwords,.write_warp_mask,
  .req_valid(compute_valid),.req_ready(compute_ready),.req_context(compute_context),.req_id(compute_id),.c_registers(compute_c),
  .operands_initialized(initialized),.addresses_legal(legal),.context_ready(compute_context_ready),.context_initialized(compute_context_initialized),
  .rsp_valid(compute_rsp_valid),.rsp_ready(compute_rsp_ready),.rsp_context(compute_rsp_context),.rsp_id(compute_rsp_id),
  .result_registers(compute_result),.outstanding(compute_outstanding),.warp_drained,.warp_memory_safe,
  .native_issue_valid,.native_issue_context,.native_issue_warp,.native_issue_pc
 );
endmodule
```

### 4.48. One shared-read service for multiple clients

**Question and organization.** How can native operands and output-scratch reads compete for the same modeled read capacity? The [shared-read hub](components/shared_read_candidate_hub.sv) connects multiple clients to exactly one `warp_shared_read_service`. Each granted operation contains 32 aligned word addresses and 32 input words. The underlying service computes bank/broadcast work as described in section 4.31. Client identity is retained through actual result acknowledgment; adding clients does not add read-service instances.

| Interface or parameter | Contract |
|---|---|
| Candidate input | Per-client eligibility bit, 32-bit ID, 32 addresses and 32 input words |
| Grant output | At most one client selected per edge; means the common service actually accepted its values |
| Response | Per-client valid/ready, retained external ID and 32 returned words |
| Capacity | Defaults: two clients, four owner records and four common service slots |
| Service timing | Default package interval one and return delay one modeled cycle; both hypotheses |
| Counts | Global outstanding and per-client outstanding include responses held without acknowledgment |

Candidates are **previews**, not conventional stalled ready/valid offers. Before a grant, a client may change its preview or withdraw eligibility. Only the edge with `candidate_grant` snapshots the selected addresses and words and advances that client's instruction. This distinction lets arbitration examine several eligible operations without pretending they have already entered a queue.

The hub searches clients round-robin when a free owner record exists. Actual acceptance saves the client, its external ID and a monotonically increasing internal service ID; only then does the cursor advance. The internal ID routes the eventual response to its saved owner. A held FIFO-head response blocks later service returns. The owner record remains live until that client's response handshake. Equal external IDs in different clients are legal; reusing the same live ID within one client is rejected, including reuse on its retirement edge. Capacity checks use pre-edge state. Exhausting internal IDs requires reset; reset clears all owners and the common service.

The [hub receipt](numerical/shared_hub_verification.json) checks 256 returned words across synthetic capacities one and two. It checks changing ungranted previews, acceptance snapshots, equal IDs across clients, held responses, per-client/global conservation and reset cancellation; a duplicate live client ID is rejected. Round-robin arbitration, FIFO blocking and timing choices are implementation contracts, not discovered RTX scheduler or queue properties.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_shared_read_candidate_hub.py`.

**Inline behavior.**

```systemverilog
// Candidate previews are not ready/valid offers: only candidate_grant commits
// the selected values. One common scalar-warp read service snapshots each grant.
// RR issue, FIFO head blocking and one global return are simulation hypotheses.
module shared_read_candidate_hub #(
 parameter int CLIENTS=2,SLOTS=4,SERVICE_INTERVAL=1,RETURN_DELAY=1
)(
 input logic clk,rst,
 input logic[CLIENTS-1:0]candidate_valid,output logic[CLIENTS-1:0]candidate_grant,
 input logic[31:0]candidate_id[CLIENTS],byte_addresses[CLIENTS][32],input_words[CLIENTS][32],
 output logic[CLIENTS-1:0]rsp_valid,input logic[CLIENTS-1:0]rsp_ready,
 output logic[31:0]rsp_id[CLIENTS],output_words[CLIENTS][32],
 output int outstanding,client_outstanding[CLIENTS]
);
 logic live[SLOTS];int owner[SLOTS];logic[31:0]internal_ids[SLOTS],external_ids[SLOTS];
 logic[31:0]next_id;int cursor,selected,free_record,response_record;
 logic unit_req_valid,unit_req_ready,unit_rsp_valid,unit_rsp_ready;
 logic[31:0]unit_req_id,unit_rsp_id,unit_addresses[32],unit_inputs[32],unit_outputs[32];
 int unit_outstanding;
 initial if(CLIENTS<1||SLOTS<1)$fatal(1,"Invalid shared-read hub capacity");
 always_comb begin
  free_record=-1;outstanding=0;
  for(int client=0;client<CLIENTS;client++)client_outstanding[client]=0;
  for(int slot=0;slot<SLOTS;slot++)begin
   if(live[slot])begin outstanding++;client_outstanding[owner[slot]]++;end
   else if(free_record<0)free_record=slot;
  end
 end
 always_comb begin
  selected=-1;
  for(int offset=0;offset<CLIENTS;offset++)begin
   int client;client=(cursor+offset)%CLIENTS;
   if(!rst&&free_record>=0&&selected<0&&candidate_valid[client])selected=client;
  end
  for(int lane=0;lane<32;lane++)begin
   unit_addresses[lane]=selected>=0?byte_addresses[selected][lane]:0;
   unit_inputs[lane]=selected>=0?input_words[selected][lane]:0;
  end
 end
 assign unit_req_valid=!rst&&selected>=0;
 assign unit_req_id=next_id;
 always_comb begin
  candidate_grant='0;
  if(unit_req_valid&&unit_req_ready)candidate_grant[selected]=1;
 end
 always_comb begin
  response_record=-1;
  for(int slot=0;slot<SLOTS;slot++)if(live[slot]&&internal_ids[slot]==unit_rsp_id)response_record=slot;
  rsp_valid='0;
  for(int client=0;client<CLIENTS;client++)begin
   rsp_id[client]=0;
   for(int lane=0;lane<32;lane++)output_words[client][lane]=0;
  end
  if(!rst&&unit_rsp_valid&&response_record>=0)begin
   rsp_valid[owner[response_record]]=1;
   rsp_id[owner[response_record]]=external_ids[response_record];
   for(int lane=0;lane<32;lane++)output_words[owner[response_record]][lane]=unit_outputs[lane];

  end
 end
 always_comb begin
  unit_rsp_ready=0;
  if(!rst&&unit_rsp_valid&&response_record>=0)unit_rsp_ready=rsp_ready[owner[response_record]];
 end
 always_ff @(posedge clk)begin
  if(rst)begin
   next_id<=0;cursor<=0;
   for(int slot=0;slot<SLOTS;slot++)begin live[slot]<=0;owner[slot]<=0;internal_ids[slot]<=0;external_ids[slot]<=0;end
  end else begin
   if(outstanding!=unit_outstanding)$fatal(1,"Shared-read owner/service conservation failed");
   if(unit_rsp_valid&&response_record<0)$fatal(1,"Shared-read completion has no owner");
   if(unit_rsp_valid&&unit_rsp_ready)live[response_record]<=0;
   if(unit_req_valid&&unit_req_ready)begin
    if(free_record<0)$fatal(1,"Shared-read grant lacks owner capacity");
    if(&next_id)$fatal(1,"Shared-read service ID exhausted; reset required");
    for(int slot=0;slot<SLOTS;slot++)if(live[slot]&&owner[slot]==selected&&external_ids[slot]==candidate_id[selected])
     $fatal(1,"Duplicate in-flight shared-read client ID");
    live[free_record]<=1;owner[free_record]<=selected;internal_ids[free_record]<=next_id;external_ids[free_record]<=candidate_id[selected];
    next_id<=next_id+1;cursor<=(selected+1)%CLIENTS;
   end
  end
 end
 warp_shared_read_service #(.SLOTS(SLOTS),.SERVICE_INTERVAL(SERVICE_INTERVAL),.RETURN_DELAY(RETURN_DELAY)) service(
  .clk,.rst,.req_valid(unit_req_valid),.req_ready(unit_req_ready),.req_id(unit_req_id),.byte_addresses(unit_addresses),.input_words(unit_inputs),
  .rsp_valid(unit_rsp_valid),.rsp_ready(unit_rsp_ready),.rsp_id(unit_rsp_id),.output_words(unit_outputs),.outstanding(unit_outstanding),.request_packages()
 );
 // Owner records live through response acknowledgment. Equal IDs across clients
 // are legal; same-client reuse on a retirement edge is conservatively rejected.
 // Reset discards every outstanding request and resets the shared service.
endmodule
```

### 4.49. Resident native stages with externally shared reads

**Role.** The [shared native engine](numerical/resident_native_stage_shared.sv) retains the resident execution state from section 4.44 but removes its private shared-read unit. Its native operand reads use section 4.48's candidate/grant interface. One MOVM service and one HMMA service remain inside the engine. With two contexts and four warps per context, eight independent instruction positions share these services; this is a bounded stage model, not a complete concurrent kernel.

| Interface or state | Contract |
|---|---|
| Read preview | One eligible native read ID, 32 byte addresses and 32 current operand words |
| Read grant | Actual common-service acceptance; advances instruction state and allocates pending ownership |
| Read return | ID and 32 words; acknowledgment updates the owning operand registers and readiness |
| Read accounting | `read_client_outstanding` is this engine's hub-client count, not the hub's total across clients |
| Context storage | 4,096 operand bytes per context; separate A/B registers, accumulators, readiness and instruction positions |
| Admission/result | Context and 32-bit operation ID; `[4][32][8]` FP32 register results held until acknowledgment |
| Other services | Defaults: four MOVM slots at delay/interval 1/1; two HMMA slots at 16/4 |
| Local read limit | Default `READ_SLOTS = 4`; this is an engine credit limit, not an additional physical read queue |

Only a granted read produces an accepted-operation record. Completion decodes context, warp, instruction and epoch, rejects stale or unexpected ownership, and updates that operation's actual values. The engine checks that accepted minus retired read credits equal its hub-client count. It also checks per-warp pending counts against the read, MOVM and HMMA service totals. Native register dependencies and decoded instruction controls remain active. Completion arbitration gives read returns priority over MOVM and HMMA, allowing one selected completion to update values and barrier bookkeeping per edge. Ungranted read previews can change as another eligible instruction becomes selected; no operand or instruction state advances merely because a preview was visible.

Scalar and optional vector writes initialize idle context storage. Native reads sample their operand values on actual grant. Registered response ownership keeps a held context result stable while another context can finish. Memory-safe indications remain distinct from complete register/service drain. Reset cancels contexts and pending services; external shared clients must reset consistently with the hub. Epoch tags guard context reuse within the declared bounded instruction window. Address generation outside that window, full CTA barriers, output stores and allocation through complete kernel retirement remain outside this component.

The [shared-engine receipt](numerical/resident_shared_stage_verification.json) verifies 8,192 native result words with distinct dyadic inputs and nonzero accumulators across read capacities one and two. It also checks 256 words from a synthetic scratch client using the **same hub service**. The connected tests check context interleaving, another context finishing while a result is held, retained resource allocations, matching retirement and reset/refill. The scratch client is a test participant; this receipt does not validate the separately developed output-scratch component or a complete kernel connecting it. No physical parameter is closed: eight fields remain identified, 32 partial and 94 unknown. All delay, arbitration and credit settings remain uncalibrated model choices.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_resident_native_stage_shared.py`.

**Inline behavior.**

```systemverilog
// Resident native stages with external candidate/grant read service sharing.
// Private MOVM/HMMA services remain single instances; reads belong to the hub.
// Epoch tags isolate reused context windows. Global RR and timing remain hypotheses.
// Round-robin ONE global issue port and read>move>matrix return priority are
// simulation hypotheses, not RTX5090 scheduler topology or bandwidth facts.
// Address ALU is control-only; offsets precomputed, entry barrier assumed.
module resident_native_stage_shared #(
 parameter int CONTEXTS=2,
 parameter int WARPS=4,parameter bit ALLOW_WARP_WRITES=0,
 parameter int READ_SLOTS=4,SERVICE_INTERVAL=1,RETURN_DELAY=1,
 parameter int MOVM_SLOTS=4,MOVM_LATENCY=1,MOVM_INTERVAL=1,
 parameter int HMMA_SLOTS=2,HMMA_LATENCY=16,HMMA_INTERVAL=4,ARITHMETIC_MODE=1
)(
 input logic clk,rst,
 output logic read_candidate_valid,input logic read_candidate_grant,
 output logic[31:0]read_candidate_id,read_candidate_byte_addresses[32],read_candidate_input_words[32],
 input logic read_rsp_valid,output logic read_rsp_ready,
 input logic[31:0]read_rsp_id,read_rsp_words[32],input int read_client_outstanding,
 input logic[31:0]write_context,
 input logic write_valid,output logic write_ready,
 input logic[31:0]write_byte_address,input logic[15:0]write_data,
 input logic write_warp_valid,output logic write_warp_ready,
 input logic[31:0]write_warp_byte_addresses[32],
 input logic[15:0]write_warp_halfwords[32],input logic[31:0]write_warp_mask,
 input logic req_valid,output logic req_ready,input logic[31:0]req_context,req_id,
 input logic[31:0]c_registers[WARPS][32][8],
 output logic operands_initialized,addresses_legal,
 output logic[CONTEXTS-1:0]context_ready,context_initialized,
 output logic rsp_valid,input logic rsp_ready,
 output logic[31:0]rsp_context,rsp_id,result_registers[WARPS][32][8],output int outstanding,
 output logic[WARPS-1:0] warp_drained[CONTEXTS],warp_memory_safe[CONTEXTS],
 output logic native_issue_valid,output logic[31:0]native_issue_context,native_issue_warp,native_issue_pc
);
 import native_studied_stage_schedule::*;
 localparam int HALFWORDS=2048,TOTAL_WARPS=CONTEXTS*WARPS;
 localparam int LOCAL_BITS=$clog2(TOTAL_WARPS*INSTRUCTIONS),EPOCH_BITS=32-LOCAL_BITS;
 logic[EPOCH_BITS-1:0]epoch[CONTEXTS];
 int response_owner,response_cursor;
 typedef enum logic[1:0]{IDLE,RUN,DRAIN,RESPONSE}state_t;state_t state[CONTEXTS];
 int read_live_perwarp[TOTAL_WARPS];
 int warp_service_live[TOTAL_WARPS];logic service_pending[TOTAL_WARPS][INSTRUCTIONS];
 int pc[TOTAL_WARPS],round_robin,selected,read_live_count;int read_locations[32];
 logic[31:0]saved_id[CONTEXTS];logic[15:0]memory[CONTEXTS][HALFWORDS];logic initialized[CONTEXTS][HALFWORDS];
 logic[31:0]a_words[TOTAL_WARPS][2][32][4],b_raw[TOTAL_WARPS][2][32][4],b_moved[TOTAL_WARPS][2][32][4],accumulator[TOTAL_WARPS][32][8];
 logic a_ready[TOTAL_WARPS][2][4],b_ready[TOTAL_WARPS][2][4],mov_ready[TOTAL_WARPS][2][4],c_ready[TOTAL_WARPS][2];
 descriptor_t desc[TOTAL_WARPS],chosen_desc,completion_desc;
 native_control_decode::control_t control[TOTAL_WARPS],completion_control;
 logic dependencies_ready[TOTAL_WARPS],gate_valid[TOTAL_WARPS],gate_ready[TOTAL_WARPS],dispatch_valid[TOTAL_WARPS],dispatch_ready[TOTAL_WARPS],issued[TOTAL_WARPS],gate_error[TOTAL_WARPS];
 logic[5:0]busy_write[TOTAL_WARPS],busy_read[TOTAL_WARPS];logic[3:0]cooldown[TOTAL_WARPS];
 logic read_req_valid,read_req_ready;
 logic[31:0]read_req_id,read_addresses[32],read_inputs[32];int read_outstanding;
 logic mov_req_valid,mov_req_ready,mov_rsp_valid,mov_rsp_ready;
 logic[31:0]mov_req_id,mov_rsp_id,mov_inputs[32],mov_outputs[32];int mov_outstanding;
 logic h_req_valid,h_req_ready,h_rsp_valid,h_rsp_ready;
 logic[31:0]h_req_id,h_rsp_id,h_a[32][4],h_b[32][2],h_c[32][4],h_results[32][4];int h_outstanding;
 logic completion_valid,write_legal,warp_write_legal,selected_issued;
 logic[31:0]completion_id;int completion_warp,completion_pc,completion_context;
 logic[EPOCH_BITS-1:0]completion_epoch;
 logic all_issued[CONTEXTS],all_drained[CONTEXTS];
 function automatic int address(input bit operand_b,input int kk,word_index,lane,tile);
  if(operand_b)return 2048+64*(16*kk+lane/4)+32*(tile%2)+4*(lane%4)+(word_index%2)*512+(word_index/2)*16;
  return 64*(16*(tile/2)+lane/4)+32*kk+4*(lane%4)+(word_index%2)*512+(word_index/2)*16;
 endfunction
 initial if(CONTEXTS<1||WARPS<1||WARPS>4||EPOCH_BITS<1)$fatal(1,"Native stage supports one through four warps");
 assign write_legal=write_context<CONTEXTS&&write_byte_address[0]==0&&write_byte_address<=4094;
 assign write_ready=!rst&&write_legal&&(write_context<CONTEXTS?state[write_context]==IDLE:0)&&!read_req_valid;
 always_comb begin
  warp_write_legal=write_context<CONTEXTS;
  if(ALLOW_WARP_WRITES)for(int lane=0;lane<32;lane++)if(write_warp_mask[lane])begin
   if(write_warp_byte_addresses[lane][0]!=0||write_warp_byte_addresses[lane]>4094)warp_write_legal=0;
   for(int other=0;other<lane;other++)if(write_warp_mask[other]&&write_warp_byte_addresses[lane]==write_warp_byte_addresses[other])warp_write_legal=0;
  end
 end
 assign write_warp_ready=ALLOW_WARP_WRITES&&!rst&&warp_write_legal&&(write_context<CONTEXTS?state[write_context]==IDLE:0)&&!write_valid&&!read_req_valid;
 assign addresses_legal=req_context<CONTEXTS;
 assign req_ready=!rst&&(addresses_legal?context_ready[req_context]:0);
 assign operands_initialized=addresses_legal?context_initialized[req_context]:0;
 assign rsp_valid=!rst&&response_owner>=0;
 assign rsp_context=response_owner>=0?32'(response_owner):0;
 assign rsp_id=response_owner>=0?saved_id[response_owner]:0;
 always_comb begin
  outstanding=0;
  for(int ctx=0;ctx<CONTEXTS;ctx++)begin
   context_initialized[ctx]=1;
   for(int warp=0;warp<WARPS;warp++)for(int kk=0;kk<2;kk++)for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)
    context_initialized[ctx]=context_initialized[ctx]&&initialized[ctx][address(0,kk,word,lane,warp)/2]&&initialized[ctx][address(0,kk,word,lane,warp)/2+1]&&initialized[ctx][address(1,kk,word,lane,warp)/2]&&initialized[ctx][address(1,kk,word,lane,warp)/2+1];
   context_ready[ctx]=!rst&&state[ctx]==IDLE&&context_initialized[ctx];
   if(state[ctx]!=IDLE)outstanding++;
  end
  for(int warp=0;warp<WARPS;warp++)for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)
   result_registers[warp][lane][word]=response_owner>=0?accumulator[response_owner*WARPS+warp][lane][word]:0;
 end
 always_comb begin
  for(int warp=0;warp<TOTAL_WARPS;warp++)begin
   desc[warp]='0;if(pc[warp]<INSTRUCTIONS)desc[warp]=descriptor(pc[warp]);
   control[warp]=native_control_decode::decode(desc[warp].raw);
   dependencies_ready[warp]=1;
   if(desc[warp].kind==2)dependencies_ready[warp]=b_ready[warp][desc[warp].kk][desc[warp].word_index];
   if(desc[warp].kind==3)begin
    dependencies_ready[warp]=c_ready[warp][desc[warp].upper_half];
    for(int word=0;word<4;word++)dependencies_ready[warp]=dependencies_ready[warp]&&a_ready[warp][desc[warp].kk][word];
    for(int word=0;word<2;word++)dependencies_ready[warp]=dependencies_ready[warp]&&mov_ready[warp][desc[warp].kk][2*int'(desc[warp].upper_half)+word];
   end
   gate_valid[warp]=!rst&&state[warp/WARPS]==RUN&&pc[warp]<INSTRUCTIONS&&dependencies_ready[warp];
  end
 end
 always_comb begin
  for(int ctx=0;ctx<CONTEXTS;ctx++)begin
   all_issued[ctx]=1;all_drained[ctx]=1;
   for(int localwarp=0;localwarp<WARPS;localwarp++)begin
    int warp;warp=ctx*WARPS+localwarp;
    if(pc[warp]!=INSTRUCTIONS)all_issued[ctx]=0;
    if(pc[warp]!=INSTRUCTIONS||busy_write[warp]!=0||busy_read[warp]!=0||cooldown[warp]!=0||!c_ready[warp][0]||!c_ready[warp][1]||warp_service_live[warp]!=0)all_drained[ctx]=0;
   end
  end
 end
 always_comb begin
  selected=-1;
  for(int offset=0;offset<TOTAL_WARPS;offset++)begin
   int candidate;candidate=(round_robin+offset)%TOTAL_WARPS;
   if(selected<0&&dispatch_valid[candidate])begin
    case(desc[candidate].kind)
     // All precomputed load addresses are aligned; capacity is readiness here.
     1:if(read_live_count<READ_SLOTS)selected=candidate;
     2:if(mov_req_ready)selected=candidate;
     3:if(h_req_ready)selected=candidate;
     default:selected=candidate;
    endcase
   end
  end
  chosen_desc='0;if(selected>=0)chosen_desc=desc[selected];
 end
 always_comb begin
  for(int warp=0;warp<TOTAL_WARPS;warp++)begin
   dispatch_ready[warp]=0;
   if(selected==warp)begin
    case(desc[warp].kind)
     1:dispatch_ready[warp]=read_req_ready;
     2:dispatch_ready[warp]=mov_req_ready;
     3:dispatch_ready[warp]=h_req_ready;
     default:dispatch_ready[warp]=1;
    endcase
   end
  end
 end
 always_comb begin
  selected_issued=0;
  for(int warp=0;warp<TOTAL_WARPS;warp++)if(issued[warp])selected_issued=1;
 end
 always_comb begin
  read_req_valid=0;mov_req_valid=0;h_req_valid=0;
  mov_req_id=0;h_req_id=0;
  native_issue_valid=selected_issued;native_issue_context=0;native_issue_warp=0;native_issue_pc=0;
  if(selected>=0)begin
   native_issue_context=32'(selected/WARPS);native_issue_warp=32'(selected%WARPS);native_issue_pc=32'h1350+32'(16*pc[selected]);
   mov_req_id=read_req_id;h_req_id=read_req_id;
   read_req_valid=issued[selected]&&chosen_desc.kind==1;
   mov_req_valid=issued[selected]&&chosen_desc.kind==2;
   h_req_valid=issued[selected]&&chosen_desc.kind==3;
  end
 end
 always_comb begin
  for(int lane=0;lane<32;lane++)begin
   read_locations[lane]=0;
   read_addresses[lane]=0;read_inputs[lane]=0;mov_inputs[lane]=0;
   for(int word=0;word<4;word++)begin h_a[lane][word]=0;h_c[lane][word]=0;end
   for(int word=0;word<2;word++)h_b[lane][word]=0;
   if(selected>=0)begin
    read_locations[lane]=address(chosen_desc.operand_b,int'(chosen_desc.kk),int'(chosen_desc.word_index),lane,selected%WARPS);
    read_addresses[lane]=32'(read_locations[lane]);read_inputs[lane]={memory[selected/WARPS][read_locations[lane]/2+1],memory[selected/WARPS][read_locations[lane]/2]};
    mov_inputs[lane]=b_raw[selected][chosen_desc.kk][lane][chosen_desc.word_index];
    for(int word=0;word<4;word++)begin h_a[lane][word]=a_words[selected][chosen_desc.kk][lane][word];h_c[lane][word]=accumulator[selected][lane][4*int'(chosen_desc.upper_half)+word];end
    for(int word=0;word<2;word++)h_b[lane][word]=b_moved[selected][chosen_desc.kk][lane][2*int'(chosen_desc.upper_half)+word];
   end
  end
 end
 assign read_rsp_ready=!rst;
 always_comb begin
  mov_rsp_ready=read_rsp_ready&&!read_rsp_valid;
  h_rsp_ready=mov_rsp_ready&&!mov_rsp_valid;
  completion_valid=(read_rsp_valid&&read_rsp_ready)||(mov_rsp_valid&&mov_rsp_ready)||(h_rsp_valid&&h_rsp_ready);
  completion_id=read_rsp_valid?read_rsp_id:(mov_rsp_valid?mov_rsp_id:h_rsp_id);
  completion_warp=int'(completion_id & ((32'b1<<LOCAL_BITS)-1))/INSTRUCTIONS;completion_pc=int'(completion_id & ((32'b1<<LOCAL_BITS)-1))%INSTRUCTIONS;
  completion_context=completion_warp/WARPS;completion_epoch=EPOCH_BITS'(completion_id>>LOCAL_BITS);
  completion_desc='0;if(completion_valid&&completion_warp<TOTAL_WARPS)completion_desc=descriptor(completion_pc);
  completion_control=native_control_decode::decode(completion_desc.raw);
 end
 always_ff @(posedge clk)begin
  if(rst)begin
   response_owner<=-1;response_cursor<=0;round_robin<=0;read_live_count<=0;
   for(int ctx=0;ctx<CONTEXTS;ctx++)begin state[ctx]<=IDLE;saved_id[ctx]<=0;epoch[ctx]<=0;warp_drained[ctx]<='0;warp_memory_safe[ctx]<='0;for(int i=0;i<HALFWORDS;i++)initialized[ctx][i]<=0;end
   for(int warp=0;warp<TOTAL_WARPS;warp++)begin
    read_live_perwarp[warp]<=0;warp_service_live[warp]<=0;for(int op=0;op<INSTRUCTIONS;op++)service_pending[warp][op]<=0;
    pc[warp]<=0;for(int kk=0;kk<2;kk++)for(int word=0;word<4;word++)begin a_ready[warp][kk][word]<=0;b_ready[warp][kk][word]<=0;mov_ready[warp][kk][word]<=0;end
    for(int half=0;half<2;half++)c_ready[warp][half]<=0;
    for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)accumulator[warp][lane][word]<=0;
   end
  end else begin
   // Memory reuse safety is separate from register-only service drain.
   // This bounded-window signal does not replay the following native BAR PCs.
   begin
    integer total_reads;total_reads=0;
    for(int warp=0;warp<TOTAL_WARPS;warp++)begin
     bit accepted_read,retired_read;integer delta;
     accepted_read=read_req_valid&&read_req_ready&&int'(read_req_id & ((32'b1<<LOCAL_BITS)-1))/INSTRUCTIONS==warp;
     retired_read=read_rsp_valid&&read_rsp_ready&&int'(read_rsp_id & ((32'b1<<LOCAL_BITS)-1))/INSTRUCTIONS==warp;
     delta=int'(accepted_read)-int'(retired_read);
     total_reads+=read_live_perwarp[warp];
     if(read_live_perwarp[warp]<0||read_live_perwarp[warp]>READ_SLOTS)$fatal(1,"Per-warp shared-read liveness out of bounds");
     if(retired_read&&read_live_perwarp[warp]==0)$fatal(1,"Shared-read completion lacks warp credit");
     read_live_perwarp[warp]<=read_live_perwarp[warp]+delta;
     if((state[warp/WARPS]==RUN||state[warp/WARPS]==DRAIN)&&pc[warp]==INSTRUCTIONS&&cooldown[warp]==0&&read_live_perwarp[warp]==0)
      warp_memory_safe[warp/WARPS][warp%WARPS]<=1;
     if(warp_memory_safe[warp/WARPS][warp%WARPS]&&(state[warp/WARPS]==RUN||state[warp/WARPS]==DRAIN||state[warp/WARPS]==RESPONSE)&&read_live_perwarp[warp]!=0)$fatal(1,"Memory-safe warp retains pending shared read");
    end
    if(total_reads!=read_outstanding)$fatal(1,"Per-warp shared-read conservation failed");
   end
   // Per-warp liveness follows accepted service operations and actual retired
   // responses. Decoded barrier bits alone do not cover every pending operation.
   begin
    integer total_live;total_live=0;
    for(int warp=0;warp<TOTAL_WARPS;warp++)begin
     integer delta;bit accepted,retired;delta=0;
     accepted=(read_req_valid&&read_req_ready&&int'(read_req_id & ((32'b1<<LOCAL_BITS)-1))/INSTRUCTIONS==warp)||
              (mov_req_valid&&mov_req_ready&&int'(mov_req_id & ((32'b1<<LOCAL_BITS)-1))/INSTRUCTIONS==warp)||
              (h_req_valid&&h_req_ready&&int'(h_req_id & ((32'b1<<LOCAL_BITS)-1))/INSTRUCTIONS==warp);
     retired=completion_valid&&completion_warp==warp;
     total_live+=warp_service_live[warp];
     if(warp_service_live[warp]<0||warp_service_live[warp]>READ_SLOTS+MOVM_SLOTS+HMMA_SLOTS)$fatal(1,"Warp service liveness out of bounds");
     if(accepted)begin
      if(pc[warp]>=INSTRUCTIONS||service_pending[warp][pc[warp]])$fatal(1,"Duplicate/out-of-range warp service acceptance");
      service_pending[warp][pc[warp]]<=1;delta++;
     end
     if(retired)begin
      if(!service_pending[warp][completion_pc]||warp_service_live[warp]==0)$fatal(1,"Warp completion without accepted operation");
      service_pending[warp][completion_pc]<=0;delta--;
     end
     warp_service_live[warp]<=warp_service_live[warp]+delta;
     if((state[warp/WARPS]==RUN||state[warp/WARPS]==DRAIN)&&pc[warp]==INSTRUCTIONS&&busy_read[warp]==0&&busy_write[warp]==0&&cooldown[warp]==0&&c_ready[warp][0]&&c_ready[warp][1]&&warp_service_live[warp]==0)
      warp_drained[warp/WARPS][warp%WARPS]<=1;
     if(warp_drained[warp/WARPS][warp%WARPS]&&(state[warp/WARPS]==RUN||state[warp/WARPS]==DRAIN||state[warp/WARPS]==RESPONSE)&&warp_service_live[warp]!=0)$fatal(1,"Drained warp retains pending service");
     if(state[warp/WARPS]==RESPONSE&&warp_service_live[warp]!=0)$fatal(1,"Batch response retains warp service");
    end
    if(total_live!=read_outstanding+mov_outstanding+h_outstanding)$fatal(1,"Per-warp/global service conservation failed");
   end
   // Local admission credits are exact transfer counts, not capacity estimates.
   if(read_live_count!=read_outstanding)$fatal(1,"Shared read credit conservation failed");
   if(read_req_valid&&!read_req_ready)$fatal(1,"Granted read lacks actual service readiness");
   if(read_candidate_grant&&!read_candidate_valid)$fatal(1,"Read grant lacks eligible preview");
   if(read_candidate_grant!=read_req_valid)$fatal(1,"Read grant/issued transfer mismatch");
   case({read_req_valid&&read_req_ready,read_rsp_valid&&read_rsp_ready})
    2'b10:read_live_count<=read_live_count+1;
    2'b01:read_live_count<=read_live_count-1;
    default:read_live_count<=read_live_count;
   endcase
   if(write_valid&&!write_legal)$fatal(1,"Invalid multiwarp shared write");
   if(ALLOW_WARP_WRITES&&write_warp_valid&&!warp_write_legal)$fatal(1,"Invalid multiwarp vector write");
   for(int warp=0;warp<TOTAL_WARPS;warp++)if(gate_error[warp])$fatal(1,"Multiwarp barrier error");
   if(write_valid&&write_ready)begin memory[write_context][write_byte_address/2]<=write_data;initialized[write_context][write_byte_address/2]<=1;end
   if(ALLOW_WARP_WRITES&&write_warp_valid&&write_warp_ready)for(int lane=0;lane<32;lane++)if(write_warp_mask[lane])begin memory[write_context][write_warp_byte_addresses[lane]/2]<=write_warp_halfwords[lane];initialized[write_context][write_warp_byte_addresses[lane]/2]<=1;end
   if(completion_valid)begin
    if(completion_warp>=TOTAL_WARPS)$fatal(1,"Unknown resident completion ID");
    else if(completion_epoch!=epoch[completion_context]||state[completion_context]==IDLE||state[completion_context]==RESPONSE)$fatal(1,"Stale resident completion epoch");
   end
   if(read_rsp_valid&&read_rsp_ready)begin
    if(completion_desc.kind!=1)$fatal(1,"Wrong multiwarp read completion class");
    for(int lane=0;lane<32;lane++)begin
     if(completion_desc.operand_b)b_raw[completion_warp][completion_desc.kk][lane][completion_desc.word_index]<=read_rsp_words[lane];
     else a_words[completion_warp][completion_desc.kk][lane][completion_desc.word_index]<=read_rsp_words[lane];
    end
    if(completion_desc.operand_b)b_ready[completion_warp][completion_desc.kk][completion_desc.word_index]<=1;
    else a_ready[completion_warp][completion_desc.kk][completion_desc.word_index]<=1;
   end
   if(mov_rsp_valid&&mov_rsp_ready)begin
    if(completion_desc.kind!=2)$fatal(1,"Wrong multiwarp MOVM completion class");
    for(int lane=0;lane<32;lane++)b_moved[completion_warp][completion_desc.kk][lane][completion_desc.word_index]<=mov_outputs[lane];
    mov_ready[completion_warp][completion_desc.kk][completion_desc.word_index]<=1;
   end
   if(h_rsp_valid&&h_rsp_ready)begin
    if(completion_desc.kind!=3)$fatal(1,"Wrong multiwarp HMMA completion class");
    for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)accumulator[completion_warp][lane][4*int'(completion_desc.upper_half)+word]<=h_results[lane][word];
    c_ready[completion_warp][completion_desc.upper_half]<=1;
   end
   if(req_valid&&!addresses_legal)$fatal(1,"Invalid request context");
   for(int warp=0;warp<TOTAL_WARPS;warp++)if(issued[warp])begin
    pc[warp]<=pc[warp]+1;if(desc[warp].kind==3)c_ready[warp][desc[warp].upper_half]<=0;
    round_robin<=(warp+1)%TOTAL_WARPS;
   end
   for(int ctx=0;ctx<CONTEXTS;ctx++)begin
    case(state[ctx])
     IDLE:if(req_valid&&req_ready&&req_context==ctx)begin
      if(&epoch[ctx])$fatal(1,"Resident epoch exhausted; reset required");
      epoch[ctx]<=epoch[ctx]+1;state[ctx]<=RUN;saved_id[ctx]<=req_id;
      warp_drained[ctx]<='0;warp_memory_safe[ctx]<='0;
      for(int localwarp=0;localwarp<WARPS;localwarp++)begin
       int warp;warp=ctx*WARPS+localwarp;
       read_live_perwarp[warp]<=0;warp_service_live[warp]<=0;
       for(int op=0;op<INSTRUCTIONS;op++)service_pending[warp][op]<=0;
       pc[warp]<=0;
       for(int kk=0;kk<2;kk++)for(int word=0;word<4;word++)begin a_ready[warp][kk][word]<=0;b_ready[warp][kk][word]<=0;mov_ready[warp][kk][word]<=0;end
       for(int half=0;half<2;half++)c_ready[warp][half]<=1;
       for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)accumulator[warp][lane][word]<=c_registers[localwarp][lane][word];
      end
     end
     RUN:if(all_issued[ctx])state[ctx]<=DRAIN;
     DRAIN:if(all_drained[ctx])state[ctx]<=RESPONSE;
     RESPONSE:if(rsp_valid&&rsp_ready&&response_owner==ctx)state[ctx]<=IDLE;
     default:$fatal(1,"Invalid resident context state");
    endcase
   end
   if(response_owner<0)begin
    int choice;choice=-1;
    for(int offset=0;offset<CONTEXTS;offset++)begin
     int candidate;candidate=(response_cursor+offset)%CONTEXTS;
     if(choice<0&&state[candidate]==RESPONSE)choice=candidate;
    end
    if(choice>=0)response_owner<=choice;
   end else if(rsp_valid&&rsp_ready)begin response_cursor<=(response_owner+1)%CONTEXTS;response_owner<=-1;end

  end
 end
 for(genvar warp=0;warp<TOTAL_WARPS;warp++)begin:warps
  decoded_native_issue_gate #(.MAX_OPS(64),.TAG_W(7),.COUNT_W(7)) gate(
   .clk,.reset(rst||state[warp/WARPS]==IDLE),.instr_valid(gate_valid[warp]),.instr_ready(gate_ready[warp]),
   .operation_id(7'(pc[warp])),.control(control[warp]),.dispatch_valid(dispatch_valid[warp]),.dispatch_ready(dispatch_ready[warp]),.issued(issued[warp]),
   .write_complete_valid(completion_valid&&completion_warp==warp&&completion_control.write_barrier!=7),.write_complete_tag(7'(completion_pc)),
   .read_complete_valid(1'b0),.read_complete_tag(7'd0),.busy_write_mask(busy_write[warp]),.busy_read_mask(busy_read[warp]),.cooldown(cooldown[warp]),.error_sticky(gate_error[warp])
  );
 end
 // This is an eligible instruction preview, independent of dispatch grant.
 // A hub grant means its common read service accepted these exact values.
 assign read_candidate_valid=!rst&&selected>=0&&(selected>=0?dispatch_valid[selected]&&chosen_desc.kind==1:0);
 assign read_req_id=selected>=0?(32'(epoch[selected/WARPS])<<LOCAL_BITS)|32'(selected*INSTRUCTIONS+pc[selected]):0;
 assign read_candidate_id=read_req_id;
 assign read_req_ready=read_candidate_grant;
 assign read_outstanding=read_client_outstanding;
 for(genvar lane=0;lane<32;lane++)begin:read_preview
  assign read_candidate_byte_addresses[lane]=read_addresses[lane];
  assign read_candidate_input_words[lane]=read_inputs[lane];
 end
 native_movm_word_pipeline #(.SLOTS(MOVM_SLOTS),.LATENCY(MOVM_LATENCY),.INTERVAL(MOVM_INTERVAL)) moves(
  .clk,.rst,.req_valid(mov_req_valid),.req_ready(mov_req_ready),.req_id(mov_req_id),.input_words(mov_inputs),
  .rsp_valid(mov_rsp_valid),.rsp_ready(mov_rsp_ready),.rsp_id(mov_rsp_id),.output_words(mov_outputs),.outstanding(mov_outstanding)
 );
 native_hmma16816_adapter #(.SLOTS(HMMA_SLOTS),.LATENCY(HMMA_LATENCY),.INTERVAL(HMMA_INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) tensor(
  .clk,.rst,.req_valid(h_req_valid),.req_ready(h_req_ready),.req_id(h_req_id),.a_registers(h_a),.b_registers(h_b),.c_registers(h_c),
  .rsp_valid(h_rsp_valid),.rsp_ready(h_rsp_ready),.rsp_id(h_rsp_id),.result_registers(h_results),.outstanding(h_outstanding)
 );
 // Shared values sampled on accepted LD.E issue. No full native register file,
 // address-ALU scoreboard, original missing scratch/barrier protocol or full SM.
endmodule
```

### 4.50. Resident blocks through scratch and acknowledged global outputs

**Question and scope.** Can two resident block contexts share the implemented services and retain their allocation until every output has actually been written? The [complete resident controller](numerical/resident_gemm_complete.sv) extends section 4.47 from register results to producer/consumer barriers, output scratch and acknowledged global stores. It runs bounded BM32/BN32/BK32 blocks. A caller submits block coordinates; this component is not a full-grid dispatcher or a multiple-SM scheduler.

| Interface or quantity | Contract |
|---|---|
| Launch | Valid/ready, 32-bit ID, A/B/C bases and block row/column; captured on acceptance |
| Input backing | 32-bit ID/address requests, actual 256-bit sector returns |
| Output backing | 32-bit ID/address, 256-bit data and eight-bit word mask; matching acknowledgment required |
| Completion | Retained ID/context and `[4][32][8]` registers, held until acknowledgment |
| Residency | Defaults two contexts, four warps each; 5,120 register words and 9,216 shared bytes reserved per block |
| Common services | One input cache, one read hub/service, one MOVM service and one HMMA service |
| Service capacities | Defaults: two common read slots, four MOVM slots and two HMMA slots; cache has 64 sets and eight ways |
| Output actor | One scratch transaction and one warp-store transaction at a time |
| Default delays | Read return nine, MOVM 19, HMMA 73, store return one and barrier release one modeled cycle |
| Default intervals | Shared package one, MOVM one, HMMA four and scratch store package one modeled cycle |

Launch validation checks complete block bounds, even A/B bases, word-aligned C, 32-bit allocation limits and output/input nonoverlap. Accepted metadata remains captured while external launch inputs change. Cached A/B values must remain immutable until reset. The tested blocks write disjoint output tiles; concurrent conflicting output launches are outside the intended contract.

Each context carries its accumulator through K/32 actual stages. Producer barrier arrivals follow the final committed operand groups for its four warps. Consumer arrivals use memory-safe indications, while the controller separately waits for actual arithmetic results before replacing the stage. The producer and consumer barrier objects track generations separately. This whole-stage rule remains conservative and does not replay every original address-generation or synchronization instruction.

**One resource across operand and scratch work.** Native operand reads and scratch reads are separate clients of the same read hub. Neither the native engine nor scratch component has a private read service. A common write arbiter grants either one staging vector commit or one scratch bank package per edge. Operand arrays remain private per context, and scratch has its own 4,096-byte logical array. Sharing service admission does not establish actual GPU storage aliasing, bank topology, native write bandwidth or calibrated overlap.

**Scratch interface and behavior.** The [external-service scratch component](numerical/studied_output_scratch_shared.sv) accepts an ID and four fragments' accumulators, then captures their values. Its store preview requests permission to commit the next package; only `store_grant` commits selected pending words. Four native STS64-shaped groups per warp produce 16 groups and 1,024 committed words. The modeled bank rule selects at most one pending word per bank per granted package; its interval and return delay are hypotheses. After a collective all-writes visibility fence, 32 real warp-read grants and matching returns reconstruct `[4][256]` row-major words. This all-store-before-all-read ordering is stronger than the original per-warp ordering. The component holds its ID and row-major response until acknowledged.

A registered output owner supplies these returned scratch words to 32 warp stores. Every 32 × 32 block sends 128 masked 32-byte sector packets containing all 1,024 FP32 outputs. The store adapter waits for each actual matching backing acknowledgment. The controller releases the scratch response only with the final warp-store completion; only then does that block enter final completion. Allocation remains live while final completion is held and retires only on its acknowledgment. Section 4.47 stops at the final register result; this bounded block lifetime also includes output writes.

**A model bug found by integration.** The first connected test exposed a consumer arrival after its barrier had already released. The controller had derived new arrivals from the barrier's transient arrived mask, which clears on release, while memory-safe indications stayed asserted. That caused the same warps to arrive again before the next generation was armed. The corrected `consumer_seen` mask belongs to the compute stage: it persists across barrier release and clears only when the next compute request is accepted. Thus each warp contributes once to that stage. This correction fixes simulation ownership; it does not identify a new NVIDIA barrier property.

**Verification and limits.** The [current complete-block receipt](numerical/resident_complete_verification.json) checks 12,288 acknowledged global FP32 outputs: all six disjoint blocks of M64/N96 at K64 and again at K1536, admitted through two contexts. An independent integer dot product using the original A17/B13 patterns and global strides, divided by 256, supplies exact expectations. Misaligned C, overlap with A/B and C-allocation overflow are rejected. The fixture perturbs A/B metadata and C base after acceptance and checks captured values. Reset is tested at the first pending input read, not during output stores. Held completion stability is checked; progress by another context during that exact hold is not required by this test. Reset requires provider cancellation and does not undo already committed stores.

Scratch behavior is exercised through this integrated top, not an isolated scratch test. The fixture records no simultaneous eligible native/scratch read candidates and confirms that staging and scratch writes were eligible together. Its contention indicators are Boolean flags, not event counts. Therefore it does not directly test real read competition in this complete path; section 4.49’s synthetic scratch client separately exercises the common hub. The numerical checks establish this bounded value/lifecycle path. They do not validate the original large global grid, full native instruction replay, physical resident capacity or GPU runtime. Output service is conservative and serial. All queue, delay and arbitration choices remain uncalibrated; physical counts remain eight identified, 32 partial and 94 unknown.

The [connected-round record](discovery_rounds/resident_complete_connected.json) preserves the integration evidence and remaining gaps.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_resident_gemm_complete.py`.

**Inline scratch behavior.**

```systemverilog
// External read hub and write-package grant; no private read service.
// A store grant commits one pending word per bank. Global write arbitration
// is required when staging and scratch stores coexist.
// Original BM32 output scratch: four STS64 groups per warp, then eight LDS
// warp reads per warp. Native C layout is measured; serial service and bank
// write interval/return delays are simulation choices, not identified timing.
// Collective visibility fence substitutes for native WARPSYNC arrival rules.
module studied_output_scratch_shared #(
 parameter int STORE_INTERVAL=1,STORE_RETURN_DELAY=1
)(
 output logic store_candidate_valid,input logic store_grant,
 output logic read_candidate_valid,input logic read_candidate_grant,
 output logic[31:0]read_candidate_id,read_candidate_byte_addresses[32],read_candidate_input_words[32],
 input logic read_rsp_valid,output logic read_rsp_ready,
 input logic[31:0]read_rsp_id,read_rsp_words[32],
 input logic clk,rst,req_valid,output logic req_ready,input logic[31:0]req_id,
 input logic[31:0]c_registers[4][32][8],
 output logic rsp_valid,input logic rsp_ready,output logic[31:0]rsp_id,
 output logic[31:0]row_major_words[4][256],output int outstanding,
 output int store_requests,store_commit_words,read_requests,read_completions
);
 typedef enum logic[2:0]{IDLE,STORE_PREP,STORE_SERVICE,STORE_RETURN,
  READ_SEND,READ_WAIT,RESPONSE}state_t;
 state_t state;
 logic[31:0]saved_id,saved_c[4][32][8],scratch[1024];logic initialized[1024];
 int store_warp,store_group,remaining_words,pacing,return_delay,read_ordinal;
 logic pending_entry[64];int entry_address[64];logic[31:0]entry_data[64];
 int selected_entry[32],selected_words;
 logic read_req_valid,read_req_ready;
 logic[31:0]read_req_id,read_addresses[32],read_inputs[32],read_outputs[32];
 initial if(STORE_INTERVAL<1||STORE_RETURN_DELAY<1)
  $fatal(1,"Invalid output scratch timing configuration");
 assign req_ready=!rst&&state==IDLE;
 assign rsp_valid=!rst&&state==RESPONSE;assign rsp_id=saved_id;
 assign outstanding=state==IDLE?0:1;
 always_comb begin
  selected_words=0;
  for(int bank=0;bank<32;bank++)begin
   selected_entry[bank]=-1;
   for(int entry=0;entry<64;entry++)if(pending_entry[entry]&&entry_address[entry]%32==bank&&selected_entry[bank]<0)selected_entry[bank]=entry;
   if(selected_entry[bank]>=0)selected_words++;
  end
 end
 assign store_candidate_valid=!rst&&state==STORE_SERVICE&&pacing==0;
 assign read_req_valid=!rst&&state==READ_SEND;
 assign read_candidate_valid=read_req_valid;
 assign read_req_ready=read_candidate_grant;
 assign read_candidate_id=read_req_id;
 always_comb for(int lane=0;lane<32;lane++)begin
  read_candidate_byte_addresses[lane]=read_addresses[lane];
  read_candidate_input_words[lane]=read_inputs[lane];
  read_outputs[lane]=read_rsp_words[lane];
 end
 always_ff @(posedge clk)if(!rst&&store_grant&&!store_candidate_valid)$fatal(1,"Scratch write grant lacks a candidate");
 always_ff @(posedge clk)if(!rst&&read_candidate_grant&&!read_candidate_valid)$fatal(1,"Scratch read grant lacks a candidate");
 always_ff @(posedge clk)if(!rst&&read_rsp_valid&&state!=READ_WAIT)$fatal(1,"Scratch read response has no pending operation");
 assign read_rsp_ready=!rst&&state==READ_WAIT;
 assign read_req_id=32'(read_ordinal);
 always_comb begin
  for(int lane=0;lane<32;lane++)begin
   read_addresses[lane]=32'(1024*(read_ordinal/8)+4*(lane+32*(read_ordinal%8)));
   read_inputs[lane]=scratch[256*(read_ordinal/8)+lane+32*(read_ordinal%8)];
  end
 end
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;saved_id<=0;store_warp<=0;store_group<=0;remaining_words<=0;pacing<=0;return_delay<=0;read_ordinal<=0;
   store_requests<=0;store_commit_words<=0;read_requests<=0;read_completions<=0;
   for(int i=0;i<1024;i++)begin scratch[i]<=0;initialized[i]<=0;end
   for(int entry=0;entry<64;entry++)begin pending_entry[entry]<=0;entry_address[entry]<=0;entry_data[entry]<=0;end
   for(int warp=0;warp<4;warp++)begin
    for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)saved_c[warp][lane][word]<=0;
    for(int word=0;word<256;word++)row_major_words[warp][word]<=0;
   end
  end else case(state)
   IDLE:if(req_valid&&req_ready)begin
    saved_id<=req_id;store_warp<=0;store_group<=0;read_ordinal<=0;state<=STORE_PREP;
    store_requests<=0;store_commit_words<=0;read_requests<=0;read_completions<=0;
    for(int i=0;i<1024;i++)initialized[i]<=0;
    for(int warp=0;warp<4;warp++)begin
     for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)saved_c[warp][lane][word]<=c_registers[warp][lane][word];
     for(int word=0;word<256;word++)row_major_words[warp][word]<=0;
    end
   end
   STORE_PREP:begin
    // Pairs0/1,2/3,4/5,6/7 have native byte offsets0,512,32,544.
    for(int lane=0;lane<32;lane++)for(int half=0;half<2;half++)begin
     pending_entry[2*lane+half]<=1;
     entry_address[2*lane+half]<=256*store_warp+native_bf16_layout::c_element_index(lane,2*store_group+half);
     entry_data[2*lane+half]<=saved_c[store_warp][lane][2*store_group+half];
    end
    remaining_words<=64;pacing<=0;store_requests<=store_requests+1;state<=STORE_SERVICE;
   end
   STORE_SERVICE:begin
    if(pacing>0)pacing<=pacing-1;
    else if(store_grant)begin
     if(selected_words<1||selected_words>remaining_words)$fatal(1,"Invalid output scratch bank work");
     for(int bank=0;bank<32;bank++)if(selected_entry[bank]>=0)begin
      scratch[entry_address[selected_entry[bank]]]<=entry_data[selected_entry[bank]];
      initialized[entry_address[selected_entry[bank]]]<=1;pending_entry[selected_entry[bank]]<=0;
     end
     store_commit_words<=store_commit_words+selected_words;
     remaining_words<=remaining_words-selected_words;pacing<=STORE_INTERVAL-1;
     if(remaining_words==selected_words)begin return_delay<=STORE_RETURN_DELAY-1;state<=STORE_RETURN;end
    end
   end
   STORE_RETURN:begin
    if(return_delay>0)return_delay<=return_delay-1;
    else if(store_group<3)begin store_group<=store_group+1;state<=STORE_PREP;end
    else if(store_warp<3)begin store_warp<=store_warp+1;store_group<=0;state<=STORE_PREP;end
    else begin
     if(store_commit_words!=1024||store_requests!=16)$fatal(1,"Scratch visibility fence reached before all stores");
     read_ordinal<=0;state<=READ_SEND;
    end
   end
   READ_SEND:if(read_req_valid&&read_req_ready)begin
    for(int lane=0;lane<32;lane++)if(!initialized[256*(read_ordinal/8)+lane+32*(read_ordinal%8)])$fatal(1,"Scratch load precedes write visibility");
    read_requests<=read_requests+1;state<=READ_WAIT;
   end
   READ_WAIT:if(read_rsp_valid&&read_rsp_ready)begin
    if(read_rsp_id!=read_req_id)$fatal(1,"Scratch read completion identity mismatch");
    for(int lane=0;lane<32;lane++)row_major_words[read_ordinal/8][lane+32*(read_ordinal%8)]<=read_outputs[lane];
    read_completions<=read_completions+1;
    if(read_ordinal==31)state<=RESPONSE;
    else begin read_ordinal<=read_ordinal+1;state<=READ_SEND;end
   end
   RESPONSE:if(rsp_valid&&rsp_ready)state<=IDLE;
   default:$fatal(1,"Invalid output scratch state");
  endcase
 end
 // Actual shared words feed response reads; no C-to-output bypass. Each batch
 // drains all writes then all32 reads. Reset discards pending service events.
endmodule
```

**Inline complete-block behavior.**

```systemverilog
// Concurrent complete-reduction operand/compute path for native BM32/BN32.
// One shared input cache and one shared read/MOVM/HMMA service set.
// Actual scratch/output-store acknowledgments and context barrier generations
// complete this bounded lifecycle. Arbitration and all timing remain hypotheses.
module resident_gemm_complete #(
 parameter int CONTEXTS=2,M=64,N=96,K=64,SETS=64,WAYS=8,
 parameter int STORE_INTERVAL=1,STORE_RETURN_DELAY=1,BARRIER_RELEASE_DELAY=1,
 parameter int READ_SLOTS=2,RETURN_DELAY=9,MOVM_LATENCY=19,HMMA_LATENCY=73,
 parameter int SERVICE_INTERVAL=1,MOVM_INTERVAL=1,HMMA_INTERVAL=4,ARITHMETIC_MODE=1
)(
 input logic clk,rst,launch_valid,output logic launch_ready,
 input logic[31:0]launch_id,a_base,b_base,c_base,cta_row,cta_col,
 output logic done_valid,input logic done_ready,
 output logic[31:0]done_id,done_context,result_registers[4][32][8],
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data,
 output logic store_backing_req_valid,input logic store_backing_req_ready,
 output logic[31:0]store_backing_req_id,store_backing_req_byte_address,
 output logic[255:0]store_backing_req_data,output logic[7:0]store_backing_req_word_mask,
 input logic store_backing_rsp_valid,output logic store_backing_rsp_ready,input logic[31:0]store_backing_rsp_id,
 output int resident_blocks,resident_warps,
 output logic native_issue_valid,output logic[31:0]native_issue_context,native_issue_warp,native_issue_pc
);
 localparam int STAGES=K/32;
 typedef enum logic[2:0]{IDLE,STAGE_SEND,STAGE_WAIT,COMPUTE_SEND,COMPUTE_WAIT,OUTPUT_SEND,OUTPUT_WAIT,RESULT}state_t;
 state_t state[CONTEXTS];
 logic[31:0]ids[CONTEXTS],rows[CONTEXTS],cols[CONTEXTS],abase[CONTEXTS],bbase[CONTEXTS],cbase[CONTEXTS];
 logic[31:0]accumulators[CONTEXTS][4][32][8];
 int stage_number[CONTEXTS],stage_owner,stage_cursor,compute_owner,compute_cursor,result_owner,result_cursor;
 int admitted_slot,allocated_register_words,allocated_shared_bytes;
 logic allocator_ready,launch_legal,admit_fire,retire_fire;
 logic staging_valid,staging_ready,staging_done_valid,staging_done_ready;
 logic[31:0]staging_context,staging_id,staging_done_context,staging_done_id;
 logic[CONTEXTS-1:0]staging_context_ready;int staging_outstanding;
 logic write_warp_valid,write_warp_ready;logic[31:0]write_context,write_warp_byte_addresses[32],write_warp_mask;
 logic[15:0]write_warp_halfwords[32];
 logic compute_valid,compute_ready,compute_rsp_valid,compute_rsp_ready;
 logic[31:0]compute_context,compute_id,compute_rsp_context,compute_rsp_id;
 logic[31:0]compute_c[4][32][8],compute_result[4][32][8];
 logic[CONTEXTS-1:0]compute_context_ready,compute_context_initialized;
 logic[3:0]warp_drained[CONTEXTS],warp_memory_safe[CONTEXTS];
 logic initialized,legal;int compute_outstanding;
 logic[1:0]read_candidate_valid,read_candidate_grant,read_return_valid,read_return_ready;
 logic[31:0]read_candidate_id[2],read_candidate_addresses[2][32],read_candidate_words[2][32],read_return_id[2],read_return_words[2][32];
 int read_outstanding,read_client_outstanding[2];
 logic staging_commit_ready,engine_write_ready,scratch_store_candidate,scratch_store_grant;
 int write_cursor;
 logic producer_released[CONTEXTS],consumer_released[CONTEXTS];
 logic producer_release_valid[CONTEXTS],consumer_release_valid[CONTEXTS];
 logic[3:0]consumer_arrived[CONTEXTS],consumer_arrival_mask[CONTEXTS],consumer_seen[CONTEXTS];
 logic producer_arrival_valid[CONTEXTS];logic[3:0]producer_arrival_mask[CONTEXTS];
 int output_owner,output_cursor,store_ordinal;
 logic scratch_req_valid,scratch_req_ready,scratch_rsp_valid,scratch_rsp_ready;
 logic[31:0]scratch_rsp_id,scratch_c[4][32][8],scratch_words[4][256];
 int scratch_outstanding,scratch_store_requests,scratch_commit_words,scratch_read_requests,scratch_read_completions;
 logic store_req_valid,store_req_ready,store_rsp_valid,store_rsp_ready;
 logic[31:0]store_id,store_rsp_id,store_addresses[32],store_words[32];int store_sectors;
 logic store_wait;
 initial if(CONTEXTS<1||M<32||N<32||K<32||M%32||N%32||K%32)$fatal(1,"Unsupported resident reduction geometry");
 always_comb begin
  launch_legal=cta_row<M/32&&cta_col<N/32&&!a_base[0]&&!b_base[0]&&c_base[1:0]==0;
  if(64'(a_base)+2*64'(M)*64'(K)>64'h100000000||64'(b_base)+2*64'(K)*64'(N)>64'h100000000||64'(c_base)+4*64'(M)*64'(N)>64'h100000000)launch_legal=0;
  if(64'(c_base)<64'(a_base)+2*64'(M)*64'(K)&&64'(a_base)<64'(c_base)+4*64'(M)*64'(N))launch_legal=0;
  if(64'(c_base)<64'(b_base)+2*64'(K)*64'(N)&&64'(b_base)<64'(c_base)+4*64'(M)*64'(N))launch_legal=0;
 end
 assign launch_ready=!rst&&allocator_ready&&launch_legal;
 assign admit_fire=launch_valid&&launch_ready;
 assign done_valid=!rst&&result_owner>=0;
 assign done_context=result_owner>=0?32'(result_owner):0;
 assign done_id=result_owner>=0?ids[result_owner]:0;
 assign retire_fire=done_valid&&done_ready;
 always_comb begin
  for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)begin
   result_registers[w][l][e]=result_owner>=0?accumulators[result_owner][w][l][e]:0;
   compute_c[w][l][e]=compute_owner>=0?accumulators[compute_owner][w][l][e]:0;
  end
 end
 assign staging_valid=!rst&&stage_owner>=0;
 assign staging_context=stage_owner>=0?32'(stage_owner):0;
 assign staging_id=stage_owner>=0?32'(stage_number[stage_owner]):0;
 assign staging_done_ready=!rst&&staging_done_context<CONTEXTS&&
                           (staging_done_context<CONTEXTS?state[staging_done_context]==STAGE_WAIT&&producer_released[staging_done_context]:0);
 assign compute_valid=!rst&&compute_owner>=0;
 assign compute_context=compute_owner>=0?32'(compute_owner):0;
 assign compute_id=compute_owner>=0?32'(stage_number[compute_owner]):0;
 assign compute_rsp_ready=!rst&&compute_rsp_context<CONTEXTS&&
                         (compute_rsp_context<CONTEXTS?state[compute_rsp_context]==COMPUTE_WAIT&&consumer_released[compute_rsp_context]:0);
 quantized_block_admission #(.BLOCK_SLOTS(CONTEXTS)) admission(
  .clk,.rst,.admit_valid(admit_fire),.block_threads(128),.registers_per_thread(40),
  .user_shared_bytes(8192),.reserved_shared_bytes(1024),.admit_ready(allocator_ready),
  .admitted_slot,.resident_blocks,.resident_warps,.allocated_register_words,.allocated_shared_bytes,
  .retire_valid(retire_fire),.retire_slot(result_owner)
 );
 always_ff @(posedge clk)begin
  if(rst)begin
   stage_owner<=-1;stage_cursor<=0;compute_owner<=-1;compute_cursor<=0;result_owner<=-1;result_cursor<=0;output_owner<=-1;output_cursor<=0;store_ordinal<=0;store_wait<=0;write_cursor<=0;
   for(int c=0;c<CONTEXTS;c++)begin
    state[c]<=IDLE;ids[c]<=0;rows[c]<=0;cols[c]<=0;abase[c]<=0;bbase[c]<=0;cbase[c]<=0;stage_number[c]<=0;producer_released[c]<=0;consumer_released[c]<=0;consumer_seen[c]<='0;
    for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)accumulators[c][w][l][e]<=0;
   end
  end else begin
   integer active;active=0;for(int c=0;c<CONTEXTS;c++)if(state[c]!=IDLE)active++;
   if(active!=resident_blocks||resident_warps!=4*active)$fatal(1,"Reduction resource/context conservation failed");
   if(launch_valid&&!launch_legal)$fatal(1,"Invalid resident reduction launch geometry or input allocation");
   if(admit_fire)begin
    if(admitted_slot<0||admitted_slot>=CONTEXTS||state[admitted_slot]!=IDLE)$fatal(1,"Reduction slot admission mismatch");
    state[admitted_slot]<=STAGE_SEND;ids[admitted_slot]<=launch_id;rows[admitted_slot]<=cta_row;cols[admitted_slot]<=cta_col;
    abase[admitted_slot]<=a_base;bbase[admitted_slot]<=b_base;cbase[admitted_slot]<=c_base;stage_number[admitted_slot]<=0;
    for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)accumulators[admitted_slot][w][l][e]<=0;
   end
   // Owners are registered before a request is offered; stalled payloads stay fixed.
   if(stage_owner<0)begin
    integer choice;choice=-1;
    for(int off=0;off<CONTEXTS;off++)begin integer c;c=(stage_cursor+off)%CONTEXTS;
     if(choice<0&&state[c]==STAGE_SEND)choice=c;
    end
    if(choice>=0)stage_owner<=choice;
   end else if(staging_valid&&staging_ready)begin
    producer_released[stage_owner]<=0;state[stage_owner]<=STAGE_WAIT;stage_cursor<=(stage_owner+1)%CONTEXTS;stage_owner<=-1;
   end
   if(staging_done_valid)begin
    if(staging_done_context>=CONTEXTS)$fatal(1,"Unknown staging completion context");
    else if(state[staging_done_context]!=STAGE_WAIT||staging_done_id!=32'(stage_number[staging_done_context]))$fatal(1,"Staging completion ownership mismatch");
   end
   if(staging_done_valid&&staging_done_ready)state[staging_done_context]<=COMPUTE_SEND;
   if(compute_owner<0)begin
    integer choice;choice=-1;
    for(int off=0;off<CONTEXTS;off++)begin integer c;c=(compute_cursor+off)%CONTEXTS;
     if(choice<0&&state[c]==COMPUTE_SEND)choice=c;
    end
    if(choice>=0)compute_owner<=choice;
   end else if(compute_valid&&compute_ready)begin
    consumer_released[compute_owner]<=0;consumer_seen[compute_owner]<='0;state[compute_owner]<=COMPUTE_WAIT;compute_cursor<=(compute_owner+1)%CONTEXTS;compute_owner<=-1;
   end
   if(compute_rsp_valid)begin
    if(compute_rsp_context>=CONTEXTS)$fatal(1,"Unknown compute completion context");
    else if(state[compute_rsp_context]!=COMPUTE_WAIT||compute_rsp_id!=32'(stage_number[compute_rsp_context]))$fatal(1,"Compute completion ownership mismatch");
   end
   if(compute_rsp_valid&&compute_rsp_ready)begin
    for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)accumulators[compute_rsp_context][w][l][e]<=compute_result[w][l][e];
    if(stage_number[compute_rsp_context]==STAGES-1)state[compute_rsp_context]<=OUTPUT_SEND;
    else begin stage_number[compute_rsp_context]<=stage_number[compute_rsp_context]+1;state[compute_rsp_context]<=STAGE_SEND;end
   end
   for(int ctx=0;ctx<CONTEXTS;ctx++)begin
    if(producer_release_valid[ctx])producer_released[ctx]<=1;
    if(consumer_release_valid[ctx])consumer_released[ctx]<=1;
    if(consumer_arrival_mask[ctx]!=0)consumer_seen[ctx]<=consumer_seen[ctx]|consumer_arrival_mask[ctx];
   end
   if(write_warp_valid&&staging_commit_ready)write_cursor<=1;
   if(scratch_store_grant)write_cursor<=0;
   if(output_owner<0)begin
    integer choice;choice=-1;
    for(int off=0;off<CONTEXTS;off++)begin integer c;c=(output_cursor+off)%CONTEXTS;
     if(choice<0&&state[c]==OUTPUT_SEND)choice=c;
    end
    if(choice>=0)begin output_owner<=choice;store_ordinal<=0;store_wait<=0;end
   end else begin
    if(scratch_req_valid&&scratch_req_ready)state[output_owner]<=OUTPUT_WAIT;
    if(scratch_rsp_valid&&scratch_rsp_id!=32'(output_owner))$fatal(1,"Scratch ownership mismatch");
    if(store_req_valid&&store_req_ready)store_wait<=1;
    if(store_rsp_valid)begin
     if(!store_wait||store_rsp_id!=store_id)$fatal(1,"Output store identity mismatch");
    end
    if(store_rsp_valid&&store_rsp_ready)begin
     store_wait<=0;
     if(store_ordinal==31)begin state[output_owner]<=RESULT;output_cursor<=(output_owner+1)%CONTEXTS;output_owner<=-1;end
     else store_ordinal<=store_ordinal+1;
    end
   end
   if(result_owner<0)begin
    integer choice;choice=-1;
    for(int off=0;off<CONTEXTS;off++)begin integer c;c=(result_cursor+off)%CONTEXTS;
     if(choice<0&&state[c]==RESULT)choice=c;
    end
    if(choice>=0)result_owner<=choice;
   end else if(retire_fire)begin
    state[result_owner]<=IDLE;result_cursor<=(result_owner+1)%CONTEXTS;result_owner<=-1;
   end
  end
 end
 resident_operand_staging #(.CONTEXTS(CONTEXTS),.M(M),.N(N),.K(K),.SETS(SETS),.WAYS(WAYS)) staging(
  .clk,.rst,.req_valid(staging_valid),.req_ready(staging_ready),.req_context(staging_context),.req_id(staging_id),
  .a_base(stage_owner>=0?abase[stage_owner]:0),.b_base(stage_owner>=0?bbase[stage_owner]:0),
  .cta_row(stage_owner>=0?rows[stage_owner]:0),.cta_col(stage_owner>=0?cols[stage_owner]:0),
  .stage_index(stage_owner>=0?32'(stage_number[stage_owner]):0),
  .context_ready(staging_context_ready),.outstanding(staging_outstanding),
  .write_warp_valid,.write_warp_ready(staging_commit_ready),.write_context,.write_warp_byte_addresses,.write_warp_halfwords,.write_warp_mask,
  .done_valid(staging_done_valid),.done_ready(staging_done_ready),.done_context(staging_done_context),.done_id(staging_done_id),
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,
  .backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data
 );
 resident_native_stage_shared #(.CONTEXTS(CONTEXTS),.ALLOW_WARP_WRITES(1),.READ_SLOTS(READ_SLOTS),
  .SERVICE_INTERVAL(SERVICE_INTERVAL),.RETURN_DELAY(RETURN_DELAY),.MOVM_LATENCY(MOVM_LATENCY),.MOVM_INTERVAL(MOVM_INTERVAL),
  .HMMA_LATENCY(HMMA_LATENCY),.HMMA_INTERVAL(HMMA_INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) engine(
  .read_candidate_valid(read_candidate_valid[0]),.read_candidate_grant(read_candidate_grant[0]),
  .read_candidate_id(read_candidate_id[0]),.read_candidate_byte_addresses(read_candidate_addresses[0]),.read_candidate_input_words(read_candidate_words[0]),
  .read_rsp_valid(read_return_valid[0]),.read_rsp_ready(read_return_ready[0]),.read_rsp_id(read_return_id[0]),.read_rsp_words(read_return_words[0]),.read_client_outstanding(read_client_outstanding[0]),
  .clk,.rst,.write_context,.write_valid(1'b0),.write_ready(),.write_byte_address(32'd0),.write_data(16'd0),
  .write_warp_valid(write_warp_valid&&staging_commit_ready),.write_warp_ready(engine_write_ready),.write_warp_byte_addresses,.write_warp_halfwords,.write_warp_mask,
  .req_valid(compute_valid),.req_ready(compute_ready),.req_context(compute_context),.req_id(compute_id),.c_registers(compute_c),
  .operands_initialized(initialized),.addresses_legal(legal),.context_ready(compute_context_ready),.context_initialized(compute_context_initialized),
  .rsp_valid(compute_rsp_valid),.rsp_ready(compute_rsp_ready),.rsp_context(compute_rsp_context),.rsp_id(compute_rsp_id),
  .result_registers(compute_result),.outstanding(compute_outstanding),.warp_drained,.warp_memory_safe,
  .native_issue_valid,.native_issue_context,.native_issue_warp,.native_issue_pc
 );
 // Common write edge: staging vector or scratch bank package, never both.
 always_comb begin
  staging_commit_ready=0;scratch_store_grant=0;
  if(!rst)begin
   if(write_warp_valid&&engine_write_ready&&(!scratch_store_candidate||write_cursor==0))staging_commit_ready=1;
   else if(scratch_store_candidate)scratch_store_grant=1;
  end
 end
 assign write_warp_ready=staging_commit_ready;
 for(genvar ctx=0;ctx<CONTEXTS;ctx++)begin:barriers
  logic prod_arm_ready,cons_arm_ready,prod_arrival_ready,cons_arrival_ready,prod_active,cons_active;
  logic[31:0]prod_generation,cons_generation;logic[3:0]prod_arrived,prod_release_mask,cons_release_mask;
  always_comb begin
   producer_arrival_valid[ctx]=write_warp_valid&&staging_commit_ready&&write_context==ctx&&write_warp_byte_addresses[0]>=3840;
   producer_arrival_mask[ctx]=producer_arrival_valid[ctx]?4'(1<<(int'(write_warp_byte_addresses[0])/64-60)):0;
   consumer_arrival_mask[ctx]=state[ctx]==COMPUTE_WAIT?(warp_memory_safe[ctx]&~consumer_seen[ctx]):0;
  end
  cta_generation_barrier #(.RELEASE_DELAY(BARRIER_RELEASE_DELAY)) producer(
   .clk,.rst(rst||state[ctx]==IDLE),.arm_valid(staging_valid&&staging_ready&&stage_owner==ctx),.arm_ready(prod_arm_ready),.arm_generation(32'(stage_number[ctx])),.expected_mask(4'b1111),
   .arrival_valid(producer_arrival_valid[ctx]),.arrival_ready(prod_arrival_ready),.arrival_generation(32'(stage_number[ctx])),.arrival_mask(producer_arrival_mask[ctx]),
   .release_valid(producer_release_valid[ctx]),.release_ready(1'b1),.generation(prod_generation),.release_mask(prod_release_mask),.arrived_mask(prod_arrived),.active(prod_active));
  cta_generation_barrier #(.RELEASE_DELAY(BARRIER_RELEASE_DELAY)) consumer(
   .clk,.rst(rst||state[ctx]==IDLE),.arm_valid(compute_valid&&compute_ready&&compute_owner==ctx),.arm_ready(cons_arm_ready),.arm_generation(32'(stage_number[ctx])),.expected_mask(4'b1111),
   .arrival_valid(consumer_arrival_mask[ctx]!=0),.arrival_ready(cons_arrival_ready),.arrival_generation(32'(stage_number[ctx])),.arrival_mask(consumer_arrival_mask[ctx]),
   .release_valid(consumer_release_valid[ctx]),.release_ready(1'b1),.generation(cons_generation),.release_mask(cons_release_mask),.arrived_mask(consumer_arrived[ctx]),.active(cons_active));
 end
 shared_read_candidate_hub #(.CLIENTS(2),.SLOTS(READ_SLOTS),.SERVICE_INTERVAL(SERVICE_INTERVAL),.RETURN_DELAY(RETURN_DELAY)) read_hub(
  .clk,.rst,.candidate_valid(read_candidate_valid),.candidate_grant(read_candidate_grant),.candidate_id(read_candidate_id),.byte_addresses(read_candidate_addresses),.input_words(read_candidate_words),
  .rsp_valid(read_return_valid),.rsp_ready(read_return_ready),.rsp_id(read_return_id),.output_words(read_return_words),.outstanding(read_outstanding),.client_outstanding(read_client_outstanding));
 assign scratch_req_valid=!rst&&output_owner>=0&&(output_owner>=0?state[output_owner]==OUTPUT_SEND:0);
 always_comb for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)scratch_c[w][l][e]=output_owner>=0?accumulators[output_owner][w][l][e]:0;
 studied_output_scratch_shared #(.STORE_INTERVAL(STORE_INTERVAL),.STORE_RETURN_DELAY(STORE_RETURN_DELAY)) scratch(
  .clk,.rst,.store_candidate_valid(scratch_store_candidate),.store_grant(scratch_store_grant),
  .read_candidate_valid(read_candidate_valid[1]),.read_candidate_grant(read_candidate_grant[1]),.read_candidate_id(read_candidate_id[1]),.read_candidate_byte_addresses(read_candidate_addresses[1]),.read_candidate_input_words(read_candidate_words[1]),
  .read_rsp_valid(read_return_valid[1]),.read_rsp_ready(read_return_ready[1]),.read_rsp_id(read_return_id[1]),.read_rsp_words(read_return_words[1]),
  .req_valid(scratch_req_valid),.req_ready(scratch_req_ready),.req_id(output_owner>=0?32'(output_owner):0),.c_registers(scratch_c),
  .rsp_valid(scratch_rsp_valid),.rsp_ready(scratch_rsp_ready),.rsp_id(scratch_rsp_id),.row_major_words(scratch_words),.outstanding(scratch_outstanding),
  .store_requests(scratch_store_requests),.store_commit_words(scratch_commit_words),.read_requests(scratch_read_requests),.read_completions(scratch_read_completions));
 assign store_id=output_owner>=0?32'(output_owner*32+store_ordinal):0;
 assign store_req_valid=!rst&&output_owner>=0&&scratch_rsp_valid&&!store_wait;
 assign store_rsp_ready=!rst&&output_owner>=0&&store_wait;
 assign scratch_rsp_ready=store_rsp_valid&&store_rsp_ready&&store_ordinal==31;
 always_comb for(int lane=0;lane<32;lane++)begin
  int warp,index_value,row_value,col_value;
  warp=store_ordinal/8;index_value=32*(store_ordinal%8)+lane;
  row_value=16*(warp/2)+index_value/16;col_value=16*(warp%2)+index_value%16;
  store_words[lane]=scratch_words[warp][index_value];
  store_addresses[lane]=output_owner>=0?cbase[output_owner]+32'(4*((int'(rows[output_owner])*32+row_value)*N+int'(cols[output_owner])*32+col_value)):0;
 end
 coalesced_fp32_warp_store stores(
  .clk,.rst,.req_valid(store_req_valid),.req_ready(store_req_ready),.req_id(store_id),.byte_addresses(store_addresses),.words(store_words),.active_mask(32'hffffffff),
  .rsp_valid(store_rsp_valid),.rsp_ready(store_rsp_ready),.rsp_id(store_rsp_id),.sector_count(store_sectors),
  .backing_req_valid(store_backing_req_valid),.backing_req_ready(store_backing_req_ready),.backing_req_id(store_backing_req_id),.backing_req_byte_address(store_backing_req_byte_address),.backing_req_data(store_backing_req_data),.backing_req_word_mask(store_backing_req_word_mask),
  .backing_rsp_valid(store_backing_rsp_valid),.backing_rsp_ready(store_backing_rsp_ready),.backing_rsp_id(store_backing_rsp_id));
endmodule
```

### 4.51. Whole-grid dispatch into resident block contexts

**Role and organization.** The [resident grid controller](numerical/resident_gemm_grid.sv) submits every complete 32 × 32 output block to one instance of section 4.50's resident complete-block model. Unlike section 4.43's serial dispatcher, this component admits another block whenever a resident context is available. The default grid is M64/N96/K64: two block rows, three block columns and six blocks. Dimensions must be positive multiples of 32; partial edge blocks are unsupported. Two resident contexts share one input cache, read hub, MOVM/HMMA service set and serial output actor. This is one modeled SM, not an RTX chip scheduler.

| Interface or quantity | Definition |
|---|---|
| Grid launch | Valid/ready and 32-bit ID/A/B/C bases; captured on acceptance |
| Grid completion | Valid/ready and retained launch ID; stable while held |
| Input backing | 32-bit sector ID/address and actual 256-bit sector response |
| Output backing | 32-bit ID/address, 256-bit data, eight-bit word mask and matching acknowledgment |
| `dispatched_blocks` | Number of accepted child block launches in this grid |
| `completed_blocks` | Number of acknowledged child completions, each after its output stores |
| `resident_blocks`/`resident_warps` | Actual live child reservations; two contexts allow up to two blocks/eight warps |
| Block trace | Acceptance/completion pulses, ordinal and derived block row/column |
| `elapsed_cycles` | 64-bit model-edge counter from accepted grid launch to registered COMPLETE |

**Dispatch and ownership.** IDLE validates base alignment, 32-bit allocation bounds and C/input nonoverlap. Acceptance captures bases/ID, clears per-block launched/completed flags and enters RUN. Block columns advance fastest, followed by block rows. The dispatch ordinal advances only on child acceptance, so offered coordinates remain stable during backpressure. Child IDs are these ordinals rather than the external grid ID. Completion looks up the returned ordinal, rejects unlaunched, duplicate or out-of-range IDs and marks that block complete. The bookkeeping permits out-of-order child IDs; numerical correctness alone does not prove every possible ordering was exercised.

The controller checks `resident_blocks = dispatched_blocks − completed_blocks` while RUN. Grid completion requires every expected block dispatched and completed and zero resident reservations. Because each child completion follows all its actual output acknowledgments, grid completion cannot precede those stores. A subsequent RUN edge observes the drained counts and registers COMPLETE; final validity then holds until grid acknowledgment. No new grid is accepted while completion is held.

**Cycle boundary.** Acceptance sets the counter to zero. Each following RUN edge increments it, including the last child retirement and the additional drain-check edge. The counter stops in COMPLETE and remains fixed during a held final response. Thus it includes one drain-check edge beyond the last retirement, but excludes reset and held-completion duration. It is a count of this model's clock edges, with no conversion to physical GPU cycles or frequency.

The [current grid receipt](numerical/resident_grid_verification.json) checks 24,576 global output words: two complete six-block grids at K64 and two at K1536. Each launch checks all 6,144 outputs with an independent full integer-dot-product oracle and actual provider acknowledgments. Both contexts are occupied during each launch. C misalignment, overlap with A/B and allocation overflow are rejected. Captured A/B/C bases, held completion/counter stability and reset at the first pending input read are checked. Reset during output stores is not tested. The provider must flush stale returns on reset; previously committed output words are not rolled back. A/B remain immutable between repeated launches because the cache is retained and there is no invalidation port.

| Reduction length | First launch model cycles | Repeated launch model cycles |
|---|---:|---:|
| K64 | 27,499 | 21,692 |
| K1536 | 543,444 | 543,447 |

An independent edge counter checks these values. Cache contents are retained between launches, but the provider's timing phase also changes; these comparisons do not isolate a physical cache effect. Delay, queue, arbitration and resident-capacity settings inherit section 4.50's synthetic choices. This validates complete small-grid values and acknowledgment lifetimes, not the original M2048/N2112 grid or calibrated RTX runtime. Physical counts remain eight identified, 32 partial and 94 unknown.

The [connected-round record](discovery_rounds/resident_grid_connected.json) records the model change, verification and remaining full-chip gaps.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_resident_gemm_grid.py`.

**Inline behavior.**

```systemverilog
// A complete grid dispatches into one resident SM model. Column index changes
// fastest within each tile row. Scheduling/timing are hypotheses, not multi-SM.
module resident_gemm_grid #(
 parameter int CONTEXTS=2,M=64,N=96,K=64,SETS=64,WAYS=8,
 parameter int READ_SLOTS=2,RETURN_DELAY=9,MOVM_LATENCY=19,HMMA_LATENCY=73,
 parameter int SERVICE_INTERVAL=1,MOVM_INTERVAL=1,HMMA_INTERVAL=4,ARITHMETIC_MODE=1,
 parameter int STORE_INTERVAL=1,STORE_RETURN_DELAY=1,BARRIER_RELEASE_DELAY=1
)(
 input logic clk,rst,launch_valid,output logic launch_ready,
 input logic[31:0]launch_id,a_base,b_base,c_base,
 output logic done_valid,input logic done_ready,output logic[31:0]done_id,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data,
 output logic store_backing_req_valid,input logic store_backing_req_ready,
 output logic[31:0]store_backing_req_id,store_backing_req_byte_address,
 output logic[255:0]store_backing_req_data,output logic[7:0]store_backing_req_word_mask,
 input logic store_backing_rsp_valid,output logic store_backing_rsp_ready,input logic[31:0]store_backing_rsp_id,
 output int resident_blocks,resident_warps,dispatched_blocks,completed_blocks,
 output logic[63:0]elapsed_cycles,
 output logic block_launch_valid,block_done_valid,
 output logic[31:0]block_launch_ordinal,block_launch_row,block_launch_col,
 output logic[31:0]block_done_ordinal,block_done_row,block_done_col,
 output logic native_issue_valid,output logic[31:0]native_issue_context,native_issue_warp,native_issue_pc
);
 localparam int TILE_ROWS=M/32,TILE_COLS=N/32,BLOCKS=TILE_ROWS*TILE_COLS;
 typedef enum logic[1:0]{IDLE,RUN,COMPLETE}state_t;
 state_t state;logic[31:0]saved_id,saved_a,saved_b,saved_c;
 logic launched[BLOCKS],completed[BLOCKS];logic launch_legal;
 logic child_launch_valid,child_launch_ready,child_done_valid,child_done_ready;
 logic[31:0]child_id,child_done_id,child_done_context,child_result[4][32][8];
 initial if(CONTEXTS<1||M<32||N<32||K<32||M%32||N%32||K%32||BLOCKS<1)$fatal(1,"Invalid resident grid geometry");
 always_comb begin
  launch_legal=!a_base[0]&&!b_base[0]&&c_base[1:0]==0;
  if(64'(a_base)+2*64'(M)*64'(K)>64'h100000000||64'(b_base)+2*64'(K)*64'(N)>64'h100000000||64'(c_base)+4*64'(M)*64'(N)>64'h100000000)launch_legal=0;
  if(64'(c_base)<64'(a_base)+2*64'(M)*64'(K)&&64'(a_base)<64'(c_base)+4*64'(M)*64'(N))launch_legal=0;
  if(64'(c_base)<64'(b_base)+2*64'(K)*64'(N)&&64'(b_base)<64'(c_base)+4*64'(M)*64'(N))launch_legal=0;
 end
 assign launch_ready=!rst&&state==IDLE&&launch_legal;
 assign done_valid=!rst&&state==COMPLETE;assign done_id=saved_id;
 assign child_launch_valid=!rst&&state==RUN&&dispatched_blocks<BLOCKS;
 assign child_id=32'(dispatched_blocks);
 assign child_done_ready=!rst&&state==RUN;
 assign block_launch_valid=child_launch_valid&&child_launch_ready;
 assign block_launch_ordinal=child_id;
 assign block_launch_row=32'(dispatched_blocks/TILE_COLS);
 assign block_launch_col=32'(dispatched_blocks%TILE_COLS);
 assign block_done_valid=child_done_valid&&child_done_ready;
 assign block_done_ordinal=child_done_id;
 assign block_done_row=child_done_id/32'(TILE_COLS);
 assign block_done_col=child_done_id%32'(TILE_COLS);
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;elapsed_cycles<=0;saved_id<=0;saved_a<=0;saved_b<=0;saved_c<=0;dispatched_blocks<=0;completed_blocks<=0;
   for(int block_index=0;block_index<BLOCKS;block_index++)begin launched[block_index]<=0;completed[block_index]<=0;end
  end else begin
   if(launch_valid&&state==IDLE&&!launch_legal)$fatal(1,"Invalid resident grid launch allocation");
   if(state==RUN&&resident_blocks!=dispatched_blocks-completed_blocks)$fatal(1,"Grid dispatch/retirement conservation failed");
   case(state)
    IDLE:if(launch_valid&&launch_ready)begin
     elapsed_cycles<=0;saved_id<=launch_id;saved_a<=a_base;saved_b<=b_base;saved_c<=c_base;
     dispatched_blocks<=0;completed_blocks<=0;
     for(int block_index=0;block_index<BLOCKS;block_index++)begin launched[block_index]<=0;completed[block_index]<=0;end
     state<=RUN;
    end
    RUN:begin
     elapsed_cycles<=elapsed_cycles+1;
     if(block_launch_valid)begin
      if(dispatched_blocks>=BLOCKS||launched[dispatched_blocks])$fatal(1,"Duplicate/out-of-range grid dispatch");
      launched[dispatched_blocks]<=1;dispatched_blocks<=dispatched_blocks+1;
     end
     if(block_done_valid)begin
      if(child_done_id>=BLOCKS)$fatal(1,"Out-of-range grid completion");
      else if(!launched[child_done_id]||completed[child_done_id])$fatal(1,"Unlaunched/duplicate grid completion");
      completed[child_done_id]<=1;completed_blocks<=completed_blocks+1;
     end
     if(dispatched_blocks==BLOCKS&&completed_blocks==BLOCKS&&resident_blocks==0)state<=COMPLETE;
    end
    COMPLETE:if(done_valid&&done_ready)state<=IDLE;
    default:$fatal(1,"Invalid resident grid state");
   endcase
  end
 end
 resident_gemm_complete #(.CONTEXTS(CONTEXTS),.M(M),.N(N),.K(K),.SETS(SETS),.WAYS(WAYS),
  .READ_SLOTS(READ_SLOTS),.RETURN_DELAY(RETURN_DELAY),.MOVM_LATENCY(MOVM_LATENCY),.HMMA_LATENCY(HMMA_LATENCY),
  .SERVICE_INTERVAL(SERVICE_INTERVAL),.MOVM_INTERVAL(MOVM_INTERVAL),.HMMA_INTERVAL(HMMA_INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE),
  .STORE_INTERVAL(STORE_INTERVAL),.STORE_RETURN_DELAY(STORE_RETURN_DELAY),.BARRIER_RELEASE_DELAY(BARRIER_RELEASE_DELAY)) sm(
  .clk,.rst,.launch_valid(child_launch_valid),.launch_ready(child_launch_ready),.launch_id(child_id),.a_base(saved_a),.b_base(saved_b),.c_base(saved_c),
  .cta_row(32'(dispatched_blocks/TILE_COLS)),.cta_col(32'(dispatched_blocks%TILE_COLS)),
  .done_valid(child_done_valid),.done_ready(child_done_ready),.done_id(child_done_id),.done_context(child_done_context),.result_registers(child_result),
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,.backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data,
  .store_backing_req_valid,.store_backing_req_ready,.store_backing_req_id,.store_backing_req_byte_address,.store_backing_req_data,.store_backing_req_word_mask,
  .store_backing_rsp_valid,.store_backing_rsp_ready,.store_backing_rsp_id,.resident_blocks,.resident_warps,
  .native_issue_valid,.native_issue_context,.native_issue_warp,.native_issue_pc
 );
 // elapsed_cycles counts every edge after accepted launch through the edge
 // registering COMPLETE (including the final retirement and drain-check edge).
 // It freezes while COMPLETE is held; no hardware-frequency conversion implied.
 // Completion means all child stores acknowledged, every block retired, and
 // resident reservations zero. Providers must cancel stale returns on reset.
endmodule
```

### 4.52. A common backing-sector gateway

**Role.** The [sector gateway](numerical/multi_sm_sector_gateway.sv) gives several modeled SMs one common backing owner. Its capacity is **one combined read or write transaction**, including a response waiting for client acknowledgment. It is neither a global cache nor an identified physical memory controller.

| Interface or state | Contract |
|---|---|
| Read clients | Per-SM valid/ready, 32-bit ID and aligned byte address; 256-bit response |
| Write clients | Per-SM valid/ready, 32-bit ID/address, 256-bit data and eight-bit nonzero word mask; ID acknowledgment |
| External provider | Separate read/write channels, but at most one combined live gateway record |
| Owner record | SM index, read/write kind, external ID, internal ID, address, write data/mask and returned read data |
| Defaults | Two SM clients; round-robin across their four read/write request positions |

The state sequence is IDLE, SEND, WAIT_REPLY and RETURN. In IDLE, one valid client is accepted and its complete payload captured. This is conventional request valid/ready, not the changing-preview contract of the shared-read hub. The cursor advances on that acceptance. SEND holds the captured backing request until provider acceptance. WAIT_REPLY accepts only the active operation's response channel and checks its internal ID. RETURN restores the saved client ID and holds its response until that client acknowledges. Thus equal external IDs across SMs or read/write clients cannot confuse ownership. No new operation enters while an earlier response is held; no retirement-edge slot reuse is implemented. Addresses must align to 32 bytes, and writes require a nonzero mask. Internal ID exhaustion requires reset.

For the shortest legal transaction, suppose each receiver is ready and the provider offers its reply on the first eligible edge. Edges below name consecutive rising clock edges; provider delay or consumer backpressure extends the corresponding state.

| Edge | Accepted event | State after the edge |
|---|---|---|
| k | Client request and complete payload | SEND |
| k+1 | External backing request | WAIT_REPLY |
| k+2 | Matching actual provider response | RETURN |
| k+3 | Owning client response acknowledgment | IDLE |
| k+4 | Next client request may enter | SEND |

The [gateway unit receipt](numerical/multi_sm_gateway_verification.json) checks 16 returned read words, equal external IDs across clients, captured write payloads, delayed provider responses, held client responses, one combined outstanding transaction and reset/provider flush. A wrong completion ID is rejected. These are transaction tests, not the full-grid numerical oracle. Reset cancels the owner record but cannot undo provider writes already committed. Provider work must be flushed before restart because internal IDs restart from zero. Serialization and round-robin order are development hypotheses, not RTX backing bandwidth.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_multi_sm_sector_gateway.py`.

**Inline behavior.**

```systemverilog
// One shared external memory transaction. Serialization/RR is a hypothesis;
// this is not a measured physical DRAM controller or global cache.
module multi_sm_sector_gateway #(parameter int SMS=2)(
 input logic clk,rst,
 input logic[SMS-1:0]read_req_valid,output logic[SMS-1:0]read_req_ready,
 input logic[31:0]read_req_id[SMS],read_req_byte_address[SMS],
 output logic[SMS-1:0]read_rsp_valid,input logic[SMS-1:0]read_rsp_ready,
 output logic[31:0]read_rsp_id[SMS],output logic[255:0]read_rsp_data[SMS],
 input logic[SMS-1:0]write_req_valid,output logic[SMS-1:0]write_req_ready,
 input logic[31:0]write_req_id[SMS],write_req_byte_address[SMS],
 input logic[255:0]write_req_data[SMS],input logic[7:0]write_req_word_mask[SMS],
 output logic[SMS-1:0]write_rsp_valid,input logic[SMS-1:0]write_rsp_ready,
 output logic[31:0]write_rsp_id[SMS],
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data,
 output logic store_backing_req_valid,input logic store_backing_req_ready,
 output logic[31:0]store_backing_req_id,store_backing_req_byte_address,
 output logic[255:0]store_backing_req_data,output logic[7:0]store_backing_req_word_mask,
 input logic store_backing_rsp_valid,output logic store_backing_rsp_ready,input logic[31:0]store_backing_rsp_id
);
 typedef enum logic[1:0]{IDLE,SEND,WAIT_REPLY,RETURN}state_t;state_t state;
 int cursor,selected,owner;logic kind;
 logic[31:0]next_id,saved_internal_id,saved_external_id,saved_address;
 logic[255:0]saved_data,returned_data;logic[7:0]saved_mask;
 initial if(SMS<1)$fatal(1,"Invalid gateway SM count");
 always_comb begin
  selected=-1;read_req_ready='0;write_req_ready='0;
  for(int offset=0;offset<2*SMS;offset++)begin
   int candidate;candidate=(cursor+offset)%(2*SMS);
   if(!rst&&state==IDLE&&selected<0&&(candidate<SMS?read_req_valid[candidate]:write_req_valid[candidate-SMS]))selected=candidate;
  end
  if(selected>=0)begin
   if(selected<SMS)read_req_ready[selected]=1;else write_req_ready[selected-SMS]=1;
  end
 end
 always_comb begin
  read_rsp_valid='0;write_rsp_valid='0;
  for(int sm=0;sm<SMS;sm++)begin read_rsp_id[sm]=0;write_rsp_id[sm]=0;read_rsp_data[sm]=0;end
  if(!rst&&state==RETURN)begin
   if(kind)begin write_rsp_valid[owner]=1;write_rsp_id[owner]=saved_external_id;end
   else begin read_rsp_valid[owner]=1;read_rsp_id[owner]=saved_external_id;read_rsp_data[owner]=returned_data;end
  end
 end
 assign backing_req_valid=!rst&&state==SEND&&!kind;
 assign store_backing_req_valid=!rst&&state==SEND&&kind;
 assign backing_req_id=saved_internal_id;assign store_backing_req_id=saved_internal_id;
 assign backing_req_byte_address=saved_address;assign store_backing_req_byte_address=saved_address;
 assign store_backing_req_data=saved_data;assign store_backing_req_word_mask=saved_mask;
 assign backing_rsp_ready=!rst&&state==WAIT_REPLY&&!kind;
 assign store_backing_rsp_ready=!rst&&state==WAIT_REPLY&&kind;
 always_ff @(posedge clk)begin
  if(rst)begin state<=IDLE;cursor<=0;owner<=0;kind<=0;next_id<=0;saved_internal_id<=0;saved_external_id<=0;saved_address<=0;saved_data<=0;saved_mask<=0;returned_data<=0;end
  else case(state)
   IDLE:if(selected>=0)begin
    if(&next_id)$fatal(1,"Gateway ID exhausted; reset required");
    owner<=selected%SMS;kind<=selected>=SMS;saved_internal_id<=next_id;next_id<=next_id+1;
    if(selected<SMS)begin
     if(read_req_byte_address[selected][4:0]!=0)$fatal(1,"Unaligned gateway read sector");
     saved_external_id<=read_req_id[selected];saved_address<=read_req_byte_address[selected];saved_data<=0;saved_mask<=0;
    end else begin
     if(write_req_byte_address[selected-SMS][4:0]!=0||write_req_word_mask[selected-SMS]==0)$fatal(1,"Invalid gateway write sector");
     saved_external_id<=write_req_id[selected-SMS];saved_address<=write_req_byte_address[selected-SMS];saved_data<=write_req_data[selected-SMS];saved_mask<=write_req_word_mask[selected-SMS];
    end
    cursor<=(selected+1)%(2*SMS);state<=SEND;
   end
   SEND:if((backing_req_valid&&backing_req_ready)||(store_backing_req_valid&&store_backing_req_ready))state<=WAIT_REPLY;
   WAIT_REPLY:begin
    if(backing_rsp_valid&&backing_rsp_ready)begin
     if(backing_rsp_id!=saved_internal_id)$fatal(1,"Gateway read completion identity mismatch");
     returned_data<=backing_rsp_data;state<=RETURN;
    end
    if(store_backing_rsp_valid&&store_backing_rsp_ready)begin
     if(store_backing_rsp_id!=saved_internal_id)$fatal(1,"Gateway write completion identity mismatch");
     state<=RETURN;
    end
   end
   RETURN:if(kind?write_rsp_ready[owner]:read_rsp_ready[owner])state<=IDLE;
   default:$fatal(1,"Invalid gateway state");
  endcase
 end
 // Owners and all payloads remain held through external/provider/client stalls.
 // Reset cancels the record; provider must flush stale responses before restart.
endmodule
```

### 4.53. Whole-grid dispatch across multiple resident SM models

**Organization.** The [multi-SM controller](numerical/resident_gemm_multi_sm.sv) instantiates two resident complete-block models by default, each with two block contexts. Four live blocks therefore share the common backing gateway while each SM retains its own operand/scratch storage, read hub and MOVM/HMMA services. Each SM also retains its own input cache: 64 sets, eight ways, 128-byte lines and four independently valid 32-byte sectors, or 64 KiB modeled data per SM. **There is no shared global L2 cache in this organization.** The placement and physical interpretation of these private cache instances remain unspecified.

| Interface or quantity | Contract |
|---|---|
| Grid launch/completion | Valid/ready, captured 32-bit ID and A/B/C bases; final completion held until acknowledgment |
| Backing interface | Common read-sector and masked-write-sector channels from section 4.52 |
| Global ledger | Per-block launched/completed bits and dispatched/completed counters |
| Dispatch trace | Block ordinal, row/column and selected SM on actual child acceptance |
| Completion trace | Actual child ordinal/coordinate and returning SM |
| Residency | Sum of child live blocks/warps; defaults permit four blocks and 16 warps |
| Cycle counter | 64-bit model-edge count through final RUN drain check, frozen while completion is held |

Column coordinates change fastest within each block row. A round-robin search finds an SM with child launch readiness; the selected SM is registered before its request is offered and remains the owner under backpressure. Only acceptance increments the global block ordinal. A separate round-robin completion selector acknowledges at most one child per edge. Returned ordinals index the global ledger, permitting out-of-order block completion while rejecting duplicate, unissued or out-of-range IDs. The ledger validates ordinal uniqueness; it does not independently store an expected SM owner for each ordinal. Residency must equal dispatched minus completed blocks. Final completion requires all blocks complete and all SM reservations zero, which follows their actual global store acknowledgments.

The [multi-SM receipt](numerical/resident_multi_sm_verification.json) checks 24,576 final words: two complete M64/N96 grids at K64 and two at K1536. Each grid has six disjoint blocks and 6,144 independent exact integer-dot-product expectations. Every launch reaches four resident blocks, and both SMs issue native instructions. Four invalid-C launch cases are rejected. Launch bases are captured, completion/counter holds are checked and reset occurs at the first pending input read; reset during output stores is not covered. Inputs remain immutable across repeated cache-preserving launches. Partial tiles, the original large grid and arbitrary conflicting output launches are outside current verification.

| Reduction length | First launch model cycles | Repeated launch model cycles |
|---|---:|---:|
| K64 | 28,234 | 17,862 |
| K1536 | 424,384 | 424,392 |

These counts use the same accepted-launch-to-registered-completion boundary as section 4.51, including the final drain-check edge and excluding held completion. They are uncalibrated model outputs. Duplicated SM-local services, private caches, two contexts per SM, one serialized backing gateway and inherited service delays are hypotheses. Cache state and provider phase change between launches, so the comparison does not isolate a physical cache effect or predict RTX multi-SM scaling. Physical counts remain eight identified, 32 partial and 94 unknown.

The [connected-round record](discovery_rounds/multi_sm_connected.json) records the model update and remaining shared-cache and timing gaps.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_resident_gemm_multi_sm.py`.

**Inline behavior.**

```systemverilog
// Complete disjoint grid across explicit resident SM models, one shared memory
// gateway. Serialization, dispatch RR and timing remain uncalibrated hypotheses.
module resident_gemm_multi_sm #(
 parameter int SMS=2,CONTEXTS=2,M=64,N=96,K=64,SETS=64,WAYS=8,
 parameter int READ_SLOTS=2,RETURN_DELAY=9,MOVM_LATENCY=19,HMMA_LATENCY=73,
 parameter int SERVICE_INTERVAL=1,MOVM_INTERVAL=1,HMMA_INTERVAL=4,ARITHMETIC_MODE=1,
 parameter int STORE_INTERVAL=1,STORE_RETURN_DELAY=1,BARRIER_RELEASE_DELAY=1
)(
 input logic clk,rst,launch_valid,output logic launch_ready,
 input logic[31:0]launch_id,a_base,b_base,c_base,
 output logic done_valid,input logic done_ready,output logic[31:0]done_id,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data,
 output logic store_backing_req_valid,input logic store_backing_req_ready,
 output logic[31:0]store_backing_req_id,store_backing_req_byte_address,
 output logic[255:0]store_backing_req_data,output logic[7:0]store_backing_req_word_mask,
 input logic store_backing_rsp_valid,output logic store_backing_rsp_ready,input logic[31:0]store_backing_rsp_id,
 output int resident_blocks,resident_warps,dispatched_blocks,completed_blocks,
 output logic[63:0]elapsed_cycles,
 output logic block_launch_valid,block_done_valid,
 output logic[31:0]block_launch_ordinal,block_launch_row,block_launch_col,
 output logic[31:0]block_done_ordinal,block_done_row,block_done_col,block_launch_sm,block_done_sm,
 output logic[SMS-1:0]sm_native_issue_valid
);
 localparam int TILE_ROWS=M/32,TILE_COLS=N/32,BLOCKS=TILE_ROWS*TILE_COLS;
 typedef enum logic[1:0]{IDLE,RUN,COMPLETE}state_t;
 state_t state;logic[31:0]saved_id,saved_a,saved_b,saved_c;
 logic launched[BLOCKS],completed[BLOCKS];logic launch_legal;
 logic[SMS-1:0]child_launch_valid,child_launch_ready,child_done_valid,child_done_ready;
 logic[31:0]child_id,child_done_id[SMS],child_done_context[SMS],child_result[SMS][4][32][8];
 int launch_owner,launch_cursor,completion_owner,completion_cursor;
 int sm_resident_blocks[SMS],sm_resident_warps[SMS];
 logic[31:0]sm_native_context[SMS],sm_native_warp[SMS],sm_native_pc[SMS];
 logic[SMS-1:0]read_req_valid,read_req_ready,read_rsp_valid,read_rsp_ready,write_req_valid,write_req_ready,write_rsp_valid,write_rsp_ready;
 logic[31:0]read_req_id[SMS],read_req_byte_address[SMS],read_rsp_id[SMS],write_req_id[SMS],write_req_byte_address[SMS],write_rsp_id[SMS];
 logic[255:0]read_rsp_data[SMS],write_req_data[SMS];logic[7:0]write_req_word_mask[SMS];
 initial if(SMS<1||CONTEXTS<1||M<32||N<32||K<32||M%32||N%32||K%32||BLOCKS<1)$fatal(1,"Invalid resident grid geometry");
 always_comb begin
  launch_legal=!a_base[0]&&!b_base[0]&&c_base[1:0]==0;
  if(64'(a_base)+2*64'(M)*64'(K)>64'h100000000||64'(b_base)+2*64'(K)*64'(N)>64'h100000000||64'(c_base)+4*64'(M)*64'(N)>64'h100000000)launch_legal=0;
  if(64'(c_base)<64'(a_base)+2*64'(M)*64'(K)&&64'(a_base)<64'(c_base)+4*64'(M)*64'(N))launch_legal=0;
  if(64'(c_base)<64'(b_base)+2*64'(K)*64'(N)&&64'(b_base)<64'(c_base)+4*64'(M)*64'(N))launch_legal=0;
 end
 assign launch_ready=!rst&&state==IDLE&&launch_legal;
 assign done_valid=!rst&&state==COMPLETE;assign done_id=saved_id;
 assign child_id=32'(dispatched_blocks);
 always_comb begin
  child_launch_valid='0;child_done_ready='0;
  if(!rst&&state==RUN&&launch_owner>=0&&dispatched_blocks<BLOCKS)child_launch_valid[launch_owner]=1;
  completion_owner=-1;
  for(int off=0;off<SMS;off++)begin
   int sm;sm=(completion_cursor+off)%SMS;
   if(!rst&&state==RUN&&completion_owner<0&&child_done_valid[sm])completion_owner=sm;
  end
  if(completion_owner>=0)child_done_ready[completion_owner]=1;
  resident_blocks=0;resident_warps=0;
  for(int sm=0;sm<SMS;sm++)begin resident_blocks+=sm_resident_blocks[sm];resident_warps+=sm_resident_warps[sm];end
 end
 assign block_launch_valid=launch_owner>=0?(child_launch_valid[launch_owner]&&child_launch_ready[launch_owner]):0;
 assign block_launch_ordinal=child_id;assign block_launch_sm=launch_owner>=0?32'(launch_owner):0;
 assign block_launch_row=32'(dispatched_blocks/TILE_COLS);assign block_launch_col=32'(dispatched_blocks%TILE_COLS);
 assign block_done_valid=completion_owner>=0;
 assign block_done_ordinal=completion_owner>=0?child_done_id[completion_owner]:0;
 assign block_done_sm=completion_owner>=0?32'(completion_owner):0;
 assign block_done_row=block_done_ordinal/32'(TILE_COLS);assign block_done_col=block_done_ordinal%32'(TILE_COLS);
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;launch_owner<=-1;launch_cursor<=0;completion_cursor<=0;elapsed_cycles<=0;saved_id<=0;saved_a<=0;saved_b<=0;saved_c<=0;dispatched_blocks<=0;completed_blocks<=0;
   for(int block_index=0;block_index<BLOCKS;block_index++)begin launched[block_index]<=0;completed[block_index]<=0;end
  end else begin
   if(launch_valid&&state==IDLE&&!launch_legal)$fatal(1,"Invalid resident grid launch allocation");
   if(state==RUN&&resident_blocks!=dispatched_blocks-completed_blocks)$fatal(1,"Grid dispatch/retirement conservation failed");
   case(state)
    IDLE:if(launch_valid&&launch_ready)begin
     launch_owner<=-1;launch_cursor<=0;completion_cursor<=0;elapsed_cycles<=0;saved_id<=launch_id;saved_a<=a_base;saved_b<=b_base;saved_c<=c_base;
     dispatched_blocks<=0;completed_blocks<=0;
     for(int block_index=0;block_index<BLOCKS;block_index++)begin launched[block_index]<=0;completed[block_index]<=0;end
     state<=RUN;
    end
    RUN:begin
     elapsed_cycles<=elapsed_cycles+1;
     if(launch_owner<0&&dispatched_blocks<BLOCKS)begin
      int choice;choice=-1;
      for(int off=0;off<SMS;off++)begin int sm;sm=(launch_cursor+off)%SMS;
       if(choice<0&&child_launch_ready[sm])choice=sm;
      end
      if(choice>=0)launch_owner<=choice;
     end
     if(block_launch_valid)begin launch_cursor<=(launch_owner+1)%SMS;launch_owner<=-1;end
     if(block_done_valid)completion_cursor<=(completion_owner+1)%SMS;
     if(block_launch_valid)begin
      if(dispatched_blocks>=BLOCKS||launched[dispatched_blocks])$fatal(1,"Duplicate/out-of-range grid dispatch");
      launched[dispatched_blocks]<=1;dispatched_blocks<=dispatched_blocks+1;
     end
     if(block_done_valid)begin
      if(block_done_ordinal>=BLOCKS)$fatal(1,"Out-of-range grid completion");
      else if(!launched[block_done_ordinal]||completed[block_done_ordinal])$fatal(1,"Unlaunched/duplicate grid completion");
      completed[block_done_ordinal]<=1;completed_blocks<=completed_blocks+1;
     end
     if(dispatched_blocks==BLOCKS&&completed_blocks==BLOCKS&&resident_blocks==0)state<=COMPLETE;
    end
    COMPLETE:if(done_valid&&done_ready)state<=IDLE;
    default:$fatal(1,"Invalid resident grid state");
   endcase
  end
 end
 for(genvar sm=0;sm<SMS;sm++)begin:sm_models
 resident_gemm_complete #(.CONTEXTS(CONTEXTS),.M(M),.N(N),.K(K),.SETS(SETS),.WAYS(WAYS),
  .READ_SLOTS(READ_SLOTS),.RETURN_DELAY(RETURN_DELAY),.MOVM_LATENCY(MOVM_LATENCY),.HMMA_LATENCY(HMMA_LATENCY),
  .SERVICE_INTERVAL(SERVICE_INTERVAL),.MOVM_INTERVAL(MOVM_INTERVAL),.HMMA_INTERVAL(HMMA_INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE),
  .STORE_INTERVAL(STORE_INTERVAL),.STORE_RETURN_DELAY(STORE_RETURN_DELAY),.BARRIER_RELEASE_DELAY(BARRIER_RELEASE_DELAY)) model(
  .clk,.rst,.launch_valid(child_launch_valid[sm]),.launch_ready(child_launch_ready[sm]),.launch_id(child_id),.a_base(saved_a),.b_base(saved_b),.c_base(saved_c),
  .cta_row(32'(dispatched_blocks/TILE_COLS)),.cta_col(32'(dispatched_blocks%TILE_COLS)),
  .done_valid(child_done_valid[sm]),.done_ready(child_done_ready[sm]),.done_id(child_done_id[sm]),.done_context(child_done_context[sm]),.result_registers(child_result[sm]),
  .backing_req_valid(read_req_valid[sm]),.backing_req_ready(read_req_ready[sm]),.backing_req_id(read_req_id[sm]),.backing_req_byte_address(read_req_byte_address[sm]),
  .backing_rsp_valid(read_rsp_valid[sm]),.backing_rsp_ready(read_rsp_ready[sm]),.backing_rsp_id(read_rsp_id[sm]),.backing_rsp_data(read_rsp_data[sm]),
  .store_backing_req_valid(write_req_valid[sm]),.store_backing_req_ready(write_req_ready[sm]),.store_backing_req_id(write_req_id[sm]),.store_backing_req_byte_address(write_req_byte_address[sm]),.store_backing_req_data(write_req_data[sm]),.store_backing_req_word_mask(write_req_word_mask[sm]),
  .store_backing_rsp_valid(write_rsp_valid[sm]),.store_backing_rsp_ready(write_rsp_ready[sm]),.store_backing_rsp_id(write_rsp_id[sm]),.resident_blocks(sm_resident_blocks[sm]),.resident_warps(sm_resident_warps[sm]),
  .native_issue_valid(sm_native_issue_valid[sm]),.native_issue_context(sm_native_context[sm]),.native_issue_warp(sm_native_warp[sm]),.native_issue_pc(sm_native_pc[sm])
 );
 end
 multi_sm_sector_gateway #(.SMS(SMS)) gateway(
  .clk,.rst,.read_req_valid,.read_req_ready,.read_req_id,.read_req_byte_address,.read_rsp_valid,.read_rsp_ready,.read_rsp_id,.read_rsp_data,
  .write_req_valid,.write_req_ready,.write_req_id,.write_req_byte_address,.write_req_data,.write_req_word_mask,.write_rsp_valid,.write_rsp_ready,.write_rsp_id,
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,.backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data,
  .store_backing_req_valid,.store_backing_req_ready,.store_backing_req_id,.store_backing_req_byte_address,.store_backing_req_data,.store_backing_req_word_mask,.store_backing_rsp_valid,.store_backing_rsp_ready,.store_backing_rsp_id
 );
 // elapsed_cycles counts every edge after accepted launch through the edge
 // registering COMPLETE (including the final retirement and drain-check edge).
 // It freezes while COMPLETE is held; no hardware-frequency conversion implied.
 // Completion means all child stores acknowledged, every block retired, and
 // resident reservations zero. Providers must cancel stale returns on reset.
endmodule
```

### 4.54. Shared read-only sector cache after gateway ownership

**Placement and geometry.** The [L2 gateway wrapper](numerical/multi_sm_l2_gateway.sv) connects modeled SMs → common ownership gateway → one shared read-only sector cache → backing provider. The ownership gateway still permits only one combined read/write transaction through client acknowledgment. Reads access one actual `sector_read_cache`; writes bypass it. Defaults are 64 sets, eight ways and 128-byte lines with four independently valid 32-byte sectors: **64 KiB of modeled data**. This is a development geometry, not the physical RTX L2 capacity.

| Interface or quantity | Contract |
|---|---|
| SM read/write clients | Section 4.52's valid/ready IDs, sector addresses, 256-bit packets and write masks |
| Provider reads | Actual aligned 32-byte requests and matching 256-bit returns on misses |
| Shared-cache response | Whole 256-bit sector and retained internal ID, routed through gateway ownership |
| `l2_read_requests` | Cumulative ownership-to-cache request handshakes since reset |
| `l2_read_hits`/`l2_read_misses` | Cumulative cache-to-ownership response handshakes, classified by returned hit flag |
| Cache pending record | One accepted logical cache read not yet returned to ownership |

Valid-sector hits return stored data. A miss issues a backing-sector request and fills only after the actual matching provider response. The cache returns the full sector packet through the ownership gateway. Independent sector valid bits and replacement follow section 4.25's implemented rules; a requested sector does not imply filling all four sectors of its line.

In the current behavioral cache, an accepted hit makes its registered response available immediately after that edge; ownership can accept it at the next edge. There is no separate calibrated L2 hit-delay parameter here. A miss waits for the provider, then registers its returned packet before ownership can accept it.

Request counters increment at cache acceptance, which is later than the original SM-to-gateway acceptance. Hit/miss counters increment when the cache response is accepted by ownership, even if the gateway must subsequently hold that returned response for its client. Held cache responses do not double-count. The invariant is requests = hits + misses + the pending bit. Counters persist between grid launches and clear on reset; writes never increment these read counters.

The [current L2 unit receipt](numerical/multi_sm_l2_gateway_verification.json) checks 40 returned read words, one hit, four misses and four actual backing reads. It checks captured write payloads, delayed provider replies, held client responses, reset/provider flush and wrong-ID rejection. Its read operations are sequential; it does not exhaustively test simultaneous L2 callers. The earlier ownership-gateway unit separately tests multiple-client ownership. The current wrapper also retains one combined transaction limit.

A/B inputs remain immutable and output C is disjoint. There is no write invalidation, dirty data, cross-SM coherence, external invalidation operation or multiple concurrent miss records. Reset cancels cache and gateway state and requires provider flush; it cannot undo committed writes. Shared geometry, replacement, serialization and service timing remain model choices.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_multi_sm_l2_gateway.py`.

**Inline behavior.**

```systemverilog
// One shared read-only sector cache after gateway ownership, before backing.
// Default64sets*8ways*128B=64KiB data (four32B sectors per line),
// test geometry not RTX5090 L2 geometry.
// Writes bypass cache; A/B immutable until reset and C disjoint from cached inputs.
module multi_sm_l2_gateway #(parameter int SMS=2,L2_SETS=64,L2_WAYS=8)(
 input logic clk,rst,
 input logic[SMS-1:0]read_req_valid,output logic[SMS-1:0]read_req_ready,
 input logic[31:0]read_req_id[SMS],read_req_byte_address[SMS],
 output logic[SMS-1:0]read_rsp_valid,input logic[SMS-1:0]read_rsp_ready,
 output logic[31:0]read_rsp_id[SMS],output logic[255:0]read_rsp_data[SMS],
 input logic[SMS-1:0]write_req_valid,output logic[SMS-1:0]write_req_ready,
 input logic[31:0]write_req_id[SMS],write_req_byte_address[SMS],
 input logic[255:0]write_req_data[SMS],input logic[7:0]write_req_word_mask[SMS],
 output logic[SMS-1:0]write_rsp_valid,input logic[SMS-1:0]write_rsp_ready,
 output logic[31:0]write_rsp_id[SMS],
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data,
 output logic store_backing_req_valid,input logic store_backing_req_ready,
 output logic[31:0]store_backing_req_id,store_backing_req_byte_address,
 output logic[255:0]store_backing_req_data,output logic[7:0]store_backing_req_word_mask,
 input logic store_backing_rsp_valid,output logic store_backing_rsp_ready,input logic[31:0]store_backing_rsp_id,
 output int l2_read_requests,l2_read_hits,l2_read_misses
);
 logic cache_req_valid,cache_req_ready,cache_rsp_valid,cache_rsp_ready,cache_rsp_hit;
 logic[31:0]cache_req_id,cache_req_address,cache_rsp_id,cache_rsp_word;
 logic[255:0]cache_rsp_packet;
 logic read_pending;
 multi_sm_sector_gateway #(.SMS(SMS)) ownership(
  .clk,.rst,.read_req_valid,.read_req_ready,.read_req_id,.read_req_byte_address,.read_rsp_valid,.read_rsp_ready,.read_rsp_id,.read_rsp_data,
  .write_req_valid,.write_req_ready,.write_req_id,.write_req_byte_address,.write_req_data,.write_req_word_mask,.write_rsp_valid,.write_rsp_ready,.write_rsp_id,
  .backing_req_valid(cache_req_valid),.backing_req_ready(cache_req_ready),.backing_req_id(cache_req_id),.backing_req_byte_address(cache_req_address),
  .backing_rsp_valid(cache_rsp_valid),.backing_rsp_ready(cache_rsp_ready),.backing_rsp_id(cache_rsp_id),.backing_rsp_data(cache_rsp_packet),
  .store_backing_req_valid,.store_backing_req_ready,.store_backing_req_id,.store_backing_req_byte_address,.store_backing_req_data,.store_backing_req_word_mask,
  .store_backing_rsp_valid,.store_backing_rsp_ready,.store_backing_rsp_id
 );
 sector_read_cache #(.SETS(L2_SETS),.WAYS(L2_WAYS)) l2(
  .clk,.rst,.req_valid(cache_req_valid),.req_ready(cache_req_ready),.req_id(cache_req_id),.req_byte_address(cache_req_address),
  .rsp_valid(cache_rsp_valid),.rsp_ready(cache_rsp_ready),.rsp_id(cache_rsp_id),.rsp_data(cache_rsp_word),.rsp_sector_data(cache_rsp_packet),.rsp_hit(cache_rsp_hit),
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,.backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data
 );
 always_ff @(posedge clk)begin
  if(rst)begin l2_read_requests<=0;l2_read_hits<=0;l2_read_misses<=0;read_pending<=0;end
  else begin
   if(cache_req_valid&&cache_req_ready)begin
    if(read_pending)$fatal(1,"L2 accepted overlapping logical read");
    read_pending<=1;l2_read_requests<=l2_read_requests+1;
   end
   if(cache_rsp_valid&&cache_rsp_ready)begin
    if(!read_pending)$fatal(1,"L2 return has no accepted logical read");
    read_pending<=0;
    if(cache_rsp_hit)l2_read_hits<=l2_read_hits+1;else l2_read_misses<=l2_read_misses+1;
   end
   if(l2_read_requests!=l2_read_hits+l2_read_misses+int'(read_pending))$fatal(1,"L2 logical read count conservation failed");
  end
 end
 // A miss is counted once at returned logical completion, never again at its
 // backing request. Held responses cannot double-count. Reset flushes both layers.
 // No write invalidation, dirty lines, cross-SM coherence or multiple MSHRs.
endmodule
```

### 4.55. Multi-SM grids with shared read-only reuse

**Organization.** The [L2-enabled multi-SM controller](numerical/resident_gemm_multi_sm_l2.sv) preserves two modeled SMs with two resident contexts each and their private 64 KiB input caches. Reads leaving those private caches share section 4.54's single cache after common gateway ownership. Output writes bypass the shared cache. Global dispatch, ordinal completion bookkeeping, actual store acknowledgments and final zero-residency completion retain section 4.53's contracts. The system now has executable shared read reuse; its cache hierarchy and capacities are not identified RTX microarchitecture.

The [current grid receipt](numerical/resident_multi_sm_l2_verification.json) checks 24,576 final FP32 outputs: two full M64/N96 grids at K64 and two at K1536. Each launch has six disjoint output blocks and 6,144 exact expectations from the independent full integer dot product. Both SMs execute work and peak residency reaches four blocks. Four invalid-C launch cases are rejected; captured bases and held completion are checked. Reset coverage remains the first pending input read, not output stores. A/B remain immutable across repeated launches. Partial blocks, the original large grid and arbitrary overlapping output launches are outside current verification.

The following counters are **cumulative since reset**, rather than per-launch traffic:

| Reduction and observation | Cumulative requests | Cumulative hits | Cumulative misses |
|---|---:|---:|---:|
| K64 first launch | 1,280 | 640 | 640 |
| K64 repeated launch | 1,280 | 640 | 640 |
| K1536 first launch | 30,720 | 3,938 | 26,782 |
| K1536 repeated launch | 61,440 | 7,875 | 53,565 |

The unchanged K64 counts show that private-cache replay produces no new ownership-to-shared-cache requests in this model. K1536 counts reflect this declared geometry and request ordering only; they do not establish physical hit rates, cache mapping or replacement policy. Backing fills contain real data, so reuse affects values through executable cache state rather than a fitted hit fraction.

| Reduction length | First launch model cycles | Repeated launch model cycles |
|---|---:|---:|
| K64 | 26,283 | 17,862 |
| K1536 | 457,918 | 457,947 |

These clock-edge counts include the final RUN drain-check edge and freeze during held completion. They are uncalibrated model outputs. Added cache-handshake work, provider phase and reuse interact, so the numbers do not isolate a physical cache effect or predict GPU speedup. Physical counts remain eight identified, 32 partial and 94 unknown; no field is closed by local integration.

The [connected-round record](discovery_rounds/shared_l2_connected.json) records the shared-cache model update, traffic checks and remaining concurrency and timing gaps.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_resident_gemm_multi_sm_l2.py`.

**Inline behavior.**

```systemverilog
// Read-only shared L2 test geometry; immutable inputs, disjoint write-around C.
// Complete disjoint grid across explicit resident SM models, one shared memory
// gateway. Serialization, dispatch RR and timing remain uncalibrated hypotheses.
module resident_gemm_multi_sm_l2 #(
 parameter int L2_SETS=64,L2_WAYS=8,
 parameter int SMS=2,CONTEXTS=2,M=64,N=96,K=64,SETS=64,WAYS=8,
 parameter int READ_SLOTS=2,RETURN_DELAY=9,MOVM_LATENCY=19,HMMA_LATENCY=73,
 parameter int SERVICE_INTERVAL=1,MOVM_INTERVAL=1,HMMA_INTERVAL=4,ARITHMETIC_MODE=1,
 parameter int STORE_INTERVAL=1,STORE_RETURN_DELAY=1,BARRIER_RELEASE_DELAY=1
)(
 input logic clk,rst,launch_valid,output logic launch_ready,
 input logic[31:0]launch_id,a_base,b_base,c_base,
 output logic done_valid,input logic done_ready,output logic[31:0]done_id,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data,
 output logic store_backing_req_valid,input logic store_backing_req_ready,
 output logic[31:0]store_backing_req_id,store_backing_req_byte_address,
 output logic[255:0]store_backing_req_data,output logic[7:0]store_backing_req_word_mask,
 input logic store_backing_rsp_valid,output logic store_backing_rsp_ready,input logic[31:0]store_backing_rsp_id,
 output int resident_blocks,resident_warps,dispatched_blocks,completed_blocks,
 output logic[63:0]elapsed_cycles,
 output logic block_launch_valid,block_done_valid,
 output logic[31:0]block_launch_ordinal,block_launch_row,block_launch_col,
 output logic[31:0]block_done_ordinal,block_done_row,block_done_col,block_launch_sm,block_done_sm,
 output int l2_read_requests,l2_read_hits,l2_read_misses,
 output logic[SMS-1:0]sm_native_issue_valid
);
 localparam int TILE_ROWS=M/32,TILE_COLS=N/32,BLOCKS=TILE_ROWS*TILE_COLS;
 typedef enum logic[1:0]{IDLE,RUN,COMPLETE}state_t;
 state_t state;logic[31:0]saved_id,saved_a,saved_b,saved_c;
 logic launched[BLOCKS],completed[BLOCKS];logic launch_legal;
 logic[SMS-1:0]child_launch_valid,child_launch_ready,child_done_valid,child_done_ready;
 logic[31:0]child_id,child_done_id[SMS],child_done_context[SMS],child_result[SMS][4][32][8];
 int launch_owner,launch_cursor,completion_owner,completion_cursor;
 int sm_resident_blocks[SMS],sm_resident_warps[SMS];
 logic[31:0]sm_native_context[SMS],sm_native_warp[SMS],sm_native_pc[SMS];
 logic[SMS-1:0]read_req_valid,read_req_ready,read_rsp_valid,read_rsp_ready,write_req_valid,write_req_ready,write_rsp_valid,write_rsp_ready;
 logic[31:0]read_req_id[SMS],read_req_byte_address[SMS],read_rsp_id[SMS],write_req_id[SMS],write_req_byte_address[SMS],write_rsp_id[SMS];
 logic[255:0]read_rsp_data[SMS],write_req_data[SMS];logic[7:0]write_req_word_mask[SMS];
 initial if(SMS<1||CONTEXTS<1||M<32||N<32||K<32||M%32||N%32||K%32||BLOCKS<1)$fatal(1,"Invalid resident grid geometry");
 always_comb begin
  launch_legal=!a_base[0]&&!b_base[0]&&c_base[1:0]==0;
  if(64'(a_base)+2*64'(M)*64'(K)>64'h100000000||64'(b_base)+2*64'(K)*64'(N)>64'h100000000||64'(c_base)+4*64'(M)*64'(N)>64'h100000000)launch_legal=0;
  if(64'(c_base)<64'(a_base)+2*64'(M)*64'(K)&&64'(a_base)<64'(c_base)+4*64'(M)*64'(N))launch_legal=0;
  if(64'(c_base)<64'(b_base)+2*64'(K)*64'(N)&&64'(b_base)<64'(c_base)+4*64'(M)*64'(N))launch_legal=0;
 end
 assign launch_ready=!rst&&state==IDLE&&launch_legal;
 assign done_valid=!rst&&state==COMPLETE;assign done_id=saved_id;
 assign child_id=32'(dispatched_blocks);
 always_comb begin
  child_launch_valid='0;child_done_ready='0;
  if(!rst&&state==RUN&&launch_owner>=0&&dispatched_blocks<BLOCKS)child_launch_valid[launch_owner]=1;
  completion_owner=-1;
  for(int off=0;off<SMS;off++)begin
   int sm;sm=(completion_cursor+off)%SMS;
   if(!rst&&state==RUN&&completion_owner<0&&child_done_valid[sm])completion_owner=sm;
  end
  if(completion_owner>=0)child_done_ready[completion_owner]=1;
  resident_blocks=0;resident_warps=0;
  for(int sm=0;sm<SMS;sm++)begin resident_blocks+=sm_resident_blocks[sm];resident_warps+=sm_resident_warps[sm];end
 end
 assign block_launch_valid=launch_owner>=0?(child_launch_valid[launch_owner]&&child_launch_ready[launch_owner]):0;
 assign block_launch_ordinal=child_id;assign block_launch_sm=launch_owner>=0?32'(launch_owner):0;
 assign block_launch_row=32'(dispatched_blocks/TILE_COLS);assign block_launch_col=32'(dispatched_blocks%TILE_COLS);
 assign block_done_valid=completion_owner>=0;
 assign block_done_ordinal=completion_owner>=0?child_done_id[completion_owner]:0;
 assign block_done_sm=completion_owner>=0?32'(completion_owner):0;
 assign block_done_row=block_done_ordinal/32'(TILE_COLS);assign block_done_col=block_done_ordinal%32'(TILE_COLS);
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;launch_owner<=-1;launch_cursor<=0;completion_cursor<=0;elapsed_cycles<=0;saved_id<=0;saved_a<=0;saved_b<=0;saved_c<=0;dispatched_blocks<=0;completed_blocks<=0;
   for(int block_index=0;block_index<BLOCKS;block_index++)begin launched[block_index]<=0;completed[block_index]<=0;end
  end else begin
   if(launch_valid&&state==IDLE&&!launch_legal)$fatal(1,"Invalid resident grid launch allocation");
   if(state==RUN&&resident_blocks!=dispatched_blocks-completed_blocks)$fatal(1,"Grid dispatch/retirement conservation failed");
   case(state)
    IDLE:if(launch_valid&&launch_ready)begin
     launch_owner<=-1;launch_cursor<=0;completion_cursor<=0;elapsed_cycles<=0;saved_id<=launch_id;saved_a<=a_base;saved_b<=b_base;saved_c<=c_base;
     dispatched_blocks<=0;completed_blocks<=0;
     for(int block_index=0;block_index<BLOCKS;block_index++)begin launched[block_index]<=0;completed[block_index]<=0;end
     state<=RUN;
    end
    RUN:begin
     elapsed_cycles<=elapsed_cycles+1;
     if(launch_owner<0&&dispatched_blocks<BLOCKS)begin
      int choice;choice=-1;
      for(int off=0;off<SMS;off++)begin int sm;sm=(launch_cursor+off)%SMS;
       if(choice<0&&child_launch_ready[sm])choice=sm;
      end
      if(choice>=0)launch_owner<=choice;
     end
     if(block_launch_valid)begin launch_cursor<=(launch_owner+1)%SMS;launch_owner<=-1;end
     if(block_done_valid)completion_cursor<=(completion_owner+1)%SMS;
     if(block_launch_valid)begin
      if(dispatched_blocks>=BLOCKS||launched[dispatched_blocks])$fatal(1,"Duplicate/out-of-range grid dispatch");
      launched[dispatched_blocks]<=1;dispatched_blocks<=dispatched_blocks+1;
     end
     if(block_done_valid)begin
      if(block_done_ordinal>=BLOCKS)$fatal(1,"Out-of-range grid completion");
      else if(!launched[block_done_ordinal]||completed[block_done_ordinal])$fatal(1,"Unlaunched/duplicate grid completion");
      completed[block_done_ordinal]<=1;completed_blocks<=completed_blocks+1;
     end
     if(dispatched_blocks==BLOCKS&&completed_blocks==BLOCKS&&resident_blocks==0)state<=COMPLETE;
    end
    COMPLETE:if(done_valid&&done_ready)state<=IDLE;
    default:$fatal(1,"Invalid resident grid state");
   endcase
  end
 end
 for(genvar sm=0;sm<SMS;sm++)begin:sm_models
 resident_gemm_complete #(.CONTEXTS(CONTEXTS),.M(M),.N(N),.K(K),.SETS(SETS),.WAYS(WAYS),
  .READ_SLOTS(READ_SLOTS),.RETURN_DELAY(RETURN_DELAY),.MOVM_LATENCY(MOVM_LATENCY),.HMMA_LATENCY(HMMA_LATENCY),
  .SERVICE_INTERVAL(SERVICE_INTERVAL),.MOVM_INTERVAL(MOVM_INTERVAL),.HMMA_INTERVAL(HMMA_INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE),
  .STORE_INTERVAL(STORE_INTERVAL),.STORE_RETURN_DELAY(STORE_RETURN_DELAY),.BARRIER_RELEASE_DELAY(BARRIER_RELEASE_DELAY)) model(
  .clk,.rst,.launch_valid(child_launch_valid[sm]),.launch_ready(child_launch_ready[sm]),.launch_id(child_id),.a_base(saved_a),.b_base(saved_b),.c_base(saved_c),
  .cta_row(32'(dispatched_blocks/TILE_COLS)),.cta_col(32'(dispatched_blocks%TILE_COLS)),
  .done_valid(child_done_valid[sm]),.done_ready(child_done_ready[sm]),.done_id(child_done_id[sm]),.done_context(child_done_context[sm]),.result_registers(child_result[sm]),
  .backing_req_valid(read_req_valid[sm]),.backing_req_ready(read_req_ready[sm]),.backing_req_id(read_req_id[sm]),.backing_req_byte_address(read_req_byte_address[sm]),
  .backing_rsp_valid(read_rsp_valid[sm]),.backing_rsp_ready(read_rsp_ready[sm]),.backing_rsp_id(read_rsp_id[sm]),.backing_rsp_data(read_rsp_data[sm]),
  .store_backing_req_valid(write_req_valid[sm]),.store_backing_req_ready(write_req_ready[sm]),.store_backing_req_id(write_req_id[sm]),.store_backing_req_byte_address(write_req_byte_address[sm]),.store_backing_req_data(write_req_data[sm]),.store_backing_req_word_mask(write_req_word_mask[sm]),
  .store_backing_rsp_valid(write_rsp_valid[sm]),.store_backing_rsp_ready(write_rsp_ready[sm]),.store_backing_rsp_id(write_rsp_id[sm]),.resident_blocks(sm_resident_blocks[sm]),.resident_warps(sm_resident_warps[sm]),
  .native_issue_valid(sm_native_issue_valid[sm]),.native_issue_context(sm_native_context[sm]),.native_issue_warp(sm_native_warp[sm]),.native_issue_pc(sm_native_pc[sm])
 );
 end
 multi_sm_l2_gateway #(.SMS(SMS),.L2_SETS(L2_SETS),.L2_WAYS(L2_WAYS)) gateway(
  .l2_read_requests,.l2_read_hits,.l2_read_misses,
  .clk,.rst,.read_req_valid,.read_req_ready,.read_req_id,.read_req_byte_address,.read_rsp_valid,.read_rsp_ready,.read_rsp_id,.read_rsp_data,
  .write_req_valid,.write_req_ready,.write_req_id,.write_req_byte_address,.write_req_data,.write_req_word_mask,.write_rsp_valid,.write_rsp_ready,.write_rsp_id,
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,.backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data,
  .store_backing_req_valid,.store_backing_req_ready,.store_backing_req_id,.store_backing_req_byte_address,.store_backing_req_data,.store_backing_req_word_mask,.store_backing_rsp_valid,.store_backing_rsp_ready,.store_backing_rsp_id
 );
 // elapsed_cycles counts every edge after accepted launch through the edge
 // registering COMPLETE (including the final retirement and drain-check edge).
 // It freezes while COMPLETE is held; no hardware-frequency conversion implied.
 // Completion means all child stores acknowledged, every block retired, and
 // resident reservations zero. Providers must cancel stale returns on reset.
endmodule
```

### 4.56. Nonblocking shared sector ownership and refill

**Role and quantitative organization.** The [nonblocking read-only cache](numerical/multi_sm_nonblocking_l2.sv) replaces the single combined ownership record with multiple live client operations and tagged missing-sector fetches. A miss-status holding register, or MSHR, records one missing sector until its actual provider return. Defaults are two SM clients, **eight owner records and four MSHRs**, with 64 sets/eight ways/128-byte lines/four valid sectors: 64 KiB data. These are development choices, not identified RTX queue capacities or geometry.

| Interface or state | Contract |
|---|---|
| Client read | Per-SM valid/ready, 32-bit ID/address; whole 256-bit response |
| Client write | Per-SM valid/ready, 32-bit ID/address, 256-bit data/eight-bit mask; ID acknowledgment |
| Owner record | Client/read-write identity, external ID, completion state, data and MSHR association or tagged write |
| MSHR | Sector address/internal ID, cache set/way/sector and sent state |
| Reply owner | One retained owner index per SM read client and per SM write client |
| Backing offer | One registered read-or-write payload; multiple previously issued records may remain live |
| Counters | Accepted reads, hits, logical misses, merged misses, actual fills, live/peak owners and MSHRs |

**Acceptance and backpressure.** Round-robin admission accepts at most one client operation per edge. A read needs a free owner and either a valid-sector hit, an existing same-address MSHR to join, or a free MSHR plus an eligible cache way. A blocked read is not captured. Ways with live sector refills are pinned against replacement. Writes require a free owner and capture their payload while bypassing cache data. Read sectors must align to 32 bytes; the current code rejects an asserted unaligned request. Invalid write alignment or zero mask is rejected on acceptance. Duplicate live IDs within one read/write client are rejected; equal IDs across separate clients remain legal.

Hits snapshot sector data at acceptance. Joined misses share one fetch but retain separate owners. A new miss reserves its line/sector and tagged MSHR. Actual provider returns match sent internal IDs, fill only their sector, and copy the packet into all waiting owners. Other sectors do not become valid accidentally. A same-edge joined acceptance and refill explicitly forwards that packet into the newly accepted owner. Unknown, duplicate or unsent return IDs are rejected. Returned MSHRs are freed while completed owners can remain live waiting for their clients.

**Completion timing and ordering.** Each client selects its lowest-index completed owner and retains it under response backpressure, independently of other clients. Owner slots use pre-edge free state; retirement does not create same-edge admission capacity. The backing offer is registered and held until provider acceptance. The next offer is inserted on a later edge, giving a minimum unblocked backing-request initiation interval of **two model cycles**, not one. Sent state is registered, so a provider cannot return a newly accepted backing request on that same edge. Tagged later returns may arrive out of request order. These are simulator scheduling rules, not intrinsic GPU latency.

Read-request and hit/miss counters increment together at actual SM read acceptance; merged misses are included in logical misses. `l2_actual_fills` increments on actual tagged provider returns. Therefore requests = hits + misses at every settled edge; fills count returned fetches rather than client acknowledgments. Held replies never repeat those increments. All counts persist until reset. Reset clears ownership, pending refills and cache validity and requires provider flush before internal ID reuse. Immutable A/B and disjoint C are required: no dirty sectors, write coherence or invalidation are implemented.

The [current unit receipt](numerical/multi_sm_nonblocking_l2_verification.json) checks 56 returned words: one hit, six logical misses, two merged misses and four actual fills, plus wrong-return-ID rejection. Its directed operations exercise captured payloads, held client ownership and reset/provider cancellation. Backing arbitration permits at most one combined read/write request acceptance per edge while multiple previously accepted operations remain outstanding. Numerical unit coverage does not identify hardware queues or latency.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_multi_sm_nonblocking_l2.py`.

**Inline behavior.**

```systemverilog
// Shared nonblocking read-only sector cache, write-around output transactions.
// RR issue, owner/MSHR capacities and geometry are simulation choices.
module multi_sm_nonblocking_l2 #(
 parameter int SMS=2,L2_SETS=64,L2_WAYS=8,OWNER_SLOTS=8,MSHRS=4
)(
 input logic clk,rst,
 input logic[SMS-1:0]read_req_valid,output logic[SMS-1:0]read_req_ready,
 input logic[31:0]read_req_id[SMS],read_req_byte_address[SMS],
 output logic[SMS-1:0]read_rsp_valid,input logic[SMS-1:0]read_rsp_ready,
 output logic[31:0]read_rsp_id[SMS],output logic[255:0]read_rsp_data[SMS],
 input logic[SMS-1:0]write_req_valid,output logic[SMS-1:0]write_req_ready,
 input logic[31:0]write_req_id[SMS],write_req_byte_address[SMS],
 input logic[255:0]write_req_data[SMS],input logic[7:0]write_req_word_mask[SMS],
 output logic[SMS-1:0]write_rsp_valid,input logic[SMS-1:0]write_rsp_ready,
 output logic[31:0]write_rsp_id[SMS],
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data,
 output logic store_backing_req_valid,input logic store_backing_req_ready,
 output logic[31:0]store_backing_req_id,store_backing_req_byte_address,
 output logic[255:0]store_backing_req_data,output logic[7:0]store_backing_req_word_mask,
 input logic store_backing_rsp_valid,output logic store_backing_rsp_ready,input logic[31:0]store_backing_rsp_id,
 output int l2_read_requests,l2_read_hits,l2_read_misses,l2_merged_misses,l2_actual_fills,live_owners,live_mshrs,peak_owners,peak_mshrs);
 logic owner_live[OWNER_SLOTS],owner_done[OWNER_SLOTS],owner_write[OWNER_SLOTS],owner_sent[OWNER_SLOTS];
 int owner_client[OWNER_SLOTS],owner_mshr[OWNER_SLOTS];
 logic[31:0]owner_id[OWNER_SLOTS],owner_internal_id[OWNER_SLOTS],owner_address[OWNER_SLOTS];
 logic[255:0]owner_data[OWNER_SLOTS];logic[7:0]owner_mask[OWNER_SLOTS];
 logic mshr_live[MSHRS],mshr_sent[MSHRS];
 int mshr_set[MSHRS],mshr_way[MSHRS],mshr_sector[MSHRS];
 logic[31:0]mshr_address[MSHRS],mshr_id[MSHRS];
 logic line_valid[L2_SETS][L2_WAYS];logic[31:0]line_tag[L2_SETS][L2_WAYS];
 logic[3:0]sector_valid[L2_SETS][L2_WAYS];logic[255:0]sectors[L2_SETS][L2_WAYS][4];
 int victim_cursor[L2_SETS];logic pinned[L2_SETS][L2_WAYS];
 int response_owner[2*SMS],admission_cursor,selected,free_owner,free_mshr;
 int read_set[SMS],read_way[SMS],read_sector[SMS],read_join[SMS];
 logic[31:0]read_tag[SMS];logic read_hit[SMS],read_admissible[SMS];
 logic backend_offer,backend_kind;int backend_owner,backend_mshr,backend_cursor;
 logic[31:0]next_internal_id,backend_id,backend_address;
 logic[255:0]backend_data;logic[7:0]backend_mask;
 int read_return_mshr,write_return_owner;
 initial if(SMS<1||L2_SETS<1||L2_WAYS<1||OWNER_SLOTS<1||MSHRS<1)$fatal(1,"Invalid nonblocking cache geometry");
 always_comb begin
  live_owners=0;free_owner=-1;
  for(int o=0;o<OWNER_SLOTS;o++)begin if(owner_live[o])live_owners++;else if(free_owner<0)free_owner=o;end
  live_mshrs=0;free_mshr=-1;
  for(int m=0;m<MSHRS;m++)begin if(mshr_live[m])live_mshrs++;else if(free_mshr<0)free_mshr=m;end
  for(int s=0;s<L2_SETS;s++)for(int w=0;w<L2_WAYS;w++)begin
   pinned[s][w]=0;
   for(int m=0;m<MSHRS;m++)if(mshr_live[m]&&mshr_set[m]==s&&mshr_way[m]==w)pinned[s][w]=1;
  end
 end
 always_comb begin
  for(int sm=0;sm<SMS;sm++)begin
   int match_way;match_way=-1;
   read_set[sm]=int'((read_req_byte_address[sm]>>7)%32'(L2_SETS));
   read_tag[sm]=read_req_byte_address[sm]/32'(128*L2_SETS);
   read_sector[sm]=int'(read_req_byte_address[sm][6:5]);read_way[sm]=-1;read_join[sm]=-1;
   for(int w=0;w<L2_WAYS;w++)if(line_valid[read_set[sm]][w]&&line_tag[read_set[sm]][w]==read_tag[sm])match_way=w;
   if(match_way>=0)read_way[sm]=match_way;
   for(int w=0;w<L2_WAYS;w++)if(read_way[sm]<0&&!line_valid[read_set[sm]][w]&&!pinned[read_set[sm]][w])read_way[sm]=w;
   for(int offset=0;offset<L2_WAYS;offset++)begin
    int w;w=(victim_cursor[read_set[sm]]+offset)%L2_WAYS;
    if(read_way[sm]<0&&!pinned[read_set[sm]][w])read_way[sm]=w;
   end
   read_hit[sm]=match_way>=0?(sector_valid[read_set[sm]][match_way][read_sector[sm]]):0;
   for(int m=0;m<MSHRS;m++)if(mshr_live[m]&&mshr_address[m]==read_req_byte_address[sm])read_join[sm]=m;
   read_admissible[sm]=read_req_byte_address[sm][4:0]==0&&(read_hit[sm]||read_join[sm]>=0||(free_mshr>=0&&read_way[sm]>=0));
  end
 end
 always_comb begin
  selected=-1;read_req_ready='0;write_req_ready='0;
  for(int offset=0;offset<2*SMS;offset++)begin
   int client;client=(admission_cursor+offset)%(2*SMS);
   if(!rst&&free_owner>=0&&selected<0)begin
    if(client<SMS)begin if(read_req_valid[client]&&read_admissible[client])selected=client;end
    else if(write_req_valid[client-SMS])selected=client;
   end
  end
  if(selected>=0)begin if(selected<SMS)read_req_ready[selected]=1;else write_req_ready[selected-SMS]=1;end
 end
 always_comb begin
  read_rsp_valid='0;write_rsp_valid='0;
  for(int sm=0;sm<SMS;sm++)begin
   read_rsp_id[sm]=0;read_rsp_data[sm]=0;write_rsp_id[sm]=0;
   if(!rst&&response_owner[sm]>=0)begin read_rsp_valid[sm]=1;read_rsp_id[sm]=owner_id[response_owner[sm]];read_rsp_data[sm]=owner_data[response_owner[sm]];end
   if(!rst&&response_owner[SMS+sm]>=0)begin write_rsp_valid[sm]=1;write_rsp_id[sm]=owner_id[response_owner[SMS+sm]];end
  end
 end
 assign backing_req_valid=!rst&&backend_offer&&!backend_kind;
 assign store_backing_req_valid=!rst&&backend_offer&&backend_kind;
 assign backing_req_id=backend_id;assign store_backing_req_id=backend_id;
 assign backing_req_byte_address=backend_address;assign store_backing_req_byte_address=backend_address;
 assign store_backing_req_data=backend_data;assign store_backing_req_word_mask=backend_mask;
 always_comb begin
  read_return_mshr=-1;write_return_owner=-1;
  for(int m=0;m<MSHRS;m++)if(mshr_live[m]&&mshr_sent[m]&&mshr_id[m]==backing_rsp_id)read_return_mshr=m;
  for(int o=0;o<OWNER_SLOTS;o++)if(owner_live[o]&&owner_write[o]&&owner_sent[o]&&!owner_done[o]&&owner_internal_id[o]==store_backing_rsp_id)write_return_owner=o;
 end
 assign backing_rsp_ready=!rst;
 assign store_backing_rsp_ready=!rst;
 always_ff @(posedge clk)begin
  if(rst)begin
   admission_cursor<=0;backend_cursor<=0;next_internal_id<=0;backend_offer<=0;backend_kind<=0;backend_owner<=0;backend_mshr<=0;backend_id<=0;backend_address<=0;backend_data<=0;backend_mask<=0;
   l2_read_requests<=0;l2_read_hits<=0;l2_read_misses<=0;l2_merged_misses<=0;l2_actual_fills<=0;peak_owners<=0;peak_mshrs<=0;
   for(int o=0;o<OWNER_SLOTS;o++)begin owner_live[o]<=0;owner_done[o]<=0;owner_write[o]<=0;owner_sent[o]<=0;owner_client[o]<=0;owner_mshr[o]<=-1;owner_id[o]<=0;owner_internal_id[o]<=0;owner_address[o]<=0;owner_data[o]<=0;owner_mask[o]<=0;end
   for(int m=0;m<MSHRS;m++)begin mshr_live[m]<=0;mshr_sent[m]<=0;mshr_set[m]<=0;mshr_way[m]<=0;mshr_sector[m]<=0;mshr_address[m]<=0;mshr_id[m]<=0;end
   for(int c=0;c<2*SMS;c++)response_owner[c]<=-1;
   for(int s=0;s<L2_SETS;s++)begin victim_cursor[s]<=0;for(int w=0;w<L2_WAYS;w++)begin line_valid[s][w]<=0;line_tag[s][w]<=0;sector_valid[s][w]<=0;end end
  end else begin
   for(int sm=0;sm<SMS;sm++)if(read_req_valid[sm]&&read_req_byte_address[sm][4:0]!=0)$fatal(1,"Unaligned nonblocking read sector");
   if(live_owners>peak_owners)peak_owners<=live_owners;
   if(live_mshrs>peak_mshrs)peak_mshrs<=live_mshrs;
   if(l2_read_requests!=l2_read_hits+l2_read_misses)$fatal(1,"Nonblocking logical cache count mismatch");
   // Each client has a held reply owner independent of every other client.
   for(int c=0;c<2*SMS;c++)begin
    if(response_owner[c]<0)begin
     int choice;choice=-1;
     for(int o=0;o<OWNER_SLOTS;o++)if(choice<0&&owner_live[o]&&owner_done[o]&&owner_client[o]==c)choice=o;
     if(choice>=0)response_owner[c]<=choice;
    end else if(c<SMS?read_rsp_ready[c]:write_rsp_ready[c-SMS])begin owner_live[response_owner[c]]<=0;response_owner[c]<=-1;end
   end
   if(selected>=0)begin
    int sm;sm=selected%SMS;
    for(int o=0;o<OWNER_SLOTS;o++)if(owner_live[o]&&owner_client[o]==selected&&owner_id[o]==(selected<SMS?read_req_id[sm]:write_req_id[sm]))$fatal(1,"Duplicate nonblocking client ownership ID");
    owner_live[free_owner]<=1;owner_client[free_owner]<=selected;owner_id[free_owner]<=selected<SMS?read_req_id[sm]:write_req_id[sm];owner_done[free_owner]<=0;owner_sent[free_owner]<=0;owner_write[free_owner]<=selected>=SMS;owner_mshr[free_owner]<=-1;
    admission_cursor<=(selected+1)%(2*SMS);
    if(selected>=SMS)begin
     if(write_req_byte_address[sm][4:0]!=0||write_req_word_mask[sm]==0)$fatal(1,"Invalid nonblocking write sector");
     if(&next_internal_id)$fatal(1,"Nonblocking ID exhausted");
     owner_internal_id[free_owner]<=next_internal_id;next_internal_id<=next_internal_id+1;owner_address[free_owner]<=write_req_byte_address[sm];owner_data[free_owner]<=write_req_data[sm];owner_mask[free_owner]<=write_req_word_mask[sm];
    end else begin
     l2_read_requests<=l2_read_requests+1;
     if(read_hit[sm])begin l2_read_hits<=l2_read_hits+1;owner_done[free_owner]<=1;owner_data[free_owner]<=sectors[read_set[sm]][read_way[sm]][read_sector[sm]];end
     else begin
      l2_read_misses<=l2_read_misses+1;
      if(read_join[sm]>=0)begin
       l2_merged_misses<=l2_merged_misses+1;owner_mshr[free_owner]<=read_join[sm];
       // A joining acceptance can coincide with its refill return.
       if(backing_rsp_valid&&read_return_mshr==read_join[sm])begin owner_done[free_owner]<=1;owner_data[free_owner]<=backing_rsp_data;owner_mshr[free_owner]<=-1;end
      end else begin
       if(&next_internal_id)$fatal(1,"Nonblocking ID exhausted");
       mshr_live[free_mshr]<=1;mshr_sent[free_mshr]<=0;mshr_id[free_mshr]<=next_internal_id;next_internal_id<=next_internal_id+1;
       mshr_address[free_mshr]<=read_req_byte_address[sm];mshr_set[free_mshr]<=read_set[sm];mshr_way[free_mshr]<=read_way[sm];mshr_sector[free_mshr]<=read_sector[sm];owner_mshr[free_owner]<=free_mshr;
       if(!line_valid[read_set[sm]][read_way[sm]]||line_tag[read_set[sm]][read_way[sm]]!=read_tag[sm])begin line_valid[read_set[sm]][read_way[sm]]<=1;line_tag[read_set[sm]][read_way[sm]]<=read_tag[sm];sector_valid[read_set[sm]][read_way[sm]]<=0;end
       victim_cursor[read_set[sm]]<=(read_way[sm]+1)%L2_WAYS;
      end
     end
    end
   end
   if(!backend_offer)begin
    int choice;choice=-1;
    for(int off=0;off<MSHRS+OWNER_SLOTS;off++)begin
     int index_value;index_value=(backend_cursor+off)%(MSHRS+OWNER_SLOTS);
     if(choice<0)begin
      if(index_value<MSHRS)begin if(mshr_live[index_value]&&!mshr_sent[index_value])choice=index_value;end
      else if(owner_live[index_value-MSHRS]&&owner_write[index_value-MSHRS]&&!owner_sent[index_value-MSHRS])choice=index_value;
     end
    end
    if(choice>=0)begin
     backend_offer<=1;backend_kind<=choice>=MSHRS;
     if(choice<MSHRS)begin backend_mshr<=choice;backend_id<=mshr_id[choice];backend_address<=mshr_address[choice];backend_data<=0;backend_mask<=0;end
     else begin backend_owner<=choice-MSHRS;backend_id<=owner_internal_id[choice-MSHRS];backend_address<=owner_address[choice-MSHRS];backend_data<=owner_data[choice-MSHRS];backend_mask<=owner_mask[choice-MSHRS];end
     backend_cursor<=(choice+1)%(MSHRS+OWNER_SLOTS);
    end
   end else if((backing_req_valid&&backing_req_ready)||(store_backing_req_valid&&store_backing_req_ready))begin
    backend_offer<=0;if(backend_kind)owner_sent[backend_owner]<=1;else mshr_sent[backend_mshr]<=1;
   end
   if(backing_rsp_valid)begin
    if(read_return_mshr<0)$fatal(1,"Nonblocking read completion identity mismatch");
    else begin
     l2_actual_fills<=l2_actual_fills+1;mshr_live[read_return_mshr]<=0;
     sectors[mshr_set[read_return_mshr]][mshr_way[read_return_mshr]][mshr_sector[read_return_mshr]]<=backing_rsp_data;
     sector_valid[mshr_set[read_return_mshr]][mshr_way[read_return_mshr]][mshr_sector[read_return_mshr]]<=1;
     for(int o=0;o<OWNER_SLOTS;o++)if(owner_live[o]&&!owner_write[o]&&!owner_done[o]&&owner_mshr[o]==read_return_mshr)begin owner_done[o]<=1;owner_data[o]<=backing_rsp_data;owner_mshr[o]<=-1;end
    end
   end
   if(store_backing_rsp_valid)begin
    if(write_return_owner<0)$fatal(1,"Nonblocking write completion identity mismatch");
    else owner_done[write_return_owner]<=1;
   end
  end
 end
 // Logical misses include merged requests. Actual fills count returned fetches,
 // not owner acknowledgments; hits capture data at acceptance. Refill lines pin
 // their ways until all live sectors return. IDs reset only with provider flush.
 // No coherence/write invalidation. Cached inputs remain immutable until reset.
endmodule
```

### 4.57. Multi-SM grids with overlapping shared-cache requests

**Organization.** The [nonblocking grid top](numerical/resident_gemm_multi_sm_nb_l2.sv) preserves two modeled SMs/two contexts each, private input caches, shared native services within each SM, and the whole-grid ownership ledger. Its common memory component is section 4.56 rather than the serialized gateway. Output writes bypass the read-only data cache but occupy owner records and require actual acknowledgment. The independent backing provider used for verification has four tagged records and permits out-of-order returns. None of these capacities establishes physical RTX backing concurrency.

The [current full-grid receipt](numerical/resident_multi_sm_nb_l2_verification.json) checks 24,576 final words: two complete M64/N96 grids at each K64/K1536, using the independent full integer-dot-product oracle. Peak residency is four blocks, and all four invalid-C launch cases are rejected. Captured launch bases and held completion are checked; reset coverage remains only the first pending input read. Output-store reset, the original large grid, partial blocks and coherence are not verified.

Cache counters below are cumulative since reset, including both launches:

| K and observation | Requests | Hits | Logical misses | Merged misses | Actual fills |
|---|---:|---:|---:|---:|---:|
| K64 first | 1,024 | 264 | 760 | 120 | 640 |
| K64 repeated | 1,280 | 520 | 760 | 120 | 640 |
| K1536 first | 33,792 | 5,140 | 28,652 | 4,076 | 24,576 |
| K1536 repeated | 67,584 | 10,283 | 57,301 | 8,149 | 49,152 |

For example, the first K64 observation has 760 logical misses but only 640 fills because 120 requests join outstanding sectors. This is executable sharing of actual returned data, not a fitted hit fraction. The request ordering and private-cache state also change which reads reach this layer; comparisons with earlier model variants do not isolate physical cache behavior.

| Reduction length | First launch model cycles | Repeated launch model cycles |
|---|---:|---:|
| K64 | 26,731 | 16,154 |
| K1536 | 582,963 | 583,000 |

The accepted-launch-to-registered-completion counter includes the final drain-check edge and freezes while completion is held. These are uncalibrated model results. More outstanding state does not guarantee fewer model cycles, and these values do not predict GPU scaling. Physical evidence remains eight identified fields, 32 partial and 94 unknown.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_resident_gemm_multi_sm_nb_l2.py`.

**Inline behavior.**

```systemverilog
// Read-only shared L2 test geometry; immutable inputs, disjoint write-around C.
// Complete disjoint grid across explicit resident SM models, one shared memory
// gateway. Serialization, dispatch RR and timing remain uncalibrated hypotheses.
module resident_gemm_multi_sm_nb_l2 #(
 parameter int L2_SETS=64,L2_WAYS=8,OWNER_SLOTS=8,MSHRS=4,
 parameter int SMS=2,CONTEXTS=2,M=64,N=96,K=64,SETS=64,WAYS=8,
 parameter int READ_SLOTS=2,RETURN_DELAY=9,MOVM_LATENCY=19,HMMA_LATENCY=73,
 parameter int SERVICE_INTERVAL=1,MOVM_INTERVAL=1,HMMA_INTERVAL=4,ARITHMETIC_MODE=1,
 parameter int STORE_INTERVAL=1,STORE_RETURN_DELAY=1,BARRIER_RELEASE_DELAY=1
)(
 input logic clk,rst,launch_valid,output logic launch_ready,
 input logic[31:0]launch_id,a_base,b_base,c_base,
 output logic done_valid,input logic done_ready,output logic[31:0]done_id,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data,
 output logic store_backing_req_valid,input logic store_backing_req_ready,
 output logic[31:0]store_backing_req_id,store_backing_req_byte_address,
 output logic[255:0]store_backing_req_data,output logic[7:0]store_backing_req_word_mask,
 input logic store_backing_rsp_valid,output logic store_backing_rsp_ready,input logic[31:0]store_backing_rsp_id,
 output int resident_blocks,resident_warps,dispatched_blocks,completed_blocks,
 output logic[63:0]elapsed_cycles,
 output logic block_launch_valid,block_done_valid,
 output logic[31:0]block_launch_ordinal,block_launch_row,block_launch_col,
 output logic[31:0]block_done_ordinal,block_done_row,block_done_col,block_launch_sm,block_done_sm,
 output int l2_read_requests,l2_read_hits,l2_read_misses,l2_merged_misses,l2_actual_fills,live_owners,live_mshrs,peak_owners,peak_mshrs,
 output logic[SMS-1:0]sm_native_issue_valid
);
 localparam int TILE_ROWS=M/32,TILE_COLS=N/32,BLOCKS=TILE_ROWS*TILE_COLS;
 typedef enum logic[1:0]{IDLE,RUN,COMPLETE}state_t;
 state_t state;logic[31:0]saved_id,saved_a,saved_b,saved_c;
 logic launched[BLOCKS],completed[BLOCKS];logic launch_legal;
 logic[SMS-1:0]child_launch_valid,child_launch_ready,child_done_valid,child_done_ready;
 logic[31:0]child_id,child_done_id[SMS],child_done_context[SMS],child_result[SMS][4][32][8];
 int launch_owner,launch_cursor,completion_owner,completion_cursor;
 int sm_resident_blocks[SMS],sm_resident_warps[SMS];
 logic[31:0]sm_native_context[SMS],sm_native_warp[SMS],sm_native_pc[SMS];
 logic[SMS-1:0]read_req_valid,read_req_ready,read_rsp_valid,read_rsp_ready,write_req_valid,write_req_ready,write_rsp_valid,write_rsp_ready;
 logic[31:0]read_req_id[SMS],read_req_byte_address[SMS],read_rsp_id[SMS],write_req_id[SMS],write_req_byte_address[SMS],write_rsp_id[SMS];
 logic[255:0]read_rsp_data[SMS],write_req_data[SMS];logic[7:0]write_req_word_mask[SMS];
 initial if(SMS<1||CONTEXTS<1||M<32||N<32||K<32||M%32||N%32||K%32||BLOCKS<1)$fatal(1,"Invalid resident grid geometry");
 always_comb begin
  launch_legal=!a_base[0]&&!b_base[0]&&c_base[1:0]==0;
  if(64'(a_base)+2*64'(M)*64'(K)>64'h100000000||64'(b_base)+2*64'(K)*64'(N)>64'h100000000||64'(c_base)+4*64'(M)*64'(N)>64'h100000000)launch_legal=0;
  if(64'(c_base)<64'(a_base)+2*64'(M)*64'(K)&&64'(a_base)<64'(c_base)+4*64'(M)*64'(N))launch_legal=0;
  if(64'(c_base)<64'(b_base)+2*64'(K)*64'(N)&&64'(b_base)<64'(c_base)+4*64'(M)*64'(N))launch_legal=0;
 end
 assign launch_ready=!rst&&state==IDLE&&launch_legal;
 assign done_valid=!rst&&state==COMPLETE;assign done_id=saved_id;
 assign child_id=32'(dispatched_blocks);
 always_comb begin
  child_launch_valid='0;child_done_ready='0;
  if(!rst&&state==RUN&&launch_owner>=0&&dispatched_blocks<BLOCKS)child_launch_valid[launch_owner]=1;
  completion_owner=-1;
  for(int off=0;off<SMS;off++)begin
   int sm;sm=(completion_cursor+off)%SMS;
   if(!rst&&state==RUN&&completion_owner<0&&child_done_valid[sm])completion_owner=sm;
  end
  if(completion_owner>=0)child_done_ready[completion_owner]=1;
  resident_blocks=0;resident_warps=0;
  for(int sm=0;sm<SMS;sm++)begin resident_blocks+=sm_resident_blocks[sm];resident_warps+=sm_resident_warps[sm];end
 end
 assign block_launch_valid=launch_owner>=0?(child_launch_valid[launch_owner]&&child_launch_ready[launch_owner]):0;
 assign block_launch_ordinal=child_id;assign block_launch_sm=launch_owner>=0?32'(launch_owner):0;
 assign block_launch_row=32'(dispatched_blocks/TILE_COLS);assign block_launch_col=32'(dispatched_blocks%TILE_COLS);
 assign block_done_valid=completion_owner>=0;
 assign block_done_ordinal=completion_owner>=0?child_done_id[completion_owner]:0;
 assign block_done_sm=completion_owner>=0?32'(completion_owner):0;
 assign block_done_row=block_done_ordinal/32'(TILE_COLS);assign block_done_col=block_done_ordinal%32'(TILE_COLS);
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;launch_owner<=-1;launch_cursor<=0;completion_cursor<=0;elapsed_cycles<=0;saved_id<=0;saved_a<=0;saved_b<=0;saved_c<=0;dispatched_blocks<=0;completed_blocks<=0;
   for(int block_index=0;block_index<BLOCKS;block_index++)begin launched[block_index]<=0;completed[block_index]<=0;end
  end else begin
   if(launch_valid&&state==IDLE&&!launch_legal)$fatal(1,"Invalid resident grid launch allocation");
   if(state==RUN&&resident_blocks!=dispatched_blocks-completed_blocks)$fatal(1,"Grid dispatch/retirement conservation failed");
   case(state)
    IDLE:if(launch_valid&&launch_ready)begin
     launch_owner<=-1;launch_cursor<=0;completion_cursor<=0;elapsed_cycles<=0;saved_id<=launch_id;saved_a<=a_base;saved_b<=b_base;saved_c<=c_base;
     dispatched_blocks<=0;completed_blocks<=0;
     for(int block_index=0;block_index<BLOCKS;block_index++)begin launched[block_index]<=0;completed[block_index]<=0;end
     state<=RUN;
    end
    RUN:begin
     elapsed_cycles<=elapsed_cycles+1;
     if(launch_owner<0&&dispatched_blocks<BLOCKS)begin
      int choice;choice=-1;
      for(int off=0;off<SMS;off++)begin int sm;sm=(launch_cursor+off)%SMS;
       if(choice<0&&child_launch_ready[sm])choice=sm;
      end
      if(choice>=0)launch_owner<=choice;
     end
     if(block_launch_valid)begin launch_cursor<=(launch_owner+1)%SMS;launch_owner<=-1;end
     if(block_done_valid)completion_cursor<=(completion_owner+1)%SMS;
     if(block_launch_valid)begin
      if(dispatched_blocks>=BLOCKS||launched[dispatched_blocks])$fatal(1,"Duplicate/out-of-range grid dispatch");
      launched[dispatched_blocks]<=1;dispatched_blocks<=dispatched_blocks+1;
     end
     if(block_done_valid)begin
      if(block_done_ordinal>=BLOCKS)$fatal(1,"Out-of-range grid completion");
      else if(!launched[block_done_ordinal]||completed[block_done_ordinal])$fatal(1,"Unlaunched/duplicate grid completion");
      completed[block_done_ordinal]<=1;completed_blocks<=completed_blocks+1;
     end
     if(dispatched_blocks==BLOCKS&&completed_blocks==BLOCKS&&resident_blocks==0)state<=COMPLETE;
    end
    COMPLETE:if(done_valid&&done_ready)state<=IDLE;
    default:$fatal(1,"Invalid resident grid state");
   endcase
  end
 end
 for(genvar sm=0;sm<SMS;sm++)begin:sm_models
 resident_gemm_complete #(.CONTEXTS(CONTEXTS),.M(M),.N(N),.K(K),.SETS(SETS),.WAYS(WAYS),
  .READ_SLOTS(READ_SLOTS),.RETURN_DELAY(RETURN_DELAY),.MOVM_LATENCY(MOVM_LATENCY),.HMMA_LATENCY(HMMA_LATENCY),
  .SERVICE_INTERVAL(SERVICE_INTERVAL),.MOVM_INTERVAL(MOVM_INTERVAL),.HMMA_INTERVAL(HMMA_INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE),
  .STORE_INTERVAL(STORE_INTERVAL),.STORE_RETURN_DELAY(STORE_RETURN_DELAY),.BARRIER_RELEASE_DELAY(BARRIER_RELEASE_DELAY)) model(
  .clk,.rst,.launch_valid(child_launch_valid[sm]),.launch_ready(child_launch_ready[sm]),.launch_id(child_id),.a_base(saved_a),.b_base(saved_b),.c_base(saved_c),
  .cta_row(32'(dispatched_blocks/TILE_COLS)),.cta_col(32'(dispatched_blocks%TILE_COLS)),
  .done_valid(child_done_valid[sm]),.done_ready(child_done_ready[sm]),.done_id(child_done_id[sm]),.done_context(child_done_context[sm]),.result_registers(child_result[sm]),
  .backing_req_valid(read_req_valid[sm]),.backing_req_ready(read_req_ready[sm]),.backing_req_id(read_req_id[sm]),.backing_req_byte_address(read_req_byte_address[sm]),
  .backing_rsp_valid(read_rsp_valid[sm]),.backing_rsp_ready(read_rsp_ready[sm]),.backing_rsp_id(read_rsp_id[sm]),.backing_rsp_data(read_rsp_data[sm]),
  .store_backing_req_valid(write_req_valid[sm]),.store_backing_req_ready(write_req_ready[sm]),.store_backing_req_id(write_req_id[sm]),.store_backing_req_byte_address(write_req_byte_address[sm]),.store_backing_req_data(write_req_data[sm]),.store_backing_req_word_mask(write_req_word_mask[sm]),
  .store_backing_rsp_valid(write_rsp_valid[sm]),.store_backing_rsp_ready(write_rsp_ready[sm]),.store_backing_rsp_id(write_rsp_id[sm]),.resident_blocks(sm_resident_blocks[sm]),.resident_warps(sm_resident_warps[sm]),
  .native_issue_valid(sm_native_issue_valid[sm]),.native_issue_context(sm_native_context[sm]),.native_issue_warp(sm_native_warp[sm]),.native_issue_pc(sm_native_pc[sm])
 );
 end
 multi_sm_nonblocking_l2 #(.SMS(SMS),.L2_SETS(L2_SETS),.L2_WAYS(L2_WAYS),.OWNER_SLOTS(OWNER_SLOTS),.MSHRS(MSHRS)) gateway(
  .l2_read_requests,.l2_read_hits,.l2_read_misses,.l2_merged_misses,.l2_actual_fills,.live_owners,.live_mshrs,.peak_owners,.peak_mshrs,
  .clk,.rst,.read_req_valid,.read_req_ready,.read_req_id,.read_req_byte_address,.read_rsp_valid,.read_rsp_ready,.read_rsp_id,.read_rsp_data,
  .write_req_valid,.write_req_ready,.write_req_id,.write_req_byte_address,.write_req_data,.write_req_word_mask,.write_rsp_valid,.write_rsp_ready,.write_rsp_id,
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,.backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data,
  .store_backing_req_valid,.store_backing_req_ready,.store_backing_req_id,.store_backing_req_byte_address,.store_backing_req_data,.store_backing_req_word_mask,.store_backing_rsp_valid,.store_backing_rsp_ready,.store_backing_rsp_id
 );
 // elapsed_cycles counts every edge after accepted launch through the edge
 // registering COMPLETE (including the final retirement and drain-check edge).
 // It freezes while COMPLETE is held; no hardware-frequency conversion implied.
 // Completion means all child stores acknowledged, every block retired, and
 // resident reservations zero. Providers must cancel stale returns on reset.
endmodule
```

### 4.58. Effective dependent-operation replay

**Purpose and measurement boundary.** The [dependency replay](numerical/dependency_probe_replay.sv) executes actual repeated MOVM transformations or scalar shared-memory pointer reads with a configured successive-dependency spacing. It makes measured effective cost executable without interpreting that cost as intrinsic hardware latency. The saved MOVM observation is 29,684 net cycles/1,024 operations = 28.98828125 cycles per operation, rounded to 29. It includes loop/timer work, and `end_timer_waits_final_result = false`: the timer does not await the final result. Using a 29-cycle result return to enable the next dependent issue is therefore a calibration convention, not identified final-return latency or exact reproduction of the historical timer interval. Scalar shared loads use a 28-cycle effective recurrence including return, wakeup, issue and native-control effects. Neither value identifies independent throughput.

| Interface or parameter | Contract |
|---|---|
| Launch | Valid/ready, 32-bit ID, two-bit opcode and 32 input words or byte addresses; opcode zero MOVM, one LDS |
| Shared writes | Aligned 32-bit words into an initialized 32 KiB array, only while IDLE |
| Result | 32 actual transformed/read words and retained ID, held until acknowledgment |
| Trace | Actual operation admission pulse, ordinal and opcode |
| Defaults | 1,024 operations; MOVM recurrence 29 and LDS recurrence 28 model cycles |
| Timing mode | Effective mode zero only; nonzero extra issue/wakeup/cache costs are rejected |

Acceptance captures inputs and enters RUN. The first operation issues on the following edge. Each actual return updates the chain values; direct forwarding permits the next admission on that same return edge. MOVM uses the measured word transformation, while LDS reads actual initialized words and uses their values as future byte addresses. All 32 LDS addresses must be aligned, in range and mapped to distinct banks. The model excludes conflicting/multiwarp/global/cache paths. Launch and shared write cannot share an edge. The last actual return enters DONE; elapsed cycles then freeze while completion is held. Reset clears state and initialization.

For N operations and recurrence R, first-to-last admission spans `(N − 1) × R`, first admission to final return spans `N × R`, and accepted launch to registered DONE spans `1 + N × R`. These are explicit simulator edges, not the historical probe's timer endpoints:

| Operation/count | First-to-last admission | First-to-final return | Launch-to-DONE |
|---|---:|---:|---:|
| MOVM / 37 | 1,044 | 1,073 | 1,074 |
| LDS / 37 | 1,008 | 1,036 | 1,037 |
| MOVM / 1,024 | 29,667 | 29,696 | 29,697 |
| LDS / 1,024 | 28,644 | 28,672 | 28,673 |

The [replay receipt](numerical/dependency_probe_verification.json) checks 128 output words across these cases with an independent repeated coordinate-transpose oracle and a 32-address pointer ring. Unsupported timing mode and double charging are rejected. This validates implementation of the configured recurrence, not independent hardware timing. In particular, 29,696 final-return cycles must not be compared directly with the 29,684 historical net timer count as matching endpoints. The 0.01171875-cycle rounding difference per MOVM operation is approximately 0.0404% of its measured average; that is rounding error, not GEMM prediction error.

Effective costs cannot be charged again as intrinsic service latency plus separate included overhead. Their transfer to GEMM remains unvalidated because scheduling, dependencies and competition differ. The separate phase-composition model’s largest recorded error remains 5.966342%; physical counts remain eight identified, 32 partial and 94 unknown. No new hardware evidence is added by this replay.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_dependency_probe_replay.py`.

**Inline behavior.**

```systemverilog
// Effective issue-to-next-dependent-issue recurrences, one full dependent warp.
// MOVM28.98828125 rounded to29 integer cycles; direct conflict-free LDS32 uses28.
// MOVM source timer did NOT wait for final result;29 is a provisional rounded
// successive-admission spacing, not measured final return latency. Using return
// to enable the dependent issue is an explicit model choice. N*29 is NOT an
// experimentally validated total duration.
// These include measured issue/wakeup/compiler scheduling, not intrinsic unit
// latency. Do not add cache/issue/wakeup delays or infer independent throughput.
module dependency_probe_replay #(
 parameter int OPERATIONS=1024,TIMING_MODE=0,MOVM_RECURRENCE=29,LDS_RECURRENCE=28,
 parameter int EXTRA_ISSUE_CYCLES=0,EXTRA_WAKEUP_CYCLES=0,EXTRA_CACHE_CYCLES=0
)(
 input logic clk,rst,launch_valid,output logic launch_ready,
 input logic[31:0]launch_id,input logic[1:0]opcode,
 input logic[31:0]input_words[32],byte_addresses[32],
 input logic write_valid,output logic write_ready,input logic[31:0]write_byte_address,write_data,
 output logic done_valid,input logic done_ready,output logic[31:0]done_id,result_words[32],
 output logic issue_valid,output logic[31:0]issue_id,output logic[1:0]issue_opcode,
 output logic[63:0]elapsed_cycles
);
 typedef enum logic[1:0]{IDLE,RUN,DONE}state_t;state_t state;
 logic[31:0]memory[8192];logic initialized[8192];
 logic[31:0]saved_id,chain_words[32];logic[1:0]saved_opcode;
 int issued_count,returned_count,cycle;
 logic mov_req_valid,mov_req_ready,mov_rsp_valid,mov_rsp_ready;
 logic[31:0]mov_inputs[32],mov_outputs[32],mov_rsp_id;int mov_outstanding;
 logic lds_pending,lds_return_valid;int lds_due;logic[31:0]lds_values[32],lds_return_id;
 logic return_valid;logic[31:0]return_id,return_words[32],next_inputs[32];
 initial begin
  if(TIMING_MODE!=0||EXTRA_ISSUE_CYCLES!=0||EXTRA_WAKEUP_CYCLES!=0||EXTRA_CACHE_CYCLES!=0)$fatal(1,"Effective recurrence rejects decomposed/additional timing");
  if(OPERATIONS<1||MOVM_RECURRENCE<1||LDS_RECURRENCE<1)$fatal(1,"Invalid dependency replay length/timing");
 end
 assign launch_ready=!rst&&state==IDLE;
 assign write_ready=!rst&&state==IDLE&&write_byte_address[1:0]==0&&write_byte_address<=32764;
 assign done_valid=!rst&&state==DONE;assign done_id=saved_id;
 assign lds_return_valid=!rst&&state==RUN&&lds_pending&&cycle>=lds_due;
 assign return_valid=saved_opcode==0?mov_rsp_valid:lds_return_valid;
 assign return_id=saved_opcode==0?mov_rsp_id:lds_return_id;
 always_comb for(int lane=0;lane<32;lane++)begin
  return_words[lane]=saved_opcode==0?mov_outputs[lane]:lds_values[lane];
  next_inputs[lane]=issued_count==0?chain_words[lane]:return_words[lane];
  mov_inputs[lane]=next_inputs[lane];
 end
 // Direct forwarding allows the next issue on the exact return-acceptance edge.
 // Launch/snapshot and final held response are separately visible overhead;
 // they are never charged again to each measured recurrence.
 assign issue_valid=!rst&&state==RUN&&issued_count<OPERATIONS&&(issued_count==0||return_valid)&&(saved_opcode==1||mov_req_ready);
 assign issue_id=32'(issued_count);assign issue_opcode=saved_opcode;
 assign mov_req_valid=issue_valid&&saved_opcode==0;
 assign mov_rsp_ready=!rst&&state==RUN&&saved_opcode==0;
 native_movm_word_pipeline #(.SLOTS(2),.LATENCY(MOVM_RECURRENCE),.INTERVAL(1)) movm(
  .clk,.rst,.req_valid(mov_req_valid),.req_ready(mov_req_ready),.req_id(issue_id),.input_words(mov_inputs),
  .rsp_valid(mov_rsp_valid),.rsp_ready(mov_rsp_ready),.rsp_id(mov_rsp_id),.output_words(mov_outputs),.outstanding(mov_outstanding));
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;saved_id<=0;saved_opcode<=0;issued_count<=0;returned_count<=0;cycle<=0;elapsed_cycles<=0;lds_pending<=0;lds_due<=0;lds_return_id<=0;
   for(int word=0;word<8192;word++)initialized[word]<=0;
   for(int lane=0;lane<32;lane++)begin chain_words[lane]<=0;result_words[lane]<=0;lds_values[lane]<=0;end
  end else begin
   cycle<=cycle+1;
   if(write_valid&&(write_byte_address[1:0]!=0||write_byte_address>32764))$fatal(1,"Invalid replay shared write");
   if(write_valid&&write_ready)begin memory[write_byte_address/4]<=write_data;initialized[write_byte_address/4]<=1;end
   case(state)
    IDLE:if(launch_valid&&launch_ready)begin
     if(opcode>1)$fatal(1,"Unsupported dependency replay opcode");
     if(write_valid)$fatal(1,"Replay launch and memory write cannot share edge");
     saved_id<=launch_id;saved_opcode<=opcode;issued_count<=0;returned_count<=0;elapsed_cycles<=0;state<=RUN;
     for(int lane=0;lane<32;lane++)chain_words[lane]<=opcode==0?input_words[lane]:byte_addresses[lane];
    end
    RUN:begin
     elapsed_cycles<=elapsed_cycles+1;
     if(return_valid)begin
      if(return_id!=32'(returned_count)||returned_count>=issued_count)$fatal(1,"Dependency return identity mismatch");
      returned_count<=returned_count+1;
      for(int lane=0;lane<32;lane++)begin chain_words[lane]<=return_words[lane];result_words[lane]<=return_words[lane];end
      if(saved_opcode==1)lds_pending<=0;
      if(returned_count==OPERATIONS-1)state<=DONE;
     end
     if(issue_valid)begin
      issued_count<=issued_count+1;
      if(saved_opcode==1)begin
       for(int lane=0;lane<32;lane++)begin
        if(next_inputs[lane][1:0]!=0||next_inputs[lane]>32764)$fatal(1,"LDS pointer outside aligned shared memory");
        else if(!initialized[next_inputs[lane]/4])$fatal(1,"LDS pointer reads uninitialized shared word");
        for(int earlier=0;earlier<lane;earlier++)if((next_inputs[lane]/4)%32==(next_inputs[earlier]/4)%32)$fatal(1,"Replay LDS scope requires distinct32banks");
        lds_values[lane]<=memory[next_inputs[lane]/4];
       end
       lds_pending<=1;lds_due<=cycle+LDS_RECURRENCE;lds_return_id<=issue_id;
      end
     end
    end
    DONE:if(done_valid&&done_ready)state<=IDLE;
    default:$fatal(1,"Invalid dependency replay state");
   endcase
  end
 end
 // LDS values are memory reads and become future dependent byte addresses.
 // Native cache/global/conflicting/multiwarp paths and full GEMM are excluded.
endmodule
```

## 5. Build and verification procedure

### 5.1 Compile the component testbench

From the project root, build in a temporary directory:

```sh
verilator --binary --timing -Wno-fatal --top-module components_tb \
  --Mdir /tmp/rtx5090-rtl-components-build \
  studies/rtx5090_gemm_milp/rtl/components/hardware_blocks.sv \
  studies/rtx5090_gemm_milp/rtl/components/components_tb.sv
```

Then run:

```sh
/tmp/rtx5090-rtl-components-build/Vcomponents_tb
```

The executable must terminate successfully and print:

```text
COMPONENT_TESTS_PASS scheduler shared_values cache_reuse queue_capacity backpressure barrier
```

`-Wno-fatal` permits lint warnings during this behavioral build; it does not certify warning-free RTL. The multi-module source produces naming/multiple-top warnings under whole-library lint, and some wider index bits are unused. Inspect other warnings when changing interfaces or configuration. Source compilation alone is not a behavioral test.

Run the separate connected register/completion checks from the project root:

```text
python studies/rtx5090_gemm_milp/rtl/components/verify_completion_path.py
```

The runner builds three synthetic-delay variants in temporary directories, checks five expected failures, and saves source hashes and results. It disables core dumps for intentional assertion failures. Builds permit warnings; their logs are retained beside the receipt. These local checks use no GPU or network connection.

Run the separate numerical matrix checks:

```text
python studies/rtx5090_gemm_milp/rtl/numerical/verify_numerical_matrix.py
```

This runner uses the installed Verilator and local C++ compiler. It saves generated operands, expected values, source hashes and verification results. It does not use remote hardware.

Run the connected resource-admission checks:

```sh
python studies/rtx5090_gemm_milp/rtl/components/verify_quantized_admission.py
```

This builds the allocation arithmetic, block allocator and wrapper together. It checks saved occupancy and capacity boundaries, without assigning physical dispatch timing.

### 5.2 Expected test behavior

| Test | Stimulus | Expected observation | Current evidence |
|---|---|---|---|
| Arbitration | Four eligible warps; accept first choice then stall receiver | Choose zero, then one; cursor holds without acceptance | Passed |
| Shared storage | Write and read word seven | Read returns 0x12345678 | Passed |
| Cache reuse | Read address 0x100 twice, completing each request | First misses; second hits | Passed |
| Queue capacity | Two requests into a two-slot queue; stall returns | No third admission while full | Passed |
| Response backpressure | Hold rsp_ready low for three ticks | Valid response and identity remain intact | Passed |
| Barrier | Partial arrivals, then all arrivals while protected work pending | No release until both conditions hold | Passed |

These checks are implemented in [components_tb.sv](components/components_tb.sv). [The receipt](components/verification.json) records the tested categories. Other component references explicitly state where behavioral tests remain absent.

### 5.3 Interface timing examples

These examples specify this library, not measured GPU pipeline timing. Labels k, k+1 and so on identify successive rising edges after reset. Values describe the handshake at the edge, before registered state updates.

**Timing FIFO: LATENCY=3, INTERVAL=1, SLOTS=2.**

| Edge | Accepted request | Head response eligible for handshake | Head identity | Consumer ready | Ownership after edge |
|---|---|---|---|---|---|
| k | A | No | Not meaningful | 0 | A pending |
| k+1 | B | No | Not meaningful | 0 | A and B pending |
| k+2 | None: full | No | Not meaningful | 0 | A and B pending |
| k+3 | None: full | Yes | A | 0 | A held; B pending |
| k+4 | None: full | Yes | A | 1 | A retires; B remains |
| k+5 | C may enter | Yes | B | 1 | B retires; C pending |

B is due at k+4 but waits behind A. At k+4, full-queue readiness is computed before retirement, so a new request cannot yet enter. This exposes a throughput consequence of the implementation instead of hiding it in a latency number.

**Shared bank: write followed by read, LATENCY=3.**

| Event | Stored word | Output ownership | Allowed next action |
|---|---|---|---|
| Accept write to word 7 | Updated to write_data | Write response pending | Reject another request while occupied |
| Countdown reaches zero | Updated word remains | Write response valid | Consumer may accept |
| Write response accepted | Updated word remains | Slot freed | A read may be accepted on a later edge |
| Accept read of word 7 | Unchanged | Response latches stored value | Wait for configured response delay |

This states exactly when the model stores and returns data. No actual RTX shared-bank write delay is inferred from it.

### 5.4 Minimum integration verification


Before reporting an integrated model, verify: accepted-operation conservation; correct destination/version returns; no early dependent issue; no overflow; valid shared read-after-write behavior; no premature barrier release; no retirement with outputs outstanding; and deterministic reset/replay. Include queue-full and stalled-response cases, because an unstalled example does not verify backpressure.

After functional integration, compare calibrated predictions against independent hardware cases. A correct RTL handshake test establishes model semantics, not NVIDIA timing accuracy. The seven checks in the older monolithic prototype remain separate evidence and are not automatically inherited by this library.

## 6. Operation semantics and unsupported behavior

This table describes the original component library. Later numerical and integrated components in sections 4.16–4.57 extend these operations; their individual contracts govern those implementations.

| Modeled operation | Inputs/required state | Affected state | Completion/ordering | Unsupported behavior |
|---|---|---|---|---|
| Allocate block | Legal resource counts and free slot | busy and per-slot allocations | Captured slot identity | Rounding/threads not supplied by allocator |
| Issue warp instruction | eligible warp and downstream acceptance | Cursor and external warp PC | Handshake is the sole issue event | Arbitrary issue without resource acceptance |
| Reserve register result | Ready sources and free destination | Destination defined/readiness timestamp | Available at deterministic due cycle | Unknown variable return time |
| Shared write | Valid local word index and 32-bit value | Stored word and pending response | Explicit response retirement | Byte masks/atomics absent |
| Shared read | Valid local word index | Pending response data | Returns latched stored word | Full-warp conflict decoding absent |
| Cache timing read | 32-bit address; idle cache | Tags, recency, hit flag and pending response | Blocking modeled hit/miss delay | Writes, coherence and concurrent pending consumers absent |
| ALU/matrix token | Accepted identity | Timed outstanding queue | Returns identity, not numerical result | Arithmetic result semantics absent |
| Barrier arrival | Participant pulse | Arrival mask and release countdown | All arrivals plus protected completion | Partial/asynchronous barriers absent |
| Retire block | All warp ends and store completion | Completion latch, then external allocation release | Exactly one retirement per block | Early retirement forbidden |

No undefined operation is silently assigned an approximate GPU timing. Validation must distinguish a module's simulation assertion from an actual GPU fault or exception; this library does not emulate NVIDIA exception behavior.

## 7. Configuration admission and development limits

The [parameter inventory](missing_parameters.md) has 87 functional/structural fields and 47 timing fields. Physical evidence fully identifies eight functional fields, supports 24 functional fields partially and leaves 55 functional fields unknown. Timing has no fully identified fields, eight partial fields and 39 unknown fields. Partial fields still count as incompletely identified: 79 functional plus 47 timing fields remain. A per-class or per-queue-family vector counts as one field; these are specification entries, not every scalar NVIDIA property. The [provisional profile](provisional_parameters.md) supplies a behavioral baseline for all 134 entries while keeping these evidence statuses unchanged.


Do not select new capacities by fitting a complete GEMM time. First identify the resource and match the probe's operation, addresses, dependency pattern, and concurrency. Preserve failed scheduler and timing explanations as counterexamples.

Unknown quantitative fields include scheduler assignment and issue restrictions, register/collector banks and ports, physical execution pipeline counts, queue depths, cache mapping/associativity and write policy, intrinsic response delays, and memory-domain timing. The current [quantitative tables](quantitative_microarchitecture.md) distinguish these from measured capacities and compound costs.

Sections 4.43–4.57 now connect native numerical execution, input staging, barriers, resident block admission, output stores and shared-cache requests for the supported small grids. The remaining integration work is to reproduce the original large workload, represent its relevant issue and memory-service organization, and bind experimentally justified parameters. An accurate RTX 5090 runtime model cannot be claimed until this executable predicts independent GPU measurements. This round uses local simulation. The earlier scoped remote authorization has expired; new remote measurements require renewed authorization.

### 7.1 Current implementation and error audit

The largest reproduced error among sixteen saved dense-grid cases is 5.97%: the 32 × 32 tile on a 2,048 × 2,112 output with reduction length 1,536 predicts 293.383 microseconds and measures 276.864 microseconds. Absolute relative error is the absolute predicted-minus-measured difference divided by measured time. This result belongs to the existing independent phase-composition model, not the integrated RTL. [The audit](current_error_audit.json) preserves its unchanged predictions. No new GPU measurements were taken.

The current integrated top is [resident_gemm_multi_sm_nb_l2.sv](numerical/resident_gemm_multi_sm_nb_l2.sv). It executes actual operand values on two modeled SMs, with two resident contexts per SM, native 32 × 32 tiles, barriers, private input caches, shared pending-sector fetches and acknowledged output stores. The [full-grid verification](numerical/resident_multi_sm_nb_l2_verification.json) checks 24,576 outputs across reduction lengths 64 and 1,536. These grids have 64 rows and 96 columns; they do not reproduce the original large case.

| Test finding | Executable consequence | Evidence boundary |
|---|---|---|
| Two clients request the same sector before its fetch returns | Separate owners join one pending fetch and receive its actual returned data | Local numerical and protocol verification; physical merging policy is unknown |
| Different sector fetches return out of order | Saved internal IDs route each packet to its cache sector and waiting owners | Tagged test provider; physical return ordering is unknown |
| A client holds a completed response | Its owner and data remain stable while unrelated clients may finish | Explicit simulator rule; physical response-buffer capacity is unknown |
| A new join coincides with its sector refill | The arriving packet is forwarded to the new owner on that edge | Directed simultaneous-event test; no measured GPU timing |
| Complete grids produce correct final words | Native compute, staging, barrier and output paths are connected | Supported 32 × 32 tiles only; full-chip timing and tile ranking remain unvalidated |

[The experiment-to-model record](discovery_rounds/nonblocking_l2_connected.json) preserves these changes. They resolve executable behavior gaps without closing physical parameters: eight fields remain identified, 32 partial and 94 unknown. The priority is now defensible parameter binding and support for the largest-error workload. Compound instruction dependency costs may constrain an effective timing mode, but cannot be relabeled as intrinsic cache or execution latency.

## Appendix A. Reference-format provenance

The format review used the following supplied documents. Page references here are physical PDF page numbers, followed by chapter/section identifiers where useful.

| Reference | Inspected format examples | Adopted convention |
|---|---|---|
| XiangShan Kunminghu V2R2 design manual | PDF 116–142, instruction cache; 232–246, scheduling; 363–384, LSU; 464–483, DCache; 572–601, L2/MSHR | Submodule lists; parameter values and restrictions; storage tables; pipeline-stage explanation; interface timing; allocation-to-release lifecycle |
| Intel combined SDM | PDF 597–613, instruction-description conventions; 628–630, ADD; 1255–1259, MOV; 3285–3297, ordering; 3441–3459, cache control | Operation inputs/outputs; exact affected state; supported forms; explicitly separated invalid and exceptional cases |

The reference review examined the tables of contents and the selected sections, with visual inspection of representative parameter, timing, pipeline, lifecycle and instruction-reference pages. It did not read all 5,060 Intel pages. The XiangShan PDF has 626 pages. Only formatting and specification practices are adapted; no CPU-specific queue size, cache policy, instruction behavior or timing is adopted as an RTX hardware fact.

The RTX values remain linked to device queries and its own tests in [the quantitative specification](quantitative_microarchitecture.md). The inline SystemVerilog remains our own explicitly hypothetical implementation.


## Appendix B. Template compliance and evidence navigation

| Template requirement | Location in this manual | Supporting implementation or evidence |
|---|---|---|
| Scope, device and build status | Section 1 | Separates the component library from the earlier prototype |
| Quantitative values and evidence classes | Section 2 and each component's parameter table | [Quantitative specification](quantitative_microarchitecture.md), [saved structural evidence](evidence.json) |
| Clocks, handshakes and ownership | Section 3 | Explicit integration obligations and absent interfaces |
| Per-component role, ports, state, transitions and full code | Sections 4.1–4.18 | [Authoritative component source](components/hardware_blocks.sv) |
| Cycle timing and blocked operations | Component transitions/lifecycles and Section 5.3 | Acceptance, held responses and registered barrier release |
| Verification and coverage limits | Section 5 | [Component testbench](components/components_tb.sv), [component receipt](components/verification.json) |
| Operation semantics and unsupported forms | Section 6 and later component sections | Section 6 describes the original library; sections 4.16–4.57 add numerical execution and connected memory behavior |
| Missing physical properties and integration work | Section 7 and component parameter restrictions | [Detailed component contracts](component_specification.md) and quantitative specification |
| Reference scope and formatting sources | Appendix A | Reference-review receipt (reference-review metadata excluded from this public package) |

The document supplies a development contract for the fourteen original module definitions, completion-driven register file and numerical matrix pipeline. It does not supply missing NVIDIA internals: cache associativity and replacement, scheduler partitions, operand-collector organization, physical queue depths and intrinsic delays remain unresolved. Those unknowns are requirements for further reverse engineering, not fields that can be completed from a CPU manual.

## Native instruction evidence update

[Round 3](discovery_rounds/source_sweep_003.md) reproduces four native HMMA instruction addresses in the saved 32 × 32 loop body and twelve in the 64 × 48 loop body, in both p0 and p2 variants. Static addresses are not dynamic instruction counts or pipeline latencies. Section 4.16 remains an operation-level numerical reference; native instruction issue, lane mapping and internal execution are still missing. The simulator must preserve this distinction when deriving timing.

[Round 4](discovery_rounds/source_sweep_004.md) checks dynamic matrix work against saved profiler records. Both supported launches execute 49,152 warp-level HMMA instructions, matching the source-derived count. The reproducible counter supplies matrix work quantity only; instruction service and completion timing remain unidentified.

## Measured shared-read work update

[Hardware sweep 1](discovery_rounds/hardware_sweep_001.md) verifies the scalar bank-service package rule on three read patterns: 4, 2 and 8 packages, exactly matching measured wavefront totals. The new executable rule is `parameter_sweep/shared_work.py`; full request arbitration and wider accesses remain unresolved. The measured dependent LDS loop costs 34 cycles per iteration, including address and control costs. This value has not been assigned as intrinsic bank latency. The existing Verilog shared-bank model remains uncalibrated.

[Hardware sweep 2](discovery_rounds/hardware_sweep_002.md) narrows the conflict-free scalar LDS dependency path to 28 cycles per load when address arithmetic is removed and loop control is amortized. This combines response and wakeup; neither is separately identified. The scalar bank-work rule now matches seven measured patterns. These findings do not calibrate wider operations or complete the connected RTL model.

[Hardware sweep 3](discovery_rounds/hardware_sweep_003.md) falsifies extension of the scalar bank rule to 128-bit same-vector broadcasts: measured work is two wavefronts, not one. The executable bounded vector-work rule matches twelve read/store patterns and rejects unverified wide patterns. This work-count rule is not yet connected to a calibrated Verilog operand path; physical ports and grouping remain unknown.
