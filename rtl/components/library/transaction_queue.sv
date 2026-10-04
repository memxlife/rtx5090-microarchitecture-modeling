// Extracted executable baseline; physical GPU parameters remain provisional.
module transaction_queue #(parameter int SLOTS=4,LATENCY=1,INTERVAL=1)(
 input logic clk,rst,req_valid,output logic req_ready,input logic [31:0] req_id,
 output logic rsp_valid,input logic rsp_ready,output logic [31:0] rsp_id);
 // Capacity and return backpressure; lane coalescing must be supplied upstream.
 timed_queue #(.SLOTS(SLOTS),.LATENCY(LATENCY),.INTERVAL(INTERVAL)) queue(.*);
endmodule
