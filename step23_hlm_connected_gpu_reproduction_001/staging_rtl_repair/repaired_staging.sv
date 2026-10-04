module repaired_staging #(parameter int CONTEXTS=3,M=128,N=96,K=12288,READY_FLOOR=340)(
 input logic clk,rst,input logic[63:0]cycle,
 input logic req_valid,output logic req_ready,input logic[31:0]req_context,req_id,a_base,b_base,cta_row,cta_col,stage_index,
 output logic backing_valid,input logic backing_ready,output logic[31:0]backing_id,backing_address,backing_context,backing_group,backing_sector,
 input logic response_valid,input logic[31:0]response_id,input logic[255:0]response_data,
 output logic write_valid,input logic write_ready,output logic[31:0]write_context,write_addresses[32],output logic[15:0]write_halfwords[32],
 output logic done_valid,input logic done_ready,output logic[31:0]done_context,done_id,
 output logic[CONTEXTS-1:0]context_ready,output int outstanding,
 output logic[63:0]sector_count,commit_count,completion_count,instruction_count
);
 `include "producer_tables.svh"
 localparam logic[63:0] NEVER=64'hffffffffffffffff;
 logic active[CONTEXTS],finished[CONTEXTS];int pcs[CONTEXTS][4];
 logic[31:0]ids[CONTEXTS],aa[CONTEXTS],bb[CONTEXTS],rows[CONTEXTS],cols[CONTEXTS],stages[CONTEXTS];
 logic[63:0]regready[CONTEXTS][4][64],readrelease[CONTEXTS][4][64],tags[CONTEXTS][4][6];
 logic[15:0]payload[CONTEXTS][64][32];
 int lcount,scount,cursor,done_cursor;logic[31:0]next_id;
 int lc[32],lw[32],li[32],lg[32],la[32],lr[32];logic[31:0]lid[32];logic[63:0]lissue[32],ldue[32];
 int sc[32],sg[32];logic[63:0]sdue[32];
 int offer,selected_done;logic legal;
 function automatic logic[63:0]umax(input logic[63:0]a,b);return a>b?a:b;endfunction
 function automatic logic eligible(input int c,w,idx,input logic[63:0]t);
  logic ok;logic[63:0]src,dst;int req;ok=1;src=op_src(idx);dst=op_dst(idx);req=op_req(idx);
  for(int r=0;r<64;r++)begin if(src[r]&&regready[c][w][r]>t)ok=0;if(dst[r]&&(regready[c][w][r]>t||readrelease[c][w][r]>t))ok=0;end
  for(int b=0;b<6;b++)if((req&(1<<b))&&tags[c][w][b]>t)ok=0;
  for(int l=0;l<32;l++)if(l<lcount&&lc[l]==c&&lw[l]==w&&op_wr(li[l])>=0&&(req&(1<<op_wr(li[l]))))ok=0;
  return ok;
 endfunction
 always_comb begin
  legal=req_context<CONTEXTS&&cta_row<M/32&&cta_col<N/32&&stage_index<K/32&&!a_base[0]&&!b_base[0];req_ready=0;if(legal)req_ready=!active[req_context];
  outstanding=0;for(int c=0;c<CONTEXTS;c++)begin context_ready[c]=!active[c];if(active[c])outstanding++;end
  offer=-1;for(int l=0;l<32;l++)if(l<lcount&&la[l]<2&&offer<0)offer=l;
  backing_valid=offer>=0;backing_id=0;backing_address=0;backing_context=0;backing_group=0;backing_sector=0;
  if(offer>=0)begin backing_id=lid[offer]+32'(la[offer]);backing_context=lc[offer];backing_group=lg[offer];backing_sector=la[offer];
   if(lg[offer]<32)backing_address=aa[lc[offer]]+32'(2*(64'(rows[lc[offer]]*32+lg[offer])*K+stages[lc[offer]]*32));
   else backing_address=bb[lc[offer]]+32'(2*(64'(stages[lc[offer]]*32+lg[offer]-32)*N+cols[lc[offer]]*32));
   backing_address+=32'(32*la[offer]);end
  write_valid=scount>0&&sdue[0]<=cycle;write_context=write_valid?sc[0]:0;for(int a=0;a<32;a++)begin write_addresses[a]=write_valid?32'(2*(sg[0]*32+a)):0;write_halfwords[a]=write_valid?payload[sc[0]][sg[0]][a]:0;end
  selected_done=-1;for(int x=0;x<CONTEXTS;x++)if(finished[(done_cursor+x)%CONTEXTS]&&selected_done<0)selected_done=(done_cursor+x)%CONTEXTS;
  done_valid=selected_done>=0;done_context=selected_done>=0?selected_done:0;done_id=selected_done>=0?ids[selected_done]:0;
 end
 // Blocking updates intentionally mirror the frozen executable's explicit edge
 // transition order. This is behavioral simulation RTL, not synthesis-ready RTL.
 always @(posedge clk)begin : transition
  int c,w,idx,selected,x,group_value,l,b;logic found,ended;logic[63:0]src,dst;
  if(rst)begin lcount=0;scount=0;cursor=0;done_cursor=0;next_id=1;sector_count=0;commit_count=0;completion_count=0;instruction_count=0;
   for(c=0;c<CONTEXTS;c++)begin active[c]=0;finished[c]=0;ids[c]=0;aa[c]=0;bb[c]=0;rows[c]=0;cols[c]=0;stages[c]=0;
    for(w=0;w<4;w++)begin pcs[c][w]=0;for(int r=0;r<64;r++)begin regready[c][w][r]=0;readrelease[c][w][r]=0;end for(b=0;b<6;b++)tags[c][w][b]=0;end
    for(int g=0;g<64;g++)for(int a=0;a<32;a++)payload[c][g][a]=0;
   end
  end else begin
   if(req_valid&&req_ready)begin c=int'(req_context);active[c]=1;finished[c]=0;ids[c]=req_id;aa[c]=a_base;bb[c]=b_base;rows[c]=cta_row;cols[c]=cta_col;stages[c]=stage_index;
    for(w=0;w<4;w++)begin pcs[c][w]=0;for(int r=0;r<64;r++)begin regready[c][w][r]=0;readrelease[c][w][r]=0;end for(b=0;b<6;b++)tags[c][w][b]=0;end
    for(int g=0;g<64;g++)for(int a=0;a<32;a++)payload[c][g][a]=0;
   end
   if(backing_valid&&backing_ready)begin la[offer]++;sector_count++;end
   if(response_valid)begin found=0;for(l=0;l<32;l++)if(l<lcount&&response_id>=lid[l]&&response_id<lid[l]+2)begin
    b=int'(response_id-lid[l]);if((lr[l]&(1<<b))||b>=la[l])$fatal(1,"duplicate/unaccepted sector response");lr[l]|=1<<b;for(int a=0;a<16;a++)payload[lc[l]][lg[l]][b*16+a]=response_data[a*16+:16];
    if(lr[l]==3)ldue[l]=umax(lissue[l]+READY_FLOOR,cycle+1);found=1;end if(!found)$fatal(1,"unowned sector response");end
   if(write_valid&&write_ready)begin for(l=0;l<31;l++)begin sc[l]=sc[l+1];sg[l]=sg[l+1];sdue[l]=sdue[l+1];end scount--;commit_count++;end
   if(done_valid&&done_ready)begin active[selected_done]=0;finished[selected_done]=0;done_cursor=(selected_done+1)%CONTEXTS;completion_count++;end
   l=0;while(l<lcount)begin if(ldue[l]<=cycle)begin c=lc[l];w=lw[l];dst=op_dst(li[l]);for(int r=0;r<64;r++)if(dst[r])regready[c][w][r]=ldue[l];b=op_wr(li[l]);if(b>=0)tags[c][w][b]=umax(tags[c][w][b],ldue[l]);
     for(int j=l;j<31;j++)begin lc[j]=lc[j+1];lw[j]=lw[j+1];li[j]=li[j+1];lg[j]=lg[j+1];la[j]=la[j+1];lr[j]=lr[j+1];lid[j]=lid[j+1];lissue[j]=lissue[j+1];ldue[j]=ldue[j+1];end lcount--;
    end else l++;end
   selected=-1;for(int off=0;off<CONTEXTS*4;off++)begin x=(cursor+off)%(CONTEXTS*4);c=x/4;w=x%4;idx=pcs[c][w];if(active[c]&&!finished[c]&&idx<PATH_LEN&&selected<0&&eligible(c,w,idx,cycle)&&!(op_kind(idx)==1&&lcount>=32)&&!(op_kind(idx)==2&&scount>=32))selected=x;end
   if(selected>=0)begin c=selected/4;w=selected%4;idx=pcs[c][w];src=op_src(idx);dst=op_dst(idx);group_value=op_group(idx);group_value=group_value<32?group_value*4+w:32+(group_value-32)*4+w;
    if(op_kind(idx)==1)begin l=lcount;lcount++;lc[l]=c;lw[l]=w;li[l]=idx;lg[l]=group_value;lid[l]=next_id;next_id+=2;lissue[l]=cycle;ldue[l]=NEVER;la[l]=0;lr[l]=0;
     for(int r=0;r<64;r++)begin if(dst[r])regready[c][w][r]=NEVER;if(src[r])readrelease[c][w][r]=umax(readrelease[c][w][r],cycle+1);end b=op_rd(idx);if(b>=0)tags[c][w][b]=umax(tags[c][w][b],cycle+1);
    end else begin for(int r=0;r<64;r++)begin if(dst[r])regready[c][w][r]=cycle+1;if(src[r])readrelease[c][w][r]=umax(readrelease[c][w][r],cycle+1);end b=op_wr(idx);if(b>=0)tags[c][w][b]=umax(tags[c][w][b],cycle+1);b=op_rd(idx);if(b>=0)tags[c][w][b]=umax(tags[c][w][b],cycle+1);
     if(op_kind(idx)==2)begin sc[scount]=c;sg[scount]=group_value;sdue[scount]=cycle+1;scount++;end end
    pcs[c][w]++;cursor=(selected+1)%(CONTEXTS*4);instruction_count++;
   end
   for(c=0;c<CONTEXTS;c++)if(active[c]&&!finished[c])begin ended=1;for(w=0;w<4;w++)if(pcs[c][w]!=PATH_LEN)ended=0;for(l=0;l<32;l++)if(l<lcount&&lc[l]==c)ended=0;for(l=0;l<32;l++)if(l<scount&&sc[l]==c)ended=0;if(ended)finished[c]=1;end
  end
 end
endmodule
