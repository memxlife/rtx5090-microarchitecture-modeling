#include "Vstaging_component_top.h"
#include "verilated.h"
#include "staging_event.hpp"
#include <algorithm>
#include <iostream>
#ifndef TEST_CONTEXTS
#define TEST_CONTEXTS 2
#endif
struct Return{uint64_t due;uint32_t id;};
int main(){Vstaging_component_top d;d.rst=1;d.clk=0;d.eval();d.clk=1;d.eval();d.rst=0;staging_event::Staging model(TEST_CONTEXTS,2048,2112,1536);std::vector<Return>pending;
 uint64_t t=0;for(;t<100000&&model.completions()<TEST_CONTEXTS;t++){
 staging_event::Input i;i.request.valid=t%2==0&&t/2<TEST_CONTEXTS;i.request.context=t/2;i.request.id=t/2;i.request.a_base=4096;i.request.b_base=6299648;i.request.row=t/2;i.request.col=t/2;
 i.backing_ready=t%7!=0;i.write_ready=t%11!=0;i.done_ready=t%13!=0;
 auto ret=std::min_element(pending.begin(),pending.end(),[](auto&a,auto&b){return a.due<b.due;});if(ret!=pending.end()&&ret->due<=t){i.response_valid=true;i.response_id=ret->id;pending.erase(ret);}
 d.req_valid=i.request.valid;d.req_context=i.request.context;d.backing_ready=i.backing_ready;d.write_ready=i.write_ready;d.done_ready=i.done_ready;d.response_valid=i.response_valid;d.response_id=i.response_id;d.clk=0;d.eval();auto s=model.signals(i.request);
 bool equal=s.request_ready==bool(d.req_ready)&&s.backing_valid==bool(d.backing_valid)&&s.write_valid==bool(d.write_valid)&&s.done_valid==bool(d.done_valid);
 if(s.backing_valid)equal&=s.backing_id==d.backing_id&&s.backing_address==d.backing_address;
 if(s.write_valid)equal&=s.write_context==d.write_context&&s.write_addresses[0]==d.write_base;
 if(s.done_valid)equal&=s.done_context==d.done_context&&s.done_id==d.done_id;
 if(!equal){std::cerr<<"STAGING_MISMATCH cycle="<<t<<" valid C++ "<<s.backing_valid<<s.write_valid<<s.done_valid<<" RTL "<<int(d.backing_valid)<<int(d.write_valid)<<int(d.done_valid)<<"\n";return 1;}
 if(s.backing_valid&&i.backing_ready)pending.push_back({t+10+s.backing_id%5,s.backing_id});model.edge(i);d.clk=1;d.eval();}
 if(model.completions()!=TEST_CONTEXTS)throw std::runtime_error("staging incomplete");std::cout<<"STAGING_RTL_PASS contexts="<<TEST_CONTEXTS<<" cycles="<<t<<" sector_requests="<<model.sectors()<<" commits="<<model.commits()<<"\n";
}
