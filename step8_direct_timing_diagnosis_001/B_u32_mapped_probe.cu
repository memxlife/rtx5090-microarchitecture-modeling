#include <cuda_runtime.h>
#include <cuda_bf16.h>
#include <cublas_v2.h>
#include <cublasLt.h>
#include <mma.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <functional>
#include <chrono>
#include <vector>
#include <cstring>
using namespace nvcuda;
#define CK(x) do{auto e=(x);if(e!=cudaSuccess){fprintf(stderr,"CUDA line%d %s\n",__LINE__,cudaGetErrorString(e));exit(2);}}while(0)
#define BL(x) do{auto blas_status_=(x);if(blas_status_!=CUBLAS_STATUS_SUCCESS){fprintf(stderr,"BLAS line%d status%d\n",__LINE__,int(blas_status_));exit(3);}}while(0)
constexpr int M=192,N=768,K=3072;
#define BM 32
#define BN 32
#define BK 32
static constexpr int TM=BM/16,TN=BN/16,SLOTS=(TM*TN+3)/4;

template<int WINDOW,int DEP> __global__ void ready_probe(const __nv_bfloat16*A,const __nv_bfloat16*B,unsigned short*out,unsigned long long*clockout,unsigned sentinel){unsigned long long t0=0,t1=0;
 extern __shared__ __align__(32) unsigned char storage[];unsigned short*a=(unsigned short*)storage,*b=a+1024;int tid=threadIdx.x;
 for(int k=0;k<3072;k+=32){
 #pragma unroll
 for(int operand=0;operand<2;operand++){
 #pragma unroll
 for(int group=0;group<8;group+=WINDOW){unsigned vals[WINDOW];
 #pragma unroll
 for(int j=0;j<WINDOW;j++){int i=tid+128*(group+j);int word=(group+j)%4,kk=(group+j)/4*16,lane=tid%32,warp=tid/32;const __nv_bfloat16*src=operand?B+(k+kk+(word%2)*8+lane/4)*768+blockIdx.x*32+(warp%2)*16+(word/2)*8+(lane%4)*2:A+(blockIdx.y*32+(warp/2)*16+(word%2)*8+lane/4)*3072+k+kk+(word/2)*8+(lane%4)*2;if(k==1024&&operand==1&&group==0&&j==0){if constexpr(DEP)asm volatile("{.reg .pred p; mov.u64 %1, %%clock64; ld.u32 %0,[%3]; setp.ne.u32 p,%0,%4; @p mov.u64 %2, %%clock64;}" :"=r"(vals[j]),"=l"(t0),"=l"(t1):"l"(src),"r"(sentinel):"memory");else asm volatile("{.reg .pred p; mov.u64 %1, %%clock64; ld.u32 %0,[%3]; setp.ne.u32 p,%5,%4; @p mov.u64 %2, %%clock64;}" :"=r"(vals[j]),"=l"(t0),"=l"(t1):"l"(src),"r"(sentinel),"r"(unsigned(tid)):"memory");}else asm volatile("ld.u32 %0, [%1];":"=r"(vals[j]):"l"(src):"memory");}
 #pragma unroll
 for(int j=0;j<WINDOW;j++){int i=tid+128*(group+j);unsigned short*dst=operand?b+(i/32)*48+i%32:a+i;unsigned addr=__cvta_generic_to_shared(dst);asm volatile("st.shared.u16 [%0], %1;"::"r"(addr),"r"(vals[j]):"memory");}}
 }__syncthreads();__syncthreads();}
 int cta=blockIdx.y*24+blockIdx.x;if((tid&31)==0){clockout[(cta*4+tid/32)*2]=t0;clockout[(cta*4+tid/32)*2+1]=t1;}for(int i=tid;i<2048;i+=128)out[cta*2048+i]=i<1024?a[i]:b[((i-1024)/32)*48+(i-1024)%32];
}
struct Times{std::vector<double>us;double median;};
Times timing(std::function<void(cudaStream_t)>fn,cudaStream_t stream){for(int i=0;i<1;i++)fn(stream);CK(cudaStreamSynchronize(stream));cudaGraph_t graph;cudaGraphExec_t exec;constexpr int reps=200;CK(cudaStreamBeginCapture(stream,cudaStreamCaptureModeGlobal));for(int i=0;i<reps;i++)fn(stream);CK(cudaStreamEndCapture(stream,&graph));CK(cudaGraphInstantiate(&exec,graph,0));cudaEvent_t a,b;CK(cudaEventCreate(&a));CK(cudaEventCreate(&b));for(int i=0;i<5;i++)CK(cudaGraphLaunch(exec,stream));CK(cudaStreamSynchronize(stream));Times t;for(int i=0;i<11;i++){CK(cudaEventRecord(a,stream));CK(cudaGraphLaunch(exec,stream));CK(cudaEventRecord(b,stream));CK(cudaEventSynchronize(b));float ms;CK(cudaEventElapsedTime(&ms,a,b));t.us.push_back(ms*1000/reps);}auto sorted=t.us;std::sort(sorted.begin(),sorted.end());t.median=sorted[sorted.size()/2];CK(cudaGraphExecDestroy(exec));CK(cudaGraphDestroy(graph));CK(cudaEventDestroy(a));CK(cudaEventDestroy(b));return t;}
void print_times(const char*name,int stride,const Times&t){printf("{\"kind\":\"timing\",\"name\":\"%s\",\"stride\":%d,\"median_us\":%.9g,\"samples_us\":[",name,stride,t.median);for(size_t i=0;i<t.us.size();i++)printf("%s%.9g",i?",":"",t.us[i]);printf("]}\n");}

int main(){CK(cudaSetDevice(7));cudaStream_t stream;CK(cudaStreamCreate(&stream));__nv_bfloat16 *da,*db;unsigned short*dc;unsigned long long*dt;CK(cudaMalloc(&dt,1152*8));CK(cudaMalloc(&da,2ull*M*K));CK(cudaMalloc(&db,2ull*K*N));CK(cudaMalloc(&dc,144*2048*2));std::vector<__nv_bfloat16>a(M*K),b(K*N);for(size_t i=0;i<a.size();i++)a[i]=__float2bfloat16(float(int(i%37)-18)/32);for(size_t i=0;i<b.size();i++)b[i]=__float2bfloat16(float(int(i%43)-21)/32);CK(cudaMemcpy(da,a.data(),a.size()*2,cudaMemcpyHostToDevice));CK(cudaMemcpy(db,b.data(),b.size()*2,cudaMemcpyHostToDevice));
 for(int dep:{0,1})for(int w:{4}){auto fn=[&](cudaStream_t ss){dim3 g(24,6);if(dep)ready_probe<4,1><<<g,128,5120,ss>>>(da,db,dc,dt,65536);else ready_probe<4,0><<<g,128,5120,ss>>>(da,db,dc,dt,65536);CK(cudaGetLastError());};fn(stream);CK(cudaStreamSynchronize(stream));std::vector<unsigned short>o(144*2048);CK(cudaMemcpy(o.data(),dc,o.size()*2,cudaMemcpyDeviceToHost));int bad=0;for(int c=0;c<144;c++)for(int i=0;i<2048;i++){int op=i/1024,local=i%1024,tid=local%128,g=local/128,word=g%4,kk=g/4*16,lane=tid%32,warp=tid/32,row=c/24,col=c%24;__nv_bfloat16 v=op?b[(3040+kk+(word%2)*8+lane/4)*768+col*32+(warp%2)*16+(word/2)*8+(lane%4)*2]:a[(row*32+(warp/2)*16+(word%2)*8+lane/4)*3072+3040+kk+(word/2)*8+(lane%4)*2];unsigned short expected;memcpy(&expected,&v,2);bad+=o[c*2048+i]!=expected;}printf("{\"kind\":\"correctness\",\"window\":%d,\"checked\":294912,\"bad\":%d}\n",w,bad);if(bad)return 4;printf("{\"kind\":\"condition\",\"dependent\":%d}\n",dep);std::vector<unsigned long long>ts(1152);CK(cudaMemcpy(ts.data(),dt,ts.size()*8,cudaMemcpyDeviceToHost));for(int i=0;i<576;i++)printf("{\"kind\":\"ready_cycles\",\"dep\":%d,\"owner\":%d,\"cycles\":%llu}\n",dep,i,ts[i*2+1]-ts[i*2]);}}
