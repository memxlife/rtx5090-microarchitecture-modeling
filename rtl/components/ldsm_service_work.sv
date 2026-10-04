// Inferred LDSM x1/x2/x4 all-lane aligned-row service work, not latency.
// Count provider groups separately; identical rows within a group are merged.
module ldsm_service_work(
 input logic [31:0] row_byte_addresses[32],
 input logic [2:0] matrix_count,
 output logic request_legal,output logic [5:0] service_packages
);
 always_comb begin
  request_legal=matrix_count==1||matrix_count==2||matrix_count==4;
  for(int lane=0;lane<32;lane++)
   if(row_byte_addresses[lane][3:0]!=0) request_legal=0;
  service_packages=0;
  if(request_legal) for(int group=0;group<4;group++) begin
   int group_max;group_max=0;
   if(group<int'(matrix_count)) begin
    for(int quartet=0;quartet<8;quartet++) begin
     int distinct_rows;distinct_rows=0;
     for(int row=0;row<8;row++) begin
      bit unique_row;unique_row=1;
      for(int earlier=0;earlier<row;earlier++)
       if(row_byte_addresses[group*8+row]==row_byte_addresses[group*8+earlier]) unique_row=0;
      if(unique_row&&int'(row_byte_addresses[group*8+row][6:4])==quartet)
       distinct_rows++;
     end
     if(distinct_rows>group_max) group_max=distinct_rows;
    end
    service_packages=6'(int'(service_packages)+group_max);
   end
  end
 end
endmodule
