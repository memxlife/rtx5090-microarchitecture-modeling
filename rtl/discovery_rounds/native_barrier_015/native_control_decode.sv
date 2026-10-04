package native_control_decode;
 typedef struct packed {logic[3:0] issue_delay;logic group_continue;logic[2:0] write_barrier;logic[2:0] read_barrier;logic[5:0] wait_mask;} control_t;
 function automatic control_t decode(input logic[127:0] raw);
  control_t c;
  c.issue_delay=raw[108:105];c.group_continue=raw[109];
  c.write_barrier=raw[112:110];c.read_barrier=raw[115:113];c.wait_mask=raw[121:116];
  return c;
 endfunction
endpackage
