// Timing-only structural hypothesis. Not NVIDIA RTL or numerical GEMM.
module gpu_timing;
  parameter int WARPS=4, DEPTH=256, REGS=64, SETS=16, WAYS=2;
  logic clk=0;
  always #5 clk=~clk;
  logic [63:0] program_mem [0:WARPS*DEPTH-1];
  int pc[WARPS], ready_at[WARPS][REGS], valid_reg[WARPS][REGS];
  int warp_done[WARPS], next_issue[4];
  int cache_tag[SETS][WAYS], cache_valid[SETS][WAYS];
  int cache_ready[SETS][WAYS], cache_age[SETS][WAYS];
  int bank_ready[32];
  int cycle=0, cursor=0, issued=0, hits=0, misses=0, pending_hits=0;
  int dep_wait=0, service_wait=0, barrier_wait=0;
  int hit_latency, miss_latency, memory_spacing, memory_slots;
  int shared_latency, shared_spacing, mma_latency, mma_spacing, alu_latency;
  int barrier_latency, max_cycles;
  string trace_path;
  initial begin
    if (!$value$plusargs("TRACE=%s",trace_path)) $fatal(1,"Missing TRACE");
    if (!$value$plusargs("HIT=%d",hit_latency)) $fatal(1,"Missing HIT");
    if (!$value$plusargs("MISS=%d",miss_latency)) $fatal(1,"Missing MISS");
    if (!$value$plusargs("MEM_SPACING=%d",memory_spacing)) $fatal(1,"Missing MEM_SPACING");
    if (!$value$plusargs("MEM_SLOTS=%d",memory_slots)) $fatal(1,"Missing MEM_SLOTS");
    if (!$value$plusargs("SHARED=%d",shared_latency)) $fatal(1,"Missing SHARED");
    if (!$value$plusargs("SHARED_SPACING=%d",shared_spacing)) $fatal(1,"Missing SHARED_SPACING");
    if (!$value$plusargs("MMA=%d",mma_latency)) $fatal(1,"Missing MMA");
    if (!$value$plusargs("MMA_SPACING=%d",mma_spacing)) $fatal(1,"Missing MMA_SPACING");
    if (!$value$plusargs("ALU=%d",alu_latency)) $fatal(1,"Missing ALU");
    if (!$value$plusargs("BARRIER=%d",barrier_latency)) $fatal(1,"Missing BARRIER");
    if (!$value$plusargs("MAX_CYCLES=%d",max_cycles)) $fatal(1,"Missing MAX_CYCLES");
    for(int w=0;w<WARPS;w++) begin
      pc[w]=0; warp_done[w]=0;
      for(int r=0;r<REGS;r++) begin valid_reg[w][r]=(r==0); ready_at[w][r]=0; end
    end
    for(int r=0;r<4;r++) next_issue[r]=0;
    for(int b=0;b<32;b++) bank_ready[b]=0;
    for(int s=0;s<SETS;s++) for(int a=0;a<WAYS;a++) begin
      cache_valid[s][a]=0; cache_ready[s][a]=0; cache_age[s][a]=0; cache_tag[s][a]=0;
    end
    for(int i=0;i<WARPS*DEPTH;i++) program_mem[i]=64'hf;
    $readmemh(trace_path,program_mem);
  end
  always @(posedge clk) begin : step
    int complete, all_barrier, all_drained, chosen, active_fills;
    int op, src, dst, addr, set_id, tag, way, oldest, resource_id;
    int finish_time, latency, spacing, bank, needs_src, cached;
    logic [63:0] inst;
    complete=1; all_barrier=1; all_drained=1; chosen=-1; active_fills=0;
    for(int s=0;s<SETS;s++) for(int a=0;a<WAYS;a++)
      if(cache_valid[s][a]!=0 && cache_ready[s][a]>cycle) active_fills++;
    for(int w=0;w<WARPS;w++) begin
      if(pc[w]>=DEPTH) $fatal(1,"Program overflow");
      op=int'(program_mem[w*DEPTH+pc[w]][3:0]);
      if(op!=15 || warp_done[w]>cycle) complete=0;
      if(op!=6) all_barrier=0;
      if(warp_done[w]>cycle) all_drained=0;
    end
    if(complete!=0) begin
      $display("RESULT cycles=%0d issued=%0d hits=%0d misses=%0d pending_hits=%0d dependency_wait=%0d service_wait=%0d barrier_wait=%0d",cycle,issued,hits,misses,pending_hits,dep_wait,service_wait,barrier_wait);
      $finish;
    end else if(cycle>=max_cycles) $fatal(1,"Timeout or unresolved dependency/barrier");
    else if(all_barrier!=0 && all_drained!=0) begin
      for(int w=0;w<WARPS;w++) begin pc[w]++; warp_done[w]=cycle+barrier_latency; end
    end else begin
      // One modeled scheduler issues at most one warp instruction per tick.
      for(int k=0;k<WARPS;k++) begin
        int w;
        w=(cursor+k)%WARPS; inst=program_mem[w*DEPTH+pc[w]];
        op=int'(inst[3:0]); src=int'(inst[9:4]); dst=int'(inst[15:10]); addr=int'(inst[47:16]);
        needs_src=(op==2 || op==4 || op==5);
        resource_id=(op==1)?0:((op==2 || op==3)?1:((op==4)?2:3));
        bank=(addr/4)%32; cached=0;
        for(int a=0;a<WAYS;a++)
          if(cache_valid[(addr/32)%SETS][a]!=0 && cache_tag[(addr/32)%SETS][a]==(addr/32)/SETS) cached=1;
        if(op==6) barrier_wait++;
        else if(op!=15 && chosen<0) begin
          if(op<1 || op>5) $fatal(1,"Unsupported opcode");
          if(pc[w]>0 && warp_done[w]>cycle && program_mem[w*DEPTH+pc[w]-1][3:0]==6) dep_wait++;
          else if(needs_src!=0 && (valid_reg[w][src]==0 || ready_at[w][src]>cycle)) dep_wait++;
          else if(op!=2 && valid_reg[w][dst]!=0 && ready_at[w][dst]>cycle) dep_wait++;
          else if(next_issue[resource_id]>cycle || ((op==2 || op==3) && bank_ready[bank]>cycle) || (op==1 && cached==0 && active_fills>=memory_slots)) service_wait++;
          else chosen=w;
        end
      end
      if(chosen>=0) begin
        inst=program_mem[chosen*DEPTH+pc[chosen]];
        op=int'(inst[3:0]); src=int'(inst[9:4]); dst=int'(inst[15:10]); addr=int'(inst[47:16]);
        resource_id=(op==1)?0:((op==2 || op==3)?1:((op==4)?2:3));
        latency=alu_latency; spacing=1; finish_time=cycle+latency;
        if(op==1) begin
          set_id=(addr/32)%SETS; tag=(addr/32)/SETS; way=-1; oldest=0;
          for(int a=0;a<WAYS;a++) begin
            if(cache_valid[set_id][a]!=0 && cache_tag[set_id][a]==tag) way=a;
            if(cache_valid[set_id][a]==0 || cache_age[set_id][a]<cache_age[set_id][oldest]) oldest=a;
          end
          if(way>=0) begin
            hits++; finish_time=cycle+hit_latency;
            if(cache_ready[set_id][way]>cycle) begin
              pending_hits++;
              finish_time=cache_ready[set_id][way]+hit_latency;
            end
          end else begin
            // Refuse overwriting a pending fill: its state would be lost.
            if(cache_valid[set_id][oldest]!=0 && cache_ready[set_id][oldest]>cycle)
              $fatal(1,"Pending cache replacement unsupported");
            misses++; way=oldest; finish_time=cycle+miss_latency;
            cache_valid[set_id][way]=1; cache_tag[set_id][way]=tag;
            cache_ready[set_id][way]=finish_time;
          end
          cache_age[set_id][way]=cycle; spacing=memory_spacing;
        end else if(op==2 || op==3) begin
          finish_time=cycle+shared_latency; spacing=shared_spacing;
          bank=(addr/4)%32; bank_ready[bank]=cycle+shared_spacing;
        end else if(op==4) begin finish_time=cycle+mma_latency; spacing=mma_spacing; end
        if(op!=2) begin valid_reg[chosen][dst]=1; ready_at[chosen][dst]=finish_time; end
        if(finish_time>warp_done[chosen]) warp_done[chosen]=finish_time;
        next_issue[resource_id]=cycle+spacing;
        $display("ISSUE cycle=%0d warp=%0d pc=%0d op=%0d ready=%0d",cycle,chosen,pc[chosen],op,finish_time);
        pc[chosen]++; cursor=(chosen+1)%WARPS; issued++;
      end
    end
    cycle++;
  end
endmodule
