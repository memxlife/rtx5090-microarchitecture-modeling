#pragma once
#include "staging_event.hpp"
#include "native_engine_event.hpp"
#include "shared_hub_event.hpp"
#include "resident_metadata.hpp"
#include "generation_metadata.hpp"
#include <optional>
namespace sm_event {
struct Offer{bool valid=false;uint32_t id=0,address=0;uint8_t mask=0;};
struct Input{bool launch=false,done_ready=true,read_ready=false,write_ready=false;uint32_t id=0,row=0,col=0,a=0,b=0,c=0;std::optional<uint32_t>read_return,write_return;};
struct Signals{bool launch_ready=false,done=false,native_issue=false,read_return_ready=true,write_return_ready=false;uint32_t done_id=0,done_context=0,native_context=0,native_warp=0,native_pc=0;Offer read,write;int resident=0;};
class SM{
 int n,M,N,K;resident_event::Controller ctrl;staging_event::Staging staging;native_engine_event::Engine engine;shared_hub_event::Hub hub;output_event::Scratch scratch;output_event::WarpStore store;
 std::vector<generation_event::Barrier>producer,consumer;
 struct Wiring{resident_event::Controller::Inputs ci;resident_event::Controller::Signals cs;staging_event::Input si;staging_event::Signals ss;native_engine_event::Engine::Input ei;native_engine_event::Engine::Signals es;output_event::Scratch::Inputs xi;output_event::Scratch::Signals xs;output_event::WarpStore::Inputs wi;output_event::WarpStore::Signals ws;std::vector<shared_hub_event::Offer>ho;std::vector<bool>hr;shared_hub_event::Signals hs;native_event::Stage::Preview np;};
 Wiring wire(uint64_t t,const Input&i){Wiring w;w.ci.launch_valid=i.launch;w.ci.launch_id=i.id;w.ci.row=i.row;w.ci.col=i.col;w.ci.a=i.a;w.ci.b=i.b;w.ci.c=i.c;w.ci.done_ready=i.done_ready;
  w.ci.launch_legal=i.row<uint32_t(M/32)&&i.col<uint32_t(N/32)&&!(i.a&1)&&!(i.b&1)&&!(i.c&3);
  w.ci.launch_legal &= uint64_t(i.a)+2ULL*M*K<=0x100000000ULL&&uint64_t(i.b)+2ULL*K*N<=0x100000000ULL&&uint64_t(i.c)+4ULL*M*N<=0x100000000ULL;
  w.ci.launch_legal &= !(uint64_t(i.c)<uint64_t(i.a)+2ULL*M*K&&uint64_t(i.a)<uint64_t(i.c)+4ULL*M*N)&&!(uint64_t(i.c)<uint64_t(i.b)+2ULL*K*N&&uint64_t(i.b)<uint64_t(i.c)+4ULL*M*N);
  if(ctrl.stage_owner>=0){auto&c=ctrl.ctx[ctrl.stage_owner];w.si.request={true,uint32_t(ctrl.stage_owner),uint32_t(c.stage),c.a,c.b,c.row,c.col,uint32_t(c.stage)};}
  w.ss=staging.signals(w.si.request,t);w.es=engine.signals();w.xs=scratch.signals();w.np=engine.stage.preview(t);
  w.ho.resize(2);w.hr={true,w.xs.read_response_ready};w.ho[0]={w.np.read_valid,w.np.id,w.np.addresses};w.ho[1]={w.xs.read_candidate,w.xs.read_id,w.xs.read_addresses};w.hs=hub.signals(t,w.ho);
  bool native_read=w.np.read_valid&&w.hs.grant[0];bool engine_write=w.ss.write_valid&&engine.write_ready(w.ss.write_context,native_read);
  bool staging_write=engine_write&&(!w.xs.store_candidate||ctrl.write_cursor==0);bool scratch_write=w.xs.store_candidate&&!staging_write;
  w.si.backing_ready=i.read_ready;w.si.response_valid=i.read_return.has_value();w.si.response_id=i.read_return.value_or(0);w.si.write_ready=staging_write;
  w.ci.staging_ready=w.ss.request_ready;w.ci.staging_done=w.ss.done_valid;w.ci.staging_context=w.ss.done_context;w.ci.staging_id=w.ss.done_id;
  w.ci.compute_ready=ctrl.compute_owner>=0&&engine.ready(ctrl.compute_owner);w.ci.compute_done=w.es.response;w.ci.compute_context=w.es.response_context;w.ci.compute_id=w.es.response_id;
  w.ci.scratch_response=w.xs.response;w.ci.scratch_id=w.xs.response_id;w.ci.scratch_ready=w.xs.ready;
  // Store response does not depend on request addresses, but store readiness does.
  w.wi.ack_valid=i.write_return.has_value();w.wi.ack_id=i.write_return.value_or(0);w.wi.backing_ready=i.write_ready;auto pre=store.signals(w.wi);
  w.ci.store_response=pre.response;w.ci.store_id=pre.response_id;w.ci.producer_release.resize(n);w.ci.consumer_release.resize(n);w.ci.consumer_arrival.resize(n);
  for(int c=0;c<n;c++){w.ci.producer_release[c]=producer[c].signals({}).release;w.ci.consumer_release[c]=consumer[c].signals({}).release;w.ci.consumer_arrival[c]=ctrl.ctx[c].state==resident_event::Controller::COMPUTE_WAIT?(engine.memory_safe(c)&~ctrl.ctx[c].seen):0;}
  w.cs=ctrl.signals(w.ci);w.wi.valid=w.cs.store;w.wi.request_id=w.cs.store_id;w.wi.addresses=w.cs.store_addresses;w.wi.response_ready=w.cs.store_response_ready;w.ws=store.signals(w.wi);w.ci.store_ready=w.ws.ready;
  // Controller's store-ready input is not part of its combinational equations.
  w.si.done_ready=w.cs.staging_done_ready;w.ei.request=w.cs.compute;w.ei.context=w.cs.compute_context;w.ei.id=w.cs.compute_id;w.ei.response_ready=w.cs.compute_done_ready;w.ei.write=staging_write;w.ei.write_context=w.ss.write_context;w.ei.write_base=w.ss.write_addresses[0];w.ei.read_grant=w.hs.grant[0];if(w.hs.response_valid[0])w.ei.read_return=engine.stage.decode_read_id(w.hs.response_id[0]);
  w.xi.valid=w.cs.scratch;w.xi.request_id=ctrl.output_owner>=0?ctrl.output_owner:0;w.xi.response_ready=w.cs.scratch_response_ready;w.xi.store_grant=scratch_write;w.xi.read_grant=w.hs.grant[1];w.xi.read_response=w.hs.response_valid[1];w.xi.read_response_id=w.hs.response_id[1];
  w.ci.write_valid=w.ss.write_valid;w.ci.write_ready=staging_write;w.ci.scratch_grant=scratch_write;return w;
 }
 public:
 SM(int contexts=11,int m=2048,int columns=2112,int k=1536,int sharedSlots=2):n(contexts),M(m),N(columns),K(k),ctrl(contexts,k,columns),staging(contexts,m,columns,k),engine(contexts,sharedSlots),hub(2,sharedSlots,1,28),producer(contexts),consumer(contexts){}
 Signals signals(uint64_t t,const Input&i){auto w=wire(t,i);Signals s;s.launch_ready=w.cs.launch_ready;s.done=w.cs.done;s.done_id=w.cs.done_id;s.done_context=w.cs.done_context;s.read={w.ss.backing_valid,w.ss.backing_id,w.ss.backing_address,0};s.write={w.ws.backing_valid,w.ws.backing_id,w.ws.address,w.ws.mask};s.resident=ctrl.admission.signals({}).resident;s.write_return_ready=w.ws.ack_ready;s.native_issue=w.np.selected>=0&&(!w.np.read_valid||w.hs.grant[0]);if(s.native_issue){s.native_context=w.np.warp/4;s.native_warp=w.np.warp%4;s.native_pc=0x1350+16*w.np.pc;}return s;}
 bool active()const{return ctrl.admission.signals({}).resident!=0;}
 uint64_t wake(uint64_t t){Input idle;idle.done_ready=true;auto w=wire(t,idle);uint64_t next=UINT64_MAX;auto take=[&](uint64_t v){next=std::min(next,v);};
  if(staging.internal_edge_required()||engine.internal_edge_required()||w.cs.staging&&w.ci.staging_ready||w.cs.compute&&w.ci.compute_ready||w.ss.done_valid&&w.si.done_ready||w.es.response&&w.ei.response_ready||w.cs.scratch&&w.ci.scratch_ready||w.cs.store&&w.ws.ready||w.ws.response&&w.wi.response_ready||w.cs.done||w.ei.write||w.xi.store_grant||w.xi.read_grant||w.np.selected>=0&&(!w.np.read_valid||w.ei.read_grant)||w.hs.response_valid[0]||w.hs.response_valid[1])take(t);
  if(ctrl.wake(t)!=UINT64_MAX)take(t);if(scratch.wake(t)!=UINT64_MAX)take(t);take(engine.stage.timed_wake(t));take(hub.wake(t));for(int c=0;c<n;c++){if(producer[c].wake(t)!=UINT64_MAX||consumer[c].wake(t)!=UINT64_MAX||producer[c].signals({}).release||consumer[c].signals({}).release)take(t);}return next;
 }
 void edge(uint64_t t,const Input&i){auto w=wire(t,i);
  for(int c=0;c<n;c++){generation_event::Barrier::Inputs p,q;p.reset=q.reset=ctrl.ctx[c].state==resident_event::Controller::IDLE;p.arm=w.cs.staging&&w.ci.staging_ready&&ctrl.stage_owner==c;q.arm=w.cs.compute&&w.ci.compute_ready&&ctrl.compute_owner==c;p.arm_generation=q.arm_generation=p.arrival_generation=q.arrival_generation=ctrl.ctx[c].stage;p.expected_mask=q.expected_mask=15;p.release_ready=q.release_ready=true;
   if(w.ei.write&&w.ei.write_context==c&&w.ei.write_base>=3840)p.arrival_mask=1U<<(w.ei.write_base/64-60);q.arrival_mask=w.ci.consumer_arrival[c];p.arrival=p.arrival_mask!=0;q.arrival=q.arrival_mask!=0;producer[c].edge(p);consumer[c].edge(q);}
  ctrl.edge(w.ci);staging.edge(w.si,t);engine.edge(t,w.ei);hub.edge(t,w.ho,w.hr);scratch.edge(w.xi);store.edge(w.wi);
 }
};
}
