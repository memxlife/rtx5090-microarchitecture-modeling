// Observed sm120/CUDA12.8 BF16 WMMA row-major m16n16k16 layout.
// Describes operand contents, not physical register-bank routing or latency.
package native_bf16_layout;
  function automatic int a_element_index(input int lane, input int element);
    int row, col;
    row = lane / 4 + 8 * ((element / 2) % 2);
    col = 2 * (lane % 4) + element % 2 + 8 * (element / 4);
    return row * 16 + col;
  endfunction
  function automatic int b_element_index(input int lane, input int element);
    int row, col;
    row = 2 * (lane % 4) + element % 2 + 8 * ((element / 2) % 2);
    col = lane / 4 + 8 * (element / 4);
    return row * 16 + col;
  endfunction
  function automatic int c_element_index(input int lane, input int element);
    return a_element_index(lane, element);
  endfunction
  function automatic int native_c_element(input int hmma_half, input int word);
    return 4 * hmma_half + word;
  endfunction
  function automatic int native_b_word(input int hmma_half, input int word);
    return 2 * hmma_half + word;
  endfunction
endpackage
