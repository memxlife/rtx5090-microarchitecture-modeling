#include "Vnative_component_top.h"
#include "verilated.h"
#include "native_stage_event.hpp"
#include <iostream>

#ifndef TEST_CONTEXTS
#define TEST_CONTEXTS 1
#endif
int main(){Vnative_component_top d;auto tick=[&](){d.clk=0;d.eval();d.clk=1;d.eval();};d.rst=1;tick();d.rst=0;
 d.write_valid=1;for(int ctx=0;ctx<TEST_CONTEXTS;ctx++){d.write_context=ctx;for(int i=0;i<64;i++){d.write_base=i*64;tick();}}d.write_valid=0;
 native_event::Config c;c.contexts=TEST_CONTEXTS;native_event::Stage model(c);for(int ctx=0;ctx<TEST_CONTEXTS;ctx++)model.set_context_start(ctx,ctx*3+1);model.run();
 std::vector<native_event::Event> rtl;
 for(uint64_t t=0;t<model.cycles()+20;t++){
 d.req_valid=t%3==0&&t/3<TEST_CONTEXTS;d.req_context=t/3;d.clk=0;d.eval();
 // Executor reports return before issue for a simultaneous edge.
 if(d.completion_valid)rtl.push_back({t,1,int(d.completion_warp),int(d.completion_pc)});
 if(d.issue_valid)rtl.push_back({t,0,int(d.issue_warp),int(d.issue_pc)});
 d.clk=1;d.eval();}
 if(rtl!=model.trace()){
 for(size_t i=0;i<std::max(rtl.size(),model.trace().size());i++)if(i>=rtl.size()||i>=model.trace().size()||!(rtl[i]==model.trace()[i])){
 auto a=i<rtl.size()?rtl[i]:native_event::Event{0,-1,0,0};auto b=i<model.trace().size()?model.trace()[i]:native_event::Event{0,-1,0,0};
 std::cerr<<"mismatch "<<i<<" RTL "<<a.cycle<<","<<a.kind<<","<<a.warp<<","<<a.pc<<" C++ "<<b.cycle<<","<<b.kind<<","<<b.warp<<","<<b.pc<<"\n";return 1;}}
 std::cout<<"NATIVE_RTL_EVENT_PASS events="<<rtl.size()<<" cycles="<<model.cycles()<<"\n";
}
