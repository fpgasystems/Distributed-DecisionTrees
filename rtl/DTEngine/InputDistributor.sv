/*
 * Copyright 2018 - 2019 Systems Group, ETH Zurich
 *
 * This hardware operator is free software: you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as published
 * by the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
 
/*
    The Input Distriputor module implements input crossbars and broadcasting functionality.
    It receives Data/Trees from either PCIe or SL3, it forwards Data/Trees to local core
	and to SL3 if the Trees/Data need to be broadcasted for all FPGAs.


*/

import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;

import DTEngine_Types::*;

module InputDistributor (
	input  wire                         		clk,    // Clock
	input  wire                         		rst_n,  // Asynchronous reset active low
	input  wire 								start_core,
	input  wire 								host_node,               // if true, expect trees first
	input  wire 								data_distributed,        // if true, expect data through PCIe
	input  wire 								broadcast_trees, 
	input  wire 								broadcast_data, 
	input  wire 								last_node, 

	input  wire  [15:0] 						tree_weights_numcls_minus_one,
	input  wire  [15:0] 						tree_feature_index_numcls_minus_one,
	input  wire  [15:0] 						tuple_numcls_minus_one,	

	output reg   [15:0]    						received_data_with_weigths,
    output reg   [15:0]    						received_data_with_findex,	

	input  CoreDataIn                  			pcie_input, 
	input  wire 								pcie_input_valid, 
 	output wire 								pcie_input_ready, 
 	output reg                                  distributer_empty,

 	input  CoreDataIn                  			sl3_input, 
	input  wire 								sl3_input_valid, 
 	output wire 								sl3_input_ready, 

	output CoreDataIn                  			sl3_output, 
	output wire                         		sl3_output_valid, 
	input  wire 								sl3_output_ready, 

	output CoreDataIn                  		    core_output, 
	output wire                         		core_output_valid, 
	input  wire 								core_output_ready
);



CoreDataIn  							input_line;
wire 									input_line_valid;

CoreDataIn  							input_fifo_dout;
wire 									input_fifo_valid;
wire 									input_fifo_empty;

reg  									input_fifo_re;
wire 									input_fifo_full;

CoreDataIn 								core_input_fifo_dout;
wire 									core_input_fifo_full;
wire 									core_input_fifo_valid;
wire 									core_input_fifo_empty;

reg 									core_input_fifo_we;

reg 									dest_input_fifo_we;
wire 									dest_input_fifo_full;
wire 									dest_input_fifo_empty;

wire 									single_tree_weights_received;
wire 									single_tree_feature_indexes_received;
wire 									single_tuple_features_received;

wire 									data_last_flag;


reg  [15:0]    							received_cl_count;
reg  [15:0]    							received_weight_cl_count;
reg  [15:0]    							received_findex_cl_count;
reg  [15:0]    							received_tuple_cl_count;

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////              Trees Input Path               /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/* 
   If this is a host node then the input will come from PCIE only, if not then if data distributed 
   then data comes through PCIe and trees over SL3. if not then every thing comes through SL3
*/

////////////////////////////////////////////////////////////////////////////////////////////////////
assign input_line_valid  = (host_node)?  pcie_input_valid : 
						   (data_distributed)? sl3_input_valid | pcie_input_valid : sl3_input_valid;

assign input_line        = (host_node)? pcie_input :
				    	   (data_distributed)? ((sl3_input_valid)? sl3_input :  pcie_input) : sl3_input;

assign pcie_input_ready  = ~input_fifo_full;
assign sl3_input_ready   = ~input_fifo_full;

////////////////////////////////////////////////////////////////////////////////////////////////////
quick_fifo  #(.FIFO_WIDTH($bits(CoreDataIn)),     //      
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(508)
      ) input_fifo (
        .clk                (clk),
        .reset_n            (rst_n),
        .din                (input_line),
        .we                 (input_line_valid),

        .re                 (input_fifo_re),
        .dout               (input_fifo_dout),
        .empty              (input_fifo_empty),
        .valid              (input_fifo_valid),
        .full               (input_fifo_full),
        .count              (),
        .almostfull         ()
    );

always@(posedge clk) begin 
	if(~rst_n) begin
		distributer_empty <= 1'b0;
	end
	else begin 
		distributer_empty <= input_fifo_empty & core_input_fifo_empty & dest_input_fifo_empty;
	end
end
////////////////////////////////////////////////////////////////////////////////////////////////////
// Forward trees either to local core or to destination address

quick_fifo  #(.FIFO_WIDTH($bits(CoreDataIn)),     //      
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(508)
      ) core_input_fifo (
        .clk                (clk),
        .reset_n            (rst_n),
        .din                (input_fifo_dout),
        .we                 (core_input_fifo_we),

        .re                 (core_output_ready),
        .dout               (core_input_fifo_dout),
        .empty              (core_input_fifo_empty),
        .valid              (core_input_fifo_valid),
        .full               (core_input_fifo_full),
        .count              (),
        .almostfull         ()
    );


quick_fifo  #(.FIFO_WIDTH($bits(CoreDataIn)),     //      
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(508)
      ) dest_input_fifo (
        .clk                (clk),
        .reset_n            (rst_n),
        .din                (input_fifo_dout),
        .we                 (dest_input_fifo_we),

        .re                 (sl3_output_ready),
        .dout               (sl3_output),
        .empty              (dest_input_fifo_empty),
        .valid              (sl3_output_valid),
        .full               (dest_input_fifo_full),
        .count              (),
        .almostfull         ()
    );


////////////////////////////////////////////////////////////////////////////////////////////////////
always@(*) begin 
	//
	core_input_fifo_we = 1'b0;
	dest_input_fifo_we = 1'b0;
	input_fifo_re      = 1'b0;
	//
	if(input_fifo_valid) begin 
		// if the input fifo has data then we check if we should broadcast to dest address or not
		if(input_fifo_dout.data_valid) begin
			if(broadcast_data & ~last_node) begin
				core_input_fifo_we = ~dest_input_fifo_full;
				dest_input_fifo_we = ~core_input_fifo_full;
				input_fifo_re      = ~dest_input_fifo_full & ~core_input_fifo_full;
			end
			else begin 
				// if not broadcast, we send data to core 
				core_input_fifo_we = 1'b1;
				input_fifo_re      = ~core_input_fifo_full;
			end
		end
		else begin
			// If it is trees, we check if we should broadcast or not
			if(broadcast_trees & ~last_node) begin
				core_input_fifo_we = ~dest_input_fifo_full;
				dest_input_fifo_we = ~core_input_fifo_full;
				input_fifo_re      = ~dest_input_fifo_full & ~core_input_fifo_full;
			end
			else begin 
				// if not broadcast, we send trees to core 
				core_input_fifo_we = 1'b1;
				input_fifo_re      = ~core_input_fifo_full;
			end
		end
	end
end

////////////////////////////////////////////////////////////////////////////////////////////////////
// Separate individual trees (insert last signal for end of tree for local core)

always @(posedge clk) begin
	if(~rst_n) begin
		received_data_with_weigths  <= 0;
		received_data_with_findex   <= 0;
	end 
	else begin 

		if((received_tuple_cl_count > 0)  & (received_weight_cl_count > 0)) begin
			received_data_with_weigths <= received_data_with_weigths + 1'b1;
		end

		if((received_tuple_cl_count > 0)  & (received_findex_cl_count > 0)) begin
			received_data_with_findex <= received_data_with_findex + 1'b1;
		end
	end
end 

// count received cls to check if full tree weights, or full tree indexes or full tuple has been received.
always @(posedge clk) begin
	if(~rst_n | start_core) begin
		received_cl_count        <= 0;
		received_weight_cl_count <= 0;
		received_findex_cl_count <= 0;
		received_tuple_cl_count  <= 0;
	end 
	else if( core_input_fifo_valid & core_output_ready ) begin
		if( ~core_input_fifo_dout.data_valid &  core_input_fifo_dout.prog_mode ) begin 
			if(single_tree_weights_received) begin 
				received_weight_cl_count <= 0;
			end
			else begin 
				received_weight_cl_count <= received_weight_cl_count + 1'b1;
			end
		end
		else if( ~core_input_fifo_dout.data_valid &  ~core_input_fifo_dout.prog_mode  ) begin 
			if(single_tree_feature_indexes_received) begin 
				received_findex_cl_count <= 0;
			end
			else begin 
				received_findex_cl_count <= received_findex_cl_count + 1'b1;
			end
		end
		else if(core_input_fifo_dout.data_valid) begin
			if(single_tuple_features_received) begin 
				received_tuple_cl_count <= 0;
			end
			else begin 
				received_tuple_cl_count <= received_tuple_cl_count + 1'b1;
			end
		end
	end
end


assign single_tree_weights_received         = received_weight_cl_count == tree_weights_numcls_minus_one;
assign single_tree_feature_indexes_received = received_findex_cl_count == tree_feature_index_numcls_minus_one;
assign single_tuple_features_received       = received_tuple_cl_count  == tuple_numcls_minus_one;

assign data_last_flag      = (core_input_fifo_dout.data_valid)? single_tuple_features_received : 
                             (core_input_fifo_dout.prog_mode)?  single_tree_weights_received   : single_tree_feature_indexes_received;


assign core_output_valid = core_input_fifo_valid;
assign core_output       = '{prog_mode: core_input_fifo_dout.prog_mode, 
 						    last: data_last_flag, 
 						    data_valid: core_input_fifo_dout.data_valid, 
 						    data: core_input_fifo_dout.data}; 


endmodule