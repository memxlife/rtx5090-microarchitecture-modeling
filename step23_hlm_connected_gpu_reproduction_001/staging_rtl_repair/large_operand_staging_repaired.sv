// Experimental compiled-producer staging adapter with external memory returns.
// Internal tick drives the behavioral C++-matched component; baseline stays separate.
module large_operand_staging #(
 parameter int CONTEXTS=2,M=64,N=96,K=64,SETS=64,WAYS=8
)(
 input logic clk,rst,req_valid,output logic req_ready,
 input logic[31:0]req_context,req_id,a_base,b_base,cta_row,cta_col,stage_index,
 output logic[CONTEXTS-1:0]context_ready,output int outstanding,
 output logic write_warp_valid,input logic write_warp_ready,
 output logic[31:0]write_context,write_warp_byte_addresses[32],write_warp_mask,
 output logic[15:0]write_warp_halfwords[32],
 output logic done_valid,input logic done_ready,output logic[31:0]done_context,done_id,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic[31:0]backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic[31:0]backing_rsp_id,input logic[255:0]backing_rsp_data
);
 logic [63:0] tick;
 always @(posedge clk) if(rst) tick<=0; else tick<=tick+1;
 assign backing_rsp_ready=1;
 assign write_warp_mask='1;
 repaired_staging #(.CONTEXTS(CONTEXTS),.M(M),.N(N),.K(K)) core(
 .clk(clk),.rst(rst),.cycle(tick),.req_valid(req_valid),.req_ready(req_ready),
 .req_context(req_context),.req_id(req_id),.a_base(a_base),.b_base(b_base),.cta_row(cta_row),.cta_col(cta_col),.stage_index(stage_index),
 .context_ready(context_ready),.outstanding(outstanding),
 .backing_valid(backing_req_valid),.backing_ready(backing_req_ready),.backing_id(backing_req_id),.backing_address(backing_req_byte_address),
 .backing_context(),.backing_group(),.backing_sector(),
 .response_valid(backing_rsp_valid),.response_id(backing_rsp_id),.response_data(backing_rsp_data),
 .write_valid(write_warp_valid),.write_ready(write_warp_ready),.write_context(write_context),.write_addresses(write_warp_byte_addresses),.write_halfwords(write_warp_halfwords),
 .done_valid(done_valid),.done_ready(done_ready),.done_context(done_context),.done_id(done_id),
 .sector_count(),.commit_count(),.completion_count(),.instruction_count());
endmodule
