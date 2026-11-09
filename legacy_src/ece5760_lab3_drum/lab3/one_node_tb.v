`timescale 1ns/1ns

module one_node_tb();
	
    reg clk, reset;
    reg signed [17:0] node_init_val, rho_init_val;
	
    wire signed [17:0]  node_out;

    one_node #(9, 5) DUT (
      .clk(clk),
      .reset(reset),
      .node_init(node_init_val),
      .rho_init(rho_init_val), 
      .node_out(node_out)
    );

    //Initialize clocks and index
    initial begin
	  clk = 1'b0;
    	  reset = 1'b0;
    end
	
    //Toggle the clocks
    always begin
	#10
	clk  = !clk;
    end
	
    //Intialize and drive signals
    initial begin
	reset  = 1'b0;
	#10 
	reset  = 1'b1;
	#30
	reset  = 1'b0;
    end

    initial begin
	node_init_val = 18'sh04000;
	rho_init_val = 18'sh08000;
    end
	
endmodule


