#include "instruction_executor.hpp"
#include <fstream>
#include <sstream>
#include <iostream>
using namespace data_path_instruction;
int main(int argc,char**argv){if(argc<5)return 2;std::ifstream in(argv[1]);std::vector<Instruction>path;std::string line;
 while(std::getline(in,line)){std::istringstream s(line);Instruction i;int n,r;s>>i.pc>>i.kind>>i.req>>i.wr>>i.rd>>i.packages>>n;for(int k=0;k<n;k++){s>>r;i.src.push_back(r);}s>>n;for(int k=0;k<n;k++){s>>r;i.dst.push_back(r);}path.push_back(i);}
 const int operands[16]={2,2,2,2,1,1,1,1,1,1,2,2,2,2,1,1};unsigned ordinal=0;for(auto&i:path)if(i.kind==1)i.operand=operands[ordinal++%16];
 for(auto&i:path){if(i.pc==0x330||i.pc==0x370||i.pc==0x730||i.pc==0x770||i.pc==0xb00||i.pc==0xbb0||i.pc==0x1b0||i.pc==0x1e0||i.pc==0x290)i.ready_class=1;else if(i.pc==0x320||i.pc==0x720)i.ready_class=2;}
 Parameters p;if(argc>5)p.constant_ready=std::stoull(argv[5]);if(argc>6)p.special_ready=std::stoull(argv[6]);p.global_ready=352;p.global_ready_A=std::stoull(argv[2]);p.global_ready_B=std::stoull(argv[3]);auto out=execute(path,p);std::ofstream f(argv[4]);for(auto&r:out.issues)f<<r.cycle<<' '<<r.end<<' '<<r.capture<<' '<<r.warp<<' '<<r.index<<' '<<r.pc<<' '<<r.kind<<'\n';std::cout<<out.cycles<<' '<<out.issues.size()<<'\n';}
