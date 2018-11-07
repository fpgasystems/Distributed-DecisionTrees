/*
Name: SimpleRole.sv
Description: SL3 loopback test. Sends data from PCIe through SL3 to another machine.

Copyright (c) Microsoft Corporation
 
All rights reserved. 
 
MIT License
 
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated 
documentation files (the ""Software""), to deal in the Software without restriction, including without limitation 
the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and 
to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 
The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 
THE SOFTWARE IS PROVIDED *AS IS*, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE 
WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR 
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, 
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/
 

import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;


module SimpleRole
(
    // User clock and reset
    input                               clk,
    input                               rst, 

    // Simplified Memory interface
    output MemReq                       mem_reqs        [1:0],
    input                               mem_req_grants  [1:0],
    input  MemResp                      mem_resps       [1:0],
    output                              mem_resp_grants [1:0],

    // PCIe Slot DMA interface
    input PCIEPacket                    pcie_packet_in,
    output                              pcie_full_out,

    output PCIEPacket                   pcie_packet_out,
    input                               pcie_grant_in,

    // Soft register interface
    input SoftRegReq                    softreg_req,
    output SoftRegResp                  softreg_resp,
    
    // SerialLite III interface
    output SL3DataInterface             sl_tx_out           [3:0],
    input                               sl_tx_full_in       [3:0],
    output SL3OOBInterface              sl_tx_oob_out       [3:0],
    input                               sl_tx_oob_full_in   [3:0],

    input SL3DataInterface              sl_rx_in            [3:0],
    output                              sl_rx_grant_out     [3:0],
    input SL3OOBInterface               sl_rx_oob_in        [3:0],
    output                              sl_rx_oob_grant_out [3:0]
);


localparam  NUM_USERS = 1;


//
UserPacketWord                  users_tx[NUM_USERS-1:0]; 
wire                            users_tx_ready[NUM_USERS-1:0];

UserPacketWord                  users_rx[NUM_USERS-1:0]; 
wire                            users_rx_ready[NUM_USERS-1:0]; 

UserPacketWord                  user_network_tx; 
wire                            user_network_tx_ready;

UserPacketWord                  user_network_rx;
wire                            user_network_rx_ready;

PCIEPacket                      user_pcie_packet_in;
wire                            user_pcie_full_out;

PCIEPacket                      user_pcie_packet_out;
wire                            user_pcie_grant_in;

PCIEPacket                      controller_pcie_packet_in;
wire                            controller_pcie_full_out;

PCIEPacket                      controller_pcie_packet_out;
wire                            controller_pcie_grant_in;

wire  [63:0]                    stateReg;
wire  [63:0]                    routerConfig_l;
wire  [63:0]                    routerConfig_h; 
wire  [63:0]                    routerTable_l;
wire  [63:0]                    routerTable_h;

SoftRegReq                      user_softreg_req;
SoftRegResp                     user_softreg_resp;

wire  [63:0]                    rx_lane_regs[NUM_SL3_LANES-1:0];
wire  [63:0]                    tx_lane_regs[NUM_SL3_LANES-1:0];

wire  [63:0]                    error_status_1; 
wire  [63:0]                    error_status_2;
wire  [63:0]                    error_status_3;

wire  [63:0]                    tx_line_count;

wire  [31:0]                             pcie_user_received_count;
wire  [31:0]                             pcie_user_sent_count;

wire [63:0]                     appStatus[5:0];
//
// Instantiate ManagerSoftRegs

ManagerSoftRegs softRegs 
(
    .clk                          (clk),    // Clock
    .rst_n                        (~rst),  // Asynchronous reset active low

    .softreg_req                  (softreg_req),
    .softreg_resp                 (softreg_resp),

    .user_softreg_req             (user_softreg_req),
    .user_softreg_resp            (user_softreg_resp),

    // Router Regs
    .stateReg                     (stateReg), 
    .routerConfig_l               (routerConfig_l), 
    .routerConfig_h               (routerConfig_h), 
    .routerTable_l                (routerTable_l), 
    .routerTable_h                (routerTable_h),

    .rx_lane_regs                 (rx_lane_regs),
    .tx_lane_regs                 (tx_lane_regs), 
    .error_status_1               (error_status_1), 
    .error_status_2               (error_status_2), 
    .error_status_3               (error_status_3),
    .tx_line_count                (tx_line_count),
    // PCIeShim Regs
    .pcie_user_received_count     (pcie_user_received_count),
    .pcie_user_sent_count         (pcie_user_sent_count), 

    // app status counters
    .appStatus                    (appStatus)
);

// Instantiate PCIeShim
PCIeShim pcie_shim
(
    .clk                          (clk),    // Clock
    .rst_n                        (~rst),  // Asynchronous reset active low

    // PCIe Slot DMA interface
    .pcie_packet_in               (pcie_packet_in),
    .pcie_full_out                (pcie_full_out),

    .pcie_packet_out              (pcie_packet_out),
    .pcie_grant_in                (pcie_grant_in),

    // PCIe Shim - User Logic Interface
    .user_pcie_packet_in          (user_pcie_packet_in),
    .user_pcie_full_out           (user_pcie_full_out),

    .user_pcie_packet_out         (user_pcie_packet_out),
    .user_pcie_grant_in           (user_pcie_grant_in),

    .pcie_user_received_count     (pcie_user_received_count),
    .pcie_user_sent_count         (pcie_user_sent_count),

    .controller_pcie_packet_in    (controller_pcie_packet_in),
    .controller_pcie_full_out     (controller_pcie_full_out), 

    .controller_pcie_packet_out   (controller_pcie_packet_out),
    .controller_pcie_grant_in     (controller_pcie_grant_in)
);

// Instantiate Router Node
node_router #(.NUM_USERS(NUM_USERS) ) 
Router
(
    .clk                          (clk),    // Clock
    .rst_n                        (~rst),  // Asynchronous reset active low
    // PCIe - controller I/O
    .controller_pcie_packet_in    (controller_pcie_packet_in),
    .controller_pcie_full_out     (controller_pcie_full_out),

    .controller_pcie_packet_out   (controller_pcie_packet_out),
    .controller_pcie_grant_in     (controller_pcie_grant_in),

    .stateReg                     (stateReg), 
    .routerConfig_l               (routerConfig_l), 
    .routerConfig_h               (routerConfig_h), 
    .routerTable_l                (routerTable_l), 
    .routerTable_h                (routerTable_h),
    // Physical Layer inputs /outputs
    .sl_tx_out                    (sl_tx_out),
    .sl_tx_full_in                (sl_tx_full_in),
    .sl_tx_oob_out                (sl_tx_oob_out),
    .sl_tx_oob_full_in            (sl_tx_oob_full_in),

    .sl_rx_in                     (sl_rx_in),
    .sl_rx_grant_out              (sl_rx_grant_out),
    .sl_rx_oob_in                 (sl_rx_oob_in),
    .sl_rx_oob_grant_out          (sl_rx_oob_grant_out), 

    // User Layer inputs/outputs
    .users_tx                     (users_tx), 
    .users_tx_ready               (users_tx_ready),

    .users_rx                     (users_rx), 
    .users_rx_ready               (users_rx_ready), 

    .rx_lane_regs                 (rx_lane_regs),
    .tx_lane_regs                 (tx_lane_regs), 
    .error_status_1               (error_status_1), 
    .error_status_2               (error_status_2),
    .error_status_3               (error_status_3), 
    .tx_line_count                (tx_line_count)
);

//
assign users_tx[0]           = user_network_tx;
assign user_network_tx_ready = users_tx_ready[0];

assign user_network_rx       = users_rx[0];
assign users_rx_ready[0]     = user_network_rx_ready;

// Instantiate UserLogic
App userLogic(
    .clk                          (clk),    // Clock
    .rst_n                        (~rst),  // Asynchronous reset active low

    // Simplified Memory interface
    .mem_reqs                     (mem_reqs),
    .mem_req_grants               (mem_req_grants),
    .mem_resps                    (mem_resps),
    .mem_resp_grants              (mem_resp_grants),

    .appStatus                    (appStatus),

    // PCIe Slot DMA interface
    .pcie_packet_in               (user_pcie_packet_in),
    .pcie_full_out                (user_pcie_full_out),

    .pcie_packet_out              (user_pcie_packet_out),
    .pcie_grant_in                (user_pcie_grant_in),

    // Soft register interface
    .softreg_req                  (user_softreg_req),
    .softreg_resp                 (user_softreg_resp),

    // User Layer inputs/outputs
    .user_network_tx              (user_network_tx), 
    .user_network_tx_ready        (user_network_tx_ready), 

    .user_network_rx              (user_network_rx), 
    .user_network_rx_ready        (user_network_rx_ready)
);






endmodule
