
import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;

module lane_rx_unit (
	input  wire                                         clk,    // Clock
	input  wire                                         rst_n,  // Asynchronous reset active low
	input  wire  [CONN_ID_WIDTH-1:0]                    lane_connection_id,
	input  wire  [CONN_ID_WIDTH-1:0]                    lane_order_id,
	input  wire                                         rx_programmed,

	input  wire  [CONN_ID_WIDTH-1:0]                    curr_conn_id,
	input  wire  [CONN_ID_WIDTH-1:0]                    curr_lane_id,

	output SL3DataInterface                             lane_rx, 
	input  wire                                         lane_rx_ready, 

	input  SL3DataInterface                             sl_rx_in,
    output wire                                         sl_rx_grant_out,
    output SL3OOBInterface                              sl_tx_oob_out,
    input  wire                                         sl_tx_oob_full_in, 

    output reg   [14:0]                                 credits,
    output wire  [48:0]                                 rcvLines
);



wire  									lane_granted_access;
reg  									add_credit_valid;
reg 									credit_to_return_valid;
reg   [14:0]                            next_recvCounter;
reg   [14:0]                            next_recvCounter_d1;
reg   [14:0]                            recvCounter;
reg   [14:0]                            return_credit;

wire 									rx_fifo_valid;
wire 									rx_fifo_full;
wire  [USER_DATA_BUS_WIDTH:0]           rx_fifo_dout;
wire                                    rx_fifo_empty;

// lane debug regs

reg   [15:0]                                 rcvLines_d;
reg   [15:0]                                 rcvLines_l;
reg   [15:0]                                 back_pressure_rx;

assign rcvLines = {rx_fifo_empty, back_pressure_rx, rcvLines_l, rcvLines_d};
//
always@(posedge clk) begin 
    if(~rst_n) begin 
        credits     <= 0;
        rcvLines_d  <= 0;
        rcvLines_l  <= 0;
        back_pressure_rx <= 0;
    end
    else begin 
        credits <=  next_recvCounter;

        if(sl_rx_in.valid && sl_rx_grant_out) begin
            rcvLines_d  <= rcvLines_d + 1'b1;
        end
        if(sl_rx_in.valid && sl_rx_grant_out && sl_rx_in.last) begin
            rcvLines_l  <= rcvLines_l + 1'b1;
        end

        if(rx_fifo_full && !(back_pressure_rx == 16'hFFFF)) begin
           back_pressure_rx <= back_pressure_rx + 1'b1;
        end
    end
end

// lane_out_fifo
quick_fifo  #(.FIFO_WIDTH( USER_DATA_BUS_WIDTH + 1 ),        
            .FIFO_DEPTH_BITS(9),
            .FIFO_ALMOSTFULL_THRESHOLD(2**9 -8)
            ) rx_fifo(
        .clk                (clk),
        .reset_n            (rst_n),
        .din                ({sl_rx_in.data, sl_rx_in.last}),
        .we                 (sl_rx_in.valid),
        .re                 (lane_rx_ready && lane_granted_access),
        .dout               (rx_fifo_dout),
        .empty              (rx_fifo_empty),
        .valid              (rx_fifo_valid),
        .full               (rx_fifo_full),
        .count              (),
        .almostfull         ()
    );


assign sl_rx_grant_out = sl_rx_in.valid && ~rx_fifo_full;

assign lane_rx.data   = rx_fifo_dout[USER_DATA_BUS_WIDTH:1];
assign lane_rx.last   = rx_fifo_dout[0];
assign lane_rx.valid  = rx_fifo_valid && lane_granted_access;

assign lane_granted_access = ((lane_connection_id == curr_conn_id) & (lane_order_id == curr_lane_id)) | ~rx_programmed;


// Send Credit
always@(*) begin 
	add_credit_valid    = 1'b0;
	next_recvCounter = recvCounter;

	if(rx_fifo_valid & lane_granted_access & lane_rx_ready) begin
		next_recvCounter = recvCounter + 15'd1;

		if(rx_fifo_dout[0]) begin
        	// Return credits through TX OOB channel 
        	add_credit_valid = 1'b1;
        	next_recvCounter = 0;      
    	end
	end 
end

always@(posedge clk) begin 
	if(~rst_n) begin
		return_credit          <= 0;
		credit_to_return_valid <= 0;
		recvCounter            <= 0;
        next_recvCounter_d1    <= 0;
	end
	else begin 
		recvCounter            <= next_recvCounter;

        next_recvCounter_d1    <= next_recvCounter;

		if(~sl_tx_oob_full_in | ~credit_to_return_valid) begin 
			return_credit          <= (next_recvCounter_d1 + 1'b1);
			credit_to_return_valid <= add_credit_valid;
		end
		else if(credit_to_return_valid & add_credit_valid) begin
			return_credit <= return_credit + (next_recvCounter_d1 + 1'b1);
		end
	end
end

assign sl_tx_oob_out = '{valid: credit_to_return_valid, data: return_credit};


endmodule