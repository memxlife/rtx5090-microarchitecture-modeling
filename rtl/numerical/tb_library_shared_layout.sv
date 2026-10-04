module tb_library_shared_layout;
  import library_shared_layout::*;
  integer fd,ret,kind,a,b,c,d,e,expected,actual,count;
  string vectors;
  initial begin
    if($test$plusargs("invalid"))begin actual=producer_a(128,0,0);$fatal(1,"Missing invalid index rejection");end
    if(!$value$plusargs("VECTORS=%s",vectors)) $fatal(1,"Missing VECTORS file");
    fd=$fopen(vectors,"r");if(!fd)$fatal(1,"Cannot open vectors");count=0;
    while(!$feof(fd)) begin
      ret=$fscanf(fd,"%d %d %d %d %d %d %d\n",kind,a,b,c,d,e,expected);
      if(ret==7) begin
        case(kind)
          0:actual=producer_a(a,b,c);
          1:actual=producer_b(a,b,c);
          2:actual=consumer_a(a,b,c,d,e);
          3:actual=consumer_b(a,b,c,d,e);
          default:$fatal(1,"Invalid vector kind");
        endcase
        if(actual!==expected)$fatal(1,"Layout mismatch kind=%0d actual=%0d expected=%0d",kind,actual,expected);
        count=count+1;
      end else if(ret!=-1)$fatal(1,"Malformed vector");
    end
    $fclose(fd);if(count!=18432)$fatal(1,"Unexpected test count %0d",count);
    if(SHARED_BYTES!=37376)$fatal(1,"Footprint mismatch");
    $display("PASS %0d authoritative address checks",count);$finish;
  end
endmodule
