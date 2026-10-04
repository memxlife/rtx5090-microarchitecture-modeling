// Executable modeling contracts. Policies/parameters are hypotheses, not NVIDIA RTL.
module timed_queue #(
  parameter int SLOTS=4, LATENCY=1, INTERVAL=1
)(input logic clk,rst, input logic req_valid, output logic req_ready,
  input logic [31:0] req_id, output logic rsp_valid,input logic rsp_ready,
  output logic [31:0] rsp_id);
  int cycle,count,head,tail,next_accept;
  int due[SLOTS]; logic [31:0] ids[SLOTS];
  wire push=req_valid&&req_ready, pop=rsp_valid&&rsp_ready;
  assign req_ready=(count<SLOTS)&&(cycle>=next_accept);
  assign rsp_valid=(count>0)&&(cycle>=due[head]);
  assign rsp_id=ids[head];
  initial if(SLOTS<1||LATENCY<1||INTERVAL<1) $fatal(1,"Invalid timing queue configuration");
  always_ff @(posedge clk) begin
    if(rst) begin cycle<=0;count<=0;head<=0;tail<=0;next_accept<=0;end
    else begin
      cycle<=cycle+1;
      if(push) begin ids[tail]<=req_id;due[tail]<=cycle+LATENCY;tail<=(tail+1)%SLOTS;next_accept<=cycle+INTERVAL;end
      if(pop) head<=(head+1)%SLOTS;
      case({push,pop}) 2'b10:count<=count+1;2'b01:count<=count-1;default:count<=count;endcase
    end
  end
endmodule

module block_allocator #(
 parameter int SLOTS=4, REG_WORDS=65536, SHARED_BYTES=102400
)(input logic clk,rst, input logic admit_valid,output logic admit_ready,
 input int registers_needed,shared_needed, output int admitted_slot,
 input logic retire_valid,input int retire_slot,output int resident_blocks);
 logic busy[SLOTS]; int reg_alloc[SLOTS],sh_alloc[SLOTS]; int free_regs,free_shared,slot;
 always_comb begin
  free_regs=REG_WORDS;free_shared=SHARED_BYTES;resident_blocks=0;slot=-1;
  for(int i=0;i<SLOTS;i++) begin
   if(busy[i]) begin free_regs-=reg_alloc[i];free_shared-=sh_alloc[i];resident_blocks++;end
   else if(slot<0) slot=i;
  end
  admitted_slot=slot;
  admit_ready=slot>=0&&registers_needed>=0&&shared_needed>=0&&registers_needed<=free_regs&&shared_needed<=free_shared;
 end
 always_ff @(posedge clk) begin
  if(rst) for(int i=0;i<SLOTS;i++) begin busy[i]<=0;reg_alloc[i]<=0;sh_alloc[i]<=0;end
  else begin
   if(retire_valid) begin
    if(retire_slot<0||retire_slot>=SLOTS) $fatal(1,"Invalid retire slot");
    else if(!busy[retire_slot]) $fatal(1,"Retiring unallocated block");
    else busy[retire_slot]<=0;
   end
   if(admit_valid&&admit_ready) begin busy[slot]<=1;reg_alloc[slot]<=registers_needed;sh_alloc[slot]<=shared_needed;end
  end
 end
endmodule

module warp_context #(parameter int DEPTH=256)(
 input logic clk,rst, input logic issue_fire,barrier_instruction,end_instruction,
 input logic barrier_release, output int pc,output logic waiting,ended);
 always_ff @(posedge clk) begin
  if(rst) begin pc<=0;waiting<=0;ended<=0;end
  else begin
   if(barrier_release) waiting<=0;
   if(issue_fire) begin
    if(waiting||ended||pc>=DEPTH) $fatal(1,"Illegal warp advance");
    pc<=pc+1;
    if(barrier_instruction) waiting<=1;
    if(end_instruction) ended<=1;
   end
  end
 end
endmodule

module warp_scheduler #(parameter int WARPS=4)(
 input logic clk,rst,input logic [WARPS-1:0] eligible,
 output logic issue_valid,input logic issue_ready,output int issue_warp);
 int cursor;
 always_comb begin
  issue_valid=0;issue_warp=0;
  for(int k=0;k<WARPS;k++) begin
   if(!issue_valid&&eligible[(cursor+k)%WARPS]) begin issue_valid=1;issue_warp=(cursor+k)%WARPS;end
  end
 end
 always_ff @(posedge clk) begin
  if(rst) cursor<=0;
  else if(issue_valid&&issue_ready) cursor<=(issue_warp+1)%WARPS;
 end
endmodule

module register_scoreboard #(parameter int REGS=64)(
 input logic clk,rst,input int source_a,source_b,destination,
 input logic use_a,use_b,write_destination,
 output logic operands_ready,destination_free,
 input logic issue_fire,input int result_delay);
 int cycle,available_at[REGS]; logic defined[REGS];
 always_comb begin
  operands_ready=(!use_a||(defined[source_a]&&cycle>=available_at[source_a]))&&
                 (!use_b||(defined[source_b]&&cycle>=available_at[source_b]));
  destination_free=!write_destination||!defined[destination]||cycle>=available_at[destination];
 end
 always_ff @(posedge clk) begin
  if(rst) begin
   cycle<=0;
   for(int r=0;r<REGS;r++) begin defined[r]<=(r==0);available_at[r]<=0;end
  end else begin
   cycle<=cycle+1;
   if(issue_fire) begin
    if(!operands_ready||!destination_free||result_delay<1) $fatal(1,"Illegal register issue");
    if(write_destination) begin defined[destination]<=1;available_at[destination]<=cycle+result_delay;end
   end
  end
 end
endmodule

module execution_pipeline #(parameter int SLOTS=4,LATENCY=1,INTERVAL=1)(
 input logic clk,rst,req_valid,output logic req_ready,input logic [31:0] req_id,
 output logic rsp_valid,input logic rsp_ready,output logic [31:0] rsp_id);
 // Instantiate separately for ALU, operand rearrangement, and matrix operations.
 timed_queue #(.SLOTS(SLOTS),.LATENCY(LATENCY),.INTERVAL(INTERVAL)) pipe(.*);
endmodule

module transaction_queue #(parameter int SLOTS=4,LATENCY=1,INTERVAL=1)(
 input logic clk,rst,req_valid,output logic req_ready,input logic [31:0] req_id,
 output logic rsp_valid,input logic rsp_ready,output logic [31:0] rsp_id);
 // Capacity and return backpressure; lane coalescing must be supplied upstream.
 timed_queue #(.SLOTS(SLOTS),.LATENCY(LATENCY),.INTERVAL(INTERVAL)) queue(.*);
endmodule

module address_translation #(parameter int LATENCY=1)(
 input logic clk,rst,req_valid,output logic req_ready,input logic [31:0] virtual_address,
 output logic rsp_valid,input logic rsp_ready,output logic [31:0] physical_address);
 // Explicit identity-mapping baseline. Not a measured translation cache.
 timed_queue #(.SLOTS(4),.LATENCY(LATENCY),.INTERVAL(1)) translation(
  .clk,.rst,.req_valid,.req_ready,.req_id(virtual_address),.rsp_valid,.rsp_ready,.rsp_id(physical_address));
endmodule

module shared_memory_bank #(parameter int WORDS=64,LATENCY=1)(
 input logic clk,rst,req_valid,output logic req_ready,input logic write,
 input int word_address,input logic [31:0] write_data,output logic rsp_valid,
 input logic rsp_ready,output logic [31:0] read_data);
 logic [31:0] storage[WORDS]; logic occupied;int remaining;
 assign req_ready=!occupied;
 assign rsp_valid=occupied&&remaining==0;
 always_ff @(posedge clk) begin
  if(rst) begin occupied<=0;remaining<=0;read_data<=0;for(int i=0;i<WORDS;i++) storage[i]<=0;end
  else begin
   if(occupied&&remaining>0) remaining<=remaining-1;
   if(rsp_valid&&rsp_ready) occupied<=0;
   if(req_valid&&req_ready) begin
    if(word_address<0||word_address>=WORDS||LATENCY<1) $fatal(1,"Invalid shared access");
    else begin
     occupied<=1;remaining<=LATENCY-1;
     if(write) begin storage[word_address]<=write_data;read_data<=write_data;end
     else read_data<=storage[word_address];
    end
   end
  end
 end
endmodule

module read_cache #(parameter int SETS=16,WAYS=2,HIT_DELAY=1,MISS_DELAY=1)(
 input logic clk,rst,req_valid,output logic req_ready,input logic [31:0] byte_address,
 output logic rsp_valid,input logic rsp_ready,output logic hit,output logic [31:0] response_address);
 int tags[SETS][WAYS],age[SETS][WAYS],cycle,remaining,set_id,tag,found,victim;
 logic valid[SETS][WAYS],occupied;
 assign req_ready=!occupied;assign rsp_valid=occupied&&remaining==0;
 always_comb begin
  set_id=int'((byte_address>>5)%SETS);tag=int'((byte_address>>5)/SETS);found=-1;victim=0;
  for(int a=0;a<WAYS;a++) begin
   if(valid[set_id][a]&&tags[set_id][a]==tag) found=a;
   if(!valid[set_id][a]||age[set_id][a]<age[set_id][victim]) victim=a;
  end
 end
 always_ff @(posedge clk) begin
  if(rst) begin
   cycle<=0;remaining<=0;occupied<=0;hit<=0;response_address<=0;
   for(int s=0;s<SETS;s++) for(int a=0;a<WAYS;a++) begin valid[s][a]<=0;tags[s][a]<=0;age[s][a]<=0;end
  end else begin
   cycle<=cycle+1;
   if(occupied&&remaining>0) remaining<=remaining-1;
   if(rsp_valid&&rsp_ready) occupied<=0;
   if(req_valid&&req_ready) begin
    if(HIT_DELAY<1||MISS_DELAY<1) $fatal(1,"Invalid cache delay");
    occupied<=1;hit<=found>=0;response_address<=byte_address;
    if(found>=0) begin remaining<=HIT_DELAY-1;age[set_id][found]<=cycle;end
    else begin remaining<=MISS_DELAY-1;valid[set_id][victim]<=1;tags[set_id][victim]<=tag;age[set_id][victim]<=cycle;end
   end
  end
 end
 // Blocking read-only cache: no request accepted until response retires.
endmodule

module memory_controller #(parameter int SLOTS=4,LATENCY=1,INTERVAL=1)(
 input logic clk,rst,req_valid,output logic req_ready,input logic [31:0] req_id,
 output logic rsp_valid,input logic rsp_ready,output logic [31:0] rsp_id);
 // FIFO timed-service baseline, not a GDDR7 bank/command implementation.
 timed_queue #(.SLOTS(SLOTS),.LATENCY(LATENCY),.INTERVAL(INTERVAL)) controller(.*);
endmodule

module barrier_controller #(parameter int WARPS=4,RELEASE_DELAY=1)(
 input logic clk,rst,input logic [WARPS-1:0] arrivals,
 input logic protected_operations_complete,output logic release_warps);
 logic [WARPS-1:0] arrived;logic releasing;int remaining;
 always_ff @(posedge clk) begin
  if(rst) begin arrived<=0;releasing<=0;remaining<=0;release_warps<=0;end
  else begin
   release_warps<=0;
   if(!releasing) begin
    arrived<=arrived|arrivals;
    if(&(arrived|arrivals)&&protected_operations_complete) begin
     if(RELEASE_DELAY<1) $fatal(1,"Invalid barrier delay");
     releasing<=1;remaining<=RELEASE_DELAY-1;
    end
   end else if(remaining>0) remaining<=remaining-1;
   else begin release_warps<=1;arrived<=0;releasing<=0;end
  end
 end
endmodule

module completion_tracker #(parameter int WARPS=4)(
 input logic clk,rst,input logic [WARPS-1:0] ended,
 input logic all_output_stores_complete,output logic block_complete);
 always_ff @(posedge clk) begin
  if(rst) block_complete<=0;
  else if((&ended)&&all_output_stores_complete) block_complete<=1;
 end
endmodule

module reference_clock_counter(input logic clk,rst,output logic [63:0] cycles);
 always_ff @(posedge clk) begin if(rst) cycles<=0;else cycles<=cycles+1;end
endmodule
