
import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;



module NetworkLayerTX (
	input  wire                                   clk,    // Clock
	input  wire                                   rst_n,  // Asynchronous reset active low

	input  wire  [ROUTING_TABLE_WORD_WIDTH-1:0]   routing_table_word, 
	input  wire  [ROUTING_TABLE_WORD_BITS-1:0]    routing_table_word_addr,
	input  wire                                   routing_table_program_en, 

	input  PacketWord                             user_layer_tx, 
	input  wire                                   controller_packet,
	output wire                                   user_layer_tx_ready,
	output reg 	 [19:0] 						  net_tx_lines,

	input  wire  [15:0]                           NetSize,
	input  wire  [1:0]                            num_connections_minus_one,

	output NetworkLayerPacketTX                   layer_tx, 
	input  wire                                   layer_tx_ready, 

	output wire [15:0]                            layer_tx_error_status
	
);

reg 									controller_packet_d1;
PacketWord                              user_layer_tx_d1;

wire                                    routingTable_ren;
wire [CONN_ID_WIDTH-1:0]                routingTable_dout;
wire [ROUTING_TABLE_SIZE_BITS-1:0]      routingTable_raddr;
wire                                    routingTable_valid;


reg  [7:0] 								wrong_rt_entry_count;
reg  [7:0] 								wrong_dest_addr_count;


//-----------------------------------------------------------------//
//------------------------ Layer Status ---------------------------//
//-----------------------------------------------------------------//

always@(posedge clk) begin
	if(~rst_n) begin 
		wrong_rt_entry_count  <= 8'd0;
		wrong_dest_addr_count <= 8'd0;
	end
	else begin 
		if(routingTable_valid & (routingTable_dout > num_connections_minus_one)) begin
			wrong_rt_entry_count <= wrong_rt_entry_count + 8'd1;
		end

		if(user_layer_tx.valid & (!(user_layer_tx.header.dest_addr[DEVICE_ID_WIDTH+USER_ID_WIDTH-1:USER_ID_WIDTH] < NetSize))) begin
			if(!(wrong_dest_addr_count == 8'hFF) ) begin
				wrong_dest_addr_count <= wrong_dest_addr_count + 8'd1;
			end
			
		end
	end
end 

assign layer_tx_error_status = {wrong_rt_entry_count, wrong_dest_addr_count};
//-----------------------------------------------------------------//
//------------------------ Routing Table --------------------------//
//-----------------------------------------------------------------//

routing_table routingTable (
    .clk                (clk),
    .we                 (routing_table_program_en),
	.re                 (routingTable_ren),  
	.waddr              (routing_table_word_addr),
    .raddr              (routingTable_raddr),
    .din                (routing_table_word),
    .dout               (routingTable_dout),
    .valid              (routingTable_valid)
);

//-----------------------------------------------------------------//
//------------------------- TX Pipeline ---------------------------//
//-----------------------------------------------------------------//

// Stage 1:

always@(posedge clk) begin
	if(~rst_n) begin 
		user_layer_tx_d1     <= '{ header: '{dest_addr:0, src_addr:0, metadata:0}, valid: 0, first: 0, last: 0, data: 0};
		controller_packet_d1 <= 1'b0;
		net_tx_lines         <= 0;
	end
	else begin 
		user_layer_tx_d1     <= user_layer_tx;
		controller_packet_d1 <= controller_packet;

		if(user_layer_tx_d1.valid) begin
			net_tx_lines <= net_tx_lines + 1'b1;
		end
	end
end 

assign routingTable_ren   = user_layer_tx.valid;
assign routingTable_raddr = {{(ROUTING_TABLE_SIZE_BITS-DEVICE_ID_WIDTH){1'b0}}, user_layer_tx.header.dest_addr[DEVICE_ID_WIDTH+USER_ID_WIDTH-1:USER_ID_WIDTH]};

// Output
assign layer_tx.packet_word       = user_layer_tx_d1;
assign layer_tx.controller_packet = controller_packet_d1;
assign layer_tx.connection_id     = (routingTable_valid)? routingTable_dout : 0;

assign user_layer_tx_ready = layer_tx_ready;

endmodule