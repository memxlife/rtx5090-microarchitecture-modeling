"""Materialize the approved structure from existing executable contracts and evidence."""
from pathlib import Path
import json,re
R=Path(__file__).resolve().parents[1]
sections=json.loads((R/'manual/legacy_sections.json').read_text())
source=json.loads((R/'manual/source_map.json').read_text())
params=json.loads((R/'parameter_master_table.json').read_text())['parameters']
# Each original functional/timing entry has one architectural owner.
chapters=[
('Work distribution and block admission',[2,17,18,43,44,50,51,53,55,57],list(range(1,5)),list(range(1,4)),
 'The work distributor converts a matrix grid into tile identities. Admission reserves a context and its required resources before any warp starts; retirement returns those reservations only after required stores complete.',
 'Grid launch → tile selection → atomic admission → resident context → acknowledged retirement. The connected top has two modeled SMs and two contexts per SM. This exercises resource ownership but does not represent all 170 physical SMs.',
 'Launch acceptance captures the matrix bases and identity. A selected tile waits until a resident context is free. Completed tiles are marked once; the grid finishes after every tile has retired. The simple allocator consumes raw register/shared demands, while the quantized allocator adds rounding; these are different implementations.',
 'Resource totals must remain conserved. A stalled child cannot advance the dispatch cursor or consume a second reservation. Block completion requires the child completion handshake; issuing its last arithmetic instruction is insufficient.',
 'Residency changes how much work can overlap. MIP decisions may select tile/resource demands and block assignment, subject to rounded register/shared limits. The current dispatch policy is a model choice, not recovered GPU scheduling.'),
('Warp state and instruction supply',[3],list(range(5,13)),list(range(4,7)),
 'A warp context stores where a group of lanes is in its instruction sequence and whether it can proceed. It supplies control state; it does not itself execute an instruction.',
 'Instruction position and barrier state → eligibility inputs. The standalone context is a small instruction-position model; the numerical GEMM engines use specialized stage state machines instead of a general instruction fetch/decode engine.',
 'Only accepted issue advances the program counter. An accepted barrier sets a waiting state, release clears it, and end makes termination sticky. A barrier accepted on the same edge as release retains the newly entered wait according to the module priority.',
 'A stalled instruction retains its position. No issue may occur after end. Divergence, reconvergence and instruction-cache misses are outside the implemented domain.',
 'A kernel schedule needs precedence and active-lane information. A general CUDA program requires additional instruction decoding and control-flow support; the current model covers a fixed GEMM path.'),
('Scheduling and instruction issue',[4,33],list(range(13,19))+[31],list(range(7,9)),
 'The scheduler chooses an eligible warp. Eligibility means its dependencies are complete and its destination service can accept the operation.',
 'Warp eligibility → candidate selection → receiver acceptance → issue gate. The primitive scheduler has one round-robin cursor; the numerical native issue gate enforces class-specific admission. Four documented physical scheduler partitions are not four instantiated recovered schedulers.',
 'Selection is combinational. The cursor changes only on accepted issue. Timing gates prevent a native operation from accepting before the configured interval has elapsed; a selected instruction remains pending when its receiver stalls.',
 'Selection must never bypass readiness. An initiation interval constrains acceptance spacing; it is not the same quantity as completion latency. The profile and RTL arbitration choices can differ and must be recorded.',
 'Issue capacity and dependency constraints belong in the MIP. Exact scheduler policy can remain provisional until a hardware mismatch depends on it.'),
('Registers, readiness, and operand collection',[5,15],list(range(19,27)),list(range(9,14)),
 'Registers hold values; readiness records whether the most recent producer has completed. Operand collection delivers only defined, completed values to an execution operation.',
 'Issue reservation → pending destination → tagged completion → register value → dependent issue. The timestamp scoreboard models deterministic readiness; the completion-based register module stores actual returned values. Neither reconstructs physical register banks.',
 'A producer reserves a destination before completion. The timestamp model marks it available at a configured cycle; the completion model waits for its matching return. A consumer must use the version produced by the intended writer, not an earlier value.',
 'Undefined source use and overwrite of an unfinished destination are errors. Physical capacity is 65,536 32-bit words per SM; 64 abstract register identities per modeled warp are a separate implementation setting.',
 'Register demand bounds residency. Dependency edges bound earliest issue. Unknown port conflicts should not be inserted as additional penalties without evidence or combined-path validation.'),
('Scalar and address execution',[6],list(range(27,31)),list(range(14,16)),
 'This chapter defines the boundary for scalar arithmetic, address generation and control execution. The primitive implementation transports operation identities through a timing queue; it does not compute a complete CUDA scalar instruction set.',
 'Ready operands → execution acceptance → result completion. Numerical address calculations in the GEMM engines are implemented directly in their control logic; they are not routed through a calibrated scalar pipeline.',
 'The primitive accepts a token when its service queue has capacity and its initiation interval permits acceptance. It returns that token after the configured delay. Adding a general scalar unit requires opcode-specific numerical semantics and destination values.',
 'Token completion cannot establish arithmetic correctness. Throughput in scalar results per SM cycle is distinct from warp instruction issue interval.',
 'The optimizer can include scalar service demand only at its documented scope. A fixed kernel path can use measured combined costs; arbitrary scalar instruction mixes require further execution support.'),
('Matrix operands and tensor execution',[16,19,21,22,23,28,29,30,32,35,36,37,40,47,49],list(range(32,36)),list(range(16,20)),
 'The matrix path transforms lane-organized BF16 operands into FP32 accumulator updates. Operand mapping, request completion, native instruction order and accumulation order all affect its behavior.',
 'Shared-memory completion → MOVM/LDSM operand mapping → native HMMA acceptance → accumulator update. The connected kernel uses the studied native instruction family; generic matrix helpers and library-layout helpers are separate contracts.',
 'Operand windows capture completed words before matrix issue. The native operation uses the specified lane/register map and arithmetic mode. Successive reduction stages reuse an accumulator only after its previous producer has completed.',
 'No matrix instruction may consume missing operands. Preserve the specified BF16 representation and FP32 accumulation order. The dependency-probe cost includes compiler wait/control effects and is not intrinsic tensor pipeline latency.',
 'Tile shapes, operand layout and stage scheduling are optimization decisions. Native HMMA work and service limits can be represented, but one probe cost cannot be transferred to every matrix instruction family.'),
('Load/store execution',[7,38,39,41],list(range(36,43)),list(range(20,24)),
 'Load/store execution converts lane addresses into requests and converts returned sectors into lane values. Stores carry word masks and remain outstanding until acknowledged.',
 'Lane addresses → 32-byte sector requests → tagged returns → lane assembly or acknowledged write. The token transaction queue has no numerical coalescing; the numerical warp adapters implement bounded load/store families.',
 'The load adapter groups participating lane words by sector and assembles the returned data using the original lane mapping. The store adapter constructs eight-word sectors and masks. Disjoint output regions avoid a general coherence protocol.',
 'Pending identities must be unique within their routing domain. A return must match an outstanding request. Request acceptance and store acknowledgement are separate events; a block cannot retire merely because its store was submitted.',
 'Addresses and masks determine transaction counts. Bound outstanding work by modeled ownership/queue capacity; a guessed per-warp transaction cap is not a documented hardware fact.'),
('Address translation',[8],list(range(43,48)),list(range(24,27)),
 'Translation maps program addresses to serviced memory addresses. The present primitive is an identity mapping with queued timing, suitable for the controlled flat-address test domain.',
 'Virtual-address token → identity translation queue → unchanged address. The connected GEMM backing-memory model uses flat bounded addresses and does not instantiate a physical page walker or TLB.',
 'Accepted addresses retain their identity through the configured queue delay. Output equals input. Page permissions, faults, physical indexing and invalidation are not implemented.',
 'Do not attribute this identity mapping to the RTX 5090. A guessed TLB capacity does not make translation behavior executable. Test-domain bounds and launch overflow checks remain enforced.',
 'Translation can be omitted from the current fixed-domain cost only as a stated abstraction. Large-footprint cases that reveal translation delays require an expanded model.'),
('Shared-memory service',[9,20,31,46,48],list(range(48,54)),list(range(27,31)),
 'Shared memory stores block-local words and serves requests through a banked organization. Broadcast and conflicting addresses must be distinguished because equal bytes can require different service work.',
 'Global staging completion → shared writes → barrier → shared-read hub → lane operand completion. The single-bank primitive and the multi-client numerical hub are different implementations.',
 'A primitive write updates the addressed word on acceptance and holds its response. Numerical staging commits operand frames before consumption. The read hub routes completed lane values to their owning client; shared-memory ownership is block/context-local.',
 'The measured scalar dependency path is 28 cycles for broadcast or conflict-free access, with about two extra cycles per additional distinct word in the busiest bank for the tested pattern. This combined path is not a separately measured SRAM access latency.',
 'Layout decisions change bank service work. The measured conflict rule is implemented in the effective-path estimator; it is not automatically wired into every numerical RTL helper.'),
('L1 cache and shared partition',[10,25,26,45],list(range(54,63)),list(range(31,35)),
 'L1 caching retains local data near an SM. Shared-memory configuration competes for the documented combined storage budget, while cache policies and capacity determine hit behavior.',
 'Local sector lookup → cached data or backing request → staging completion. The original blocking tag-only cache is a prototype; sector caches carry actual data. The connected model uses configured per-SM cache geometry, not a measured physical set map.',
 'A hit supplies retained data according to its modeled timing. A miss waits for the configured return path. Reset invalidates tags. Replacement and write policy must be read from the selected implementation, not inferred from an unrelated helper.',
 'Inputs are immutable in the supported GEMM tests. Configuration preference is not a guarantee of exact physical carveout. The 8 KiB dependent .ca test measured about 43.21 cycles; its scope is the full tested path.',
 'Reuse, footprint and partition preference can change staging cost. Exact associativity or replacement need only be refined when current validation contradicts the provisional model.'),
('L2 cache and refill ownership',[54,56],list(range(63,75)),list(range(35,39)),
 'The shared L2 gateway retains read sectors and coordinates pending fetches from multiple SMs. A pending miss needs both fetch ownership and consumer ownership; these are separate finite resources.',
 'SM requests → shared lookup → hit, merge or new fetch → backing return → consumer response. The nonblocking gateway supports multiple pending fetches and tagged returns; the older shared gateway serializes more work.',
 'A hit returns resident data. A matching pending fetch can attach another consumer. A new miss reserves an available fetch entry and safe replacement target. Returned sectors fill the retained line and remain owned until their waiting consumers retire.',
 'A pinned victim cannot be reused while a live fetch or consumer needs it. Held responses preserve identity/data. Test geometry is 64 sets × 8 ways × 128 bytes = 64 KiB, distinct from the recorded physical 96 MiB total L2.',
 'The MIP needs reuse and finite outstanding ownership where these affect costs. Exact physical indexing remains provisional; the model must not convert its synthetic geometry into a claimed 5090 cache organization.'),
('Backing memory and response transport',[11,27,34,52],list(range(75,81)),list(range(39,43)),
 'Backing memory stores numerical input/output words and returns tagged completions. The transport connects shared cache fetches and masked stores to that storage.',
 'Cache or store request → bounded gateway → backing-memory service → tagged acknowledgement. A token memory controller supplies timing only; numerical tile/grid tests supply actual words through their backing harness.',
 'Read acceptance records address and identity; the returned sector belongs to that request even when responses reorder. Writes update only masked words and return a completion identity. Grid completion waits for those write acknowledgements.',
 'No return may be consumed by another owner. The synthetic gateway can accept at most one 32-byte sector per two SM edges in its present configuration; that is not a full-chip DRAM service model.',
 'Measured streaming copy bandwidth is about 1.476 TB/s in the scoped test. Applying it requires the correct traffic and concurrency; the current numerical RTL gateway is not calibrated to that aggregate bandwidth.'),
('Barriers and retirement',[12,13,42],list(range(81,86)),list(range(43,46)),
 'A barrier orders participating warps. Retirement ends a block only after its threads and required external stores have completed.',
 'Warp arrival → generation-specific barrier state → release → continued issue. Warp end plus store acknowledgements → block completion → resource return.',
 'The simple controller gathers an arrival mask and emits a delayed release. The numerical generation-aware barrier prevents arrivals from one iteration releasing another. Completion is sticky in the primitive until reset; resident wrappers reuse contexts through their own control.',
 'Participants and barrier generation must agree. Release cannot precede required protected work. A final arithmetic result is not equivalent to a committed output store.',
 'Barrier edges become precedence constraints. Use measured compound synchronization costs at their scope; do not label a loop cost as isolated barrier latency.'),
('Clocks, event transport, and observation',[1,14,58],list(range(86,88)),list(range(46,48)),
 'This chapter defines the simulator time base, response holding and observation. Cycle counts are meaningful only with an explicit edge convention and a stated conversion clock.',
 'One shared clock edge → simultaneous component state updates → settled outputs → observation. C++ calls the connected generated model rather than ticking child components sequentially.',
 'Requests transfer on valid and ready at a rising edge. Outputs settle after evaluation and remain held until accepted. The reference counter counts model edges; the queue keeps due times and the dependency replay waits for actual returned operands.',
 'The chosen 2.94 GHz reference converts one microsecond to 2,940 reference cycles. Observed GPU clocks vary: older full GEMM was about 2.85 GHz and recent probes about 2.95 GHz. Conversion does not recover separate physical clock domains.',
 'Record elapsed model cycles and hardware time separately. The phase estimator within 5% on two new workloads is not validation of the integrated Verilog cycle count.')]

D=R/'manual/components';D.mkdir(exist_ok=True)
def link(p,label=None): return f'[{label or Path(p).name}]({Path(p)})'
def val(x):
 if isinstance(x,(dict,list)): x=json.dumps(x,ensure_ascii=False,separators=(',',':'))
 return str(x).replace('|','\\|').replace('\n',' ')
owned=set(); links=[]
for i,(title,ids,fs,ts,purpose,interface,behavior,invariant,implication) in enumerate(chapters,1):
 file=D/f'{i:02d}_{re.sub("[^a-z0-9]+","_",title.lower()).strip("_")}.md';links.append((title,file))
 ps=[p for p in params if p['id'] in {f'F{x:03}' for x in fs}|{f'T{x:03}' for x in ts}]
 owned.update(p['id'] for p in ps)
 text=f'# {i:02d}. {title}\n\n{link(R/"rtl_microarchitecture_spec.md","System specification and chapter index")} · {link(R/"hardware_manual_structure.md","Approved manual structure")}\n\n## 1. Purpose and boundary\n\n{purpose}\n\nThis is a specification of the executable reconstruction. Statements about physical RTX 5090 hardware retain their source or measurement scope; helper defaults describe model configurations.\n\n## 2. Quantitative parameters\n\nThe table assigns this chapter ownership of the following inventory entries. “Baseline” preserves the existing setting; the evidence check may instead support a scoped alternative. Source priors are usable provisional estimates, not measurements of a private circuit.\n\n| ID | Definition | Baseline | Unit | Recorded basis | Initial check |\n|---|---|---|---|---|---|\n'
 for p in ps:
  check=p.get('initial_validation',{}); basis=check.get('check_kind',check.get('initial_check','Recorded inventory'))
  text+=f"| {p['id']} | {val(p['definition'])} | {val(p.get('provisional_value','Not specified'))} | {val(p.get('unit',''))} | {val(p.get('basis_label',p.get('current_status','')))} | {val(basis)} |\n"
 text+=f'\nUse the {link(R/"parameter_master_table.md","complete parameter table")} for values, scope, evidence links and provisional alternatives. Device capacities are centralized in the system specification. Per-module tables below identify which parameters are actually consumed by each implementation.\n\n## 3. Interfaces and transaction ownership\n\n{interface}\n\nThe exact port names, directions, widths and acceptance rules are listed in the implementation contracts in Section 8 and their linked sources. A connection must preserve both payload and ownership while stalled. The common system protocol applies unless a module contract explicitly states a pulse-only interface.\n\n## 4. State and storage\n\nEach linked module contract specifies its arrays, counters, masks, pointers or state machine. Those fields belong to that implementation only. A primitive helper is not an additional copy of a hardware resource inside the connected top unless that top instantiates it. Reset removes outstanding model ownership according to the specified contract; physical power-on behavior is outside this model.\n\n## 5. Functional transitions\n\n{behavior}\n\nRequests are accepted only when the named receiver permits acceptance. Completion must update the original owner before resources are released. The implementation contracts below describe each state transition and numerical transformation separately.\n\n## 6. Timing and arbitration\n\nUse completion latency, acceptance interval and queue capacity as three distinct quantities: when a result becomes available, how often a new request can start, and how many requests can remain pending. The per-module timing contract gives their actual code meaning.\n\nFor a held-response interface, observe a valid response after an edge, hold readiness low for one more edge, and verify that identity and data remain unchanged. Retirement occurs only on a later edge with both valid and ready. A receiver becoming free after an edge does not retroactively accept a request at that edge.\n\n## 7. Invariants and failure handling\n\n{invariant}\n\nUnsupported configurations must remain explicit. A passing test of a helper establishes its tested model contract, not a GPU-wide hardware policy.\n\n## 8. Linked implementations and detailed contracts\n\nThe following contracts retain the quantitative organization, exact interfaces, state transitions and verification scope of the existing implementations. Verilog stays in separate source files. C++ adapters expose the same generated ports and clock behavior; they do not introduce independent timing constants.\n'
 modules=[]
 for n in ids:
  s=sections[str(n)];text+=f'\n### Implementation {n}: {s["title"]}\n\n'+s['text']+'\n'
  modules+=s['modules']
 text+='\n### C++ component adapters\n\n'
 for m in dict.fromkeys(modules):
  h=R/'cpp'/f'{m}.hpp'
  if h.exists():text+=f'- {link(h,m)} — adapter for {link(source[m]["path"],"the matching Verilog source")}.\n'
 if not any((R/'cpp'/f'{m}.hpp').exists() for m in modules):text+='This chapter has no independent executable component beyond the linked contracts.\n'
 text+=f'\n## 9. Verification and evidence\n\nRetain the verification expectations and existing receipts in Section 8. The {link(R/"manual/integration_and_verification.md","integration and verification chapter")} separates existing numerical tests, new C++ smoke tests and GPU measurements. The most recent connected-grid receipt checks 24,576 output words; it does not calibrate the integrated cycle count.\n\n## 10. Optimization implications and remaining gaps\n\n{implication}\n\nA parameter checked through documentation or a transferred prior can be used provisionally. Refine it when a new end-to-end case disagrees materially or when it changes the optimization choice. Do not spend time recovering a private property that the supported execution path does not exercise.\n'
 file.write_text(text)
assert len(owned)==134,(len(owned),owned)
(R/'manual/chapter_index.json').write_text(json.dumps([{'title':t,'path':str(p)}for t,p in links],indent=2)+'\n')
(R/'manual/evidence_history.md').write_text('# Evidence history and interpretation\n\n'+link(R/'rtl_microarchitecture_spec.md','System specification')+'\n\nThe experimental objective is to determine whether realistic kernel optimization can be formulated and solved as a MIP. Hardware reconstruction supplies resource and timing structure; it is useful when it predicts performance and guides choices on the GPU.\n\nThe first model counted arithmetic and requested bytes with fixed rates. Large mismatches motivated residency, stage cost, dependencies, shared-memory service and cache-path tests. The latest initial-check pass supports using scoped estimates, while preserving their provenance.\n\n'+link(R/'parameter_sweep/initial_validation_20261003_222837/summary.md','Initial-check results and quantitative error comparison')+'\n\n'+link(R/'parameter_sweep/initial_validation_20261003_222837/consolidated_checks.md','Per-entry evidence and alternatives')+'\n\n## Library evidence contract\n\n'+sections['24']['text']+'\n\n## Claims that remain bounded\n\nAll 118 assumption-based entries have a recorded initial check or provisional alternative. Eighty use transferred priors; two have numerical consistency only. This does not establish 118 physical RTX 5090 facts. The phase estimator met 5% on two new workloads, but the connected Verilog timing remains uncalibrated.\n\nThe current component adapters are Verilator-generated C++ and therefore share their source behavior. No independent fast event simulator or measured speedup is claimed.\n')
print('Wrote 14 chapters; assigned all 134 functional/timing entries exactly once.')
