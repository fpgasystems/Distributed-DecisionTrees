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

 /*
     The PCIeShim module multiplexes PCIe traffic between the 
     User logic and the node router module. The traffic to the node router
     includes router configuration parameters and the routing table.
 */
 
import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;


module PCIeShim (
	input  wire                                  clk,    // Clock
	input  wire                                  rst_n,  // Asynchronous reset active low

	// PCIe Slot DMA interface
    input  PCIEPacket                            pcie_packet_in,
    output wire                                  pcie_full_out,

    output PCIEPacket                            pcie_packet_out,
    input  wire                                  pcie_grant_in,

    // PCIe Shim - User Logic Interface
	output PCIEPacket                            user_pcie_packet_in,
    input  wire                                  user_pcie_full_out,

    input  PCIEPacket                            user_pcie_packet_out,
    output wire                                  user_pcie_grant_in,

    output reg  [31:0]                           pcie_user_received_count, 
    output reg  [31:0]                           pcie_user_sent_count,

    // PCIe Shim - Router Node Controller interface
    input  PCIEPacket                            controller_pcie_packet_out,
    output wire                                  controller_pcie_grant_in,

    output PCIEPacket                            controller_pcie_packet_in,
    input  wire                                  controller_pcie_full_out
);


wire                                isManagerPacket;
wire                                isUserData;

wire  [$bits(PCIEPacket) - 2:0]     controller_rx_fifo_dout;
wire                                controller_rx_fifo_valid;
wire                                controller_rx_fifo_full;

wire  [$bits(PCIEPacket) - 2:0]     user_rx_fifo_dout;
wire                                user_rx_fifo_valid;
wire                                user_rx_fifo_full;

wire  [$bits(PCIEPacket) - 2:0]     controller_tx_fifo_dout;
wire                                controller_tx_fifo_valid;
wire                                controller_tx_fifo_full;

wire  [$bits(PCIEPacket) - 2:0]     user_tx_fifo_dout;
wire                                user_tx_fifo_valid;
wire                                user_tx_fifo_full;


//
always@(posedge clk) begin 
    if(~rst_n) begin
        pcie_user_received_count <= 0;
        pcie_user_sent_count     <= 0;
    end
    else begin 
        if(isUserData & ~user_rx_fifo_full) begin
            pcie_user_received_count <= pcie_user_received_count + 1'b1;
        end 
        //
        if(pcie_grant_in & ~controller_tx_fifo_valid & user_tx_fifo_valid) begin
            pcie_user_sent_count <= pcie_user_sent_count + 1'b1;
        end
    end
end
//

assign pcie_full_out   = user_rx_fifo_full | controller_rx_fifo_full;

assign isManagerPacket = pcie_packet_in.valid & (pcie_packet_in.slot == 6'b0);
assign isUserData      = pcie_packet_in.valid & ~(pcie_packet_in.slot == 6'b0);

//---------------------------------- PCIe RX FIFOs -----------------------------------//
// Controller RX FIFO
quick_fifo  #(.FIFO_WIDTH( $bits(PCIEPacket) - 1),        
            .FIFO_DEPTH_BITS(9),
            .FIFO_ALMOSTFULL_THRESHOLD(2**9 -8)
            ) controller_rx_fifo(
        .clk                (clk),
        .reset_n            (rst_n),
        .din                ({pcie_packet_in.slot, pcie_packet_in.pad, pcie_packet_in.last, pcie_packet_in.data}),
        .we                 (isManagerPacket),
        .re                 (~controller_pcie_full_out),
        .dout               (controller_rx_fifo_dout),
        .empty              (),
        .valid              (controller_rx_fifo_valid),
        .full               (controller_rx_fifo_full),
        .count              (),
        .almostfull         ()
    );



// User RX FIFO
quick_fifo  #(.FIFO_WIDTH( $bits(PCIEPacket) - 1),        
            .FIFO_DEPTH_BITS(9),
            .FIFO_ALMOSTFULL_THRESHOLD(2**9 -8)
            ) user_rx_fifo(
        .clk                (clk),
        .reset_n            (rst_n),
        .din                ({(pcie_packet_in.slot - 16'd1), pcie_packet_in.pad, pcie_packet_in.last, pcie_packet_in.data}),
        .we                 (isUserData),
        .re                 (~user_pcie_full_out),
        .dout               (user_rx_fifo_dout),
        .empty              (),
        .valid              (user_rx_fifo_valid),
        .full               (user_rx_fifo_full),
        .count              (),
        .almostfull         ()
    );

//--------------------------------- PCIe TX FIFOs --------------------------------------//
// Controller TX FIFO
quick_fifo  #(.FIFO_WIDTH( $bits(PCIEPacket) - 1),        
            .FIFO_DEPTH_BITS(9),
            .FIFO_ALMOSTFULL_THRESHOLD(2**9 -8)
            ) controller_tx_fifo(
        .clk                (clk),
        .reset_n            (rst_n),
        .din                ({controller_pcie_packet_out.slot, controller_pcie_packet_out.pad, controller_pcie_packet_out.last, controller_pcie_packet_out.data}),
        .we                 (controller_pcie_packet_out.valid),
        .re                 (pcie_grant_in),
        .dout               (controller_tx_fifo_dout),
        .empty              (),
        .valid              (controller_tx_fifo_valid),
        .full               (controller_tx_fifo_full),
        .count              (),
        .almostfull         ()
    );

// User TX FIFO
quick_fifo  #(.FIFO_WIDTH( $bits(PCIEPacket) - 1),        
            .FIFO_DEPTH_BITS(9),
            .FIFO_ALMOSTFULL_THRESHOLD(2**9 -8)
            ) user_tx_fifo(
        .clk                (clk),
        .reset_n            (rst_n),
        .din                ({user_pcie_packet_out.slot+16'd1, user_pcie_packet_out.pad, user_pcie_packet_out.last, user_pcie_packet_out.data}),
        .we                 (user_pcie_packet_out.valid),
        .re                 (pcie_grant_in & ~controller_tx_fifo_valid),
        .dout               (user_tx_fifo_dout),
        .empty              (),
        .valid              (user_tx_fifo_valid),
        .full               (user_tx_fifo_full),
        .count              (),
        .almostfull         ()
    );

//------------------------------ Round Robin PCIe TX --------------------------------//

always@(*) begin 
    if(controller_tx_fifo_valid) begin   // pass controller TX
        pcie_packet_out = '{last:controller_tx_fifo_dout[128], valid: controller_tx_fifo_valid, pad: controller_tx_fifo_dout[132:129], slot: controller_tx_fifo_dout[148:133], data:controller_tx_fifo_dout[127:0]};
    end
    else begin                // pass user
       pcie_packet_out = '{last:user_tx_fifo_dout[128], valid: user_tx_fifo_valid, pad: user_tx_fifo_dout[132:129], slot: user_tx_fifo_dout[148:133], data:user_tx_fifo_dout[127:0]};
    end
end
 

//------------------------------ User Interface ----------------------------------//
// pcie_in
assign user_pcie_packet_in = '{last:user_rx_fifo_dout[128], valid: user_rx_fifo_valid, pad: user_rx_fifo_dout[132:129], slot: user_rx_fifo_dout[148:133], data:user_rx_fifo_dout[127:0]};

// pcie_out
assign user_pcie_grant_in  = ~user_tx_fifo_full;

//----------------------------------- Manager Interface -------------------------------------//
// pcie_in
assign controller_pcie_packet_in = '{last:controller_rx_fifo_dout[128], valid: controller_rx_fifo_valid, pad: controller_rx_fifo_dout[132:129], slot: controller_rx_fifo_dout[148:133], data:controller_rx_fifo_dout[127:0]};

// pcie_out
assign controller_pcie_grant_in  = ~controller_tx_fifo_full;


endmodule