module warp_shared_read_service_tb;
 parameter int INTERVAL=1,DELAY=9;
 logic clk=0,rst=1;always #5 clk=~clk;
 logic req_valid=0,req_ready,rsp_valid,rsp_ready=0;
 logic [31:0] req_id=0,rsp_id,byte_addresses[32],input_words[32],output_words[32];
 logic [5:0] request_packages;int outstanding,cycle=0,received=0,checks=0;
 int earliest[20],last_service=0;
 logic held=0;logic [31:0] held_id,held_words[32];
 warp_shared_read_service #(.SLOTS(4),.SERVICE_INTERVAL(INTERVAL),.RETURN_DELAY(DELAY)) dut(.*);
 function automatic int work(input int id);
  case(id)1:return 1;2:return 2;3:return 4;4:return 32;default:return 1;endcase
 endfunction
 task automatic pattern(input int id);
  req_id=id;
  for(int lane=0;lane<32;lane++)begin
   case(id)
    1:byte_addresses[lane]=0;
    2:byte_addresses[lane]=4*lane*2;
    3:byte_addresses[lane]=4*lane*4;
    4:byte_addresses[lane]=4*lane*32;
    default:byte_addresses[lane]=4*lane;
   endcase
   input_words[lane]=32'(id*1000+(id==1?0:lane));
  end
 endtask
 always @(posedge clk)begin
  cycle++;
  if(!rst)begin
   if(req_valid&&req_ready)begin
    int first_service;first_service=cycle+1;
    if(last_service+INTERVAL>first_service)first_service=last_service+INTERVAL;
    last_service=first_service+(work(int'(req_id))-1)*INTERVAL;
    earliest[req_id]=last_service+DELAY+1;
    if(int'(request_packages)!=work(int'(req_id)))$fatal(1,"Bank work mismatch");
   end
   if(rsp_valid&&rsp_ready)begin
    if(cycle<earliest[rsp_id])$fatal(1,"Result arrived before service/return");
    if(rsp_id==9&&cycle!=earliest[9])$fatal(1,"Isolated completion edge mismatch");
    received++;
    if(rsp_id!=9&&rsp_id!=32'(received))$fatal(1,"Response order/identity mismatch");
    for(int lane=0;lane<32;lane++)begin
     if(output_words[lane]!=32'(int'(rsp_id)*1000+(rsp_id==1?0:lane)))$fatal(1,"Snapshot data mismatch");
     checks++;
    end
   end
  end
 end
 always @(negedge clk)begin
  if(rst)held=0;
  else begin
   if(held)begin
    if(!rsp_valid||rsp_id!=held_id)$fatal(1,"Stalled response changed");
    for(int lane=0;lane<32;lane++)if(output_words[lane]!=held_words[lane])$fatal(1,"Stalled data changed");
   end
   held=rsp_valid&&!rsp_ready;held_id=rsp_id;
   for(int lane=0;lane<32;lane++)held_words[lane]=output_words[lane];
  end
 end
 initial begin
  pattern(1);repeat(2)@(negedge clk);rst=0;
  if($test$plusargs("misaligned"))begin
   byte_addresses[0]=1;req_valid=1;repeat(3)@(negedge clk);$fatal(1,"Expected rejection missing");
  end
  if($test$plusargs("broadcast"))begin
   input_words[1]=0;req_valid=1;repeat(3)@(negedge clk);$fatal(1,"Expected broadcast rejection missing");
  end
  for(int id=1;id<=4;id++)begin
   pattern(id);req_valid=1;do @(negedge clk);while(!req_ready&&outstanding<4);
   // No response is consumed in this phase; four slots fill on consecutive edges.
  end
  req_valid=0;
  if(outstanding!=4||req_ready)$fatal(1,"Capacity not enforced");
  if($test$plusargs("duplicate"))begin
   // Clear queue then submit identical IDs while both are live.
   rst=1;@(negedge clk);rst=0;pattern(1);req_valid=1;
   repeat(4)@(negedge clk);$fatal(1,"Expected duplicate rejection missing");
  end
  for(int lane=0;lane<32;lane++)input_words[lane]='1;
  repeat(20)@(negedge clk);rsp_ready=1;
  wait(received==4);@(negedge clk);rsp_ready=0;
  // Reset cancels an accepted request; it must never return later.
  pattern(8);req_valid=1;@(negedge clk);req_valid=0;rst=1;
  repeat(2)@(negedge clk);rst=0;last_service=0;
  pattern(9);req_valid=1;@(negedge clk);req_valid=0;rsp_ready=1;
  wait(received==5);@(negedge clk);
  repeat(10)@(negedge clk);
  if(outstanding!=0||rsp_valid)$fatal(1,"Reset or retirement leak");
  $display("SHARED_SERVICE_PASS checks=%0d interval=%0d delay=%0d",checks,INTERVAL,DELAY);$finish;
 end
 initial begin #100000;$fatal(1,"Timeout");end
endmodule
