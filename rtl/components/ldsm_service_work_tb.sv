module ldsm_service_work_tb;
 logic[31:0] row_byte_addresses[32];logic[2:0] matrix_count;
 logic request_legal;logic[5:0] service_packages;
 logic[31:0] row_file[24*32];int width_file[24],expected[24];string directory;
 ldsm_service_work dut(.*);
 initial begin
  if(!$value$plusargs("vectors=%s",directory)) $fatal(1,"Missing service vectors");
  $readmemh({directory,"/rows.hex"},row_file);$readmemh({directory,"/widths.hex"},width_file);$readmemh({directory,"/expected.hex"},expected);
  for(int c=0;c<24;c++) begin
   matrix_count=3'(width_file[c]);for(int lane=0;lane<32;lane++)row_byte_addresses[lane]=row_file[c*32+lane];#1;
   if(!request_legal||int'(service_packages)!=expected[c]) $fatal(1,"Measured LDSM service mismatch");
  end
  row_byte_addresses[0]=1;#1;if(request_legal||service_packages) $fatal(1,"Alignment rejection");
  row_byte_addresses[0]=0;matrix_count=3;#1;if(request_legal||service_packages) $fatal(1,"Width rejection");
  $display("PASS:24 measured LDSM service cases and2 invalid controls");$finish;
 end
endmodule
