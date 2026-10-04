#pragma once
#include "l2_slice.hpp"
namespace timing {
// Metadata provider reproduces the existing host's fixed-delay, head-held packet queues.
// Service credit is effective measured read throughput in sectors per reference cycle.
class Backing {
 struct Pending{uint32_t id,address;Cycle due;bool write;};
 std::vector<std::deque<Pending>> queues;double credit=0,rate;unsigned read_delay,write_delay;
public:
 Backing(unsigned slices,double sectors_per_cycle=16.6694010417,unsigned rd=31,unsigned wd=17):queues(slices),rate(sectors_per_cycle),read_delay(rd),write_delay(wd){}
 struct Ports{std::vector<bool>read_ready,write_ready;std::vector<std::optional<uint32_t>>read_return,write_return;explicit Ports(unsigned n):read_ready(n),write_ready(n),read_return(n),write_return(n){}};
 Ports prepare(Cycle t,const std::vector<L2Output>& offer){credit=std::min(credit+rate,2*rate);double available=credit;Ports p(queues.size());for(unsigned s=0;s<queues.size();s++){auto&q=queues[s];p.read_ready[s]=q.size()<16&&available>=1;if(p.read_ready[s]&&offer[s].backing.valid)available-=1;p.write_ready[s]=q.size()<15;if(!q.empty()&&q.front().due<=t){if(q.front().write)p.write_return[s]=q.front().id;else p.read_return[s]=q.front().id;}}return p;}
 void edge(Cycle t,const std::vector<L2Output>& offer,const Ports& p){for(unsigned s=0;s<queues.size();s++){auto&q=queues[s];if(p.read_return[s]||p.write_return[s])q.pop_front();if(offer[s].backing.valid&&p.read_ready[s]){auto x=offer[s].backing;credit-=1;q.push_back({x.id,x.address,t+read_delay,false});}if(offer[s].store.valid&&p.write_ready[s]){auto x=offer[s].store;q.push_back({x.id,x.address,t+write_delay,true});}}}
 Cycle wake(Cycle now)const{Cycle t=UINT64_MAX;for(const auto&q:queues)if(!q.empty())t=std::min(t,std::max(now,q.front().due));return t;}
 void idle_edges(Cycle n){credit=std::min(credit+double(n)*rate,2*rate);}
 size_t outstanding()const{size_t n=0;for(auto&q:queues)n+=q.size();return n;}
};
}
