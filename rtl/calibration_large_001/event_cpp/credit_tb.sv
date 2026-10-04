module credit_tb;
localparam int SMS=170;bit clk=0,rst=1;logic[SMS-1:0]read_req_valid,write_req_valid,read_req_ready,write_req_ready;int cache_read_rate_q10=37481,cache_write_rate_q10=31056,cache_mixed_rate_q10=49089;int fd,of,status;
 logic[SMS-1:0] permitted_read,permitted_write;
 longint read_credit,write_credit,mixed_credit;
 int service_cursor;
 always_comb begin
  longint r,w,t;r=read_credit+cache_read_rate_q10;w=write_credit+cache_write_rate_q10;t=mixed_credit+cache_mixed_rate_q10;
  permitted_read=0;permitted_write=0;
  for(int off=0;off<SMS;off++)begin
   int sm;sm=(service_cursor+off)%SMS;
   if(read_req_valid[sm]&&r>=1024&&t>=1024)begin permitted_read[sm]=1;r-=1024;t-=1024;end
   if(write_req_valid[sm]&&w>=1024&&t>=1024)begin permitted_write[sm]=1;w-=1024;t-=1024;end
  end
 end
 always_ff @(posedge clk)begin
  if(rst)begin read_credit<=0;write_credit<=0;mixed_credit<=0;service_cursor<=0;end
  else begin
   longint r,w,t;r=read_credit+cache_read_rate_q10;w=write_credit+cache_write_rate_q10;t=mixed_credit+cache_mixed_rate_q10;
   for(int sm=0;sm<SMS;sm++)begin
    if(read_req_valid[sm]&&read_req_ready[sm])begin r-=1024;t-=1024;end
    if(write_req_valid[sm]&&write_req_ready[sm])begin w-=1024;t-=1024;end
   end
   read_credit<=r<cache_read_rate_q10?r:cache_read_rate_q10;
   write_credit<=w<cache_write_rate_q10?w:cache_write_rate_q10;
   mixed_credit<=t<cache_mixed_rate_q10?t:cache_mixed_rate_q10;
   service_cursor<=(service_cursor+1)%SMS;
  end
 end

initial begin #1;clk=1;#1;clk=0;rst=0;fd=$fopen("credit_stim.txt","r");of=$fopen("credit_actual.txt","w");while(!$feof(fd))begin status=$fscanf(fd,"%h %h %h %h\n",read_req_valid,write_req_valid,read_req_ready,write_req_ready);if(status==4)begin #1;$fwrite(of,"%043h %043h\n",permitted_read,permitted_write);clk=1;#1;clk=0;end end $fclose(of);$finish;end
endmodule
