`timescale 1ns/1ps
module studied_gemm_grid_tb #(
 parameter int BM=32,BN=32,M=64,N=96,K=64,READ_DELAY=2,REPLAYS=1

);
 logic clk=0;always #0.05 clk=~clk;
 logic[31:0]launch_cta_row=0,launch_cta_col=0;
 logic rst=1,launch_valid=0,launch_ready,done_valid,done_ready=0;
 logic[31:0]launch_id=101,a_base=32'h100000,b_base=32'h1000000,c_base=32'h3000000,done_id;
 logic backing_req_valid,backing_req_ready,backing_rsp_valid,backing_rsp_ready;
 logic[31:0]backing_req_id,backing_req_byte_address,backing_rsp_id;
 logic[255:0]backing_rsp_data;
 logic store_req_valid,store_req_ready,store_rsp_valid,store_rsp_ready;
 logic[31:0]store_req_id,store_req_byte_address,store_req_data,store_rsp_id;
 logic sector_store_req_valid,sector_store_req_ready,sector_store_rsp_valid,sector_store_rsp_ready;
 logic[31:0]sector_store_req_id,sector_store_req_byte_address,sector_store_rsp_id;
 logic[255:0]sector_store_req_data;
 logic[7:0]sector_store_req_word_mask;
 bit sector_pending=0,held_sector=0;
 integer sector_wait=0,saved_sector_words=0,output_packets=0,output_packet_acks=0;
 logic[31:0]saved_sector_id,held_sector_id,held_sector_address;
 logic[255:0]held_sector_data;logic[7:0]held_sector_mask;
 int cycle=0,read_wait=0,store_wait=0,backing_requests=0,stores=0,acks=0,checked=0,launches=0;
 int launch_start_cycle=0,logical_loads=0,shared_commits=0,returned_sectors=0,matrix_requests=0,matrix_completions=0;
 bit launch_active=0;
 bit read_pending=0,store_pending=0,wrong_backing=0,wrong_store=0;
 bit seen[M*N];
 int dispatched_blocks,completed_blocks;
 logic block_launch_valid,block_done_valid;
 logic[31:0]block_launch_row,block_launch_col,block_done_row,block_done_col;
 bit blocks_seen[(M/BM)*(N/BN)],blocks_done[(M/BM)*(N/BN)];
 logic[31:0]saved_read_id,saved_read_address,saved_store_id;
 logic held_store=0;logic[31:0]held_id,held_address,held_data;
 studied_gemm_grid_controller #(.BM(BM),.BN(BN),.BK(32),.M(M),.N(N),.K(K),.READ_SLOTS(2),.RETURN_DELAY(9),.MOVM_LATENCY(19),.LATENCY(73)) dut(.*);
 // All test values are integer multiples of powers of two, exactly represented.
 function automatic logic[31:0] dyadic_bits(input integer numerator,input integer fractional_bits);
  integer magnitude,top,exponent;logic[31:0]fraction;
  begin
   if(numerator==0)return 0;
   magnitude=numerator<0?-numerator:numerator;top=0;
   while((magnitude>>(top+1))!=0)top++;
   if(top>23)$fatal(1,"Oracle integer too large for exact FP32 representation");
   exponent=127+top-fractional_bits;
   fraction=32'(magnitude-(1<<top))<<(23-top);
   return (numerator<0?32'h80000000:0)|(32'(exponent)<<23)|fraction;
  end
 endfunction
 function automatic logic[15:0] input_halfword(input logic[31:0]address);
  integer index,numerator;logic[31:0]bits;
  begin
   if(address>=a_base&&{1'b0,address}<{1'b0,a_base}+33'(2*M*K))begin
    index=int'((address-a_base)/2);numerator=index%17-8;
   end else if(address>=b_base&&{1'b0,address}<{1'b0,b_base}+33'(2*K*N))begin
    index=int'((address-b_base)/2);numerator=index%13-6;
   end else $fatal(1,"Read outside original A/B ranges address%h",address);
   bits=dyadic_bits(numerator,4);return bits[31:16];
  end
 endfunction
 function automatic logic[31:0] expected_word(input integer row,col);
  integer sum;
  begin
   sum=0;
   for(int k=0;k<K;k++)sum+=((row*K+k)%17-8)*((k*N+col)%13-6);
   return dyadic_bits(sum,8);
  end
 endfunction
 always_comb begin
  backing_req_ready=!rst&&!read_pending&&(cycle%3!=0);
  backing_rsp_valid=!rst&&read_pending&&read_wait==0;
  backing_rsp_id=saved_read_id+(wrong_backing?1:0);
  backing_rsp_data=0;
  if(read_pending)for(int h=0;h<16;h++)backing_rsp_data[h*16+:16]=input_halfword(saved_read_address+32'(2*h));
  store_req_ready=!rst&&!store_pending&&(cycle%3==2);
  store_rsp_valid=!rst&&store_pending&&store_wait==0;
  store_rsp_id=saved_store_id+(wrong_store?1:0);
  sector_store_req_ready=!rst&&!sector_pending&&(cycle%3==2);
  sector_store_rsp_valid=!rst&&sector_pending&&sector_wait==0;
  sector_store_rsp_id=saved_sector_id+(wrong_store?1:0);
 end
 always @(posedge clk)begin
  cycle<=cycle+1;
  if(cycle>20000000)$fatal(1,"CTA simulation did not terminate");
  if(rst)begin
   sector_pending<=0;sector_wait<=0;held_sector<=0;output_packets=0;output_packet_acks=0;
   read_pending<=0;store_pending<=0;read_wait<=0;store_wait<=0;held_store<=0;
   stores=0;acks=0;checked=0;launches=0;backing_requests=0;
   launch_active=0;logical_loads=0;shared_commits=0;returned_sectors=0;matrix_requests=0;matrix_completions=0;
   for(int i=0;i<M*N;i++)seen[i]=0;
   for(int i=0;i<(M/BM)*(N/BN);i++)begin blocks_seen[i]=0;blocks_done[i]=0;end
  end else begin
   if(sector_pending&&sector_wait>0)sector_wait<=sector_wait-1;
   if(sector_store_rsp_valid&&sector_store_rsp_ready)begin
    sector_pending<=0;acks+=saved_sector_words;output_packet_acks++;
   end
   if(held_sector&&(!sector_store_req_valid||sector_store_req_id!==held_sector_id||sector_store_req_byte_address!==held_sector_address||sector_store_req_data!==held_sector_data||sector_store_req_word_mask!==held_sector_mask))
    $fatal(1,"Sector output payload changed under backpressure");
   held_sector<=sector_store_req_valid&&!sector_store_req_ready;
   if(sector_store_req_valid&&!sector_store_req_ready)begin
    held_sector_id<=sector_store_req_id;held_sector_address<=sector_store_req_byte_address;
    held_sector_data<=sector_store_req_data;held_sector_mask<=sector_store_req_word_mask;
   end
   if(sector_store_req_valid&&sector_store_req_ready)begin
    integer packet_words;packet_words=0;
    if(sector_store_req_byte_address[4:0]!=0||sector_store_req_word_mask==0)$fatal(1,"Invalid output sector packet");
    for(int w=0;w<8;w++)if(sector_store_req_word_mask[w])begin
     integer address,global_index,row,col,local_index;logic[31:0]want;
     address=sector_store_req_byte_address+4*w;
     if(address<c_base)$fatal(1,"Sector output address below C");
     global_index=(address-c_base)/4;row=global_index/N;col=global_index%N;
     if(row>=M||col>=N)$fatal(1,"Sector output outside full grid");
     local_index=row*N+col;if(seen[local_index])$fatal(1,"Duplicate sector output word");
     want=expected_word(row,col);
     if(sector_store_req_data[w*32+:32]!==want)$fatal(1,"Sector CTA output mismatch row%0d col%0d",row,col);
     seen[local_index]=1;packet_words++;stores++;checked++;
    end
    sector_pending<=1;saved_sector_id<=sector_store_req_id;saved_sector_words<=packet_words;sector_wait<=3+(cycle%4);output_packets++;
   end
   if(read_pending&&read_wait>0)read_wait<=read_wait-1;
   if(store_pending&&store_wait>0)store_wait<=store_wait-1;
   if(backing_rsp_valid&&backing_rsp_ready)read_pending<=0;
   if(store_rsp_valid&&store_rsp_ready)begin store_pending<=0;acks++;end
   if(backing_req_valid&&backing_req_ready)begin
    if(backing_req_byte_address[4:0]!=0)$fatal(1,"Backing request not sector aligned");
    read_pending<=1;saved_read_id<=backing_req_id;saved_read_address<=backing_req_byte_address;
    read_wait<=READ_DELAY;backing_requests++;
   end
   if(held_store&&(store_req_id!==held_id||store_req_byte_address!==held_address||store_req_data!==held_data||!store_req_valid))
    $fatal(1,"Output-store payload changed under backpressure");
   held_store<=store_req_valid&&!store_req_ready;
   if(store_req_valid&&!store_req_ready)begin held_id<=store_req_id;held_address<=store_req_byte_address;held_data<=store_req_data;end
   if(launch_valid&&launch_ready)begin
    launches++;launch_start_cycle=cycle;launch_active=1;
    logical_loads=0;shared_commits=0;returned_sectors=0;matrix_requests=0;matrix_completions=0;output_packets=0;output_packet_acks=0;
    for(int i=0;i<M*N;i++)seen[i]=0;
   for(int i=0;i<(M/BM)*(N/BN);i++)begin blocks_seen[i]=0;blocks_done[i]=0;end
   end
   if(block_launch_valid)begin
    integer bi;
    if(block_launch_row>=M/BM||block_launch_col>=N/BN)$fatal(1,"Block launch outside grid");
    bi=int'(block_launch_row)*(N/BN)+int'(block_launch_col);
    if(blocks_seen[bi])$fatal(1,"Duplicate block launch");blocks_seen[bi]=1;
    $display("GRID_BLOCK_LAUNCH row=%0d col=%0d cycle=%0d",block_launch_row,block_launch_col,cycle);
   end
   if(block_done_valid)begin
    integer bi;
    if(block_done_row>=M/BM||block_done_col>=N/BN)$fatal(1,"Block completion outside grid");
    bi=int'(block_done_row)*(N/BN)+int'(block_done_col);
    if(!blocks_seen[bi]||blocks_done[bi])$fatal(1,"Invalid block completion");blocks_done[bi]=1;
    $display("GRID_BLOCK_DONE row=%0d col=%0d cycle=%0d",block_done_row,block_done_col,cycle);
   end
   if(done_valid&&launch_active)begin
    if(dispatched_blocks!=(M/BM)*(N/BN)||completed_blocks!=dispatched_blocks)$fatal(1,"Grid block conservation failed");
    $display("GRID_LAUNCH_METRICS id=%0d completion_cycles=%0d blocks=%0d packets=%0d packet_acks=%0d",launch_id,cycle-launch_start_cycle,completed_blocks,output_packets,output_packet_acks);
    launch_active=0;
   end
   if(store_req_valid&&store_req_ready)begin
    integer global_index,row,col,local_index;logic[31:0]want;
    $fatal(1,"Unexpected scalar output in sector mode");
    if(store_req_byte_address<c_base||store_req_byte_address[1:0]!=0)$fatal(1,"Invalid output address");
    global_index=int'((store_req_byte_address-c_base)/4);row=global_index/N;col=global_index%N;
    if(row>=M||col>=N)$fatal(1,"Output outside full grid row%0d col%0d",row,col);
    local_index=row*N+col;
    if(seen[local_index])$fatal(1,"Duplicate output word");

    want=expected_word(row,col);
    if(store_req_data!==want)$fatal(1,"CTA output mismatch row%0d col%0d got%h want%h",row,col,store_req_data,want);
    seen[local_index]=1;stores++;checked++;
    store_pending<=1;saved_store_id<=store_req_id;store_wait<=3;
   end
   if(done_valid)begin
    if(done_id!=launch_id)$fatal(1,"Launch completion ID mismatch");
    if(stores!=launches*M*N||acks!=stores||store_pending||sector_pending)$fatal(1,"Done preceded all acknowledged output stores");
    for(int i=0;i<M*N;i++)if(!seen[i])$fatal(1,"Missing output word");
   end
  end
 end
 task automatic launch;
  begin
   @(negedge clk);while(!launch_ready)@(negedge clk);
   launch_valid=1;@(negedge clk);launch_valid=0;
  end
 endtask
 initial begin
  wrong_backing=$test$plusargs("wrongbacking");wrong_store=$test$plusargs("wrongstore");
  repeat(3)@(negedge clk);rst=0;
  // Cancel an actual pending read, flush the provider, then run fresh launches.
  launch();wait(read_pending);@(negedge clk);rst=1;
  repeat(2)@(negedge clk);rst=0;
  if(done_valid||store_req_valid||sector_store_req_valid||sector_store_rsp_valid||backing_rsp_valid)$fatal(1,"Reset failed to flush pending work");
  for(int replay=0;replay<REPLAYS;replay++)begin
   launch_id=32'(101+replay);launch();wait(done_valid);
   repeat(3)@(negedge clk);
   if(!done_valid||done_id!=launch_id)$fatal(1,"Held completion changed");
   done_ready=1;@(negedge clk);done_ready=0;
  end
  repeat(3)@(negedge clk);
  $display("STUDIED_GRID_PASS M=%0d N=%0d K=%0d checked_words=%0d launches=%0d stores=%0d acks=%0d backing_requests=%0d cycles=%0d",M,N,K,checked,launches,stores,acks,backing_requests,cycle);
  $finish;
 end
endmodule
