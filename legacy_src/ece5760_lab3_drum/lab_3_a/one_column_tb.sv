`include "one_column.sv"

module one_column_tb(
    
);
logic clk, reset, enable_iter;

one_column inst(
    .clk(clk),
    .reset(reset),
    .number_of_rows(10'd31),
    .eta(9),
    .enable_iter(enable_iter),
    .left_node(18'h0), 
    .right_node(18'h0),
    .rho(18'h01000),  
    .init_center_amplitude(18'h07ff8),
    .init_incr_amplitude(18'h00888)
);

always #10 clk = ~clk;


initial begin
    clk = 0;
    reset = 0;
    enable_iter = 0;
    #40
    reset = 1;
    #40
    reset = 0;
end

always begin
    #2000
    enable_iter = 1;
    #40;
    enable_iter = 0;
end

endmodule