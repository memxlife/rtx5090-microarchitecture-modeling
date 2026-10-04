`timescale 1ns/1ps
module native_multiwarp_stage_tb #(parameter int READ_SLOTS=1);
 logic clk=0;always #0.05 clk=~clk;
 logic rst=1,write_valid=0,write_ready,write_warp_valid=0,write_warp_ready;
 logic[31:0]write_byte_address=0,write_warp_byte_addresses[32],write_warp_mask=0;
 logic[15:0]write_data=0,write_warp_halfwords[32];
 logic req_valid=0,req_ready,rsp_valid,rsp_ready=0;
 logic[31:0]req_id=11,rsp_id,c_registers[4][32][8],result_registers[4][32][8];
 logic operands_initialized,addresses_legal,native_issue_valid;logic[31:0]native_issue_warp,native_issue_pc;
 logic[3:0]warp_drained,warp_memory_safe;
 int drain_cycle[4],memory_safe_cycle[4];
 int outstanding,cycle=0,counts[4],first_issue[4],last_issue[4],checked=0;
 bit observed_overlap=0;logic[31:0]held_results[4][32][8];
 native_multiwarp_stage_pipeline #(.ALLOW_WARP_WRITES(1),.READ_SLOTS(READ_SLOTS),.RETURN_DELAY(9),.MOVM_LATENCY(19),.HMMA_LATENCY(73))dut(.*);
 function automatic logic[31:0]dyadic(input integer n,input integer f);
  integer m,t;begin
   if(n==0)return 0;m=n<0?-n:n;t=0;while((m>>(t+1))!=0)t++;
   if(t>23)$fatal(1,"Oracle outside exact domain");
   return(n<0?32'h80000000:0)|(32'(127+t-f)<<23)|(32'(m-(1<<t))<<(23-t));
  end
 endfunction
 always @(posedge clk)begin
  cycle<=cycle+1;if(cycle>100000)$fatal(1,"Multiwarp stage timeout");
  if(rst)begin observed_overlap=0;for(int w=0;w<4;w++)begin counts[w]=0;first_issue[w]=-1;last_issue[w]=-1;drain_cycle[w]=-1;memory_safe_cycle[w]=-1;end end
  else begin
   if(req_valid&&req_ready)begin observed_overlap=0;for(int w=0;w<4;w++)begin counts[w]=0;first_issue[w]=-1;last_issue[w]=-1;drain_cycle[w]=-1;memory_safe_cycle[w]=-1;end end
   for(int w=0;w<4;w++)if(warp_memory_safe[w]&&outstanding&&!(req_valid&&req_ready))begin
    if(dut.read_live_perwarp[w]!=0||dut.cooldown[w]!=0||counts[w]!=40)$fatal(1,"Early warp memory-safe signal");
    if(memory_safe_cycle[w]<0)memory_safe_cycle[w]=cycle;
   end
   for(int w=0;w<4;w++)if(warp_drained[w]&&outstanding&&!(req_valid&&req_ready))begin
    if(dut.warp_service_live[w]!=0||dut.busy_read[w]!=0||dut.busy_write[w]!=0||dut.cooldown[w]!=0||counts[w]!=40)$fatal(1,"Early warp-drained signal");
    if(drain_cycle[w]<0)drain_cycle[w]=cycle;
   end
   if(rsp_valid&&warp_drained!=4'b1111)$fatal(1,"Batch response before all warps drained");
   if(native_issue_valid)begin
    integer active,completed;active=0;completed=0;
    if(native_issue_warp>=4)$fatal(1,"Invalid issuing warp");
    if(native_issue_pc!=32'h1350+32'(16*counts[native_issue_warp]))$fatal(1,"Warp PC sequence mismatch");
    if(first_issue[native_issue_warp]<0)first_issue[native_issue_warp]=cycle;
    last_issue[native_issue_warp]=cycle;counts[native_issue_warp]++;
    for(int w=0;w<4;w++)begin if(counts[w]>0)active++;if(counts[w]==40)completed++;end
    if(active>=2&&completed==0)observed_overlap=1;
    $display("MULTIWARP_ISSUE cycle=%0d warp=%0d pc=%h",cycle,native_issue_warp,native_issue_pc);
   end
  end
 end
 task automatic populate;
  begin
   for(int packet=0;packet<64;packet++)begin
    for(int lane=0;lane<32;lane++)begin
     integer h,r,k,c,n;logic[31:0]v;h=32*packet+lane;
     if(h<1024)begin r=h/32;k=h%32;n=(r*1536+k)%17-8;end
     else begin k=(h-1024)/32;c=(h-1024)%32;n=(k*2112+c)%13-6;end
     v=dyadic(n,4);write_warp_byte_addresses[lane]=32'(2*h);write_warp_halfwords[lane]=v[31:16];
    end
    write_warp_mask='1;write_warp_valid=1;#0.001;
    while(!write_warp_ready)@(negedge clk);
    @(negedge clk);
   end
   write_warp_valid=0;
  end
 endtask
 task automatic verify;
  begin
   if(rsp_id!=req_id||!observed_overlap)$fatal(1,"Batch identity/overlap failure");
   for(int w=0;w<4;w++)begin
    if(counts[w]!=40||first_issue[w]<0||last_issue[w]-first_issue[w]>20000)$fatal(1,"Warp progress/fairness failure");
    if(memory_safe_cycle[w]<0||memory_safe_cycle[w]>drain_cycle[w])$fatal(1,"Memory safety follows full drain");
    $display("MULTIWARP_MEMORY_SAFE warp=%0d cycle=%0d drained_cycle=%0d earlier=%0d",w,memory_safe_cycle[w],drain_cycle[w],memory_safe_cycle[w]<drain_cycle[w]);
    $display("MULTIWARP_DRAIN warp=%0d cycle=%0d",w,drain_cycle[w]);
    $display("MULTIWARP_WINDOW warp=%0d first=%0d last=%0d instructions=%0d",w,first_issue[w],last_issue[w],counts[w]);
    for(int lane=0;lane<32;lane++)for(int e=0;e<8;e++)begin
     integer i,r,c,sum;logic[31:0]want;i=native_bf16_layout::c_element_index(lane,e);
     r=16*(w/2)+i/16;c=16*(w%2)+i%16;sum=0;
     for(int k=0;k<32;k++)sum+=((r*1536+k)%17-8)*((k*2112+c)%13-6);
     sum+=64*((w+lane+e)%7-3);want=dyadic(sum,8);
     if(result_registers[w][lane][e]!==want)$fatal(1,"Multiwarp numeric mismatch warp%0d lane%0d element%0d",w,lane,e);
     held_results[w][lane][e]=result_registers[w][lane][e];checked++;
    end
   end
  end
 endtask
 task automatic offer;
  begin @(negedge clk);while(!req_ready)@(negedge clk);req_valid=1;@(negedge clk);req_valid=0;end
 endtask
 initial begin
  for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)c_registers[w][l][e]=dyadic((w+l+e)%7-3,2);
  repeat(3)@(negedge clk);rst=0;populate();offer();
  wait(native_issue_valid);repeat(3)@(negedge clk);rst=1;repeat(2)@(negedge clk);rst=0;
  if(rsp_valid||outstanding)$fatal(1,"Reset failed to cancel batch");populate();
  for(int replay=0;replay<2;replay++)begin
   req_id=32'(21+replay);offer();wait(rsp_valid);@(posedge clk);#0.001;@(negedge clk);verify();
   repeat(4)begin @(negedge clk);
    if(!rsp_valid||rsp_id!=req_id)$fatal(1,"Held batch response identity changed");
    for(int w=0;w<4;w++)for(int l=0;l<32;l++)for(int e=0;e<8;e++)if(result_registers[w][l][e]!==held_results[w][l][e])$fatal(1,"Held result payload changed");
   end
   rsp_ready=1;@(negedge clk);rsp_ready=0;
  end
  $display("MULTIWARP_STAGE_PASS checked_words=%0d read_slots=%0d",checked,READ_SLOTS);$finish;
 end
endmodule
