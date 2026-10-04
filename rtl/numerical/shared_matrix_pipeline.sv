// Clocked shared-value storage connected to measured LDSM operand placement.
// Logical single-halfword write port and ideal collective reads are model choices.
// Shared-service latency, bank arbitration and separate LDSM completion are absent.
module shared_matrix_pipeline #(
 parameter int SHARED_BYTES=102400,SLOTS=2,LATENCY=17,INTERVAL=3,ARITHMETIC_MODE=0
)(
 input logic clk,rst,
 input logic write_valid,output logic write_ready,
 input logic [31:0] write_byte_address,input logic [15:0] write_data,
 input logic req_valid,output logic req_ready,input logic [31:0] req_id,
 input logic [31:0] a_row_addresses[32],b_row_addresses[32],
 input logic [31:0] c_registers[32][8],
 output logic operands_initialized,addresses_legal,
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,result_registers[32][8],output int outstanding
);
 localparam int HALFWORDS=SHARED_BYTES/2;
 logic [15:0] memory[HALFWORDS];logic initialized[HALFWORDS];
 logic [31:0] a_registers[32][4],b_registers[32][4];
 logic matrix_ready;
 initial if(SHARED_BYTES<1024||SHARED_BYTES%16)
  $fatal(1,"Shared region must be a multiple of16 bytes and at least1024 bytes");
 assign write_ready=!rst&&write_byte_address[0]==0&&write_byte_address<=SHARED_BYTES-2;
 assign req_ready=!rst&&addresses_legal&&operands_initialized&&matrix_ready;
 always_comb begin
  addresses_legal=1;operands_initialized=1;
  for(int lane=0;lane<32;lane++) begin
   if(a_row_addresses[lane][3:0]!=0||a_row_addresses[lane]>SHARED_BYTES-16||
      b_row_addresses[lane][3:0]!=0||b_row_addresses[lane]>SHARED_BYTES-16)
    addresses_legal=0;
  end
  for(int lane=0;lane<32;lane++) for(int word=0;word<4;word++) begin
   a_registers[lane][word]=0;b_registers[lane][word]=0;
   if(addresses_legal) for(int halfword=0;halfword<2;halfword++) begin
    int a_index,b_index;
    a_index=int'(a_row_addresses[ldsm_x4_layout::source_lane(0,lane,word,halfword)])/2+
      ldsm_x4_layout::byte_offset(0,lane,halfword)/2;
    b_index=int'(b_row_addresses[ldsm_x4_layout::source_lane(1,lane,word,halfword)])/2+
      ldsm_x4_layout::byte_offset(1,lane,halfword)/2;
    operands_initialized=operands_initialized&&initialized[a_index]&&initialized[b_index];
    if(initialized[a_index]) a_registers[lane][word][16*halfword+:16]=memory[a_index];
    if(initialized[b_index]) b_registers[lane][word][16*halfword+:16]=memory[b_index];
   end
  end
  if(!addresses_legal) operands_initialized=0;
 end
 always_ff @(posedge clk) begin
  if(rst) begin
   for(int i=0;i<HALFWORDS;i++) initialized[i]<=0;
  end else begin
   if(write_valid&&!write_ready) $fatal(1,"Invalid shared write address");
   if(req_valid&&!addresses_legal) $fatal(1,"Invalid LDSM row address");
   if(write_valid&&write_ready) begin
    memory[write_byte_address/2]<=write_data;initialized[write_byte_address/2]<=1;
   end
  end
 end
 native_bf16_adapter #(.SLOTS(SLOTS),.LATENCY(LATENCY),.INTERVAL(INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) matrix (
  .clk,.rst,.req_valid(req_valid&&addresses_legal&&operands_initialized),.req_ready(matrix_ready),
  .req_id,.a_registers,.b_registers,.c_registers,
  .rsp_valid,.rsp_ready,.rsp_id,.result_registers,.outstanding
 );
 // Reads and initialization checks use pre-edge storage. A same-edge final
 // write cannot admit a waiting matrix operation until a later edge.
endmodule
