// Complete in-bounds output block of the studied row-major BF16 GEMM.
// Serial staging and optional four-warp execution are development schedules,
// not full native instruction replay. The cache is a blocking read-cache hypothesis, not recovered L2.
module studied_gemm_cta_controller #(
 parameter int BM=32,BN=32,BK=32,M=2048,N=2112,K=1536,CTA_ROW=0,CTA_COL=0,
 parameter int SETS=64,WAYS=8,LATENCY=16,INTERVAL=4,READ_SLOTS=4,
 parameter int SERVICE_INTERVAL=1,RETURN_DELAY=1,ARITHMETIC_MODE=1,
 parameter bit USE_NATIVE_STAGE=0,COALESCED_STAGING=0,COALESCED_OUTPUT=0,MULTIWARP_NATIVE_STAGE=0,USE_OUTPUT_SCRATCH=0,USE_CTA_BARRIERS=0,DYNAMIC_CTA_COORDS=0,
 parameter int BARRIER_RELEASE_DELAY=1,MOVM_LATENCY=1,MOVM_INTERVAL=1
)(
 input logic clk,rst,launch_valid,output logic launch_ready,
 input logic [31:0] launch_id,a_base,b_base,c_base,launch_cta_row,launch_cta_col,
 output logic done_valid,input logic done_ready,output logic [31:0] done_id,
 output logic backing_req_valid,input logic backing_req_ready,
 output logic [31:0] backing_req_id,backing_req_byte_address,
 input logic backing_rsp_valid,output logic backing_rsp_ready,
 input logic [31:0] backing_rsp_id,input logic [255:0] backing_rsp_data,
 output logic store_req_valid,input logic store_req_ready,
 output logic [31:0] store_req_id,store_req_byte_address,store_req_data,
 input logic store_rsp_valid,output logic store_rsp_ready,
 input logic [31:0] store_rsp_id,
 output logic sector_store_req_valid,input logic sector_store_req_ready,
 output logic [31:0] sector_store_req_id,sector_store_req_byte_address,
 output logic [255:0] sector_store_req_data,output logic [7:0] sector_store_req_word_mask,
 input logic sector_store_rsp_valid,output logic sector_store_rsp_ready,
 input logic [31:0] sector_store_rsp_id
);
 localparam int TN=BN/16,TILES=(BM/16)*TN,HALFWORDS=BK*(BM+BN),STAGES=K/BK;
 typedef enum logic[3:0]{IDLE,PRODUCER_ARM,PRODUCER_WAIT,CONSUMER_ARM,CONSUMER_WAIT,LOAD_SEND,LOAD_WAIT,SHARED_WRITE,MATRIX_SEND,
  MATRIX_WAIT,SCRATCH_SEND,SCRATCH_WAIT,STORE_SEND,STORE_WAIT,DONE} state_t;
 state_t state;
 logic [31:0] saved_id,saved_a,saved_b,saved_c,saved_row,saved_col;
 logic[31:0]accepted_row,accepted_col;
 assign accepted_row=DYNAMIC_CTA_COORDS?launch_cta_row:32'(CTA_ROW);
 assign accepted_col=DYNAMIC_CTA_COORDS?launch_cta_col:32'(CTA_COL);
 int stage_number,halfword_number,tile_number,k_step,store_number;
 logic [15:0] loaded_halfword;
 logic [15:0] loaded_halfwords[32],warp_halfwords[32];
 logic [31:0] warp_global_addresses[32],warp_shared_addresses[32];
 logic warp_write_valid,warp_write_ready;int warp_sector_count;
 logic cache_req_valid,cache_req_ready,cache_rsp_valid,cache_rsp_ready,cache_rsp_hit;
 logic [31:0] cache_req_id,cache_req_address,cache_rsp_id,cache_rsp_word;
 logic [31:0] global_halfword_address;
 logic write_valid,write_ready,matrix_req_valid,matrix_req_ready,matrix_rsp_valid,matrix_rsp_ready;
 logic [31:0] matrix_req_id,matrix_rsp_id,write_byte_address;
 logic [31:0] accumulators[TILES][32][8],matrix_c[32][8],matrix_results[32][8];
 logic initialized,legal;int matrix_outstanding;
 logic[31:0]batch_c[4][32][8],batch_results[4][32][8];
 logic[3:0]warp_drained,warp_memory_safe,consumer_sent,barrier_arrival_mask,barrier_arrived_mask,barrier_release_mask;
 logic barrier_arm_valid,barrier_arm_ready,barrier_arrival_valid,barrier_arrival_ready,barrier_release_valid,barrier_release_ready,barrier_active;
 logic[31:0]barrier_arm_generation,barrier_arrival_generation,barrier_generation;
 int producer_arrival_count,consumer_arrival_count,barrier_release_count;
 logic scratch_req_valid,scratch_req_ready,scratch_rsp_valid,scratch_rsp_ready;
 logic[31:0]scratch_rsp_id,scratch_words[4][256],saved_scratch_words[4][256];int scratch_outstanding;
 int scratch_store_requests,scratch_store_commit_words,scratch_read_requests,scratch_read_completions;
 logic output_warp_valid,output_warp_ready,output_done_valid,output_done_ready;
 logic [31:0] output_done_id,output_addresses[32],output_words[32];int output_sectors;
 initial if(BM<16||BN<16||BK<16||BM%16!=0||BN%16!=0||BK%16!=0||K< BK||K%BK!=0||
  BM>M||BN>N||(!DYNAMIC_CTA_COORDS&&(CTA_ROW<0||CTA_COL<0||(CTA_ROW+1)*BM>M||(CTA_COL+1)*BN>N)))
  $fatal(1,"Unsupported studied CTA geometry or partial output block");
 initial if(2*64'(M)*K>64'h100000000||2*64'(K)*N>64'h100000000||4*64'(M)*N>64'h100000000)
  $fatal(1,"Studied matrix allocation too large");
 initial if(USE_NATIVE_STAGE&&(BM!=32||BN!=32||BK!=32))
  $fatal(1,"Native stage controls support only original BM32 BN32 BK32");
 initial if(USE_CTA_BARRIERS&&(!MULTIWARP_NATIVE_STAGE||!COALESCED_STAGING))
  $fatal(1,"CTA barriers require four-warp stage and warp staging");
 initial if(USE_OUTPUT_SCRATCH&&(!MULTIWARP_NATIVE_STAGE||!COALESCED_OUTPUT))
  $fatal(1,"Output scratch requires multiwarp stage and warp output interface");
 initial if(MULTIWARP_NATIVE_STAGE&&!USE_NATIVE_STAGE)
  $fatal(1,"Multiwarp native stage requires supported native geometry");
 initial if(COALESCED_STAGING&&!USE_NATIVE_STAGE)
  $fatal(1,"Coalesced staging requires native stage vector write port");
 function automatic logic [31:0] input_address(input int index);
  int offset;offset=index-BM*BK;
  if(index<BM*BK)return saved_a+32'(2*((int'(saved_row)*BM+index/BK)*K+stage_number*BK+index%BK));
  return saved_b+32'(2*((stage_number*BK+offset/BN)*N+int'(saved_col)*BN+offset%BN));
 endfunction
 always_comb begin
  barrier_arm_valid=USE_CTA_BARRIERS&&!rst&&(state==PRODUCER_ARM||state==CONSUMER_ARM);
  barrier_arm_generation=32'(2*stage_number+(state==CONSUMER_ARM?1:0));
  barrier_arrival_valid=0;barrier_arrival_mask=0;barrier_arrival_generation=32'(2*stage_number);
  if(USE_CTA_BARRIERS&&!rst)begin
   if(state==SHARED_WRITE&&warp_write_valid&&warp_write_ready&&halfword_number>=HALFWORDS-128)begin
    barrier_arrival_valid=1;barrier_arrival_mask[ (halfword_number/32)%4 ]=1;
   end else if(state==MATRIX_WAIT&&(warp_memory_safe&~consumer_sent)!=0)begin
    barrier_arrival_valid=1;barrier_arrival_mask=warp_memory_safe&~consumer_sent;
    barrier_arrival_generation=32'(2*stage_number+1);
   end
  end
  barrier_release_ready=USE_CTA_BARRIERS&&!rst&&(state==PRODUCER_WAIT||state==CONSUMER_WAIT);
 end
 always_ff @(posedge clk)begin
  if(rst||state==IDLE)begin consumer_sent<=0;producer_arrival_count<=0;consumer_arrival_count<=0;barrier_release_count<=0;end
  else begin
   if(barrier_arm_valid&&barrier_arm_ready&&state==CONSUMER_ARM)consumer_sent<=0;
   if(barrier_arrival_valid)begin
    if(!barrier_arrival_ready)$fatal(1,"CTA arrival offered to unavailable generation");
    if(barrier_arrival_ready)begin
     if(state==SHARED_WRITE)producer_arrival_count<=producer_arrival_count+$countones(barrier_arrival_mask);
     else begin consumer_sent<=consumer_sent|barrier_arrival_mask;consumer_arrival_count<=consumer_arrival_count+$countones(barrier_arrival_mask);end
    end
   end
   if(barrier_release_valid&&barrier_release_ready)begin
    if(barrier_generation!=32'(2*stage_number+(state==CONSUMER_WAIT?1:0))||barrier_release_mask!=4'hf)
     $fatal(1,"CTA release generation or participant mismatch");
    barrier_release_count<=barrier_release_count+1;
   end
  end
 end
 assign launch_ready=!rst&&state==IDLE;
 assign done_valid=!rst&&state==DONE;assign done_id=saved_id;
 assign cache_req_valid=!rst&&state==LOAD_SEND;
 assign cache_rsp_ready=!rst&&state==LOAD_WAIT;
 assign cache_req_id=32'(stage_number*HALFWORDS+halfword_number);
 always_comb begin
  global_halfword_address=input_address(halfword_number);
  for(int lane=0;lane<32;lane++)begin
   warp_global_addresses[lane]=input_address(halfword_number+lane);
   warp_shared_addresses[lane]=32'(2*(halfword_number+lane));
  end
  for(int warp=0;warp<4;warp++)for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)
   batch_c[warp][lane][word]=warp<TILES?accumulators[warp][lane][word]:32'd0;
  // Original logical load is16bits; cache adapter obtains the containing word.
  cache_req_address={global_halfword_address[31:2],2'b00};
  for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)
   matrix_c[lane][word]=accumulators[tile_number][lane][word];
 end
 assign write_valid=!rst&&state==SHARED_WRITE&&!COALESCED_STAGING;
 assign warp_write_valid=!rst&&state==SHARED_WRITE&&COALESCED_STAGING;
 assign write_byte_address=32'(2*halfword_number);
 assign matrix_req_valid=!rst&&state==MATRIX_SEND;
 assign matrix_rsp_ready=!rst&&state==MATRIX_WAIT;
 assign matrix_req_id=32'((stage_number*TILES+tile_number)*(BK/16)+k_step);
 assign scratch_req_valid=!rst&&state==SCRATCH_SEND;
 assign scratch_rsp_ready=!rst&&state==SCRATCH_WAIT;
 assign store_req_valid=!rst&&state==STORE_SEND&&!COALESCED_OUTPUT;
 assign output_warp_valid=!rst&&state==STORE_SEND&&COALESCED_OUTPUT;
 assign output_done_ready=!rst&&state==STORE_WAIT&&COALESCED_OUTPUT;
 assign store_rsp_ready=!rst&&state==STORE_WAIT&&!COALESCED_OUTPUT;
 assign store_req_id=32'(store_number);
 always_comb begin
  int fragment,element,row,column;
  fragment=store_number/256;
  element=native_bf16_layout::c_element_index((store_number%256)/8,store_number%8);
  row=int'(saved_row)*BM+16*(fragment/TN)+element/16;
  column=int'(saved_col)*BN+16*(fragment%TN)+element%16;
  store_req_byte_address=saved_c+32'(4*(row*N+column));
  store_req_data=accumulators[fragment][(store_number%256)/8][store_number%8];
  for(int lane=0;lane<32;lane++)begin
   // Original global store reads row-major scratch at lane+32*iteration.
   // Gather equivalent values from measured fragment layout; scratch service
   // is bypassed only when USE_OUTPUT_SCRATCH is disabled. Service timing
   // remains provisional in both modes.
   element=lane+32*((store_number%256)/32);
   row=int'(saved_row)*BM+16*(fragment/TN)+element/16;
   column=int'(saved_col)*BN+16*(fragment%TN)+element%16;
   output_addresses[lane]=saved_c+32'(4*(row*N+column));
   output_words[lane]=0;
   if(USE_OUTPUT_SCRATCH)output_words[lane]=saved_scratch_words[fragment][element];
   else for(int owner=0;owner<32;owner++)for(int word=0;word<8;word++)
    if(native_bf16_layout::c_element_index(owner,word)==element)
     output_words[lane]=accumulators[fragment][owner][word];
  end
 end
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;saved_id<=0;saved_a<=0;saved_b<=0;saved_c<=0;saved_row<=0;saved_col<=0;
   stage_number<=0;halfword_number<=0;tile_number<=0;k_step<=0;store_number<=0;loaded_halfword<=0;
   for(int lane=0;lane<32;lane++)loaded_halfwords[lane]<=0;
   for(int warp=0;warp<4;warp++)for(int element=0;element<256;element++)saved_scratch_words[warp][element]<=0;
   for(int tile=0;tile<TILES;tile++)for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)
    accumulators[tile][lane][word]<=0;
  end else case(state)
   IDLE:if(launch_valid&&launch_ready)begin
    if(({32'b0,accepted_row}+64'd1)*64'(BM)>64'(M)||({32'b0,accepted_col}+64'd1)*64'(BN)>64'(N))
     $fatal(1,"Dynamic CTA coordinate outside complete output grid");
    if(a_base[6:0]!=0||b_base[6:0]!=0||c_base[1:0]!=0)$fatal(1,"Unaligned studied CTA base");
    if({1'b0,a_base}+33'(2*64'(M)*K)>33'h100000000||
       {1'b0,b_base}+33'(2*64'(K)*N)>33'h100000000||
       {1'b0,c_base}+33'(4*64'(M)*N)>33'h100000000)
     $fatal(1,"Studied CTA allocation exceeds 32-bit address space");
    // Input/output separation is required while cache write coherence is absent.
    if(({1'b0,c_base}<{1'b0,a_base}+33'(2*64'(M)*K)&&
        {1'b0,a_base}<{1'b0,c_base}+33'(4*64'(M)*N))||
       ({1'b0,c_base}<{1'b0,b_base}+33'(2*64'(K)*N)&&
        {1'b0,b_base}<{1'b0,c_base}+33'(4*64'(M)*N)))
     $fatal(1,"Overlapping studied output/input allocation");
    saved_id<=launch_id;saved_a<=a_base;saved_b<=b_base;saved_c<=c_base;saved_row<=accepted_row;saved_col<=accepted_col;
    stage_number<=0;halfword_number<=0;tile_number<=0;k_step<=0;store_number<=0;
    for(int tile=0;tile<TILES;tile++)for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)
     accumulators[tile][lane][word]<=0;
    state<=USE_CTA_BARRIERS?PRODUCER_ARM:LOAD_SEND;
   end
   PRODUCER_ARM:if(barrier_arm_valid&&barrier_arm_ready)state<=LOAD_SEND;
   PRODUCER_WAIT:if(barrier_release_valid&&barrier_release_ready)state<=CONSUMER_ARM;
   CONSUMER_ARM:if(barrier_arm_valid&&barrier_arm_ready)state<=MATRIX_SEND;
   CONSUMER_WAIT:if(barrier_release_valid&&barrier_release_ready)begin
    if(stage_number<STAGES-1)begin stage_number<=stage_number+1;halfword_number<=0;state<=PRODUCER_ARM;end
    else begin store_number<=0;state<=USE_OUTPUT_SCRATCH?SCRATCH_SEND:STORE_SEND;end
   end
   LOAD_SEND:if(cache_req_valid&&cache_req_ready)state<=LOAD_WAIT;
   LOAD_WAIT:if(cache_rsp_valid&&cache_rsp_ready)begin
    if(cache_rsp_id!=cache_req_id)$fatal(1,"Studied load completion identity mismatch");
    if(COALESCED_STAGING)for(int lane=0;lane<32;lane++)loaded_halfwords[lane]<=warp_halfwords[lane];
    else loaded_halfword<=global_halfword_address[1]?cache_rsp_word[31:16]:cache_rsp_word[15:0];
    state<=SHARED_WRITE;
   end
   SHARED_WRITE:if((write_valid&&write_ready)||(warp_write_valid&&warp_write_ready))begin
    if(halfword_number==HALFWORDS-(COALESCED_STAGING?32:1))begin tile_number<=0;k_step<=0;state<=USE_CTA_BARRIERS?PRODUCER_WAIT:MATRIX_SEND;end
    else begin halfword_number<=halfword_number+(COALESCED_STAGING?32:1);state<=LOAD_SEND;end
   end
   MATRIX_SEND:if(matrix_req_valid&&matrix_req_ready)state<=MATRIX_WAIT;
   MATRIX_WAIT:if(matrix_rsp_valid&&matrix_rsp_ready)begin
    if(matrix_rsp_id!=matrix_req_id)$fatal(1,"Studied arithmetic completion identity mismatch");
    if(MULTIWARP_NATIVE_STAGE)begin
     for(int warp=0;warp<4;warp++)for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)
      accumulators[warp][lane][word]<=batch_results[warp][lane][word];
    end else for(int lane=0;lane<32;lane++)for(int word=0;word<8;word++)
     accumulators[tile_number][lane][word]<=matrix_results[lane][word];
    if(USE_CTA_BARRIERS)state<=CONSUMER_WAIT;
    else if(!USE_NATIVE_STAGE&&k_step<BK/16-1)begin k_step<=k_step+1;state<=MATRIX_SEND;end
    else if(!MULTIWARP_NATIVE_STAGE&&tile_number<TILES-1)begin tile_number<=tile_number+1;k_step<=0;state<=MATRIX_SEND;end
    else if(stage_number<STAGES-1)begin stage_number<=stage_number+1;halfword_number<=0;state<=LOAD_SEND;end
    else begin store_number<=0;state<=USE_OUTPUT_SCRATCH?SCRATCH_SEND:STORE_SEND;end
   end
   SCRATCH_SEND:if(scratch_req_valid&&scratch_req_ready)state<=SCRATCH_WAIT;
   SCRATCH_WAIT:if(scratch_rsp_valid&&scratch_rsp_ready)begin
    if(scratch_rsp_id!=saved_id)$fatal(1,"Output scratch completion identity mismatch");
    for(int warp=0;warp<4;warp++)for(int element=0;element<256;element++)
     saved_scratch_words[warp][element]<=scratch_words[warp][element];
    state<=STORE_SEND;
   end
   STORE_SEND:if((store_req_valid&&store_req_ready)||(output_warp_valid&&output_warp_ready))state<=STORE_WAIT;
   STORE_WAIT:if((store_rsp_valid&&store_rsp_ready)||(output_done_valid&&output_done_ready))begin
    if(COALESCED_OUTPUT ? output_done_id!=32'(store_number/32) : store_rsp_id!=store_req_id)$fatal(1,"Studied store completion identity mismatch");
    if(store_number==BM*BN-(COALESCED_OUTPUT?32:1))state<=DONE;
    else begin store_number<=store_number+(COALESCED_OUTPUT?32:1);state<=STORE_SEND;end
   end
   DONE:if(done_valid&&done_ready)state<=IDLE;
   default:$fatal(1,"Invalid studied CTA controller state");
  endcase
 end
 generate if(COALESCED_STAGING)begin:warp_load_path
 coalesced_u16_warp_load #(.SETS(SETS),.WAYS(WAYS)) cache(
  .clk,.rst,.req_valid(cache_req_valid),.req_ready(cache_req_ready),.req_id(cache_req_id),
  .byte_addresses(warp_global_addresses),.active_mask(32'hffffffff),
  .rsp_valid(cache_rsp_valid),.rsp_ready(cache_rsp_ready),.rsp_id(cache_rsp_id),
  .halfwords(warp_halfwords),.sector_count(warp_sector_count),
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,
  .backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data
 );
 end else begin:scalar_load_path
 sector_read_cache #(.SETS(SETS),.WAYS(WAYS)) cache(
  .clk,.rst,.req_valid(cache_req_valid),.req_ready(cache_req_ready),.req_id(cache_req_id),.req_byte_address(cache_req_address),
  .rsp_valid(cache_rsp_valid),.rsp_ready(cache_rsp_ready),.rsp_id(cache_rsp_id),.rsp_data(cache_rsp_word),.rsp_hit(cache_rsp_hit),
  .backing_req_valid,.backing_req_ready,.backing_req_id,.backing_req_byte_address,
  .backing_rsp_valid,.backing_rsp_ready,.backing_rsp_id,.backing_rsp_data
 );
 end endgenerate
 generate if(MULTIWARP_NATIVE_STAGE)begin:multiwarp_stage_path
 native_multiwarp_stage_pipeline #(.READ_SLOTS(READ_SLOTS),.SERVICE_INTERVAL(SERVICE_INTERVAL),
  .RETURN_DELAY(RETURN_DELAY),.MOVM_LATENCY(MOVM_LATENCY),.MOVM_INTERVAL(MOVM_INTERVAL),
  .HMMA_LATENCY(LATENCY),.HMMA_INTERVAL(INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE),
  .ALLOW_WARP_WRITES(COALESCED_STAGING)) path(
  .clk,.rst,.write_valid,.write_ready,.write_byte_address,.write_data(loaded_halfword),
  .write_warp_valid(warp_write_valid),.write_warp_ready(warp_write_ready),
  .write_warp_byte_addresses(warp_shared_addresses),.write_warp_halfwords(loaded_halfwords),.write_warp_mask(32'hffffffff),
  .req_valid(matrix_req_valid),.req_ready(matrix_req_ready),.req_id(matrix_req_id),.c_registers(batch_c),
  .operands_initialized(initialized),.addresses_legal(legal),
  .rsp_valid(matrix_rsp_valid),.rsp_ready(matrix_rsp_ready),.rsp_id(matrix_rsp_id),
  .result_registers(batch_results),.outstanding(matrix_outstanding),.warp_drained(warp_drained),.warp_memory_safe(warp_memory_safe)
 );
 end else if(USE_NATIVE_STAGE)begin:native_stage_path
 native_studied_stage_pipeline #(.READ_SLOTS(READ_SLOTS),.SERVICE_INTERVAL(SERVICE_INTERVAL),
  .RETURN_DELAY(RETURN_DELAY),.MOVM_LATENCY(MOVM_LATENCY),.MOVM_INTERVAL(MOVM_INTERVAL),
  .HMMA_LATENCY(LATENCY),.HMMA_INTERVAL(INTERVAL),.ARITHMETIC_MODE(ARITHMETIC_MODE),
  .ALLOW_WARP_WRITES(COALESCED_STAGING)) path(
  .clk,.rst,.write_valid,.write_ready,.write_byte_address,.write_data(loaded_halfword),
  .write_warp_valid(warp_write_valid),.write_warp_ready(warp_write_ready),
  .write_warp_byte_addresses(warp_shared_addresses),.write_warp_halfwords(loaded_halfwords),.write_warp_mask(32'hffffffff),
  .req_valid(matrix_req_valid),.req_ready(matrix_req_ready),.req_id(matrix_req_id),
  .tile_index(32'(tile_number)),.c_registers(matrix_c),
  .operands_initialized(initialized),.addresses_legal(legal),
  .rsp_valid(matrix_rsp_valid),.rsp_ready(matrix_rsp_ready),.rsp_id(matrix_rsp_id),
  .result_registers(matrix_results),.outstanding(matrix_outstanding)
 );
 end else begin:generic_stage_path
 studied_gemm_matrix_pipeline #(.BM(BM),.BN(BN),.BK(BK),.TIMED_READS(1),
  .LATENCY(LATENCY),.INTERVAL(INTERVAL),.READ_SLOTS(READ_SLOTS),
  .SERVICE_INTERVAL(SERVICE_INTERVAL),.RETURN_DELAY(RETURN_DELAY),.ARITHMETIC_MODE(ARITHMETIC_MODE)) path(
  .clk,.rst,.write_valid,.write_ready,.write_byte_address,.write_data(loaded_halfword),
  .req_valid(matrix_req_valid),.req_ready(matrix_req_ready),.req_id(matrix_req_id),
  .tile_index(32'(tile_number)),.k_step(32'(k_step)),.c_registers(matrix_c),
  .operands_initialized(initialized),.addresses_legal(legal),
  .rsp_valid(matrix_rsp_valid),.rsp_ready(matrix_rsp_ready),.rsp_id(matrix_rsp_id),
  .result_registers(matrix_results),.outstanding(matrix_outstanding)
 );
 end endgenerate
 generate if(USE_OUTPUT_SCRATCH)begin:scratch_path
 studied_output_scratch_pipeline #(.STORE_INTERVAL(SERVICE_INTERVAL),.STORE_RETURN_DELAY(RETURN_DELAY),
  .READ_SLOTS(READ_SLOTS),.READ_INTERVAL(SERVICE_INTERVAL),.READ_RETURN_DELAY(RETURN_DELAY)) path(
  .clk,.rst,.req_valid(scratch_req_valid),.req_ready(scratch_req_ready),.req_id(saved_id),.c_registers(batch_c),
  .rsp_valid(scratch_rsp_valid),.rsp_ready(scratch_rsp_ready),.rsp_id(scratch_rsp_id),
  .row_major_words(scratch_words),.outstanding(scratch_outstanding),
  .store_requests(scratch_store_requests),.store_commit_words(scratch_store_commit_words),
  .read_requests(scratch_read_requests),.read_completions(scratch_read_completions)
 );
 end else begin:no_scratch_path
 assign scratch_store_requests=0;assign scratch_store_commit_words=0;assign scratch_read_requests=0;assign scratch_read_completions=0;
 assign scratch_req_ready=0;assign scratch_rsp_valid=0;assign scratch_rsp_id=0;assign scratch_outstanding=0;
 for(genvar warp=0;warp<4;warp++)for(genvar element=0;element<256;element++)assign scratch_words[warp][element]=0;
 end endgenerate
 generate if(COALESCED_OUTPUT)begin:warp_store_path
 coalesced_fp32_warp_store output_path(
  .clk,.rst,.req_valid(output_warp_valid),.req_ready(output_warp_ready),.req_id(32'(store_number/32)),
  .byte_addresses(output_addresses),.words(output_words),.active_mask(32'hffffffff),
  .rsp_valid(output_done_valid),.rsp_ready(output_done_ready),.rsp_id(output_done_id),.sector_count(output_sectors),
  .backing_req_valid(sector_store_req_valid),.backing_req_ready(sector_store_req_ready),
  .backing_req_id(sector_store_req_id),.backing_req_byte_address(sector_store_req_byte_address),
  .backing_req_data(sector_store_req_data),.backing_req_word_mask(sector_store_req_word_mask),
  .backing_rsp_valid(sector_store_rsp_valid),.backing_rsp_ready(sector_store_rsp_ready),.backing_rsp_id(sector_store_rsp_id)
 );
 end else begin:no_warp_store
 assign output_warp_ready=0;assign output_done_valid=0;assign output_done_id=0;assign output_sectors=0;
 assign sector_store_req_valid=0;assign sector_store_req_id=0;assign sector_store_req_byte_address=0;
 assign sector_store_req_data=0;assign sector_store_req_word_mask=0;assign sector_store_rsp_ready=0;
 end endgenerate
 generate if(USE_CTA_BARRIERS)begin:cta_barrier_path
 cta_generation_barrier #(.WARPS(4),.RELEASE_DELAY(BARRIER_RELEASE_DELAY)) barrier(
  .clk,.rst(rst||state==IDLE),.arm_valid(barrier_arm_valid),.arm_ready(barrier_arm_ready),
  .arm_generation(barrier_arm_generation),.expected_mask(4'hf),
  .arrival_valid(barrier_arrival_valid),.arrival_ready(barrier_arrival_ready),
  .arrival_generation(barrier_arrival_generation),.arrival_mask(barrier_arrival_mask),
  .release_valid(barrier_release_valid),.release_ready(barrier_release_ready),
  .generation(barrier_generation),.release_mask(barrier_release_mask),.arrived_mask(barrier_arrived_mask),.active(barrier_active)
 );
 end else begin:no_cta_barrier
 assign barrier_arm_ready=0;assign barrier_arrival_ready=0;assign barrier_release_valid=0;
 assign barrier_generation=0;assign barrier_release_mask=0;assign barrier_arrived_mask=0;assign barrier_active=0;
 end endgenerate
 // Serial stage boundaries enforce producer visibility and consumer drain,
 // but are not a reconstruction of128thread CTA barrier arbitration.
 // Providers must discard pre-reset traffic; IDs have no reset generation.
endmodule
