module hub_component_top(input logic clk,rst,input logic[1:0]candidate_valid,rsp_ready,input logic[31:0]candidate_id[2],addresses[2][32],output logic[1:0]candidate_grant,rsp_valid,output logic[31:0]rsp_id[2],output int outstanding,client_outstanding[2]);
 logic[31:0]words[2][32],result_words[2][32];for(genvar c=0;c<2;c++)for(genvar l=0;l<32;l++)assign words[c][l]=0;
 large_shared_read_candidate_hub #(.CLIENTS(2),.SLOTS(2),.SERVICE_INTERVAL(2),.RETURN_DELAY(28)) hub(.clk,.rst,.candidate_valid,.candidate_grant,.candidate_id,.byte_addresses(addresses),.input_words(words),.rsp_valid,.rsp_ready,.rsp_id,.output_words(result_words),.outstanding,.client_outstanding);
endmodule
