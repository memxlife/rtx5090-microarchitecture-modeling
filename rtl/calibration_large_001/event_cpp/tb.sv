module tb #(parameter int TAGS=8);
 localparam int TW=$clog2(TAGS+1);
 bit clk=0,rst=1;int t,mv,mi,mr,sv,si,sr,mode,iv,tag,bar,cv,ctag,wm,fd,outfd,status;logic mready,mvalid,sready,svalid,tready,waitready,error;logic[31:0]mid,sid;int mn,sn;logic[5:0]packs,busy;logic[5:0][TW-1:0]counts;logic[15:0]a[256],b[256];logic[31:0]c[256],r[256],addr[32],zero[32],sout[32];
 large_timing_matrix_pipeline #(.SLOTS(4),.LATENCY(7),.INTERVAL(3)) matrix(.clk,.rst,.req_valid(1'(mv)),.req_ready(mready),.req_id(32'(mi)),.a_words(a),.b_words(b),.accumulator_words(c),.rsp_valid(mvalid),.rsp_ready(1'(mr)),.rsp_id(mid),.result_words(r),.outstanding(mn));
 large_warp_shared_read_service #(.SLOTS(4),.SERVICE_INTERVAL(2),.RETURN_DELAY(3)) shared_unit(.clk,.rst,.req_valid(1'(sv)),.req_ready(sready),.req_id(32'(si)),.byte_addresses(addr),.input_words(zero),.rsp_valid(svalid),.rsp_ready(1'(sr)),.rsp_id(sid),.output_words(sout),.outstanding(sn),.request_packages(packs));
 large_producer_barrier_tracker #(.MAX_OPS(TAGS),.TAG_W(TW),.COUNT_W(TW)) tracker(.clk,.reset(rst),.issue_valid(1'(iv)),.issue_ready(tready),.issue_tag(TW'(tag)),.issue_barrier(3'(bar)),.complete_valid(1'(cv)),.complete_tag(TW'(ctag)),.wait_mask(6'(wm)),.wait_ready(waitready),.busy_mask(busy),.pending_count(counts),.error_sticky(error));
 initial begin
  for(int l=0;l<32;l++)begin zero[l]=0;addr[l]=0;end
  for(int l=0;l<256;l++)begin a[l]=0;b[l]=0;c[l]=0;end
  #1;clk=1;#1;clk=0;rst=0;
  fd=$fopen("stim.txt","r");outfd=$fopen("actual.txt","w");
  while(!$feof(fd))begin
   status=$fscanf(fd,"%d %d %d %d %d %d %d %d %d %d %d %d %d %d\n",t,mv,mi,mr,sv,si,sr,mode,iv,tag,bar,cv,ctag,wm);
   if(status==14)begin
    for(int l=0;l<32;l++)addr[l]=mode==0?0:mode==1?l*4:mode==2?l*128:(l%8)*128;
    #1;
    $fwrite(outfd,"%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",t,mv&&mready,mr&&mvalid,mvalid?mid:0,mn,sv&&sready,sr&&svalid,svalid?sid:0,sn,packs,tready,busy,waitready,error);
    for(int q=0;q<6;q++)$fwrite(outfd," %0d",counts[q]);$fwrite(outfd,"\n");
    clk=1;#1;clk=0;
   end
  end
  $fclose(fd);$fclose(outfd);$finish;
 end
endmodule
