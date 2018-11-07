


import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;



module PhysicalLayerTX 
	(
	input  wire                                   clk,    // Clock
	input  wire                                   rst_n,  // Asynchronous reset active low

	input  wire  [LANE_ID_LIST_WIDTH-1:0]         physical_lane_list[NUM_SL3_LANES-1:0], 
	input  wire  [LANE_ID_WIDTH-1:0]              physical_lane_list_count[NUM_SL3_LANES-1:0],
	input  wire                                   physical_layer_program_en,
	input  wire                                   connections_ready, 

	input  NetworkLayerPacketTX                   network_layer_tx, 
	output wire                                   network_layer_tx_ready, 

	output SL3DataInterface                       sl_tx_out           [NUM_SL3_LANES-1:0],
    input                                         sl_tx_full_in       [NUM_SL3_LANES-1:0],
    input  SL3OOBInterface                        sl_rx_oob_in        [NUM_SL3_LANES-1:0],
    output                                        sl_rx_oob_grant_out [NUM_SL3_LANES-1:0], 

    output wire  [11:0]                           tx_lane_credits [NUM_SL3_LANES-1:0],
    output wire  [47:0]                           lane_sentLines[NUM_SL3_LANES-1:0]
);


reg  [LANE_ID_WIDTH-1:0]                    lane_lists[NUM_SL3_LANES-1:0][NUM_SL3_LANES-1:0];  // Lane lists map: [Connections][lanes]
reg  [LANE_ID_WIDTH-1:0]                    lane_cnt[NUM_SL3_LANES-1:0];
reg  [LANE_ID_WIDTH-1:0]                    curr_lane_rr_cnt[NUM_SL3_LANES-1:0];

reg  [LANE_ID_WIDTH-1:0]                    lane_id;

wire [LANE_ID_WIDTH-1:0]                    curr_conn_init;
reg  [LANE_ID_WIDTH-1:0]                    connection_initialized[NUM_SL3_LANES-1:0];

wire [LANE_ID_WIDTH-1:0]                    curr_conn_lanes_cnt;
wire [LANE_ID_WIDTH-1:0]                    curr_lane_rr_cnt_selected;

wire [NUM_SL3_LANES-1:0]                    lanes_ready;

PacketWord                                  network_layer_tx_packet_d1;
wire [NUM_SL3_LANES-1:0]                    network_layer_tx_packet_valid;
reg  [LANE_ID_WIDTH-1:0]                    lane_id_d1;

genvar i,j;
integer k;
//-----------------------------------------------------------------//
//----------------- Physical Lanes Table --------------------------//
//-----------------------------------------------------------------//
// Fill in Physical lanes table: 4 is the maximum number of logical connections
generate for (i = 0; i < NUM_SL3_LANES; i=i+1) begin: LanesTable

	// lane_cnt: count of lanes per device connection
	always@(posedge clk) begin
		if(~rst_n) begin
			lane_cnt[i]      <= 0;
		end 
		else if(physical_layer_program_en) begin
			lane_cnt[i]      <= physical_lane_list_count[i];  // 
		end
	end

	// lane_lists: lanes list per device connection
	for (j = 0; j < NUM_SL3_LANES; j=j+1) begin: lanesLists
		always@(posedge clk) begin
			if(~rst_n) begin
				lane_lists[i][j]    <= 0;
			end 
			else if(physical_layer_program_en) begin
				lane_lists[i][j]    <= physical_lane_list[i][2*(j+1)-1:j*2];
			end
		end
	end 
end
endgenerate

//--------- Compute to which lane this request should be made
// lane_id: current lane on which we will send the packet word.
always@(*) begin
	case (network_layer_tx.connection_id[1:0])
		2'b11: lane_id = lane_lists[3][0];        // if we have 4 connections, only 1 lane per connection
		2'b10: lane_id = lane_lists[2][0];        // if we have three connections, only one lane assigned to connection 3
		2'b01: begin                              // if we have 2 connections, only up to 2 lanes assigned to connection 2
			if(curr_lane_rr_cnt[1]==0) begin 
				lane_id = lane_lists[1][0]; 
			end
			else begin 
				lane_id = lane_lists[1][1]; 
			end
		end
		2'b00: begin                              // On connection #1 up to 4 lanes can be used
			lane_id = lane_lists[0][curr_lane_rr_cnt[0]];
		end
		default: lane_id = 2'b00;
	endcase
end

//--------------------------------------------------------//
// Update current ptr for current connection ID
assign curr_conn_lanes_cnt       = lane_cnt[network_layer_tx.connection_id[1:0]];
assign curr_lane_rr_cnt_selected = curr_lane_rr_cnt[network_layer_tx.connection_id[1:0]];

// curr_lane_rr_cnt: For every logical connection we keep a round robin counter to the lanes list of current connection 
always@(posedge clk) begin
	if(~rst_n) begin
		for (k = 0; k < NUM_SL3_LANES; k=k+1) begin          
			curr_lane_rr_cnt[k]      <= 0;  
		end
	end 
	else if(network_layer_tx.packet_word.valid & network_layer_tx.packet_word.last) begin
		if(curr_lane_rr_cnt_selected == curr_conn_lanes_cnt) begin
			curr_lane_rr_cnt[network_layer_tx.connection_id[1:0]] <= 0;
		end
		else begin 
			curr_lane_rr_cnt[network_layer_tx.connection_id[1:0]] <= curr_lane_rr_cnt_selected + 1'b1;
		end
	end
end

// connection_initialized: 
always@(posedge clk) begin
	if(~rst_n) begin
		for (k = 0; k < NUM_SL3_LANES; k=k+1) begin          
			connection_initialized[k]      <= 0;  
		end
	end 
	else if(network_layer_tx.packet_word.valid & network_layer_tx.packet_word.last) begin
		connection_initialized[network_layer_tx.connection_id[1:0]] <= 1'b1;
	end
end	

assign curr_conn_init = connection_initialized[network_layer_tx.connection_id[1:0]] | connections_ready;


assign network_layer_tx_ready = lanes_ready[lane_id];

//-----------------------------------------------------------------//
//------------------------- TX Pipeline ---------------------------//
//-----------------------------------------------------------------//

// Register incoming network layer TX
always@(posedge clk) begin
	if(~rst_n) begin
		network_layer_tx_packet_d1  <= '{valid:1'b0, last:1'b0, first:1'b0, data:128'b0, header:'{dest_addr:16'b0, src_addr:16'b0, metadata:16'b0}};
	end 
	else begin
		network_layer_tx_packet_d1.data   <= network_layer_tx.packet_word.data;
		network_layer_tx_packet_d1.last   <= network_layer_tx.packet_word.last;
		network_layer_tx_packet_d1.first  <= network_layer_tx.packet_word.first;
		network_layer_tx_packet_d1.valid  <= network_layer_tx.packet_word.valid;
		network_layer_tx_packet_d1.header <= network_layer_tx.packet_word.header;
		
		//network_layer_tx_packet_d1.controller_packet <= network_layer_tx.controller_packet;

		lane_id_d1                        <= lane_id;
	end
end	

generate for (i = 0; i < NUM_SL3_LANES; i=i+1) begin: laneTXs

	assign network_layer_tx_packet_valid[i] = network_layer_tx_packet_d1.valid & (lane_id_d1 == i);
	
	lane_tx_unit lane_tx_i(
		.clk                             (clk),
		.rst_n                           (rst_n),

		.network_layer_tx_packet         (network_layer_tx_packet_d1),
		.network_layer_tx_packet_valid   (network_layer_tx_packet_valid[i]),
		.lane_ready                      (lanes_ready[i]),

		.sl_tx_out                       (sl_tx_out[i]),
		.sl_tx_full_in                   (sl_tx_full_in[i]), 

		.sl_rx_oob_in                    (sl_rx_oob_in[i]), 
		.sl_rx_oob_grant_out             (sl_rx_oob_grant_out[i]), 

		.credits                         (tx_lane_credits[i]), 
		.sentLines                       (lane_sentLines[i])          
		);
end
endgenerate

endmodule