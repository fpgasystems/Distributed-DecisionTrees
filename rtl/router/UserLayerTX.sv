

import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;

/*

   User TX interface:
   - data
   - address
   - last
   - valid

   The TX interface allows one packet at a time for the user module. 
   The first cycle the valid signal is '1', indicates the start of the packet. 
   If the last signal is '1' this means this is the last part of the packet.
   The address should stay fixed until the end of a packet. 
   Every data between the first valid and the last is considered from the same packet.

*/


module UserLayerTX #(parameter NUM_USERS = 1) 
	(
	input  wire                             clk,    // Clock
	input  wire                             rst_n,  // Asynchronous reset active low

	input  PacketWord                       users_tx[NUM_USERS-1:0], 
	output wire                             users_tx_ready[NUM_USERS-1:0],
	output wire  [31:0]                     user_packet_error_status[NUM_USERS-1:0],
	output wire  [31:0]                     packet_error_detected[NUM_USERS-1:0],
	output reg   [19:0] 					user_tx_lines,

	output PacketWord                       layer_tx, 
	output wire                             controller_packet,
	input  wire                             layer_tx_ready 
	
);

reg  [1:0]							selected_user;
reg   								packet_lock_set;
PacketWord                          curr_user_packet;
PacketWord                          curr_user_packet_d1;

wire 								user_in_valid;
wire								user_in_last;

wire 								tx_fifo_almfull;
wire 								tx_fifo_valid;
wire  [$bits(PacketWord)-1:0]       tx_fifo_dout;

PacketWord                          users_packet[NUM_USERS-1:0];
wire                                users_packet_ready[NUM_USERS-1:0];

wire                                isControllerPacket;
reg                                 isControllerPacket_d1;

//-----------------------------------------------------------------//
//------------------------- TX Pipeline ---------------------------//
//-----------------------------------------------------------------//

always@(posedge clk) begin
	if(~rst_n) begin
		selected_user         <= 0;
		packet_lock_set       <= 1'b0;
		curr_user_packet_d1   <= '{header:'{metadata:0, dest_addr:0, src_addr:0}, valid:1'b0, first:1'b0, last:1'b0, data:128'b0};
		isControllerPacket_d1 <= 0;
		user_tx_lines <= 0;
	end 
	else begin
		// selected_user: we increment the selected user counter if it has no valid data or no packet loc is set for the current user
		if( (~user_in_valid & ~packet_lock_set) | (user_in_valid & user_in_last)) begin 
			if(selected_user == NUM_USERS-1) begin
				selected_user <= 0;
			end
			else begin 
				selected_user <= selected_user + 1'b1;
			end
		end

		// packet_lock_set: 
		if(user_in_valid) begin
			packet_lock_set <= 1'b1;
			if(user_in_last) begin
				packet_lock_set <= 1'b0;
			end
		end
		//
		curr_user_packet_d1.data   <= curr_user_packet.data;
		curr_user_packet_d1.header <= curr_user_packet.header;
		curr_user_packet_d1.last   <= curr_user_packet.last;
		curr_user_packet_d1.first  <= curr_user_packet.first;
		curr_user_packet_d1.valid  <= curr_user_packet.valid & ~tx_fifo_almfull;

		isControllerPacket_d1      <= isControllerPacket;

		if(curr_user_packet_d1.valid) begin
			user_tx_lines <= user_tx_lines + 1'b1;
		end
		
	end
end

assign curr_user_packet   = users_packet[selected_user];
assign isControllerPacket = selected_user == 2'b00;

assign user_in_last  = curr_user_packet.last; 
assign user_in_valid = curr_user_packet.valid & ~tx_fifo_almfull;

quick_fifo  #(.FIFO_WIDTH( $bits(PacketWord) ),        
            .FIFO_DEPTH_BITS(9),
            .FIFO_ALMOSTFULL_THRESHOLD(2**9 -8)
            ) tx_fifo(
        .clk                (clk),
        .reset_n            (rst_n),
        .din                ({isControllerPacket_d1, curr_user_packet_d1.first, curr_user_packet_d1.last, curr_user_packet_d1.header.src_addr, curr_user_packet_d1.header.dest_addr, curr_user_packet_d1.header.metadata, curr_user_packet_d1.data}),
        .we                 (curr_user_packet_d1.valid),
        .re                 (layer_tx_ready),
        .dout               (tx_fifo_dout),
        .empty              (),
        .valid              (tx_fifo_valid),
        .full               (),
        .count              (),
        .almostfull         (tx_fifo_almfull)
    );


assign layer_tx.data      = tx_fifo_dout[USER_DATA_BUS_WIDTH-1:0];
assign layer_tx.last      = tx_fifo_dout[3*NET_ADDRESS_WIDTH+USER_DATA_BUS_WIDTH]; 
assign layer_tx.valid     = tx_fifo_valid & layer_tx_ready;
assign layer_tx.first     = tx_fifo_dout[3*NET_ADDRESS_WIDTH+USER_DATA_BUS_WIDTH+1];
assign controller_packet  = tx_fifo_dout[3*NET_ADDRESS_WIDTH+USER_DATA_BUS_WIDTH+2];
assign layer_tx.header    = '{src_addr: tx_fifo_dout[3*NET_ADDRESS_WIDTH+USER_DATA_BUS_WIDTH-1:2*NET_ADDRESS_WIDTH+USER_DATA_BUS_WIDTH], dest_addr:tx_fifo_dout[2*NET_ADDRESS_WIDTH+USER_DATA_BUS_WIDTH-1:NET_ADDRESS_WIDTH+USER_DATA_BUS_WIDTH], metadata:tx_fifo_dout[NET_ADDRESS_WIDTH+USER_DATA_BUS_WIDTH-1:USER_DATA_BUS_WIDTH]};
//-----------------------------------------------------------------//
//--------------------- User Packet FIFOs -------------------------//
//-----------------------------------------------------------------//
genvar i;
generate for (i = 0; i < NUM_USERS; i=i+1) begin: usersPacketFIFOs
	PacketFIFO pfifo_x(
	.clk                       (clk),    
	.rst_n                     (rst_n), 

	.pfifo_in                  (users_tx[i]),
	.pfifo_in_ready            (users_tx_ready[i]), 

	.pfifo_out                 (users_packet[i]),
	.pfifo_out_ready           (users_packet_ready[i]), 

	.pfifo_error_status        (user_packet_error_status[i]), 
	.packet_error_detected     (packet_error_detected[i])
);

	assign users_packet_ready[i] = ~tx_fifo_almfull & (selected_user == i);
end
endgenerate


endmodule