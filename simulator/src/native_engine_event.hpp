#pragma once
#include "native_stage_event.hpp"
namespace native_engine_event {
class Engine{
 enum State{IDLE,RUN,DRAIN,RESPONSE};struct Context{State state=IDLE;uint32_t id=0;unsigned initialized=0,memory_safe=0,drained=0;};
 std::vector<Context>ctx;int response_owner=-1,response_cursor=0;
 public:
 native_event::Stage stage;
 static native_event::Config config(int n,int reads,int shared_delay,int mov,int hmma,int hmma_interval){native_event::Config c;c.contexts=n;c.read_slots=reads;c.shared_return=shared_delay;c.mov_latency=mov;c.matrix_latency=hmma;c.matrix_interval=hmma_interval;c.external_reads=true;c.initially_active=false;return c;}
 Engine(int n,int reads=2,int shared_delay=28,int mov=29,int hmma=32,int hmma_interval=8):ctx(n),stage(config(n,reads,shared_delay,mov,hmma,hmma_interval)){}
 bool ready(int c)const{return ctx.at(c).state==IDLE&&ctx[c].initialized==2048;}
 bool write_ready(int c,bool issued_read)const{return ctx.at(c).state==IDLE&&!issued_read;}
 unsigned memory_safe(int c)const{return ctx.at(c).memory_safe;}
 bool internal_edge_required()const{if(response_owner<0)for(auto&c:ctx)if(c.state==RESPONSE)return true;for(int c=0;c<int(ctx.size());c++)if(ctx[c].state==RUN||ctx[c].state==DRAIN){bool all=true;for(int w=0;w<4;w++){int index=c*4+w;all&=ctx[c].state==RUN?stage.warp_issued_all(index):stage.warp_drained(index);if(stage.warp_memory_safe(index)&&!(ctx[c].memory_safe&(1<<w)))return true;if(stage.warp_drained(index)&&!(ctx[c].drained&(1<<w)))return true;}if(all)return true;}return false;}
 struct Input{bool request=false,response_ready=false,write=false,read_grant=false;int context=0,write_context=0;uint32_t id=0,write_base=0;std::optional<std::pair<int,int>>read_return;};
 struct Signals{bool response=false;uint32_t response_context=0,response_id=0;};
 Signals signals()const{Signals s;if(response_owner>=0){s.response=true;s.response_context=response_owner;s.response_id=ctx[response_owner].id;}return s;}
 void edge(uint64_t t,const Input&i){auto old=ctx;auto next=ctx;auto sig=signals();auto preview=stage.preview(t);
  for(int c=0;c<int(ctx.size());c++){
   if(old[c].state==RUN||old[c].state==DRAIN)for(int w=0;w<4;w++){if(stage.warp_memory_safe(c*4+w))next[c].memory_safe|=1<<w;if(stage.warp_drained(c*4+w))next[c].drained|=1<<w;}
   if(old[c].state==RUN){bool all=true;for(int w=0;w<4;w++)all&=stage.warp_issued_all(c*4+w);if(all)next[c].state=DRAIN;}
   if(old[c].state==DRAIN){bool all=true;for(int w=0;w<4;w++)all&=stage.warp_drained(c*4+w);if(all)next[c].state=RESPONSE;}
   if(old[c].state==RESPONSE&&sig.response&&i.response_ready&&response_owner==c)next[c].state=IDLE;
  }
  if(response_owner<0){for(int off=0;off<int(ctx.size());off++){int c=(response_cursor+off)%ctx.size();if(old[c].state==RESPONSE){response_owner=c;break;}}}else if(sig.response&&i.response_ready){response_cursor=(response_owner+1)%ctx.size();response_owner=-1;}
  stage.external_edge(t,i.read_grant,i.read_return);
  if(i.write){if(!write_ready(i.write_context,preview.read_valid&&i.read_grant))throw std::runtime_error("illegal native write");if(i.write_base>=4096||i.write_base%64)throw std::runtime_error("write initialization shape");if(next[i.write_context].initialized<2048)next[i.write_context].initialized+=32;}
  if(i.request&&ready(i.context)){next[i.context].state=RUN;next[i.context].id=i.id;next[i.context].memory_safe=next[i.context].drained=0;stage.activate_context(i.context,t+1);}
  ctx=std::move(next);
 }
};
}
