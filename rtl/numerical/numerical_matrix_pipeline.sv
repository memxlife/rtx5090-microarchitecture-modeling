// 16x16x16 BF16/FP32 operation-level model. Mode0 sequential reference;
// mode1 measured aligned-dot candidate, validated only in its scoped domain.
module numerical_matrix_pipeline #(
 parameter int SLOTS=2,LATENCY=17,INTERVAL=3,ARITHMETIC_MODE=0
)(
 input logic clk,rst,req_valid,output logic req_ready,
 input logic [31:0] req_id,
 input logic [15:0] a_words[256],b_words[256],
 input logic [31:0] accumulator_words[256],
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,result_words[256],output int outstanding
);
 import "DPI-C" function int unsigned reference_bf16_fma(
   input int unsigned a,b,c);
 import "DPI-C" function int unsigned reference_bf16_aligned_dot(
   input int unsigned a[],b[], input int unsigned c);
 int cycle,head,tail,next_accept,due[SLOTS];
 logic occupied[SLOTS];logic [31:0] ids[SLOTS],results[SLOTS][256];
 logic push,pop;
 assign req_ready=!rst&&outstanding<SLOTS&&cycle>=next_accept;
 assign rsp_valid=!rst&&outstanding>0&&cycle>=due[head];
 assign rsp_id=ids[head];
 assign push=req_valid&&req_ready;
 assign pop=rsp_valid&&rsp_ready;
 for(genvar i=0;i<256;i++) assign result_words[i]=results[head][i];
 initial if(SLOTS<1||LATENCY<1||INTERVAL<1||ARITHMETIC_MODE<0||ARITHMETIC_MODE>1) $fatal(1,"Invalid matrix pipeline configuration");
 always_ff @(posedge clk) begin
  if(rst) begin
   cycle<=0;head<=0;tail<=0;next_accept<=0;outstanding<=0;
   for(int s=0;s<SLOTS;s++) begin occupied[s]<=0;ids[s]<=0;due[s]<=0;end
  end else begin
   cycle<=cycle+1;
   if(push) begin
    for(int s=0;s<SLOTS;s++)
     if(occupied[s]&&ids[s]==req_id) $fatal(1,"Duplicate pending matrix identity");
    for(int m=0;m<16;m++) for(int n=0;n<16;n++) begin
     logic [31:0] sum;
     int unsigned dot_a[16],dot_b[16];
     sum=accumulator_words[m*16+n];
     for(int k=0;k<16;k++) begin
      dot_a[k]={16'b0,a_words[m*16+k]};dot_b[k]={16'b0,b_words[k*16+n]};
      if(ARITHMETIC_MODE==0) sum=reference_bf16_fma(dot_a[k],dot_b[k],sum);
     end
     if(ARITHMETIC_MODE==1)
      sum=reference_bf16_aligned_dot(dot_a,dot_b,accumulator_words[m*16+n]);
     results[tail][m*16+n]<=sum;
    end
    ids[tail]<=req_id;due[tail]<=cycle+LATENCY;occupied[tail]<=1;
    tail<=(tail+1)%SLOTS;next_accept<=cycle+INTERVAL;
   end
   if(pop) begin occupied[head]<=0;head<=(head+1)%SLOTS;end
   case({push,pop})
    2'b10:outstanding<=outstanding+1;
    2'b01:outstanding<=outstanding-1;
    default:outstanding<=outstanding;
   endcase
  end
 end
 // Results are evaluated at acceptance, then hidden until modeled completion.
 // FIFO service, no same-edge full replacement, no intrinsic timing claim.
endmodule
