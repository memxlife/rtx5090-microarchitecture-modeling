#pragma once
#include <array>
#include <vector>
#include <cstdint>
#include <stdexcept>
#include <algorithm>
namespace data_path_instruction {
using Cycle=uint64_t;
struct Instruction {int pc=0,kind=0,packages=1,operand=0,ready_class=0;std::vector<int>src,dst;unsigned req=0;int wr=-1,rd=-1;};
struct Ownership {
 std::array<Cycle,64>ready{},read_release{};std::array<Cycle,6>barrier{};
 bool eligible(Cycle t,const Instruction&i)const {
  for(int r:i.src)if(ready.at(r)>t)return false;
  for(int r:i.dst)if(ready.at(r)>t||read_release.at(r)>t)return false;
  for(int b=0;b<6;b++)if((i.req>>b&1)&&barrier[b]>t)return false;
  return true;
 }
 void issue(Cycle t,const Instruction&i,Cycle resultDelay,Cycle captureDelay){
  if(!eligible(t,i))throw std::runtime_error("ownership violation");
  for(int r:i.dst)ready.at(r)=t+resultDelay;
  for(int r:i.src)read_release.at(r)=std::max(read_release.at(r),t+captureDelay);
  if(i.wr>=0)barrier.at(i.wr)=std::max(barrier.at(i.wr),t+resultDelay);
  if(i.rd>=0)barrier.at(i.rd)=std::max(barrier.at(i.rd),t+captureDelay);
 }
};
struct Parameters {
 Cycle global_ready_A=0,global_ready_B=0,constant_ready=0,special_ready=0;
 Cycle global_ready=340,shared_ready=28,alu_ready=1,load_capture=1,store_capture=1,store_commit=1;
 Cycle global_interval=1,shared_interval=1,store_interval=1,mov_interval=1,matrix_interval=8,mov_ready=29,matrix_ready=32,barrier_delay=1;
 unsigned issue_width=1,global_slots=32,shared_slots=32,mov_slots=4,matrix_slots=2,store_slots=32;
};
struct Record {Cycle cycle,end,capture;int warp,index,pc,kind;};
struct Result {Cycle cycles=0;std::vector<Record>issues;};
inline Result execute(const std::vector<Instruction>&path,const Parameters&p){
 std::array<Ownership,4>own;std::array<unsigned,4>pc{};std::array<bool,4>atbar{};
 std::array<std::vector<Cycle>,7>pending;std::array<Cycle,7>next{};
 int cursor=0;Cycle release=UINT64_MAX;Result out;
 for(Cycle t=0;t<10000000;t++){
  for(auto&q:pending)q.erase(std::remove_if(q.begin(),q.end(),[&](Cycle d){return d<=t;}),q.end());
  bool empty=true;for(auto&q:pending)empty&=q.empty();
  if(release<=t){for(int w=0;w<4;w++){pc[w]++;atbar[w]=false;}release=UINT64_MAX;}
  bool done=true;for(auto x:pc)done&=x==path.size();if(done&&empty){out.cycles=t;return out;}
  std::array<bool,4>issued{};
  for(unsigned port=0;port<p.issue_width;port++){
   int selected=-1;
   for(int d=0;d<4;d++){
    int w=(cursor+d)%4;if(issued[w]||atbar[w]||pc[w]>=path.size())continue;auto&i=path[pc[w]];
    if(!own[w].eligible(t,i))continue;unsigned cap=UINT32_MAX;
    if(i.kind==1)cap=p.global_slots;if(i.kind==2)cap=p.store_slots;if(i.kind==3)cap=p.mov_slots;if(i.kind==4)cap=p.matrix_slots;if(i.kind==6)cap=p.shared_slots;
    if(t<next[i.kind]||pending[i.kind].size()>=cap)continue;selected=w;break;
   }
   if(selected<0)break;int w=selected;auto&i=path[pc[w]];Cycle delay=i.ready_class==1&&p.constant_ready?p.constant_ready:i.ready_class==2&&p.special_ready?p.special_ready:p.alu_ready,capture=0,interval=0;
   if(i.kind==1){delay=i.operand==1&&p.global_ready_A?p.global_ready_A:i.operand==2&&p.global_ready_B?p.global_ready_B:p.global_ready;capture=p.load_capture;interval=p.global_interval;}
   if(i.kind==2){delay=p.store_commit;capture=p.store_capture;interval=p.store_interval;}
   if(i.kind==3){delay=p.mov_ready;interval=p.mov_interval;}
   if(i.kind==4){delay=p.matrix_ready;interval=p.matrix_interval;}
   if(i.kind==6){delay=p.shared_ready+i.packages;capture=p.load_capture;interval=p.shared_interval*i.packages;}
   own[w].issue(t,i,delay,capture);
   if(i.kind&&i.kind!=5){pending[i.kind].push_back(t+delay);next[i.kind]=t+interval;}
   out.issues.push_back({t,t+delay,t+capture,w,int(pc[w]),i.pc,i.kind});issued[w]=true;cursor=(w+1)%4;
   if(i.kind==5)atbar[w]=true;else pc[w]++;
  }
  bool all=true;for(auto b:atbar)all&=b;
  if(all&&pending[1].empty()&&pending[2].empty()&&pending[6].empty()&&release==UINT64_MAX)release=t+p.barrier_delay;
 }
 throw std::runtime_error("executor limit exceeded");
}
}
