// Functional generic shared-word operand delivery with measured MOVM mapping.
// Plain generic shared-word reads and measured MOVM permutation; no LDSM.
// Reads are ideal collective snapshots. Generic-load/MOVM service timing,
// native hot-loop control, and private queues are NOT implemented here.
module generic_shared_matrix_pipeline #(
 parameter int SHARED_BYTES=37376,SLOTS=2,LATENCY=16,INTERVAL=4,ARITHMETIC_MODE=1
)(
 input logic clk,rst,
 input logic write_valid,output logic write_ready,
 input logic [31:0] write_byte_address,input logic [15:0] write_data,
 input logic req_valid,output logic req_ready,input logic [31:0] req_id,
 input logic [31:0] a_word_addresses[32][4],b_word_addresses[32][4],
 input logic [31:0] c_registers[32][8],
 output logic operands_initialized,addresses_legal,
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,result_registers[32][8],output int outstanding
);
 localparam int HALFWORDS=SHARED_BYTES/2;
 logic [15:0] memory[HALFWORDS];logic initialized[HALFWORDS];
 logic [15:0] raw_b[256];
 logic [31:0] a_registers[32][4],b_registers[32][4];
 int a_indices[32][4],b_indices[32][4];
 logic matrix_ready;
 initial if(SHARED_BYTES<4||SHARED_BYTES%2!=0)
  $fatal(1,"Library shared storage too small or not halfword aligned");
 assign write_ready=!rst&&write_byte_address[0]==0&&write_byte_address<=SHARED_BYTES-2;
 assign req_ready=!rst&&addresses_legal&&operands_initialized&&matrix_ready;
 always_comb begin
  addresses_legal=1;operands_initialized=1;
  for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)begin
   a_indices[lane][word]=int'(a_word_addresses[lane][word]/2);
   b_indices[lane][word]=int'(b_word_addresses[lane][word]/2);
   if(a_word_addresses[lane][word][1:0]!=0||b_word_addresses[lane][word][1:0]!=0||
      a_word_addresses[lane][word]>SHARED_BYTES-4||b_word_addresses[lane][word]>SHARED_BYTES-4||
      a_indices[lane][word]<0||a_indices[lane][word]+1>=HALFWORDS||
      b_indices[lane][word]<0||b_indices[lane][word]+1>=HALFWORDS)addresses_legal=0;
  end
  for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)begin
   a_registers[lane][word]=0;b_registers[lane][word]=0;
   for(int halfword=0;halfword<2;halfword++)begin
    raw_b[lane*8+word*2+halfword]=0;
    if(addresses_legal)begin
     operands_initialized=operands_initialized&&
      initialized[a_indices[lane][word]+halfword]&&initialized[b_indices[lane][word]+halfword];
     if(initialized[a_indices[lane][word]+halfword])
      a_registers[lane][word][halfword*16+:16]=memory[a_indices[lane][word]+halfword];
     if(initialized[b_indices[lane][word]+halfword])
      raw_b[lane*8+word*2+halfword]=memory[b_indices[lane][word]+halfword];
    end
   end
  end
  // The table maps each post-transpose destination halfword to a raw source.
  for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)
   for(int halfword=0;halfword<2;halfword++)
    b_registers[lane][word][halfword*16+:16]=
     raw_b[library_movm_permutation::pre_index(lane*8+word*2+halfword)];
  if(!addresses_legal)operands_initialized=0;
 end
 always_ff @(posedge clk)begin
  if(rst)begin for(int i=0;i<HALFWORDS;i++)initialized[i]<=0;end
  else begin
   if(write_valid&&!write_ready)$fatal(1,"Invalid library shared write address");
   if(req_valid&&!addresses_legal)$fatal(1,"Invalid library matrix operand address");
   if(write_valid&&write_ready)begin
    memory[write_byte_address/2]<=write_data;initialized[write_byte_address/2]<=1;
   end
  end
 end
 native_bf16_adapter #(.SLOTS(SLOTS),.LATENCY(LATENCY),.INTERVAL(INTERVAL),
  .ARITHMETIC_MODE(ARITHMETIC_MODE)) matrix(
  .clk,.rst,.req_valid(req_valid&&addresses_legal&&operands_initialized),.req_ready(matrix_ready),
  .req_id,.a_registers,.b_registers,.c_registers,
  .rsp_valid,.rsp_ready,.rsp_id,.result_registers,.outstanding
 );
 // Adapter snapshots all values at acceptance. Same-edge writes use pre-edge
 // memory: a final initializing write permits admission only on a later edge.
endmodule
