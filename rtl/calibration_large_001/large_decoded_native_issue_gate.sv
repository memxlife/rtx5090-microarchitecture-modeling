// Native control issue gate; no opcode execution or predetermined completion.
// Barrier all-producers-complete behavior is a reconstruction hypothesis.
// MAX_OPS bounds simulation tags, not physical hardware queue capacity.
// Read completion means operands consumed; write completion means result ready.
// Clients emit each event only for its allocated read/write barrier namespace.
// Completion effects become usable next cycle; same-edge tag reuse is blocked.
// A held instruction/control/tag must remain stable until instr_ready handshake.
module large_decoded_native_issue_gate #(
 parameter int MAX_OPS=16,TAG_W=$clog2(MAX_OPS+1),COUNT_W=$clog2(MAX_OPS+1)
)(
 input logic clk,reset,
 input logic instr_valid,output logic instr_ready,
 input logic [TAG_W-1:0] operation_id,
 input native_control_decode::control_t control,
 output logic dispatch_valid,input logic dispatch_ready,output logic issued,
 input logic write_complete_valid,input logic [TAG_W-1:0] write_complete_tag,
 input logic read_complete_valid,input logic [TAG_W-1:0] read_complete_tag,
 output logic [5:0] busy_write_mask,busy_read_mask,
 output logic [3:0] cooldown,output logic error_sticky
);
 logic write_ready,read_ready,write_wait_ready,read_wait_ready;
 logic write_error,read_error,local_error;
 logic [5:0][COUNT_W-1:0] write_counts,read_counts;
 logic valid_control,write_allocate,read_allocate,eligible;
 assign write_allocate=control.write_barrier!=7;
 assign read_allocate=control.read_barrier!=7;
 assign valid_control=control.write_barrier!=6&&control.read_barrier!=6&&int'(operation_id)<MAX_OPS;
 assign eligible=!reset&&valid_control&&cooldown==0&&write_wait_ready&&read_wait_ready&&
                 write_ready&&read_ready;
 assign dispatch_valid=instr_valid&&eligible;
 assign instr_ready=eligible&&dispatch_ready;
 assign issued=dispatch_valid&&dispatch_ready;
 assign error_sticky=write_error||read_error||local_error;
 always_ff @(posedge clk)begin
  if(reset)begin cooldown<=0;local_error<=0;end
  else begin
   if(instr_valid&&!valid_control)local_error<=1;
   if(issued)cooldown<=control.issue_delay>0?control.issue_delay-1'b1:4'd0;
   else if(cooldown!=0)cooldown<=cooldown-1'b1;
  end
 end
 large_producer_barrier_tracker #(.MAX_OPS(MAX_OPS),.TAG_W(TAG_W),.COUNT_W(COUNT_W)) writes(
  .clk,.reset,.issue_valid(issued&&write_allocate),.issue_ready(write_ready),
  .issue_tag(operation_id),.issue_barrier(write_allocate?control.write_barrier:3'd0),
  .complete_valid(write_complete_valid),.complete_tag(write_complete_tag),
  .wait_mask(control.wait_mask),.wait_ready(write_wait_ready),
  .busy_mask(busy_write_mask),.pending_count(write_counts),.error_sticky(write_error)
 );
 large_producer_barrier_tracker #(.MAX_OPS(MAX_OPS),.TAG_W(TAG_W),.COUNT_W(COUNT_W)) reads(
  .clk,.reset,.issue_valid(issued&&read_allocate),.issue_ready(read_ready),
  .issue_tag(operation_id),.issue_barrier(read_allocate?control.read_barrier:3'd0),
  .complete_valid(read_complete_valid),.complete_tag(read_complete_tag),
  .wait_mask(control.wait_mask),.wait_ready(read_wait_ready),
  .busy_mask(busy_read_mask),.pending_count(read_counts),.error_sticky(read_error)
 );
 // group_continue is preserved in control but not interpreted as another stall.
endmodule
