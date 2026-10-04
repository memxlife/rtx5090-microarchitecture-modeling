`timescale 1ns/1ps
`include "provisional_config.svh"
module cached_shared_matrix_tb #(parameter int BACKING_DELAY=2,CASES=24,ARITHMETIC_MODE=0);
 logic clk=0,rst=1;always #1 clk=~clk;
 logic stage_valid=0,stage_ready,stage_done_valid,stage_done_ready=0,stage_done_hit;
 logic[31:0] stage_id=0,stage_global_byte_address=0,stage_shared_byte_address=0,stage_done_id;
 logic backing_req_valid,backing_req_ready,backing_rsp_valid=0,backing_rsp_ready;
 logic[31:0] backing_req_id,backing_req_byte_address,backing_rsp_id=0;
 logic[255:0] backing_rsp_data=0;
 logic req_valid=0,req_ready,rsp_valid,rsp_ready=0,operands_initialized,addresses_legal;
 logic[31:0] req_id,rsp_id,a_row_addresses[32],b_row_addresses[32];
 logic[31:0] c_registers[32][8],result_registers[32][8];
 logic[15:0] storage_file[24*512];
 logic[31:0] c_file[24*256],expected[24*256];
 int outstanding,cmap[256],cycle=0,accepted=0,written=0,misses=0;
 int selected_case=0,remaining=-1,configured_delay=BACKING_DELAY;logic pending=0;
 string directory,mappings;
 cached_shared_matrix_pipeline #(.SETS(`PROVISIONAL_CACHE_SETS),.WAYS(`PROVISIONAL_CACHE_WAYS),.SHARED_BYTES(`PROVISIONAL_SHARED_BYTES),.SLOTS(`PROVISIONAL_MATRIX_CAPACITY),.LATENCY(`PROVISIONAL_MATRIX_LATENCY),.INTERVAL(`PROVISIONAL_MATRIX_INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) dut(.*);
 assign backing_req_ready=!rst&&!pending&&!backing_rsp_valid;
 always @(posedge clk)begin
  if(rst)begin pending<=0;remaining<=-1;backing_rsp_valid<=0;end
  else begin
   cycle<=cycle+1;
   if(backing_req_valid&&backing_req_ready)begin
    pending<=1;remaining<=configured_delay;backing_rsp_id<=backing_req_id+($test$plusargs("wrongid")?1:0);
    for(int h=0;h<16;h++)backing_rsp_data[h*16+:16]<=storage_file[selected_case*512+int'(backing_req_byte_address)/2+h];
    misses<=misses+1;
   end
   if(pending&&!backing_rsp_valid)begin
    if(remaining==0)backing_rsp_valid<=1;else remaining<=remaining-1;
   end
   if(backing_rsp_valid&&backing_rsp_ready)begin pending<=0;backing_rsp_valid<=0;end
   if(req_valid&&req_ready)begin
    if(written!=256||pending||stage_done_valid) $fatal(1,"Matrix admitted before staging completion");
    accepted<=accepted+1;
   end
  end
 end
 initial begin
  if(!$value$plusargs("vectors=%s",directory)||!$value$plusargs("mappings=%s",mappings))$fatal(1,"Missing vectors");
  if($value$plusargs("backing_delay=%d",configured_delay))begin end
  if(configured_delay<0)$fatal(1,"Negative backing delay");
  $readmemh({directory,"/storage.hex"},storage_file);$readmemh({directory,"/c.hex"},c_file);
  $readmemh({directory,"/expected.hex"},expected);$readmemh({mappings,"/c_mapping.hex"},cmap);
  for(int c=0;c<CASES;c++)begin
   selected_case=c;rst=1;stage_valid=0;stage_done_ready=0;req_valid=0;rsp_ready=0;written=0;
   for(int lane=0;lane<32;lane++)begin
    int row;
    case(c%4)
     1:row=(lane/8)*8+7-lane%8;
     2:row=lane^8;
     3:row=lane%8;
     default:row=lane;
    endcase
    a_row_addresses[lane]=32'(row*16);b_row_addresses[lane]=32'(512+row*16);
    for(int e=0;e<8;e++)c_registers[lane][e]=c_file[c*256+cmap[lane*8+e]];
   end
   req_id=32'(1000+c);repeat(2)@(negedge clk);rst=0;req_valid=1;
   if($test$plusargs("unaligned"))begin
    stage_valid=1;stage_shared_byte_address=1;@(negedge clk);$fatal(1,"Missing staging alignment rejection");
   end
   for(int i=0;i<256;i++)begin
    int critical,index;
    critical=c%4==3?159:255;index=i==255?critical:(i<critical?i:i+1);
    stage_id=32'(c*256+i);stage_global_byte_address=32'(index*4);stage_shared_byte_address=32'(index*4);
    while(!stage_ready)@(negedge clk);stage_valid=1;
    // The current falling edge observes readiness before acceptance at the next rising edge.
    @(negedge clk);stage_valid=0;
    wait(stage_done_valid);@(negedge clk);
    if(stage_done_id!=c*256+i||stage_done_hit!=(index%8!=0))$fatal(1,"Stage identity or sector reuse mismatch");
    repeat(2)begin
     if(!stage_done_valid||stage_done_id!=c*256+i||req_ready)$fatal(1,"Stalled staging completion unstable or early matrix admission");
     @(negedge clk);
    end
    written=i+1;stage_done_ready=1;@(negedge clk);stage_done_ready=0;
   end
   wait(accepted==c+1);@(negedge clk);req_valid=0;
   wait(rsp_valid);@(negedge clk);
   if(rsp_id!=1000+c)$fatal(1,"Matrix identity mismatch");
   repeat(3)begin
    for(int lane=0;lane<32;lane++)for(int e=0;e<8;e++)
     if(result_registers[lane][e]!==expected[c*256+cmap[lane*8+e]])$fatal(1,"Cached numerical mismatch case%0d lane%0d element%0d",c,lane,e);
    @(negedge clk);
   end
   rsp_ready=1;@(negedge clk);rsp_ready=0;
   if(outstanding!=0)$fatal(1,"Matrix failed to retire");
  end
  if(misses!=CASES*32)$fatal(1,"Backing request conservation mismatch");
  rst=1;@(negedge clk);#0.1;
  if(req_ready||rsp_valid||stage_done_valid||operands_initialized||outstanding)$fatal(1,"Reset failed");
  $display("CACHED_SHARED_MATRIX_PASS cases=%0d checked_words=%0d misses=%0d cycles=%0d backing_delay=%0d arithmetic_mode=%0d",CASES,CASES*256,misses,cycle,configured_delay,ARITHMETIC_MODE);$finish;
 end
 initial begin #2000000;$fatal(1,"Cached matrix timeout");end
endmodule
