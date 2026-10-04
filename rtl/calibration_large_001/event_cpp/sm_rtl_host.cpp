#include "Vlarge_gemm_complete.h"
#include "verilated.h"
#include "sm_event.hpp"
#include <deque>
#include <iostream>

#ifndef TEST_CONTEXTS
#define TEST_CONTEXTS 2
#endif
#ifndef TEST_COLUMNS
#define TEST_COLUMNS 96
#endif
struct Return{uint64_t due;uint32_t id;};
int main(){Vlarge_gemm_complete d;d.rst=1;d.clk=0;d.eval();d.clk=1;d.eval();d.rst=0;sm_event::SM sm(TEST_CONTEXTS,64,TEST_COLUMNS,64);std::deque<Return>reads,writes;int launched=0,done=0;uint64_t nr=0,nw=0,ni=0;
 for(uint64_t t=0;t<200000;t++){
 sm_event::Input i;i.launch=launched<2*(TEST_COLUMNS/32);i.id=launched;i.row=launched/(TEST_COLUMNS/32);i.col=launched%(TEST_COLUMNS/32);i.a=4096;i.b=12288;i.c=131072;i.read_ready=t%7!=0;i.write_ready=t%11!=0;i.done_ready=t%13!=0;
 if(!reads.empty()&&reads.front().due<=t){i.read_return=reads.front().id;reads.pop_front();}if(!writes.empty()&&writes.front().due<=t){i.write_return=writes.front().id;writes.pop_front();}
 d.launch_valid=i.launch;d.launch_id=i.id;d.cta_row=i.row;d.cta_col=i.col;d.a_base=i.a;d.b_base=i.b;d.c_base=i.c;d.done_ready=i.done_ready;d.backing_req_ready=i.read_ready;d.store_backing_req_ready=i.write_ready;d.backing_rsp_valid=i.read_return.has_value();d.backing_rsp_id=i.read_return.value_or(0);d.store_backing_rsp_valid=i.write_return.has_value();d.store_backing_rsp_id=i.write_return.value_or(0);d.clk=0;d.eval();auto s=sm.signals(t,i);
 bool eq=s.launch_ready==bool(d.launch_ready)&&s.done==bool(d.done_valid)&&s.read.valid==bool(d.backing_req_valid)&&s.write.valid==bool(d.store_backing_req_valid)&&s.native_issue==bool(d.native_issue_valid)&&s.resident==d.resident_blocks;
 if(s.done)eq&=s.done_id==d.done_id&&s.done_context==d.done_context;if(s.read.valid)eq&=s.read.id==d.backing_req_id&&s.read.address==d.backing_req_byte_address;if(s.write.valid)eq&=s.write.id==d.store_backing_req_id&&s.write.address==d.store_backing_req_byte_address&&s.write.mask==d.store_backing_req_word_mask;
 if(s.native_issue)eq&=s.native_context==d.native_issue_context&&s.native_warp==d.native_issue_warp&&s.native_pc==d.native_issue_pc;
 if(!eq){std::cerr<<"SM_DIFF_FAIL t="<<t<<" launch "<<s.launch_ready<<int(d.launch_ready)<<" done "<<s.done<<int(d.done_valid)<<" read "<<s.read.valid<<int(d.backing_req_valid)<<" write "<<s.write.valid<<int(d.store_backing_req_valid)<<" native "<<s.native_issue<<int(d.native_issue_valid)<<" resident "<<s.resident<<","<<d.resident_blocks<<"\n";if(s.native_issue||d.native_issue_valid)std::cerr<<"native cpp "<<s.native_context<<","<<s.native_warp<<","<<s.native_pc<<" rtl "<<d.native_issue_context<<","<<d.native_issue_warp<<","<<d.native_issue_pc<<"\n";return 1;}
 if(i.launch&&s.launch_ready)launched++;if(s.read.valid&&i.read_ready){reads.push_back({t+31,s.read.id});nr++;}if(s.write.valid&&i.write_ready){writes.push_back({t+17,s.write.id});nw++;}ni+=s.native_issue;if(s.done&&i.done_ready)done++;
 sm.edge(t,i);d.clk=1;d.eval();if(done==2*(TEST_COLUMNS/32)){std::cout<<"SM_RTL_PASS cycles="<<t+1<<" CTAs="<<done<<" reads="<<nr<<" writes="<<nw<<" native="<<ni<<"\n";return 0;}}
 return 1;
}
