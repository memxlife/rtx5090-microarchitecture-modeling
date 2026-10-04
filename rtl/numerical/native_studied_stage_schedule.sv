// Generated from original_kernel_schedule.json; do not hand-edit controls.
// Source SHA256 caf4f615c0c29d25558d721963f78172b22923d91fdb4258539d2994dbb8af5b
package native_studied_stage_schedule;
 localparam int INSTRUCTIONS=40;
 typedef struct packed {logic[127:0] raw;logic[1:0] kind;logic operand_b;logic kk;logic[1:0] word_index;logic upper_half;} descriptor_t;
 function automatic descriptor_t descriptor(input int index);
  descriptor_t d;d='0;
  case(index)
   0:begin d.raw=128'h000ee8000c1019000008000a221c7980;d.kind=2'd1;d.operand_b=1'b1;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x1350 LD.E
   1:begin d.raw=128'h000f28000c101900000a000a221d7980;d.kind=2'd1;d.operand_b=1'b1;d.kk=1'b0;d.word_index=2'd1;d.upper_half=1'b0;end // 0x1360 LD.E
   2:begin d.raw=128'h000f68000c1019000008100a22187980;d.kind=2'd1;d.operand_b=1'b1;d.kk=1'b0;d.word_index=2'd2;d.upper_half=1'b0;end // 0x1370 LD.E
   3:begin d.raw=128'h000f62000c101900000a100a22197980;d.kind=2'd1;d.operand_b=1'b1;d.kk=1'b0;d.word_index=2'd3;d.upper_half=1'b0;end // 0x1380 LD.E
   4:begin d.raw=128'h000fe200080000000000000600067c82;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x1390 UMOV
   5:begin d.raw=128'h004fc400080000000000000900077c82;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x13a0 UMOV
   6:begin d.raw=128'h000fe4000f8e02000000000608087c35;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x13b0 IADD.64
   7:begin d.raw=128'h000ea6000c101900000c000a22057980;d.kind=2'd1;d.operand_b=1'b1;d.kk=1'b1;d.word_index=2'd0;d.upper_half=1'b0;end // 0x13c0 LD.E
   8:begin d.raw=128'h040fe200078210ff0000000806207211;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x13d0 LEA
   9:begin d.raw=128'h000ea6000c101900000e100a221a7980;d.kind=2'd1;d.operand_b=1'b1;d.kk=1'b1;d.word_index=2'd3;d.upper_half=1'b0;end // 0x13e0 LD.E
   10:begin d.raw=128'h000fe400008f14070000000906217211;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x13f0 LEA.HI.X
   11:begin d.raw=128'h000ea8000c101900000e000a22067980;d.kind=2'd1;d.operand_b=1'b1;d.kk=1'b1;d.word_index=2'd1;d.upper_half=1'b0;end // 0x1400 LD.E
   12:begin d.raw=128'h000ea8000c1019000000000a200c7980;d.kind=2'd1;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x1410 LD.E
   13:begin d.raw=128'h000ea8000c1019000002000a200d7980;d.kind=2'd1;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd1;d.upper_half=1'b0;end // 0x1420 LD.E
   14:begin d.raw=128'h000ea8000c1019000000100a200e7980;d.kind=2'd1;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd2;d.upper_half=1'b0;end // 0x1430 LD.E
   15:begin d.raw=128'h000ea8000c1019000002100a200f7980;d.kind=2'd1;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd3;d.upper_half=1'b0;end // 0x1440 LD.E
   16:begin d.raw=128'h000ea8000c101900000c100a22077980;d.kind=2'd1;d.operand_b=1'b1;d.kk=1'b1;d.word_index=2'd2;d.upper_half=1'b0;end // 0x1450 LD.E
   17:begin d.raw=128'h000ea8000c1019000000200a20087980;d.kind=2'd1;d.operand_b=1'b0;d.kk=1'b1;d.word_index=2'd0;d.upper_half=1'b0;end // 0x1460 LD.E
   18:begin d.raw=128'h000ea8000c1019000002200a20097980;d.kind=2'd1;d.operand_b=1'b0;d.kk=1'b1;d.word_index=2'd1;d.upper_half=1'b0;end // 0x1470 LD.E
   19:begin d.raw=128'h000ea8000c1019000000300a200a7980;d.kind=2'd1;d.operand_b=1'b0;d.kk=1'b1;d.word_index=2'd2;d.upper_half=1'b0;end // 0x1480 LD.E
   20:begin d.raw=128'h000ea2000c1019000002300a200b7980;d.kind=2'd1;d.operand_b=1'b0;d.kk=1'b1;d.word_index=2'd3;d.upper_half=1'b0;end // 0x1490 LD.E
   21:begin d.raw=128'h000fea00038000000000000000007948;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x14a0 WARPSYNC.ALL
   22:begin d.raw=128'h000fe200000000000000000000007918;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x14b0 NOP
   23:begin d.raw=128'h008fe80000000000000000001c1c723a;d.kind=2'd2;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x14c0 MOVM.16.MT88
   24:begin d.raw=128'h010ea80000000000000000001d1d723a;d.kind=2'd2;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd1;d.upper_half=1'b0;end // 0x14d0 MOVM.16.MT88
   25:begin d.raw=128'h020fe80000000000000000001818723a;d.kind=2'd2;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd2;d.upper_half=1'b0;end // 0x14e0 MOVM.16.MT88
   26:begin d.raw=128'h000e220000000000000000001919723a;d.kind=2'd2;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd3;d.upper_half=1'b0;end // 0x14f0 MOVM.16.MT88
   27:begin d.raw=128'h004fde00000418140000001c0c14723c;d.kind=2'd3;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x1500 HMMA.16816.F32.BF16
   28:begin d.raw=128'h000fe200000000000000000000007918;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x1510 NOP
   29:begin d.raw=128'h001fe20000041810000000180c10723c;d.kind=2'd3;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b1;end // 0x1520 HMMA.16816.F32.BF16
   30:begin d.raw=128'h000fe8000000000000000000050c723a;d.kind=2'd2;d.operand_b=1'b0;d.kk=1'b1;d.word_index=2'd0;d.upper_half=1'b0;end // 0x1530 MOVM.16.MT88
   31:begin d.raw=128'h000e28000000000000000000060d723a;d.kind=2'd2;d.operand_b=1'b0;d.kk=1'b1;d.word_index=2'd1;d.upper_half=1'b0;end // 0x1540 MOVM.16.MT88
   32:begin d.raw=128'h000fe8000000000000000000070e723a;d.kind=2'd2;d.operand_b=1'b0;d.kk=1'b1;d.word_index=2'd2;d.upper_half=1'b0;end // 0x1550 MOVM.16.MT88
   33:begin d.raw=128'h000e660000000000000000001a0f723a;d.kind=2'd2;d.operand_b=1'b0;d.kk=1'b1;d.word_index=2'd3;d.upper_half=1'b0;end // 0x1560 MOVM.16.MT88
   34:begin d.raw=128'h001fde00000418140000000c0814723c;d.kind=2'd3;d.operand_b=1'b0;d.kk=1'b1;d.word_index=2'd0;d.upper_half=1'b0;end // 0x1570 HMMA.16816.F32.BF16
   35:begin d.raw=128'h000fe200000000000000000000007918;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x1580 NOP
   36:begin d.raw=128'h002fde00000418100000000e0810723c;d.kind=2'd3;d.operand_b=1'b0;d.kk=1'b1;d.word_index=2'd0;d.upper_half=1'b1;end // 0x1590 HMMA.16816.F32.BF16
   37:begin d.raw=128'h000fdc00000000000000000000007918;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x15a0 NOP
   38:begin d.raw=128'h000fea00038000000000000000007948;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x15b0 WARPSYNC.ALL
   39:begin d.raw=128'h000fe200000000000000000000007918;d.kind=2'd0;d.operand_b=1'b0;d.kk=1'b0;d.word_index=2'd0;d.upper_half=1'b0;end // 0x15c0 NOP
   default:$fatal(1,"Native stage instruction index out of range");
  endcase
  return d;
 endfunction
endpackage
