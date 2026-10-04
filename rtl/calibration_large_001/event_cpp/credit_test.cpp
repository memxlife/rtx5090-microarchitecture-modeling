#include "l2_slice.hpp"
#include <fstream>
#include <random>
using namespace timing;
std::string hex(const std::vector<bool>&v){std::string s;for(int nib=int((v.size()+3)/4)-1;nib>=0;--nib){unsigned x=0;for(unsigned b=0;b<4;b++)if(nib*4+b<v.size()&&v[nib*4+b])x|=1<<b;s.push_back("0123456789abcdef"[x]);}return s;}
int main(){std::mt19937 rng(5092);GlobalCredits g(170,37481,31056,49089);std::ofstream st("credit_stim.txt"),ex("credit_expected.txt");for(unsigned t=0;t<2000;t++){std::vector<bool>r(170),w(170),ar(170),aw(170);for(unsigned s=0;s<170;s++){r[s]=rng()%3!=0;w[s]=rng()%3==0;}auto p=g.permit(r,w);for(unsigned s=0;s<170;s++){ar[s]=p.first[s]&&rng()%3!=0;aw[s]=p.second[s]&&rng()%3!=0;}st<<hex(r)<<' '<<hex(w)<<' '<<hex(ar)<<' '<<hex(aw)<<'\n';ex<<hex(p.first)<<' '<<hex(p.second)<<'\n';g.edge(ar,aw);}}
