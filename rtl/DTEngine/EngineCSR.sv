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

import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;

import DTEngine_Types::*;

module EngineCSR (
	input  wire                         		clk,    // Clock
	input  wire                         		rst_n,  // Asynchronous reset active low

	// Soft register interface
    input  SoftRegReq                   		softreg_req,
    output SoftRegResp                  		softreg_resp,

    // parameters
    output reg 									start_core,                           // Triggers the operator
    output reg                          		pcie_receiver_enabled,                // Implies the engine will receive trees/data over pcie
	output reg 									host_node,                            // if true, expect trees first
	output reg 									data_distributed,                      // if true, expect data through PCIe
	output reg 									broadcast_trees,                      // implies trees are broadcasted to all FPGAs
	output reg 									broadcast_data,                       // implies data should be broadcasted to all FPGAs
	output reg                                  last_node, 
    output reg  [31:0]                 			total_num_trees_cls,                  // Number of CLs (128-bits) of the complete model
	output reg  [31:0]                 			total_num_weights_cls,                // Number of CLs of the Model weight nodes
	output reg  [15:0] 							numcls_local_weights_minus_one,       // Number of CLs of weights to the local node
	output reg  [15:0] 							numcls_local_findexes_minus_one,      // Number of CLs of findexes to the local node
	output reg  [NUM_FPGA_DEVICES_BITS-1:0] 	numDevs_minus_one,                    // Number of FPGA devices in the complete system
	output reg  [DEVICE_ADDRESS_WIDTH-1:0]      devices_list[NUM_FPGA_DEVICES-1:0],   // List of FPGA addresses in the system

    output reg  [31:0]                          core_data_batch_cls_minus_one,
	output reg  [15:0] 							tree_weights_numcls_minus_one,        // Number of CLs for weights of a single tree
	output reg  [15:0] 							tree_feature_index_numcls_minus_one,  // Number of CLs for findexes of a single tree
	output reg  [15:0] 							tuple_numcls_minus_one,	              // Number of CLs for a single tuple
    output reg  [15:0]                          tuple_numcls,

	output reg  [NUM_DTPU_CLUSTERS-1:0]       	prog_schedule, 
	output reg  [NUM_DTPU_CLUSTERS-1:0]       	proc_schedule, 

    output reg  [31:0]                          total_results_numcls,
    output reg  [3:0]                           result_pcie_slot,

	output reg  [31:0]                        	missing_value,                        // Missing Value for missing features
	output reg  [3 :0]                        	num_levels_per_tree_minus_one,        // Tree Depth
	output reg  [7 :0]                        	num_trees_per_pu_minus_one,           // Number of Trees assigned to PU
	output reg  [3 :0]  						num_clusters_per_tuple,               // Number of Clusters store the complete model
	output reg  [3 :0]                      	num_clusters_per_tuple_minus_one,     

	output reg  [DEVICE_ID_WIDTH-1:0]  			broadcast_address,                    // Address of Adjacent FPGA to broadcast trees/data to it.
	output reg  [DEVICE_ID_WIDTH-1:0]  			results_address,                      // Address of adjacent FPGA to send local results to it.
	output reg  [PACKET_SIZE_BITS-1:0] 			result_packet_numcls_minus_one,       // Result Packet Size
	output reg  [PACKET_SIZE_BITS-1:0] 			tree_weight_packet_numcls_minus_one,  // Trees Weights packet size
	output reg  [PACKET_SIZE_BITS-1:0] 			data_packet_numcls_minus_one,         // Data packet size
	output reg  [PACKET_SIZE_BITS-1:0] 			tree_findex_packet_numcls_minus_one,  // Trees FIndexes packet size
	output reg  [PCIE_PACKET_SIZE_BITS-1:0] 	pcie_out_packet_numcls_minus_one,

	output reg                                 	aggreg_enabled,                       // Aggregate Results flag
	output reg 									multiple_nodes, 

    //
    input  wire [1:0]                           pcie_receiver_fsm_state,
    input  wire [31:0]                          pcie_numcls_received, 

    input  wire [31:0]                          progCycles, 
    input  wire [31:0]                          execCycles, 

    // SL3TX
    input  wire [31:0]                          num_sent_lines, 
    input  wire [31:0]                          num_sent_packets, 
    input  wire [31:0]                          packets_lines
/*
    // ResCombiner
    input  wire [31:0]                          filled_lines, 
    input  wire [31:0]                          local_res_lines, 
    input  wire [31:0]                          sl3_res_lines, 
    input  wire [31:0]                          res_lines_lost,
    input  wire [31:0]                          pcie_res_lines,

    // InputDistributer 
    input  wire [31:0]                          received_data_with_weights,
    input  wire [31:0]                          receviced_data_with_findex*/
);


reg                     start_core_d1;
reg                     start_core_d2;
reg                     start_core_d3;
reg                     start_core_d4;

integer i;
always@(posedge clk) begin 
    if(~rst_n) begin
        softreg_resp <= '{valid:1'b0, data: 64'b0};
    end
    else begin 
        softreg_resp <= '{valid:1'b0, data: 64'b0};
        if(softreg_req.valid && !softreg_req.isWrite) begin
            softreg_resp.valid <= 1'b1;
            case(softreg_req.addr)
                220: softreg_resp.data <= {62'b0, pcie_receiver_fsm_state};
                221: softreg_resp.data <= {32'b0, pcie_numcls_received};
                222: softreg_resp.data <= {32'b0, progCycles};
                223: softreg_resp.data <= {32'b0, execCycles};
                224: softreg_resp.data <= {32'b0, num_sent_lines};
                225: softreg_resp.data <= {32'b0, num_sent_packets};
                226: softreg_resp.data <= {32'b0, packets_lines};
                default: softreg_resp.data <= 64'hFFFFFFFFFFFFFFFF;
            endcase
        end
    end 
end

// Read SoftRegs
always@(posedge clk) begin 
    if(~rst_n) begin
        start_core_d2 <= 0;
        start_core_d3 <= 0;
        start_core_d4 <= 0;
        start_core    <= 0;
    end
    else begin 
        start_core_d2 <= start_core_d1;
        start_core_d3 <= start_core_d2;
        start_core_d4 <= start_core_d3;
        start_core    <= start_core_d4;
    end 
end

// Write SoftRegs
always@(posedge clk) begin 
	if(~rst_n) begin
		start_core_d1                        <= 0;
		data_distributed                     <= 0;
		host_node                            <= 0;
		broadcast_data                       <= 0;
		broadcast_trees                      <= 0;
        last_node                            <= 0;
		aggreg_enabled                       <= 0;
		multiple_nodes                       <= 0;
		pcie_receiver_enabled                <= 0;
		total_num_trees_cls                  <= 0;
        total_num_weights_cls                <= 0;
        numcls_local_weights_minus_one       <= 0;
        numcls_local_findexes_minus_one      <= 0;
        numDevs_minus_one                    <= 0;
        prog_schedule                        <= 0;
        proc_schedule                        <= 0;
        tree_weights_numcls_minus_one        <= 0;
        tree_feature_index_numcls_minus_one  <= 0;
        tuple_numcls_minus_one               <= 0;
        missing_value                        <= 0;
        num_levels_per_tree_minus_one        <= 0;
        num_trees_per_pu_minus_one           <= 0;
        num_clusters_per_tuple               <= 0;
        num_clusters_per_tuple_minus_one     <= 0;
        broadcast_address                    <= 0;
        results_address                      <= 0;
        tree_weight_packet_numcls_minus_one  <= 0;
        data_packet_numcls_minus_one         <= 0;
        tree_findex_packet_numcls_minus_one  <= 0;
        result_packet_numcls_minus_one       <= 0;
        pcie_out_packet_numcls_minus_one     <= 0;

        tuple_numcls <= 0;
        
        for (i = 0; i < NUM_FPGA_DEVICES; i=i+1) begin
            devices_list[i] <= 0;
        end
	end
	else begin 
		start_core_d1 <= 0;

		if(softreg_req.valid && softreg_req.isWrite) begin
			case(softreg_req.addr)
				200: begin    // start flag
					start_core_d1 <= softreg_req.data[0];
				end
				201: begin 
					data_distributed      <= softreg_req.data[0];
					host_node             <= softreg_req.data[1];
					broadcast_data        <= softreg_req.data[2];
					broadcast_trees       <= softreg_req.data[3];
					aggreg_enabled        <= softreg_req.data[4];
					multiple_nodes        <= softreg_req.data[5];
					pcie_receiver_enabled <= softreg_req.data[6];
                    last_node             <= softreg_req.data[7];

                    core_data_batch_cls_minus_one <= softreg_req.data[63:32] - 1'b1;
				end
            	
            	202: begin 
            		total_num_trees_cls   <= softreg_req.data[31:0];
            		total_num_weights_cls <= softreg_req.data[63:32];
            	end

            	203: begin 
            		numcls_local_weights_minus_one      <= softreg_req.data[15:0];           // subtract in SW
            		numcls_local_findexes_minus_one     <= softreg_req.data[31:16] - 1'b1;
            		numDevs_minus_one                   <= softreg_req.data[39:32] - 1'b1;
            	end

            	204: begin 
            		prog_schedule                        <= softreg_req.data[NUM_DTPU_CLUSTERS-1:0];
            		proc_schedule                        <= softreg_req.data[8+NUM_DTPU_CLUSTERS-1:8];
            		tree_weights_numcls_minus_one        <= softreg_req.data[31:16] - 1'b1;                     
            		tree_feature_index_numcls_minus_one  <= softreg_req.data[47:32] - 1'b1;
            		tuple_numcls_minus_one               <= softreg_req.data[63:48] - 1'b1;
                    tuple_numcls                         <= softreg_req.data[63:48];
            	end

            	205: begin 
            		missing_value                        <= softreg_req.data[31:0];
            		num_levels_per_tree_minus_one        <= softreg_req.data[35:32] - 1'b1;
            		num_trees_per_pu_minus_one           <= softreg_req.data[43:36] - 1'b1;
            		num_clusters_per_tuple               <= softreg_req.data[47:44];
            		num_clusters_per_tuple_minus_one     <= softreg_req.data[47:44] - 1'b1;
            	end

            	206: begin 
            		broadcast_address                    <= softreg_req.data[7:0];
            		results_address                      <= softreg_req.data[15:8];
            		tree_weight_packet_numcls_minus_one  <= softreg_req.data[23:16] - 1'b1;
            		data_packet_numcls_minus_one         <= softreg_req.data[31:24] - 1'b1;
            		tree_findex_packet_numcls_minus_one  <= softreg_req.data[39:32] - 1'b1;
            		result_packet_numcls_minus_one       <= softreg_req.data[47:40] - 1'b1;
            		pcie_out_packet_numcls_minus_one     <= softreg_req.data[55:48] - 1'b1;
            	end

                207: begin 
                    total_results_numcls <= softreg_req.data[31:0];
                    result_pcie_slot     <= softreg_req.data[35:32];
                end

            	208: begin 
                   /* devices_list[0] <= {{(DEVICE_ID_WIDTH-8){1'b0}}, softreg_req.data[7:0]};
                    devices_list[1] <= {{(DEVICE_ID_WIDTH-8){1'b0}}, softreg_req.data[15:8]};
                    devices_list[2] <= {{(DEVICE_ID_WIDTH-8){1'b0}}, softreg_req.data[23:16]};
                    devices_list[3] <= {{(DEVICE_ID_WIDTH-8){1'b0}}, softreg_req.data[31:24]};*/
						devices_list[0] <= softreg_req.data[4:0];
                  devices_list[1] <= softreg_req.data[12:8];
                  devices_list[2] <= softreg_req.data[20:16];
                  devices_list[3] <= softreg_req.data[28:24];
						devices_list[4] <= softreg_req.data[36:32];
						devices_list[5] <= softreg_req.data[44:40];
						devices_list[6] <= softreg_req.data[52:48];
						devices_list[7] <= softreg_req.data[60:56];
						/*for (i = 0; i < 8; i=i+1) begin
            			if(i < NUM_FPGA_DEVICES) begin
            				devices_list[i] <= softreg_req.data[i*8+4:i*8];
            			end
            		end*/
            	end

            	209: begin 
						devices_list[8]  <= softreg_req.data[4:0];
                  devices_list[9]  <= softreg_req.data[12:8];
                  devices_list[10] <= softreg_req.data[20:16];
                  devices_list[11] <= softreg_req.data[28:24];
						devices_list[12] <= softreg_req.data[36:32];
						devices_list[13] <= softreg_req.data[44:40];
						devices_list[14] <= softreg_req.data[52:48];
						devices_list[15] <= softreg_req.data[60:56];
            		/*for (i = 0; i < 8; i=i+1) begin
            			if((i+8) < NUM_FPGA_DEVICES) begin
            				devices_list[i+8] <= softreg_req.data[i*8+4:i*8];
            			end
            		end*/
            	end

            	210: begin 
                    devices_list[16] <= softreg_req.data[4:0];
                    devices_list[17] <= softreg_req.data[12:8];
                    devices_list[18] <= softreg_req.data[20:16];
                    devices_list[19] <= softreg_req.data[28:24];
            		/*for (i = 0; i < 8; i=i+1) begin
            			if((i+16) < NUM_FPGA_DEVICES) begin
            				devices_list[i+16] <= softreg_req.data[i*8+7:i*8];
            			end
            		end*/
            	end

            	211: begin 
            		/*for (i = 0; i < 8; i=i+1) begin
            			if((i+24) < NUM_FPGA_DEVICES) begin
            				devices_list[i+24] <= softreg_req.data[i*8+7:i*8];
            			end
            		end*/
            	end
        	endcase
		end
	end 
end







endmodule