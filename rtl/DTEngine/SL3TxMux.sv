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
	The SL3 TX MUX, selects between 3 streams:
	- PCIe Trees\Data when trees or data are  not broadcasted: 
	  (If trees are broadcasted then data will not be broadcasted, if trees are not broadcasted then 
	  data will be broadcasted)
	- Broadcasted trees or data coming from input distributer
	- Results comming from Result combiner

	Default Packet Sizes: (but it is SW programmable)
	- Results :   1  CL : 128-bits
	- Trees/Data: 16 CLs: 128-bits * 16

*/

import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;

import DTEngine_Types::*;

module SL3TxMux (
	input  wire                         clk,   
	input  wire                         rst_n, 
	input  wire							start_core,  

	input  wire  [PACKET_SIZE_BITS-1:0] result_packet_numcls_minus_one, 
	input  wire  [PACKET_SIZE_BITS-1:0] tree_weight_packet_numcls_minus_one,
	input  wire  [PACKET_SIZE_BITS-1:0] data_packet_numcls_minus_one, 
	input  wire  [PACKET_SIZE_BITS-1:0] tree_findex_packet_numcls_minus_one, 

	output reg   [31:0] 				num_sent_lines, 
	output reg   [31:0] 				num_sent_packets,
	output reg   [31:0] 				packets_line,

	input  CoreDataIn                   sl3_tx_pcie, 
    input  wire  [DEVICE_ID_WIDTH-1:0]  sl3_tx_pcie_address,
	input  wire                         sl3_tx_pcie_valid, 
	output wire 						sl3_tx_pcie_ready,

	input  wire  [DATA_BUS_WIDTH-1:0]   sl3_tx_res, 
	input  wire 						sl3_tx_res_valid, 
	output wire 						sl3_tx_res_ready, 
	input  wire  [DEVICE_ID_WIDTH-1:0]  results_address,

	input  wire  [DEVICE_ID_WIDTH-1:0]  broadcast_address,
	input  CoreDataIn                   sl3_tx_distr, 
	input  wire                         sl3_tx_distr_valid, 
	output wire 						sl3_tx_distr_ready, 

	output UserPacketWord               user_network_tx, 
	input  wire                         user_network_tx_ready

);





UserPacketWord 							result_packet;
UserPacketWord							results_fifo_dout;
wire 									results_fifo_valid;
wire 									results_fifo_full;
wire 									results_fifo_re;


UserPacketWord                     	 	input_packet;
UserPacketWord                     		input_fifo_dout;
wire 									input_line_valid;
wire 									input_fifo_full;
wire 									input_fifo_valid;
wire 									input_fifo_re;

UserPacketWord 							packet_tx;
UserPacketWord 							packet_fifo_dout;
wire 									packet_fifo_full;
wire 									packet_fifo_valid;
wire 									packet_tx_valid;

reg 									select_input_packet;
reg 									select_result_packet;
reg 									input_packet_lock_set;
reg 									result_packet_lock_set;
reg 									result_priority;

reg 	[PACKET_SIZE_BITS-1:0]			packet_numcls;
reg 									input_line_last;
reg 	[PACKET_SIZE_BITS-1:0]			input_cl_count;
reg 	[PACKET_SIZE_BITS-1:0]			result_cl_count;

reg     [15:0] 							input_line_metadata;
CoreDataIn                              input_line;
wire  	[DEVICE_ID_WIDTH-1:0]  			input_line_address;

////////////////////////////////////////////////////////////////////////////////////////////
/*  
 	Input Packet: 
 		If this is a host node then data/trees come from the distributor if they are broadcasted,
 		otherwise they come from PCIe.
 		If this is not a host node then every input comes from distributor
*/


/*
	If this is not a host node then every input comes through distributor
	if this is a host node then streams coming on PCIe has priority because streams come in order there
*/

assign input_line          = (sl3_tx_pcie_valid)? sl3_tx_pcie         : sl3_tx_distr;
assign input_line_address  = (sl3_tx_pcie_valid)? sl3_tx_pcie_address : broadcast_address;
assign input_line_valid    = (sl3_tx_pcie_valid)? 1'b1                : sl3_tx_distr_valid;

assign sl3_tx_pcie_ready   = ~input_fifo_full;
assign sl3_tx_distr_ready  = ~input_fifo_full;


////////////////////////////////////////////////////////////////////////////////////////////

// Count input lines and reset counter every time we reach a packet size
always@(posedge clk) begin 
	if(~rst_n | start_core) begin
		input_cl_count <= 0;

		num_sent_lines <= 0;
		num_sent_packets <= 0;

		packets_line <= 0; 
	end
	else begin 
	 	if(~input_fifo_full & input_line_valid) begin 
			input_cl_count <= input_cl_count + 1'b1;
			if(input_cl_count == packet_numcls) begin
				input_cl_count <= 0;
			end
			// 
			if(input_line_last) begin
				num_sent_packets <= num_sent_packets + 1'b1;
			end
			//
			num_sent_lines <= num_sent_lines + 1'b1;
		end
		//
		if(packet_tx_valid & ~packet_fifo_full) begin
			packets_line <= packets_line + 1'b1;
		end
	end

end

/*  Based on the input stream type and number of received lines
	we set the packet metadata, packet last flag and packet size. 
*/
always@(*) begin 
	// 
	input_line_metadata = DATA_STREAM;
	input_line_last     = 1'b0;
	packet_numcls       = 0;

	if(input_line_valid) begin
		if(input_line.data_valid) begin
			input_line_metadata = DATA_STREAM;
			packet_numcls       = data_packet_numcls_minus_one;

			if(input_cl_count == packet_numcls) begin
				input_line_last = 1'b1;
			end
		end
		else if(input_line.prog_mode) begin
			input_line_metadata = TREE_WEIGHT_STREAM;
			packet_numcls       = tree_weight_packet_numcls_minus_one;

			if(input_cl_count == packet_numcls) begin
				input_line_last = 1'b1;
			end
		end
		else begin 
			input_line_metadata = TREE_FINDEX_STREAM;
			packet_numcls       = tree_findex_packet_numcls_minus_one;

			if(input_cl_count == packet_numcls) begin
				input_line_last = 1'b1;
			end
		end
	end
end


// Input Packet
assign input_packet = '{data:     input_line.data, 
						valid:    input_line_valid, 
						address:  {2'b0, input_line_address, 4'b0000},
						metadata: input_line_metadata, 
						last:     input_line_last};

////////////////////////////////////////////////////////////////////////////////////////////
quick_fifo  #(.FIFO_WIDTH($bits(UserPacketWord)),     //      
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(508)
      ) input_fifo (
        .clk                (clk),
        .reset_n            (rst_n),
        .din                (input_packet),
        .we                 (input_line_valid),

        .re                 (input_fifo_re),
        .dout               (input_fifo_dout),
        .empty              (),
        .valid              (input_fifo_valid),
        .full               (input_fifo_full),
        .count              (),
        .almostfull         ()
    );


////////////////////////////////////////////////////////////////////////////////////////////
/*  
 	Result Packet: here we compose results packets from incoming results stream from the
 	results combiner. Packet size is specified by SW.

 	Results packets are fed then in results fifo.
*/
always@(posedge clk) begin 
	if(~rst_n | start_core) begin
		result_cl_count <= 0;
	end
	else if(~results_fifo_full & sl3_tx_res_valid) begin 
		result_cl_count <= result_cl_count + 1'b1;
		if(result_cl_count == result_packet_numcls_minus_one) begin
			result_cl_count <= 0;
		end
	end
end

assign result_packet = '{data:     sl3_tx_res, 
                         valid:    sl3_tx_res_valid, 
                         address:  {2'b0, results_address, 4'b0000},  
                         metadata: RESULTS_STREAM, 
                         last:     (result_cl_count == result_packet_numcls_minus_one)};


quick_fifo  #(.FIFO_WIDTH($bits(UserPacketWord)),     //      
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(508)
      ) results_fifo (
        .clk                (clk),
        .reset_n            (rst_n),
        .din                (result_packet),
        .we                 (sl3_tx_res_valid),

        .re                 (results_fifo_re),
        .dout               (results_fifo_dout),
        .empty              (),
        .valid              (results_fifo_valid),
        .full               (results_fifo_full),
        .count              (),
        .almostfull         ()
    );

assign sl3_tx_res_ready = ~results_fifo_full;

////////////////////////////////////////////////////////////////////////////////////////////
/*
	Multiplexer choosing between results stream and input data/trees stream

	The MUX allocates two locks, one for result packets and the other for input packet, 
	Initially both locks are reset, The MUX uses a round robin priority flag to select between
	input and results streams, once one of the stream is selected, its lock is set, and then the 
	MUX will always select that packet until the lock is reset then it changes priority
*/

always@(posedge clk) begin 
	if(~rst_n | start_core) begin
		input_packet_lock_set  <= 1'b0;
		result_packet_lock_set <= 1'b0;

		result_priority        <= 1'b0;  // 
	end
	else begin 
		//
		input_packet_lock_set <= select_input_packet;
		if(select_input_packet) begin
			if(input_fifo_valid & ~packet_fifo_full & input_fifo_dout.last) begin
				input_packet_lock_set <= 1'b0;
				result_priority       <= 1'b1;
			end
		end

		//
		result_packet_lock_set <= select_result_packet;
		if(select_result_packet) begin
			if(results_fifo_valid & ~packet_fifo_full & results_fifo_dout.last) begin
				result_packet_lock_set <= 1'b0;
				result_priority        <= 1'b0;
			end
		end
	end
end

always@(*) begin 
	select_input_packet  = 1'b0;
	select_result_packet = 1'b0;

	if(input_packet_lock_set) begin
		select_input_packet = 1'b1;
	end
	else if(result_packet_lock_set) begin 
		select_result_packet = 1'b1;
	end 
	else begin
		if(result_priority) begin
			if(results_fifo_valid) begin
				select_result_packet = 1'b1;
			end
			else if(input_fifo_valid) begin
				select_input_packet = 1'b1;
			end
		end
		else if(input_fifo_valid) begin
			select_input_packet = 1'b1;
		end
		else if(results_fifo_valid) begin
			select_result_packet = 1'b1;
		end
	end 
end

assign packet_tx       = (select_input_packet)? input_fifo_dout  : results_fifo_dout;
assign packet_tx_valid = (select_input_packet)? input_fifo_valid : results_fifo_valid;

assign results_fifo_re = select_result_packet & ~packet_fifo_full;
assign input_fifo_re   = select_input_packet  & ~packet_fifo_full;

////////////////////////////////////////////////////////////////////////////////////////////

quick_fifo  #(.FIFO_WIDTH($bits(UserPacketWord)),     //      
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(508)
      ) packet_fifo (
        .clk                (clk),
        .reset_n            (rst_n),
        .din                (packet_tx),
        .we                 (packet_tx_valid),

        .re                 (user_network_tx_ready),
        .dout               (packet_fifo_dout),
        .empty              (),
        .valid              (packet_fifo_valid),
        .full               (packet_fifo_full),
        .count              (),
        .almostfull         ()
    );


assign user_network_tx = '{data:     packet_fifo_dout.data, 
						   last:     packet_fifo_dout.last, 
						   address:  packet_fifo_dout.address, 
						   metadata: packet_fifo_dout.metadata, 
						   valid:    packet_fifo_valid};



endmodule