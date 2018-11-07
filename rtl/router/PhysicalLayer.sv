

import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;

/*
*/


module PhysicalLayer (
	input  wire                                  clk,    // Clock
	input  wire                                  rst_n,  // Asynchronous reset active low

	input  wire  [CONN_ID_WIDTH-1:0]             lanes_connection_id[NUM_SL3_LANES-1:0], 
	input  wire  [LANE_ID_WIDTH-1:0]             lanes_order_id[NUM_SL3_LANES-1:0],
	input  wire  [LANE_ID_LIST_WIDTH-1:0]        physical_lane_list[NUM_SL3_LANES-1:0], 
	input  wire  [LANE_ID_WIDTH-1:0]             physical_lane_list_count[NUM_SL3_LANES-1:0],
	input  wire  [CONN_ID_WIDTH-1:0]             num_connections_minus_one,
	input  wire                                  physical_layer_program_en,
	input  wire 								 router_ready,
	input  wire                                  connections_ready,  
	input  wire  [DEVICE_ID_WIDTH-1:0] 			 NetSize,

	input  NetworkLayerPacketTX                  network_layer_tx, 
	output wire                                  network_layer_tx_ready, 

	output PacketWord                            network_layer_rx, 
	input  wire                                  network_layer_rx_ready, 

	// SerialLite III interface
    output SL3DataInterface                      sl_tx_out           [NUM_SL3_LANES-1:0],
    input                                        sl_tx_full_in       [NUM_SL3_LANES-1:0],
    output SL3OOBInterface                       sl_tx_oob_out       [NUM_SL3_LANES-1:0],
    input                                        sl_tx_oob_full_in   [NUM_SL3_LANES-1:0],

    input  SL3DataInterface                      sl_rx_in            [NUM_SL3_LANES-1:0],
    output                                       sl_rx_grant_out     [NUM_SL3_LANES-1:0],
    input  SL3OOBInterface                       sl_rx_oob_in        [NUM_SL3_LANES-1:0],
    output                                       sl_rx_oob_grant_out [NUM_SL3_LANES-1:0], 

    output wire  [11:0]                           tx_lane_credits [NUM_SL3_LANES-1:0],
    output wire  [47:0]                           lane_sentLines[NUM_SL3_LANES-1:0], 
    output wire  [14:0]                           rx_lane_credits [NUM_SL3_LANES-1:0],
    output wire  [48:0]                           lane_rcvLines[NUM_SL3_LANES-1:0],
    output wire  [31:0]                           phy_rx_error_status, 
    output wire  [39:0]							  phy_rx_error_packets_info
	
);



// TX Pipeline

PhysicalLayerTX tx_pipe(
	.clk                       (clk),    // Clock
	.rst_n                     (rst_n),  // Asynchronous reset active low

	.physical_lane_list        (physical_lane_list), 
	.physical_lane_list_count  (physical_lane_list_count),
	.physical_layer_program_en (physical_layer_program_en),
	.connections_ready         (connections_ready),

	.network_layer_tx          (network_layer_tx), 
	.network_layer_tx_ready    (network_layer_tx_ready),

	.sl_tx_out                 (sl_tx_out),
    .sl_tx_full_in             (sl_tx_full_in),
    .sl_rx_oob_in              (sl_rx_oob_in),
    .sl_rx_oob_grant_out       (sl_rx_oob_grant_out), 

    .tx_lane_credits           (tx_lane_credits), 
	.lane_sentLines            (lane_sentLines) 
);

// RX Pipeline
PhysicalLayerRX rx_pipe(
	.clk                       (clk),    // Clock
	.rst_n                     (rst_n),  // Asynchronous reset active low

	.lanes_connection_id       (lanes_connection_id), 
	.lanes_order_id            (lanes_order_id),
	.physical_lane_list_count  (physical_lane_list_count),
	.num_connections_minus_one (num_connections_minus_one),
	.physical_layer_program_en (physical_layer_program_en),
	.NetSize				   (NetSize),
	.router_ready              (router_ready), 

	.network_layer_rx          (network_layer_rx), 
	.network_layer_rx_ready    (network_layer_rx_ready),

	.sl_rx_in                  (sl_rx_in),
    .sl_rx_grant_out           (sl_rx_grant_out),
    .sl_tx_oob_out             (sl_tx_oob_out),
    .sl_tx_oob_full_in         (sl_tx_oob_full_in), 

    .rx_lane_credits           (rx_lane_credits), 
	.lane_rcvLines             (lane_rcvLines), 
	.phy_rx_error_status       (phy_rx_error_status),
	.phy_rx_error_packets_info (phy_rx_error_packets_info)
);




endmodule