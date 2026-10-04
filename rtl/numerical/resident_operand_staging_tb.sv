`timescale 1ns/1ps
module resident_operand_staging_tb;
 logic clk=0;always #0.05 clk=~clk;logic rst=1;
 logic req_valid=0,req_ready;logic[31:0]req_context=0,req_id=0,a_base=0,b_base=32'h10000,cta_row=0,cta_col=0,stage_index=0;
 logic[1:0]context_ready;int outstanding;
 logic write_warp_valid,write_warp_ready;logic[31:0]write_context,write_warp_byte_addresses[32],write_warp_mask;
 logic[15:0]write_warp_halfwords[32];
 logic done_valid,done_ready=0;logic[31:0]done_context,done_id;
 logic backing_req_valid,backing_req_ready,backing_rsp_valid=0,backing_rsp_ready;
 logic[31:0]backing_req_id,backing_req_byte_address,backing_rsp_id;logic[255:0]backing_rsp_data;
 int cycle=0,delay_left=0,commits[2],checked=0;bit pending=0;logic[31:0]pending_id,pending_address;
 bit seen[2][2048];logic held_packet=0;logic[31:0]held_addresses[32],held_ctx,held_mask;logic[15:0]held_values[32];
 resident_operand_staging dut(.*);
 assign write_warp_ready=!rst&&(cycle%5==0);
 assign backing_req_ready=!rst&&!pending&&!backing_rsp_valid&&(cycle%3!=0);
 function automatic integer numerator(input integer ctx,h);
  integer row,col,k;
  begin
   if(h<1024)begin row=32*ctx+h/32;k=32*ctx+h%32;return((row*64+k)%17)-8;end
   else begin k=32*ctx+(h-1024)/32;col=32*ctx+(h-1024)%32;return((k*96+col)%13)-6;end
  end
 endfunction
 function automatic logic[15:0] bf(input integer n);
  integer m,t;begin if(n==0)return 0;m=n<0?-n:n;t=0;while((m>>(t+1))!=0)t++;return(n<0?16'h8000:0)|(16'(127+t-4)<<7)|(16'(m-(1<<t))<<(7-t));end
 endfunction
 function automatic logic[15:0] memory_value(input logic[31:0]address);
  integer index,n;
  begin
   if(address<32'h10000)begin index=int'(address)/2;if(index>=4096)$fatal(1,"A address outside allocation");n=(index%17)-8;end
   else begin index=int'(address-32'h10000)/2;if(index>=6144)$fatal(1,"B address outside allocation");n=(index%13)-6;end
   return bf(n);
  end
 endfunction
 always @(posedge clk)begin
  cycle<=cycle+1;if(cycle>200000)$fatal(1,"Resident staging timeout");
  if(rst)begin pending<=0;backing_rsp_valid<=0;delay_left<=0;held_packet<=0;for(int c=0;c<2;c++)begin commits[c]=0;for(int h=0;h<2048;h++)seen[c][h]=0;end end
  else begin
   if(backing_req_valid&&backing_req_ready)begin pending<=1;pending_id<=backing_req_id;pending_address<=backing_req_byte_address;delay_left<=5;if(backing_req_byte_address[4:0])$fatal(1,"Unaligned backing sector");end
   if(pending)if(delay_left>0)delay_left<=delay_left-1;else begin
    pending<=0;backing_rsp_valid<=1;backing_rsp_id<=pending_id;for(int h=0;h<16;h++)backing_rsp_data[h*16+:16]<=memory_value(pending_address+32'(2*h));
   end
   if(backing_rsp_valid&&backing_rsp_ready)backing_rsp_valid<=0;
   if(held_packet)begin
    if(!write_warp_valid||write_context!=held_ctx||write_warp_mask!=held_mask)$fatal(1,"Held shared packet identity changed");
    for(int l=0;l<32;l++)if(write_warp_byte_addresses[l]!=held_addresses[l]||write_warp_halfwords[l]!=held_values[l])$fatal(1,"Held shared packet changed");
   end
   held_packet<=write_warp_valid&&!write_warp_ready;
   if(write_warp_valid&&!write_warp_ready)begin held_ctx<=write_context;held_mask<=write_warp_mask;for(int l=0;l<32;l++)begin held_addresses[l]<=write_warp_byte_addresses[l];held_values[l]<=write_warp_halfwords[l];end end
   if(write_warp_valid&&write_warp_ready)begin
    if(write_context>=2||write_warp_mask!='1)$fatal(1,"Shared commit contract mismatch");
    for(int l=0;l<32;l++)begin
     integer h;h=int'(write_warp_byte_addresses[l])/2;
     if(write_warp_byte_addresses[l][0]||h>=2048||seen[write_context][h])$fatal(1,"Duplicate/invalid shared destination");
     if(write_warp_halfwords[l]!==bf(numerator(int'(write_context),h)))$fatal(1,"Staged global value mismatch ctx%0d half%0d",write_context,h);
     seen[write_context][h]=1;commits[write_context]++;checked++;
    end
   end
   if(done_valid&&commits[done_context]!=2048)$fatal(1,"Done before all actual shared commits");
   if(outstanding<0||outstanding>2)$fatal(1,"Outstanding context bound");
  end
 end
 task automatic offer(input integer ctx,id);
  begin @(negedge clk);req_context=32'(ctx);req_id=32'(id);cta_row=32'(ctx);cta_col=32'(ctx);stage_index=32'(ctx);req_valid=1;#0.001;while(!req_ready)@(negedge clk);@(negedge clk);req_valid=0;cta_row=99;cta_col=99;stage_index=99;a_base=32'hdead0000;b_base=32'hdead8000;end
 endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;offer(0,10);wait(pending);@(negedge clk);rst=1;repeat(2)@(negedge clk);if(outstanding||pending||backing_rsp_valid)$fatal(1,"Reset cancellation failed");rst=0;checked=0;
  a_base=0;b_base=32'h10000;offer(0,20);a_base=0;b_base=32'h10000;offer(1,21);
  wait(done_valid);@(negedge clk);
  begin integer first;logic[31:0]first_id;first=int'(done_context);first_id=done_id;
   repeat(1500)begin @(negedge clk);if(!done_valid||done_context!=first||done_id!=first_id)$fatal(1,"Held done identity changed");end
   if(commits[0]!=2048||commits[1]!=2048||outstanding!=2)$fatal(1,"Held done blocked other staging");
   done_ready=1;@(negedge clk);done_ready=0;wait(done_valid);@(negedge clk);if(done_context==first)$fatal(1,"Repeated done context");done_ready=1;@(negedge clk);done_ready=0;
  end
  repeat(3)@(negedge clk);if(outstanding||checked!=4096)$fatal(1,"Final staging conservation mismatch");
  $display("RESIDENT_STAGING_PASS checked_halfwords=%0d",checked);$finish;
 end
endmodule
