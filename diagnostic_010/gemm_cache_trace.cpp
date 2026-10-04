#include "cache_model.hpp"
#include <cstdlib>
#include <cstdint>
// Full-tile BF16 input traces. Two scheduling hypotheses; no assumed real address hash.
int main(int argc,char**argv){if(argc!=7)return 2;unsigned M=atoi(argv[1]),N=atoi(argv[2]),K=atoi(argv[3]),BM=atoi(argv[4]),BN=atoi(argv[5]),allocation=atoi(argv[6]);if(M%BM||N%BN||K%32)return 3;
 unsigned Abytes=2*M*K,Bbytes=2*K*N,span=Abytes+Bbytes;unsigned nx=N/BN,G=(M/BM)*nx;
 for(bool concurrent:{false,true}){
 SectorCache c(96*1024*1024,allocation,span,true);std::uint64_t hits=0,reads=0;
 auto stage=[&](unsigned block,unsigned k){unsigned m=block/nx*BM,n=block%nx*BN;
  for(unsigned row=0;row<BM;row++)for(unsigned s=0;s<2;s++){hits+=c.read((2*((m+row)*K+k))/32+s);reads++;}
  for(unsigned row=0;row<32;row++)for(unsigned s=0;s<BN/16;s++){hits+=c.read((Abytes+2*((k+row)*N+n))/32+s);reads++;}
 };
 if(concurrent){for(unsigned k=0;k<K;k+=32)for(unsigned b=0;b<G;b++)stage(b,k);}
 else {for(unsigned b=0;b<G;b++)for(unsigned k=0;k<K;k+=32)stage(b,k);}
 printf("{\"schedule\":\"%s\",\"allocation_bytes\":%u,\"shape\":[%u,%u,%u],\"tile\":[%u,%u,32],\"blocks\":%u,\"requested_sectors\":%llu,\"hit_sectors\":%llu,\"miss_sectors\":%llu,\"read_hit_fraction\":%.9f}\n",concurrent?"stage_interleaved":"serial_blocks",allocation,M,N,K,BM,BN,G,(unsigned long long)reads,(unsigned long long)hits,(unsigned long long)(reads-hits),double(hits)/reads);
 }return 0;}
