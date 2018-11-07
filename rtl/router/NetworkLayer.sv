
import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;

/*
    The Network layer determines on which connection to send user requests.
    It also determines if an incoming stream destination is on another device 
    or it is on this device, or if it is to the Router Controller.
*/

module NetworkLayer (
	input  wire                                  clk,    // Clock
	input  wire                                  rst_n,  // Asynchronous reset active low

	input  wire  [DEVICE_ID_WIDTH-1:0]           device_id, 
	input  wire                                  network_layer_program_en,

	input  wire  [ROUTING_TABLE_WORD_WIDTH-1:0]  routing_table_word, 
	input  wire  [ROUTING_TABLE_WORD_BITS-1:0]   routing_table_word_addr,
	input  wire                                  routing_table_program_en, 

	input  wire  [15:0]                          NetSize,
	input  wire  [1:0]                           num_connections_minus_one,
	output wire  [19:0] 						 net_tx_lines,

	input  PacketWord                            user_layer_tx, 
	input  wire                                  controller_packet, 
	output wire                                  user_layer_tx_ready,

	output NetworkLayerPacketTX                  layer_tx, 
	input  wire                                  layer_tx_ready, 
	output wire [31:0]                           layer_error_status, 

	output PacketWord                            user_layer_rx, 
	input  wire                                  user_layer_rx_ready,

	output PacketWord                            passing_packet_rx, 
	input  wire                                  passing_packet_rx_ready,

	input  PacketWord                            layer_rx, 
	output wire                                  layer_rx_ready
	
);

reg                         layer_programmed;
wire [15:0]                 layer_tx_error_status;
wire [7:0]                  layer_rx_error_status;


always@(posedge clk) begin
    if(~rst_n) begin
        layer_programmed <= 0;
    end
    else if(network_layer_program_en) begin
        layer_programmed <= 1'b1;
    end
end


assign layer_error_status = {8'b0, layer_rx_error_status, layer_tx_error_status};

// TX Pipeline

NetworkLayerTX  tx_pipe(
	.clk                       (clk),    // Clock
	.rst_n                     (rst_n),  // Asynchronous reset active low

	.routing_table_word        (routing_table_word), 
	.routing_table_word_addr   (routing_table_word_addr),
	.routing_table_program_en  (routing_table_program_en),  

	.NetSize                   (NetSize), 
	.num_connections_minus_one (num_connections_minus_one), 

	.user_layer_tx             (user_layer_tx), 
	.controller_packet         (controller_packet), 
	.user_layer_tx_ready       (user_layer_tx_ready),
	.net_tx_lines              (net_tx_lines),

	.layer_tx                  (layer_tx), 
	.layer_tx_ready            (layer_tx_ready), 
	.layer_tx_error_status     (layer_tx_error_status)
);

// RX Pipeline
NetworkLayerRX rx_pipe(
	.clk                       (clk),    // Clock
	.rst_n                     (rst_n),  // Asynchronous reset active low

	.device_id                 (device_id),
	.layer_programmed          (layer_programmed),
	.NetSize                   (NetSize), 

	.user_layer_rx             (user_layer_rx), 
	.user_layer_rx_ready       (user_layer_rx_ready),

	.layer_rx                  (layer_rx), 
	.layer_rx_ready            (layer_rx_ready),

	.passing_packet_rx         (passing_packet_rx),
	.passing_packet_rx_ready   (passing_packet_rx_ready),

	.layer_rx_error_status     (layer_rx_error_status)
);




endmodule