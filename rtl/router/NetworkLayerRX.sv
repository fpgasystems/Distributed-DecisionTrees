
import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;


module NetworkLayerRX(
	input  wire                             clk,    // Clock
	input  wire                             rst_n,  // Asynchronous reset active low

	input  wire  [DEVICE_ID_WIDTH-1:0]      device_id, 
	input  wire                             layer_programmed,
	input  wire  [15:0]                     NetSize,

	output PacketWord                       user_layer_rx, 
	input  wire                             user_layer_rx_ready,

	input  PacketWord                       layer_rx, 
	output wire                             layer_rx_ready,

	output PacketWord                       passing_packet_rx, 
	input  wire                             passing_packet_rx_ready, 
	output wire [7:0]                       layer_rx_error_status
);


reg  [DEVICE_ID_WIDTH-1:0]        device_id_reg;
wire                              isTargetDevice;

PacketWord                        layer_rx_w;

reg  [7:0] 						  wrong_dest_addr_count;
//-----------------------------------------------------------------//
//------------------------ Layer Status ---------------------------//
//-----------------------------------------------------------------//

always@(posedge clk) begin
	if(~rst_n) begin 
		wrong_dest_addr_count <= 8'd0;
	end
	else begin 
		if(layer_rx.valid & (!(layer_rx.header.dest_addr[DEVICE_ID_WIDTH+USER_ID_WIDTH-1:USER_ID_WIDTH] < NetSize))) begin
			wrong_dest_addr_count <= wrong_dest_addr_count + 8'd1;
		end
	end
end 

assign layer_rx_error_status = wrong_dest_addr_count;
//-----------------------------------------------------------------//
//---------------------- RX Configuration -------------------------//
//-----------------------------------------------------------------//
always@(posedge clk) begin
	if(~rst_n) begin 
		device_id_reg <= 0;
	end
	else begin
		device_id_reg <= device_id;
	end
end

//-----------------------------------------------------------------//
//------------------------- RX Pipeline ---------------------------//
//-----------------------------------------------------------------//

assign isTargetDevice = ~layer_programmed | (device_id_reg == layer_rx.header.dest_addr[DEVICE_ID_WIDTH+USER_ID_WIDTH-(4'd1):USER_ID_WIDTH]);

assign passing_packet_rx.data      = layer_rx.data;
assign passing_packet_rx.last      = layer_rx.last;
assign passing_packet_rx.first     = layer_rx.first;
assign passing_packet_rx.valid     = layer_rx.valid & ~isTargetDevice;
assign passing_packet_rx.header    = layer_rx.header;

assign user_layer_rx.data          = layer_rx.data;
assign user_layer_rx.last          = layer_rx.last;
assign user_layer_rx.first         = layer_rx.first;
assign user_layer_rx.valid         = layer_rx.valid & isTargetDevice;
assign user_layer_rx.header        = layer_rx.header;

assign layer_rx_ready = (isTargetDevice)? user_layer_rx_ready : passing_packet_rx_ready;


endmodule