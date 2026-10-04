#include "Vlarge_connected_top.h"
#include "Vlarge_connected_top___024root.h"
#include "Vlarge_slice_l2_a.h"
#include "Vlarge_slice_l2_a___024root.h"
#include "verilated.h"
#include <array>
#include <bit>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <stdexcept>
#include <vector>
#ifndef MATRIX_M
#define MATRIX_M 2048
#define MATRIX_N 2112
#define MATRIX_K 1536
#define CACHE_SLICES 48
#endif
struct Pending{uint32_t id,address;uint64_t due;bool write;};
template<class T>bool native_issue_bit(T&d,int sm){
 if constexpr(MATRIX_M==64&&MATRIX_N==96){return sm<2&&(d.sm_native_issue_valid&(1u<<sm));}
 else return sm<170&&(d.sm_native_issue_valid[sm/32]&(1u<<(sm%32)));
}
int main(int argc,char**argv){try{
 fprintf(stderr,"CONSTRUCT_START\n");fflush(stderr);VerilatedContext context;context.commandArgs(argc,argv);Vlarge_connected_top d(&context);fprintf(stderr,"CONSTRUCT_DONE\n");fflush(stderr);
 constexpr uint32_t A=0,B=0x2000000,C=0x4000000;
 std::array<std::deque<Pending>,CACHE_SLICES> queues;
 std::vector<bool> seen(size_t(MATRIX_M)*MATRIX_N);
  double dram_read_credit=0;uint64_t trace_hash=1469598103934665603ull;auto hash=[&](uint64_t v){trace_hash^=v;trace_hash*=1099511628211ull;};const char* prefix_env=getenv("TIMING_PREFIX_CYCLES");uint64_t prefix_limit=prefix_env?strtoull(prefix_env,nullptr,10):0;uint64_t clock=0,checked=0;int peak=0;auto start=std::chrono::steady_clock::now();
 d.a_base=A;d.b_base=B;d.c_base=C;d.l2_hit_delay_cycles=4;d.kernel_setup_cycles=3346;d.cache_read_rate_q10=37481;d.cache_write_rate_q10=31056;d.cache_mixed_rate_q10=49089;d.done_ready=1;d.rst=1;
 auto tick=[&](){
  d.clk=0;dram_read_credit=std::min(dram_read_credit+16.6694010417,33.3388020834);double available=dram_read_credit;
  for(int s=0;s<CACHE_SLICES;s++){
   auto&q=queues[s];d.backing_req_ready[s]=q.size()<16&&available>=1;if(d.backing_req_ready[s]&&d.backing_req_valid[s])available-=1;d.store_backing_req_ready[s]=q.size()<15;
   d.backing_rsp_valid[s]=d.store_backing_rsp_valid[s]=0;
   if(!q.empty()&&q.front().due<=clock){auto&p=q.front();if(p.write){d.store_backing_rsp_valid[s]=1;d.store_backing_rsp_id[s]=p.id;}else{d.backing_rsp_valid[s]=1;d.backing_rsp_id[s]=p.id;}}
  }
  d.eval();
  for(int s=0;s<CACHE_SLICES;s++){
   auto&q=queues[s];if((d.backing_rsp_valid[s]&&d.backing_rsp_ready[s])||(d.store_backing_rsp_valid[s]&&d.store_backing_rsp_ready[s])){hash(clock);hash(1);hash(s);hash(q.front().id);hash(q.front().address);hash(q.front().write);q.pop_front();}
   if(d.backing_req_valid[s]&&d.backing_req_ready[s]){hash(clock);hash(2);hash(s);hash(d.backing_req_id[s]);hash(d.backing_req_byte_address[s]);dram_read_credit-=1;q.push_back({d.backing_req_id[s],d.backing_req_byte_address[s],clock+31,false});}
   if(d.store_backing_req_valid[s]&&d.store_backing_req_ready[s]){
    uint32_t address=d.store_backing_req_byte_address[s];hash(clock);hash(3);hash(s);hash(d.store_backing_req_id[s]);hash(address);hash(d.store_backing_req_word_mask[s]);
    for(int w=0;w<8;w++)if(d.store_backing_req_word_mask[s]&(1<<w)){
     size_t i=(address+4*w-C)/4;if(i>=seen.size()||seen[i])throw std::runtime_error("duplicate/out-of-range output");

     /* timing mode validates addresses and completion, not numerical values */seen[i]=true;checked++;
    }
    q.push_back({d.store_backing_req_id[s],address,clock+17,true});
   }
  }
  for(int sm=0;sm<170;sm++)if(native_issue_bit(d,sm)){hash(clock);hash(4);hash(sm);}
  d.clk=1;d.eval();clock++;peak=std::max(peak,int(d.resident_blocks));
  if(clock==10||clock==100||clock==1000||clock%10000==0){double seconds=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();fprintf(stderr,"PROGRESS cycles=%llu checked=%llu dispatched=%d completed=%d resident=%d wall_seconds=%.3f cycles_per_second=%.1f\n",(unsigned long long)clock,(unsigned long long)checked,int(d.dispatched_blocks),int(d.completed_blocks),int(d.resident_blocks),seconds,double(clock)/seconds);fflush(stderr);}
  if(prefix_limit&&clock>=prefix_limit){printf("PREFIX_DONE cycles=%llu elapsed=%llu trace_hash=%016llx l2_requests=%d hits=%d misses=%d fills=%d dispatched=%d completed=%d resident=%d\n",(unsigned long long)clock,(unsigned long long)d.elapsed_cycles,(unsigned long long)trace_hash,int(d.l2_read_requests),int(d.l2_read_hits),int(d.l2_read_misses),int(d.l2_actual_fills),int(d.dispatched_blocks),int(d.completed_blocks),int(d.resident_blocks));fflush(stdout);exit(0);}
  if(clock>20000000)throw std::runtime_error("cycle budget exceeded");
 };
 for(int i=0;i<3;i++)tick();d.rst=0;

 // Explicit warm starting state: all immutable A/B sectors resident, no outstanding transactions.
 // This chooses a cache initial condition; it does not skip measured workload instructions.
 bool warm=getenv("WARM_INITIAL_CACHE")!=nullptr;
 if(warm){
  std::array<Vlarge_slice_l2_a___024root*,48> roots={
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__0__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__1__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__2__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__3__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__4__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__5__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__6__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__7__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__8__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__9__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__10__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__11__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__12__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__13__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__14__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__15__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__16__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__17__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__18__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__19__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__20__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__21__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__22__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__23__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__24__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__25__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__26__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__27__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__28__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__29__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__30__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__31__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__32__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__33__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__34__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__35__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__36__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__37__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__38__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__39__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__40__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__41__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__42__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__43__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__44__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__45__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__46__KET____DOT__gateway__DOT__handle___05FV)->rootp,
 reinterpret_cast<Vlarge_slice_l2_a*>(d.rootp->large_connected_top__DOT__cache_slices__BRA__47__KET____DOT__gateway__DOT__handle___05FV)->rootp
 };
  unsigned maxways=0;uint64_t lines=0;
  auto prime=[&](uint32_t base,uint64_t bytes){
   for(uint64_t a=base;a<uint64_t(base)+bytes;a+=128){
    unsigned sl=(a>>7)%48,set=((a>>7)/48)%1024,tag=a/(128*48*1024);auto*r=roots[sl];int way=-1;
    for(int w=0;w<16;w++)if(r->large_slice_l2_a__DOT__line_valid[set][w]&&r->large_slice_l2_a__DOT__line_tag[set][w]==tag)way=w;
    for(int w=0;w<16&&way<0;w++)if(!r->large_slice_l2_a__DOT__line_valid[set][w])way=w;
    if(way<0)throw std::runtime_error("warm initial working set exceeds associativity");
    r->large_slice_l2_a__DOT__line_valid[set][way]=1;r->large_slice_l2_a__DOT__line_tag[set][way]=tag;r->large_slice_l2_a__DOT__sector_valid[set][way]=15;lines++;maxways=std::max(maxways,unsigned(way+1));
   }
  };prime(A,2ull*MATRIX_M*MATRIX_K);prime(B,2ull*MATRIX_K*MATRIX_N);
  fprintf(stderr,"WARM_INITIAL_CACHE lines=%llu max_used_ways=%u numerical_payload=none\n",(unsigned long long)lines,maxways);
 }

 for(int launch=0;launch<(warm?1:2);launch++){
  std::fill(seen.begin(),seen.end(),false);checked=0;peak=0;d.local_cache_invalidate=launch!=0;tick();d.local_cache_invalidate=0;
  while(!d.launch_ready)tick();d.launch_id=launch;d.launch_valid=1;tick();d.launch_valid=0;
  while(!d.done_valid)tick();
  if(checked!=seen.size())throw std::runtime_error("incomplete output coverage");
  double wall=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();
  printf("LARGE_TIMING_PASS launch=%d M=%d N=%d K=%d checked=%llu cycles=%llu host_seconds=%.6f host_cycles_per_second=%.1f peak_blocks=%d l2_requests=%d hits=%d misses=%d merges=%d fills=%d\n",launch,MATRIX_M,MATRIX_N,MATRIX_K,(unsigned long long)checked,(unsigned long long)d.elapsed_cycles,wall,double(clock)/wall,peak,int(d.l2_read_requests),int(d.l2_read_hits),int(d.l2_read_misses),int(d.l2_merged_misses),int(d.l2_actual_fills));fflush(stdout);tick();
 }
 d.final();return 0;
 }catch(const std::exception&e){fprintf(stderr,"FAIL %s\n",e.what());return 1;}}
