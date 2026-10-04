module native_component_top #(parameter int CONTEXTS=1)(input logic clk,rst,write_valid,input logic[31:0]write_context,write_base,input logic req_valid,input logic[31:0]req_context,output logic issue_valid,output logic[31:0]issue_warp,issue_pc,output logic completion_valid,output logic[31:0]completion_warp,completion_pc);
 logic grant,cv,rv,rr;logic[31:0]cid,addr[32],words[32],rid,rwords[32],wa[32];logic[15:0]wd[32];logic[31:0]cregs[4][32][8];int outstanding;
 for(genvar i=0;i<32;i++)begin assign wa[i]=write_base+2*i;assign wd[i]=0;end
 for(genvar w=0;w<4;w++)for(genvar l=0;l<32;l++)for(genvar k=0;k<8;k++)assign cregs[w][l][k]=0;
 logic[31:0]ctx,warp,pc;
 large_native_stage_shared #(.CONTEXTS(CONTEXTS),.ALLOW_WARP_WRITES(1),.READ_SLOTS(2),.RETURN_DELAY(9),.MOVM_LATENCY(19),.HMMA_LATENCY(73),.HMMA_INTERVAL(4)) stage(
 .clk,.rst,.read_candidate_valid(cv),.read_candidate_grant(grant),.read_candidate_id(cid),.read_candidate_byte_addresses(addr),.read_candidate_input_words(words),.read_rsp_valid(rv),.read_rsp_ready(rr),.read_rsp_id(rid),.read_rsp_words(rwords),.read_client_outstanding(outstanding),.write_context,.write_valid(1'b0),.write_byte_address(0),.write_data(0),.write_warp_valid(write_valid),.write_warp_byte_addresses(wa),.write_warp_halfwords(wd),.write_warp_mask(32'hffffffff),.req_valid,.req_context,.req_id(req_context),.c_registers(cregs),.rsp_ready(1'b1),.native_issue_valid(issue_valid),.native_issue_context(ctx),.native_issue_warp(warp),.native_issue_pc(pc));
 assign issue_warp=ctx*4+warp;assign issue_pc=(pc-32'h1350)/16;
 assign completion_valid=stage.completion_valid;assign completion_warp=stage.completion_warp;assign completion_pc=stage.completion_pc;
 logic ready;assign grant=cv&&ready;
 large_warp_shared_read_service #(.SLOTS(2),.SERVICE_INTERVAL(1),.RETURN_DELAY(9)) service(.clk,.rst,.req_valid(cv),.req_ready(ready),.req_id(cid),.byte_addresses(addr),.input_words(words),.rsp_valid(rv),.rsp_ready(rr),.rsp_id(rid),.output_words(rwords),.outstanding);
endmodule
