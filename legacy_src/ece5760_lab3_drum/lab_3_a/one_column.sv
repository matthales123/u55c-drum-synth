`include "compute_module.sv"
`include "signed_mult.sv"

module one_column (
    input clk,
    input reset,
    input [9:0] number_of_rows,
    input [4:0] eta,
    input enable_iter,
    input signed [17:0] left_node, 
    input signed [17:0] right_node,
    input signed [17:0] rho,  
    input signed [17:0] init_center_amplitude,
    input signed [17:0] init_incr_amplitude,
    output signed [17:0] curr_node_output,
    output signed [17:0] center_node_output,
	 output [17:0] cycle_time,
	 output finished
);

logic curr_we, prev_we;
logic [7:0] prev_read_addr, prev_write_addr, curr_read_addr, curr_write_addr;
logic [17:0] prev_node_read_data, prev_node_write_data, curr_node_read_data, curr_node_write_data;
logic signed [17:0] down_node, up_node, curr_node, prev_node, next_node;
logic signed [17:0] center_node;
logic signed [17:0] bottom_node_reg;
logic [9:0] counter;
logic [17:0]init_reg = 18'h0;
logic [17:0]incr_reg;
logic finished_reg;
logic [17:0] cycle_time_reg;

logic [3:0] curr_state, next_state;

localparam INIT = 4'd0;
localparam INIT_WRITE_M10K = 4'd1;
localparam PREPARE = 4'd2;
localparam UPDATE_0 = 4'd3;
localparam UPDATE_1 = 4'd4;
localparam DONE = 4'd5;

localparam BUFF_STATE = 4'd6;

assign center_node_output = center_node;
assign curr_node_output = curr_node;
assign finished = finished_reg;
assign cycle_time = cycle_time_reg;

always@(posedge clk) begin
   if(reset) curr_state <=  INIT;
   else curr_state <= next_state;
end

//state transition
always@(*)begin
    case(curr_state)
        INIT:begin
            if(enable_iter)next_state = INIT_WRITE_M10K;
            else next_state = INIT;
        end
        INIT_WRITE_M10K:begin
            if(counter == number_of_rows - 1)next_state = PREPARE;
            else next_state = INIT_WRITE_M10K;
        end
        PREPARE:begin
            next_state = UPDATE_0;
        end
        UPDATE_0:begin
            next_state = UPDATE_1;
        end
        UPDATE_1:begin
            if(counter == number_of_rows - 1)next_state = DONE;
            else next_state = PREPARE;
        end
        DONE:begin
            if(enable_iter)next_state = PREPARE;
            else next_state = DONE;
        end
        default:
            next_state = INIT;
    endcase
end
//counter and address logic
always@(posedge clk)begin
    case(curr_state)
        INIT:begin
            counter <= 0;
			curr_node <= 0;
			prev_node <= 0;
			up_node <= 0;
			down_node <= 0;
			bottom_node_reg <= 0;
			center_node <= 0;
			init_reg <= 0;
			finished_reg <= 0;
			cycle_time_reg <= 0;
        end
        INIT_WRITE_M10K:begin
		   cycle_time_reg <= 0;
			
			if((counter == 0) || (counter == number_of_rows - 1) ) init_reg <= 18'h0;
            else init_reg <= (counter <= (number_of_rows >> 1))? init_reg + init_incr_amplitude : init_reg - init_incr_amplitude;
            if(counter == number_of_rows - 1) counter <= 0;
            else counter <= counter + 1;
            if(counter == number_of_rows >> 1) center_node <= init_center_amplitude;
				finished_reg <= 0;
        end
        PREPARE:begin
		      cycle_time_reg <= cycle_time_reg + 1;
            finished_reg <= 0;
        end
        UPDATE_0:begin //read from M10k
		      cycle_time_reg <= cycle_time_reg + 1;
            prev_node <= prev_node_read_data;
            if(counter == number_of_rows - 1 )up_node <= 18'h0;
            else up_node <= curr_node_read_data;
            // // node 
            if(counter == 0)curr_node <= bottom_node_reg;
            else curr_node <= up_node;
            if(counter == 0) down_node <= 18'h0;
            else down_node <= curr_node;
            finished_reg <= 0;
        end
        UPDATE_1:begin
		      cycle_time_reg <= cycle_time_reg + 1;
            if(counter == number_of_rows) counter <= 0;
            else counter <= counter + 1;
            if(counter == 0)bottom_node_reg <= next_node;
            if(counter == (number_of_rows >> 1) )center_node <= next_node;
				finished_reg <= 0;
        end
        DONE:begin
		      cycle_time_reg <= 0;
            counter <= 0;
				finished_reg <= 1;
        end
        default:begin
            counter <= 0;
				finished_reg <= 0;
        end
            
    endcase
end

//control sig
always@(*)begin
    case(curr_state)
        INIT:begin
            prev_we = 0;
			prev_write_addr = 0;
			prev_read_addr = 0;
            prev_node_write_data = 0;
			curr_we = 0;
			curr_write_addr = 0;
			curr_read_addr = 0;
            curr_node_write_data = 0;
        end
        INIT_WRITE_M10K:begin
            //prev M10k
            prev_we = 1'b1; //write
            prev_write_addr = counter;
			prev_read_addr = 0;
            prev_node_write_data = init_reg;
            //bottom_node_reg = 18'h0;
            curr_we = 1'b1; 
            curr_write_addr = counter;
			curr_read_addr = 0;
            curr_node_write_data = init_reg;
        end
        PREPARE:begin
            //prev M10k
            prev_we = 1'b0;
            prev_read_addr = (counter==(number_of_rows)) ? 0 : counter;
			prev_write_addr = 0;
			prev_node_write_data = 0;
            //curr M10k
            curr_we = 1'b0;
            curr_read_addr = (counter==(number_of_rows-1)) ? 1 : counter + 1;
			curr_write_addr = 0;
			curr_node_write_data = 0;
        end
        UPDATE_0:begin //read from M10k
            //prev M10k
            prev_we = 1'b0;
            prev_read_addr = (counter==(number_of_rows)) ? 0 : counter;
			prev_write_addr = 0;
			prev_node_write_data = 0;
            //curr M10k
            curr_we = 1'b0;
            curr_read_addr = (counter==(number_of_rows-1)) ? 1 : counter + 1;
			curr_write_addr = 0;
			curr_node_write_data = 0;
        end
        UPDATE_1:begin
            //prev M10k
            prev_we = 1'b1; //write
            prev_write_addr = counter;
			prev_read_addr = 0;
            prev_node_write_data = curr_node;
            //curr M10k
            // if(counter == 0) bottom_node_reg = init_reg;
            curr_we = 1'b1 ; //write
            curr_write_addr = counter;
			curr_read_addr = 0;
            curr_node_write_data = next_node;
            // //node update
            // bottom_node_reg = next_node;
            // curr_node = up_node;
        end
        DONE:begin
			//prev M10k
            prev_we = 1'b0;
            prev_read_addr = 0;
			prev_write_addr = 0;
			prev_node_write_data = 0;
            //curr M10k
            curr_we = 1'b0;
            curr_read_addr = 0;
			curr_write_addr = 0;
			curr_node_write_data = 0;
        end
        default:begin
			//prev M10k
            prev_we = 1'b0;
            prev_read_addr = 0;
			prev_write_addr = 0;
			prev_node_write_data = 0;
            //curr M10k
            curr_we = 1'b0;
            curr_read_addr = 0;
			curr_write_addr = 0;
			curr_node_write_data = 0;
        end
    endcase
end



compute_module compute_inst(
    .next_node(next_node),
    .eta(eta),
    .rho(rho),
    .prev_node(prev_node),
    .curr_node(curr_node),
    .left_node(left_node),
    .right_node(right_node),
    .up_node(up_node),
    .down_node(down_node)
);

M10K curr_M10K(
    .clk(clk),
    .we(curr_we),
    .write_address(curr_write_addr),
    .read_address(curr_read_addr),
    .d(curr_node_write_data), //wr
    .q(curr_node_read_data)  //rd
);

M10K prev_M10K(
    .clk(clk),
    .we(prev_we),
    .write_address(prev_write_addr),
    .read_address(prev_read_addr),
    .d(prev_node_write_data),
    .q(prev_node_read_data)
);



endmodule


module M10K( 
    output reg [17:0] q,
    input [17:0] d,
    input [7:0] write_address, read_address,
    input we, clk
);
	 // force M10K ram style
    reg [17:0] mem [255:0]  /* synthesis ramstyle = "no_rw_check, M10K" */;
	 
    always @ (posedge clk) begin
        if (we) begin
            mem[write_address] <= d;
        end
        q <= mem[read_address]; // q doesn't get d in this clock cycle
    end
endmodule
