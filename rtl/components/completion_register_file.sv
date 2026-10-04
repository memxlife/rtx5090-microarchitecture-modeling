// Simulation contract, not a recovered RTX register-bank implementation.
module completion_register_file #(parameter int REGS=64)(
 input logic clk,rst,
 input int source_a,source_b,input logic use_a,use_b,
 output logic operands_ready,output logic [31:0] operand_a,operand_b,
 input logic reserve_valid,output logic reserve_ready,
 input int destination,input logic [31:0] reservation_id,
 input logic complete_valid,input int complete_destination,
 input logic [31:0] complete_id,complete_data,
 output int pending_count
);
 logic initialized[REGS],pending[REGS];
 logic [31:0] values[REGS],owners[REGS];
 logic sources_in_range,destination_in_range;
 initial if(REGS<2) $fatal(1,"Register capacity must be at least two");
 always_comb begin
  operand_a=0;operand_b=0;operands_ready=!rst;
  sources_in_range=(!use_a||(source_a>=0&&source_a<REGS))&&
                   (!use_b||(source_b>=0&&source_b<REGS));
  if(!sources_in_range) operands_ready=0;
  if(use_a&&source_a>=0&&source_a<REGS) begin
   operand_a=values[source_a];
   operands_ready=operands_ready&&initialized[source_a]&&!pending[source_a];
  end
  if(use_b&&source_b>=0&&source_b<REGS) begin
   operand_b=values[source_b];
   operands_ready=operands_ready&&initialized[source_b]&&!pending[source_b];
  end
  destination_in_range=destination>0&&destination<REGS;
  reserve_ready=0;
  if(destination_in_range) reserve_ready=!rst&&!pending[destination];
  pending_count=0;
  for(int r=0;r<REGS;r++) if(pending[r]) pending_count++;
 end
 always_ff @(posedge clk) begin
  if(rst) begin
   for(int r=0;r<REGS;r++) begin
    initialized[r]<=(r==0);pending[r]<=0;values[r]<=0;owners[r]<=0;
   end
  end else begin
   // A completion must match an existing reservation before this edge.
   if(complete_valid) begin
    if(complete_destination<=0||complete_destination>=REGS)
     $fatal(1,"Completion destination outside writable register range");
    else if(!pending[complete_destination]||owners[complete_destination]!=complete_id)
     $fatal(1,"Completion has no matching pending reservation");
    else begin
     values[complete_destination]<=complete_data;
     initialized[complete_destination]<=1;pending[complete_destination]<=0;
    end
   end
   if(reserve_valid) begin
    if(!destination_in_range) $fatal(1,"Reservation destination outside writable register range");
    else if(reserve_ready) begin
     for(int r=1;r<REGS;r++)
      if(pending[r]&&owners[r]==reservation_id)
       $fatal(1,"Duplicate outstanding reservation identity");
     owners[destination]<=reservation_id;pending[destination]<=1;
    end
   end
  end
 end
 // No same-edge completion bypass. A held reservation may proceed next edge.
 // Register zero is the model's immutable zero source, not an RTX allocation fact.
endmodule
