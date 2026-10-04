// Functional generic shared reads with explicit bank-service completion events.
// SERVICE_INTERVAL/RETURN_DELAY and matrix timing are engineering choices.
// One external matrix request collects eight independent scalar warp reads.
// All memory values snapshot at external matrix acceptance, not each later
// native load issue; intervening writes cannot affect this operation. This
// isolation is a model contract, not a discovered GPU memory hazard rule.
module timed_generic_shared_matrix_pipeline #(
 parameter int SHARED_BYTES=4096,SLOTS=2,LATENCY=16,INTERVAL=4,ARITHMETIC_MODE=1,
 parameter int READ_SLOTS=4,SERVICE_INTERVAL=1,RETURN_DELAY=1
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
 typedef enum logic [1:0]{IDLE,COLLECT,MATRIX_SEND,MATRIX_WAIT} state_t;
 state_t state;
 logic [15:0] memory[HALFWORDS];logic initialized[HALFWORDS];
 logic [31:0] saved_addresses[8][32],saved_words[8][32],returned_words[8][32];
 logic [31:0] saved_c[32][8],saved_id;
 logic [7:0] received;int next_read;
 logic read_req_valid,read_req_ready,read_rsp_valid,read_rsp_ready;
 logic [31:0] read_req_id,read_rsp_id,read_addresses[32],read_inputs[32],read_outputs[32];
 logic [31:0] a_registers[32][4],b_registers[32][4];
 logic [15:0] raw_b[256];logic matrix_ready;int matrix_outstanding;
 initial if(SHARED_BYTES<4||SHARED_BYTES%2!=0)$fatal(1,"Invalid shared storage size");
 assign write_ready=!rst&&write_byte_address[0]==0&&write_byte_address<=SHARED_BYTES-2;
 assign req_ready=!rst&&state==IDLE&&addresses_legal&&operands_initialized;
 assign outstanding=state==IDLE?0:1;
 always_comb begin
  addresses_legal=1;operands_initialized=1;
  for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)begin
   if(a_word_addresses[lane][word][1:0]!=0||b_word_addresses[lane][word][1:0]!=0||
      a_word_addresses[lane][word]>SHARED_BYTES-4||b_word_addresses[lane][word]>SHARED_BYTES-4)
    addresses_legal=0;
  end
  if(addresses_legal)begin
   for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)
    operands_initialized=operands_initialized&&
     initialized[a_word_addresses[lane][word]/2]&&initialized[a_word_addresses[lane][word]/2+1]&&
     initialized[b_word_addresses[lane][word]/2]&&initialized[b_word_addresses[lane][word]/2+1];
  end else operands_initialized=0;
  for(int lane=0;lane<32;lane++)begin
   read_addresses[lane]=0;read_inputs[lane]=0;
   if(next_read<8)begin read_addresses[lane]=saved_addresses[next_read][lane];read_inputs[lane]=saved_words[next_read][lane];end
   for(int word=0;word<4;word++)begin
    a_registers[lane][word]=returned_words[word][lane];
    raw_b[lane*8+word*2]=returned_words[4+word][lane][15:0];
    raw_b[lane*8+word*2+1]=returned_words[4+word][lane][31:16];
   end
  end
  for(int lane=0;lane<32;lane++)for(int word=0;word<4;word++)for(int h=0;h<2;h++)
   b_registers[lane][word][16*h+:16]=raw_b[library_movm_permutation::pre_index(lane*8+word*2+h)];
 end
 assign read_req_valid=!rst&&state==COLLECT&&next_read<8;
 assign read_req_id=32'(next_read);
 assign read_rsp_ready=!rst&&state==COLLECT;
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;next_read<=0;received<=0;saved_id<=0;
   for(int i=0;i<HALFWORDS;i++)initialized[i]<=0;
   for(int r=0;r<8;r++)for(int lane=0;lane<32;lane++)begin
    saved_addresses[r][lane]<=0;saved_words[r][lane]<=0;returned_words[r][lane]<=0;
   end
   for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)saved_c[lane][word]<=0;
  end else begin
   if(write_valid&&!write_ready)$fatal(1,"Invalid shared write address");
   if(req_valid&&!addresses_legal)$fatal(1,"Invalid packed shared read address");
   if(write_valid&&write_ready)begin memory[write_byte_address/2]<=write_data;initialized[write_byte_address/2]<=1;end
   case(state)
    IDLE:if(req_valid&&req_ready)begin
     saved_id<=req_id;next_read<=0;received<=0;state<=COLLECT;
     for(int lane=0;lane<32;lane++)begin
      for(int word=0;word<8;word++)saved_c[lane][word]<=c_registers[lane][word];
      for(int word=0;word<4;word++)begin
       saved_addresses[word][lane]<=a_word_addresses[lane][word];
       saved_addresses[word+4][lane]<=b_word_addresses[lane][word];
       saved_words[word][lane]<={memory[a_word_addresses[lane][word]/2+1],memory[a_word_addresses[lane][word]/2]};
       saved_words[word+4][lane]<={memory[b_word_addresses[lane][word]/2+1],memory[b_word_addresses[lane][word]/2]};
      end
     end
    end
    COLLECT:begin
     if(read_req_valid&&read_req_ready)next_read<=next_read+1;
     if(read_rsp_valid&&read_rsp_ready)begin
      if(read_rsp_id>=8)$fatal(1,"Unknown warp-read response identity");
      else if(received[read_rsp_id]||read_rsp_id>=next_read)$fatal(1,"Duplicate or unissued warp-read completion");
      else begin
       received[read_rsp_id]<=1;
       for(int lane=0;lane<32;lane++)returned_words[read_rsp_id][lane]<=read_outputs[lane];
       if((received|(8'b1<<read_rsp_id))==8'hff)state<=MATRIX_SEND;
      end
     end
    end
    MATRIX_SEND:if(matrix_ready)state<=MATRIX_WAIT;
    MATRIX_WAIT:if(rsp_valid&&rsp_ready)state<=IDLE;
    default:$fatal(1,"Invalid timed operand state");
   endcase
  end
 end
 warp_shared_read_service #(.SLOTS(READ_SLOTS),.SERVICE_INTERVAL(SERVICE_INTERVAL),.RETURN_DELAY(RETURN_DELAY)) reads(
  .clk,.rst,.req_valid(read_req_valid),.req_ready(read_req_ready),.req_id(read_req_id),
  .byte_addresses(read_addresses),.input_words(read_inputs),
  .rsp_valid(read_rsp_valid),.rsp_ready(read_rsp_ready),.rsp_id(read_rsp_id),.output_words(read_outputs)
 );
 native_bf16_adapter #(.SLOTS(SLOTS),.LATENCY(LATENCY),.INTERVAL(INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE)) matrix(
  .clk,.rst,.req_valid(state==MATRIX_SEND&&!rst),.req_ready(matrix_ready),.req_id(saved_id),
  .a_registers,.b_registers,.c_registers(saved_c),.rsp_valid,.rsp_ready,.rsp_id,.result_registers,.outstanding(matrix_outstanding)
 );
endmodule
