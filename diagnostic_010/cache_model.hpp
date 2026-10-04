#pragma once
// Explicit allocation tags, per-sector validity, and replacement state.
// Fully associative placement is a hypothesis, not an RTX mapping claim.
#include <vector>
#include <cstdio>
#include <cassert>
struct SectorCache {
 unsigned capacity,slots,count=0;int head=-1,tail=-1;bool lru;
 std::vector<int> prev,next;std::vector<unsigned char> valid;
 SectorCache(unsigned bytes,unsigned allocation,unsigned address_bytes,bool recency):capacity(bytes/allocation),slots(allocation/32),lru(recency),prev(address_bytes/allocation,-1),next(address_bytes/allocation,-1),valid(address_bytes/allocation,0){}
 void unlink(int t){if(prev[t]>=0)next[prev[t]]=next[t];else head=next[t];if(next[t]>=0)prev[next[t]]=prev[t];else tail=prev[t];}
 void append(int t){prev[t]=tail;next[t]=-1;if(tail>=0)next[tail]=t;else head=t;tail=t;}
 bool read(unsigned sector){unsigned tag=sector/slots,bit=1u<<(sector%slots);bool hit=valid[tag]&bit;
  if(valid[tag]){if(lru&&int(tag)!=tail){unlink(tag);append(tag);}}
  else {if(count==capacity){int old=head;unlink(old);valid[old]=0;}else count++;append(tag);}
  valid[tag]|=bit;return hit;
 }
};
