// Extracted executable baseline; physical GPU parameters remain provisional.
module timed_queue #(
  parameter int SLOTS=4, LATENCY=1, INTERVAL=1
)(input logic clk,rst, input logic req_valid, output logic req_ready,
  input logic [31:0] req_id, output logic rsp_valid,input logic rsp_ready,
  output logic [31:0] rsp_id);
  int cycle,count,head,tail,next_accept;
  int due[SLOTS]; logic [31:0] ids[SLOTS];
  wire push=req_valid&&req_ready, pop=rsp_valid&&rsp_ready;
  assign req_ready=(count<SLOTS)&&(cycle>=next_accept);
  assign rsp_valid=(count>0)&&(cycle>=due[head]);
  assign rsp_id=ids[head];
  initial if(SLOTS<1||LATENCY<1||INTERVAL<1) $fatal(1,"Invalid timing queue configuration");
  always_ff @(posedge clk) begin
    if(rst) begin cycle<=0;count<=0;head<=0;tail<=0;next_accept<=0;end
    else begin
      cycle<=cycle+1;
      if(push) begin ids[tail]<=req_id;due[tail]<=cycle+LATENCY;tail<=(tail+1)%SLOTS;next_accept<=cycle+INTERVAL;end
      if(pop) head<=(head+1)%SLOTS;
      case({push,pop}) 2'b10:count<=count+1;2'b01:count<=count-1;default:count<=count;endcase
    end
  end
endmodule
