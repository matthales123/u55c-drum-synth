`timescale 1ns/1ns

module multi_column_tb();
	
	reg clk, reset;
	reg enable;
	
	wire signed [17:0] center_node_out;
	
	
	multi_column #(9, 3, 31) DUT (
	  .clk(clk),
	  .reset(reset),
	  .number_of_rows(10'd31),
	  .init_node(18'h00000),
	  .incr_value_col(18'h00091), 
	  .incr_value_row(18'h00888),
	  .init_center_node(18'h08000),
	  .init_rho(18'h01000), 
	  .enable(enable),
	  .center_node_out(center_node_out)
	);
	integer fd;
	logic sim_done;
	initial fd = $fopen("./log.txt", "w");
	//Initialize clocks and index
	initial begin
	  sim_done = 0;
	  clk = 1'b0;
      reset = 1'b0;
	  #1000000;
	  sim_done = 1;
	  $fclose(fd);
	  $finish;
	end
	
	//Toggle the clocks
	always begin
		#10
		clk  = !clk;
	end
	
	//Toggle iteration_enable signal
	always begin
		#2000
		enable = 1'b1;
		#20
		enable = 1'b0;
	end

	//Intialize and drive signals
	initial begin
		reset  = 1'b0;
		#10 
		reset  = 1'b1;
		#30
		reset  = 1'b0;
	end
	
	//always @(posedge clk) begin
	//  if(center_node_out!== 18'hx)$fwrite(fd, "%x\n", center_node_out);
	//	if (sim_done) begin
	//		$fclose(fd);
	//		$finish;
	//	  end
	
	//end
	
endmodule
