module shared_broadcast_work_tb;
 logic [31:0] active_mask,common_byte_address=0;
 logic address_legal;logic [1:0] service_packages;
 logic [31:0] masks[10]='{32'hff,32'h11111111,32'hffff,32'h55555555,
  32'hffffffff,32'hff000000,32'hffff0000,32'h00ffff00,32'h80000001,32'h80000000};
 int expected[10]='{1,2,1,2,2,1,1,2,2,1};
 shared_broadcast_work dut(.*);
 initial begin
  for(int c=0;c<10;c++) begin
   active_mask=masks[c];#1;
   if(!address_legal||int'(service_packages)!=expected[c]) $fatal(1,"Measured service-work mismatch");
  end
  active_mask=0;#1;if(service_packages!=0) $fatal(1,"Empty mask");
  active_mask='1;common_byte_address=4;#1;
  if(address_legal||service_packages!=0) $fatal(1,"Unaligned request accepted");
  $display("PASS:10 measured masks, empty mask and invalid alignment");$finish;
 end
endmodule
