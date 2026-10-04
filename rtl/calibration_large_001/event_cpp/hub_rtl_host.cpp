#include "Vhub_component_top.h"
#include "verilated.h"
#include "shared_hub_event.hpp"
#include <iostream>
int main(){Vhub_component_top d;d.rst=1;d.clk=0;d.eval();d.clk=1;d.eval();d.rst=0;shared_hub_event::Hub hub(2,2,2,28);unsigned grants=0,returns=0;
 for(uint64_t t=0;t<5000;t++){
 std::vector<shared_hub_event::Offer>o(2);std::vector<bool>ready(2);
 d.candidate_valid=0;d.rsp_ready=0;
 for(unsigned c=0;c<2;c++){o[c].valid=t%unsigned(c+3)!=0;o[c].id=t;ready[c]=t%unsigned(c+5)!=0;if(o[c].valid)d.candidate_valid|=1<<c;if(ready[c])d.rsp_ready|=1<<c;d.candidate_id[c]=o[c].id;for(unsigned l=0;l<32;l++){o[c].addresses[l]=(t%4==0)?4*(l%8):4*l+128*c*(l%2);d.addresses[c][l]=o[c].addresses[l];}}
 d.clk=0;d.eval();auto s=hub.signals(t,o);bool same=s.outstanding==unsigned(d.outstanding);
 for(unsigned c=0;c<2;c++){same&=s.grant[c]==bool(d.candidate_grant&(1<<c))&&s.response_valid[c]==bool(d.rsp_valid&(1<<c))&&s.client_outstanding[c]==unsigned(d.client_outstanding[c]);if(s.response_valid[c])same&=s.response_id[c]==d.rsp_id[c];grants+=s.grant[c];returns+=s.response_valid[c]&&ready[c];}
 if(!same){std::cerr<<"hub mismatch cycle="<<t<<"\n";return 1;}hub.edge(t,o,ready);d.clk=1;d.eval();}
 std::cout<<"HUB_RTL_PASS cycles=5000 grants="<<grants<<" returns="<<returns<<"\n";
}
