#pragma once
#include "output_metadata.hpp"
namespace generation_event {
using output_event::Cycle;using output_event::never;using output_event::require;
struct Barrier {
 enum State{IDLE,COLLECT,DELAY,RELEASE};State state=IDLE;uint32_t generation=0,next_generation=0;unsigned expected=0,arrived=0;int delay=1,left=0;
 struct Inputs{bool reset=false,arm=false,arrival=false,release_ready=true;uint32_t arm_generation=0,arrival_generation=0;unsigned expected_mask=15,arrival_mask=0;};
 struct Signals{bool arm_ready=false,arrival_ready=false,release=false,active=false;uint32_t generation=0;unsigned release_mask=0,arrived_mask=0;};
 Signals signals(const Inputs&i)const{bool legal=i.arrival_generation==generation&&i.arrival_mask&&!(i.arrival_mask&~expected)&&!(i.arrival_mask&arrived);return{!i.reset&&state==IDLE,!i.reset&&state==COLLECT&&legal,!i.reset&&state==RELEASE,!i.reset&&state!=IDLE,generation,expected,arrived};}
 void edge(const Inputs&i){require(delay>=1,"barrier delay");if(i.reset){int d=delay;*this=Barrier{};delay=d;return;}auto s=signals(i);if(i.arrival){require(state!=IDLE,"barrier arrival before arm");require(i.arrival_generation==generation,"barrier generation mismatch");require(i.arrival_mask&&!(i.arrival_mask&~expected)&&!(i.arrival_mask&arrived)&&state==COLLECT,"barrier illegal arrival");}switch(state){case IDLE:if(i.arm){require(i.arm_generation==next_generation&&i.expected_mask,"barrier invalid arm");generation=i.arm_generation;expected=i.expected_mask;arrived=0;state=COLLECT;}break;case COLLECT:if(i.arrival&&s.arrival_ready){arrived|=i.arrival_mask;if(arrived==expected){left=delay-1;state=DELAY;}}break;case DELAY:if(left>0)left--;else state=RELEASE;break;case RELEASE:if(i.release_ready){require(next_generation!=~0u,"barrier generation overflow");next_generation++;arrived=expected=0;state=IDLE;}break;}}
 Cycle wake(Cycle now)const{return state==DELAY?now+1:never;}
 void skip_idle(Cycle edges){require(state==DELAY&&edges<=uint64_t(left),"barrier skip crosses transition");left-=edges;}
};
}
