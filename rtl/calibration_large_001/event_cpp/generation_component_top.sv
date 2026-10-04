module generation_component_top(input logic clk,rst,arm,arrival,release_ready,input logic[31:0]ag,rg,input logic[3:0]em,am,output logic arm_ready,arrival_ready,release_valid,active,output logic[31:0]generation,output logic[3:0]release_mask,arrived_mask);
cta_generation_barrier #(.RELEASE_DELAY(4)) b(.clk,.rst,.arm_valid(arm),.arm_ready,.arm_generation(ag),.expected_mask(em),.arrival_valid(arrival),.arrival_ready,.arrival_generation(rg),.arrival_mask(am),.release_valid,.release_ready,.generation,.release_mask,.arrived_mask,.active);
endmodule
