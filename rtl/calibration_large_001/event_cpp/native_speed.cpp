#include "native_stage_event.hpp"
#include <chrono>
#include <iostream>
int main(){for(bool event:{false,true}){auto start=std::chrono::steady_clock::now();uint64_t checked=0;for(int i=0;i<100;i++){native_event::Config c;c.contexts=11;native_event::Stage s(c);for(int j=0;j<11;j++)s.set_context_start(j,10000+j*3);s.run(event);checked+=s.trace().size();}auto dt=std::chrono::duration<double>(std::chrono::steady_clock::now()-start).count();std::cout<<(event?"event":"tick")<<" seconds="<<dt<<" events="<<checked<<"\n";}}
