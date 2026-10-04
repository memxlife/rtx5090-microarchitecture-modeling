#include "units.hpp"
#include <chrono>
#include <iostream>
#include <tuple>
#include <vector>
using namespace timing;
using Event=std::tuple<Cycle,unsigned,uint32_t>;
std::vector<Event> run(bool jump,Cycle limit,uint64_t& edges){Matrix m(4,7,3);Shared s(4,2,3);std::vector<Event> log;std::array<uint32_t,32>a;for(unsigned l=0;l<32;l++)a[l]=l*128;Cycle next_req=0;for(Cycle t=0;t<limit;){++edges;bool req=t==next_req;if(req)next_req+=37;uint32_t id=uint32_t(t/37+1);if(req&&m.ready(t))log.emplace_back(t,0,id);if(m.valid(t))log.emplace_back(t,1,m.id());if(req&&s.ready())log.emplace_back(t,2,id);if(s.valid(t))log.emplace_back(t,3,s.id());m.edge(t,req,id,true);s.edge(t,req,id,true,a);if(jump)t=std::max(t+1,std::min({next_req,m.wake(t),s.wake(t)}));else ++t;}return log;}
int main(){uint64_t slow_edges=0,fast_edges=0;auto start=std::chrono::steady_clock::now();auto slow=run(false,1000000,slow_edges);auto mid=std::chrono::steady_clock::now();auto fast=run(true,1000000,fast_edges);auto end=std::chrono::steady_clock::now();if(slow!=fast)throw std::runtime_error("event trace mismatch");std::cout<<"exact_events="<<fast.size()<<" cycle_edges="<<slow_edges<<" event_edges="<<fast_edges<<" cycle_seconds="<<std::chrono::duration<double>(mid-start).count()<<" event_seconds="<<std::chrono::duration<double>(end-mid).count()<<'\n';}
