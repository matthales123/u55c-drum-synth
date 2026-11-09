`include "one_column.sv"

module multi_column #(
  parameter eta=9,
  parameter g_tension=5,
  parameter number_of_columns=31
) (
  input clk,
  input reset,
  input [9:0] number_of_rows,
  input signed [17:0] init_node,
  input signed [17:0] incr_value_col,
  input signed [17:0] incr_value_row,
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
  reg signed [17:0] init_incr_amplitude_array [number_of_columns-1:0];
  reg signed [17:0] init_incr_amplitude_value;
  wire one_column_reset;
  wire signed [17:0] curr_node_out [number_of_columns-1:0];
  wire signed [17:0] center_node_array [number_of_columns-1:0];
  wire [12:0] cycle_time [number_of_columns-1:0];
  assign cycle_time_out = cycle_time[number_of_columns>>1];
  
  wire [number_of_columns-1:0] finished_array ;
  assign finished = (&finished_array);

  // nonlinear rho effect calculation moodule
  rho_update #(g_tension) rho_inst
  (
    .init_rho(init_rho),
    .center_node(center_node_out),
    .rho_value(rho)
  );
  
  // generate block to connect column modules based on number_of_columns in the drum
  
  generate                                   // indicate start of generate block
        genvar n;                              // instantiate a genvar called n
        for (n=0; n<number_of_columns; n=n+1) begin: columnGen  // a for loop which increments n from 0 to 6 (named)
				one_column DUT (
				  .clk(clk),
				  .reset(one_column_reset),
				  .number_of_rows(number_of_rows),
                  .eta(eta),
                  .enable_iter(enable),
                  .left_node((n==0)? 0 : curr_node_out[n-1]), 
                  .right_node((n==number_of_columns-1)? 0: curr_node_out[n+1]),
                  .rho(rho),  
                  .init_center_amplitude(init_center_node_array[n]),
                  .init_incr_amplitude(init_incr_amplitude_array[n]),
                  .curr_node_output(curr_node_out[n]),
                  .center_node_output(center_node_array[n]),
						.cycle_time(cycle_time[n]),
						.finished(finished_array[n])
				);
        end
    endgenerate
	

  assign center_node_out = center_node_array[number_of_columns>>1];

  localparam RESET_STATE = 2'd0;
  localparam SET_INIT_CONDITION = 2'd1;
  localparam ENABLE_SYN_SIGNAL = 2'd2;
  localparam START_CALC = 2'd3;
  reg [9:0] init_counter;
  reg [1:0] state_curr, state_next;


  assign one_column_reset = (state_curr == ENABLE_SYN_SIGNAL);

  always @ (posedge clk) begin
    if (reset) begin
     state_curr <= RESET_STATE;
	  
    end else begin
      state_curr <= state_next;
    end
  end
  always@(*) begin
    case(state_curr)
	  RESET_STATE: state_next = SET_INIT_CONDITION;
	  SET_INIT_CONDITION:begin
	    if (init_counter == (number_of_columns - 1)) state_next = ENABLE_SYN_SIGNAL;
		else state_next = SET_INIT_CONDITION;
	  end
	  ENABLE_SYN_SIGNAL : state_next = START_CALC;
	  START_CALC : begin
		  if(reset) state_next = RESET_STATE;
		  else state_next = START_CALC;
	  end
	endcase
  end
  always@(posedge clk)begin
	case(state_curr)
	  RESET_STATE:begin
	   init_counter <= 0;
	   init_center_node_value <= init_node;
	   init_incr_amplitude_value <= init_node;
	  end
	  SET_INIT_CONDITION: begin
		init_counter <= init_counter + 1;
		init_center_node_value <= (init_counter < (number_of_columns >> 1)) ?  init_center_node_value + incr_value_row : init_center_node_value - incr_value_row ;
		init_center_node_array[init_counter] <= init_center_node_value ;
		init_incr_amplitude_value <= (init_counter < (number_of_columns >> 1)) ? init_incr_amplitude_value + incr_value_col : init_incr_amplitude_value - incr_value_col;
		init_incr_amplitude_array[init_counter] <= init_incr_amplitude_value;
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
