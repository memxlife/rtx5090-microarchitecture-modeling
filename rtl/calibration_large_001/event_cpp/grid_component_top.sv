module grid_component_top #(parameter int SMS=11)(input logic clk,rst,launch_valid,done_ready,input int kernel_setup_cycles,resident_blocks,input logic[31:0]launch_id,a_base,b_base,c_base,input logic child_launch_ready[SMS],child_done_valid[SMS],input logic[31:0]child_done_id[SMS],output logic launch_ready,done_valid,output logic[31:0]done_id,output logic child_launch_valid[SMS],child_done_ready[SMS],output logic block_launch_valid,block_done_valid,output logic[31:0]block_launch_ordinal,block_launch_row,block_launch_col,block_launch_sm,block_done_ordinal,block_done_row,block_done_col,block_done_sm,output int launch_owner,launch_cursor,completion_owner,completion_cursor,dispatched_blocks,completed_blocks,setup_left,output logic[63:0]elapsed_cycles,output int state_out);
localparam int TILE_ROWS=3,TILE_COLS=9,BLOCKS=27;typedef enum logic[1:0]{IDLE,RUN,COMPLETE,STARTUP}state_t;state_t state;logic[31:0]saved_id,saved_a,saved_b,saved_c,child_id;logic launched[BLOCKS],completed[BLOCKS];logic launch_legal;
assign launch_legal=1;assign launch_ready=!rst&&state==IDLE&&launch_legal;assign done_valid=!rst&&state==COMPLETE;assign done_id=saved_id;assign child_id=32'(dispatched_blocks);assign state_out=int'(state);
always_comb begin for(int sm=0;sm<SMS;sm++)begin child_launch_valid[sm]=0;child_done_ready[sm]=0;end if(!rst&&state==RUN&&launch_owner>=0&&dispatched_blocks<BLOCKS)child_launch_valid[launch_owner]=1;completion_owner=-1;for(int off=0;off<SMS;off++)begin int sm;sm=(completion_cursor+off)%SMS;if(!rst&&state==RUN&&completion_owner<0&&child_done_valid[sm])completion_owner=sm;end if(completion_owner>=0)child_done_ready[completion_owner]=1;end
assign block_launch_valid=launch_owner>=0?(child_launch_valid[launch_owner]&&child_launch_ready[launch_owner]):0;assign block_launch_ordinal=child_id;assign block_launch_sm=launch_owner>=0?32'(launch_owner):0;assign block_launch_row=32'(dispatched_blocks/TILE_COLS);assign block_launch_col=32'(dispatched_blocks%TILE_COLS);assign block_done_valid=completion_owner>=0;assign block_done_ordinal=completion_owner>=0?child_done_id[completion_owner]:0;assign block_done_sm=completion_owner>=0?32'(completion_owner):0;assign block_done_row=block_done_ordinal/32'(TILE_COLS);assign block_done_col=block_done_ordinal%32'(TILE_COLS);
 always_ff @(posedge clk)begin
  if(rst)begin
   state<=IDLE;setup_left<=0;launch_owner<=-1;launch_cursor<=0;completion_cursor<=0;elapsed_cycles<=0;saved_id<=0;saved_a<=0;saved_b<=0;saved_c<=0;dispatched_blocks<=0;completed_blocks<=0;
   for(int block_index=0;block_index<BLOCKS;block_index++)begin launched[block_index]<=0;completed[block_index]<=0;end
  end else begin
   if(launch_valid&&state==IDLE&&!launch_legal)$fatal(1,"Invalid resident grid launch allocation");
   if(state==RUN&&resident_blocks!=dispatched_blocks-completed_blocks)$fatal(1,"Grid dispatch/retirement conservation failed");
   case(state)
    IDLE:if(launch_valid&&launch_ready)begin
     launch_owner<=-1;launch_cursor<=0;completion_cursor<=0;elapsed_cycles<=0;saved_id<=launch_id;saved_a<=a_base;saved_b<=b_base;saved_c<=c_base;
     dispatched_blocks<=0;completed_blocks<=0;
     for(int block_index=0;block_index<BLOCKS;block_index++)begin launched[block_index]<=0;completed[block_index]<=0;end
     setup_left<=kernel_setup_cycles-1;state<=kernel_setup_cycles>0?STARTUP:RUN;
    end
    STARTUP:begin elapsed_cycles<=elapsed_cycles+1;if(setup_left<=0)state<=RUN;else setup_left<=setup_left-1;end
    RUN:begin
     elapsed_cycles<=elapsed_cycles+1;
     if(launch_owner<0&&dispatched_blocks<BLOCKS)begin
      int choice;choice=-1;
      for(int off=0;off<SMS;off++)begin int sm;sm=(launch_cursor+off)%SMS;
       if(choice<0&&child_launch_ready[sm])choice=sm;
      end
      if(choice>=0)launch_owner<=choice;
     end
     if(block_launch_valid)begin launch_cursor<=(launch_owner+1)%SMS;launch_owner<=-1;end
     if(block_done_valid)completion_cursor<=(completion_owner+1)%SMS;
     if(block_launch_valid)begin
      if(dispatched_blocks>=BLOCKS||launched[dispatched_blocks])$fatal(1,"Duplicate/out-of-range grid dispatch");
      launched[dispatched_blocks]<=1;dispatched_blocks<=dispatched_blocks+1;
     end
     if(block_done_valid)begin
      if(block_done_ordinal>=BLOCKS)$fatal(1,"Out-of-range grid completion");
      else if(!launched[block_done_ordinal]||completed[block_done_ordinal])$fatal(1,"Unlaunched/duplicate grid completion");
      completed[block_done_ordinal]<=1;completed_blocks<=completed_blocks+1;
     end
     if(dispatched_blocks==BLOCKS&&completed_blocks==BLOCKS&&resident_blocks==0)state<=COMPLETE;
    end
    COMPLETE:if(done_valid&&done_ready)state<=IDLE;
    default:$fatal(1,"Invalid resident grid state");
   endcase
  end
 end
endmodule
