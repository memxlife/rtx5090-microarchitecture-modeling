# Four-partition staging consistency test

Does Verilog reproduce the experimental four-partition C++ staging component? The differential test passes 943,985 protocol, address and counter comparisons across four scenarios. It completes 24 operand frames and separately checks 49,152 BF16 values, a 16-bit floating-point format, against an address-based oracle. [The receipt](parity_receipt.json) records the exact sources and commands.

Each partition has its own context round-robin cursor and can issue one producer instruction per cycle. The four-bit `blocked_partitions` input prevents staging from issuing on partitions reserved by native compute. All partitions still share the 32-entry load and store queues; their allocations occur in partition order. The 340-cycle provisional readiness floor and actual-return boundary remain unchanged.

The first three scenarios cover early returns, late returns, and output backpressure. The fourth adds all-partition stalls and rotating native partition reservations. Reset occurs before each scenario. Midflight reset and invalid RTL return IDs are not tested; stale response rejection is checked only in C++. Host C++ multiplies RTL-delivered operands to check stage products. No Verilog arithmetic pipeline, full GEMM execution, or GPU timing calibration is tested.

Run from this directory:

```sh
verilator --cc --exe --build -j 4 -Wno-fatal --top-module repaired_staging \
  --Mdir /private/tmp/staging_partition_rtl_build -I. -CFLAGS '-std=c++20 -O2' \
  "$PWD/repaired_staging.sv" "$PWD/parity.cpp"
/private/tmp/staging_partition_rtl_build/Vrepaired_staging
```

This behavioral component follows the C++ transition ordering rather than a synthesis-ready design. Passing parity means both implementations use the same rules. It does not make those rules an identified RTX 5090 microarchitecture, and the candidate is not promoted.
