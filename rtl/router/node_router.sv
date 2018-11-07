/*
 * Copyright 2018 - 2019 Systems Group, ETH Zurich
 *
 * This hardware operator is free software: you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as published
 * by the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;

/*
    Transmit protocol:
      - A new packet is detected when the old packet is completed and the valid signal becomes '1'. 
      - The user layer sets a packet start flag on the TX bus, and stores the packet address. The stored address is
        used to determine and warn the user if it sets another address before the packet is completed. 
        (In a later version, multiple packet addresses can be supported for a single user module and a packet ID is 
        set with each bus entry)
        The user layer keeps log of packet addresses for the different users.
      - The network layer just resolve to which logical connection to route and forward the packet word.
      - The Physical layer will first send the header if it is the start of the packet as marked by the user layer

*/



module node_router #(parameter NUM_USERS = 1)
	(
	input  wire                            clk,    // Clock
	input  wire                            rst_n,  // Asynchronous reset active low

  // PCIe - controller I/O
  input  PCIEPacket                      controller_pcie_packet_in,
  output wire                            controller_pcie_full_out, 

  output PCIEPacket                      controller_pcie_packet_out,
  input  wire                            controller_pcie_grant_in,

  // SoftRegs 
  output wire  [63:0]                    stateReg, 
  output wire  [63:0]                    routerConfig_l, 
  output wire  [63:0]                    routerConfig_h, 
  output wire  [63:0]                    routerTable_l, 
  output wire  [63:0]                    routerTable_h,

  output reg   [63:0]                    rx_lane_regs[NUM_SL3_LANES-1:0],
  output reg   [63:0]                    tx_lane_regs[NUM_SL3_LANES-1:0],
  output reg   [63:0]                    tx_line_count,

  output reg   [63:0]                    error_status_1, 
  output reg   [63:0]                    error_status_2,
  output reg   [63:0]                    error_status_3,

	// Physical Layer inputs /outputs
  output SL3DataInterface                sl_tx_out           [NUM_SL3_LANES-1:0],
  input  wire                            sl_tx_full_in       [NUM_SL3_LANES-1:0],
  output SL3OOBInterface                 sl_tx_oob_out       [NUM_SL3_LANES-1:0],
  input  wire                            sl_tx_oob_full_in   [NUM_SL3_LANES-1:0],

  input SL3DataInterface                 sl_rx_in            [NUM_SL3_LANES-1:0],
  output                                 sl_rx_grant_out     [NUM_SL3_LANES-1:0],
  input SL3OOBInterface                  sl_rx_oob_in        [NUM_SL3_LANES-1:0],
  output                                 sl_rx_oob_grant_out [NUM_SL3_LANES-1:0],

	// User Layer inputs/outputs
	input  UserPacketWord                  users_tx[NUM_USERS-1:0], 
	output wire                            users_tx_ready[NUM_USERS-1:0],

 	output UserPacketWord                  users_rx[NUM_USERS-1:0], 
	input  wire                            users_rx_ready[NUM_USERS-1:0]
);




wire                                  user_layer_tx_users_ready[NUM_USERS+1:0];
PacketWord                            user_layer_tx_users[NUM_USERS+1:0];

wire  [USER_ID_WIDTH-1:0]             user_ID[NUM_USERS-1:0];
reg                                   user_packet_lock[NUM_USERS-1:0];
wire                                  user_first[NUM_USERS-1:0];
PacketHeader                          users_tx_header[NUM_USERS-1:0];

wire                                  user_layer_rx_users_ready[NUM_USERS:0];
UserPacketWord                        user_layer_rx_users[NUM_USERS:0];  

reg                                   controller_packet_lock;
wire                                  controller_packet_first;
wire                                  controller_packet;

PacketHeader                          controller_tx_header;

// Controller IO
UserPacketWord                        controller_tx;
wire                                  controller_tx_ready;

UserPacketWord                        controller_rx;
wire                                  controller_rx_ready;

// User Layer IO
PacketWord                            user_layer_tx; 
wire                                  user_layer_tx_ready; 

PacketWord                            user_layer_rx; 
wire                                  user_layer_rx_ready;

wire    [19:0]                        user_tx_lines;
// Network Layer IO
PacketWord                            network_layer_rx_ext_device;
wire                                  network_layer_rx_ext_device_ready;

NetworkLayerPacketTX                  network_layer_tx; 
wire                                  network_layer_tx_ready;

PacketWord                            network_layer_rx; 
wire                                  network_layer_rx_ready;

wire  [CONN_ID_WIDTH-1:0]             lanes_connection_id[NUM_SL3_LANES-1:0]; 
wire  [LANE_ID_WIDTH-1:0]             lanes_order_id[NUM_SL3_LANES-1:0];
wire  [LANE_ID_LIST_WIDTH-1:0]        physical_lane_list[NUM_SL3_LANES-1:0]; 
wire  [LANE_ID_WIDTH-1:0]             physical_lane_list_count[NUM_SL3_LANES-1:0];
wire  [CONN_ID_WIDTH-1:0]             num_connections_minus_one;
wire                                  physical_layer_program_en;

wire                                  network_layer_program_en; 
wire  [ROUTING_TABLE_WORD_WIDTH-1:0]  routing_table_word; 
wire  [ROUTING_TABLE_WORD_BITS-1:0]   routing_table_word_addr;
wire                                  routing_table_program_en;

wire  [DEVICE_ID_WIDTH-1:0]           device_id;

wire  [11:0]                          tx_lane_credits [NUM_SL3_LANES-1:0];
wire  [47:0]                          lane_sentLines[NUM_SL3_LANES-1:0];
wire  [14:0]                          rx_lane_credits [NUM_SL3_LANES-1:0];
wire  [48:0]                          lane_rcvLines[NUM_SL3_LANES-1:0];

wire  [31:0]                          user_packet_error_status[NUM_USERS+1:0];
wire  [7:0]                           wrong_target_user_count;
wire  [31:0]                          phy_rx_error_status;
wire  [31:0]                          network_layer_error_status;
wire  [15:0]                          NetSize;
wire                                  connections_ready;
wire  [39:0]                          phy_rx_error_packets_info_w;
wire  [19:0]                          net_tx_lines;
wire  [31:0]                          packet_error_detected[NUM_USERS+1:0];
reg   [23:0]                          usr_tx_errors;

 
 always @(posedge clk) begin
      if(~rst_n) begin
        error_status_1  <= 0;
        error_status_2  <= 0;
        error_status_3  <= 0;
        tx_line_count   <= 0;
        usr_tx_errors   <= 0;
      end 
      else begin
        error_status_1  <= {user_packet_error_status[1], user_packet_error_status[2]};
        error_status_2  <= {phy_rx_error_status, network_layer_error_status};

        error_status_3  <= {usr_tx_errors, phy_rx_error_packets_info_w};

        tx_line_count   <= {12'b0, user_tx_lines, 12'b0, net_tx_lines};

        if(packet_error_detected[2]) begin
          usr_tx_errors <= usr_tx_errors + 1'b1;
        end
      end
    end

genvar i;
generate
  for (i = 0; i < NUM_SL3_LANES; i=i+1) begin: lane_regs

    always @(posedge clk) begin
      if(~rst_n) begin
        tx_lane_regs[i] <= 0;
        rx_lane_regs[i] <= 0;
      end 
      else begin
        tx_lane_regs[i] <= {4'b0, tx_lane_credits[i], lane_sentLines[i]};
        rx_lane_regs[i] <= {rx_lane_credits[i], lane_rcvLines[i]};
      end
    end
    
  end
endgenerate

//-------------------------------------------//
//------------- User Layer ------------------//
//-------------------------------------------//

generate
  for (i = 0; i < NUM_USERS; i=i+1) begin: usersInputs

    // TX
    assign user_ID[i]               = i;
    assign user_first[i]            = ~user_packet_lock[i] & users_tx[i].valid;
    assign users_tx_header[i]       = '{dest_addr: users_tx[i].address, src_addr: {2'b0, device_id, user_ID[i]}, metadata:users_tx[i].metadata};
    assign user_layer_tx_users[i+2] = '{header: users_tx_header[i], first: user_first[i], valid: users_tx[i].valid, last: users_tx[i].last, data: users_tx[i].data};
    assign users_tx_ready[i]        = user_layer_tx_users_ready[i+2];

    //user_packet_lock
    always @(posedge clk) begin
      if(~rst_n) begin
        user_packet_lock[i] <= 0;
      end 
      else begin
        if(~user_packet_lock[i] & users_tx[i].valid & ~users_tx[i].last & users_tx_ready[i]) begin
          user_packet_lock[i] <= 1'b1;
        end
        else if(users_tx[i].valid & users_tx[i].last & users_tx_ready[i]) begin
          user_packet_lock[i] <= 0;
        end
      end
    end

    // RX
    assign users_rx[i]                    = user_layer_rx_users[i+1];
    assign user_layer_rx_users_ready[i+1] = users_rx_ready[i];
  end
endgenerate
//-------------------------------------------//

always @(posedge clk) begin
  if(~rst_n) begin
    controller_packet_lock <= 0;
  end 
  else begin
    if(~controller_packet_lock & controller_tx.valid & controller_tx_ready & ~controller_tx.last) begin
      controller_packet_lock <= 1'b1;
    end
    else if(controller_tx.valid & controller_tx.last & controller_tx_ready) begin
      controller_packet_lock <= 0;
    end
  end
end

// Controller TX
assign controller_packet_first = controller_tx.valid & ~controller_packet_lock;
assign controller_tx_header    = '{dest_addr: controller_tx.address, src_addr: {2'b0, device_id, CONTROLLER_ID}, metadata:controller_tx.metadata};
assign user_layer_tx_users[0]  = '{header: controller_tx_header, first: controller_packet_first, valid: controller_tx.valid, last: controller_tx.last, data: controller_tx.data};
assign controller_tx_ready     = user_layer_tx_users_ready[0];

// Requests Passing through to another device
assign user_layer_tx_users[1]            = network_layer_rx_ext_device;
assign network_layer_rx_ext_device_ready = user_layer_tx_users_ready[1];


// Controller RX
assign controller_rx                = user_layer_rx_users[0];
assign user_layer_rx_users_ready[0] = controller_rx_ready; 
//-------------------------------------------//
UserLayer #( .NUM_USERS(NUM_USERS+2) )
  usrlyr
  (
    .clk                      (clk), 
    .rst_n                    (rst_n),

    .users_tx                 (user_layer_tx_users), 
    .controller_packet        (controller_packet),
    .users_tx_ready           (user_layer_tx_users_ready), 
    .user_packet_error_status (user_packet_error_status),
    .packet_error_detected    (packet_error_detected),
    .wrong_target_user_count  (wrong_target_user_count),

    .layer_tx                 (user_layer_tx), 
		.layer_tx_ready           (user_layer_tx_ready), 
    .user_tx_lines            (user_tx_lines),

    .users_rx                 (user_layer_rx_users), 
    .users_rx_ready           (user_layer_rx_users_ready), 

    .layer_rx                 (user_layer_rx), 
	  .layer_rx_ready           (user_layer_rx_ready)
);

//-------------------------------------------//
//------------ Network Layer ----------------//
//-------------------------------------------//

NetworkLayer netlyr
(
    .clk                     (clk), 
    .rst_n                   (rst_n),

    .device_id               (device_id),
    .network_layer_program_en(network_layer_program_en), 
    .routing_table_word      (routing_table_word),
    .routing_table_word_addr (routing_table_word_addr), 
    .routing_table_program_en(routing_table_program_en),

    .NetSize                 (NetSize), 
    .num_connections_minus_one(num_connections_minus_one), 

    .user_layer_tx           (user_layer_tx), 
    .controller_packet       (controller_packet), 
    .user_layer_tx_ready     (user_layer_tx_ready),

    .net_tx_lines            (net_tx_lines), 

    .layer_tx                (network_layer_tx), 
    .layer_tx_ready          (network_layer_tx_ready),
    .layer_error_status      (network_layer_error_status), 

    .user_layer_rx           (user_layer_rx), 
	  .user_layer_rx_ready     (user_layer_rx_ready), 

    .passing_packet_rx       (network_layer_rx_ext_device), 
    .passing_packet_rx_ready (network_layer_rx_ext_device_ready), 

    .layer_rx                (network_layer_rx), 
    .layer_rx_ready          (network_layer_rx_ready) 
);


//-------------------------------------------//
//------------- Physical Layer --------------//
//-------------------------------------------//


PhysicalLayer  phylyr
(
    .clk                          (clk), 
    .rst_n                        (rst_n),

    .lanes_connection_id          (lanes_connection_id), 
    .lanes_order_id               (lanes_order_id),
    .physical_lane_list           (physical_lane_list), 
    .physical_lane_list_count     (physical_lane_list_count),
    .num_connections_minus_one    (num_connections_minus_one),
    .physical_layer_program_en    (physical_layer_program_en),
    .router_ready                 (network_layer_program_en), 
    .connections_ready            (connections_ready),
    .NetSize                      (NetSize),

    .network_layer_tx             (network_layer_tx), 
    .network_layer_tx_ready       (network_layer_tx_ready), 

    .network_layer_rx             (network_layer_rx), 
    .network_layer_rx_ready       (network_layer_rx_ready), 

  // SerialLite III interface
    .sl_tx_out                    (sl_tx_out),
    .sl_tx_full_in                (sl_tx_full_in),
    .sl_tx_oob_out                (sl_tx_oob_out),
    .sl_tx_oob_full_in            (sl_tx_oob_full_in),

    .sl_rx_in                     (sl_rx_in),
    .sl_rx_grant_out              (sl_rx_grant_out),
    .sl_rx_oob_in                 (sl_rx_oob_in),
    .sl_rx_oob_grant_out          (sl_rx_oob_grant_out), 

    .rx_lane_credits              (rx_lane_credits), 
    .lane_rcvLines                (lane_rcvLines), 
    .tx_lane_credits              (tx_lane_credits), 
    .lane_sentLines               (lane_sentLines), 

    .phy_rx_error_status          (phy_rx_error_status),
    .phy_rx_error_packets_info    (phy_rx_error_packets_info_w)
);


//-------------------------------------------//
//----------- Router Control Unit -----------//
//-------------------------------------------//

controller ctrl(
    .clk                          (clk), 
    .rst_n                        (rst_n),

    // Controller network TX/RX
    .controller_tx                (controller_tx), 
    .controller_tx_ready          (controller_tx_ready), 

    .controller_rx                (controller_rx), 
    .controller_rx_ready          (controller_rx_ready), 

    .connections_ready            (connections_ready),
  
    // Node programming parameters
    .device_id                    (device_id),
    .network_layer_program_en     (network_layer_program_en), 
    .routing_table_word           (routing_table_word),
    .routing_table_word_addr      (routing_table_word_addr), 
    .routing_table_program_en     (routing_table_program_en), 

    .NetworkSize                  (NetSize), 

    .lanes_connection_id          (lanes_connection_id), 
    .lanes_order_id               (lanes_order_id),
    .physical_lane_list           (physical_lane_list), 
    .physical_lane_list_count     (physical_lane_list_count),
    .num_connections_minus_one    (num_connections_minus_one),
    .physical_layer_program_en    (physical_layer_program_en),
    
    // PCIe-Controller Signals
    .controller_pcie_packet_in    (controller_pcie_packet_in),
    .controller_pcie_full_out     (controller_pcie_full_out), 

    .controller_pcie_packet_out   (controller_pcie_packet_out),
    .controller_pcie_grant_in     (controller_pcie_grant_in),

    .stateReg                     (stateReg), 
    .routerConfig_l               (routerConfig_l), 
    .routerConfig_h               (routerConfig_h), 
    .routerTable_l                (routerTable_l), 
    .routerTable_h                (routerTable_h)
);


endmodule