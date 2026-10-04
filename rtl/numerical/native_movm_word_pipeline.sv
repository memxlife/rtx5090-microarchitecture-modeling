// One MOVM.16.MT88 over one32-bit register per lane. Mapping is measured;
// latency, initiation interval, FIFO policy and capacity are model choices.
module native_movm_word_pipeline #(
 parameter int SLOTS=4,LATENCY=1,INTERVAL=1
)(
 input logic clk,rst,req_valid,output logic req_ready,input logic [31:0] req_id,
 input logic [31:0] input_words[32],
 output logic rsp_valid,input logic rsp_ready,
 output logic [31:0] rsp_id,output_words[32],output int outstanding
);
 int cycle,head,tail,next_accept,due[SLOTS];
 logic occupied[SLOTS];logic [31:0] ids[SLOTS],values[SLOTS][32];
 logic push,pop;
 initial if(SLOTS<1||LATENCY<1||INTERVAL<1)$fatal(1,"Invalid MOVM model parameters");
 assign req_ready=!rst&&outstanding<SLOTS&&cycle>=next_accept;
 assign rsp_valid=!rst&&outstanding>0&&cycle>=due[head];
 assign rsp_id=ids[head];
 assign push=req_valid&&req_ready;assign pop=rsp_valid&&rsp_ready;
 for(genvar lane=0;lane<32;lane++)assign output_words[lane]=values[head][lane];
 always_ff @(posedge clk)begin
  if(rst)begin
   cycle<=0;head<=0;tail<=0;next_accept<=0;outstanding<=0;
   for(int slot=0;slot<SLOTS;slot++)begin occupied[slot]<=0;ids[slot]<=0;due[slot]<=0;end
  end else begin
   cycle<=cycle+1;
   if(push)begin
    for(int slot=0;slot<SLOTS;slot++)if(occupied[slot]&&ids[slot]==req_id)
     $fatal(1,"Duplicate live MOVM identity");
    for(int lane=0;lane<32;lane++)for(int halfword=0;halfword<2;halfword++)begin
     int source;source=library_movm_permutation::pre_index(lane*8+halfword);
     values[tail][lane][16*halfword+:16]<=input_words[source/8][16*(source%2)+:16];
    end
    ids[tail]<=req_id;due[tail]<=cycle+LATENCY;occupied[tail]<=1;
    tail<=(tail+1)%SLOTS;next_accept<=cycle+INTERVAL;
   end
   if(pop)begin occupied[head]<=0;head<=(head+1)%SLOTS;end
   case({push,pop})
    2'b10:outstanding<=outstanding+1;
    2'b01:outstanding<=outstanding-1;
    default:outstanding<=outstanding;
   endcase
  end
 end
 // Values snapshot at admission and remain hidden until unit return becomes
 // valid. A full queue does not admit replacement on the retirement edge.
endmodule
