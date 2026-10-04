# 12. Backing memory and response transport

[System specification and chapter index](../../rtl_microarchitecture_spec.md) · [Approved manual structure](../../hardware_manual_structure.md)

## 1. Purpose and boundary

Backing memory stores numerical input/output words and returns tagged completions. The transport connects shared cache fetches and masked stores to that storage.

This is a specification of the executable reconstruction. Statements about physical RTX 5090 hardware retain their source or measurement scope; helper defaults describe model configurations.

## 2. Quantitative parameters

The table assigns this chapter ownership of the following inventory entries. “Baseline” preserves the existing setting; the evidence check may instead support a scoped alternative. Source priors are usable provisional estimates, not measurements of a private circuit.

| ID | Definition | Baseline | Unit | Recorded basis | Initial check |
|---|---|---|---|---|---|
| F075 | The organization of memory channels, controllers, banks and bank groups. | {"controllers":16,"bits_per_controller":32,"banks_per_controller":16} | controllers; bits; banks | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F076 | The function assigning a physical address to a memory channel and bank. | {"channel":"(address//256)%16","bank":"(address//32768)%16","row":"address//524288","column":"(address%256)+256*((address//4096)%8)"} | address mapping | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F077 | The numbers of waiting read, write or command requests a controller can hold. | {"read_entries":64,"write_entries":64} | queue entries/controller | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F078 | The rule choosing which waiting memory request or command proceeds next. | FR-FCFS: ready row hits first, then oldest; fairness after64 selections | arbitration policy | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F079 | The legal command sequence and open-row state used to access a memory bank. | {"row_bytes":2048,"open_page":true,"one_open_row_per_bank":true} | bytes/row; state rules | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| F080 | How the controller buffers, combines and schedules writes relative to reads. | {"write_buffer_entries":64,"drain_high_watermark":48,"drain_low_watermark":16,"merge_same_sector":true} | entries; controller write policy | ENGINEERING_ASSUMPTION | Transferred simulator prior |
| T039 | Time from a DRAM read command being accepted to first returned data; row-hit, row-miss and queue conditions must be stated. | Not specified | SM-reference cycles | unidentified | Published RTX 5090 path measurement |
| T040 | Time from a DRAM write command being accepted to the chosen write-completion point; excludes upstream cache acknowledgment. | Not specified | SM-reference cycles | unidentified | Transferred simulator prior |
| T041 | Additional interval when the memory controller changes between reading and writing; excludes ordinary transfers in one direction. | Not specified | SM-reference cycles | unidentified | Transferred simulator prior |
| T042 | Spacing between completed data transfers at a stated interface; aggregate streaming bandwidth does not identify a controller’s command interval. | Not specified | SM-reference cycles/32-byte sector, aggregate bus | unidentified | GPU contract or effective path |

Use the [complete parameter table](../../parameter_master_table.md) for values, scope, evidence links and provisional alternatives. Device capacities are centralized in the system specification. Per-module tables below identify which parameters are actually consumed by each implementation.

## 3. Interfaces and transaction ownership

Cache or store request → bounded gateway → backing-memory service → tagged acknowledgement. A token memory controller supplies timing only; numerical tile/grid tests supply actual words through their backing harness.

The exact port names, directions, widths and acceptance rules are listed in the implementation contracts in Section 8 and their linked sources. A connection must preserve both payload and ownership while stalled. The common system protocol applies unless a module contract explicitly states a pulse-only interface.

## 4. State and storage

Each linked module contract specifies its arrays, counters, masks, pointers or state machine. Those fields belong to that implementation only. A primitive helper is not an additional copy of a hardware resource inside the connected top unless that top instantiates it. Reset removes outstanding model ownership according to the specified contract; physical power-on behavior is outside this model.

## 5. Functional transitions

Read acceptance records address and identity; the returned sector belongs to that request even when responses reorder. Writes update only masked words and return a completion identity. Grid completion waits for those write acknowledgements.

Requests are accepted only when the named receiver permits acceptance. Completion must update the original owner before resources are released. The implementation contracts below describe each state transition and numerical transformation separately.

## 6. Timing and arbitration

Use completion latency, acceptance interval and queue capacity as three distinct quantities: when a result becomes available, how often a new request can start, and how many requests can remain pending. The per-module timing contract gives their actual code meaning.

For a held-response interface, observe a valid response after an edge, hold readiness low for one more edge, and verify that identity and data remain unchanged. Retirement occurs only on a later edge with both valid and ready. A receiver becoming free after an edge does not retroactively accept a request at that edge.

## 7. Invariants and failure handling

No return may be consumed by another owner. The synthetic gateway can accept at most one 32-byte sector per two SM edges in its present configuration; that is not a full-chip DRAM service model.

Unsupported configurations must remain explicit. A passing test of a helper establishes its tested model contract, not a GPU-wide hardware policy.

## 8. Linked implementations and detailed contracts

The following contracts retain the quantitative organization, exact interfaces, state transitions and verification scope of the existing implementations. Verilog stays in separate source files. C++ adapters expose the same generated ports and clock behavior; they do not introduce independent timing constants.

### Implementation 11: Device-memory controller baseline

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

**Linked behavioral implementation.**


**Source implementation:** [memory_controller.sv](../../components/library/memory_controller.sv)


**Verification expectation.** FIFO primitive checks passed. Memory-controller physical behavior is unimplemented.

**Unimplemented or unidentified.** GDDR7 channels, bank/row state, address mapping, command constraints, read/write turnaround, transfer buses, numerical memory contents, and clock-domain crossings are missing.

### Implementation 27: One-tile GEMM reduction and acknowledged output stores

**Purpose.** The [tile controller](../../numerical/gemm_tile_controller.sv) computes one 16 × 16 output tile, starting with zero FP32 accumulators. Let `STAGES` be the number of 16-element reduction steps. The reduction length is `K = 16 × STAGES`. Each step obtains actual input values through section 4.26, waits for an actual matrix result and carries that result into the next step. After the final step, 256 FP32 words are stored through an acknowledged output interface. There is one active launch. This is a serialized functional reproducer with cycle-driven interfaces, not a recovered native GPU schedule, full-chip scheduling, or the inspected cuBLASLt generic `LD.E`/`MOVM` kernel.

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

**Verification.** The [tile verification receipt](../../numerical/gemm_tile_verification.json) passes 2,048 FP32 output comparisons across reduction lengths 32 and 48, two launches per configuration, and synthetic backing delays of two and 13 cycles. Replay launches reuse cached sectors. Added delay propagates exactly: 64 sector requests add 704 cycles; 96 requests add 1,056 cycles. Tests stall output-store acceptance for two cycles per word, check actual output-store acknowledgments, and reject a wrong store ID, unaligned base and overlapping input/output spans. Source hashes match the tested files. Numerical fixtures use small integers with exact intermediate sums; they do not characterize general NVIDIA floating-point behavior. Runtime has not been validated against hardware.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_gemm_tile.py` from the project root.

**Authoritative behavioral implementation.** The following source is copied exactly from `numerical/gemm_tile_controller.sv`.


**Source implementation:** [gemm_tile_controller.sv](../../numerical/gemm_tile_controller.sv)

### Implementation 34: One original CTA from global input values to acknowledged output

**Purpose and supported scope.** The [studied CTA controller](../../numerical/studied_gemm_cta_controller.sv) connects one complete in-bounds output block of the original GEMM: global row-major A/B inputs, completion-driven read-cache values, scalar halfword staging, the timed generic shared/MOVM path, carried matrix accumulation, and actual acknowledged output stores. It uses a deliberately serial development schedule. It is neither native SASS replay nor a full-grid GPU simulation; the optional `USE_NATIVE_STAGE` mode now uses section 4.37's bounded decoded operand window. Global staging remains serial. Fragment execution is sequential by default; section 4.40’s optional batch shares services across four active fragment warps. Optional `COALESCED_STAGING` groups 32 logical BF16 loads by their unique sectors and commits their returned halfwords together; it still services sectors serially.

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

**Independent end-to-end value checks.** The [full-target receipt](../../numerical/studied_gemm_cta_verification.json) passes 4,096 final output-word comparisons: all 1,024 words of the first 32 × 32 CTA and all 3,072 words of the first 64 × 48 CTA, both through `K = 1536`. The test provider builds every returned sector from the original A17/B13 patterns and global strides. An independent full integer dot product divided by 256 supplies exact FP32 expectations for these dyadic fixtures. Every distinct output address, word and store acknowledgment is checked. The cold sector counts exactly equal `2 × K × (BM + BN) / 32`: 6,144 and 10,752. This counts each logical input once in these aligned row-major fixtures; it does not establish native warp coalescing or concurrent memory service. These are complete first-CTA outputs, not just intermediate fragment comparisons and not the entire global matrix.

The [quick protocol receipt](../../numerical/studied_gemm_cta_quick_verification.json) separately passes 4,096 output comparisons for `K = 64`: two repeated launches each at synthetic backing delays two and 13. Across each pair of K64 launches, the provider observes 256 sector requests, equal to the unique cold input count; the repeated inputs remain cache-resident in this declared configuration. It rejects wrong backing/store response IDs. All configurations cancel an initial real pending read, flush the provider on reset, impose read/store acceptance backpressure, check stable held stores, delay actual store acknowledgments, and hold final launch completion. The [native-window end-to-end receipt](../../numerical/studied_gemm_cta_native_verification.json) additionally passes 5,120 final output comparisons: two repeated K64 launches at each backing delay and one K1536 32 × 32 CTA. Wrong backing/store IDs are rejected. These receipts preserve the hashes of their tested sources. The two full geometries use different backing delays and therefore do not provide a controlled runtime comparison. Recorded harness cycles include reset and testbench holds and are not GPU performance predictions.

The earlier [coalesced-input receipt](../../numerical/studied_gemm_cta_coalesced_verification.json), before the added sector-output interface, separately verifies 5,120 output words: two K64 replays at each synthetic backing delay of 2 and 13 cycles, followed by one K1536 first CTA. The full-reduction case requests 6,144 cold sectors. Every output store is acknowledged before completion, and wrong backing/store IDs are rejected. `testbench_total_cycles` include setup, reset and held completion; they are not isolated kernel runtimes or hardware predictions.

That coalesced-input receipt also checks conservation of accepted coalesced requests and shared commits: K1536 has 3,072 of each, plus 6,144 returned sector references. Its `logical_loads` counter counts 32-lane requests rather than individual halfwords. `returned_sectors` includes cache-hit packet returns; backing-sector requests count actual misses, so a warm replay can return 256 sectors while making zero new backing requests.

`completion_cycles` measures accepted launch to the first observed completion edge, excluding setup, reset and time holding the completed response. Under the declared synthetic service choices, the K64 cold/warm launches take 9,419/8,393 cycles with backing delay two, and 12,485/8,393 cycles with delay 13. The K1536 cold launch takes 84,698 cycles with delay two. These are execution times of this serialized behavioral model, not validated RTX 5090 predictions.

The earlier single-warp [coalesced input/output receipt](../../numerical/studied_gemm_cta_coalesced_output_verification.json) verifies another 5,120 final values using masked sector output. Each 32 × 32 launch emits 32 warp output requests containing 128 sector packets and requires all 128 matching packet acknowledgments before completion. The full K1536 case retains 3,072 input requests/commits and 6,144 cold input sectors, and takes 79,701 accepted-launch-to-completion cycles under the declared synthetic choices. It preserves the tested single-warp controller version. The [native scalar-output regression](../../numerical/studied_gemm_cta_native_quick_verification.json) also compares 4,096 output words after those interface extensions. Earlier receipts retain their own tested source versions. Section 4.39 explains why the original scratch layout is preserved functionally but its timing is bypassed.

The earlier [four-warp connected receipt](../../numerical/studied_gemm_cta_multiwarp_verification.json) checks 5,120 final output words with shared finite services. Its K1536 launch accepts and completes 48 four-warp batches, 3,072 coalesced input requests/shared commits, 6,144 returned input sectors and 128 output-sector acknowledgments. The accepted-launch-to-observed-completion count is 67,389 cycles under the synthetic choices. That receipt retains the pre-scratch implementation hashes; this model count is not a GPU timing validation.

The earlier [output-scratch connected receipt](../../numerical/studied_gemm_cta_output_scratch_verification.json) checks 5,120 final words after restoring scratch values to the output path. Every launch commits 16 scratch-store groups containing 1,024 words and receives 32 real warp-read completions before its 128 global sector packets are retired. The full K1536 launch retains 48 operand batches and 6,144 cold input sectors; accepted-launch-to-observed-completion takes 67,617 synthetic cycles. That receipt retains its tested pre-barrier source version. The operand and scratch arrays are separate in the model: 4,096 bytes each, or 8,192 logical bytes, excluding the original kernel’s 1,024-byte reserved allocation. Shared allocation/reuse and occupancy are not implemented by summing these arrays. The output phase has a separate shared-read service instance, and never overlaps the operand phase; this does not claim simultaneous extra physical bandwidth.

The earlier [barrier-connected receipt](../../numerical/studied_gemm_cta_barriers_verification.json) verifies 5,120 final words after producer visibility and consumer drain become explicit generation transactions. At K1536, all 48 stages account for 192 producer warp arrivals, 192 consumer warp arrivals and 96 acknowledged releases. These are individual warp participants, not necessarily 192 distinct interface transfers: one mask can report several consumer warps together. The complete launch takes 67,832 synthetic cycles from accepted launch to observed completion. That receipt binds its tested pre-grid-input version; the arrival conditions and release delay remain conservative model policies, not recovered NVIDIA synchronization latency.

The latest [grid receipt](../../numerical/studied_gemm_grid_verification.json) verifies complete small matrices by reusing this dynamically addressed CTA controller. It checks 24,576 acknowledged words across four grid launches with six distinct block coordinates each. A fresh [single-CTA quick regression](../../numerical/studied_gemm_cta_barriers_quick_verification.json) also checks 4,096 words after the dynamic inputs are added. Section 4.43 distinguishes complete tested-grid values from unmodeled SM concurrency.

**Remaining limit.** Numerical global-to-output behavior is connected for one original CTA. Complete native instruction scheduling, calibrated cache/controller timing, multi-CTA/multi-SM contention, real barrier arbitration, complete arithmetic semantics and independent hardware runtime validation remain absent. Physical evidence counts are unchanged: eight identified fields, 32 partial and 94 unknown. No model-accuracy claim follows from these synthetic timing tests.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_studied_gemm_cta.py --full-only` for baseline full-reduction fixtures, `--quick` for baseline replay/protocol fixtures, or `--native-stage` for the bounded native-window integration fixtures. Add `--coalesced-staging` to the native mode for grouped global reads and vector shared writes. `--multiwarp` selects the four-warp batch and enables both coalesced input and output. `--output-scratch` additionally routes values through the scratch component before global stores. `--cta-barriers` enables the explicit producer/consumer generations and the required connected modes.

**Authoritative behavioral implementation.**


**Source implementation:** [studied_gemm_cta_controller.sv](../../numerical/studied_gemm_cta_controller.sv)

### Implementation 52: A common backing-sector gateway

**Role.** The [sector gateway](../../numerical/multi_sm_sector_gateway.sv) gives several modeled SMs one common backing owner. Its capacity is **one combined read or write transaction**, including a response waiting for client acknowledgment. It is neither a global cache nor an identified physical memory controller.

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

The [gateway unit receipt](../../numerical/multi_sm_gateway_verification.json) checks 16 returned read words, equal external IDs across clients, captured write payloads, delayed provider responses, held client responses, one combined outstanding transaction and reset/provider flush. A wrong completion ID is rejected. These are transaction tests, not the full-grid numerical oracle. Reset cancels the owner record but cannot undo provider writes already committed. Provider work must be flushed before restart because internal IDs restart from zero. Serialization and round-robin order are development hypotheses, not RTX backing bandwidth.

Run `python studies/rtx5090_gemm_milp/rtl/numerical/verify_multi_sm_sector_gateway.py`.

**Inline behavior.**


**Source implementation:** [multi_sm_sector_gateway.sv](../../numerical/multi_sm_sector_gateway.sv)

### C++ component adapters

- [memory_controller](../../cpp/memory_controller.hpp) — adapter for [the matching Verilog source](../../components/library/memory_controller.sv).
- [gemm_tile_controller](../../cpp/gemm_tile_controller.hpp) — adapter for [the matching Verilog source](../../numerical/gemm_tile_controller.sv).
- [studied_gemm_cta_controller](../../cpp/studied_gemm_cta_controller.hpp) — adapter for [the matching Verilog source](../../numerical/studied_gemm_cta_controller.sv).
- [multi_sm_sector_gateway](../../cpp/multi_sm_sector_gateway.hpp) — adapter for [the matching Verilog source](../../numerical/multi_sm_sector_gateway.sv).

## 9. Verification and evidence

Retain the verification expectations and existing receipts in Section 8. The [integration and verification chapter](../integration_and_verification.md) separates existing numerical tests, new C++ smoke tests and GPU measurements. The most recent connected-grid receipt checks 24,576 output words; it does not calibrate the integrated cycle count.

## 10. Optimization implications and remaining gaps

Measured streaming copy bandwidth is about 1.476 TB/s in the scoped test. Applying it requires the correct traffic and concurrency; the current numerical RTL gateway is not calibrated to that aggregate bandwidth.

A parameter checked through documentation or a transferred prior can be used provisionally. Refine it when a new end-to-end case disagrees materially or when it changes the optimization choice. Do not spend time recovering a private property that the supported execution path does not exercise.
