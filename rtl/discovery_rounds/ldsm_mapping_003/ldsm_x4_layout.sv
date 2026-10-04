// Functional address placement observed on sm120, four 8x8 b16 matrices.
// Each source lane supplies one 16-byte-aligned row address.
// No latency, pipeline or physical bank-port assumptions are introduced.
package ldsm_x4_layout;
 function automatic int source_lane(input bit transpose, input int out_lane, input int word, input int halfword);
  if(transpose) return word*8 + 2*(out_lane%4) + halfword;
  return word*8 + out_lane/4;
 endfunction
 function automatic int byte_offset(input bit transpose, input int out_lane, input int halfword);
  if(transpose) return 2*(out_lane/4);
  return 4*(out_lane%4)+2*halfword;
 endfunction
endpackage
