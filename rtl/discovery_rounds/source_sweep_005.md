# Source sweep 5: allocation rules admitted

The literature subagent used Google through Chrome to research official CUDA and PTX documentation. Its [source review](literature_sweep_005.md) supplies citations and scope. This integration independently checked the installed CUDA 12.8.93 occupancy helper functions for compute capability 12.0 and implemented their allocation arithmetic. No new GPU workload ran.

Two functional fields are now identified within the CUDA allocation model: **F001 rounds registers to 256 32-bit words per warp**, and **F002 rounds shared allocation to 128 bytes per block**. Register demand is rounded per warp before multiplying by warp count. Shared demand includes application and runtime-reserved storage before rounding. These rules do not identify physical register banks or SRAM rows.

The new Verilog component [allocation_demands.sv](../components/allocation_demands.sv) also calculates the separate launch-check demand using warp count rounded to four partitions. The small saved GEMM needs 9,216 shared bytes including its 1,024-byte reservation, rather than 8,192 application bytes. The larger needs 12,288 rather than 11,264. Omitting the reservation can overestimate residency.

Six directed Verilog checks passed, including saved demands, a partial-warp boundary and invalid inputs. The toolkit helper functions returned the expected quantums in a local compiled check. The component is not yet connected to the full GPU model.

| Category | Newly identified | Newly partial | Cumulative identified | Remaining |
|---|---:|---:|---:|---:|
| Functional | 2 | 5 | 7 | 80 |
| Timing | 0 | 1 | 0 | 47 |
| Total | 2 | 6 | 7 | 127 |

Remaining totals include **14 partial functional and 2 partial timing fields**. No fields were added. Partial findings cover divergence, reconvergence, scalar arithmetic, virtual matrix fragments, global transaction segments and aggregate execution-rate ceilings. Native routing, arbitration and individual timing remain unresolved.

The source review also found conflicting residency figures. Saved device attributes agree with the Programming Guide on 24 blocks and 100 KiB allocatable shared memory per SM. The tuning guide's 32-block and 128-KiB figures must not replace the queried device values. The 128-KiB unified L1/shared pool is a different capacity.
