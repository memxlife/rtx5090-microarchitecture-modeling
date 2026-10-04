`timescale 1ns/1ps
module resident_native_stage_tb #(parameter int READ_SLOTS=1);
 logic clk=0;always #0.05 clk=~clk;
 logic rst=1,write_valid=0,write_ready,write_warp_valid=0,write_warp_ready;
 logic[31:0]write_context=0,write_byte_address=0,write_warp_byte_addresses[32],write_warp_mask=0;
 logic[15:0]write_data=0,write_warp_halfwords[32];
 logic req_valid=0,req_ready,rsp_valid,rsp_ready=0;
 logic[31:0]req_context=0,req_id=0,rsp_context,rsp_id,c_registers[4][32][8],result_registers[4][32][8];
 logic[1:0]context_ready,context_initialized;logic operands_initialized,addresses_legal;
 logic[3:0]warp_drained[2],warp_memory_safe[2];
 logic native_issue_valid;logic[31:0]native_issue_context,native_issue_warp,native_issue_pc;
 logic stage_req_valid,stage_req_ready,stage_rsp_ready,admission_done_valid;
 int stage_req_context,admission_done_context,resident_blocks,resident_warps,allocated_register_words,allocated_shared_bytes;
 logic[31:0]stage_req_id,admission_done_id;
 int outstanding,cycle=0,counts[2][4],checked=0;bit overlap=0;
 logic[31:0]held[4][32][8];
 resident_native_stage_engine #(.ALLOW_WARP_WRITES(1),.READ_SLOTS(READ_SLOTS),.RETURN_DELAY(9),.MOVM_LATENCY(19),.HMMA_LATENCY(73))dut(.req_valid(stage_req_valid),.req_ready(stage_req_ready),.req_context(32'(stage_req_context)),.req_id(stage_req_id),.rsp_ready(stage_rsp_ready),.*);
 resident_stage_admission admission(.clk,.rst,.launch_valid(req_valid),.launch_ready(req_ready),.launch_id(req_id),
  .stage_req_valid,.stage_req_ready,.stage_req_context,.stage_req_id,
  .stage_rsp_valid(rsp_valid),.stage_rsp_ready,.stage_rsp_context(int'(rsp_context)),.stage_rsp_id(rsp_id),
  .done_valid(admission_done_valid),.done_ready(rsp_ready),.done_context(admission_done_context),.done_id(admission_done_id),
  .resident_blocks,.resident_warps,.allocated_register_words,.allocated_shared_bytes);
 function automatic logic[31:0] dyadic(input integer n,input integer f);
  integer m,t;begin
   if(n==0)return 0;m=n<0?-n:n;t=0;while((m>>(t+1))!=0)t++;
   if(t>23)$fatal(1,"Oracle outside exact FP32 domain");
   return(n<0?32'h80000000:0)|(32'(127+t-f)<<23)|(32'(m-(1<<t))<<(23-t));
  end
 endfunction
 function automatic integer avalue(input integer ctx,row,k);
  return ((row*1536+k+3*ctx)%17)-8;
 endfunction
 function automatic integer bvalue(input integer ctx,k,col);
  return ((k*2112+col+5*ctx)%13)-6;
 endfunction
 function automatic logic[31:0] expected(input integer ctx,warp_id,lane,e);
  integer i,r,c,sum;
  begin
   i=native_bf16_layout::c_element_index(lane,e);r=16*(warp_id/2)+i/16;c=16*(warp_id%2)+i%16;
   sum=64*((ctx+warp_id+lane+e)%7-3);
   for(int k=0;k<32;k++)sum+=avalue(ctx,r,k)*bvalue(ctx,k,c);
   return dyadic(sum,8);
  end
 endfunction

 always @(posedge clk)begin
  cycle<=cycle+1;if(cycle>200000)$fatal(1,"Resident stage timeout");
  if(rst)begin overlap=0;for(int c=0;c<2;c++)for(int w=0;w<4;w++)counts[c][w]=0;end
  else begin
   if(stage_req_valid&&stage_req_ready)begin
    if(allocated_register_words!=5120||allocated_shared_bytes!=9216)$fatal(1,"Incorrect per-request allocation demand");
    for(int w=0;w<4;w++)counts[stage_req_context][w]=0;
   end
   if(native_issue_valid)begin
    bit first_done,any0,any1;first_done=1;any0=0;any1=0;
    if(native_issue_context>=2||native_issue_warp>=4)$fatal(1,"Invalid resident trace identity");
    if(native_issue_pc!=32'h1350+32'(16*counts[native_issue_context][native_issue_warp]))$fatal(1,"Resident PC order mismatch");
    counts[native_issue_context][native_issue_warp]++;
    for(int w=0;w<4;w++)begin
     if(counts[0][w]!=40)first_done=0;if(counts[0][w]>0)any0=1;if(counts[1][w]>0)any1=1;
    end
    if(any0&&any1&&!first_done)overlap=1;
    $display("RESIDENT_ISSUE cycle=%0d context=%0d warp=%0d pc=%h",cycle,native_issue_context,native_issue_warp,native_issue_pc);
   end
   if(resident_blocks!=outstanding||resident_warps!=4*resident_blocks)$fatal(1,"Resident allocation/engine conservation failed");
   if(outstanding<0||outstanding>2)$fatal(1,"Resident outstanding bound violated");
  end
 end
 task automatic populate;
  begin for(int ctx=0;ctx<2;ctx++)begin
   write_context=32'(ctx);
   for(int packet=0;packet<64;packet++)begin
    for(int l=0;l<32;l++)begin
     integer h,n;logic[31:0]v;h=32*packet+l;
     n=h<1024?avalue(ctx,h/32,h%32):bvalue(ctx,(h-1024)/32,(h-1024)%32);
     v=dyadic(n,4);write_warp_byte_addresses[l]=32'(2*h);write_warp_halfwords[l]=v[31:16];
    end
    write_warp_mask='1;write_warp_valid=1;#0.001;while(!write_warp_ready)@(negedge clk);@(negedge clk);
   end
   write_warp_valid=0;
  end end
 endtask
 task automatic offer(input integer ctx,id);
  begin
   @(negedge clk);req_context=32'(ctx);req_id=32'(id);
   for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)c_registers[w][l][e]=dyadic((ctx+w+l+e)%7-3,2);
   while(!req_ready)@(negedge clk);if(stage_req_context!=ctx)$fatal(1,"Unexpected allocator context");req_valid=1;@(negedge clk);req_valid=0;
   for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)c_registers[w][l][e]=32'hdeadbeef;
  end
 endtask
 task automatic check_response(input integer ctx,id);
  begin
   if(!rsp_valid||rsp_context!=ctx||rsp_id!=id)$fatal(1,"Resident response identity mismatch");
   for(int w=0;w<4;w++)begin
    if(counts[ctx][w]!=40)$fatal(1,"Resident incomplete issue sequence");
    for(int l=0;l<32;l++)for(int e=0;e<8;e++)begin
     if(result_registers[w][l][e]!==expected(ctx,w,l,e))$fatal(1,"Resident numerical cross-context mismatch");
     held[w][l][e]=result_registers[w][l][e];checked++;
    end
   end
  end
 endtask
 task automatic held_check(input integer ctx,id);
  begin
   if(!rsp_valid||rsp_context!=ctx||rsp_id!=id||resident_blocks<1)$fatal(1,"Held resident identity/allocation changed");
   for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)if(result_registers[w][l][e]!==held[w][l][e])$fatal(1,"Held resident payload changed");
  end
 endtask
 task automatic acknowledge;
  begin @(negedge clk);rsp_ready=1;@(negedge clk);rsp_ready=0;end
 endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;populate();offer(0,10);wait(native_issue_valid);@(negedge clk);rst=1;repeat(2)@(negedge clk);rst=0;
  if(rsp_valid||outstanding||context_initialized)$fatal(1,"Resident reset failed");populate();
  // Simultaneously resident batches must share services and interleave execution.
  offer(0,20);offer(1,21);wait(rsp_valid);@(posedge clk);#0.001;@(negedge clk);
  begin integer owner;owner=int'(rsp_context);check_response(owner,20+owner);
   repeat(4)begin @(negedge clk);held_check(owner,20+owner);end
   if(!overlap||resident_blocks!=2||resident_warps!=8)$fatal(1,"Resident contexts did not interleave/retain allocations");acknowledge();
   if(resident_blocks!=1||resident_warps!=4)$fatal(1,"Retiring one context affected the other");
   wait(rsp_valid);@(posedge clk);#0.001;@(negedge clk);check_response(1-owner,21-owner);acknowledge();
  end
  // Start the second context only after the first response is deliberately held.
  offer(0,30);wait(rsp_valid);@(posedge clk);#0.001;@(negedge clk);check_response(0,30);offer(1,31);
  while(warp_drained[1]!=4'b1111)begin @(negedge clk);held_check(0,30);end
  $display("RESIDENT_HELD_PROGRESS context=1 while_context0_response_held=1");acknowledge();
  wait(rsp_valid);@(posedge clk);#0.001;@(negedge clk);check_response(1,31);acknowledge();
  repeat(3)@(negedge clk);if(outstanding||resident_blocks||resident_warps)$fatal(1,"Resident retirement did not release resources");
  $display("RESIDENT_STAGE_PASS checked_words=%0d read_slots=%0d",checked,READ_SLOTS);$finish;
 end
endmodule
