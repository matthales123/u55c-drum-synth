module compute_module (
    output signed [17:0]  next_node,
    input [4:0] eta,
    input signed [17:0] rho,
    input signed [17:0] prev_node,
    input signed [17:0] curr_node,
    input signed [17:0] left_node,
    input signed [17:0] right_node,
    input signed [17:0] up_node,
    input signed [17:0] down_node
);

logic signed [17:0] term1, term2, term3;
logic signed [17:0] mult_result;
logic signed[17:0] sum;

signed_mult mult_inst(
    .out(mult_result),
    .a(rho),
    .b(sum)
);
assign sum = (left_node - curr_node) + (right_node - curr_node) + (up_node - curr_node) + (down_node - curr_node);// - (curr_node << 2);
assign term1 = prev_node - (prev_node>>>eta); 
assign term2 = mult_result + (curr_node<<1) - term1;
assign next_node = term2 - (term2>>>eta);
    
endmodule