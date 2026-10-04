module native_ldsm_decode_tb;
 logic [63:0] low_word,high_word;logic supported,transpose;
 logic [2:0] register_words;logic [7:0] destination_register,address_register;
 logic [63:0] lows[8],highs[8];int widths[8],transposes[8],destinations[8],addresses[8];string directory;
 native_ldsm_decode dut(.*);
 initial begin
  if(!$value$plusargs("vectors=%s",directory)) $fatal(1,"Missing decoder vectors");
  $readmemh({directory,"/lows.hex"},lows);$readmemh({directory,"/highs.hex"},highs);
  $readmemh({directory,"/widths.hex"},widths);$readmemh({directory,"/transposes.hex"},transposes);
  $readmemh({directory,"/destinations.hex"},destinations);$readmemh({directory,"/addresses.hex"},addresses);
  for(int i=0;i<8;i++) begin
   low_word=lows[i];high_word=highs[i];#1;
   if(!supported||int'(register_words)!=widths[i]||int'(transpose)!=transposes[i]||
      int'(destination_register)!=destinations[i]||int'(address_register)!=addresses[i]) $fatal(1,"Observed native descriptor mismatch");
  end
  low_word=lows[0];high_word=highs[0]|64'h300;#1;if(supported)$fatal(1,"Reserved width");
  high_word=highs[0]|64'h8000;#1;if(supported)$fatal(1,"Unknown format");
  high_word=highs[0];low_word=lows[0]|64'h100000000;#1;if(supported)$fatal(1,"Address offset not supported");
  low_word=0;#1;if(supported)$fatal(1,"Other opcode");
  low_word=lows[0]|64'hff000000;#1;if(supported)$fatal(1,"RZ address unsupported");
  $display("PASS:8 native descriptors and5 unsupported forms");$finish;
 end
endmodule
