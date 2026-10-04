#include "native_stage_event.hpp"
#include <chrono>
#include <iostream>
int main(){for(int n:{1,2,11})for(int delay:{0,10000}){
 native_event::Config cfg;cfg.contexts=n;native_event::Stage event(cfg),ticks(cfg);
 for(int c=0;c<n;c++){event.set_context_start(c,delay+c*3);ticks.set_context_start(c,delay+c*3);}
 event.run(true);ticks.run(false);
 if(event.cycles()!=ticks.cycles()||event.trace()!=ticks.trace())throw std::runtime_error("event/tick mismatch");
 std::cout<<"NATIVE_EVENT_PASS contexts="<<n<<" start="<<delay<<" cycles="<<event.cycles()<<" events="<<event.trace().size()<<" evaluated_edges="<<event.edges()<<" skipped_cycles="<<event.skipped()<<"\n";
}}
