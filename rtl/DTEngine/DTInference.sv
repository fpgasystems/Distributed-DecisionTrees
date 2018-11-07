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
     The PCIe RX unit receives data/ trees to local core and other cores in the FPGA network
     it has a list of all devices addresses, and number of trees (numcls) per core

     While receiving trees it count lines and determine for which device to send them, or it broadcast 
     them to all devices if configured to do that.

     While receiving data it either broadcast the data to all devices if configured that way. Or, it 
     distribute batches of data to each device one after the other.

     Modes of Operation:

     - Tree ensemble spread over all the FPGAs and a tuple is broadcasted to all FPGAs 
       Partial results are forwarded from an FPGA to another and aggregate results.

       We batch at least 4 results together so we send full 128-bit line 

     - Tree Ensemble fits in one FPGA and we partition tuples between FPGAs. 
       For ordering and scheduling reasons, we batch every 4 consecutive tuples to one FPGA
       so results from one FPGA are in order. 
*/

import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;

import DTEngine_Types::*;

module DTInference (
	input  wire                         clk,    // Clock
	input  wire                         rst_n,  // Asynchronous reset active low

	// Simplified Memory interface
    output MemReq                       mem_reqs        [1:0],
    input                               mem_req_grants  [1:0],
    input  MemResp                      mem_resps       [1:0],
    output                              mem_resp_grants [1:0],

    output reg  [63:0]                  appStatus[5:0],

    // PCIe Slot DMA interface
    input  PCIEPacket                   pcie_packet_in,
    output                              pcie_full_out,

    output PCIEPacket                   pcie_packet_out,
    input                               pcie_grant_in,

    // Soft register interface
    input  SoftRegReq                   softreg_req,
    output SoftRegResp                  softreg_resp,

    // User Layer inputs/outputs
	output UserPacketWord               user_network_tx, 
	input  wire                         user_network_tx_ready,

 	input  UserPacketWord               user_network_rx, 
	output wire                         user_network_rx_ready
	);



////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////            Signals Declarations             /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

wire 									start_core;                           // Triggers the operator
wire                          			pcie_receiver_enabled;                // Implies the engine will receive trees/data over pcie
wire 									host_node;                            // if true, expect trees first
wire 									data_distributed;                      // if true, expect data through PCIe
wire 									broadcast_trees;                      // implies trees are broadcasted to all FPGAs
wire 									broadcast_data;                       // implies data should be broadcasted to all FPGAs
wire  [31:0]                 			total_num_trees_cls;                  // Number of CLs (128-bits) of the complete model
wire  [31:0]                 			total_num_weights_cls;                // Number of CLs of the Model weight nodes
wire  [15:0] 							numcls_local_weights_minus_one;       // Number of CLs of weights to the local node
wire  [15:0] 							numcls_local_findexes_minus_one;      // Number of CLs of findexes to the local node
wire  [NUM_FPGA_DEVICES_BITS-1:0] 		numDevs_minus_one;                    // Number of FPGA devices in the complete system
wire  [DEVICE_ID_WIDTH-1:0]  			devices_list[NUM_FPGA_DEVICES-1:0];   // List of FPGA addresses in the system

wire  [15:0] 							tree_weights_numcls_minus_one;        // Number of CLs for weights of a single tree
wire  [15:0] 							tree_feature_index_numcls_minus_one;  // Number of CLs for findexes of a single tree
wire  [15:0] 							tuple_numcls_minus_one;	              // Number of CLs for a single tuple
wire  [15:0] 							tuple_numcls;	

wire  [NUM_DTPU_CLUSTERS-1:0]       	prog_schedule; 
wire  [NUM_DTPU_CLUSTERS-1:0]       	proc_schedule; 

wire  [31:0]                        	missing_value;                        // Missing Value for missing features
wire  [3 :0]                        	num_levels_per_tree_minus_one;        // Tree Depth
wire  [7 :0]                        	num_trees_per_pu_minus_one;           // Number of Trees assigned to PU
wire  [3 :0]  							num_clusters_per_tuple;               // Number of Clusters store the complete model
wire  [3 :0]                      		num_clusters_per_tuple_minus_one;     

wire  [DEVICE_ID_WIDTH-1:0]  			broadcast_address;                    // Address of Adjacent FPGA to broadcast trees/data to it.
wire  [DEVICE_ID_WIDTH-1:0]  			results_address;                      // Address of adjacent FPGA to send local results to it.
wire  [PACKET_SIZE_BITS-1:0] 			result_packet_numcls_minus_one;       // Result Packet Size
wire  [PACKET_SIZE_BITS-1:0] 			tree_weight_packet_numcls_minus_one;  // Trees Weights packet size
wire  [PACKET_SIZE_BITS-1:0] 			data_packet_numcls_minus_one;         // Data packet size
wire  [PACKET_SIZE_BITS-1:0] 			tree_findex_packet_numcls_minus_one;  // Trees FIndexes packet size
wire  [PCIE_PACKET_SIZE_BITS-1:0] 		pcie_out_packet_numcls_minus_one;

reg   [PCIE_PACKET_SIZE_BITS-1:0] 		pcie_out_cl_count;

wire  [31:0] 							core_data_batch_cls_minus_one;
wire 									aggregEnabled;
wire 									multiple_nodes;    
wire 									process_done;

reg   [31:0]							total_pcie_out_cls_count;
wire  [31:0] 							total_results_numcls;
wire  [3:0] 							result_pcie_slot;



// PCIeReceiver
CoreDataIn                  			pcie_input; 
wire 									pcie_input_valid; 
wire 									pcie_input_ready;

CoreDataIn                  			sl3_tx_pcie; 
wire  [DEVICE_ID_WIDTH-1:0]  			sl3_tx_pcie_address;
wire                         			sl3_tx_pcie_valid; 
wire 									sl3_tx_pcie_ready;

// InputDistriputor
CoreDataIn                  			sl3_input; 
wire 									sl3_input_valid; 
wire 									sl3_input_ready; 

CoreDataIn                  			sl3_tx_distr; 
wire                         			sl3_tx_distr_valid; 
wire 									sl3_tx_distr_ready;

CoreDataIn                  			core_output; 
wire                         			core_output_valid; 
wire 									core_output_ready;
wire 								    last_node;

// Core
CoreDataIn                            	core_data_in;
wire 								   	core_data_in_valid;
wire 								   	core_data_in_ready;

wire   [DATA_PRECISION-1:0] 			tuple_out_data; 
wire 								   	tuple_out_data_valid; 
wire 								   	tuple_out_data_ready;

// ResultsCombiner
wire   [DATA_PRECISION-1:0]  			local_core_result; 
wire 									local_core_result_valid; 
wire 									local_core_result_ready; 

wire   [DATA_BUS_WIDTH-1:0] 	 		sl3_result; 
wire  									sl3_result_valid; 
wire 									sl3_result_ready;

wire   [DATA_BUS_WIDTH-1:0]  			sl3_tx_res; 
wire 									sl3_tx_res_valid; 
wire 									sl3_tx_res_ready; 

wire   [DATA_BUS_WIDTH-1:0]  			pcie_output;
wire 									pcie_output_valid; 
wire 									pcie_output_ready;

//
wire   [1:0]                            pcie_receiver_fsm_state;
wire   [31:0]                           pcie_numcls_received;
// SL3TxMux



reg    [31:0] 							progCycles;
reg    [31:0]              				execCycles;
reg    [31:0]              				tuples_detected;
reg 									state;
reg 									prog_state;

wire   [31:0]						   data_lines;
wire   [31:0]						   prog_lines;
wire   [31:0]						   num_out_tuples;

wire   [31:0] 						   num_sent_lines;
wire   [31:0] 						   num_sent_packets;

wire   [31:0] 						   packets_line;
wire   [1:0] 						   core_state;

wire   [31:0] 						   tuples_passed; 
wire 								   started;

wire   [31:0]                		   pcie_res_lines;
wire   [31:0]                          local_res_lines; 
wire   [31:0]                          sl3_res_lines;
wire   [31:0]                          res_lines_lost;

wire                                   distributer_empty;

wire   [15:0]    					   received_data_with_weigths;
wire   [15:0]    					   received_data_with_findex;

wire   [31:0]						   filled_lines;

wire   [31:0]						   aggreg_tuples_in;
wire   [31:0]						   aggreg_part_res_in;

wire   [31:0] 						   cluster_out_valids;

wire   [31:0] 						   cluster_tuples_received[NUM_DTPU_CLUSTERS-1:0];
wire   [31:0] 						   cluster_lines_received[NUM_DTPU_CLUSTERS-1:0];
wire   [31:0] 						   cluster_tuples_res_out[NUM_DTPU_CLUSTERS-1:0];
wire   [31:0] 						   cluster_tree_res_out[NUM_DTPU_CLUSTERS-1:0];
wire   [31:0] 						   cluster_reduce_tree_outs[NUM_DTPU_CLUSTERS-1:0];
wire   [31:0] 						   cluster_reduce_tree_outs_valids[NUM_DTPU_CLUSTERS-1:0];
////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////            DT Engine Parameters             /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////


EngineCSR EngineCSR(
	.clk                                (clk),
    .rst_n                              (rst_n),

	// Soft register interface
    .softreg_req                        (softreg_req),
    .softreg_resp                       (softreg_resp),

    // parameters
    .start_core                         (start_core),

    .pcie_receiver_enabled              (pcie_receiver_enabled),
	.host_node                          (host_node),               
	.data_distributed                   (data_distributed), 
	.broadcast_trees                    (broadcast_trees),        
	.broadcast_data 					(broadcast_data), 
	.last_node                          (last_node),
	.total_num_trees_cls                (total_num_trees_cls),
	.total_num_weights_cls              (total_num_weights_cls), 
	.numcls_local_weights_minus_one     (numcls_local_weights_minus_one),
	.numcls_local_findexes_minus_one    (numcls_local_findexes_minus_one),
	.numDevs_minus_one                  (numDevs_minus_one),
	.devices_list                       (devices_list),

	.core_data_batch_cls_minus_one      (core_data_batch_cls_minus_one),
	.tree_weights_numcls_minus_one      (tree_weights_numcls_minus_one),
	.tree_feature_index_numcls_minus_one(tree_feature_index_numcls_minus_one),
	.tuple_numcls_minus_one             (tuple_numcls_minus_one),
	.tuple_numcls 						(tuple_numcls),

	.result_pcie_slot                   (result_pcie_slot), 
	.total_results_numcls               (total_results_numcls),

	.prog_schedule                      (prog_schedule), 
	.proc_schedule                      (proc_schedule), 

	.missing_value                      (missing_value), 
	.num_levels_per_tree_minus_one      (num_levels_per_tree_minus_one), 
	.num_trees_per_pu_minus_one         (num_trees_per_pu_minus_one), 
	.num_clusters_per_tuple             (num_clusters_per_tuple),
	.num_clusters_per_tuple_minus_one   (num_clusters_per_tuple_minus_one),

	.results_address                    (results_address), 
	.broadcast_address                  (broadcast_address),
	.result_packet_numcls_minus_one     (result_packet_numcls_minus_one), 
    .tree_weight_packet_numcls_minus_one(tree_weight_packet_numcls_minus_one), 
    .data_packet_numcls_minus_one       (data_packet_numcls_minus_one),
    .tree_findex_packet_numcls_minus_one(tree_findex_packet_numcls_minus_one),
    .pcie_out_packet_numcls_minus_one   (pcie_out_packet_numcls_minus_one), 

	.aggreg_enabled                     (aggregEnabled), 
	.multiple_nodes                     (multiple_nodes), 

	// status registers
	.pcie_receiver_fsm_state            (pcie_receiver_fsm_state), 
	.pcie_numcls_received               (pcie_numcls_received), 

	.progCycles                         (progCycles), 
	.execCycles                         (execCycles), 

	.num_sent_lines                     (num_sent_lines), 
    .num_sent_packets                   (num_sent_packets),
    .packets_lines 						(packets_line)
);


////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////            Performance counters             /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////




always@(posedge clk) begin 
	if(~rst_n) begin 
		progCycles <= 0;
		execCycles <= 0;
		state      <= 0;
		prog_state <= 0;

		appStatus[0] <= 0;
		appStatus[1] <= 0;
		appStatus[2] <= 0;
		appStatus[3] <= 0;

		tuples_detected <= 0;
	end
	else begin 
		// Run state
		if(start_core) begin 
			state <= 1'b1;
		end
		else if(process_done) begin
			state <= 1'b0;
		end
		//
		if(start_core) begin 
			execCycles <= 0;
		end
		else if(state) begin 
			execCycles <= execCycles + 1'b1;
		end

		// Prog state
		if((sl3_input_valid & ~sl3_input.data_valid) | (pcie_input_valid & ~pcie_input.data_valid)) begin
			prog_state <= 1'b1;
		end
		else if((sl3_input_valid & sl3_input.data_valid) | (pcie_input_valid & pcie_input.data_valid)) begin
			prog_state <= 1'b0;
		end
		//
		if(start_core) begin 
			progCycles <= 0;
		end
		else if(prog_state) begin 
			progCycles <= progCycles + 1'b1;
		end

		//
		if(start_core) begin
			tuples_detected <= 0;
		end
		else if(core_data_in_valid & core_data_in.last & core_data_in_ready) begin
			tuples_detected <= tuples_detected + 1'b1;
		end
		//
		appStatus[0] <= {cluster_out_valids, cluster_tuples_res_out[0]};
		appStatus[1] <= {num_out_tuples, cluster_tree_res_out[0]};
		appStatus[2] <= {data_lines, prog_lines};
		appStatus[3] <= {aggreg_tuples_in, cluster_reduce_tree_outs[0]};
		appStatus[4] <= {cluster_reduce_tree_outs_valids[0], sl3_res_lines};
		appStatus[5] <= {cluster_tuples_received[0], cluster_lines_received[0]};
	end
end

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////            Receive From SL3                /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

assign sl3_result       = user_network_rx.data; 
assign sl3_result_valid = user_network_rx.valid & (user_network_rx.metadata == RESULTS_STREAM);


assign sl3_input        = '{data:       user_network_rx.data, 
						    last:       1'b0, 
						    data_valid: (user_network_rx.metadata == DATA_STREAM)?1'b1 : 1'b0, 
						    prog_mode:  (user_network_rx.metadata == TREE_WEIGHT_STREAM)? 1'b1 : 1'b0};

assign sl3_input_valid  = user_network_rx.valid & !(user_network_rx.metadata == RESULTS_STREAM);

assign user_network_rx_ready = (~user_network_rx.valid)? 1'b1 : 
							   ((user_network_rx.metadata == RESULTS_STREAM)?sl3_result_ready : 
							   	sl3_input_ready);

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////            Receive From PCIe                /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

PCIeReceiver PCIeReceiver(
	.clk                                (clk),
    .rst_n                              (rst_n),
    .start_core 						(start_core),

    .process_done                       (process_done), 
	.pcie_receiver_enabled              (pcie_receiver_enabled),
	.host_node                          (host_node),               
	.data_distributed                   (data_distributed), 
	.broadcast_trees                    (broadcast_trees),        
	.broadcast_data 					(broadcast_data), 
	.core_data_batch_cls_minus_one      (core_data_batch_cls_minus_one),
	.total_num_trees_cls                (total_num_trees_cls),
	.total_num_weights_cls              (total_num_weights_cls), 
	.numcls_local_weights_minus_one     (numcls_local_weights_minus_one),
	.numcls_local_findexes_minus_one    (numcls_local_findexes_minus_one),
	.numDevs_minus_one                  (numDevs_minus_one),
	.devices_list                       (devices_list),

	//
	.pcie_receiver_fsm_state            (pcie_receiver_fsm_state), 
	.pcie_numcls_received               (pcie_numcls_received),
	// PCIe Slot DMA interface
    .pcie_packet_in                     (pcie_packet_in),
    .pcie_full_out                      (pcie_full_out),

	.sl3_output                         (sl3_tx_pcie), 
    .sl3_output_address                 (sl3_tx_pcie_address),
	.sl3_output_valid                   (sl3_tx_pcie_valid), 
	.sl3_output_ready                   (sl3_tx_pcie_ready), 

    .pcie_input                         (pcie_input), 
	.pcie_input_valid                   (pcie_input_valid), 
 	.pcie_input_ready                   (pcie_input_ready), 
 	.distributer_empty                  (distributer_empty)
	);

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////            Data\Trees Reader                /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////


InputDistributor InputDistributor(
	.clk                                (clk),
    .rst_n                              (rst_n),
    .start_core 						(start_core),

    .host_node                          (host_node),               
	.data_distributed                   (data_distributed), 
	.broadcast_trees                    (broadcast_trees),        
	.broadcast_data 					(broadcast_data), 
	.last_node                          (last_node), 

	.tree_weights_numcls_minus_one      (tree_weights_numcls_minus_one),
	.tree_feature_index_numcls_minus_one(tree_feature_index_numcls_minus_one),
	.tuple_numcls_minus_one             (tuple_numcls_minus_one),

	.received_data_with_weigths         (received_data_with_weigths), 
	.received_data_with_findex          (received_data_with_findex),

	.pcie_input                         (pcie_input), 
	.pcie_input_valid                   (pcie_input_valid), 
 	.pcie_input_ready                   (pcie_input_ready), 
 	.distributer_empty                  (distributer_empty),

 	.sl3_input                          (sl3_input), 
	.sl3_input_valid                    (sl3_input_valid), 
 	.sl3_input_ready                    (sl3_input_ready), 

	.sl3_output                         (sl3_tx_distr), 
	.sl3_output_valid                   (sl3_tx_distr_valid), 
	.sl3_output_ready                   (sl3_tx_distr_ready), 

	.core_output                        (core_data_in), 
	.core_output_valid                  (core_data_in_valid), 
	.core_output_ready                  (core_data_in_ready)
);


////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////                 Engine Core                 /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////


Core engine_core(
	.clk                                (clk),
    .rst_n                              (rst_n),
    .start_core                         (start_core),

    .core_data_in                       (core_data_in),
    .core_data_in_valid                 (core_data_in_valid),
	.core_data_in_ready                 (core_data_in_ready),

	// parameters
	.prog_schedule                      (prog_schedule), 
	.proc_schedule                      (proc_schedule), 

	.missing_value                      (missing_value), 
	.tree_feature_index_numcls          (tree_feature_index_numcls_minus_one), 
	.tree_weights_numcls                (tree_weights_numcls_minus_one), 
	.tuple_numcls                       (tuple_numcls), 
	.num_levels_per_tree_minus_one      (num_levels_per_tree_minus_one), 
	.num_trees_per_pu_minus_one         (num_trees_per_pu_minus_one), 
	.num_clusters_per_tuple             (num_clusters_per_tuple),
	.num_clusters_per_tuple_minus_one   (num_clusters_per_tuple_minus_one),

	// output 
	.tuple_out_data                     (local_core_result), 
	.tuple_out_data_valid               (local_core_result_valid), 
	.tuple_out_data_ready               (local_core_result_ready), 
    
    .data_lines                         (data_lines), 
    .prog_lines                         (prog_lines),
    .num_out_tuples                     (num_out_tuples),
    .aggreg_tuples_in                   (aggreg_tuples_in),
    .aggreg_part_res_in                 (aggreg_part_res_in),
    .core_state                         (core_state), 
    .started                            (started), 
    .tuples_passed                      (tuples_passed), 
    .cluster_out_valids 				(cluster_out_valids),

    .cluster_tuples_received 			(cluster_tuples_received),
	.cluster_lines_received 			(cluster_lines_received),
	.cluster_tuples_res_out 			(cluster_tuples_res_out),
	.cluster_tree_res_out 				(cluster_tree_res_out), 	
	.cluster_reduce_tree_outs 			(cluster_reduce_tree_outs), 
	.cluster_reduce_tree_outs_valids    (cluster_reduce_tree_outs_valids)
);

////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////          Results Combine Section            /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/*
    Results come from two places: Local core and over SL3 from other cores. 
    Actions:
    1- Put results from local core in 128-bit register (gather 4 consecutive results)
    2- If configured to aggregate with results coming over the network, put in the aggregate FIFO
    3- If not configured to aggregate results, multiple local core and SL3 results. 

*/


ResultsCombiner ResultsCombiner(
	.clk                                (clk),
    .rst_n                              (rst_n),
    .process_done                       (start_core),

	.aggregEnabled                      (aggregEnabled), 
	.multiple_nodes                     (multiple_nodes), 
	.host_node                          (host_node), 

	.local_core_result                  (local_core_result), 
	.local_core_result_valid            (local_core_result_valid), 
	.local_core_result_ready            (local_core_result_ready), 

	.sl3_result                         (sl3_result), 
	.sl3_result_valid                   (sl3_result_valid), 
	.sl3_result_ready                   (sl3_result_ready),

	.sl3_output                         (sl3_tx_res), 
	.sl3_output_valid                   (sl3_tx_res_valid), 
	.sl3_output_ready                   (sl3_tx_res_ready), 

	.pcie_output                        (pcie_output),
	.pcie_output_valid                  (pcie_output_valid), 
	.pcie_output_ready                  (pcie_grant_in),

	.pcie_res_lines 					(pcie_res_lines), 
	.res_lines_lost                     (res_lines_lost),
	.sl3_res_lines                      (sl3_res_lines), 
	.local_res_lines 					(local_res_lines), 
	.filled_lines 					    (filled_lines)
);


////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////             SL3 TX MUX Section              /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////


SL3TxMux SL3TxMux(
	.clk                                (clk),
    .rst_n                              (rst_n),
    .start_core 						(start_core),

    .result_packet_numcls_minus_one     (result_packet_numcls_minus_one), 
    .tree_weight_packet_numcls_minus_one(tree_weight_packet_numcls_minus_one), 
    .data_packet_numcls_minus_one       (data_packet_numcls_minus_one),
    .tree_findex_packet_numcls_minus_one(tree_findex_packet_numcls_minus_one),

    .num_sent_lines                     (num_sent_lines), 
    .num_sent_packets                   (num_sent_packets),
    .packets_line 						(packets_line),

	.sl3_tx_pcie                        (sl3_tx_pcie), 
    .sl3_tx_pcie_address                (sl3_tx_pcie_address),
	.sl3_tx_pcie_valid                  (sl3_tx_pcie_valid), 
	.sl3_tx_pcie_ready                  (sl3_tx_pcie_ready),

	.sl3_tx_res                         (sl3_tx_res), 
	.sl3_tx_res_valid                   (sl3_tx_res_valid), 
	.sl3_tx_res_ready                   (sl3_tx_res_ready), 
	.results_address                    (results_address), 

	.broadcast_address                  (broadcast_address), 
	.sl3_tx_distr                       (sl3_tx_distr), 
	.sl3_tx_distr_valid                 (sl3_tx_distr_valid), 
	.sl3_tx_distr_ready                 (sl3_tx_distr_ready), 

	.user_network_tx                    (user_network_tx), 
	.user_network_tx_ready              (user_network_tx_ready)
);



////////////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////                            //////////////////////////////////
//////////////////////////////               PCIe Transmitter              /////////////////////////
//////////////////////////////////////                            //////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////


always@(posedge clk) begin 
	if(~rst_n | process_done) begin
		pcie_out_cl_count        <= 0;
		total_pcie_out_cls_count <= 0;
	end
	else if(pcie_grant_in & pcie_output_valid) begin 

		total_pcie_out_cls_count <= total_pcie_out_cls_count + 1'b1;

		pcie_out_cl_count <= pcie_out_cl_count + 1'b1;
		if(pcie_out_cl_count == pcie_out_packet_numcls_minus_one) begin
			pcie_out_cl_count <= 0;
		end
	end
end

always@(posedge clk) begin 
	if(~rst_n | process_done) begin
		process_done    <=  0;
	end
	else begin
		process_done    <= total_pcie_out_cls_count == total_results_numcls;
	end
end
 

assign pcie_packet_out = '{data:  pcie_output, 
						   slot:  {12'b0, result_pcie_slot}, 
						   pad:   0, 
						   valid: pcie_output_valid, 
						   last:  (pcie_out_cl_count == pcie_out_packet_numcls_minus_one)};



endmodule

