
import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;



module UserLayerRX #(parameter NUM_USERS = 1) 
	(
	input  wire                             clk,    // Clock
	input  wire                             rst_n,  // Asynchronous reset active low

	output UserPacketWord                   users_rx[NUM_USERS-1:0], 
	input  wire                             users_rx_ready[NUM_USERS-1:0],

	input  PacketWord                       layer_rx, 
	output wire                             layer_rx_ready, 
	output reg     [7:0] 					wrong_target_user_count 
	
);




//-----------------------------------------------------------------//
//------------------------- RX Pipeline ---------------------------//
//-----------------------------------------------------------------//
wire    [NUM_USERS-1:0]              users_ready;
wire 								 wrong_target_user;



genvar i;
generate for (i = 1; i < NUM_USERS; i=i+1) begin: assignUsers
	assign users_rx[i].data     = layer_rx.data;
	assign users_rx[i].last     = layer_rx.last;
	assign users_rx[i].valid    = layer_rx.valid & (i-1 == layer_rx.header.dest_addr[USER_ID_WIDTH-1:0]);
	assign users_rx[i].address  = layer_rx.header.src_addr; 
	assign users_rx[i].metadata = layer_rx.header.metadata;

	assign users_ready[i]       = users_rx_ready[i] & (i-1 == layer_rx.header.dest_addr[USER_ID_WIDTH-1:0]);
end
endgenerate

assign users_ready[0]       = users_rx_ready[0] & (layer_rx.header.dest_addr[USER_ID_WIDTH-1:0] == CONTROLLER_ID);

assign users_rx[0].data     = layer_rx.data;
assign users_rx[0].last     = layer_rx.last;
assign users_rx[0].valid    = layer_rx.valid & (layer_rx.header.dest_addr[USER_ID_WIDTH-1:0] == CONTROLLER_ID);
assign users_rx[0].address  = layer_rx.header.src_addr; 
assign users_rx[0].metadata = layer_rx.header.metadata; 


assign layer_rx_ready     = |users_ready;

/////////////////////////////////////////////////////
assign wrong_target_user = (layer_rx.header.dest_addr[USER_ID_WIDTH-1:0] != CONTROLLER_ID) & 
                           (layer_rx.header.dest_addr[USER_ID_WIDTH-1:0] > (NUM_USERS-1));

always@(posedge clk) begin
    if(~rst_n) begin
        wrong_target_user_count <= 0;
    end 
    else begin
        if(layer_rx.valid & wrong_target_user) begin
            wrong_target_user_count <= wrong_target_user_count + 8'd1;
        end
    end
end

endmodule