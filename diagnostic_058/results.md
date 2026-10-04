# Can clock differences explain the remaining timing error?

Separate phase measurements predict the tested full GEMM about 5% too slowly at its normal resident-block limit. We checked whether those phases and the full GEMM execute in different clock contexts, before changing any model coefficients.

Eight ordinary timing cases passed 360 output checks. Host-side clock queries left the native GPU kernels unchanged. However, readings immediately before and after a kernel do not measure its average clock while executing, so we did not use those snapshots to rescale runtime.

Minimal counter profiles produced these observations for the longer cases:

| Program path | Reported SM counter rate | Profile duration versus ordinary median |
|---|---:|---:|
| Input staging | 2.664 GHz | 0.15% shorter |
| Operand loading and computation | 2.932 GHz | 0.61% shorter |
| Complete GEMM | 2.850 GHz | 0.12% shorter |

The short common-work path differed by 7.1%, or 1.75 microseconds, under profiling. Its counter rate was 2.930 GHz. Profiling is therefore not equally representative for every path. The dominant paths nevertheless have close timing agreement while their reported counter rates differ.

This shows why measured phase costs need an explicit operating context. It does not establish that every part of staging scales with the SM clock: requests also use the memory system, and queueing and overlap can change with the rate at which instructions arrive.

We calculated a sensitivity hypothesis that lets an unknown fraction of each phase scale with SM frequency, with the remaining fraction unchanged. Under constant representative frequencies and unchanged queueing, it gives a composed stage cost from 4.728 to 4.975 microseconds. The observed full-kernel runtime increase corresponds to 4.694 microseconds per step. The hypothesis does not cover that value.

This is a retrospective diagnostic, not a physical bound or a new predictive validation. The counter rate for the full kernel was measured only at the longer reduction, so it does not establish the operating context at both lengths. We therefore admitted no blind clock correction. The executable model retains the clock-sensitive fractions and phase interactions as unresolved; its runtime coefficients remain unchanged.

The [ordinary measurements](ordinary_analysis.json), [minimal profiles](minimal_analysis.json), and [sensitivity hypothesis](clock_hypothesis.json) preserve these findings. The current benchmark set is complete, and the user requested stopping after this set.
