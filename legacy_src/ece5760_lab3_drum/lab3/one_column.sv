module one_column#(parameter eta = 9, parameter g_tension = 3)
(
  input clk,
  input reset,
  input enable,
  input [9:0] column_length,
  input signed [17:0] init_center_node,
  input signed [17:0] init_node,
  input signed [17:0] init_rho,
  input signed [17:0] incr_value,
  input signed [17:0] left_node,
  input signed [17:0] right_node,
  output signed [17:0] center_node_output,
  output signed [17:0] curr_node_output,
  output finished
  
);
  logic signed [17:0] center_node;
  logic [9:0] counter;
  logic signed[17:0] init_node_val, init_node_val_temp;
  logic signed[17:0] top_node, bottom_node, curr_node, next_node, prev_node;
  logic prev_we, curr_we;
  logic [8:0] curr_write_addr, curr_read_addr;
  logic [8:0] prev_write_addr, prev_read_addr;
  logic [17:0] prev_node_write_data, prev_node_read_data, curr_node_write_data,  curr_node_read_data;
  logic [3:0] cur_state, next_state;
  logic finished_reg;
  
  
  localparam INIT = 4'd0;
  localparam INIT_WRITE = 4'd1;
  localparam INIT_READ_0 = 4'd2;
  localparam INIT_READ_1 = 4'd3;
  localparam PRE_CALC = 4'd4;
  localparam CALC = 4'd5;
  localparam DONE = 4'd6;
  
  assign center_node_output = center_node;
  assign curr_node_output = curr_node;
  assign finished = finished_reg;
  
  //next state
  always@(posedge clk) begin
	if(reset) begin
	  cur_state <= INIT;
	end
	else begin
	  cur_state <= next_state;
	end
  end
  
  always@(posedge clk)begin
	case(cur_state)
	  INIT : begin
	    counter <= 0;
	  end
	  INIT_WRITE: begin
	    counter <= counter + 1;
	  end
	  INIT_READ_1: begin
	    counter <= 0;
	  end
	  PRE_CALC: begin
	    counter <= counter;
	  end
	  CALC: begin
	    counter <= counter + 1;
	  end
	  DONE: begin
	    counter <= 0;
	  end
	  default:begin
	    counter <= 0;
	  end
	endcase
  end
  
  //counter
  always@(posedge clk) begin
    case(cur_state)
	  INIT : begin
	    //counter <= 0;
		finished_reg <= 0;
		init_node_val <= init_node;
		init_node_val_temp <= init_node;
		center_node <= init_center_node;
	  end
	  INIT_WRITE: begin
	    //counter <= counter + 1;
		init_node_val_temp <= (counter < column_length >> 1) ? init_node_val_temp + incr_value : init_node_val_temp - incr_value;
		init_node_val <= (init_node_val_temp < init_center_node) ? init_node_val_temp : init_center_node;
		curr_node <= (init_node_val_temp < init_center_node) ? init_node_val_temp : init_center_node;
	  end
	  INIT_READ_1: begin
	    //counter <= 0;
		curr_node <= curr_node_read_data;
	  end
	  PRE_CALC: begin
	    finished_reg <= 0;
        top_node <= curr_node_read_data;
        prev_node <= prev_node_read_data;
		center_node <= (counter == (column_length>>1)) ? next_node : center_node;
	  end
	  CALC: begin
	    //counter <= counter + 1;
		curr_node <= top_node;
		bottom_node <= curr_node;
		top_node <= curr_node_read_data;
		prev_node <= prev_node_read_data;
	  end
	  DONE: begin
	    //counter <= 0;
		finished_reg <= 1;
	  end
	endcase
  end
  
  //state transition
  always @(*)begin
	case(cur_state)
	  INIT: begin
	    next_state = INIT_WRITE;
	  end
	  INIT_WRITE: begin
	    if(counter == column_length - 1) next_state = INIT_READ_0;
	    else next_state = INIT_WRITE;
	  end
	  INIT_READ_0: begin
	    next_state = INIT_READ_1;
	  end
	  INIT_READ_1: begin
	    next_state = PRE_CALC;
	  end
	  PRE_CALC: begin
	    next_state = CALC;
	  end
	  CALC: begin
	    if(counter == column_length - 1) next_state = DONE;
	    else next_state = PRE_CALC;
	  end
	  DONE: begin
	    if(enable) next_state = PRE_CALC;
		else next_state = DONE;
	  end
	  default : begin
	    next_state = cur_state;
		cur_state = INIT;
	  end
	endcase
  end
  
  //M10K memory control singal
  always@(*) begin
    case(cur_state)
	  INIT_WRITE:begin
	    prev_we = 1;
		prev_write_addr = counter;
		prev_node_write_data = init_node_val;
		curr_we = 1;
		curr_write_addr = counter;
		curr_node_write_data = init_node_val;
		curr_read_addr = curr_read_addr;
		prev_read_addr = prev_read_addr;
		
	  end
	  INIT_READ_0:begin
	    prev_we = 0;
		prev_read_addr = prev_read_addr;
		curr_we = 0;
		curr_read_addr = 0;
		//
		prev_write_addr = prev_write_addr;
		curr_write_addr = curr_write_addr;
		prev_node_write_data = prev_node_write_data;
		curr_node_write_data = curr_node_write_data;
		
	  end
	  INIT_READ_1:begin
	    prev_we = 0;
		prev_read_addr = 0;
		curr_we = 0;
		curr_read_addr = 1;
		//
		prev_write_addr = prev_write_addr;
		curr_write_addr = curr_write_addr;
		prev_node_write_data = prev_node_write_data;
		curr_node_write_data = curr_node_write_data;
	  end
	  PRE_CALC: begin
	    prev_we = 0;
		curr_we = 0;
		//
		prev_write_addr = prev_write_addr;
		curr_write_addr = curr_write_addr;
		prev_node_write_data = prev_node_write_data;
		curr_node_write_data = curr_node_write_data;
		curr_read_addr = curr_read_addr;
		prev_read_addr = prev_read_addr;
	  end
	  CALC: begin
	    prev_we = 1;
		prev_write_addr = counter;
		prev_node_write_data = curr_node;
		curr_we = 1;
		curr_write_addr = counter;
		curr_node_write_data = next_node;
		curr_read_addr = (counter==(column_length-2)) ? 0 : (counter==(column_length-1) ? 1 : counter + 2);
        prev_read_addr = (counter==(column_length-1)) ? 0 : counter + 1;
	  end
	  DONE: begin
	    prev_we = prev_we;
		curr_we = curr_we;
		prev_write_addr = prev_write_addr;
		curr_write_addr = curr_write_addr;
		prev_node_write_data = prev_node_write_data;
		curr_node_write_data = curr_node_write_data;
		curr_read_addr = curr_read_addr;
		prev_read_addr = prev_read_addr;
	  end
	  default: begin
        prev_we = prev_we;
		curr_we = curr_we;
		prev_write_addr = prev_write_addr;
		curr_write_addr = curr_write_addr;
		prev_node_write_data = prev_node_write_data;
		curr_node_write_data = curr_node_write_data;
		curr_read_addr = curr_read_addr;
		prev_read_addr = prev_read_addr;
      end
    endcase
  end
  
  compute_module #(eta) compute_inst 
  (
    .curr_node(curr_node),
    .left(left_node),
    .right(right_node),
    .top((counter==(column_length-1))?18'd0:top_node),
    .bottom((counter==0)?18'd0:bottom_node),
    .prev_node(prev_node),
    .rho(init_rho),
    .next_node(next_node)
  );
  
  //2 M10K module
  M10K #(18) curr_node_mem(
    .clk(clk),
    .we(curr_we),
    .write_addr(curr_write_addr),
	.read_addr(curr_read_addr),
	.d(curr_node_write_data),
	.q(curr_node_read_data)
  );
  
  M10K #(18) prev_node_mem(
    .clk(clk),
    .we(prev_we),
    .write_addr(prev_write_addr),
	.read_addr(prev_read_addr),
	.d(prev_node_write_data),
	.q(prev_node_read_data)
  );
  
endmodule

module compute_module#(parameter eta = 9)(
  input signed [17:0] curr_node,
  input signed[17:0] prev_node,
  input signed[17:0] left,
  input signed[17:0] right,
  input signed[17:0] top,
  input signed[17:0] bottom,
  input signed[17:0] rho,
  output signed[17:0] next_node
);
  logic signed[17:0] sum;
  logic signed[17:0] mult_out;
  logic signed[17:0] term1, term2, term3;
  
  assign sum = (left - curr_node) + (right - curr_node) + (top - curr_node) + (bottom - curr_node);// - (curr_node << 2);
  
  signed_mult mult1(
    .out(mult_out),
    .a(sum),
	.b(rho)
  );
  
  //assign term1 = mult_out + (curr_node << 1);
  //assign term2 = prev_node - (prev_node >>> eta);
  //assign term3 = term1 - term2;
  //assign next_node = term3 - (term3 >>> eta);
  assign term1 = prev_node - (prev_node>>>eta); 
  assign term2 = mult_out + (curr_node<<1) - term1;
  assign next_node = term2 - (term2>>>eta);

endmodule


module signed_mult (out, a, b);
  output  signed  [17:0]  out;
  input   signed  [17:0]  a;
  input   signed  [17:0]  b;
  // intermediate full bit length
  wire  signed  [35:0]  mult_out;
  assign mult_out = a * b;
  // select bits for 1.18 fixed point
  assign out = {mult_out[35], mult_out[33:17]};
endmodule

module M10K #(parameter data_width) (
  input clk,
  input we,
  input [8:0] write_addr,
  input [8:0] read_addr,
  input [data_width-1:0] d,
  output reg [data_width-1:0] q
);
  reg [19:0] mem [511:0];
  
  always @ (posedge clk) begin
    if (we) begin
      mem[write_addr] <= d;
    end
	  q <= mem[read_addr][data_width-1:0];
  end
endmodule