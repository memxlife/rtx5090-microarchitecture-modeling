// Warp-granularity CTA barrier hypothesis: explicit arm, arrivals and release.
// WARPS and registered release delay do not identify private GPU barrier state.
// One generation at a time. Completed release increments the next generation.
module cta_generation_barrier #(parameter int WARPS=4,RELEASE_DELAY=1)(
 input logic clk,rst,
 input logic arm_valid,output logic arm_ready,input logic[31:0]arm_generation,
 input logic[WARPS-1:0]expected_mask,
 input logic arrival_valid,output logic arrival_ready,input logic[31:0]arrival_generation,
 input logic[WARPS-1:0]arrival_mask,
 output logic release_valid,input logic release_ready,output logic[31:0]generation,
 output logic[WARPS-1:0]release_mask,arrived_mask,output logic active
);
 typedef enum logic[1:0]{IDLE,COLLECT,DELAY,RELEASE}state_t;
 state_t state;logic[WARPS-1:0]saved_expected;logic[31:0]next_generation;
 int delay_left;logic arrival_legal;
 initial if(WARPS<1||RELEASE_DELAY<1)$fatal(1,"Invalid CTA generation barrier parameters");
 assign arm_ready=!rst&&state==IDLE;
 assign active=!rst&&state!=IDLE;
 assign arrival_legal=arrival_generation==generation&&arrival_mask!='0&&
  (arrival_mask&~saved_expected)=='0&&(arrival_mask&arrived_mask)=='0;
 assign arrival_ready=!rst&&state==COLLECT&&arrival_legal;
 assign release_valid=!rst&&state==RELEASE;assign release_mask=saved_expected;
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;generation<=0;next_generation<=0;saved_expected<='0;arrived_mask<='0;delay_left<=0;
  end else begin
   // Arrival is an event for an already armed generation, never a speculative
   // operation held before arm. Same-edge arm/arrival is therefore invalid.
   if(arrival_valid)begin
    if(state==IDLE)$fatal(1,"CTA arrival before generation arm");
    else if(arrival_generation!=generation)$fatal(1,"CTA arrival generation mismatch");
    else if(arrival_mask=='0)$fatal(1,"Empty CTA arrival mask");
    else if((arrival_mask&~saved_expected)!='0)$fatal(1,"Unexpected CTA arrival warp");
    else if((arrival_mask&arrived_mask)!='0)$fatal(1,"Duplicate CTA generation arrival");
    else if(state!=COLLECT)$fatal(1,"CTA arrival after collection closed");
   end
   case(state)
    IDLE:if(arm_valid&&arm_ready)begin
     if(arm_generation!=next_generation)$fatal(1,"CTA arm generation out of sequence");
     if(expected_mask=='0)$fatal(1,"Empty CTA expected mask");
     generation<=arm_generation;saved_expected<=expected_mask;arrived_mask<='0;state<=COLLECT;
    end
    COLLECT:if(arrival_valid&&arrival_ready)begin
     arrived_mask<=arrived_mask|arrival_mask;
     if((arrived_mask|arrival_mask)==saved_expected)begin delay_left<=RELEASE_DELAY-1;state<=DELAY;end
    end
    DELAY:if(delay_left>0)delay_left<=delay_left-1;else state<=RELEASE;
    RELEASE:if(release_valid&&release_ready)begin
     if(next_generation==32'hffffffff)$fatal(1,"CTA generation counter overflow unsupported");
     next_generation<=next_generation+1;arrived_mask<='0;saved_expected<='0;state<=IDLE;
    end
    default:$fatal(1,"Invalid CTA generation state");
   endcase
  end
 end
 // A held arm is backpressured during active/release. Release acknowledgement
 // cannot also accept a new arm; the next arm is eligible the following cycle.
 // Reset cancels active arrivals/release and resets the sequence to generation0.
endmodule
