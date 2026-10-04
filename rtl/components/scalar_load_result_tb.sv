module scalar_load_result_tb;
 logic [31:0] raw_value,register_value,expected;
 logic [5:0] width_bits;logic signed_load,supported;
 integer values[8]='{0,1,127,128,255,32767,32768,65535};
 scalar_load_result dut(.*);
 initial begin
  for(int i=0;i<8;i++)begin
   raw_value=32'habcd0000|values[i];
   for(int w=0;w<3;w++)for(int s=0;s<2;s++)begin
    width_bits=w==0?8:w==1?16:32;signed_load=s;
    if(w==0)expected=s?32'($signed(raw_value[7:0])):{24'b0,raw_value[7:0]};
    else if(w==1)expected=s?32'($signed(raw_value[15:0])):{16'b0,raw_value[15:0]};
    else expected=raw_value;
    #1;if(!supported||register_value!==expected)$fatal(1,"extension mismatch");
   end
  end
  width_bits=24;#1;if(supported)$fatal(1,"unsupported width accepted");
  $display("48 scalar value checks and unsupported width passed");$finish;
 end
endmodule
