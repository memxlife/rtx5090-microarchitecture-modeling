`timescale 1ns/1ps
module numerical_matrix_tb #(parameter int LATENCY=17,INTERVAL=3,ARITHMETIC_MODE=0);
 localparam int CASES=6;
 logic clk=0,rst=1;always #1 clk=~clk;
 logic req_valid,req_ready,rsp_valid,rsp_ready;
 logic[31:0] req_id,rsp_id,accumulator_words[256],result_words[256];
 logic[15:0] a_words[256],b_words[256];
 logic[15:0] a_file[CASES*256],b_file[CASES*256];
 logic[31:0] c_file[CASES*256],expected[CASES*256];
 int outstanding,sent=0,received=0,cycle=0,accepted[CASES],last_accept=-1000,held=0;
 string directory;logic active=0;logic duplicate=0;
 numerical_matrix_pipeline #(.LATENCY(LATENCY),.INTERVAL(INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) dut(.*);
 assign req_valid=active&&sent<CASES;
 assign req_id=duplicate?32'd200:32'(200+sent);
 assign rsp_ready=active&&cycle>=50&&cycle%5!=0;
 always_comb begin
  for(int i=0;i<256;i++) begin
   a_words[i]=a_file[(sent<CASES?sent:0)*256+i];
   b_words[i]=b_file[(sent<CASES?sent:0)*256+i];
   accumulator_words[i]=c_file[(sent<CASES?sent:0)*256+i];
  end
 end
 always @(posedge clk) begin
  if(!rst&&active) begin
   cycle<=cycle+1;
   if(outstanding<0||outstanding>2) $fatal(1,"Matrix queue capacity violated");
   if(req_valid&&req_ready) begin
    if(cycle-last_accept<INTERVAL) $fatal(1,"Matrix initiation interval violated");
    accepted[sent]=cycle;last_accept=cycle;sent<=sent+1;
   end
   if(rsp_valid) begin
    if(rsp_id!=200+received) $fatal(1,"Matrix identity/order wrong");
    if(cycle<accepted[received]+LATENCY) $fatal(1,"Premature matrix result");
    for(int i=0;i<256;i++)
     if(result_words[i]!==expected[received*256+i])
      $fatal(1,"Matrix value mismatch case=%0d word=%0d actual=%h expected=%h",received,i,result_words[i],expected[received*256+i]);
    if(!rsp_ready) held<=held+1;
    else received<=received+1;
   end
  end
 end
 initial begin
  duplicate=$test$plusargs("duplicate");
  if(!$value$plusargs("vectors=%s",directory)) $fatal(1,"Missing vectors directory");
  $readmemh({directory,"/a.hex"},a_file);$readmemh({directory,"/b.hex"},b_file);
  $readmemh({directory,"/c.hex"},c_file);$readmemh({directory,"/expected.hex"},expected);
  repeat(3) @(negedge clk);rst=0;active=1;
  wait(received==CASES);@(negedge clk);
  if(outstanding!=0||sent!=CASES||held==0) $fatal(1,"Completion conservation/stall coverage wrong");
  active=0;rst=1;@(negedge clk);#0.1;
  if(outstanding!=0||rsp_valid||req_ready) $fatal(1,"Reset did not clear matrix work");
  $display("NUMERICAL_MATRIX_PASS operations=%0d checked_words=%0d latency=%0d interval=%0d held_cycles=%0d cycles=%0d",received,CASES*256,LATENCY,INTERVAL,held,cycle);
  $finish;
 end
 initial begin #2000;$fatal(1,"Matrix pipeline timeout");end
endmodule
