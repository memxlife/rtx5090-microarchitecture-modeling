#pragma once
#include <array>
#include <cstdint>
#include <deque>
#include <vector>
#include <algorithm>
#include <stdexcept>
namespace timing {
using Cycle=uint64_t;
struct Packet {uint32_t id;Cycle due;};
// Inputs are evaluated before an edge. A full queue cannot reuse a retiring slot on that edge.
class Matrix {
 std::deque<Packet> q;Cycle next_accept=0;unsigned slots,latency,interval;
public:
 Matrix(unsigned s,unsigned l,unsigned i):slots(s),latency(l),interval(i){}
 bool ready(Cycle t)const{return q.size()<slots&&t>=next_accept;}
 bool valid(Cycle t)const{return !q.empty()&&t>=q.front().due;}
 uint32_t id()const{return q.empty()?0:q.front().id;}
 size_t size()const{return q.size();}
 Cycle wake(Cycle t)const{return std::min(next_accept>t?next_accept:UINT64_MAX,!q.empty()&&q.front().due>t?q.front().due:UINT64_MAX);}
 void edge(Cycle t,bool rv,uint32_t id,bool rr){bool push=rv&&ready(t),pop=rr&&valid(t);if(push)for(auto p:q)if(p.id==id)throw std::runtime_error("duplicate matrix ID");if(pop)q.pop_front();if(push){q.push_back({id,t+latency});next_accept=t+interval;}}
};
class Shared {
 std::deque<Packet> q;Cycle next_service=0;unsigned slots,interval,delay;
public:
 Shared(unsigned s,unsigned i,unsigned d):slots(s),interval(i),delay(d){}
 static unsigned packages(const std::array<uint32_t,32>& a){std::array<unsigned,32> n{};for(unsigned l=0;l<32;l++){bool first=true;for(unsigned e=0;e<l;e++)if(a[l]==a[e])first=false;if(first)++n[(a[l]>>2)&31];}return *std::max_element(n.begin(),n.end());}
 bool ready()const{return q.size()<slots;}
 bool valid(Cycle t)const{return !q.empty()&&t>=q.front().due;}
 uint32_t id()const{return q.empty()?0:q.front().id;}
 size_t size()const{return q.size();}
 Cycle wake(Cycle t)const{return !q.empty()&&q.front().due>t?q.front().due:UINT64_MAX;}
 void edge(Cycle t,bool rv,uint32_t id,bool rr,const std::array<uint32_t,32>& a){bool push=rv&&ready(),pop=rr&&valid(t);if(push)for(auto p:q)if(p.id==id)throw std::runtime_error("duplicate shared ID");if(pop)q.pop_front();if(push){auto first=std::max(t+1,next_service),last=first+(packages(a)-1)*interval;next_service=last+interval;q.push_back({id,last+delay+1});}}
};
class Tracker {
 std::vector<bool> active;std::vector<unsigned> label;std::array<unsigned,6> counts{};bool error=false;
public:
 Tracker(unsigned slots=8):active(slots,false),label(slots,0){}
 bool ready(unsigned tag,unsigned bar)const{return tag<active.size()&&bar<6&&!active[tag];}
 unsigned busy()const{unsigned m=0;for(unsigned b=0;b<6;b++)if(counts[b])m|=1<<b;return m;}
 bool wait(unsigned m)const{return !(m&busy());}
 bool bad()const{return error;}
 const auto& pending()const{return counts;}
 void edge(bool iv,unsigned tag,unsigned bar,bool cv,unsigned complete){bool push=iv&&ready(tag,bar);if(iv&&(tag>=active.size()||bar>=6))error=true;if(cv){if(complete>=active.size()||!active[complete])error=true;else{active[complete]=false;--counts[label[complete]];}}if(push){active[tag]=true;label[tag]=bar;++counts[bar];}}
};
}
