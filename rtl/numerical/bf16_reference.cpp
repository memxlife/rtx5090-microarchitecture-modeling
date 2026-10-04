// Simulation-only reference arithmetic. Not NVIDIA Tensor Core implementation.
#include <bit>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstdint>
static void require_supported(uint32_t bits, unsigned fraction, unsigned exponent) {
    uint32_t e=(bits>>fraction)&((1u<<exponent)-1u);
    uint32_t f=bits&((1u<<fraction)-1u);
    if(e==((1u<<exponent)-1u)||(e==0&&f!=0)) {
        std::fputs("Unsupported reference arithmetic: nonfinite or subnormal operand/result\n",stderr);
        std::abort();
    }
}
extern "C" unsigned int reference_bf16_fma(unsigned int a,unsigned int b,unsigned int c) {
    require_supported(a,7,8);require_supported(b,7,8);require_supported(c,23,8);
    float av=std::bit_cast<float>(uint32_t(a<<16));
    float bv=std::bit_cast<float>(uint32_t(b<<16));
    float cv=std::bit_cast<float>(uint32_t(c));
    float result=std::fma(av,bv,cv);
    uint32_t bits=std::bit_cast<uint32_t>(result);
    require_supported(bits,23,8);
    return bits;
}

// Candidate arithmetic reconstructed from magnitude-alignment probes.
// Validated cancellation family only; no claim of complete Tensor Core behavior.
#include "svdpi.h"
extern "C" unsigned int reference_bf16_aligned_dot(
    const svOpenArrayHandle a,const svOpenArrayHandle b,unsigned int c) {
    require_supported(c,23,8);
    double values[17],maximum=0;
    for(int k=0;k<16;k++) {
        uint32_t av=*static_cast<const uint32_t*>(svGetArrElemPtr1(a,k));
        uint32_t bv=*static_cast<const uint32_t*>(svGetArrElemPtr1(b,k));
        require_supported(av,7,8);require_supported(bv,7,8);
        values[k]=double(std::bit_cast<float>(av<<16))*double(std::bit_cast<float>(bv<<16));
        maximum=std::fmax(maximum,std::fabs(values[k]));
    }
    values[16]=double(std::bit_cast<float>(uint32_t(c)));
    maximum=std::fmax(maximum,std::fabs(values[16]));
    if(maximum==0)return 0;
    int exponent=std::ilogb(maximum);
    double quantum=std::ldexp(1.0,exponent-25);
    int64_t aligned=0;
    for(double value:values) aligned+=int64_t(std::trunc(value/quantum));
    float result=float(double(aligned)*quantum);
    uint32_t bits=std::bit_cast<uint32_t>(result);
    require_supported(bits,23,8);
    return bits;
}
