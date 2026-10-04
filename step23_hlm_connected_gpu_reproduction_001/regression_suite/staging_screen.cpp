#include "staging_event.hpp"
#include <iostream>
#include <set>
#include <deque>
template<class T> auto read_signals(T&m,const staging_event::Request&r,unsigned t){if constexpr(requires{m.edge(staging_event::Input{},t);})return m.signals(r,t);else return m.signals(r);}
template<class T> void advance(T&m,const staging_event::Input&i,unsigned t){if constexpr(requires{m.edge(i,t);})m.edge(i,t);else m.edge(i);}
int main(){staging_event::Staging model(1,128,96,12288);bool offered=false,done=false;std::deque<std::pair<unsigned,uint32_t>>pending;std::set<uint32_t>written;unsigned requests=0,groups=0;
for(unsigned t=0;t<10000&&!done;t++){staging_event::Input i;i.request={!offered,0,7,0,0x2000000,0,0,0};auto s=read_signals(model,i.request,t);if(i.request.valid&&s.request_ready)offered=true;
if(s.backing_valid){pending.emplace_back(t+4,s.backing_id);requests++;}
if(!pending.empty()&&pending.front().first<=t){i.response_valid=true;i.response_id=pending.front().second;pending.pop_front();}
if(s.write_valid){groups++;for(auto a:s.write_addresses)if(a&1||a>=4096||!written.insert(a).second)throw std::runtime_error("shared address coverage");}
if(s.done_valid){if(s.done_id!=7)throw std::runtime_error("completion ownership");done=true;}advance(model,i,t);}
if(!done||requests!=128||groups!=64||written.size()!=2048||model.outstanding()!=0)throw std::runtime_error("incomplete staging contract");
std::cout<<"STAGING_SCREEN_PASS requests="<<requests<<" groups="<<groups<<" words="<<written.size()<<" cycles="<<model.cycle()<<"\n";}
