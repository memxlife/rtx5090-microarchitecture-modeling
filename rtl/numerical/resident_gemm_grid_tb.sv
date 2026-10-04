`timescale 1ns/1ps
module resident_gemm_grid_tb #(parameter int K=64);
 logic clk=0;always #0.05 clk=~clk;logic rst=1,launch_valid=0,launch_ready,done_valid,done_ready=0;
 logic[31:0]launch_id=0,a_base=0,b_base=32'h100000,c_base=32'h200000,done_id;
 logic backing_req_valid,backing_req_ready,backing_rsp_valid=0,backing_rsp_ready;
 logic[31:0]backing_req_id,backing_req_byte_address,backing_rsp_id;logic[255:0]backing_rsp_data;
 logic[63:0]elapsed_cycles;longint unsigned expected_elapsed=0;bit elapsed_active=0;
 int dispatched_blocks,completed_blocks;logic block_launch_valid,block_done_valid;
 logic[31:0]block_launch_ordinal,block_launch_row,block_launch_col,block_done_ordinal,block_done_row,block_done_col;
 bit dispatched_seen[6];int dispatches=0,grid_launches=0,peak_resident=0;
 int resident_blocks,resident_warps,cycle=0,delay_left=0,checked=0;bit pending=0;
 logic[31:0]pending_id,pending_address;logic native_issue_valid;logic[31:0]native_issue_context,native_issue_warp,native_issue_pc;
 int issues[2];
 logic store_backing_req_valid,store_backing_req_ready,store_backing_rsp_valid,store_backing_rsp_ready;
 logic[31:0]store_backing_req_id,store_backing_req_byte_address,store_backing_rsp_id;
 logic[255:0]store_backing_req_data;logic[7:0]store_backing_req_word_mask;
 bit store_pending=0,store_held=0,seen[6144],done_seen[6];int store_wait=0,stores=0,acks=0,block_acks[6],completed=0;
 logic[31:0]saved_store_id,held_store_id,held_store_address;logic[255:0]held_store_data;logic[7:0]held_store_mask;int pending_block,pending_words;
 assign store_backing_req_ready=!rst&&!store_pending&&(cycle%5==0);
 assign store_backing_rsp_valid=!rst&&store_pending&&store_wait==0;
 assign store_backing_rsp_id=saved_store_id;
 function automatic logic[31:0] output_expected(input integer row,col);
  integer sum;begin sum=0;for(int k=0;k<K;k++)sum+=((row*K+k)%17-8)*((k*96+col)%13-6);return dyadic(sum,8);end
 endfunction
 always @(posedge clk)begin
  if(rst)begin store_pending<=0;store_held<=0;stores=0;acks=0;completed=0;for(int b=0;b<6;b++)begin block_acks[b]=0;done_seen[b]=0;end for(int i=0;i<6144;i++)seen[i]=0;end
  else begin
   if(store_held)begin
    if(!store_backing_req_valid||store_backing_req_id!=held_store_id||store_backing_req_byte_address!=held_store_address||store_backing_req_data!==held_store_data||store_backing_req_word_mask!=held_store_mask)$fatal(1,"Held output packet changed");
   end
   store_held<=store_backing_req_valid&&!store_backing_req_ready;
   if(store_backing_req_valid&&!store_backing_req_ready)begin held_store_id<=store_backing_req_id;held_store_address<=store_backing_req_byte_address;held_store_data<=store_backing_req_data;held_store_mask<=store_backing_req_word_mask;end
   if(store_pending&&store_wait>0)store_wait<=store_wait-1;
   if(store_backing_rsp_valid&&store_backing_rsp_ready)begin store_pending<=0;acks+=pending_words;block_acks[pending_block]+=pending_words;end
   if(store_backing_req_valid&&store_backing_req_ready)begin
    int words,owner;words=0;owner=-1;
    if(store_backing_req_byte_address[4:0]||!store_backing_req_word_mask)$fatal(1,"Output sector contract");
    for(int w=0;w<8;w++)if(store_backing_req_word_mask[w])begin
     int index,row,col,block_id;index=int'(store_backing_req_byte_address+32'(4*w)-32'h200000)/4;row=index/96;col=index%96;block_id=3*(row/32)+col/32;
     if(index<0||index>=6144||seen[index])$fatal(1,"Output coverage/address mismatch");
     if(store_backing_req_data[32*w+:32]!==output_expected(row,col))$fatal(1,"Global output numerical mismatch");
     if(owner>=0&&owner!=block_id)$fatal(1,"Packet crosses block");owner=block_id;seen[index]=1;words++;stores++;
    end
    pending_block=owner;pending_words=words;saved_store_id<=store_backing_req_id;store_wait<=11;store_pending<=1;
   end
   if(block_launch_valid)begin
    int b;b=int'(block_launch_ordinal);
    if(b<0||b>=6||dispatched_seen[b]||block_launch_row!=b/3||block_launch_col!=b%3)$fatal(1,"Grid dispatch coordinate/identity");
    dispatched_seen[b]=1;dispatches++;
   end
   if(block_done_valid)begin
    int b;b=int'(block_done_ordinal);
    if(b<0||b>=6||!dispatched_seen[b]||done_seen[b]||block_done_row!=b/3||block_done_col!=b%3||block_acks[b]!=1024)$fatal(1,"Block completion before own acknowledgments");
    done_seen[b]=1;completed++;
   end
   if(resident_blocks>peak_resident)peak_resident=resident_blocks;
   if(done_valid&&(acks!=6144||completed!=6||dispatched_blocks!=6||completed_blocks!=6||resident_blocks!=0))$fatal(1,"Grid done before all output acks and retirement");
  end
 end
 resident_gemm_grid #(.K(K),.READ_SLOTS(2),.RETURN_DELAY(9),.MOVM_LATENCY(19),.HMMA_LATENCY(73))dut(.*);
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
  if(rst)begin expected_elapsed<=0;elapsed_active<=0;end
  else if(launch_valid&&launch_ready)begin expected_elapsed<=0;elapsed_active<=1;end
  else if(elapsed_active)begin
   if(done_valid)begin if(elapsed_cycles!=expected_elapsed)$fatal(1,"Modeled elapsed-cycle mismatch actual%0d expected%0d",elapsed_cycles,expected_elapsed);elapsed_active<=0;end
   else expected_elapsed<=expected_elapsed+1;
  end
 end
 always @(posedge clk)begin
  cycle<=cycle+1;if(cycle>3000000)$fatal(1,"Reduction timeout");
  if(rst)begin pending<=0;backing_rsp_valid<=0;delay_left<=0;for(int c=0;c<2;c++)begin issues[c]=0; end end
  else begin
   if(backing_req_valid&&backing_req_ready)begin pending<=1;pending_id<=backing_req_id;pending_address<=backing_req_byte_address;delay_left<=5;if(backing_req_byte_address[4:0])$fatal(1,"Sector alignment");end
   if(pending)if(delay_left>0)delay_left<=delay_left-1;else begin pending<=0;backing_rsp_valid<=1;backing_rsp_id<=pending_id;for(int h=0;h<16;h++)backing_rsp_data[16*h+:16]<=memory_value(pending_address+32'(2*h));end
   if(backing_rsp_valid&&backing_rsp_ready)backing_rsp_valid<=0;
   if(native_issue_valid)begin if(native_issue_context>=2)$fatal(1,"Trace context");issues[native_issue_context]++;end
   if(resident_blocks<0||resident_blocks>2||resident_warps!=4*resident_blocks)$fatal(1,"Resource conservation");
  end
 end
 task automatic clear_scoreboard;
  begin
   stores=0;acks=0;completed=0;dispatches=0;peak_resident=0;
   for(int b=0;b<6;b++)begin block_acks[b]=0;done_seen[b]=0;dispatched_seen[b]=0;end
   for(int i=0;i<6144;i++)seen[i]=0;
  end
 endtask
 task automatic offer(input integer id);
  begin @(negedge clk);launch_id=32'(id);a_base=0;b_base=32'h100000;c_base=32'h200000;launch_valid=1;#0.001;while(!launch_ready)@(negedge clk);@(negedge clk);launch_valid=0;a_base=32'hdead0000;b_base=32'hdead8000;c_base=32'hdeadf000;end
 endtask
 initial begin
  repeat(3)@(negedge clk);rst=0;
  if($test$plusargs("misaligned_c")||$test$plusargs("c_overlap_a")||$test$plusargs("c_overlap_b")||$test$plusargs("c_overflow"))begin
   @(negedge clk);a_base=0;b_base=32'h100000;c_base=32'h200000;
   if($test$plusargs("misaligned_c"))c_base=32'h200002;
   if($test$plusargs("c_overlap_a"))c_base=0;
   if($test$plusargs("c_overlap_b"))c_base=32'h100000;
   if($test$plusargs("c_overflow"))c_base=32'hfffffffc;
   launch_valid=1;repeat(3)@(negedge clk);$fatal(1,"Invalid grid C launch was not rejected");
  end
  clear_scoreboard();offer(10);wait(pending);@(negedge clk);rst=1;repeat(2)@(negedge clk);
  if(pending||backing_rsp_valid||resident_blocks)$fatal(1,"Reset flush");rst=0;
  for(int replay=0;replay<2;replay++)begin
   clear_scoreboard();offer(20+replay);wait(done_valid);@(negedge clk);
   if(done_id!=20+replay||stores!=6144||acks!=6144||dispatches!=6||completed!=6||peak_resident!=2)$fatal(1,"Final grid identity/coverage/allocation");
   for(int i=0;i<6144;i++)if(!seen[i])$fatal(1,"Output hole");
   repeat(5)begin @(negedge clk);if(!done_valid||done_id!=20+replay||resident_blocks||elapsed_cycles!=expected_elapsed)$fatal(1,"Held grid completion");end
   done_ready=1;@(negedge clk);done_ready=0;grid_launches++;
   $display("RESIDENT_GRID_LAUNCH id=%0d words=%0d blocks=%0d peak_resident=%0d elapsed_cycles=%0d",20+replay,stores,completed,peak_resident,elapsed_cycles);
  end
  $display("RESIDENT_GRID_PASS K=%0d checked_words=12288 launches=%0d",K,grid_launches);$finish;
 end
endmodule
