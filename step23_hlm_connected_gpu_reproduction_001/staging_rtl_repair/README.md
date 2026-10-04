# Repaired staging component

Does the experimental Verilog staging component follow the repaired C++ component cycle by cycle? The differential test passes 921,445 protocol, address and counter comparisons across three scenarios. It checks three simultaneous block contexts, two stages each, early and late memory returns, and output backpressure. The [receipt](parity_receipt.json) records source hashes and exact coverage.

The component delays a loaded register until both its 340-cycle provisional readiness interval and its actual memory return have completed. Dependent shared stores then wait for that register. The Verilog implementation follows the C++ edge ordering explicitly; it is behavioral simulation code, not a synthesis-ready implementation.

Run from this directory with Verilator installed:

```sh
verilator --cc --exe --build -j 4 -Wno-fatal --top-module repaired_staging \
  --Mdir /private/tmp/staging_rtl_repair_build -I. -CFLAGS '-std=c++20 -O2' \
  "$PWD/repaired_staging.sv" "$PWD/parity.cpp"
/private/tmp/staging_rtl_repair_build/Vrepaired_staging
```

The test separately checks 36,864 BF16 halfwords, the 16-bit operand format, against an address-based oracle. Host C++ multiplies the delivered operands and checks each stage product. This is not a Verilog matrix-compute test or full-chip timing validation. Reset occurs before each scenario; midflight reset and invalid RTL responses are not tested. C++ rejects stale completed-stage responses.

[The adapter](large_operand_staging_repaired.sv) preserves the existing numerical staging interface and passes compilation lint. It intentionally exports the original module name, so compile it instead of the baseline module, never alongside it. Its compatibility cache parameters are unused because memory responses arrive through the external backing interface. It has not been integrated into a full numerical Verilog matrix execution.

Component agreement does not establish hardware accuracy. The C++ candidate remains experimental: its focused timing error is −11.05%, and its dense regression is +31.57%. It must not replace the preserved baseline.
