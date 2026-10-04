// Measured scalar generic-load value semantics; no timing or queue policy.
module scalar_load_result(
 input logic [31:0] raw_value,
 input logic [5:0] width_bits,
 input logic signed_load,
 output logic [31:0] register_value,
 output logic supported
);
 always_comb begin
  supported=1'b1;
  case(width_bits)
   6'd8: register_value=signed_load ? {{24{raw_value[7]}},raw_value[7:0]} : {24'b0,raw_value[7:0]};
   6'd16: register_value=signed_load ? {{16{raw_value[15]}},raw_value[15:0]} : {16'b0,raw_value[15:0]};
   6'd32: register_value=raw_value;
   default: begin register_value='0;supported=1'b0;end
  endcase
 end
endmodule
