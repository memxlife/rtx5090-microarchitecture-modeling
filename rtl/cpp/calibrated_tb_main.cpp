// Explicit C++ host for the same timed SystemVerilog calibration harness.
#include <memory>
#include <verilated.h>
#include <Vcalibration_connected_tb.h>
int main(int argc,char** argv) {
    auto context=std::make_unique<VerilatedContext>();
    context->commandArgs(argc,argv);
    auto model=std::make_unique<Vcalibration_connected_tb>(context.get());
    while(!context->gotFinish()) {
        model->eval();
        if(!model->eventsPending()) break;
        context->time(model->nextTimeSlot());
    }
    model->final();
    return context->gotFinish()?0:2;
}
