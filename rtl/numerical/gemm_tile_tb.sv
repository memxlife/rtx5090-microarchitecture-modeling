`timescale 1ns/1ps
`include "provisional_config.svh"
module gemm_tile_tb #(parameter int STAGES=2);
 logic clk=0,rst=1;always #1 clk=~clk;
 logic launch_valid=0,launch_ready,done_valid,done_ready=0;
 logic[31:0]launch_id=17,input_base=0,output_base=32'h100000,done_id;
 logic backing_req_valid,backing_req_ready,backing_rsp_valid=0,backing_rsp_ready;
 logic[31:0]backing_req_id,backing_req_byte_address,backing_rsp_id=0;
 logic[255:0]backing_rsp_data=0;
 logic store_req_valid,store_req_ready,store_rsp_valid=0,store_rsp_ready;
 logic[31:0]store_req_id,store_req_byte_address,store_req_data,store_rsp_id=0;
 logic[15:0]input_words[STAGES*512];logic[31:0]expected[256],output_words[256];
 bit committed[256];int pending_index;logic[31:0]pending_data;
 int read_countdown=-1,write_countdown=-1,backing_delay=2,store_delay=5,store_admission_wait=2;
 int cycles=0,misses=0,accepted_stores=0,committed_stores=0;
 int launch_cycle=0;bit completion_reported=0;
 bit read_pending=0,write_pending=0;
 string vectors;
 gemm_tile_controller #(.STAGES(STAGES),.SETS(`PROVISIONAL_CACHE_SETS),.WAYS(`PROVISIONAL_CACHE_WAYS),
  .SHARED_BYTES(`PROVISIONAL_SHARED_BYTES),.SLOTS(`PROVISIONAL_MATRIX_CAPACITY),
  .LATENCY(`PROVISIONAL_MATRIX_LATENCY),.INTERVAL(`PROVISIONAL_MATRIX_INTERVAL)) dut(.*);
 assign backing_req_ready=!rst&&!read_pending&&!backing_rsp_valid;
 assign store_req_ready=!rst&&!write_pending&&!store_rsp_valid&&store_admission_wait==0;
 always @(posedge clk)begin
  if(rst)begin read_pending<=0;write_pending<=0;backing_rsp_valid<=0;store_rsp_valid<=0;store_admission_wait<=2;end
  else begin
   cycles<=cycles+1;
   if(launch_valid&&launch_ready)begin launch_cycle<=cycles;completion_reported<=0;end
   if(done_valid&&!completion_reported)begin
    $display("TILE_EXECUTION id=%0d cycles=%0d",done_id,cycles-launch_cycle);
    completion_reported<=1;
   end
   if(store_req_valid&&!write_pending&&!store_rsp_valid&&store_admission_wait>0)store_admission_wait<=store_admission_wait-1;
   if(backing_req_valid&&backing_req_ready)begin
    if(backing_req_byte_address>=STAGES*1024)$fatal(1,"Invalid backing request");
    read_pending<=1;read_countdown<=backing_delay;backing_rsp_id<=backing_req_id;
    for(int h=0;h<16;h++)backing_rsp_data[h*16+:16]<=input_words[int'(backing_req_byte_address)/2+h];
    misses<=misses+1;
   end
   if(read_pending&&!backing_rsp_valid)begin
    if(read_countdown==0)backing_rsp_valid<=1;else read_countdown<=read_countdown-1;
   end
   if(backing_rsp_valid&&backing_rsp_ready)begin read_pending<=0;backing_rsp_valid<=0;end
   if(store_req_valid&&store_req_ready)begin
    int index;index=int'((store_req_byte_address-output_base)/4);
    if(store_req_byte_address[1:0]||index<0||index>=256||committed[index])$fatal(1,"Output address or duplicate store");
    write_pending<=1;write_countdown<=store_delay;store_rsp_id<=store_req_id+($test$plusargs("wrongstoreid")?1:0);
    pending_index<=index;pending_data<=store_req_data;accepted_stores<=accepted_stores+1;
   end
   if(write_pending&&!store_rsp_valid)begin
    if(write_countdown==0)store_rsp_valid<=1;else write_countdown<=write_countdown-1;
   end
   if(store_rsp_valid&&store_rsp_ready)begin
    output_words[pending_index]<=pending_data;committed[pending_index]<=1;
    committed_stores<=committed_stores+1;write_pending<=0;store_rsp_valid<=0;store_admission_wait<=2;
   end
   if(done_valid&&(committed_stores%256!=0||write_pending||store_rsp_valid))$fatal(1,"Premature tile completion");
  end
 end
 initial begin
  if(!$value$plusargs("vectors=%s",vectors))$fatal(1,"Missing vectors");
  if($value$plusargs("backing_delay=%d",backing_delay))begin end
  if($value$plusargs("store_delay=%d",store_delay))begin end
  $readmemh({vectors,"/input.hex"},input_words);$readmemh({vectors,"/expected.hex"},expected);
  repeat(2)@(negedge clk);rst=0;
  if($test$plusargs("badbase"))begin input_base=4;launch_valid=1;@(negedge clk);$fatal(1,"Missing base rejection");end
  if($test$plusargs("overlap"))begin output_base=0;launch_valid=1;@(negedge clk);$fatal(1,"Missing overlap rejection");end
  for(int replay=0;replay<2;replay++)begin
   for(int i=0;i<256;i++)committed[i]=0;
   launch_id=32'(17+replay);while(!launch_ready)@(negedge clk);
   launch_valid=1;@(negedge clk);launch_valid=0;
   wait(done_valid);@(negedge clk);
   if(done_id!=17+replay||committed_stores!=(replay+1)*256)$fatal(1,"Completion identity/count");
   repeat(3)begin
    for(int i=0;i<256;i++)if(!committed[i]||output_words[i]!==expected[i])$fatal(1,"GEMM tile numerical mismatch element%0d",i);
    if(!done_valid||done_id!=17+replay||store_req_valid)$fatal(1,"Held tile completion unstable");
    @(negedge clk);
   end
   done_ready=1;@(negedge clk);done_ready=0;
  end
  if(misses!=STAGES*32||accepted_stores!=512||committed_stores!=512)$fatal(1,"Replay cache reuse or store conservation");
  rst=1;@(negedge clk);#0.1;
  if(done_valid||launch_ready||store_req_valid||backing_req_valid)$fatal(1,"Reset failed");
  $display("GEMM_TILE_PASS stages=%0d checked_words=512 backing_requests=%0d stores=%0d cycles=%0d",STAGES,misses,committed_stores,cycles);$finish;
 end
 initial begin #2000000;$fatal(1,"GEMM tile timeout");end
endmodule
