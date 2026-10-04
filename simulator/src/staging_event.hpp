#pragma once
#include <array>
#include <cstdint>
#include <limits>
#include <stdexcept>
#include <vector>
namespace staging_event {
using Cycle=uint64_t;
struct Request{bool valid=false;uint32_t context=0,id=0,a_base=0,b_base=0,row=0,col=0,stage=0;};
struct Input{Request request;bool backing_ready=true,write_ready=true,done_ready=true,response_valid=false;uint32_t response_id=0;};
struct Signals{bool request_ready=false,backing_valid=false,write_valid=false,done_valid=false;uint32_t backing_id=0,backing_address=0,write_context=0,done_context=0,done_id=0;std::array<uint32_t,32>write_addresses{};};
class Staging{
 enum Outer{O_IDLE,O_SEND,O_WAIT,O_DONE};enum Load{L_IDLE,L_SEND,L_WAIT,L_RESPONSE};
 struct Context{Outer outer=O_IDLE;Load load=L_IDLE;uint32_t epoch=0,load_epoch=0,id=0,load_id=0,abase=0,bbase=0,row=0,col=0,stage=0;int group=0,sector=0;std::vector<uint32_t>sectors;};
 std::vector<Context>ctx;int m,n,k,outer_bits,load_bits;int request_owner=-1,request_cursor=0,cache_owner=-1,cache_cursor=0,response_owner=-1,response_cursor=0,done_owner=-1,done_cursor=0;
 Cycle now_=0;uint64_t accepted_sectors_=0,commits_=0,done_=0;
 static int clog2(unsigned x){int b=0;for(unsigned v=x-1;v;v>>=1)b++;return b;}
 uint32_t load_tag(int c)const{return (ctx[c].load_epoch<<load_bits)|uint32_t(c*32+ctx[c].sector);}
 uint32_t group_tag(int c)const{return (ctx[c].epoch<<outer_bits)|uint32_t(c*64+ctx[c].group);}
 std::array<uint32_t,32>addresses(int c)const{std::array<uint32_t,32>a{};auto&x=ctx[c];for(int lane=0;lane<32;lane++){int h=x.group*32+lane;uint64_t address;if(h<1024){uint64_t r=x.row*32+h/32,col=x.stage*32+h%32;address=x.abase+2*(r*k+col);}else{h-=1024;uint64_t r=x.stage*32+h/32,col=x.col*32+h%32;address=x.bbase+2*(r*n+col);}if(address>UINT32_MAX)throw std::runtime_error("address overflow");a[lane]=uint32_t(address);}return a;}
 bool legal(const Request&r)const{return r.context<ctx.size()&&r.row<uint32_t(m/32)&&r.col<uint32_t(n/32)&&r.stage<uint32_t(k/32)&&!(r.a_base&1)&&!(r.b_base&1)&&uint64_t(r.a_base)+2ULL*m*k<=0x100000000ULL&&uint64_t(r.b_base)+2ULL*k*n<=0x100000000ULL;}
 template<class P>int choose(int cursor,P pred)const{for(int off=0;off<int(ctx.size());off++){int c=(cursor+off)%ctx.size();if(pred(c))return c;}return -1;}
 public:
 Staging(int contexts,int M,int N,int K):ctx(contexts),m(M),n(N),k(K),outer_bits(clog2(contexts*64)),load_bits(clog2(contexts*32)){if(contexts<1||M%32||N%32||K%32)throw std::runtime_error("unsupported geometry");}
 Signals signals(const Request&r={})const{Signals s;s.request_ready=legal(r)&&ctx[r.context].outer==O_IDLE;
  if(cache_owner>=0&&ctx[cache_owner].load==L_SEND){s.backing_valid=true;s.backing_id=load_tag(cache_owner);s.backing_address=ctx[cache_owner].sectors.at(ctx[cache_owner].sector);}
  if(response_owner>=0){s.write_valid=true;s.write_context=response_owner;for(int lane=0;lane<32;lane++)s.write_addresses[lane]=2*(ctx[response_owner].group*32+lane);}
  if(done_owner>=0){s.done_valid=true;s.done_context=done_owner;s.done_id=ctx[done_owner].id;}return s;
 }
 bool context_ready(int c)const{return ctx.at(c).outer==O_IDLE;}
 int outstanding()const{int n=0;for(auto&x:ctx)n+=x.outer!=O_IDLE;return n;}
 Cycle cycle()const{return now_;}uint64_t sectors()const{return accepted_sectors_;}uint64_t commits()const{return commits_;}uint64_t completions()const{return done_;}
 // Only registered-owner selections require an internal edge while all ports
 // are stalled. External arrivals/readiness changes must wake this component.
 bool internal_edge_required()const{
  if(request_owner>=0&&ctx[request_owner].load==L_IDLE)return true;
  if(request_owner<0&&choose(request_cursor,[&](int c){return ctx[c].outer==O_SEND&&ctx[c].load==L_IDLE;})>=0)return true;
  if(cache_owner<0&&choose(cache_cursor,[&](int c){return ctx[c].load==L_SEND;})>=0)return true;
  if(response_owner<0&&choose(response_cursor,[&](int c){return ctx[c].load==L_RESPONSE;})>=0)return true;
  if(done_owner<0&&choose(done_cursor,[&](int c){return ctx[c].outer==O_DONE;})>=0)return true;
  return false;
 }
 void skip_to(Cycle t){if(t<now_||internal_edge_required())throw std::runtime_error("unsafe idle jump");now_=t;}
 void edge(const Input&in){auto old=ctx;auto next=ctx;const auto s=signals(in.request);int ro=request_owner,co=cache_owner,po=response_owner,doo=done_owner;
  if(in.request.valid){if(!legal(in.request))throw std::runtime_error("illegal frame");if(s.request_ready){auto&r=in.request;auto&x=next[r.context];x.epoch++;x.id=r.id;x.abase=r.a_base;x.bbase=r.b_base;x.row=r.row;x.col=r.col;x.stage=r.stage;x.group=0;x.outer=O_SEND;}}
  // Outer staging owner and loader admission use the same pre-edge snapshot.
  if(ro<0)request_owner=choose(request_cursor,[&](int c){return old[c].outer==O_SEND&&old[c].load==L_IDLE;});
  else if(old[ro].load==L_IDLE){auto&x=next[ro];x.outer=O_WAIT;x.load_epoch++;x.load_id=group_tag(ro);x.sector=0;x.sectors.clear();for(auto a:addresses(ro)){a&=~31U;bool found=false;for(auto b:x.sectors)found|=a==b;if(!found)x.sectors.push_back(a);}x.load=x.sectors.empty()?L_RESPONSE:L_SEND;request_cursor=(ro+1)%ctx.size();request_owner=-1;}
  if(co<0)cache_owner=choose(cache_cursor,[&](int c){return old[c].load==L_SEND;});
  else if(s.backing_valid&&in.backing_ready){next[co].load=L_WAIT;cache_cursor=(co+1)%ctx.size();cache_owner=-1;accepted_sectors_++;}
  if(in.response_valid){int c=(in.response_id&((1U<<load_bits)-1))/32;if(c>=int(ctx.size())||old[c].load!=L_WAIT||in.response_id!=load_tag(c))throw std::runtime_error("stale/unowned sector return");auto&x=next[c];if(old[c].sector==int(old[c].sectors.size())-1)x.load=L_RESPONSE;else{x.sector++;x.load=L_SEND;}}
  if(po<0)response_owner=choose(response_cursor,[&](int c){return old[c].load==L_RESPONSE;});
  else if(s.write_valid&&in.write_ready){if(old[po].outer!=O_WAIT||old[po].load_id!=group_tag(po))throw std::runtime_error("unowned group commit");next[po].load=L_IDLE;response_cursor=(po+1)%ctx.size();response_owner=-1;if(old[po].group==63)next[po].outer=O_DONE;else{next[po].group++;next[po].outer=O_SEND;}commits_++;}
  if(doo<0)done_owner=choose(done_cursor,[&](int c){return old[c].outer==O_DONE;});
  else if(s.done_valid&&in.done_ready){next[doo].outer=O_IDLE;done_cursor=(doo+1)%ctx.size();done_owner=-1;done_++;}
  ctx=std::move(next);now_++;
 }
};
}
