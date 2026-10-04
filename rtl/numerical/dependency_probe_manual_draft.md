# Draft section 4.58: effective dependent-operation replay

This template awaits finalized `dependency_probe_replay.sv` and its current verification receipt. It does not claim calibrated GEMM timing.

## Purpose and measured boundary

Describe a replay of dependent operations matching the bounded measurement, rather than treating a measured compound duration as one hardware pipeline latency. The observed full-warp MOVM cost is 28.98828125 cycles per operation, rounded to 29 for this replay, from 1,024 dependent operations with unroll 32 and loop/timer work included. The observed scalar shared-load cost is 28 cycles per operation, including return, wakeup, issue and native-control effects. Neither number identifies intrinsic latency or independent initiation interval. The MOVM observation is 29,684 net cycles divided by 1,024 operations, and its end timer does not wait for the final result (`end_timer_waits_final_result = false`). A rounded 29-cycle successive-dependency spacing is therefore a calibration convention, not physical final-completion latency or exact end-to-end reproduction of the timed probe.

## Component contract

After source finalization, define the actual input operation kind/count, accepted start edge, internal state, cycle counter, completion edge and held-result behavior. State rounding and count multiplication explicitly. Define reset and any overflow/invalid-operation rejection. Inline exact source and link its runner only after the receipt matches current code.

## Verification and claim limit

Report which bounded operation/count cases are checked and the independent expected elapsed-edge calculation. Distinguish replaying a measured effective cost from recovering internal GPU pipeline stages. The loop/timer inclusion means these coefficients cannot also be charged as intrinsic service latency plus separate loop/timer overhead. Transfer to GEMM is unvalidated: its dependency chains, scheduling, overlap and resource competition differ. The largest recorded error remains 5.966342; do not change physical proof counts or classify these constants as newly identified hardware parameters.
