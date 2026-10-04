// Execute the identical timed SystemVerilog harness through an explicit C++ host.
// This checks host execution equivalence; it is not an independent state model.
#include <memory>
#include <verilated.h>
#include <Vresident_gemm_multi_sm_nb_l2_tb.h>
int main(int argc,char** argv) {
    auto context=std::make_unique<VerilatedContext>();
    context->commandArgs(argc,argv);
    auto model=std::make_unique<Vresident_gemm_multi_sm_nb_l2_tb>(context.get());
    while(!context->gotFinish()) {
        model->eval();
        if(!model->eventsPending()) break;
        context->time(model->nextTimeSlot());
    }
    model->final();
    return context->gotFinish()?0:2;
}
