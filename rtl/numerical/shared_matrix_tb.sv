`timescale 1ns/1ps
module shared_matrix_tb #(parameter int LATENCY=17,INTERVAL=3,SHARED_BYTES=1024);
 localparam int CASES=24;
 logic clk=0,rst=1;always #1 clk=~clk;
 logic write_valid=0,write_ready,req_valid=0,req_ready,rsp_valid,rsp_ready=0;
 logic[31:0] write_byte_address=0,req_id,rsp_id,a_row_addresses[32],b_row_addresses[32];
 logic[15:0] write_data,storage_file[CASES*512];
 logic[31:0] c_registers[32][8],result_registers[32][8],c_file[CASES*256],expected[CASES*256];
 logic operands_initialized,addresses_legal;
 int outstanding,cmap[256],accepted=0,written=0,cycle=0,accept_cycle;
 string directory,mappings;
 shared_matrix_pipeline #(.SHARED_BYTES(SHARED_BYTES),.LATENCY(LATENCY),.INTERVAL(INTERVAL)) dut(.*);
 always @(posedge clk) if(!rst) begin
  cycle<=cycle+1;
  if(req_valid&&req_ready) begin
   if(written!=512) $fatal(1,"Matrix issued before final shared write became visible");
   accepted<=accepted+1;accept_cycle=cycle;
  end
 end
 initial begin
  if(!$value$plusargs("vectors=%s",directory)||!$value$plusargs("mappings=%s",mappings)) $fatal(1,"Missing inputs");
  $readmemh({directory,"/storage.hex"},storage_file);
  $readmemh({directory,"/c.hex"},c_file);$readmemh({directory,"/expected.hex"},expected);
  $readmemh({mappings,"/c_mapping.hex"},cmap);
  for(int c=0;c<CASES;c++) begin
   rst=1;req_valid=0;write_valid=0;rsp_ready=0;written=0;
   for(int lane=0;lane<32;lane++) begin
    int row;
    case(c%4)
     1:row=(lane/8)*8+7-lane%8;
     2:row=lane^8;
     3:row=lane%8;
     default:row=lane;
    endcase
    a_row_addresses[lane]=32'(SHARED_BYTES-1024+row*16);b_row_addresses[lane]=32'(SHARED_BYTES-512+row*16);
    for(int element=0;element<8;element++) c_registers[lane][element]=c_file[c*256+cmap[lane*8+element]];
   end
   req_id=32'(500+c);
   repeat(2) @(negedge clk);rst=0;
   if($test$plusargs("writeodd")) begin write_valid=1;write_byte_address=1;@(negedge clk);$fatal(1,"Missing write rejection");end
   if($test$plusargs("unaligned")) begin a_row_addresses[0]=4;req_valid=1;@(negedge clk);$fatal(1,"Missing alignment rejection");end
   if($test$plusargs("outofbounds")) begin b_row_addresses[0]=32'(SHARED_BYTES);req_valid=1;@(negedge clk);$fatal(1,"Missing bounds rejection");end
   req_valid=1;
   // Keep one actually referenced word until last, including repeated-row requests.
   for(int i=0;i<512;i++) begin
    int critical,index;
    critical=c%4==3?319:511;
    index=i==511?critical:(i<critical?i:i+1);
    write_valid=1;write_byte_address=32'(SHARED_BYTES-1024+index*2);write_data=storage_file[c*512+index];
    @(negedge clk);written=i+1;
    if(i<511&&req_ready) $fatal(1,"Incomplete operand packet ready");
   end
   write_valid=0;
   wait(accepted==c+1);@(negedge clk);req_valid=0;
   // Overwrite an operand after acceptance: pending result must use the captured packet.
   write_valid=1;write_byte_address=32'(SHARED_BYTES-1024);write_data=0;@(negedge clk);write_valid=0;
   wait(rsp_valid);@(negedge clk);
   if(cycle<accept_cycle+LATENCY||rsp_id!=500+c) $fatal(1,"Completion timing or identity");
   repeat(3) begin
    for(int lane=0;lane<32;lane++) for(int element=0;element<8;element++)
     if(result_registers[lane][element]!==expected[c*256+cmap[lane*8+element]])
      $fatal(1,"Shared matrix numerical mismatch case=%0d lane=%0d word=%0d",c,lane,element);
    @(negedge clk);
   end
   rsp_ready=1;@(negedge clk);
   if(outstanding!=0) $fatal(1,"Response not retired");
   rsp_ready=0;
  end
  rst=1;@(negedge clk);#0.1;
  if(outstanding||rsp_valid||req_ready||operands_initialized) $fatal(1,"Reset did not invalidate work and shared words");
  $display("SHARED_MATRIX_PASS operations=24 checked_words=6144 readiness snapshot stall reset");$finish;
 end
 initial begin #100000;$fatal(1,"Shared matrix timeout");end
endmodule
