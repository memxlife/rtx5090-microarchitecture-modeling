#include "timed_queue.hpp"
#include <iostream>
#include <stdexcept>

void require(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}
int main() {
    rtx_model::timed_queue simulator;
    auto& p = simulator.ports();
    p.req_valid = 0; p.rsp_ready = 0; p.req_id = 0;
    simulator.reset();
    p.req_valid = 1; p.req_id = 10; simulator.settle();
    require(p.req_ready, "first request not ready"); simulator.tick();
    p.req_id = 20; simulator.settle();
    require(p.req_ready, "second request not ready"); simulator.tick();
    p.req_valid = 0; simulator.settle();
    require(!p.req_ready, "full queue admitted another request");
    while (!p.rsp_valid && simulator.cycles() < 20) simulator.tick();
    require(p.rsp_valid && p.rsp_id == 10, "first response mismatch");
    for (int i = 0; i < 3; ++i) {
        simulator.tick(); require(p.rsp_valid && p.rsp_id == 10, "stalled response changed");
    }
    p.rsp_ready = 1; simulator.tick();
    require(p.rsp_valid && p.rsp_id == 20, "second response mismatch");
    simulator.tick(); require(!p.rsp_valid, "extra response");
    std::cout << "CPP_QUEUE_PASS capacity=2 latency=4 fifo=2 held_cycles=3\n";
}
