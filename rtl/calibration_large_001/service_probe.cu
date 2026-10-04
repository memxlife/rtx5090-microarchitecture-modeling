#include <cuda_runtime.h>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <algorithm>
#define CK(x) do{cudaError_t e=(x);if(e!=cudaSuccess){fprintf(stderr,"%s\n",cudaGetErrorString(e));exit(1);}}while(0)
__global__ void init(unsigned*x,unsigned*y,size_t n){for(size_t i=blockIdx.x*blockDim.x+threadIdx.x;i<n;i+=gridDim.x*blockDim.x){x[i]=1;y[i]=0;}}
__global__ void service(const unsigned*x,unsigned*y,size_t n,int mode,int reps,unsigned long long*counts){
 unsigned long long count=0;for(int r=0;r<reps;r++)for(size_t i=size_t(blockIdx.x)*blockDim.x+threadIdx.x;i<n;i+=size_t(gridDim.x)*blockDim.x){unsigned v=1;if(mode!=1)asm volatile("ld.global.cg.u32 %0,[%1];":"=r"(v):"l"(x+i):"memory");if(mode!=0)asm volatile("st.global.wb.u32 [%0],%1;"::"l"(y+i),"r"(v+2):"memory");count+=v;}
 counts[blockIdx.x*blockDim.x+threadIdx.x]=count;
}
int main(){cudaDeviceProp p;CK(cudaGetDeviceProperties(&p,0));fprintf(stderr,"GPU %s SMs %d L2 %d\n",p.name,p.multiProcessorCount,p.l2CacheSize);
 for(size_t bytes:{size_t(16)<<20,size_t(256)<<20}){size_t n=bytes/4;unsigned*x,*y;unsigned long long*c;CK(cudaMalloc(&x,bytes));CK(cudaMalloc(&y,bytes));CK(cudaMalloc(&c,680*256*sizeof(*c)));init<<<680,256>>>(x,y,n);CK(cudaDeviceSynchronize());
 for(int mode=0;mode<3;mode++)for(int blocks:{1,32,170,680}){
 service<<<blocks,256>>>(x,y,n,mode,4,c);CK(cudaDeviceSynchronize());std::vector<float>times;cudaEvent_t a,b;CK(cudaEventCreate(&a));CK(cudaEventCreate(&b));
 for(int t=0;t<3;t++){CK(cudaEventRecord(a));service<<<blocks,256>>>(x,y,n,mode,4,c);CK(cudaEventRecord(b));CK(cudaEventSynchronize(b));float ms;CK(cudaEventElapsedTime(&ms,a,b));times.push_back(ms);}std::sort(times.begin(),times.end());
 std::vector<unsigned long long> hostc(blocks*256);CK(cudaMemcpy(hostc.data(),c,hostc.size()*sizeof(*c),cudaMemcpyDeviceToHost));unsigned long long total=0;for(auto v:hostc)total+=v;if(total!=n*4){fprintf(stderr,"count mismatch\n");return 2;}
 if(mode!=0){std::vector<unsigned>out(n);CK(cudaMemcpy(out.data(),y,bytes,cudaMemcpyDeviceToHost));for(auto v:out)if(v!=3){fprintf(stderr,"write mismatch\n");return 3;}}
 double traffic=double(bytes)*4*(mode==2?2:1);printf("{\"bytes\":%zu,\"mode\":%d,\"blocks\":%d,\"repetitions\":4,\"median_ms\":%.9g,\"requested_GBps\":%.9g,\"correct\":true}\n",bytes,mode,blocks,times[1],traffic/times[1]/1e6);fflush(stdout);CK(cudaEventDestroy(a));CK(cudaEventDestroy(b));}
 CK(cudaFree(x));CK(cudaFree(y));CK(cudaFree(c));}
}
