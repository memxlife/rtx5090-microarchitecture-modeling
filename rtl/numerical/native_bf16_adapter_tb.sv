module native_bf16_adapter_tb;
 logic clk=0,rst=1,req_valid=0,req_ready,rsp_valid,rsp_ready=0;
 logic [31:0] req_id=42,rsp_id,a_registers[32][4],b_registers[32][4],c_registers[32][8],result_registers[32][8];
 int outstanding,amap[256],bmap[256],cmap[256];
 always #5 clk=~clk;
 native_bf16_adapter #(.LATENCY(3),.INTERVAL(1)) dut(.*);
 initial begin
  $readmemh("a_mapping.hex",amap);$readmemh("b_mapping.hex",bmap);$readmemh("c_mapping.hex",cmap);
  for(int lane=0;lane<32;lane++) begin
   for(int word=0;word<4;word++) begin
    a_registers[lane][word]=0;b_registers[lane][word]=0;
    for(int half=0;half<2;half++) begin
     int ai,bi;ai=amap[lane*8+word*2+half];bi=bmap[lane*8+word*2+half];
     a_registers[lane][word][half*16+:16]=(ai/16==ai%16)?16'h3f80:0;
     b_registers[lane][word][half*16+:16]=(bi/16==bi%16)?16'h4000:0;
    end
   end
   for(int e=0;e<8;e++) c_registers[lane][e]=32'h3f800000;
  end
  repeat(2) @(negedge clk);rst=0;req_valid=1;
  @(negedge clk);req_valid=0;
  wait(rsp_valid);@(negedge clk);
  if(rsp_id!=42) $fatal(1,"Identity mismatch");
  repeat(3) begin
   for(int lane=0;lane<32;lane++) for(int e=0;e<8;e++) begin
    int ci;ci=cmap[lane*8+e];
    if(result_registers[lane][e]!==((ci/16==ci%16)?32'h40400000:32'h3f800000)) $fatal(1,"Native result mismatch");
   end
   @(negedge clk);
  end
  rsp_ready=1;@(negedge clk);if(outstanding!=0) $fatal(1,"Retirement mismatch");
  $display("PASS: native adapter 256 numerical words and stalled response stability");$finish;
 end
 initial begin #1000;$fatal(1,"Timeout");end
endmodule
