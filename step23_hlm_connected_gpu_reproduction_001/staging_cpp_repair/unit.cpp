#include "staging_event.hpp"
#include <iostream>
#include <map>
#include <set>
using namespace staging_event;
struct Test {Cycle first_load=NEVER,first_write=NEVER,done=0;uint64_t sectors=0,writes=0,issues=0;};
Test run(Cycle delay,bool backpressure){Staging s(11,128,96,12288);std::map<Cycle,std::vector<uint32_t>>due;std::set<uint32_t>addresses,groups;Test r;bool done=false;uint32_t old_id=0;
 for(Cycle t=0;t<20000;t++){Input in;in.request={t==0,0,0,0,0x2000000,0,0,0};in.write_ready=!backpressure||t%7!=0;auto v=s.signals(in.request,t);
 if(v.backing_valid){due[t+delay].push_back(v.backing_id);addresses.insert(v.backing_address);r.first_load=std::min(r.first_load,t);old_id=v.backing_id;}
 if(due.count(t)){if(due[t].size()!=1)throw std::runtime_error("test return collision");in.response_valid=true;in.response_id=due[t][0];}
 if(v.write_valid&&in.write_ready){if(!groups.insert(v.write_addresses[0]).second)throw std::runtime_error("duplicate sharedgroup");r.first_write=std::min(r.first_write,t);r.writes++;}
 if(v.done_valid){done=true;r.done=t;s.edge(in,t);break;}s.edge(in,t);}
 r.sectors=s.sectors();r.issues=s.instruction_issues();if(!done||r.writes!=64||r.sectors!=128||addresses.size()!=128||r.first_write<r.first_load+340)throw std::runtime_error("coverage/readiness test failed");
 bool stale_rejected=false;try{Input late;late.response_valid=true;late.response_id=old_id;s.edge(late,r.done+1);}catch(const std::runtime_error&){stale_rejected=true;}if(!stale_rejected)throw std::runtime_error("late previousstage callback accepted");return r;}
int main(){auto early=run(5,false),late=run(500,false),pressure=run(5,true);if(late.first_write<late.first_load+500||late.first_write>late.first_load+510)throw std::runtime_error("arrival max/doublecount failure");if(early.issues!=late.issues||early.issues!=pressure.issues)throw std::runtime_error("instruction count changed");std::cout<<"UNIT_PASS early_cycles="<<early.done<<" late_cycles="<<late.done<<" pressure_cycles="<<pressure.done<<" sectors="<<early.sectors<<" writes="<<early.writes<<" instructions="<<early.issues<<" early_first="<<early.first_write<<" delayed_first="<<late.first_write<<" stale_rejected=true\n";}
