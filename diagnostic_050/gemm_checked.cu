#include <cuda_runtime.h>
#include <cuda_bf16.h>
#include <cublas_v2.h>
#include <mma.h>
#include <cstdio>
#include <cstdlib>
#include <vector>
#include <cmath>
#include <algorithm>
using namespace nvcuda;
#ifndef BM
#define BM 64
#define BN 64
#define BK 32
#endif
#define CK(x) do{cudaError_t e=(x);if(e!=cudaSuccess){fprintf(stderr,"CUDA %s\n",cudaGetErrorString(e));exit(1);}}while(0)
static constexpr int TM=BM/16,TN=BN/16,SLOTS=(TM*TN+3)/4;
__global__ void flush_cache(const float* buffer,float* sink,size_t n){float sum=0;for(size_t i=blockIdx.x*blockDim.x+threadIdx.x;i<n;i+=gridDim.x*blockDim.x){float v;asm volatile("ld.global.cg.f32 %0, [%1];":"=f"(v):"l"(buffer+i));sum+=v;}if(threadIdx.x==0)sink[blockIdx.x]=sum;}
__global__ void gemm(const __nv_bfloat16* A,const __nv_bfloat16* B,float* C,int M,int N,int K,const unsigned* zero,int mode){
 #if PIN
 unsigned z;asm volatile("ld.global.cg.u32 %0, [%1];":"=r"(z):"l"(zero):"memory");
 A+=z;B+=z;M+=z;N+=z;K+=z;
 #endif
 extern __shared__ __align__(32) unsigned char storage[];
 auto a=(__nv_bfloat16*)storage;auto b=a+BM*BK;
 __shared__ __align__(32) float result[4*256];
 int tid=threadIdx.x,warp=tid/32,lane=tid%32;
 if(!(mode&1)){
  for(int i=tid;i<BM*BK;i+=128)a[i]=__float2bfloat16(0.0625f);
  for(int i=tid;i<BK*BN;i+=128)b[i]=__float2bfloat16(0.0625f);
 }
 __syncthreads();
 wmma::fragment<wmma::accumulator,16,16,16,float> acc[SLOTS];
 #pragma unroll
 for(int j=0;j<SLOTS;j++)wmma::fill_fragment(acc[j],0.f);
 for(int k=0;k<K;k+=BK){
 if(mode&1){
 for(int i=tid;i<BM*BK;i+=128){int r=blockIdx.y*BM+i/BK,c=k+i%BK;a[i]=(r<M&&c<K)?A[r*K+c]:__float2bfloat16(0);}
 for(int i=tid;i<BK*BN;i+=128){int r=k+i/BN,c=blockIdx.x*BN+i%BN;b[i]=(r<K&&c<N)?B[r*N+c]:__float2bfloat16(0);}
 }
 __syncthreads();
 if(mode&2){
 #pragma unroll
 for(int j=0;j<SLOTS;j++){int tile=warp+4*j;if(tile<TM*TN){int r=tile/TN,c=tile%TN;
 #pragma unroll
 for(int kk=0;kk<BK;kk+=16){wmma::fragment<wmma::matrix_a,16,16,16,__nv_bfloat16,wmma::row_major> fa;wmma::fragment<wmma::matrix_b,16,16,16,__nv_bfloat16,wmma::row_major> fb;
 wmma::load_matrix_sync(fa,a+r*16*BK+kk,BK);wmma::load_matrix_sync(fb,b+kk*BN+c*16,BN);wmma::mma_sync(acc[j],fa,fb,acc[j]);}}}
 }
 __syncthreads();}
 #pragma unroll
 for(int j=0;j<SLOTS;j++){int tile=warp+4*j;if(tile<TM*TN){int r=tile/TN,c=tile%TN;wmma::store_matrix_sync(result+warp*256,acc[j],16,wmma::mem_row_major);__syncwarp();for(int i=lane;i<256;i+=32){int rr=blockIdx.y*BM+r*16+i/16,cc=blockIdx.x*BN+c*16+i%16;if(rr<M&&cc<N)C[rr*N+cc]=result[warp*256+i];}__syncwarp();}}
}

template<int period> __global__ void initialize_pattern(__nv_bfloat16* data,size_t count) {
 for(size_t i=blockIdx.x*blockDim.x+threadIdx.x;i<count;i+=gridDim.x*blockDim.x)
  data[i]=__float2bfloat16(((int)(i%period)-period/2)/16.f);
}
__global__ void preheat_input(const __nv_bfloat16* data,unsigned* sink,size_t count) {
 unsigned sum=0;
 for(size_t i=blockIdx.x*blockDim.x+threadIdx.x;i<count;i+=gridDim.x*blockDim.x) {
  unsigned short v;asm volatile("ld.global.cg.u16 %0, [%1];":"=h"(v):"l"(data+i):"memory");sum+=v;
 }
 if(threadIdx.x==0)sink[blockIdx.x]=sum;
}

int main(int argc,char**argv) {
 if(argc!=6)return 4;int M=atoi(argv[1]),N=atoi(argv[2]),K=atoi(argv[3]),warm=atoi(argv[4]),mode=atoi(argv[5]);if(mode<0||mode>3)return 4;
 const size_t count=1024ull*1024*1024;
 if(M%BM||N%BN||K%BK || M*K>count || K*N>count)return 4;
 __nv_bfloat16 *da,*db;float *dc,*refdev;unsigned*sink,*zero;
 CK(cudaMalloc(&da,count*2));CK(cudaMalloc(&db,count*2));CK(cudaMalloc(&dc,M*N*4ull));CK(cudaMalloc(&refdev,M*N*4ull));CK(cudaMalloc(&sink,4096*4));CK(cudaMalloc(&zero,4));CK(cudaMemset(zero,0,4));
 initialize_pattern<17><<<4096,256>>>(da,count);initialize_pattern<13><<<4096,256>>>(db,count);CK(cudaDeviceSynchronize());
 int smem=2*BK*(BM+BN);CK(cudaFuncSetAttribute(gemm,cudaFuncAttributeMaxDynamicSharedMemorySize,smem));
 cudaFuncAttributes attr;CK(cudaFuncGetAttributes(&attr,gemm));int resident;CK(cudaOccupancyMaxActiveBlocksPerMultiprocessor(&resident,gemm,128,smem));
 if(getenv("RESIDENT_CTAS")) {int target=atoi(getenv("RESIDENT_CTAS"));int limit;CK(cudaDeviceGetAttribute(&limit,cudaDevAttrMaxSharedMemoryPerBlockOptin,0));CK(cudaFuncSetAttribute(gemm,cudaFuncAttributeMaxDynamicSharedMemorySize,limit-attr.sharedSizeBytes));bool found=false;for(int bytes=smem;bytes<=limit-(int)attr.sharedSizeBytes;bytes+=256){int r;CK(cudaOccupancyMaxActiveBlocksPerMultiprocessor(&r,gemm,128,bytes));if(r==target){smem=bytes;resident=r;found=true;break;}}if(!found)return 5;}
 CK(cudaMemset(dc,0,M*N*4ull));dim3 grid(N/BN,M/BM);auto launch=[&](size_t oa,size_t ob){gemm<<<grid,128,smem>>>(da+oa,db+ob,dc,M,N,K,zero,mode);};
 launch(0,0);CK(cudaGetLastError());CK(cudaDeviceSynchronize());
 cublasHandle_t handle;if(cublasCreate(&handle)!=CUBLAS_STATUS_SUCCESS)return 3;float alpha=1,beta=0;
 auto status=cublasGemmEx(handle,CUBLAS_OP_N,CUBLAS_OP_N,N,M,K,&alpha,db,CUDA_R_16BF,N,da,CUDA_R_16BF,K,&beta,refdev,CUDA_R_32F,N,CUBLAS_COMPUTE_32F,CUBLAS_GEMM_DEFAULT);
 if(status!=CUBLAS_STATUS_SUCCESS)return 3;
 std::vector<float> reference(M*N),observed(M*N);CK(cudaMemcpy(reference.data(),refdev,M*N*4ull,cudaMemcpyDeviceToHost));
 if(mode!=3)std::fill(reference.begin(),reference.end(),mode==2?K/256.f:0.f);

 for(int i=0;i<10;i++)launch(0,0);CK(cudaDeviceSynchronize());
 // Reinitialization displaces the early reference/warmup regions before measurement.
 initialize_pattern<17><<<4096,256>>>(da,count);initialize_pattern<13><<<4096,256>>>(db,count);CK(cudaDeviceSynchronize());
 cudaEvent_t x,y;CK(cudaEventCreate(&x));CK(cudaEventCreate(&y));std::vector<double> samples;double maxerr=0;
 for(int r=0;r<9;r++) {double total=0;
  for(int i=0;i<5;i++) {
   int sequence=r*5+i;size_t oa=(size_t)sequence*17*1024*1024,ob=(size_t)sequence*13*1024*1024;
   if(oa+(size_t)M*K>count||ob+(size_t)K*N>count)return 4;
   if(warm){preheat_input<<<4096,256>>>(da+oa,sink,(size_t)M*K);preheat_input<<<4096,256>>>(db+ob,sink,(size_t)K*N);}
   CK(cudaEventRecord(x));launch(oa,ob);CK(cudaEventRecord(y));CK(cudaEventSynchronize(y));float ms;CK(cudaEventElapsedTime(&ms,x,y));total+=ms;
   CK(cudaMemcpy(observed.data(),dc,M*N*4ull,cudaMemcpyDeviceToHost));
   for(size_t j=0;j<observed.size();j++) {double e=fabs(observed[j]-reference[j]);maxerr=std::max(maxerr,e);if(!std::isfinite(observed[j])||e>1e-3+1e-3*fabs(reference[j])) {fprintf(stderr,"output mismatch\n");return 2;}}
  }samples.push_back(total/5);
 }
 printf("{\"tile\":[%d,%d,%d],\"shape\":[%d,%d,%d],\"warm\":%d,\"correct\":true,\"output_checks\":45,\"max_abs_error\":%.9g,\"registers_thread\":%d,\"local_bytes_thread\":%zu,\"resident_ctas\":%d,\"latency_ms_samples\":[",BM,BN,BK,M,N,K,warm,maxerr,attr.numRegs,attr.localSizeBytes,resident);
 for(int r=0;r<9;r++)printf("%s%.9g",r?",":"",samples[r]);printf("]}\n");return 0;
}
