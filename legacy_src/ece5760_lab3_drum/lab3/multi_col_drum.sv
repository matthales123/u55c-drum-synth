`include "one_column.sv"

module multi_col_drum #(
  parameter eta=9,
  parameter g_tension=5,
  parameter number_of_columns=31
) (
  input clk,
  input reset,
  input [9:0] number_of_rows,
  input signed [17:0] init_node,
  input signed [17:0] incr_value_boundary,
  input signed [17:0] incr_value_center,
  input signed [17:0] init_center_node,
  input signed [17:0] init_rho,
  input enable,
  output signed [17:0] center_node_out,
  output        [12:0] cycle_time_out,
  output finished
);
  wire signed [17:0] rho;
  reg signed [17:0] init_center_node_array [number_of_columns-1:0];
  reg signed [17:0] init_center_node_value;
  reg signed [17:0] b_incr_array [number_of_columns-1:0];
  reg signed [17:0] b_incr_value;
  wire one_column_reset;

  // nonlinear rho effect calculation moodule
  rho_update #(g_tension) rho_inst
  (
    .init_rho(init_rho),
    .center_node(center_node_out),
    .rho_value(rho)
  );


  wire signed [17:0] curr_node_out [number_of_columns-1:0];
  wire signed [17:0] center_node [number_of_columns-1:0];
  wire [12:0] cycle_time [number_of_columns-1:0];
  assign cycle_time_out = cycle_time[number_of_columns>>1];
  
  wire [number_of_columns-1:0] finished_array ;
  assign finished = (finished_array == 31'h7fff_ffff);
  
  
  // generate block to connect column modules based on number_of_columns in the drum
  
  generate                                   // indicate start of generate block
        genvar n;                              // instantiate a genvar called n
        for (n=0; n<number_of_columns; n=n+1) begin: columnGen  // a for loop which increments n from 0 to 6 (named)
            //dflop u(.clock(clock),             // each time, instantiate a dflop module, connect to p
            //        .d(p[n]),
            //        .q(p[n+1]));
			if(n==0)begin
				one_column #(eta, g_tension) DUT (
				  .clk(clk),
				  .reset(one_column_reset),
				  .column_length(number_of_rows),
				  .init_node(init_node), 
				  .init_center_node(init_center_node_array[n]),//(18'h08000)
				  .init_rho(rho),
				  .incr_value(b_incr_array[n]),
				  .left_node(18'h0),//(18'h0) ,
				  .right_node(curr_node_out[n+1]),//(18'h0),
				  .enable(enable),
				  .center_node_output(center_node[n]),
				  .curr_node_output(curr_node_out[n]),
				  .finished(finished_array[n])
				);
			end
			else if (n==(number_of_columns-1)) begin
				one_column #(eta, g_tension) DUT (
				  .clk(clk),
				  .reset(one_column_reset),
				  .column_length(number_of_rows),
				  .init_node(init_node), 
				  .init_center_node(init_center_node_array[n]),//(18'h08000)
				  .init_rho(rho),
				  .incr_value(b_incr_array[n]),
				  .left_node(curr_node_out[n-1]),//(18'h0) ,
				  .right_node(18'h0),//(18'h0),
				  .enable(enable),
				  .center_node_output(center_node[n]),
				  .curr_node_output(curr_node_out[n]),
				  .finished(finished_array[n])
				);
			end
			else begin
				one_column #(eta, g_tension) DUT (
				  .clk(clk),
				  .reset(one_column_reset),
				  .column_length(number_of_rows), //(row_num),
				  .init_node(init_node), 
				  .init_center_node(init_center_node_array[n]),//(18'h08000)
				  .init_rho(rho),
				  .incr_value(b_incr_array[n]),
				  .left_node(curr_node_out[n-1]),//(18'h0) ,
				  .right_node(curr_node_out[n+1]),//(18'h0),
				  .enable(enable),
				  .center_node_output(center_node[n]),
				  .curr_node_output(curr_node_out[n]),
				  .finished(finished_array[n])
				);
			end
        end
    endgenerate
	

  assign center_node_out = center_node[number_of_columns>>1];

  localparam RESET = 2'd0;
  localparam SET_INIT_CONDITION = 2'd1;
  localparam ENABLE_SYN_SIGNAL = 2'd2;
  localparam START_CALC = 2'd3;
  reg [9:0] init_counter;
  reg [1:0] state_curr, state_next;


  assign one_column_reset = (state_curr == ENABLE_SYN_SIGNAL);

  always @ (posedge clk) begin
    if (reset) begin
     state_curr <= RESET;
	  
    end else begin
      state_curr <= state_next;
    end
  end
  always@(*) begin
    case(state_curr)
	  RESET: state_next = SET_INIT_CONDITION;
	  SET_INIT_CONDITION:begin
	    if (init_counter == (number_of_columns - 1)) state_next = ENABLE_SYN_SIGNAL;
		else state_next = SET_INIT_CONDITION;
	  end
	  ENABLE_SYN_SIGNAL : state_next = START_CALC;
	endcase
  end
  always@(posedge clk)begin
	case(state_curr)
	  RESET:begin
	   init_counter <= 0;
	   init_center_node_value <= init_node;
	   b_incr_value <= init_node;
	  end
	  SET_INIT_CONDITION: begin
		init_counter <= init_counter + 1;
		init_center_node_value <= (init_counter < (number_of_columns >> 1)) ?  init_center_node_value + incr_value_center : init_center_node_value - incr_value_center ;
		init_center_node_array[init_counter] <= init_center_node_value ;
		b_incr_value <= (init_counter < (number_of_columns >> 1)) ? b_incr_value + incr_value_boundary : b_incr_value - incr_value_boundary;
		b_incr_array[init_counter] <= b_incr_value;
	  end
	  default: begin
	    init_counter<= init_counter;
	  end
	endcase
  end
  

endmodule

module rho_update
#(parameter g_tension)
(
  input signed [17:0] init_rho,
  input signed [17:0] center_node,
  output signed [17:0] rho_value
);
  wire signed [17:0] rho_term1, rho_term2;
  assign rho_term1 = center_node >>> g_tension;
  signed_mult inst2 (
    .out(rho_term2),
    .a(rho_term1),
    .b(rho_term1)
  );
  assign rho_value = (18'h0FAE1 < (init_rho + rho_term2)) ? 18'h0FAE1 : (init_rho + rho_term2);
endmodule