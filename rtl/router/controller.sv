


import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;


/*
     router_config: 128 bits vector
*/

module controller (
	input  wire                                  clk,    // Clock
	input  wire                                  rst_n,  // Asynchronous reset active low

	// Controller network TX/RX
	output UserPacketWord                        controller_tx, 
	input  wire                                  controller_tx_ready, 

	input  UserPacketWord                        controller_rx, 
	output wire                                  controller_rx_ready, 
	
	output reg 									 connections_ready,
	// Node programming parameters
	output wire                                  network_layer_program_en, 
	output wire  [ROUTING_TABLE_WORD_WIDTH-1:0]  routing_table_word, 
	output wire  [ROUTING_TABLE_WORD_BITS-1:0]   routing_table_word_addr,
	output wire                                  routing_table_program_en, 
    
    output wire  [15:0]                          NetworkSize, 
	output wire  [DEVICE_ID_WIDTH-1:0]           device_id,

	output wire  [CONN_ID_WIDTH-1:0]             lanes_connection_id[NUM_SL3_LANES-1:0], 
	output wire  [LANE_ID_WIDTH-1:0]             lanes_order_id[NUM_SL3_LANES-1:0],
	output wire  [LANE_ID_LIST_WIDTH-1:0]        physical_lane_list[NUM_SL3_LANES-1:0],
	output wire  [LANE_ID_WIDTH-1:0]             physical_lane_list_count[NUM_SL3_LANES-1:0],
	output wire  [LANE_ID_WIDTH-1:0]             num_connections_minus_one,
	output wire                                  physical_layer_program_en,
    
    // PCIe-Controller Signals
    input  PCIEPacket                            controller_pcie_packet_in,
  	output wire                                  controller_pcie_full_out, 

  	output PCIEPacket                            controller_pcie_packet_out,
    input  wire                                  controller_pcie_grant_in,

    // softRegs Out 
    output reg   [63:0]  						 stateReg, 
    output reg   [63:0]  						 routerConfig_l, 
    output reg   [63:0]  						 routerConfig_h, 
    output reg   [63:0]  						 routerTable_l, 
    output reg   [63:0]  						 routerTable_h
);


localparam [2:0]   NOT_PROGRAMMED     = 3'b000, 
				   RCV_ROUTING_TABLE  = 3'b001, 
				   FILL_ROUTING_TABLE = 3'b010, 
				   NET_PROGRAMMING    = 3'b011, 
				   WAIT_DEVICE_ACK    = 3'b100, 
				   ACK_PROGRAM_1      = 3'b101, 
				   ACK_PROGRAM_2      = 3'b110,
				   ROUTER_PROGRAMMED  = 3'b111;


wire  [15:0]                  	NetSize;
wire  [7:0]                   	device_program_lines; 
wire  [7:0]                   	routingTableSize;
wire  [15:0]                  	devAddr;

wire  [31:0]                  	router_table_vec[3:0];


reg   [1:0]     				routingTableWords;
reg  							MasterNode;
reg   [2:0]      				controller_state;
reg   [127:0]    				router_table;
reg   [127:0]    				router_config;
reg             				prog_lines_cnt;
reg   [7:0]      				prog_devices_cnt;

wire    						nrx_fifo_valid;
wire 							nrx_fifo_re;
wire 							nrx_fifo_full;
wire  [144:0]  					nrx_fifo_dout;

wire  [144:0]  					ntx_fifo_dout;
wire    						ntx_fifo_valid;
wire 							ntx_fifo_full;

reg   [15:0]  					master_address;
reg 							progOverPCIe;

reg   [DEVICE_ID_WIDTH-1:0]     slave_device_id;

UserPacketWord 					controller_tx_d1;
UserPacketWord                  controller_rx_w1;

//
assign NetworkSize = NetSize;

assign controller_pcie_full_out = ~( (controller_state == NET_PROGRAMMING) | 
	                                 (controller_state == NOT_PROGRAMMED)  | 
	                                 (controller_state == RCV_ROUTING_TABLE) );


// device ID
// Program device
assign NetSize                   = router_config[15:0];         // Number of FPGAs in the network
assign device_id                 = router_config[25:16];        // Current device ID

assign num_connections_minus_one = router_config[56+LANE_ID_WIDTH-1:56];

assign routingTableSize          = router_config[103:96];     // number of 32 bit words representing routing table entries
assign device_program_lines      = router_config[111:104];

genvar i;
generate for (i = 0; i < NUM_SL3_LANES; i=i+1) begin: lanesProg
	assign lanes_connection_id[i]      = router_config[32+LANE_ID_WIDTH*(i+1)-1:32+LANE_ID_WIDTH*i];
	assign lanes_order_id[i]           = router_config[40+LANE_ID_WIDTH*(i+1)-1:40+LANE_ID_WIDTH*i];

	assign physical_lane_list_count[i] = router_config[48+LANE_ID_WIDTH*(i+1)-1:48+LANE_ID_WIDTH*i];

	assign physical_lane_list[i]       = router_config[64+LANE_ID_LIST_WIDTH*(i+1)-1:64+LANE_ID_LIST_WIDTH*i];
end
endgenerate

assign routing_table_word       = router_table_vec[routingTableWords];
assign routing_table_word_addr  = {{(ROUTING_TABLE_WORD_BITS-2){1'b0}}, routingTableWords};
assign routing_table_program_en = controller_state == FILL_ROUTING_TABLE;

assign network_layer_program_en = controller_state == ACK_PROGRAM_1;

assign router_table_vec[0] = router_table[31:0];
assign router_table_vec[1] = router_table[63:32];
assign router_table_vec[2] = router_table[95:64];
assign router_table_vec[3] = router_table[127:96];

assign physical_layer_program_en = controller_state == RCV_ROUTING_TABLE;


always@(posedge clk) begin 
	if(~rst_n) begin

		master_address       <= 0;
		routingTableWords    <= 0;
		controller_state     <= NOT_PROGRAMMED;
		MasterNode           <= 1'b0;
		router_config        <= 128'b0;
		router_table         <= 128'b0;
		prog_lines_cnt       <= 0;
		prog_devices_cnt     <= 0;
		progOverPCIe         <= 1'b0;
		controller_tx_d1     <= '{metadata:0, address: 0, valid: 1'b0, last: 0, data: 0};

		controller_pcie_packet_out <= '{last:1'b0, valid: 1'b0, pad: 4'b0, slot: 16'b0, data:128'b0};

		stateReg       <= 0;
		routerConfig_l <= 0;
		routerConfig_h <= 0;
		routerTable_l  <= 0;
		routerTable_h  <= 0;

		slave_device_id <= 0;
		connections_ready <= 0;
	end
	else begin 

		// SoftRegs
		stateReg       <= {61'b0, controller_state};
		routerConfig_l <= router_config[63:0];
		routerConfig_h <= router_config[127:64];
		routerTable_l  <= router_table[63:0];
		routerTable_h  <= router_table[127:64];
		//
		case (controller_state)
			NOT_PROGRAMMED: begin 
				master_address <= 0;

				if(controller_pcie_packet_in.valid) begin 
					controller_state <= RCV_ROUTING_TABLE;
					connections_ready <= 1'b1;
					MasterNode       <= controller_pcie_packet_in.data[112];
					progOverPCIe     <= 1'b1;
					//
					router_config    <= controller_pcie_packet_in.data;

					if(controller_pcie_packet_in.data[112]) begin
						connections_ready <= 1'b1;
					end
				end
				else if(controller_rx_w1.valid) begin
					controller_state <= RCV_ROUTING_TABLE;
					MasterNode       <= 1'b0;
					progOverPCIe     <= 1'b0;
					//
					router_config    <= controller_rx_w1.data;
					master_address   <= controller_rx_w1.address;
				end
				// 
				routingTableWords    <= 0;
				prog_lines_cnt       <= 0;
				prog_devices_cnt     <= 0;
			end
			RCV_ROUTING_TABLE: begin                      // NOTE: FOR NOW ONLY 128-BIT TABLE SIZE IS SUPPORTED
				if(controller_pcie_packet_in.valid) begin 
					router_table     <= controller_pcie_packet_in.data;
					controller_state <= FILL_ROUTING_TABLE;
				end
				else if(controller_rx_w1.valid) begin
					router_table     <= controller_rx_w1.data;
					controller_state <= FILL_ROUTING_TABLE;
				end
				//
			end
			FILL_ROUTING_TABLE: begin 
				if(routingTableWords == routingTableSize) begin
					controller_state  <= ACK_PROGRAM_1;
					routingTableWords <= 0;
				end
				else begin 
					routingTableWords <= routingTableWords + 1'b1;
				end
			end
			NET_PROGRAMMING: begin 
				controller_tx_d1           <= '{metadata:0, address: 0, valid: 1'b0, last: 0, data: 0};
				controller_pcie_packet_out <= '{last:1'b0, valid: 1'b0, pad: 4'b0, slot: 16'b0, data:128'b0};
				if(controller_pcie_packet_in.valid) begin 
					controller_tx_d1 <= '{metadata:0, address: devAddr, valid: 1'b1, last: controller_pcie_packet_in.last, data: controller_pcie_packet_in.data};
					
					if(prog_lines_cnt == 1) begin
						prog_lines_cnt   <= 0;
						controller_state <= WAIT_DEVICE_ACK;
					end
					else begin 
						prog_lines_cnt  <= prog_lines_cnt + 1'b1;
						slave_device_id <= controller_pcie_packet_in.data[DEVICE_ID_WIDTH + 15:16];
					end
				end
			end
			WAIT_DEVICE_ACK: begin 
				controller_tx_d1 <= '{metadata:0, address: 0, valid: 1'b0, last: 0, data: 0};
				if(controller_rx_w1.valid) begin
					controller_pcie_packet_out <= '{last:1'b1, valid: 1'b1, pad: 4'b0, slot: 16'b0, data:{112'b0, controller_rx_w1.address}};
					prog_devices_cnt           <= prog_devices_cnt + 1'b1;

					if(prog_devices_cnt == NetSize[7:0]) begin
						controller_state <= ROUTER_PROGRAMMED;
					end
					else begin 
						controller_state <= NET_PROGRAMMING;
					end
				end
			end
			//
			ACK_PROGRAM_1: begin 
				if(progOverPCIe) begin
					// send prog ack over PCIe
					controller_pcie_packet_out <= '{last:1'b0, valid: 1'b1, pad: 4'b0, slot: 16'b0, data:{118'b0, device_id}};
					//prog_devices_cnt           <= prog_devices_cnt + 1'b1;
					controller_state  <= ACK_PROGRAM_2;
				end
				else begin 
					controller_tx_d1 <= '{metadata:0, address: master_address, valid: 1'b1, last: 1'b0, data: {118'b0, device_id}};
					controller_state  <= ACK_PROGRAM_2;
				end
			end
			ACK_PROGRAM_2: begin 
				if(progOverPCIe) begin
					// send prog ack over PCIe
					controller_pcie_packet_out <= '{last:1'b1, valid: 1'b1, pad: 4'b0, slot: 16'b0, data:{118'b0, device_id}};
					prog_devices_cnt           <= prog_devices_cnt + 1'b1;

					if(MasterNode) begin
						controller_state  <= NET_PROGRAMMING;
					end
					else begin 
						controller_state  <= ROUTER_PROGRAMMED;
					end
				end
				else begin 
					controller_tx_d1 <= '{metadata:0, address: master_address, valid: 1'b1, last: 1'b1, data: {118'b0, device_id}};
					controller_state  <= ROUTER_PROGRAMMED;
				end
			end
			ROUTER_PROGRAMMED: begin 
				controller_tx_d1           <= '{metadata:0, address: 0, valid: 1'b0, last: 1'b0, data: 0};
				controller_pcie_packet_out <= '{last:1'b0, valid: 1'b0, pad: 4'b0, slot: 16'b0, data:128'b0};
			end
		endcase
	end
end

assign devAddr = (prog_lines_cnt == 0)? {2'b00, controller_pcie_packet_in.data[DEVICE_ID_WIDTH + 15:16], CONTROLLER_ID} : 
										{2'b00, slave_device_id, CONTROLLER_ID};
// 

//-------------------------------------------------------//

// Network TX FIFO
quick_fifo  #(.FIFO_WIDTH( $bits(UserPacketWord) - 1),        
            .FIFO_DEPTH_BITS(9),
            .FIFO_ALMOSTFULL_THRESHOLD(2**9 -8)
            ) ntx_fifo(
        .clk                (clk),
        .reset_n            (rst_n),
        .din                ({controller_tx_d1.address, controller_tx_d1.last, controller_tx_d1.data}),
        .we                 (controller_tx_d1.valid),
        .re                 (controller_tx_ready),
        .dout               (ntx_fifo_dout),
        .empty              (),
        .valid              (ntx_fifo_valid),
        .full               (ntx_fifo_full),
        .count              (),
        .almostfull         ()
    );

assign controller_tx = '{metadata:0, address: ntx_fifo_dout[144:129], valid: ntx_fifo_valid, last: ntx_fifo_dout[128], data: ntx_fifo_dout[127:0]};

// Network RX FIFO
quick_fifo  #(.FIFO_WIDTH( $bits(UserPacketWord) - 1),        
            .FIFO_DEPTH_BITS(9),
            .FIFO_ALMOSTFULL_THRESHOLD(2**9 -8)
            ) nrx_fifo(
        .clk                (clk),
        .reset_n            (rst_n),
        .din                ({controller_rx.address, controller_rx.last, controller_rx.data}),
        .we                 (controller_rx.valid),
        .re                 (nrx_fifo_re),
        .dout               (nrx_fifo_dout),
        .empty              (),
        .valid              (nrx_fifo_valid),
        .full               (nrx_fifo_full),
        .count              (),
        .almostfull         ()
    );


assign controller_rx_ready = ~nrx_fifo_full;

assign nrx_fifo_re         = (controller_state == NOT_PROGRAMMED)    | 
                             (controller_state == RCV_ROUTING_TABLE) | 
                             (controller_state == WAIT_DEVICE_ACK);

assign controller_rx_w1    = '{metadata:0, address: nrx_fifo_dout[144:129], valid: nrx_fifo_valid, last: nrx_fifo_dout[128], data: nrx_fifo_dout[127:0]};


endmodule