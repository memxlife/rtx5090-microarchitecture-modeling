#pragma once
#include "native_schedule.hpp"
#include <algorithm>
#include <array>
#include <cstdint>
#include <deque>
#include <limits>
#include <optional>
#include <stdexcept>
#include <vector>
namespace native_event {
using Cycle=uint64_t;
struct Config {int contexts=11,read_slots=2,mov_slots=4,matrix_slots=2;
 bool external_reads=false,initially_active=true;
 Cycle shared_interval=1,shared_return=9,mov_latency=19,mov_interval=1,matrix_latency=73,matrix_interval=4;};
struct Event {Cycle cycle;int kind,warp,pc;bool operator==(const Event&)const=default;};
struct Warp {int pc=0;Cycle next_issue=0,start=0;std::array<std::array<bool,4>,2>a{},b{},mov{};std::array<bool,2> c{true,true};std::array<uint8_t,6> barriers{};uint64_t pending=0;};
struct Pending {int warp,pc;Cycle due=0;int packages=0;bool serviced=false;};
// Component executor only: caller supplies initialized operand contexts. External
// staging/read-hub contention, cache routing, and CTA lifecycle are NOT modeled here.
// State changes use pre-edge eligibility; returns at edge t permit issue at t+1.
class Stage {
 Config cfg;std::vector<Warp> warps;std::vector<uint32_t> epochs;int id_bits=0;std::deque<Pending> reads,moves,matrices;
 Cycle now_=0,read_next=0,mov_next=0,matrix_next=0;int rr=0;
 std::vector<Event> trace_;uint64_t edges_=0,skipped_=0;
 bool external_grant=false;std::optional<std::pair<int,int>> external_return;
 static int packages(const Descriptor&d,int tile){
  std::array<int,32> addresses{},counts{};int largest=0;
  for(int lane=0;lane<32;lane++){
   int addr=d.b?2048+64*(16*d.k+lane/4)+32*(tile%2)+4*(lane%4)+(d.word%2)*512+(d.word/2)*16:
    64*(16*(tile/2)+lane/4)+32*d.k+4*(lane%4)+(d.word%2)*512+(d.word/2)*16;
   addresses[lane]=addr;bool first=true;for(int j=0;j<lane;j++)if(addresses[j]==addr)first=false;
   if(first)largest=std::max(largest,++counts[(addr>>2)&31]);
  }return largest;
 }
 bool dependency(int w)const{
  const auto&x=warps[w];const auto&d=schedule[x.pc];
  for(int b=0;b<6;b++)if((d.wait&(1<<b))&&x.barriers[b])return false;
  if(d.kind==2)return x.b[d.k][d.word];
  if(d.kind==3){if(!x.c[d.half])return false;for(bool v:x.a[d.k])if(!v)return false;
   for(int j=0;j<2;j++)if(!x.mov[d.k][2*d.half+j])return false;}
  return true;
 }
 void finish(Pending p){auto&x=warps[p.warp];const auto&d=schedule[p.pc];
  if(!(x.pending&(uint64_t(1)<<p.pc)))throw std::runtime_error("unowned completion");
  x.pending&=~(uint64_t(1)<<p.pc);
  if(d.write_barrier!=7){if(!x.barriers[d.write_barrier])throw std::runtime_error("barrier underflow");--x.barriers[d.write_barrier];}
  if(d.kind==1)(d.b?x.b:x.a)[d.k][d.word]=true;
  if(d.kind==2)x.mov[d.k][d.word]=true;
  if(d.kind==3)x.c[d.half]=true;
  trace_.push_back({now_,1,p.warp,p.pc});
 }
 bool idle_done()const{for(auto&x:warps)if(x.pc!=40||x.pending||now_<x.next_issue)return false;return true;}
 int select()const{
  for(int offset=0;offset<int(warps.size());offset++){
   int w=(rr+offset)%warps.size();const auto&x=warps[w];if(x.pc==40||now_<x.start||now_<x.next_issue||!dependency(w))continue;
   auto d=schedule[x.pc];if(d.kind==1&&reads.size()>=size_t(cfg.read_slots))continue;
   if(d.kind==2&&(moves.size()>=size_t(cfg.mov_slots)||now_<mov_next))continue;
   if(d.kind==3&&(matrices.size()>=size_t(cfg.matrix_slots)||now_<matrix_next))continue;
   return w;
  }return -1;
 }
 Cycle next_change()const{
  Cycle next=std::numeric_limits<Cycle>::max();auto take=[&](Cycle c){if(c>now_)next=std::min(next,c);};
  for(const auto&x:warps){take(x.start);take(x.next_issue);}take(mov_next);take(matrix_next);
  for(const auto&r:reads)if(r.serviced)take(r.due);else take(std::max(now_+1,read_next));
  if(!moves.empty())take(moves.front().due);if(!matrices.empty())take(matrices.front().due);
  return next;
 }
 void edge(int chosen){
  // Return arbiter prioritizes shared, then MOVM, then matrix. No full-slot
  // replacement on this edge: chosen was selected before any retirement.
  auto ri=std::find_if(reads.begin(),reads.end(),[&](auto&p){return p.serviced&&p.due<=now_;});
  if(cfg.external_reads){ri=reads.end();if(external_return){ri=std::find_if(reads.begin(),reads.end(),[&](auto&p){return p.warp==external_return->first&&p.pc==external_return->second;});if(ri==reads.end())throw std::runtime_error("unowned external read response");}}
  bool rp=ri!=reads.end(),mp=!moves.empty()&&moves.front().due<=now_,hp=!matrices.empty()&&matrices.front().due<=now_;
  auto service=std::find_if(reads.begin(),reads.end(),[](auto&p){return !p.serviced;});
  if(!cfg.external_reads&&service!=reads.end()&&now_>=read_next){read_next=now_+cfg.shared_interval;if(--service->packages==0){service->serviced=true;service->due=now_+cfg.shared_return+1;}}
  if(rp){auto p=*ri;reads.erase(ri);finish(p);}else if(mp){auto p=moves.front();moves.pop_front();finish(p);}else if(hp){auto p=matrices.front();matrices.pop_front();finish(p);}
  if(chosen>=0&&cfg.external_reads&&schedule[warps[chosen].pc].kind==1&&!external_grant)chosen=-1;
  if(chosen>=0){auto&x=warps[chosen];const int pc=x.pc;const auto d=schedule[pc];
   trace_.push_back({now_,0,chosen,pc});x.pc++;rr=(chosen+1)%warps.size();x.next_issue=now_+std::max(1,d.delay);
   if(d.read_barrier!=7)throw std::runtime_error("read barrier translation not supported");
   if(d.write_barrier!=7)++x.barriers[d.write_barrier];
   Pending p{chosen,pc};if(d.kind){x.pending|=uint64_t(1)<<pc;}
   if(d.kind==1){p.packages=packages(d,chosen%4);reads.push_back(p);}
   if(d.kind==2){p.due=now_+cfg.mov_latency;moves.push_back(p);mov_next=now_+cfg.mov_interval;}
   if(d.kind==3){p.due=now_+cfg.matrix_latency;matrices.push_back(p);matrix_next=now_+cfg.matrix_interval;x.c[d.half]=false;}
  }
  edges_++;
 }
 public:
 explicit Stage(Config c):cfg(c),warps(c.contexts*4),epochs(c.contexts,c.initially_active?1:0){for(unsigned v=c.contexts*4*40-1;v;v>>=1)id_bits++;if(c.contexts<1)throw std::runtime_error("invalid contexts");if(!c.initially_active)for(auto&x:warps)x.pc=40;}
 struct Preview {uint32_t id=0;int selected=-1,warp=-1,pc=-1;bool read_valid=false;std::array<uint32_t,32>addresses{};};
 Preview preview(Cycle t){now_=t;Preview p;p.selected=select();if(p.selected>=0){p.warp=p.selected;p.pc=warps[p.selected].pc;p.id=(epochs[p.warp/4]<<id_bits)|uint32_t(p.warp*40+p.pc);p.read_valid=schedule[p.pc].kind==1;auto d=schedule[p.pc];int tile=p.warp%4;for(int lane=0;lane<32;lane++)p.addresses[lane]=d.b?2048+64*(16*d.k+lane/4)+32*(tile%2)+4*(lane%4)+(d.word%2)*512+(d.word/2)*16:64*(16*(tile/2)+lane/4)+32*d.k+4*(lane%4)+(d.word%2)*512+(d.word/2)*16;}return p;}
 void external_edge(Cycle t,bool grant,std::optional<std::pair<int,int>> returned={}){if(!cfg.external_reads)throw std::runtime_error("external port disabled");now_=t;external_grant=grant;external_return=returned;int chosen=select();edge(chosen);now_++;external_return.reset();}
 std::pair<int,int> decode_read_id(uint32_t id)const{unsigned local=id&((1U<<id_bits)-1),w=local/40,pc=local%40;if(w>=warps.size()||(id>>id_bits)!=epochs[w/4])throw std::runtime_error("stale native read epoch");return {int(w),int(pc)};}
 bool warp_drained(int w)const{return warps.at(w).pc==40&&!warps[w].pending&&now_>=warps[w].next_issue;}
 bool warp_memory_safe(int w)const{if(warps.at(w).pc!=40||now_<warps[w].next_issue)return false;for(auto&r:reads)if(r.warp==w)return false;return true;}
 bool warp_issued_all(int w)const{return warps.at(w).pc==40;}
 bool context_drained(int ctx)const{for(int w=ctx*4;w<ctx*4+4;w++)if(warps.at(w).pc!=40||warps[w].pending||now_<warps[w].next_issue)return false;return true;}
 bool context_memory_safe(int ctx)const{for(auto&r:reads)if(r.warp/4==ctx)return false;for(int w=ctx*4;w<ctx*4+4;w++)if(warps.at(w).pc!=40||now_<warps[w].next_issue)return false;return true;}
 void activate_context(int ctx,Cycle first_issue){epochs.at(ctx)++;if(!context_drained(ctx))throw std::runtime_error("context restarted before drain");for(int w=ctx*4;w<ctx*4+4;w++){warps.at(w)=Warp{};warps[w].start=first_issue;}}
 Cycle timed_wake(Cycle t)const{Cycle next=UINT64_MAX;for(auto&x:warps)if(x.pc<40){if(x.start>t)next=std::min(next,x.start);if(x.next_issue>t)next=std::min(next,x.next_issue);}if(mov_next>t)next=std::min(next,mov_next);if(matrix_next>t)next=std::min(next,matrix_next);if(!moves.empty())next=std::min(next,std::max(t,moves.front().due));if(!matrices.empty())next=std::min(next,std::max(t,matrices.front().due));return next;}
 Cycle wake(Cycle t){now_=t;if(select()>=0)return t;Cycle next=std::numeric_limits<Cycle>::max();for(auto&x:warps)if(x.pc<40){if(x.start>t)next=std::min(next,x.start);if(x.next_issue>t)next=std::min(next,x.next_issue);}next=std::min(next,mov_next>t?mov_next:UINT64_MAX);next=std::min(next,matrix_next>t?matrix_next:UINT64_MAX);if(!moves.empty())next=std::min(next,std::max(t,moves.front().due));if(!matrices.empty())next=std::min(next,std::max(t,matrices.front().due));return next;}
 // Staggered starts exercise inactive-context gaps without ticking those gaps.
 void set_context_start(int ctx,Cycle cycle){for(int w=ctx*4;w<ctx*4+4;w++)warps.at(w).start=cycle;}
 void run(bool skip_idle=true){while(!idle_done()){
  int selected=select();bool completion=(!moves.empty()&&moves.front().due<=now_)||(!matrices.empty()&&matrices.front().due<=now_);
  bool shared_work=false;for(auto&p:reads)if((p.serviced&&p.due<=now_)||(!p.serviced&&now_>=read_next))shared_work=true;
  if(skip_idle&&selected<0&&!completion&&!shared_work){Cycle next=next_change();if(next==std::numeric_limits<Cycle>::max())throw std::runtime_error("native deadlock");skipped_+=next-now_;now_=next;continue;}
  edge(selected);now_++;if(now_>100000000)throw std::runtime_error("native safety bound");
 }}
 Cycle cycles()const{return now_;}uint64_t edges()const{return edges_;}uint64_t skipped()const{return skipped_;}
 const auto&trace()const{return trace_;}
};
}
