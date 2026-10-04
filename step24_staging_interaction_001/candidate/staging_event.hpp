#pragma once
#include "producer_path.hpp"
#include <array>
#include <deque>
#include <vector>
#include <limits>
#include <algorithm>
#include <stdexcept>
#include <cstdint>
namespace staging_event {
using Cycle=uint64_t;constexpr Cycle NEVER=std::numeric_limits<Cycle>::max();
struct Request{bool valid=false;uint32_t context=0,id=0,a_base=0,b_base=0,row=0,col=0,stage=0;};
struct Input{Request request;bool backing_ready=true,write_ready=true,done_ready=true,response_valid=false;uint32_t response_id=0;};
struct Signals{bool request_ready=false,backing_valid=false,write_valid=false,done_valid=false;uint32_t backing_id=0,backing_address=0,write_context=0,done_context=0,done_id=0;std::array<uint32_t,32>write_addresses{};};
class Staging{
 struct Own{std::array<Cycle,64>ready{},release{};std::array<Cycle,6>tag{};};
 struct Context{bool active=false,done=false;Request frame;std::array<Own,4>own;std::array<unsigned,4>pc{};};
 struct Load{int ctx,warp;Op op;uint32_t id,group;Cycle issued,ready=NEVER;unsigned accepted=0,returned=0;};
 struct Store{int ctx;uint32_t group;Cycle due;};
 std::vector<Context>ctx;std::deque<Load>loads;std::deque<Store>stores;int m,n,k,cursor=0,done_cursor=0;uint32_t next_id=1;Cycle now_=0;uint64_t sectors_=0,commits_=0,done_=0,issues_=0;Cycle ready_prior=340;
 uint32_t group_for(const Op&o,int warp)const{return o.group<32?o.group*4+warp:32+(o.group-32)*4+warp;}
 bool legal(const Request&r)const{return r.context<ctx.size()&&r.row<uint32_t(m/32)&&r.col<uint32_t(n/32)&&r.stage<uint32_t(k/32)&&!(r.a_base&1)&&!(r.b_base&1);}
 uint32_t address(const Load&l,int sector)const{auto&r=ctx[l.ctx].frame;uint32_t g=l.group;uint64_t a;if(g<32)a=r.a_base+2ull*((r.row*32+g)*k+r.stage*32);else a=r.b_base+2ull*((r.stage*32+g-32)*n+r.col*32);a+=32*sector;if(a>UINT32_MAX)throw std::runtime_error("address overflow");return uint32_t(a);}
 bool eligible(int c,int w,const Op&o,Cycle t)const{auto&a=ctx[c].own[w];for(int r:o.src)if(a.ready[r]>t)return false;for(int r:o.dst)if(a.ready[r]>t||a.release[r]>t)return false;for(int b=0;b<6;b++)if((o.req>>b&1)&&a.tag[b]>t)return false;for(auto&l:loads)if(l.ctx==c&&l.warp==w&&l.op.wr>=0&&(o.req>>l.op.wr&1))return false;return true;}

 public:
 std::array<uint64_t,12> diagnostic(Cycle t)const {std::array<uint64_t,12>a{};auto&path=producer_path();a[0]=outstanding();a[1]=loads.size();a[2]=stores.size();for(auto&l:loads){a[3]+=l.returned!=3;a[4]+=l.returned==3&&l.ready>t;a[5]+=l.accepted<2;}for(int c=0;c<int(ctx.size());c++)for(int w=0;w<4;w++)if(ctx[c].active&&!ctx[c].done&&ctx[c].pc[w]<path.size()){a[6]++;auto&o=path[ctx[c].pc[w]];if(eligible(c,w,o,t)){a[7]++;if((o.kind!=1||loads.size()<32)&&(o.kind!=2||stores.size()<32))a[8]++;}else{auto&own=ctx[c].own[w];bool sr=false,wr=false;for(int r:o.src)sr|=own.ready[r]>t;for(int r:o.dst)wr|=own.release[r]>t;a[9]+=sr;a[10]+=wr;} }a[11]=issues_;return a;}
 public:
 Staging(int contexts,int M,int N,int K):ctx(contexts),m(M),n(N),k(K){if(contexts<1||M%32||N%32||K%32)throw std::runtime_error("unsupported geometry");}
 Signals signals(const Request&r={},Cycle t=0)const{Signals s;s.request_ready=legal(r)&&!ctx[r.context].active;
 for(auto&l:loads)if(l.accepted<2){s.backing_valid=true;s.backing_id=l.id+l.accepted;s.backing_address=address(l,l.accepted);break;}
 if(!stores.empty()&&stores.front().due<=t){auto&v=stores.front();s.write_valid=true;s.write_context=v.ctx;for(int a=0;a<32;a++)s.write_addresses[a]=2*(v.group*32+a);}
 for(int x=0;x<int(ctx.size());x++){int c=(done_cursor+x)%ctx.size();if(ctx[c].done){s.done_valid=true;s.done_context=c;s.done_id=ctx[c].frame.id;break;}}return s;
 }
 bool context_ready(int c)const{return !ctx.at(c).active;}int outstanding()const{int n=0;for(auto&c:ctx)n+=c.active;return n;}
 Cycle cycle()const{return now_;}uint64_t sectors()const{return sectors_;}uint64_t commits()const{return commits_;}uint64_t completions()const{return done_;}uint64_t instruction_issues()const{return issues_;}
 bool internal_edge_required()const{return outstanding()!=0;}void skip_to(Cycle t){if(outstanding())throw std::runtime_error("unsafe skip");now_=t;}
 void edge(const Input&in,Cycle t){now_=t;auto s=signals(in.request,t);
 if(in.request.valid&&s.request_ready){auto&c=ctx[in.request.context];c=Context{};c.active=true;c.frame=in.request;}
 if(s.backing_valid&&in.backing_ready){for(auto&l:loads)if(l.accepted<2){l.accepted++;sectors_++;break;}}
 if(in.response_valid){bool found=false;for(auto&l:loads)if(in.response_id>=l.id&&in.response_id<l.id+2){unsigned bit=1u<<(in.response_id-l.id);if(l.returned&bit)throw std::runtime_error("duplicate return");if(in.response_id-l.id>=l.accepted)throw std::runtime_error("unaccepted return");l.returned|=bit;if(l.returned==3)l.ready=std::max(l.issued+ready_prior,t+1);found=true;break;}if(!found)throw std::runtime_error("unowned return");}
 if(s.write_valid&&in.write_ready){stores.pop_front();commits_++;}
 if(s.done_valid&&in.done_ready){ctx[s.done_context].active=false;ctx[s.done_context].done=false;done_cursor=(s.done_context+1)%ctx.size();done_++;}
 for(auto it=loads.begin();it!=loads.end();){if(it->ready<=t){auto&own=ctx[it->ctx].own[it->warp];for(int r:it->op.dst)own.ready[r]=it->ready;if(it->op.wr>=0)own.tag[it->op.wr]=std::max(own.tag[it->op.wr],it->ready);it=loads.erase(it);}else ++it;}
 auto&path=producer_path();int total=ctx.size()*4,selected=-1;
 for(int off=0;off<total;off++){int x=(cursor+off)%total,c=x/4,w=x%4;if(!ctx[c].active||ctx[c].done||ctx[c].pc[w]>=path.size())continue;auto&o=path[ctx[c].pc[w]];if(!eligible(c,w,o,t))continue;if(o.kind==1&&loads.size()>=32)continue;if(o.kind==2&&stores.size()>=32)continue;selected=x;break;}
 if(selected>=0){int c=selected/4,w=selected%4;auto&o=path[ctx[c].pc[w]];auto&a=ctx[c].own[w];Cycle due=t+1;
 if(o.kind==1){if(o.group<0)throw std::runtime_error("missing global descriptor");Load l{c,w,o,next_id,group_for(o,w),t};next_id+=2;loads.push_back(l);for(int r:o.dst)a.ready[r]=NEVER;for(int r:o.src)a.release[r]=std::max(a.release[r],t+1);if(o.rd>=0)a.tag[o.rd]=std::max(a.tag[o.rd],t+1);}
 else{for(int r:o.dst)a.ready[r]=due;for(int r:o.src)a.release[r]=std::max(a.release[r],due);if(o.wr>=0)a.tag[o.wr]=std::max(a.tag[o.wr],due);if(o.rd>=0)a.tag[o.rd]=std::max(a.tag[o.rd],due);if(o.kind==2){if(o.group<0)throw std::runtime_error("missing store descriptor");stores.push_back({c,group_for(o,w),t+1});}}
 ctx[c].pc[w]++;cursor=(selected+1)%total;issues_++;}
 for(int c=0;c<int(ctx.size());c++)if(ctx[c].active&&!ctx[c].done){bool end=true;for(auto pc:ctx[c].pc)end&=pc==path.size();for(auto&l:loads)if(l.ctx==c)end=false;for(auto&v:stores)if(v.ctx==c)end=false;if(end)ctx[c].done=true;}
 now_=t+1;
 }
};
}
