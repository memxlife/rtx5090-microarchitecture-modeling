// Software address layout reconstructed from the selected library kernel.
// These constants do not identify private GPU hardware capacities.
package library_shared_layout;
  localparam integer SHARED_BYTES=37376;
  localparam integer A_PITCH=528, A_ROWS=32, A_STAGE_K=128;
  localparam integer B_PITCH=80, B_ROWS=128, B_COLUMNS=32;
  localparam integer B_START=16896, B_SLOT=10240;
  function automatic integer producer_a(input integer thread_id, slot, group_id);
    begin
      if(thread_id<0 || thread_id>=128 || slot<0 || slot>=2 || group_id<0 || group_id>=4)
        $fatal(1,"producer_a index outside layout contract");
      producer_a=A_PITCH*(thread_id/16)+16*(thread_id%16)+256*slot+4224*group_id;
    end
  endfunction
  function automatic integer producer_b(input integer thread_id, slot, group_id);
    begin
      if(thread_id<0 || thread_id>=128 || slot<0 || slot>=2 || group_id<0 || group_id>=4)
        $fatal(1,"producer_b index outside layout contract");
      producer_b=B_START+B_PITCH*(thread_id/4)+16*(thread_id%4)+B_SLOT*slot+2560*group_id;
    end
  endfunction
  function automatic integer consumer_a(input integer warp_id, lane, slot, kstep, word_id);
    integer delta;
    begin
      if(warp_id<0 || warp_id>=4 || lane<0 || lane>=32 || slot<0 || slot>=2 || kstep<0 || kstep>=8 || word_id<0 || word_id>=4)
        $fatal(1,"consumer_a index outside layout contract");
      case(word_id) 0:delta=0;1:delta=4224;2:delta=16;3:delta=4240;endcase
      consumer_a=8448*(warp_id%2)+256*slot+32*kstep+A_PITCH*(lane/4)+4*(lane%4)+delta;
    end
  endfunction
  function automatic integer consumer_b(input integer warp_id, lane, slot, kstep, word_id);
    integer delta;
    begin
      if(warp_id<0 || warp_id>=4 || lane<0 || lane>=32 || slot<0 || slot>=2 || kstep<0 || kstep>=8 || word_id<0 || word_id>=4)
        $fatal(1,"consumer_b index outside layout contract");
      case(word_id) 0:delta=0;1:delta=640;2:delta=16;3:delta=656;endcase
      consumer_b=32*(warp_id/2)+B_SLOT*slot+1280*kstep+B_START+B_PITCH*(lane/4)+4*(lane%4)+delta;
    end
  endfunction
endpackage
