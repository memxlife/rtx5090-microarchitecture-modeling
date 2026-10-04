#pragma once
#include "units.hpp"
#include <optional>
namespace shared_hub_event {
struct Offer{bool valid=false;uint32_t id=0;std::array<uint32_t,32>addresses{};};
struct Signals{std::vector<bool>grant,response_valid;std::vector<uint32_t>response_id;std::vector<unsigned>client_outstanding;unsigned outstanding=0;};
class Hub{
 struct Record{bool live=false;unsigned owner=0;uint32_t internal=0,external=0;};
 unsigned clients,cursor=0;uint32_t next_id=0;std::vector<Record>records;timing::Shared service;
 int free_record()const{for(unsigned i=0;i<records.size();i++)if(!records[i].live)return i;return -1;}
 int selected(const std::vector<Offer>&o)const{if(free_record()<0)return -1;for(unsigned i=0;i<clients;i++){unsigned c=(cursor+i)%clients;if(o[c].valid)return c;}return -1;}
 int returned(timing::Cycle t)const{if(!service.valid(t))return -1;for(unsigned i=0;i<records.size();i++)if(records[i].live&&records[i].internal==service.id())return i;throw std::runtime_error("unowned hub response");}
 public:
 Hub(unsigned c,unsigned slots,unsigned interval,unsigned delay):clients(c),records(slots),service(slots,interval,delay){}
 Signals signals(timing::Cycle t,const std::vector<Offer>&o)const{if(o.size()!=clients)throw std::runtime_error("hub client shape");Signals s;s.grant.resize(clients);s.response_valid.resize(clients);s.response_id.resize(clients);s.client_outstanding.resize(clients);for(auto&r:records)if(r.live){s.outstanding++;s.client_outstanding[r.owner]++;}int c=selected(o);if(c>=0&&service.ready())s.grant[c]=true;int ri=returned(t);if(ri>=0){auto&r=records[ri];s.response_valid[r.owner]=true;s.response_id[r.owner]=r.external;}return s;}
 timing::Cycle wake(timing::Cycle t)const{return service.wake(t);}
 void edge(timing::Cycle t,const std::vector<Offer>&o,const std::vector<bool>&ready){auto s=signals(t,o);int c=selected(o),f=free_record(),ri=returned(t);bool pop=ri>=0&&ready[records[ri].owner],push=c>=0&&s.grant[c];std::array<uint32_t,32>a{};if(c>=0)a=o[c].addresses;
  if(s.outstanding!=service.size())throw std::runtime_error("hub service conservation");
  if(push){for(auto&r:records)if(r.live&&r.owner==unsigned(c)&&r.external==o[c].id)throw std::runtime_error("duplicate client ID");if(next_id==UINT32_MAX)throw std::runtime_error("hub ID exhausted");}
  service.edge(t,push,next_id,pop,a);if(pop)records[ri].live=false;if(push){records[f]={true,unsigned(c),next_id++,o[c].id};cursor=(c+1)%clients;}
 }
};
}
