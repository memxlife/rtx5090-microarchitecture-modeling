#include "units.hpp"
#include <fstream>
#include <iostream>
#include <vector>
#include <random>
using namespace timing;
int main(int argc,char**argv){unsigned tags=argc>1?unsigned(std::stoul(argv[1])):8;Matrix mat(4,7,3);Shared sh(4,2,3);Tracker tr(tags);std::mt19937 rng(5090);std::ofstream stim("stim.txt"),expect("expected.txt");for(Cycle t=0;t<4000;t++){unsigned mv=rng()%2,sv=rng()%2,mr=rng()%5!=0,sr=rng()%4!=0,mode=rng()%4,iv=rng()%2,tag=rng()%tags,bar=rng()%6,cv=rng()%2,ctag=rng()%tags,wm=rng()%64;std::array<uint32_t,32>a;for(unsigned l=0;l<32;l++)a[l]=mode==0?0:mode==1?l*4:mode==2?l*128:(l%8)*128;stim<<t<<' '<<mv<<' '<<t+1<<' '<<mr<<' '<<sv<<' '<<t+1<<' '<<sr<<' '<<mode<<' '<<iv<<' '<<tag<<' '<<bar<<' '<<cv<<' '<<ctag<<' '<<wm<<'\n';expect<<t<<' '<<(mv&&mat.ready(t))<<' '<<(mr&&mat.valid(t))<<' '<<(mat.valid(t)?mat.id():0)<<' '<<mat.size()<<' '<<(sv&&sh.ready())<<' '<<(sr&&sh.valid(t))<<' '<<(sh.valid(t)?sh.id():0)<<' '<<sh.size()<<' '<<Shared::packages(a)<<' '<<tr.ready(tag,bar)<<' '<<tr.busy()<<' '<<tr.wait(wm)<<' '<<tr.bad();for(auto c:tr.pending())expect<<' '<<c;expect<<'\n';mat.edge(t,mv,t+1,mr);sh.edge(t,sv,t+1,sr,a);tr.edge(iv,tag,bar,cv,ctag);}std::cout<<"4000 arbitrary-stimulus cycles generated\n";}
