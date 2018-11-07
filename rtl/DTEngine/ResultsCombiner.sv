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
	Since the architecture is a ring, host node will push its local results to SL3 and write incoming SL3 
	results to PCIe. If data distributed, then it will push its local results to PCIe.
	Take care if only one node used, then local results are also passed to PCIe.

	If not a host node, then results 

	The results combiner merge results generated from local core with results coming over the SL3
	and either output the results to PCIe if it is a host node, or to SL3 if it has to 
	forward results to adjacent node.


*/

import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;

import DTEngine_Types::*;



module ResultsCombiner (
	input  wire                         clk,    // Clock
	input  wire                         rst_n,  // Asynchronous reset active low
	input  wire 						process_done,

	input  wire                         aggregEnabled,
	input  wire							multiple_nodes,
	input  wire							host_node, 

	input  wire   [DATA_PRECISION-1:0]  local_core_result, 
	input  wire 						local_core_result_valid, 
	output wire 						local_core_result_ready, 

	input  wire   [DATA_BUS_WIDTH-1:0]  sl3_result, 
	input  wire  						sl3_result_valid, 
	output wire 						sl3_result_ready,

	output wire   [DATA_BUS_WIDTH-1:0]  sl3_output, 
	output wire 						sl3_output_valid, 
	input  wire 						sl3_output_ready, 

	output wire   [DATA_BUS_WIDTH-1:0]  pcie_output,
	output wire 						pcie_output_valid, 
	input  wire 						pcie_output_ready, 

	output reg    [31:0]                pcie_res_lines,
	output reg    [31:0]                local_res_lines, 
	output reg    [31:0]                sl3_res_lines, 
	output reg    [31:0]                res_lines_lost,
	output reg    [31:0]                filled_lines
);


////////////////////////////////////////////////////////////////////////////////////////////////////

reg   [DATA_PRECISION-1:0]      local_core_result_line[3:0];
reg   [1:0]                     curr_word; 
reg 							local_core_result_line_filled;

wire  							fill_local_core_result_line;

reg  							aggreg_core_result_re;
wire  [DATA_BUS_WIDTH-1:0] 		aggreg_core_result_dout;
wire							aggreg_core_result_dout_valid;
wire							aggreg_core_result_full;


reg 							arbiter_state; 

reg   [DATA_BUS_WIDTH-1:0]  	sl3_result_line; 
reg  							sl3_result_line_valid;

reg   [DATA_BUS_WIDTH-1:0]  	pcie_result_line; 
reg  							pcie_result_line_valid;

wire 							pcie_result_fifo_re;
wire 							pcie_result_fifo_valid;
wire 							pcie_result_fifo_almostfull; 
wire 							pcie_result_fifo_full;
wire  [DATA_BUS_WIDTH-1:0]  	pcie_result_fifo_dout; 

wire							sl3_result_fifo_re;
wire 							sl3_result_fifo_valid;
wire 							sl3_result_fifo_almostfull; 
wire 							sl3_result_fifo_full;
wire  [DATA_BUS_WIDTH-1:0]  	sl3_result_fifo_dout; 

reg  							aggreg_sl3_result_re; 
wire 							aggreg_sl3_result_full;
wire 							aggreg_sl3_result_valid;
wire  [DATA_BUS_WIDTH-1:0]		aggreg_sl3_result_dout;


wire  [DATA_PRECISION+1:0]    	inputA[3:0];
wire  [DATA_PRECISION+1:0]    	inputB[3:0];
wire  [DATA_PRECISION+1:0]    	adderResult[3:0];

wire  [DATA_BUS_WIDTH-1:0]    	aggregate_result_line;

wire 						    aggreg_result_line_valid;


integer i;


////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////                                   /////////////////////////////
//////////////////////////////        Fill Core result in 128-bit line       ///////////////////////
////////////////////////////////////                                   /////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

assign fill_local_core_result_line = (local_core_result_valid)? 
                                     ((local_core_result_line_filled)? ~aggreg_core_result_full : 1'b1) : 1'b0;
                                     
// Fill Local core results in 128-bit line
always@(posedge clk) begin 
	if(~rst_n) begin 
		local_core_result_line_filled <= 1'b0;
		curr_word                     <= 2'b00;

		for (i = 0; i < 4; i=i+1) begin
			local_core_result_line[ i ] <= 32'b0;
		end
	end
	else begin 
		// curr_word:
		// local_core_result_line:
		if(fill_local_core_result_line) begin
			local_core_result_line[ curr_word ] <= local_core_result;
			curr_word                           <= curr_word + 1'b1;
		end
		// local_core_result_line_filled
		if((curr_word == 2'b11) & fill_local_core_result_line) begin
			local_core_result_line_filled <= 1'b1;
		end
		else if(~aggreg_core_result_full) begin 
			local_core_result_line_filled <= 1'b0;
		end
	end
end

assign local_core_result_ready = ~aggreg_core_result_full | ~local_core_result_line_filled;
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////                                   /////////////////////////////
//////////////////////////////       FIFOs before Combining Core & SL3       ///////////////////////
////////////////////////////////////                                   /////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

always@(posedge clk)  begin 
	if(~rst_n) begin
		local_res_lines <= 0;
		filled_lines    <= 0;
	end
	else begin 
		if(local_core_result_line_filled & ~aggreg_core_result_full) begin
			local_res_lines <= local_res_lines + 1'b1;
		end

		if(local_core_result_line_filled) begin
			filled_lines    <= filled_lines   + 1'b1;
		end
	end
		
end

// FIFOs holding results
quick_fifo  #(.FIFO_WIDTH(DATA_BUS_WIDTH),     // data + data valid flag + last flag + prog flags        
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(508)
      ) aggreg_core_result (
        .clk                (clk),
        .reset_n            (rst_n),
        .din                ({local_core_result_line[3], local_core_result_line[2], local_core_result_line[1], local_core_result_line[0]}),
        .we                 (local_core_result_line_filled),

        .re                 (aggreg_core_result_re),
        .dout               (aggreg_core_result_dout),
        .empty              (),
        .valid              (aggreg_core_result_dout_valid),
        .full               (aggreg_core_result_full),
        .count              (),
        .almostfull         ()
    );


assign sl3_result_ready = ~aggreg_sl3_result_full;

quick_fifo  #(.FIFO_WIDTH(DATA_BUS_WIDTH),     // data + data valid flag + last flag + prog flags        
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(508)
      ) aggreg_sl3_result (
        .clk                (clk),
        .reset_n            (rst_n),
        .din                (sl3_result),
        .we                 (sl3_result_valid),

        .re                 (aggreg_sl3_result_re),
        .dout               (aggreg_sl3_result_dout),
        .empty              (),
        .valid              (aggreg_sl3_result_valid),
        .full               (aggreg_sl3_result_full),
        .count              (),
        .almostfull         ()
    );


always@(posedge clk)  begin 
	if(~rst_n) begin
		sl3_res_lines <= 0;
	end
	else if(sl3_result_valid & ~aggreg_sl3_result_full) begin
		sl3_res_lines <= sl3_res_lines + 1'b1;
	end
end

// aggreg_core_result_re
always@(*)begin 
	aggreg_core_result_re = 1'b0;

	if(host_node) begin
		if(aggregEnabled) begin
			aggreg_core_result_re = ~sl3_result_fifo_full;
		end
		else if(~arbiter_state | ~aggreg_sl3_result_valid) begin
			aggreg_core_result_re = ~pcie_result_fifo_full;
		end
	end
	else begin 
		if(aggregEnabled) begin
			aggreg_core_result_re = ~sl3_result_fifo_almostfull;
		end
		else if(~arbiter_state | ~aggreg_sl3_result_valid) begin
			aggreg_core_result_re = ~sl3_result_fifo_full;
		end
	end
end

// aggreg_sl3_result_re
always@(*)begin 
	aggreg_sl3_result_re = 1'b0;

	if(host_node) begin
		if(aggregEnabled | arbiter_state | ~aggreg_core_result_dout_valid) begin
			aggreg_sl3_result_re = ~pcie_result_fifo_full;
		end
	end
	else begin 
		if(aggregEnabled) begin
			aggreg_sl3_result_re = ~sl3_result_fifo_almostfull;
		end
		else if(arbiter_state | ~aggreg_core_result_dout_valid) begin
			aggreg_sl3_result_re = ~sl3_result_fifo_full;
		end
	end
end


always@(posedge clk) begin 
	if(~rst_n) begin
		res_lines_lost <= 1'b0;
	end
	else if(aggreg_core_result_re & aggreg_core_result_dout_valid & aggreg_sl3_result_re & aggreg_sl3_result_valid) begin 
		res_lines_lost <= res_lines_lost + 1'b1;
	end
end
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////                                   /////////////////////////////
//////////////////////////////            Combine Results Adders             ///////////////////////
////////////////////////////////////                                   /////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

generate
	genvar j;
	for (j = 0; j < 4; j = j + 1) begin: aggregAdders

	    assign inputA[j] = {1'b0, {|(aggreg_core_result_dout[32*j+31:32*j])}, aggreg_core_result_dout[32*j+31:32*j] };
	    assign inputB[j] = {1'b0, {|(aggreg_sl3_result_dout[32*j+31:32*j])},  aggreg_sl3_result_dout[32*j+31:32*j] };
		
		FPAdder_8_23_uid2_l2 fpadder_1_x(
				.clk          (clk),
				.rst          (~rst_n),
				.seq_stall    (1'b0),
				.X            (inputA[j]),
				.Y            (inputB[j]),
				.R            (adderResult[j])
				);
	end

	assign aggregate_result_line = {adderResult[3][31:0], adderResult[2][31:0], adderResult[1][31:0], adderResult[0][31:0]};

endgenerate


delay #(.DATA_WIDTH(1),
	    .DELAY_CYCLES(FP_ADDER_LATENCY) 
	) fpadder_delay(

	    .clk              (clk),
	    .rst_n            (rst_n),
	    .data_in          (1'b1),   // 
	    .data_in_valid    (aggreg_sl3_result_valid & aggreg_core_result_dout_valid & ~sl3_result_fifo_almostfull),
	    .data_out         (),
	    .data_out_valid   (aggreg_result_line_valid)
	);

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////                                   /////////////////////////////
//////////////////////////////                 Outputs MUXs                  ///////////////////////
////////////////////////////////////                                   /////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/*
	if this is a host node, then 
		if data broadcasted then
			send local results over SL3
		else 
			send local results over PCIe
	else
		if data broadcasted then
			aggregate SL3 and local results and send them over SL3
		else if trees broadcasted  then
			send local results and SL3 results separately over SL3

*/
////////////////////////////////////////////////////////////////////////////////////////////////////
// arbiter state
always@(posedge clk) begin 
	if(~rst_n | process_done) begin
		arbiter_state <= 1'b0;
	end
	else if(multiple_nodes) begin 
		arbiter_state <= ~arbiter_state;
	end
end
// 
always@(*) begin 
	sl3_result_line       = 0;
	sl3_result_line_valid = 0;

	if(host_node) begin
		if(aggregEnabled) begin
			sl3_result_line       = aggreg_core_result_dout;
			sl3_result_line_valid = aggreg_core_result_dout_valid;
		end
	end
	else begin 
		if(aggregEnabled) begin
			sl3_result_line       = aggregate_result_line;
			sl3_result_line_valid = aggreg_result_line_valid;
		end
		else begin 
			if(~arbiter_state) begin
				if(aggreg_core_result_dout_valid) begin
					sl3_result_line       = aggreg_core_result_dout;
					sl3_result_line_valid = 1'b1;
				end
				else begin 
					sl3_result_line       = aggreg_sl3_result_dout;
					sl3_result_line_valid = aggreg_sl3_result_valid;
				end
			end
			else begin 
				if(aggreg_sl3_result_valid) begin
					sl3_result_line       = aggreg_sl3_result_dout;
					sl3_result_line_valid = 1'b1;			
				end
				else begin 
					sl3_result_line       = aggreg_core_result_dout;
					sl3_result_line_valid = aggreg_core_result_dout_valid;
				end
			end
		end
	end
end


quick_fifo  #(.FIFO_WIDTH(DATA_BUS_WIDTH),     // data + data valid flag + last flag + prog flags        
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(508)
      ) sl3_result_fifo (
        .clk                (clk),
        .reset_n            (rst_n),
        .din                (sl3_result_line),
        .we                 (sl3_result_line_valid),

        .re                 (sl3_result_fifo_re),
        .dout               (sl3_result_fifo_dout),
        .empty              (),
        .valid              (sl3_result_fifo_valid),
        .full               (sl3_result_fifo_full),
        .count              (),
        .almostfull         (sl3_result_fifo_almostfull)
    );


assign sl3_output             = sl3_result_fifo_dout; 
assign sl3_output_valid       = sl3_result_fifo_valid;
assign sl3_result_fifo_re     = sl3_output_ready;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

always@(*) begin 
	pcie_result_line       = 0;
	pcie_result_line_valid = 0;

	if(host_node) begin
		if(aggregEnabled) begin
			pcie_result_line       = aggreg_sl3_result_dout;
			pcie_result_line_valid = aggreg_sl3_result_valid;
		end
		else begin 
			if(~arbiter_state) begin
				if(aggreg_core_result_dout_valid) begin
					pcie_result_line       = aggreg_core_result_dout;
					pcie_result_line_valid = 1'b1;
				end
				else begin 
					pcie_result_line       = aggreg_sl3_result_dout;
					pcie_result_line_valid = aggreg_sl3_result_valid;
				end
			end
			else begin 
				if(aggreg_sl3_result_valid) begin
					pcie_result_line       = aggreg_sl3_result_dout;
					pcie_result_line_valid = 1'b1;			
				end
				else begin 
					pcie_result_line       = aggreg_core_result_dout;
					pcie_result_line_valid = aggreg_core_result_dout_valid;
				end
			end
		end
	end
end

always@(posedge clk) begin 
	if(~rst_n) begin
		pcie_res_lines <= 1'b0;
	end
	else if(pcie_result_line_valid & ~pcie_result_fifo_full) begin 
		pcie_res_lines <= pcie_res_lines + 1'b1;
	end
end

quick_fifo  #(.FIFO_WIDTH(DATA_BUS_WIDTH),     // data + data valid flag + last flag + prog flags        
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(508)
      ) pcie_result_fifo (
        .clk                (clk),
        .reset_n            (rst_n),
        .din                (pcie_result_line),
        .we                 (pcie_result_line_valid),

        .re                 (pcie_result_fifo_re),
        .dout               (pcie_result_fifo_dout),
        .empty              (),
        .valid              (pcie_result_fifo_valid),
        .full               (pcie_result_fifo_full),
        .count              (),
        .almostfull         (pcie_result_fifo_almostfull)
    );


assign pcie_output            = pcie_result_fifo_dout; 
assign pcie_output_valid      = pcie_result_fifo_valid;
assign pcie_result_fifo_re    = pcie_output_ready;

endmodule