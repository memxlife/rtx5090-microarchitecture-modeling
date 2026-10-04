module native_movm_word_tb;
 parameter int LATENCY=1,INTERVAL=1;
 localparam int OPERATIONS=2060;
 logic clk=0,rst=1;always #5 clk=~clk;
 logic req_valid,req_ready,rsp_valid,rsp_ready;
 logic [31:0] req_id,rsp_id,input_words[32],output_words[32];int outstanding;
 logic [31:0] raw_words[OPERATIONS*32],gold_words[OPERATIONS*32];
 int offered=0,received=0,cycle=0,checked=0;
 string raw_path,gold_path;
 logic held=0;logic [31:0] held_id,held_values[32];
 native_movm_word_pipeline #(.SLOTS(4),.LATENCY(LATENCY),.INTERVAL(INTERVAL)) dut(.*);
 always_comb begin
  req_valid=!rst&&offered<OPERATIONS;req_id=32'(offered);
  rsp_ready=!rst&&(cycle%5>=2);
  for(int lane=0;lane<32;lane++)input_words[lane]=offered<OPERATIONS?raw_words[offered*32+lane]:0;
 end
 always @(posedge clk)begin
  cycle<=cycle+1;
  if(!rst)begin
   if(req_valid&&req_ready)offered<=offered+1;
   if(rsp_valid&&rsp_ready)begin
    if(rsp_id!=32'(received))$fatal(1,"MOVM response identity/order mismatch");
    for(int lane=0;lane<32;lane++)begin
     if(output_words[lane]!=gold_words[received*32+lane])$fatal(1,"MOVM hardware capture mismatch");
     checked++;
    end
    received<=received+1;
   end
   if(held)begin
    if(!rsp_valid||rsp_id!=held_id)$fatal(1,"MOVM held identity changed");
    for(int lane=0;lane<32;lane++)if(output_words[lane]!=held_values[lane])$fatal(1,"MOVM held value changed");
   end
   held<=rsp_valid&&!rsp_ready;held_id<=rsp_id;
   for(int lane=0;lane<32;lane++)held_values[lane]<=output_words[lane];
  end else held<=0;
 end
 initial begin
  if(!$value$plusargs("raw=%s",raw_path)||!$value$plusargs("gold=%s",gold_path))$fatal(1,"Missing MOVM vectors");
  $readmemh(raw_path,raw_words);$readmemh(gold_path,gold_words);
  repeat(2)@(negedge clk);rst=0;
  wait(received==OPERATIONS);@(negedge clk);
  if(outstanding!=0)$fatal(1,"MOVM retirement leak");
  rst=1;@(negedge clk);rst=0;
  if(rsp_valid||outstanding!=0)$fatal(1,"MOVM reset leak");
  $display("NATIVE_MOVM_PASS operations=%0d checked_words=%0d",received,checked);$finish;
 end
 initial begin #1000000;$fatal(1,"MOVM timeout");end
endmodule
