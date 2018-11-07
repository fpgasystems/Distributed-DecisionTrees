


import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;

/*
   
*/

module PhysicalLayerRX 
	(
	input  wire                                   clk,    // Clock
	input  wire                                   rst_n,  // Asynchronous reset active low

	input  wire  [CONN_ID_WIDTH-1:0]              lanes_connection_id[NUM_SL3_LANES-1:0], 
	input  wire  [LANE_ID_WIDTH-1:0]              lanes_order_id[NUM_SL3_LANES-1:0],
	input  wire  [LANE_ID_WIDTH-1:0]              physical_lane_list_count[NUM_SL3_LANES-1:0],
	input  wire  [LANE_ID_WIDTH-1:0]              num_connections_minus_one,
	input  wire                                   physical_layer_program_en,
	input  wire  [DEVICE_ID_WIDTH-1:0] 			  NetSize,
	input  wire                                   router_ready, 

	output PacketWord                             network_layer_rx, 
	input  wire                                   network_layer_rx_ready, 

	input  SL3DataInterface                       sl_rx_in            [NUM_SL3_LANES-1:0],
    output                                        sl_rx_grant_out     [NUM_SL3_LANES-1:0],
    output SL3OOBInterface                        sl_tx_oob_out       [NUM_SL3_LANES-1:0],
    input                                         sl_tx_oob_full_in   [NUM_SL3_LANES-1:0], 

    output wire  [14:0]                           rx_lane_credits [NUM_SL3_LANES-1:0],
    output wire  [48:0]                           lane_rcvLines[NUM_SL3_LANES-1:0], 
    output wire  [31:0]                           phy_rx_error_status,
    output wire  [39:0]							  phy_rx_error_packets_info
);


//
reg  [CONN_ID_WIDTH-1:0]              connection_id[NUM_SL3_LANES-1:0]; 
reg  [LANE_ID_WIDTH-1:0]              lane_order_id[NUM_SL3_LANES-1:0];
reg  [LANE_ID_WIDTH-1:0]              conn_lane_cnt[NUM_SL3_LANES-1:0];
reg  [LANE_ID_WIDTH-1:0]              num_conns_minus_one;


wire [USER_DATA_BUS_WIDTH + 1:0]      rr_fifo_din;
wire [USER_DATA_BUS_WIDTH + 1:0]      rr_fifo_dout;

wire                                  rr_fifo_ready;
wire                                  rr_fifo_almfull;
wire                                  rr_fifo_valid;
reg                                   rr_datain_valid_d1;

wire                                  rr_datain_valid;
reg                                   rr_datain_last;

wire [NUM_SL3_LANES-1:0]              lane_rx_valids;
reg  [LANE_ID_WIDTH-1:0]              conn_lane_rr_count[NUM_SL3_LANES-1:0];
wire [LANE_ID_WIDTH-1:0]              curr_conn_lane_cnt;
wire [LANE_ID_WIDTH-1:0]              curr_conn_lane_rr_count;
reg  [LANE_ID_WIDTH-1:0]              curr_conn_id;

SL3DataInterface                      lane_rx[NUM_SL3_LANES-1:0];
SL3DataInterface                      rr_lane_rx;

PacketWord                            pfifo_in;
wire                                  pfifo_in_ready;
reg                                   header_valid;
reg   [NET_ADDRESS_WIDTH-1:0]		  dest_addr_d;
reg   [NET_ADDRESS_WIDTH-1:0]		  src_addr_d;

PacketHeader 						  header_data;

reg                                   physical_layer_programmed;

reg 								  packet_lock_set;
reg 								  packet_first;
reg 								  first_data_set;
reg 								  discard_curr_packet;
reg   [DEVICE_ID_WIDTH-1:0] 		  NetSize_d1;

reg   [15:0]						  first_error_packet_pos;
reg   [15:0]						  last_error_packet_pos;
reg   [15:0]						  received_packets_count;
reg   [7 :0]						  error_packet_count;

//
genvar i,j;
integer k;
//-----------------------------------------------------------------//
//----------------- Physical Lanes Table --------------------------//
//-----------------------------------------------------------------//
// Fill in Physical lanes table: every lane is programmed with the device connection ID, 
// and its order among the connection lanes
generate for (i = 0; i < NUM_SL3_LANES; i=i+1) begin: connections
	
	always@(posedge clk) begin
		if(~rst_n) begin
			connection_id[i]      <= 0;
			lane_order_id[i]      <= 0;
			conn_lane_cnt[i]      <= 0;                       // number of lanes per connection
		end 
		else if(physical_layer_program_en) begin
			connection_id[i]      <= lanes_connection_id[i];
			lane_order_id[i]      <= lanes_order_id[i];
			conn_lane_cnt[i]      <= physical_lane_list_count[i];
		end
	end
end
endgenerate

//
always@(posedge clk) begin 
	if(~rst_n) begin
		num_conns_minus_one       <= 0;
		physical_layer_programmed <= 1'b0;
		NetSize_d1                <= 0;
	end
	else begin 
		NetSize_d1 <= NetSize;
		if(physical_layer_program_en) begin 
			num_conns_minus_one <= num_connections_minus_one;
		end

		if(router_ready) begin
			physical_layer_programmed <= 1'b1;
		end
	end 
end

//-----------------------------------------------------------------//
//------------------------- TX Pipeline ---------------------------//
//-----------------------------------------------------------------//

// RX Packet FIFO
PacketFIFO pfifo_rx(
	.clk                       (clk),    
	.rst_n                     (rst_n), 

	.pfifo_in                  (pfifo_in),
	.pfifo_in_ready            (pfifo_in_ready), 

	.pfifo_out                 (network_layer_rx),
	.pfifo_out_ready           (network_layer_rx_ready), 
	.pfifo_error_status        (phy_rx_error_status), 
	.packet_error_detected     ()
);

assign pfifo_in.data   = rr_fifo_dout[USER_DATA_BUS_WIDTH + 1: 2];
assign pfifo_in.last   = rr_fifo_dout[0];
assign pfifo_in.valid  = header_valid & rr_fifo_valid & ~discard_curr_packet;
assign pfifo_in.first  = header_valid & ~first_data_set; 
assign pfifo_in.header =  header_data; //'{src_addr: src_addr_d, dest_addr: dest_addr_d};

// header

assign phy_rx_error_packets_info = {error_packet_count, last_error_packet_pos, first_error_packet_pos};

always@(posedge clk) begin 
	if(~rst_n) begin
		header_valid <= 1'b0;
		dest_addr_d  <= 0;
		src_addr_d   <= 0;
		first_data_set <= 1'b0;
		discard_curr_packet <= 1'b0;
		header_data    <= '{src_addr:0, dest_addr:0, metadata:0};

		error_packet_count <= 0;
		first_error_packet_pos <= 0;
		last_error_packet_pos <= 0;
		received_packets_count <= 0;
	end
	else begin 
		// if the last line detected reset header_valid

		// first_data_set
		if(rr_fifo_valid & pfifo_in_ready) begin
			if(rr_fifo_dout[0]) begin
				first_data_set <= 1'b0;
			end
			else if(header_valid) begin 
				first_data_set <= 1'b1;
			end
		end

		// header valid
		if(rr_fifo_valid) begin
			if((~header_valid)) begin
				header_valid   <= 1'b1;
				header_data    <= rr_fifo_dout[3*NET_ADDRESS_WIDTH+2-1:2];
				dest_addr_d    <= rr_fifo_dout[NET_ADDRESS_WIDTH + 1: 2];
				src_addr_d     <= rr_fifo_dout[NET_ADDRESS_WIDTH*2 + 1: NET_ADDRESS_WIDTH+2];

				received_packets_count <= received_packets_count + 1'b1;

				if(~(rr_fifo_dout[DEVICE_ID_WIDTH+USER_ID_WIDTH+1:USER_ID_WIDTH+2] < NetSize_d1)) begin
					discard_curr_packet <= 1'b1;
					if(!(error_packet_count == 8'hFF)) begin
						error_packet_count <= error_packet_count + 1'b1;
					end
					
					if(error_packet_count == 8'h00) begin
						first_error_packet_pos <= received_packets_count;
					end
					else begin 
						last_error_packet_pos <= received_packets_count;
					end
				end
			end
			else if(pfifo_in_ready & rr_fifo_dout[0]) begin
				header_valid   <= 1'b0;
				discard_curr_packet <= 1'b0;
			end
		end
	end
end
// Round Robin output FIFO
quick_fifo  #(.FIFO_WIDTH( USER_DATA_BUS_WIDTH + 2 ),        
            .FIFO_DEPTH_BITS(9),
            .FIFO_ALMOSTFULL_THRESHOLD(2**9 -8)
            ) rr_fifo(
        .clk                (clk),
        .reset_n            (rst_n),
        .din                ({rr_lane_rx.data, packet_first, rr_lane_rx.last}),
        .we                 (rr_datain_valid_d1),
        .re                 (pfifo_in_ready | ~header_valid | discard_curr_packet),
        .dout               (rr_fifo_dout),
        .empty              (),
        .valid              (rr_fifo_valid),
        .full               (),
        .count              (),
        .almostfull         (rr_fifo_almfull)
    );

// Lanes Multiplexer
 
assign rr_datain_valid = |lane_rx_valids;
assign rr_fifo_ready   = ~rr_fifo_almfull;

// rr_datain_last
always@(*) begin 
	case (lane_rx_valids)
		4'b0001 : rr_datain_last = lane_rx[0].last;
		4'b0010 : rr_datain_last = lane_rx[1].last;
		4'b0100 : rr_datain_last = lane_rx[2].last;
		4'b1000 : rr_datain_last = lane_rx[3].last;
		default : rr_datain_last = 0;
	endcase
end

// rr_lane_rx: lane word to be selected
// rr_datain_valid_d1: buffer selected lane valid signal
always@(posedge clk) begin 
	if(~rst_n) begin
		rr_lane_rx         <= 0;
		rr_datain_valid_d1 <= 0;
	end
	else begin 
		rr_datain_valid_d1 <= rr_datain_valid & rr_fifo_ready;
		case (lane_rx_valids)
			4'b0001 : rr_lane_rx <= lane_rx[0];
			4'b0010 : rr_lane_rx <= lane_rx[1];
			4'b0100 : rr_lane_rx <= lane_rx[2];
			4'b1000 : rr_lane_rx <= lane_rx[3];
			default : rr_lane_rx <= 0;
		endcase
	end
end

// Lanes Round Robin
assign curr_conn_lane_rr_count = conn_lane_rr_count[curr_conn_id];
assign curr_conn_lane_cnt      = conn_lane_cnt[curr_conn_id];

always@(posedge clk) begin
	if(~rst_n) begin
		curr_conn_id    <= 0;
		packet_lock_set <= 1'b0;
		packet_first    <= 1'b0;

		for (int k = 0; k < NUM_SL3_LANES; k=k+1) begin
			conn_lane_rr_count[k] <= 0;
			
		end
	end 
	else begin
		// Round Robin of connection ID: if we start receving a packet on a connection
		// we lock on this connection ID until the full packet received. 
		if(rr_fifo_ready & ((~packet_lock_set & ~rr_datain_valid) | (rr_datain_valid & rr_datain_last)) ) begin
			if(curr_conn_id == num_conns_minus_one) begin
				curr_conn_id <= 0;
			end
			else begin 
				curr_conn_id <= curr_conn_id + 1'b1;
			end
		end
		// Round Robin of conn_lane_rr_count and packet lock set
		if(rr_fifo_ready & rr_datain_valid ) begin
			// 
			if(rr_datain_last & physical_layer_programmed) begin
				if(curr_conn_lane_rr_count == curr_conn_lane_cnt) begin
					conn_lane_rr_count[curr_conn_id] <= 0;
				end
				else begin 
					conn_lane_rr_count[curr_conn_id] <= curr_conn_lane_rr_count + 1'b1;
				end
			end
			
			// packet_lock_set
			packet_lock_set <= 1'b1;
			if(rr_datain_last) begin
				packet_lock_set <= 1'b0;
			end
			//packet first
			packet_first <= 1'b1;
			if(packet_lock_set) begin
				packet_first <= 1'b0;
			end
		end

	end
end	


//-----------------------------------------------------------------//
//----------------------- Lanes Receivers -------------------------//
//-----------------------------------------------------------------//
generate for (i = 0; i < NUM_SL3_LANES; i=i+1) begin: laneRXs
	
	lane_rx_unit  lane_rx_i(
		.clk                        (clk),
		.rst_n                      (rst_n),
		.rx_programmed              (physical_layer_programmed),
		.lane_connection_id         (connection_id[i]),
		.lane_order_id              (lane_order_id[i]),

		.curr_conn_id               (curr_conn_id), 
		.curr_lane_id               (curr_conn_lane_rr_count), 

		.lane_rx                    (lane_rx[i]),
		.lane_rx_ready              (rr_fifo_ready),

		.sl_rx_in                   (sl_rx_in[i]),
		.sl_rx_grant_out            (sl_rx_grant_out[i]), 

		.sl_tx_oob_out              (sl_tx_oob_out[i]), 
		.sl_tx_oob_full_in          (sl_tx_oob_full_in[i]), 

		.credits                    (rx_lane_credits[i]), 
		.rcvLines                   (lane_rcvLines[i])         
		);

//
assign lane_rx_valids[i] = lane_rx[i].valid;


end
endgenerate

endmodule