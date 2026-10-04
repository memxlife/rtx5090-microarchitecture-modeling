#include "backing.hpp"
#include <iostream>
using namespace timing;
int main(){Backing backing(48);std::vector<L2Output> outputs;for(unsigned i=0;i<48;i++)outputs.emplace_back(2);unsigned accepted=0,returned=0;for(Cycle t=0;t<200;t++){for(unsigned s=0;s<48;s++){outputs[s].backing={t<80,uint32_t(t*48+s),s*128,0};outputs[s].store.valid=false;}auto p=backing.prepare(t,outputs);for(unsigned s=0;s<48;s++){accepted+=outputs[s].backing.valid&&p.read_ready[s];returned+=bool(p.read_return[s]);}backing.edge(t,outputs,p);}if(accepted!=returned||backing.outstanding()!=0)throw std::runtime_error("provider lost packet");std::cout<<"48-slice accepted="<<accepted<<" returned="<<returned<<" remaining="<<backing.outstanding()<<'\n';}
