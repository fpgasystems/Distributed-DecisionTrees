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
	The software part communicates with hardware part through PCIe and soft registers, 
	it triggers the DTEngine by writing a command to soft registers. If the node is a host node, then 
	it will start writing the tree ensemble to all FPGAs through PCIe. 

	If data comes from the host node only, then after writing all trees it starts writing data.
	If data is distributed then every node software starts writing data after writing the command to 
	the soft registers. 

	The PCIe receiver module will expect either trees or data or both. The PCIe receiver implements the functionality 
	of routing incoming stream from CPU to the target FPGA device (including local core).

	FSM: if host node set, it first receives trees then data, when it receives done signal 
	     it returns to IDLE state

	This 
*/

import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;

import DTEngine_Types::*;

module PCIeReceiver (
	input  wire                         		clk,    // Clock
	input  wire                         		rst_n,  // Asynchronous reset active low
	input  wire 								start_core, 
	input  wire 								process_done, 
	input  wire                         		pcie_receiver_enabled,
	input  wire 								host_node,               // if true, expect trees first
	input  wire 								data_distributed,        // if true, expect data through PCIe
	input  wire 								broadcast_trees, 
	input  wire 								broadcast_data, 
	input  wire  [31:0] 						core_data_batch_cls_minus_one,
	input  wire  [31:0]                 		total_num_trees_cls,
	input  wire  [31:0]                 		total_num_weights_cls, 
	input  wire  [15:0] 						numcls_local_weights_minus_one,
	input  wire  [15:0] 						numcls_local_findexes_minus_one,
	input  wire  [NUM_FPGA_DEVICES_BITS-1:0] 	numDevs_minus_one,
	input  wire  [DEVICE_ADDRESS_WIDTH-1:0]  	devices_list[NUM_FPGA_DEVICES-1:0],
	//
	output reg   [1:0]                          pcie_receiver_fsm_state,
	output reg 	 [31:0]                         pcie_numcls_received, 

	// PCIe Slot DMA interface
    input  PCIEPacket                  		 	pcie_packet_in,
    output wire                          		pcie_full_out,

    // Data/Trees to be sent for other nodes through SL3
    output CoreDataIn                  			sl3_output, 
    output wire  [DEVICE_ID_WIDTH-1:0]   	    sl3_output_address,
	output wire                         		sl3_output_valid, 
	input  wire 								sl3_output_ready, 

	// Data/Trees passed to local nodes
    output CoreDataIn                  			pcie_input, 
	output wire 								pcie_input_valid, 
 	input  wire 								pcie_input_ready, 
 	input  wire                                 distributer_empty 
	
);

//////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////

PCIEPacket                              input_fifo_dout;
wire 									input_fifo_re;
wire 									input_fifo_valid;

reg 									to_local_core;

reg  [15:0]       						currWCount;
reg  [15:0]       						currFCount;
reg  [NUM_FPGA_DEVICES_BITS-1:0]       	currDevID;
reg  [31:0]       						currDCount;
reg  [31:0]								numcls_received;


reg  [1:0] 								receiver_fsm_state;

CoreDataIn                  			input_line;


localparam  [1:0]  	IDLE          = 2'b00, 
					RECEIVE_TREES = 2'b01,
					WAIT_DATA     = 2'b10,  
					RECEIVE_DATA  = 2'b11;

//////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////

quick_fifo  #(.FIFO_WIDTH($bits(PCIEPacket)),     //      
              .FIFO_DEPTH_BITS(9),
              .FIFO_ALMOSTFULL_THRESHOLD(508)
      ) input_fifo (
        .clk                (clk),
        .reset_n            (rst_n),
        .din                (pcie_packet_in),
        .we                 (pcie_packet_in.valid),

        .re                 (input_fifo_re),
        .dout               (input_fifo_dout),
        .empty              (),
        .valid              (input_fifo_valid),
        .full               (pcie_full_out),
        .count              (),
        .almostfull         ()
    );



//////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////

assign input_line = '{last:1'b0, 
                      data: input_fifo_dout.data, 
                      data_valid: (receiver_fsm_state == RECEIVE_DATA), 
                      prog_mode: (numcls_received < total_num_weights_cls)};



assign input_fifo_re    = ((receiver_fsm_state == RECEIVE_DATA) | (receiver_fsm_state == RECEIVE_TREES)) & ((to_local_core)? pcie_input_ready : sl3_output_ready);

assign pcie_input       = input_line;
assign pcie_input_valid = input_fifo_valid & to_local_core & ((receiver_fsm_state == RECEIVE_DATA) | (receiver_fsm_state == RECEIVE_TREES)); 

assign sl3_output         = input_line;
assign sl3_output_valid   = input_fifo_valid & ~to_local_core  & ((receiver_fsm_state == RECEIVE_DATA) | (receiver_fsm_state == RECEIVE_TREES));
assign sl3_output_address = { {(DEVICE_ID_WIDTH - DEVICE_ADDRESS_WIDTH){1'b0}}, devices_list[currDevID]};


//////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////
always@(*) begin
	to_local_core = 1'b1;

	if(input_fifo_valid) begin
		if(receiver_fsm_state == RECEIVE_DATA) begin
			if(~broadcast_data) begin
				if( !(currDevID == 0) ) begin
					to_local_core = 1'b0;
				end
			end
		end
		else if(receiver_fsm_state == RECEIVE_TREES) begin 
			if(~broadcast_trees) begin
				if(numcls_received < total_num_weights_cls) begin
					if( !(currDevID == 0) ) begin
						to_local_core = 1'b0;
					end
				end
				else if( !(currDevID == 0) ) begin
					to_local_core = 1'b0;
				end
			end
		end
	end
end


//////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////////////
always @(posedge clk) begin
	if(~rst_n) begin
		receiver_fsm_state <= IDLE;

		currWCount <= 0;
		currFCount <= 0;
		currDevID  <= 0;
		currDCount <= 0;

		pcie_receiver_fsm_state <= 0;
		pcie_numcls_received    <= 0;

		numcls_received         <= 0;  
	end 
	else begin

		pcie_receiver_fsm_state <= receiver_fsm_state;
		pcie_numcls_received    <= numcls_received;

		case (receiver_fsm_state)
			IDLE: begin 
				currWCount <= 0;
				currFCount <= 0;
				currDevID  <= 0;
				currDCount <= 0;

				numcls_received <= 0; 

				/* If the node will receive trees, data or both over PCIe, then it will be enabled, 
				   if it is the master node then it will start receiving trees then data, if it is not 
				   a master node but data is distributed then we move to RECEIVE_DATA 
				*/
				if(start_core) begin
					if(pcie_receiver_enabled) begin 
						if(host_node) begin
							receiver_fsm_state <= RECEIVE_TREES;
						end
						else if(data_distributed) begin
							receiver_fsm_state <= RECEIVE_DATA;
						end
					end
				end
				
			end
			RECEIVE_TREES: begin 
				// If we receive all trees then we ready to receive data
				if(input_fifo_valid & input_fifo_re & (numcls_received == (total_num_trees_cls -1'b1))) begin
					receiver_fsm_state <= WAIT_DATA;
				end

				// numcls_received counter
				if(input_fifo_valid & input_fifo_re) begin
					numcls_received <= numcls_received + 1'b1;
					
					// currWCount: weights cls counter
					if(!broadcast_trees) begin
						if((numcls_received < total_num_weights_cls)) begin
							currWCount <= currWCount + 1'b1;

							// currDevID: if received weight cls reach node weights cls then we send 
							// next batch (if there is any) to next device in the list of devices
							if(currWCount == numcls_local_weights_minus_one) begin
								currWCount                  <= 0;
								currDevID                   <= currDevID + 1'b1;
								if(currDevID == numDevs_minus_one) begin
									currDevID <= 0;
								end
							end
						end
						else begin 
							currFCount <= currFCount + 1'b1;
							if(currFCount == numcls_local_findexes_minus_one) begin
								currFCount                   <= 0;
								currDevID                    <= currDevID + 1'b1;
								if(currDevID == numDevs_minus_one) begin
									currDevID <= 0;
								end
							end
						end
					end
					else begin 
						currWCount <= 0;
						currFCount <= 0;
						currDevID  <= 0;
					end
					
				end

				currDCount <= 0;
			end
			WAIT_DATA: begin 
				if(broadcast_trees) begin
					if(distributer_empty) begin
						receiver_fsm_state <= RECEIVE_DATA;
					end
				end
				else begin 
					receiver_fsm_state <= RECEIVE_DATA;
				end

				currDCount <= 0;
				currDevID  <= 0;
			end
			RECEIVE_DATA: begin 
				if(process_done) begin
					receiver_fsm_state <= IDLE;
				end

				// If the data is not to be broadcast then we distribute over multiple devices
				if(input_fifo_valid & input_fifo_re) begin
					numcls_received <= numcls_received + 1'b1;

					if(~broadcast_data) begin
						currDCount <= currDCount + 1'b1;
						if(currDCount == core_data_batch_cls_minus_one) begin
							currDCount <= 0;
							currDevID  <= currDevID + 1'b1;
							if(currDevID == numDevs_minus_one) begin
								currDevID <= 0;
							end
						end
					end
					else begin 
						currDCount <= 0;
						currDevID <= 0;
					end
				end
			end
		endcase
	end
end











endmodule