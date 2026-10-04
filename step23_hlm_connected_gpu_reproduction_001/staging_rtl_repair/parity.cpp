#include "Vrepaired_staging.h"
#include "verilated.h"
#include "../staging_cpp_repair/staging_event.hpp"
#include <deque>
#include <set>
#include <cstring>
#include <iostream>
#include <cmath>
using namespace staging_event;
struct Packet{Cycle due;uint32_t id,address;};
uint16_t data(uint32_t address){bool b=address>=0x2000000;uint32_t idx=(address-(b?0x2000000:0))/2;float v=float(int(idx%(b?13:17))-(b?6:8))/16.f;uint32_t z;std::memcpy(&z,&v,4);return z>>16;}
float bf(uint16_t h){uint32_t x=uint32_t(h)<<16;float v;std::memcpy(&v,&x,4);return v;}
void eq(uint64_t a,uint64_t b,const char*name,Cycle t){if(a!=b){std::cerr<<"MISMATCH "<<name<<" t="<<t<<" cpp="<<a<<" rtl="<<b<<"\n";throw std::runtime_error("parity");}}
int main(int argc,char**argv){Verilated::commandArgs(argc,argv);uint64_t fields=0,completed=0,values=0;double checksum=0;
for(int scenario=0;scenario<3;scenario++){Vrepaired_staging v;Staging gold(3,128,96,12288);v.clk=0;v.rst=1;v.cycle=0;v.eval();v.clk=1;v.eval();v.clk=0;v.rst=0;std::deque<Packet>pending;std::array<int,3>launches{},done{};std::array<std::array<uint16_t,2048>,3>frames{};std::array<std::set<uint32_t>,3>seen;uint32_t lastid=0;Cycle end=0;
for(Cycle t=0;t<30000;t++){Input in;in.backing_ready=!(scenario==2&&(t%11<3));in.write_ready=!(scenario==2&&(t%13<5));in.done_ready=!(scenario==2&&(t%17<7));
 int offer=-1;for(int c=0;c<3;c++)if(launches[c]<2&&done[c]==launches[c]&&t>=unsigned(40*c)){offer=c;break;}
 if(offer>=0)in.request={true,uint32_t(offer),uint32_t(100*offer+launches[offer]),0,0x2000000,uint32_t(offer),uint32_t(offer%3),uint32_t(launches[offer])};
 if(!pending.empty()&&pending.front().due<=t){in.response_valid=true;in.response_id=pending.front().id;lastid=in.response_id;}
 v.cycle=t;v.req_valid=in.request.valid;v.req_context=in.request.context;v.req_id=in.request.id;v.a_base=in.request.a_base;v.b_base=in.request.b_base;v.cta_row=in.request.row;v.cta_col=in.request.col;v.stage_index=in.request.stage;v.backing_ready=in.backing_ready;v.write_ready=in.write_ready;v.done_ready=in.done_ready;v.response_valid=in.response_valid;v.response_id=in.response_id;
 for(int x=0;x<8;x++)v.response_data[x]=0;if(in.response_valid)for(int x=0;x<16;x++)v.response_data[x/2]|=uint32_t(data(pending.front().address+2*x))<<(16*(x%2));
 v.eval();auto s=gold.signals(in.request,t);
 eq(s.request_ready,v.req_ready,"req_ready",t);eq(s.backing_valid,v.backing_valid,"backing_valid",t);eq(s.backing_id,v.backing_id,"backing_id",t);eq(s.backing_address,v.backing_address,"backing_address",t);eq(s.write_valid,v.write_valid,"write_valid",t);eq(s.write_context,v.write_context,"write_context",t);eq(s.done_valid,v.done_valid,"done_valid",t);eq(s.done_context,v.done_context,"done_context",t);eq(s.done_id,v.done_id,"done_id",t);eq(gold.outstanding(),v.outstanding,"outstanding",t);
 for(int c=0;c<3;c++)eq(gold.context_ready(c),bool(v.context_ready&(1<<c)),"context_ready",t);for(int x=0;x<32;x++)eq(s.write_addresses[x],v.write_addresses[x],"writeaddress",t);fields+=45;
 if(in.request.valid&&s.request_ready){int c=in.request.context;launches[c]++;seen[c].clear();frames[c].fill(0);}
 if(s.write_valid&&in.write_ready){int c=s.write_context;for(int x=0;x<32;x++){auto at=s.write_addresses[x]/2;if(!seen[c].insert(at).second)throw std::runtime_error("duplicate write");uint32_t global=at<1024?2*((c*32+at/32)*12288+(launches[c]-1)*32+at%32):0x2000000+2*(((launches[c]-1)*32+(at-1024)/32)*96+(c%3)*32+(at-1024)%32);eq(data(global),v.write_halfwords[x],"halfword",t);frames[c][at]=v.write_halfwords[x];values++;}}
 if(s.done_valid&&in.done_ready){int c=s.done_context;if(seen[c].size()!=2048)throw std::runtime_error("incomplete frame");for(int r=0;r<32;r++)for(int col=0;col<32;col++){float out=0,ref=0;for(int k=0;k<32;k++){out+=bf(frames[c][r*32+k])*bf(frames[c][1024+k*32+col]);uint32_t a=2*((c*32+r)*12288+(launches[c]-1)*32+k),b=0x2000000+2*(((launches[c]-1)*32+k)*96+(c%3)*32+col);ref+=bf(data(a))*bf(data(b));}if(out!=ref)throw std::runtime_error("matrix numerical mismatch");checksum+=out;}done[c]++;completed++;}
 if(in.response_valid)pending.pop_front();if(s.backing_valid&&in.backing_ready){Cycle delay=scenario==1?500:5;pending.push_back({t+delay,s.backing_id,s.backing_address});}
 gold.edge(in,t);v.clk=1;v.eval();v.clk=0;v.eval();eq(gold.sectors(),v.sector_count,"sectors",t);eq(gold.commits(),v.commit_count,"commits",t);eq(gold.completions(),v.completion_count,"completions",t);eq(gold.instruction_issues(),v.instruction_count,"instructions",t);fields+=4;
 if(done[0]==2&&done[1]==2&&done[2]==2){end=t;break;}}
 if(!end)throw std::runtime_error("simulation did not finish");bool reject=false;try{Input in;in.response_valid=true;in.response_id=lastid;gold.edge(in,end+1);}catch(const std::runtime_error&){reject=true;}if(!reject)throw std::runtime_error("stale ID accepted");std::cout<<"SCENARIO_PASS scenario="<<scenario<<" cycles="<<end<<" fields="<<fields<<"\n";
}
std::cout<<"PARITY_PASS fields="<<fields<<" completed_frames="<<completed<<" checked_halfwords="<<values<<" matrix_checksum="<<checksum<<"\n";}
