// Measured/inferred service work for naturally aligned same-vector LDS.128.
// Zero-cycle combinational work decoder; neither latency nor bank-port model.
module shared_broadcast_work(
 input logic [31:0] active_mask,
 input logic [31:0] common_byte_address,
 output logic address_legal,
 output logic [1:0] service_packages
);
 assign address_legal=common_byte_address[3:0]==0;
 assign service_packages=address_legal?
   ({1'b0,|active_mask[15:0]}+{1'b0,|active_mask[31:16]}):2'b00;
endmodule
