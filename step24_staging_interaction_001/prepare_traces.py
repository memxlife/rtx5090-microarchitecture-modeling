from pathlib import Path
import shutil
root=Path(__file__).resolve().parents[1];out=root/'step24_staging_interaction_001'
for name,source in [('baseline',root/'rtl/calibration_large_001/event_cpp'),('candidate',root/'step23_hlm_connected_gpu_reproduction_001/staging_cpp_repair')]:
 p=out/name;p.mkdir(exist_ok=True)
 for f in source.glob('*.hpp'):shutil.copyfile(f,p/f.name)
 shutil.copyfile(source/'full_gpu_parallel.cpp',p/'full_gpu_parallel.cpp')
 f=p/'staging_event.hpp';s=f.read_text();at=s.index(' public:')
 if name=='candidate':
  method='''\n public:\n std::array<uint64_t,12> diagnostic(Cycle t)const {std::array<uint64_t,12>a{};auto&path=producer_path();a[0]=outstanding();a[1]=loads.size();a[2]=stores.size();for(auto&l:loads){a[3]+=l.returned!=3;a[4]+=l.returned==3&&l.ready>t;a[5]+=l.accepted<2;}for(int c=0;c<int(ctx.size());c++)for(int w=0;w<4;w++)if(ctx[c].active&&!ctx[c].done&&ctx[c].pc[w]<path.size()){a[6]++;auto&o=path[ctx[c].pc[w]];if(eligible(c,w,o,t)){a[7]++;if((o.kind!=1||loads.size()<32)&&(o.kind!=2||stores.size()<32))a[8]++;}else{auto&own=ctx[c].own[w];bool sr=false,wr=false;for(int r:o.src)sr|=own.ready[r]>t;for(int r:o.dst)wr|=own.release[r]>t;a[9]+=sr;a[10]+=wr;} }a[11]=issues_;return a;}\n'''
 else:
  method='''\n public:\n std::array<uint64_t,12> diagnostic(Cycle t)const {std::array<uint64_t,12>a{};a[0]=outstanding();for(auto&c:ctx){a[1]+=c.load!=L_IDLE;a[3]+=c.load==L_WAIT;a[5]+=c.load==L_SEND;a[6]+=c.outer!=O_IDLE;a[7]+=c.load==L_RESPONSE;}a[2]=response_owner>=0;return a;}\n'''
 s=s[:at]+method+s[at:];f.write_text(s)
 f=p/'sm_event.hpp';s=f.read_text();at=s.index(' public:');method='''\n public:\n std::array<uint64_t,16> diagnostic(uint64_t t)const {std::array<uint64_t,16>a{};auto b=staging.diagnostic(t);for(int j=0;j<12;j++)a[j]=b[j];for(auto&c:ctrl.ctx){a[12]+=c.state==resident_event::Controller::STAGE_WAIT;a[13]+=c.state==resident_event::Controller::COMPUTE_WAIT;}a[14]=staging.completions();a[15]=staging.commits();return a;}\n''';s=s[:at]+method+s[at:];f.write_text(s)
 f=p/'full_gpu_parallel.cpp';s=f.read_text();s=s.replace('Cycle base=0;', 'std::array<uint64_t,16> sums{};Cycle base=0;');needle=' if(t%10000==9999';idx=s.index(needle);s=s[:idx]+''' std::array<uint64_t,16> d{};for(unsigned ds=0;ds<sms;ds++){auto x=sm[ds]->diagnostic(t+1);for(int j=0;j<16;j++)d[j]+=x[j];}for(int j=0;j<14;j++)sums[j]+=d[j];if(t%1000==999){std::cout<<"TRACE t="<<t+1;for(auto x:d)std::cout<<' '<<x;std::cout<<"\\nSUM";for(auto x:sums)std::cout<<' '<<x;std::cout<<std::endl;}
'''+s[idx:];f.write_text(s)
