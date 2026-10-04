module timed_generic_shared_matrix_tb;
 logic clk=0,rst=1;always #5 clk=~clk;
 logic write_valid=0,write_ready;logic[31:0]write_byte_address=0;logic[15:0]write_data=0;
 logic req_valid=0,req_ready;logic[31:0]req_id=123,a_word_addresses[32][4],b_word_addresses[32][4],c_registers[32][8];
 logic operands_initialized,addresses_legal,rsp_valid,rsp_ready=0;logic[31:0]rsp_id,result_registers[32][8];int outstanding;
 timed_generic_shared_matrix_pipeline #(.SHARED_BYTES(1024),.LATENCY(2),.INTERVAL(1),.SERVICE_INTERVAL(2),.RETURN_DELAY(3)) dut(.*);
 task tick;@(posedge clk);#1;endtask
function automatic logic [15:0] bf(input int n);case(n)
0:return 16'h0000;
1:return 16'h3f80;
2:return 16'h4000;
3:return 16'h4040;
4:return 16'h4080;
5:return 16'h40a0;
6:return 16'h40c0;
7:return 16'h40e0;
8:return 16'h4100;
9:return 16'h4110;
10:return 16'h4120;
11:return 16'h4130;
12:return 16'h4140;
13:return 16'h4150;
14:return 16'h4160;
15:return 16'h4170;
16:return 16'h4180;
default:return 0;endcase endfunction
function automatic logic[31:0] fp(input int n);case(n)
0:return 32'h00000000;
1:return 32'h3f800000;
2:return 32'h40000000;
3:return 32'h40400000;
4:return 32'h40800000;
5:return 32'h40a00000;
6:return 32'h40c00000;
7:return 32'h40e00000;
8:return 32'h41000000;
9:return 32'h41100000;
10:return 32'h41200000;
11:return 32'h41300000;
12:return 32'h41400000;
13:return 32'h41500000;
14:return 32'h41600000;
15:return 32'h41700000;
16:return 32'h41800000;
default:return 0;endcase endfunction

 initial begin
  for(int l=0;l<32;l++)begin
   for(int w=0;w<4;w++)begin
    a_word_addresses[l][w]=32*(l/4)+4*(l%4)+(w%2)*256+(w/2)*16;
    b_word_addresses[l][w]=512+32*(l/4)+4*(l%4)+(w%2)*256+(w/2)*16;
   end
   for(int e=0;e<8;e++)c_registers[l][e]=0;
  end
  tick();@(negedge clk);rst=0;#1;
  if(req_ready||operands_initialized)$fatal(1,"Uninitialized operands admitted");
  for(int index=0;index<512;index++)begin
   @(negedge clk);write_valid=1;write_byte_address=32'(2*index);
   if(index<256)write_data=bf((index/16)==(index%16)?1:0);
   else write_data=bf((index%16)+1);
   tick();
  end
  @(negedge clk);write_valid=0;req_valid=1;#1;
  if(!req_ready)$fatal(1,"Initialized request not ready");tick();
  @(negedge clk);req_valid=0;write_valid=1;write_byte_address=0;write_data=0;
  for(int l=0;l<32;l++)begin
   for(int w=0;w<4;w++)begin a_word_addresses[l][w]=0;b_word_addresses[l][w]=0;end
   for(int e=0;e<8;e++)c_registers[l][e]=32'h42c60000;
  end
  tick();@(negedge clk);write_valid=0;
  for(int timeout=0;timeout<1000&&!rsp_valid;timeout++)tick();
  if(!rsp_valid||rsp_id!=123)$fatal(1,"No matching matrix response");
  for(int l=0;l<32;l++)for(int e=0;e<8;e++)begin
   int index;index=native_bf16_layout::c_element_index(l,e);
   if(result_registers[l][e]!==fp(index%16+1))$fatal(1,"Returned operands failed l%0d e%0d got%h",l,e,result_registers[l][e]);
  end
  repeat(4)begin tick();if(!rsp_valid||req_ready)$fatal(1,"Lost backpressured output");end
  @(negedge clk);rsp_ready=1;tick();@(negedge clk);rsp_ready=0;rst=1;tick();
  @(negedge clk);rst=0;#1;if(operands_initialized||rsp_valid||outstanding!=0)$fatal(1,"Reset failed");
  $display("TIMED_GENERIC_PASS checked_words=256 snapshots=1 reset=1 backpressure=1");$finish;
 end
endmodule
