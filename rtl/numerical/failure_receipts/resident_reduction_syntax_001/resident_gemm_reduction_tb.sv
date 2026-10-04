`timescale 1ns/1ps
module resident_gemm_reduction_tb #(parameter int K=64);
 logic clk=0;always #0.05 clk=~clk;logic rst=1,launch_valid=0,launch_ready,done_valid,done_ready=0;
 logic[31:0]launch_id=0,a_base=0,b_base=32'h100000,cta_row=0,cta_col=0,done_id,done_context,result_registers[4][32][8];
 logic backing_req_valid,backing_req_ready,backing_rsp_valid=0,backing_rsp_ready;
 logic[31:0]backing_req_id,backing_req_byte_address,backing_rsp_id;logic[255:0]backing_rsp_data;
 int resident_blocks,resident_warps,cycle=0,delay_left=0,checked=0;bit pending=0;
 logic[31:0]pending_id,pending_address;logic native_issue_valid;logic[31:0]native_issue_context,native_issue_warp,native_issue_pc;
 int issues[2],commits[2],stage_commits[2][K/32];bit staged_seen[2][K/32][2048];logic[31:0]held[4][32][8];
 resident_gemm_reduction #(.K(K),.READ_SLOTS(2),.RETURN_DELAY(9),.MOVM_LATENCY(19),.HMMA_LATENCY(73))dut(.*);
 assign backing_req_ready=!rst&&!pending&&!backing_rsp_valid&&(cycle%4!=0);
 function automatic logic[31:0] dyadic(input integer n,input integer f);
  integer m,t;begin if(n==0)return 0;m=n<0?-n:n;t=0;while((m>>(t+1))!=0)t++;if(t>23)$fatal(1,"Oracle exact domain");return(n<0?32'h80000000:0)|(32'(127+t-f)<<23)|(32'(m-(1<<t))<<(23-t));end
 endfunction
 function automatic logic[15:0] memory_value(input logic[31:0]address);
  integer index,n;logic[31:0]v;
  begin if(address<32'h100000)begin index=int'(address)/2;if(index>=64*K)$fatal(1,"A bounds");n=index%17-8;end
   else begin index=int'(address-32'h100000)/2;if(index>=K*96)$fatal(1,"B bounds");n=index%13-6;end
   v=dyadic(n,4);return v[31:16];end
 endfunction
 function automatic logic[31:0] expected(input integer ctx,w,l,e);
  integer i,row,col,sum;
  begin i=native_bf16_layout::c_element_index(l,e);row=32*ctx+16*(w/2)+i/16;col=32*ctx+16*(w%2)+i%16;sum=0;
   for(int k=0;k<K;k++)sum+=((row*K+k)%17-8)*((k*96+col)%13-6);return dyadic(sum,8);end
 endfunction
 always @(posedge clk)begin
  cycle<=cycle+1;if(cycle>3000000)$fatal(1,"Reduction timeout");
  if(rst)begin pending<=0;backing_rsp_valid<=0;delay_left<=0;for(int c=0;c<2;c++)begin issues[c]=0;commits[c]=0;for(int st=0;st<K/32;st++)begin stage_commits[c][st]=0;for(int h=0;h<2048;h++)staged_seen[c][st][h]=0;endend end
  else begin
   if(backing_req_valid&&backing_req_ready)begin pending<=1;pending_id<=backing_req_id;pending_address<=backing_req_byte_address;delay_left<=5;if(backing_req_byte_address[4:0])$fatal(1,"Sector alignment");end
   if(pending)if(delay_left>0)delay_left<=delay_left-1;else begin pending<=0;backing_rsp_valid<=1;backing_rsp_id<=pending_id;for(int h=0;h<16;h++)backing_rsp_data[16*h+:16]<=memory_value(pending_address+32'(2*h));end
   if(backing_rsp_valid&&backing_rsp_ready)backing_rsp_valid<=0;
   if(dut.write_warp_valid&&dut.write_warp_ready)begin
    int ctx,st;ctx=int'(dut.write_context);st=dut.stage_number[ctx];
    if(ctx>=2||st>=K/32||dut.write_warp_mask!='1)$fatal(1,"Staging identity/mask");
    for(int l=0;l<32;l++)begin
     int h,row,col,k,n;logic[31:0]v;h=int'(dut.write_warp_byte_addresses[l])/2;
     if(h>=2048||dut.write_warp_byte_addresses[l][0]||staged_seen[ctx][st][h])$fatal(1,"Duplicate staging destination");
     if(h<1024)begin row=32*ctx+h/32;k=32*st+h%32;n=(row*K+k)%17-8;end
     else begin k=32*st+(h-1024)/32;col=32*ctx+(h-1024)%32;n=(k*96+col)%13-6;end
     v=dyadic(n,4);if(dut.write_warp_halfwords[l]!==v[31:16])$fatal(1,"Actual staging value mismatch");
     staged_seen[ctx][st][h]=1;stage_commits[ctx][st]++;commits[ctx]++;
    end
   end
   if(dut.compute_valid&&dut.compute_ready&&stage_commits[dut.compute_context][dut.stage_number[dut.compute_context]]!=2048)$fatal(1,"Compute before2048 actual commits");
   if(native_issue_valid)begin if(native_issue_context>=2)$fatal(1,"Trace context");issues[native_issue_context]++;end
   if(resident_blocks<0||resident_blocks>2||resident_warps!=4*resident_blocks)$fatal(1,"Resource conservation");
  end
 end
 task automatic offer(input integer ctx,id);
  begin @(negedge clk);launch_id=32'(id);cta_row=32'(ctx);cta_col=32'(ctx);a_base=0;b_base=32'h100000;launch_valid=1;#0.001;while(!launch_ready)@(negedge clk);@(negedge clk);launch_valid=0;cta_row=99;cta_col=99;a_base=32'hdead0000;b_base=32'hdead8000;end
 endtask
 task automatic inspect;
  begin
   if(done_context>=2||done_id!=20+done_context)$fatal(1,"Final identity");
   if(commits[done_context]!=2048*(K/32))$fatal(1,"Missing shared stage words");
   if(issues[done_context]!=160*(K/32))$fatal(1,"Missing native operations");
   for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)begin
    if(result_registers[w][l][e]!==expected(int'(done_context),w,l,e))$fatal(1,"Whole K result mismatch ctx%0d w%0d l%0d e%0d",done_context,w,l,e);
    held[w][l][e]=result_registers[w][l][e];checked++;
   end
  end
 endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;offer(0,10);wait(pending);@(negedge clk);rst=1;repeat(2)@(negedge clk);if(pending||backing_rsp_valid||resident_blocks)$fatal(1,"Reset flush");rst=0;
  offer(0,20);offer(1,21);wait(done_valid);@(negedge clk);inspect();
  begin logic[31:0]first,first_id;first=done_context;first_id=done_id;
   repeat(5000)begin @(negedge clk);
    if(!done_valid||done_context!=first||done_id!=first_id||resident_blocks!=2)$fatal(1,"Held final identity/allocation");
    for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)if(result_registers[w][l][e]!==held[w][l][e])$fatal(1,"Held final data");
   end
   if(issues[1-first]==0)$fatal(1,"Other context no progress");done_ready=1;@(negedge clk);done_ready=0;
   if(resident_blocks!=1||resident_warps!=4)$fatal(1,"Premature other retirement");
   wait(done_valid);@(negedge clk);if(done_context==first)$fatal(1,"Duplicate final");inspect();done_ready=1;@(negedge clk);done_ready=0;
  end
  repeat(3)@(negedge clk);if(resident_blocks||resident_warps||checked!=2048)$fatal(1,"Final resource/value conservation");
  $display("RESIDENT_REDUCTION_PASS K=%0d checked_words=%0d",K,checked);$finish;
 end
endmodule
