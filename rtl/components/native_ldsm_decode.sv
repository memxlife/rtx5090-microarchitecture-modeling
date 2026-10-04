// Partial descriptor decoder for six measured direct-register sm120 LDSM forms.
// Does not decode predicates, address offsets, scheduling controls or other opcodes.
module native_ldsm_decode(
 input logic [63:0] low_word,high_word,
 output logic supported,transpose,
 output logic [2:0] register_words,
 output logic [7:0] destination_register,address_register
);
 always_comb begin
  supported=0;transpose=0;register_words=0;
  destination_register=low_word[23:16];address_register=low_word[31:24];
  if(low_word[15:0]==16'h783b&&low_word[63:32]==0&&
     (high_word[15:0]&16'hbcff)==0&&high_word[9:8]!=3) begin
   register_words=3'(1<<high_word[9:8]);transpose=high_word[14];
   supported=int'(destination_register)+int'(register_words)<=255&&address_register!=255;
  end
 end
endmodule
