// Extracted executable baseline; physical GPU parameters remain provisional.
module shared_memory_bank #(parameter int WORDS=64,LATENCY=1)(
 input logic clk,rst,req_valid,output logic req_ready,input logic write,
 input int word_address,input logic [31:0] write_data,output logic rsp_valid,
 input logic rsp_ready,output logic [31:0] read_data);
 logic [31:0] storage[WORDS]; logic occupied;int remaining;
 assign req_ready=!occupied;
 assign rsp_valid=occupied&&remaining==0;
 always_ff @(posedge clk) begin
  if(rst) begin occupied<=0;remaining<=0;read_data<=0;for(int i=0;i<WORDS;i++) storage[i]<=0;end
  else begin
   if(occupied&&remaining>0) remaining<=remaining-1;
   if(rsp_valid&&rsp_ready) occupied<=0;
   if(req_valid&&req_ready) begin
    if(word_address<0||word_address>=WORDS||LATENCY<1) $fatal(1,"Invalid shared access");
    else begin
     occupied<=1;remaining<=LATENCY-1;
     if(write) begin storage[word_address]<=write_data;read_data<=write_data;end
     else read_data<=storage[word_address];
    end
   end
  end
 end
endmodule
