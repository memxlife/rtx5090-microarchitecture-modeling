#pragma once
#include <cstdint>
#include <memory>
#include <verilated.h>

namespace rtx_model {
// Drive the same rising-edge contract as the linked SystemVerilog module.
// A tick settles inputs before the edge and evaluates registered updates after it.
template<class GeneratedModel> class ClockedModel {
    std::unique_ptr<VerilatedContext> context_;
    std::unique_ptr<GeneratedModel> model_;
    std::uint64_t cycles_ = 0;
public:
    ClockedModel() : context_(std::make_unique<VerilatedContext>()),
                     model_(std::make_unique<GeneratedModel>(context_.get())) {}
    ClockedModel(const ClockedModel&) = delete;
    ClockedModel& operator=(const ClockedModel&) = delete;
    GeneratedModel& ports() { return *model_; }
    void settle() { model_->eval(); }
    void tick() {
        model_->clk = 0; model_->eval();
        context_->timeInc(1);
        model_->clk = 1; model_->eval();
        context_->timeInc(1);
        model_->clk = 0; model_->eval();
        ++cycles_;
    }
    void reset() {
        model_->rst = 1; tick();
        model_->rst = 0; settle();
        cycles_ = 0;
    }
    std::uint64_t cycles() const { return cycles_; }
    ~ClockedModel() { model_->final(); }
};

template<class GeneratedModel> class CombinationalModel {
    std::unique_ptr<VerilatedContext> context_;
    std::unique_ptr<GeneratedModel> model_;
public:
    CombinationalModel() : context_(std::make_unique<VerilatedContext>()),
                          model_(std::make_unique<GeneratedModel>(context_.get())) {}
    GeneratedModel& ports() { return *model_; }
    void evaluate() { model_->eval(); }
    ~CombinationalModel() { model_->final(); }
};
} // namespace rtx_model
