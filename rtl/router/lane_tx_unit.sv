

import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;


module lane_tx_unit (
	input  wire                                         clk,    // Clock
	input  wire                                         rst_n,  // Asynchronous reset active low
	
	input  PacketWord                                   network_layer_tx_packet, 
	input  wire                                         network_layer_tx_packet_valid, 
	output wire                                         lane_ready, 

	output SL3DataInterface                             sl_tx_out,
    input wire                                          sl_tx_full_in,
    input  SL3OOBInterface                              sl_rx_oob_in,
    output reg                                          sl_rx_oob_grant_out,

    output reg   [11:0]                                 credits,
    output wire  [47:0]                                 sentLines
);

wire                            in_fifo_valid;
wire                            in_fifo_re;
wire                            in_fifo_almfull;

PacketWord                      in_fifo_dout;

wire                            header_valid;
wire                            header_last;
wire  [PHIT_WIDTH-1:0]          header_data;

reg                             header_set;
reg                             tx_packet_valid;
reg                             tx_packet_last;
reg   [PHIT_WIDTH-1:0]          tx_packet_data;

wire                            payload_valid;
wire                            payload_last;
wire  [PHIT_WIDTH-1:0]          payload_data;


wire                            out_fifo_almfull;
wire                            out_fifo_valid;
reg                             out_fifo_re;
wire  [PHIT_WIDTH:0]            out_fifo_dout;

reg   [11:0]                    sendCredits;
reg   [11:0]                    next_sendCredits;
// lane debug regs

reg   [15:0]                                 sentLines_d;
reg   [15:0]                                 sentLines_l;
reg   [15:0]                                 back_pressure_tx;

assign sentLines = {back_pressure_tx, sentLines_l, sentLines_d};
//
always@(posedge clk) begin 
    if(~rst_n) begin 
        credits    <= 0;
        sentLines_d  <= 0;
        sentLines_l  <= 0;

        back_pressure_tx <= 0;
    end
    else begin 
        credits <=  next_sendCredits;

        if(sl_tx_out.valid & ~sl_tx_full_in) begin
            sentLines_d  <= sentLines_d + 8'd1;
        end

        if(sl_tx_out.valid & sl_tx_out.last & ~sl_tx_full_in) begin
            sentLines_l  <= sentLines_l + 8'd1;
        end

        if(sl_tx_full_in && !(back_pressure_tx == 16'hFFFF)) begin
           back_pressure_tx <= back_pressure_tx + 1'b1;
        end
    end
end
//-----------------------------------------------------------------//
//------------------------- Input  FIFO ---------------------------//
//-----------------------------------------------------------------//
// 
quick_fifo  #(.FIFO_WIDTH( $bits(PacketWord)),        
            .FIFO_DEPTH_BITS(9),
            .FIFO_ALMOSTFULL_THRESHOLD(504)
            ) in_fifo(
        .clk                (clk),
        .reset_n            (rst_n),
        .din                (network_layer_tx_packet),
        .we                 (network_layer_tx_packet_valid),
        .re                 (in_fifo_re),
        .dout               (in_fifo_dout),
        .empty              (),
        .valid              (in_fifo_valid),
        .full               (),
        .count              (),
        .almostfull         (in_fifo_almfull)
    );

assign lane_ready = ~in_fifo_almfull;

//-----------------------------------------------------------------//
//-------------------- Multiplex Packet Parts  --------------------//
//-----------------------------------------------------------------//
assign header_valid  = in_fifo_valid & in_fifo_dout.first;
assign header_last   = 1'b0;
assign header_data   = {{(PHIT_WIDTH-48){1'b0}}, in_fifo_dout.header};

assign payload_valid = in_fifo_valid;
assign payload_last  = in_fifo_dout.last;
assign payload_data  = in_fifo_dout.data;


always@(posedge clk) begin 
	if(~rst_n) begin 
		tx_packet_valid <= 0;
        tx_packet_last  <= 0;
        tx_packet_data  <= 0;

        header_set      <= 0;
	end
	else begin 
        tx_packet_valid <=  ((header_valid & ~header_set)? 1'b1 : payload_valid) & ~out_fifo_almfull;
        tx_packet_last  <=  (header_valid & ~header_set)? header_last   : payload_last;
        tx_packet_data  <=  (header_valid & ~header_set)? header_data   : payload_data;

        header_set      <= 0;

        if(~out_fifo_almfull) begin 
            header_set <= header_valid & ~header_set;
        end
	end
end


assign in_fifo_re = ~out_fifo_almfull & ~(header_valid & ~header_set);
//-----------------------------------------------------------------//
//------------------------- Output FIFO ---------------------------//
//-----------------------------------------------------------------//

quick_fifo  #(.FIFO_WIDTH( PHIT_WIDTH + 1 ),        
            .FIFO_DEPTH_BITS(9),
            .FIFO_ALMOSTFULL_THRESHOLD(2**9 -8)
            ) out_fifo(
        .clk                (clk),
        .reset_n            (rst_n),
        .din                ({tx_packet_last, tx_packet_data}),
        .we                 (tx_packet_valid),
        .re                 (out_fifo_re),
        .dout               (out_fifo_dout),
        .empty              (),
        .valid              (out_fifo_valid),
        .full               (),
        .count              (),
        .almostfull         (out_fifo_almfull)
    );

//-----------------------------------------------------------------//
//----------------------- Output Credits --------------------------//
//-----------------------------------------------------------------//

always@(posedge clk) begin
    if(~rst_n) begin
        sendCredits <= INIT_CREDITS;
    end
    else begin
        sendCredits <= next_sendCredits;
    end
end

always@(*) begin 
	sl_tx_out           = '{valid: 1'b0, data: 128'b0, last: 1'b0};
	out_fifo_re         = 1'b0;
	next_sendCredits    = sendCredits;
	sl_rx_oob_grant_out = 1'b0;

	if(out_fifo_valid && !sl_tx_full_in && (sendCredits > 0)) begin
		sl_tx_out        = '{valid: 1'b1, data: out_fifo_dout[PHIT_WIDTH-1:0], last: out_fifo_dout[PHIT_WIDTH]};
		out_fifo_re      = 1'b1;

        next_sendCredits = sendCredits - 32'd1;
	end

	// Increment credits
    if(sl_rx_oob_in.valid) begin
        next_sendCredits = next_sendCredits + sl_rx_oob_in.data;
        sl_rx_oob_grant_out = 1'b1;
    end
end





endmodule