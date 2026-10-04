`timescale 1ns/1ps
module shared_read_candidate_hub_tb #(parameter int SLOTS=1);
 logic clk=0;always #0.05 clk=~clk;logic rst=1;
 logic[1:0]candidate_valid=0,candidate_grant,rsp_valid,rsp_ready=0;
 logic[31:0]candidate_id[2],byte_addresses[2][32],input_words[2][32],rsp_id[2],output_words[2][32];
 int outstanding,client_outstanding[2],cycle=0,accepted[2],retired[2],checked=0;
 logic[31:0]expected_words[2][8][32];bit expected_live[2][8];
 bit held[2];logic[31:0]held_id[2],held_values[2][32];
 shared_read_candidate_hub #(.SLOTS(SLOTS),.SERVICE_INTERVAL(3),.RETURN_DELAY(7))dut(.*);
 always @(posedge clk)begin
  cycle<=cycle+1;if(cycle>10000)$fatal(1,"Hub timeout");
  if(rst)begin for(int c=0;c<2;c++)begin accepted[c]=0;retired[c]=0;held[c]=0;for(int id=0;id<8;id++)expected_live[c][id]=0;end end
  else begin
   if(candidate_grant==2'b11)$fatal(1,"Multiple grants on one edge");
   for(int c=0;c<2;c++)begin
    if(client_outstanding[c]!=accepted[c]-retired[c])$fatal(1,"Client conservation");
    if(held[c])begin
     if(!rsp_valid[c]||rsp_id[c]!=held_id[c])$fatal(1,"Held response identity changed");
     for(int l=0;l<32;l++)if(output_words[c][l]!==held_values[c][l])$fatal(1,"Held response data changed");
    end
    held[c]=rsp_valid[c]&&!rsp_ready[c];
    if(held[c])begin held_id[c]=rsp_id[c];for(int l=0;l<32;l++)held_values[c][l]=output_words[c][l];end
    if(candidate_grant[c])begin
     if(!candidate_valid[c]||candidate_id[c]>=8)$fatal(1,"Invalid grant");
     if(expected_live[c][candidate_id[c]])begin
      if(!$test$plusargs("duplicate"))$fatal(1,"Unexpected duplicate test input");
     end
     expected_live[c][candidate_id[c]]=1;accepted[c]++;
     for(int l=0;l<32;l++)expected_words[c][candidate_id[c]][l]=input_words[c][l];
    end
    if(rsp_valid[c]&&rsp_ready[c])begin
     if(rsp_id[c]>=8||!expected_live[c][rsp_id[c]])$fatal(1,"Unmatched completion");
     for(int l=0;l<32;l++)begin if(output_words[c][l]!==expected_words[c][rsp_id[c]][l])$fatal(1,"Snapshot/owner mismatch");checked++;end
     expected_live[c][rsp_id[c]]=0;retired[c]++;
    end
   end
   if(outstanding!=client_outstanding[0]+client_outstanding[1])$fatal(1,"Global conservation");
  end
 end
 task automatic prepare(input integer c,id,pattern);
  begin candidate_id[c]=32'(id);for(int l=0;l<32;l++)begin
   byte_addresses[c][l]=pattern==0?32'(4*l):pattern==1?32'(128*l):0;
   input_words[c][l]=32'h70000000+32'(c*65536+id*256+(pattern==2?0:l));
  end end
 endtask
 task automatic submit(input integer c,id,pattern);
  begin @(negedge clk);prepare(c,id,pattern);candidate_valid[c]=1;#0.001;while(!candidate_grant[c])@(negedge clk);@(negedge clk);candidate_valid[c]=0;for(int l=0;l<32;l++)input_words[c][l]='1;end
 endtask
 initial begin
  for(int c=0;c<2;c++)prepare(c,0,0);
  repeat(3)@(negedge clk);rst=0;submit(0,1,1);@(negedge clk);rst=1;repeat(2)@(negedge clk);if(outstanding)$fatal(1,"Reset did not cancel");rst=0;
  if($test$plusargs("duplicate"))begin submit(0,2,1);submit(0,2,0);$fatal(1,"Duplicate not rejected");end
  // Both previews contend. Only the granted preview is committed.
  @(negedge clk);prepare(0,2,1);prepare(1,2,0);candidate_valid=3;
  begin bit got[2];got[0]=0;got[1]=0;
   while(!got[0]||!got[1])begin
    bit g0,g1;#0.001;g0=candidate_grant[0];g1=candidate_grant[1];@(negedge clk);
    if(g0)begin got[0]=1;candidate_valid[0]=0;end
    if(g1)begin got[1]=1;candidate_valid[1]=0;end
    // Alter an ungranted candidate legally; accepted payload remains immutable internally.
    for(int c=0;c<2;c++)if(!got[c])prepare(c,2,cycle%2);
    if(got[0])rsp_ready[0]=1;
   end
  end
  rsp_ready=3;wait(outstanding==0);@(negedge clk);rsp_ready=0;
  submit(0,3,2);wait(rsp_valid[0]);@(negedge clk);repeat(5)@(negedge clk);rsp_ready[0]=1;@(negedge clk);rsp_ready[0]=0;
  submit(1,4,1);wait(rsp_valid[1]);@(negedge clk);repeat(5)@(negedge clk);rsp_ready[1]=1;@(negedge clk);rsp_ready[1]=0;
  repeat(3)@(negedge clk);if(outstanding||checked!=128)$fatal(1,"Final completion count");
  $display("SHARED_HUB_PASS slots=%0d checked_words=%0d",SLOTS,checked);$finish;
 end
endmodule
