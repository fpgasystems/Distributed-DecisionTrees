

import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;

/*
   User Layer exposes a streaming TX and RX channels for the User Modules

   Constraints:
    - Supports one user module 
    - User module uses the physical address of the target module. 
*/


module UserLayer 
       #(parameter NUM_USERS = 1) 
(
	input  wire                             clk,    // Clock
	input  wire                             rst_n,  // Asynchronous reset active low

	input  PacketWord                       users_tx[NUM_USERS-1:0], 
	output wire                             users_tx_ready[NUM_USERS-1:0],
	output wire  [31:0]                     user_packet_error_status[NUM_USERS-1:0],
	output wire  [31:0]                     packet_error_detected[NUM_USERS-1:0],
	output wire  [7:0] 					    wrong_target_user_count, 
	output wire  [19:0] 					user_tx_lines,

	output PacketWord                       layer_tx, 
	output wire                             controller_packet,
	input  wire                             layer_tx_ready, 

	output UserPacketWord                   users_rx[NUM_USERS-2:0],                // one less user 
	input  wire                             users_rx_ready[NUM_USERS-2:0],

	input  PacketWord                       layer_rx, 
	output wire                             layer_rx_ready 
);



// TX Pipeline

UserLayerTX #(
	 		.NUM_USERS(NUM_USERS)
		   	) 
	tx_pipe(
	.clk                       (clk),    // Clock
	.rst_n                     (rst_n),  // Asynchronous reset active low

	.users_tx                  (users_tx), 
	.users_tx_ready            (users_tx_ready),
	.user_packet_error_status  (user_packet_error_status),
	.packet_error_detected     (packet_error_detected),
	.user_tx_lines             (user_tx_lines),

	.layer_tx                  (layer_tx), 
	.controller_packet         (controller_packet),
	.layer_tx_ready            (layer_tx_ready) 
);

// RX Pipeline
UserLayerRX #(
	 		.NUM_USERS(NUM_USERS-1)
		   	) 
	rx_pipe(
	.clk                       (clk),    // Clock
	.rst_n                     (rst_n),  // Asynchronous reset active low

	.users_rx                  (users_rx), 
	.users_rx_ready            (users_rx_ready),

	.layer_rx                  (layer_rx), 
	.layer_rx_ready            (layer_rx_ready), 
	.wrong_target_user_count   (wrong_target_user_count)
);




endmodule