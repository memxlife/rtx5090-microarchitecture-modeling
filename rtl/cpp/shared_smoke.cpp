#include "shared_memory_bank.hpp"
#include <iostream>
#include <stdexcept>

void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}
int main() {
    rtx_model::shared_memory_bank simulator;
    auto& p = simulator.ports();
    p.req_valid = 0; p.rsp_ready = 0; p.write = 0; p.word_address = 0; p.write_data = 0;
    simulator.reset();
    auto access = [&](bool write) {
        p.write = write; p.word_address = 7; p.write_data = 0x12345678;
        p.req_valid = 1; simulator.settle();
        require(p.req_ready, "shared request blocked");
        auto accepted_cycle = simulator.cycles(); simulator.tick();
        p.req_valid = 0; simulator.settle();
        while (!p.rsp_valid && simulator.cycles() - accepted_cycle < 10) simulator.tick();
        require(p.rsp_valid && p.read_data == 0x12345678, "shared value mismatch");
        require(simulator.cycles() - accepted_cycle == 3, "shared timing mismatch");
        simulator.tick(); require(p.rsp_valid && p.read_data == 0x12345678, "held shared value changed");
        p.rsp_ready = 1; simulator.tick(); p.rsp_ready = 0; simulator.settle();
    };
    access(true); access(false);
    std::cout << "CPP_SHARED_PASS write_read=2 latency=3 held_response=true\n";
}
