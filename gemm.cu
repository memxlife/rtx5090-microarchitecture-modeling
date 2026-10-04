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
__global__ void gemm(const __nv_bfloat16* A,const __nv_bfloat16* B,float* C,int M,int N,int K){
 extern __shared__ __align__(32) unsigned char storage[];
 auto a=(__nv_bfloat16*)storage;auto b=a+BM*BK;
 __shared__ __align__(32) float result[4*256];
 int tid=threadIdx.x,warp=tid/32,lane=tid%32;
 wmma::fragment<wmma::accumulator,16,16,16,float> acc[SLOTS];
 #pragma unroll
 for(int j=0;j<SLOTS;j++)wmma::fill_fragment(acc[j],0.f);
 for(int k=0;k<K;k+=BK){
 for(int i=tid;i<BM*BK;i+=128){int r=blockIdx.y*BM+i/BK,c=k+i%BK;a[i]=(r<M&&c<K)?A[r*K+c]:__float2bfloat16(0);}
 for(int i=tid;i<BK*BN;i+=128){int r=k+i/BN,c=blockIdx.x*BN+i%BN;b[i]=(r<K&&c<N)?B[r*N+c]:__float2bfloat16(0);}
 __syncthreads();
 #pragma unroll
 for(int j=0;j<SLOTS;j++){int tile=warp+4*j;if(tile<TM*TN){int r=tile/TN,c=tile%TN;
 #pragma unroll
 for(int kk=0;kk<BK;kk+=16){wmma::fragment<wmma::matrix_a,16,16,16,__nv_bfloat16,wmma::row_major> fa;wmma::fragment<wmma::matrix_b,16,16,16,__nv_bfloat16,wmma::row_major> fb;
 wmma::load_matrix_sync(fa,a+r*16*BK+kk,BK);wmma::load_matrix_sync(fb,b+kk*BN+c*16,BN);wmma::mma_sync(acc[j],fa,fb,acc[j]);}}}
 __syncthreads();}
 #pragma unroll
 for(int j=0;j<SLOTS;j++){int tile=warp+4*j;if(tile<TM*TN){int r=tile/TN,c=tile%TN;wmma::store_matrix_sync(result+warp*256,acc[j],16,wmma::mem_row_major);__syncwarp();for(int i=lane;i<256;i+=32){int rr=blockIdx.y*BM+r*16+i/16,cc=blockIdx.x*BN+c*16+i%16;if(rr<M&&cc<N)C[rr*N+cc]=result[warp*256+i];}__syncwarp();}}
}
int main(int argc,char**argv){int M=argc>1?atoi(argv[1]):960,N=argc>2?atoi(argv[2]):960,K=argc>3?atoi(argv[3]):960;
 std::vector<__nv_bfloat16>a(M*K),b(K*N);for(size_t i=0;i<a.size();i++)a[i]=__float2bfloat16(((int)(i%17)-8)/16.f);for(size_t i=0;i<b.size();i++)b[i]=__float2bfloat16(((int)(i%13)-6)/16.f);
 __nv_bfloat16 *da,*db;float*dc;CK(cudaMalloc(&da,a.size()*2));CK(cudaMalloc(&db,b.size()*2));CK(cudaMalloc(&dc,M*N*4ull));CK(cudaMemcpy(da,a.data(),a.size()*2,cudaMemcpyHostToDevice));CK(cudaMemcpy(db,b.data(),b.size()*2,cudaMemcpyHostToDevice));int smem=2*BK*(BM+BN);if(argc>4)smem=std::max(smem,atoi(argv[4]));CK(cudaFuncSetAttribute(gemm,cudaFuncAttributeMaxDynamicSharedMemorySize,smem));cudaFuncAttributes attr;CK(cudaFuncGetAttributes(&attr,gemm));int resident;CK(cudaOccupancyMaxActiveBlocksPerMultiprocessor(&resident,gemm,128,smem));dim3 grid((N+BN-1)/BN,(M+BM-1)/BM);auto launch=[&](){gemm<<<grid,128,smem>>>(da,db,dc,M,N,K);};launch();CK(cudaGetLastError());CK(cudaDeviceSynchronize());std::vector<float>c(M*N);CK(cudaMemcpy(c.data(),dc,c.size()*4,cudaMemcpyDeviceToHost));double maxerr=0;bool correct=true;
 // Independent cuBLAS BF16/FP32 reference, checked over every output.
 float *refdev;CK(cudaMalloc(&refdev,M*N*4ull));cublasHandle_t handle;if(cublasCreate(&handle)!=CUBLAS_STATUS_SUCCESS)return 3;float alpha=1,beta=0;
 auto status=cublasGemmEx(handle,CUBLAS_OP_N,CUBLAS_OP_N,N,M,K,&alpha,db,CUDA_R_16BF,N,da,CUDA_R_16BF,K,&beta,refdev,CUDA_R_32F,N,CUBLAS_COMPUTE_32F,CUBLAS_GEMM_DEFAULT);
 if(status!=CUBLAS_STATUS_SUCCESS){fprintf(stderr,"cuBLAS status %d\n",status);return 3;}
 std::vector<float>reference(M*N);CK(cudaMemcpy(reference.data(),refdev,reference.size()*4,cudaMemcpyDeviceToHost));
 for(size_t i=0;i<c.size();i++){double e=fabs(c[i]-reference[i]);maxerr=std::max(maxerr,e);if(!std::isfinite(c[i])||e>1e-3+1e-3*fabs(reference[i]))correct=false;}
 float *flush_buffer,*sink;size_t flush_n=128ull*1024*1024;CK(cudaMalloc(&flush_buffer,flush_n*4));CK(cudaMalloc(&sink,4096*4));CK(cudaMemset(flush_buffer,0,flush_n*4));
 for(int i=0;i<10;i++)launch();CK(cudaDeviceSynchronize());cudaEvent_t x,y;CK(cudaEventCreate(&x));CK(cudaEventCreate(&y));printf("{\"tile\":[%d,%d,%d],\"shape\":[%d,%d,%d],\"correct\":%s,\"max_abs_error\":%.9g,\"registers_thread\":%d,\"local_bytes_thread\":%zu,\"static_shared_bytes\":%zu,\"dynamic_shared_bytes\":%d,\"resident_ctas\":%d,\"timing\":\"512MiB sweep before each launch; sweep excluded\",\"latency_ms_samples\":[",BM,BN,BK,M,N,K,correct?"true":"false",maxerr,attr.numRegs,attr.localSizeBytes,attr.sharedSizeBytes,smem,resident);
 for(int r=0;r<9;r++){double total=0;for(int i=0;i<5;i++){flush_cache<<<4096,256>>>(flush_buffer,sink,flush_n);CK(cudaEventRecord(x));launch();CK(cudaEventRecord(y));CK(cudaEventSynchronize(y));float ms;CK(cudaEventElapsedTime(&ms,x,y));total+=ms;}printf("%s%.9g",r?",":"",total/5);}
 printf("]}\n");return correct?0:2;}
