`include "signed_mult.v"

module one_node 
#(parameter eta_delta_t, parameter g_tension)
(
  input logic clk, 
  input logic reset, 
  input logic [17:0] node_init,
  input logic [17:0] rho_init,
  output logic [17:0] node_out
);

logic signed [17:0] node_curr;
logic signed [17:0] node_prev;
logic signed [17:0] node_temp1, node_temp2, node_temp3, rho_temp1, rho_temp2;
logic signed [17:0] rho_curr;
logic signed [17:0] rho_prev;

assign node_temp1 = -(node_prev - (node_prev>>>eta_delta_t));

signed_mult mul_1 (
	.out(node_temp2),
	.a(node_curr<<<2),
	.b(rho_prev)
);

assign node_temp3 =  ((node_curr<<<1) - node_temp2 + node_temp1) - (((node_curr<<<1) - node_temp2 + node_temp1)  >>> eta_delta_t);

 signed_mult mul_2 (
  .out(rho_temp1),
  .a(node_curr>>>g_tension),
  .b(node_curr>>>g_tension)
);

assign rho_temp2 = (18'h0FAE1 < rho_init + rho_temp1) ? 18'h0FAE1 : rho_init + rho_temp1;

always@(posedge clk) begin
	if(reset) begin
		node_curr <= node_init;
		node_prev <= node_init;
		rho_curr <= rho_init;
		rho_prev <= rho_init;
	end else begin 
		node_curr <= node_temp3;
		node_prev <= node_curr;
		rho_curr <= rho_temp2;
		rho_prev <= rho_curr;
		
	end
end

assign node_out = node_curr;
  
endmodule