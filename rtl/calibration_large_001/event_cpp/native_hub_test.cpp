#include "native_stage_event.hpp"
#include "shared_hub_event.hpp"
#include <iostream>
int main(){for(int n:{1,2,11}){native_event::Config c;c.contexts=n;native_event::Stage isolated(c);for(int ctx=0;ctx<n;ctx++)isolated.set_context_start(ctx,ctx*3+1);isolated.run();
 c.external_reads=true;native_event::Stage connected(c);for(int ctx=0;ctx<n;ctx++)connected.set_context_start(ctx,ctx*3+1);shared_hub_event::Hub hub(2,2,1,9);
 for(uint64_t t=0;t<isolated.cycles()+20;t++){
  auto p=connected.preview(t);std::vector<shared_hub_event::Offer>offer(2);offer[1].valid=p.read_valid;offer[1].id=p.id;offer[1].addresses=p.addresses;auto s=hub.signals(t,offer);
  std::optional<std::pair<int,int>> ret;if(s.response_valid[1])ret=connected.decode_read_id(s.response_id[1]);connected.external_edge(t,s.grant[1],ret);hub.edge(t,offer,{true,true});}
 if(isolated.trace()!=connected.trace())throw std::runtime_error("native-hub integration mismatch");std::cout<<"NATIVE_HUB_PASS contexts="<<n<<" ordered_events="<<connected.trace().size()<<"\n";
}}
