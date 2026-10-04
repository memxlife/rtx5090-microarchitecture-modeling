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
using namespace nvcuda;
#define CK(x) do{auto e=(x);if(e!=cudaSuccess){fprintf(stderr,"CUDA line%d %s\n",__LINE__,cudaGetErrorString(e));exit(2);}}while(0)
#define BL(x) do{auto blas_status_=(x);if(blas_status_!=CUBLAS_STATUS_SUCCESS){fprintf(stderr,"BLAS line%d status%d\n",__LINE__,int(blas_status_));exit(3);}}while(0)
constexpr int M=192,N=768,K=2048;
#define BM 32
#define BN 32
#define BK 32
static constexpr int TM=BM/16,TN=BN/16,SLOTS=(TM*TN+3)/4;
template<int LDB> __global__ void layout_gemm(const __nv_bfloat16* A,const __nv_bfloat16* B,float* C,int M,int N,int K){
 extern __shared__ __align__(32) unsigned char storage[];
 auto a=(__nv_bfloat16*)storage;auto b=a+BM*BK;
 __shared__ __align__(32) float result[4*256];
 int tid=threadIdx.x,warp=tid/32,lane=tid%32;
 wmma::fragment<wmma::accumulator,16,16,16,float> acc[SLOTS];
 #pragma unroll
 for(int j=0;j<SLOTS;j++)wmma::fill_fragment(acc[j],0.f);
 for(int k=0;k<K;k+=BK){
 for(int i=tid;i<BM*BK;i+=128){int r=blockIdx.y*BM+i/BK,c=k+i%BK;a[i]=(r<M&&c<K)?A[r*K+c]:__float2bfloat16(0);}
 for(int i=tid;i<BK*BN;i+=128){int r=k+i/BN,c=blockIdx.x*BN+i%BN;b[(i/BN)*LDB+i%BN]=(r<K&&c<N)?B[r*N+c]:__float2bfloat16(0);}
 __syncthreads();
 #pragma unroll
 for(int j=0;j<SLOTS;j++){int tile=warp+4*j;if(tile<TM*TN){int r=tile/TN,c=tile%TN;
 #pragma unroll
 for(int kk=0;kk<BK;kk+=16){wmma::fragment<wmma::matrix_a,16,16,16,__nv_bfloat16,wmma::row_major> fa;wmma::fragment<wmma::matrix_b,16,16,16,__nv_bfloat16,wmma::row_major> fb;
 wmma::load_matrix_sync(fa,a+r*16*BK+kk,BK);wmma::load_matrix_sync(fb,b+kk*LDB+c*16,LDB);wmma::mma_sync(acc[j],fa,fb,acc[j]);}}}
 __syncthreads();}
 #pragma unroll
 for(int j=0;j<SLOTS;j++){int tile=warp+4*j;if(tile<TM*TN){int r=tile/TN,c=tile%TN;wmma::store_matrix_sync(result+warp*256,acc[j],16,wmma::mem_row_major);__syncwarp();for(int i=lane;i<256;i+=32){int rr=blockIdx.y*BM+r*16+i/16,cc=blockIdx.x*BN+c*16+i%16;if(rr<M&&cc<N)C[rr*N+cc]=result[warp*256+i];}__syncwarp();}}
}
__global__ void direct_gemm(const __nv_bfloat16* A,const __nv_bfloat16* B,float* C,int M,int N,int K){
 __shared__ __align__(32) float result[4*256];
 int tid=threadIdx.x,warp=tid/32,lane=tid%32;
 wmma::fragment<wmma::accumulator,16,16,16,float> acc[SLOTS];
 #pragma unroll
 for(int j=0;j<SLOTS;j++)wmma::fill_fragment(acc[j],0.f);
 for(int k=0;k<K;k+=BK){
 #pragma unroll
 for(int j=0;j<SLOTS;j++){int tile=warp+4*j;if(tile<TM*TN){int r=tile/TN,c=tile%TN;
 #pragma unroll
 for(int kk=0;kk<BK;kk+=16){wmma::fragment<wmma::matrix_a,16,16,16,__nv_bfloat16,wmma::row_major> fa;wmma::fragment<wmma::matrix_b,16,16,16,__nv_bfloat16,wmma::row_major> fb;
 wmma::load_matrix_sync(fa,A+(blockIdx.y*BM+r*16)*K+k+kk,K);wmma::load_matrix_sync(fb,B+(k+kk)*N+blockIdx.x*BN+c*16,N);wmma::mma_sync(acc[j],fa,fb,acc[j]);}}}
 }
 #pragma unroll
 for(int j=0;j<SLOTS;j++){int tile=warp+4*j;if(tile<TM*TN){int r=tile/TN,c=tile%TN;wmma::store_matrix_sync(result+warp*256,acc[j],16,wmma::mem_row_major);__syncwarp();for(int i=lane;i<256;i+=32){int rr=blockIdx.y*BM+r*16+i/16,cc=blockIdx.x*BN+c*16+i%16;if(rr<M&&cc<N)C[rr*N+cc]=result[warp*256+i];}__syncwarp();}}
}
struct Check{bool ok=true;double maxabs=0,maxscaled=0;int bad=0;};
Check check(float*dc,const std::vector<double>&reference){std::vector<float>out(reference.size());CK(cudaMemcpy(out.data(),dc,out.size()*4,cudaMemcpyDeviceToHost));Check q;for(size_t i=0;i<out.size();i++){double e=fabs(double(out[i])-reference[i]);double tol=0.002+0.0002*fabs(reference[i]);q.maxabs=std::max(q.maxabs,e);q.maxscaled=std::max(q.maxscaled,e/tol);if(!std::isfinite(out[i])||e>tol){q.ok=false;q.bad++;}}return q;}
std::vector<double> reference(const std::vector<__nv_bfloat16>&a,const std::vector<__nv_bfloat16>&b){std::vector<double>r(M*N);std::vector<double>af(a.size()),bf(b.size());for(size_t i=0;i<a.size();i++)af[i]=__bfloat162float(a[i]);for(size_t i=0;i<b.size();i++)bf[i]=__bfloat162float(b[i]);for(int i=0;i<M;i++)for(int k=0;k<K;k++){double v=af[i*K+k];for(int j=0;j<N;j++)r[i*N+j]+=v*bf[k*N+j];}return r;}
struct Times{std::vector<double>us;double median;};
Times timing(std::function<void(cudaStream_t)>fn,cudaStream_t stream){for(int i=0;i<1;i++)fn(stream);CK(cudaStreamSynchronize(stream));cudaGraph_t graph;cudaGraphExec_t exec;constexpr int reps=200;CK(cudaStreamBeginCapture(stream,cudaStreamCaptureModeGlobal));for(int i=0;i<reps;i++)fn(stream);CK(cudaStreamEndCapture(stream,&graph));CK(cudaGraphInstantiate(&exec,graph,0));cudaEvent_t a,b;CK(cudaEventCreate(&a));CK(cudaEventCreate(&b));for(int i=0;i<5;i++)CK(cudaGraphLaunch(exec,stream));CK(cudaStreamSynchronize(stream));Times t;for(int i=0;i<11;i++){CK(cudaEventRecord(a,stream));CK(cudaGraphLaunch(exec,stream));CK(cudaEventRecord(b,stream));CK(cudaEventSynchronize(b));float ms;CK(cudaEventElapsedTime(&ms,a,b));t.us.push_back(ms*1000/reps);}auto sorted=t.us;std::sort(sorted.begin(),sorted.end());t.median=sorted[sorted.size()/2];CK(cudaGraphExecDestroy(exec));CK(cudaGraphDestroy(graph));CK(cudaEventDestroy(a));CK(cudaEventDestroy(b));return t;}
void print_times(const char*name,int stride,const Times&t){printf("{\"kind\":\"timing\",\"name\":\"%s\",\"stride\":%d,\"median_us\":%.9g,\"samples_us\":[",name,stride,t.median);for(size_t i=0;i<t.us.size();i++)printf("%s%.9g",i?",":"",t.us[i]);printf("]}\n");}
int main(int argc,char**argv){int gpu=argc>1?atoi(argv[1]):7,selected=argc>2?atoi(argv[2]):0;CK(cudaSetDevice(gpu));cudaDeviceProp prop;CK(cudaGetDeviceProperties(&prop,gpu));cudaStream_t stream;CK(cudaStreamCreate(&stream));__nv_bfloat16 *da,*db;float*dc;CK(cudaMalloc(&da,2ull*M*K));CK(cudaMalloc(&db,2ull*K*N));CK(cudaMalloc(&dc,4ull*M*N));
 std::vector<__nv_bfloat16>a(M*K),b(K*N);std::vector<double>ref;
 auto custom=[&](int stride,cudaStream_t s){dim3 grid(N/32,M/32);if(stride==32)layout_gemm<32><<<grid,128,4096,s>>>(da,db,dc,M,N,K);else if(stride==48)layout_gemm<48><<<grid,128,5120,s>>>(da,db,dc,M,N,K);else if(stride==64)layout_gemm<64><<<grid,128,6144,s>>>(da,db,dc,M,N,K);else if(stride==0)direct_gemm<<<grid,128,0,s>>>(da,db,dc,M,N,K);else exit(5);CK(cudaGetLastError());};
 printf("{\"kind\":\"device\",\"gpu\":%d,\"name\":\"%s\",\"SMs\":%d,\"M\":%d,\"N\":%d,\"K\":%d,\"selected_stride\":%d,\"timing_mode\":\"warm CUDA graph200 independent alpha1 beta0 GEMMs;5 warm graphs;11 samples\"}\n",gpu,prop.name,prop.multiProcessorCount,M,N,K,selected);
 for(int seed=0;seed<2;seed++){uint32_t state=0x91e10da5+seed;auto value=[&](){state^=state<<13;state^=state>>17;state^=state<<5;return seed?float(int(state%20001)-10000)/8192.f:float(int(state%17)-8)/16.f;};for(auto&v:a)v=__float2bfloat16(value());for(auto&v:b)v=__float2bfloat16(value());ref=reference(a,b);CK(cudaMemcpy(da,a.data(),a.size()*2,cudaMemcpyHostToDevice));CK(cudaMemcpy(db,b.data(),b.size()*2,cudaMemcpyHostToDevice));for(int stride:{32,48,64,0}){custom(stride,stream);CK(cudaStreamSynchronize(stream));auto q=check(dc,ref);printf("{\"kind\":\"correctness\",\"seed\":%d,\"stride\":%d,\"checked\":%d,\"correct\":%s,\"max_abs_error\":%.9g,\"max_error_over_tolerance\":%.9g,\"bad\":%d}\n",seed,stride,M*N,q.ok?"true":"false",q.maxabs,q.maxscaled,q.bad);if(!q.ok)return 6;}}
 for(int stride:{32,48,64,0}){cudaFuncAttributes attrs;int resident;if(stride==0){CK(cudaFuncGetAttributes(&attrs,direct_gemm));CK(cudaOccupancyMaxActiveBlocksPerMultiprocessor(&resident,direct_gemm,128,0));}else if(stride==32){CK(cudaFuncGetAttributes(&attrs,layout_gemm<32>));CK(cudaOccupancyMaxActiveBlocksPerMultiprocessor(&resident,layout_gemm<32>,128,4096));}else if(stride==48){CK(cudaFuncGetAttributes(&attrs,layout_gemm<48>));CK(cudaOccupancyMaxActiveBlocksPerMultiprocessor(&resident,layout_gemm<48>,128,5120));}else{CK(cudaFuncGetAttributes(&attrs,layout_gemm<64>));CK(cudaOccupancyMaxActiveBlocksPerMultiprocessor(&resident,layout_gemm<64>,128,6144));}printf("{\"kind\":\"resources\",\"stride\":%d,\"registers_thread\":%d,\"static_shared\":%zu,\"local_bytes\":%zu,\"resident_ctas\":%d}\n",stride,attrs.numRegs,attrs.sharedSizeBytes,attrs.localSizeBytes,resident);}
 if(selected<0){printf("{\"kind\":\"prepared_correctness_only\"}\n");return 0;}
 // Custom choice is frozen externally; only original32 and that choice are timed.
 print_times("custom_direct_global",0,timing([&](cudaStream_t s){custom(0,s);},stream));return 0;}
