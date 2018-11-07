
import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;
/**/

module PacketFIFO (
	input   wire                                         clk,    // Clock
	input   wire                                         rst_n,  // Asynchronous reset active low

	input   PacketWord                                   pfifo_in,
	output  wire                                         pfifo_in_ready, 

	output  PacketWord                                   pfifo_out,
	input   wire                                         pfifo_out_ready, 

    output  wire  [31:0]                                 pfifo_error_status, 
    output  wire                                         packet_error_detected 
);

reg   [10:0]                         pfifo_packets_count;
PacketWord                           pfifo_dout;
wire                                 pfifo_valid;
wire                                 pfifo_full;


reg   [9:0]                          cntrl_cnt;
wire  [9:0]                          next_cntrl_cnt;
wire                                 p_cntrl_fifo_valid;
wire                                 p_cntrl_fifo_re;
wire                                 p_cntrl_fifo_we;
wire                                 p_fifo_re;
wire                                 p_ctnrl_discard;
wire  [9:0]                          p_ctnrl_size;
reg                                  pfifo_in_first;

reg                                  packet_discard_set;
wire                                 packet_discard;

reg                                  error_source_changed;
reg                                  error_destination_changed;
reg                                  error_first_again;
reg                                  error_first_miss;

reg   [9:0]                          next_packet_size;
reg   [9:0]                          packet_size;
reg   [9:0]                          error_at_line;


wire  [$bits(PacketWord)-1:0]        p_fifo_in;
wire  [$bits(PacketWord)-1:0]        p_fifo_dout;


reg   [7:0]                 error_destination_changed_count;
reg   [7:0]                 error_source_changed_count;
reg   [7:0]                 error_first_again_count;
reg   [7:0]                 error_first_miss_count;

reg                         rcv_packet_set;
PacketHeader                curr_header;

assign pfifo_error_status    = {error_first_miss_count, error_at_line[7:0], error_source_changed_count, error_destination_changed_count};

assign packet_error_detected = packet_discard_set | packet_discard;
assign pfifo_in_ready        = ~pfifo_full | packet_discard_set | packet_discard;
//-------------------------------------------------------//
always@(*)begin 
    error_source_changed      = 1'b0;
    error_destination_changed = 1'b0;
    error_first_again         = 1'b0;
    error_first_miss          = 1'b0;
    pfifo_in_first            = pfifo_in.first;
    next_packet_size          = packet_size;

    if(pfifo_in.valid) begin
        if(rcv_packet_set) begin   // This means we are in the middle of receiving a packet, incoming header should be the same
            if(!(curr_header.src_addr == pfifo_in.header.src_addr)) begin
                error_source_changed = 1'b1;
            end
            if(!(curr_header.dest_addr == pfifo_in.header.dest_addr)) begin
                error_destination_changed = 1'b1;
            end
            if(pfifo_in.first) begin
                error_first_again = 1'b1;
                pfifo_in_first    = 1'b0;
            end
        end
        else if(~pfifo_in.first) begin
            error_first_miss = 1'b1;

            pfifo_in_first   = 1'b1;
        end
        //
        next_packet_size = packet_size;
        if((~packet_discard | ~packet_discard_set)) begin
            next_packet_size = packet_size + 10'd1;
        end
    end
end


always@(posedge clk) begin
    if(~rst_n) begin
        curr_header               <= '{src_addr:16'b0, dest_addr:16'b0, metadata:0};
        rcv_packet_set            <= 1'b0;
        packet_size               <= 0;
        packet_discard_set        <= 1'b0;

        error_destination_changed_count <= 8'b0;
        error_source_changed_count      <= 8'b0;
        error_first_again_count         <= 8'b0;
        error_first_miss_count          <= 8'b0;

        error_at_line <= 0;
    end 
    else begin
        if(pfifo_in.valid & ~pfifo_full) begin
            if(~pfifo_in.last) begin
                rcv_packet_set <= 1'b1;
                curr_header    <= pfifo_in.header;
                packet_size    <= next_packet_size;
            end
            else begin 
                rcv_packet_set <= 1'b0;
                packet_size    <= 0;
                curr_header    <= '{src_addr:16'b0, dest_addr:16'b0, metadata:0};
            end
        end
        //
        if(error_destination_changed && (error_at_line == 10'b0)) begin
            error_at_line <= packet_size;
        end
        //
        if(packet_discard & ~pfifo_in.last) begin
            packet_discard_set <= 1'b1;
        end
        else if(pfifo_in.valid & pfifo_in.last) begin
            packet_discard_set <= 1'b0;
        end
        // error counters
        if(error_source_changed && !(error_source_changed_count == 8'hFF)) begin
            error_source_changed_count <= error_source_changed_count + 1'b1;
        end
        if(error_destination_changed && !(error_destination_changed_count == 8'hFF)) begin
            error_destination_changed_count <= error_destination_changed_count + 1'b1;
        end
        if(error_first_again && !(error_first_again_count == 8'hFF)) begin
            error_first_again_count <= error_first_again_count + 1'b1;
        end
        if(error_first_miss && !(error_first_miss_count == 8'hFF)) begin
            error_first_miss_count <= error_first_miss_count + 1'b1;
        end
    end
end

assign packet_discard = error_source_changed | error_destination_changed;

assign p_cntrl_fifo_we = (packet_discard | (pfifo_in.valid & pfifo_in.last & ~pfifo_full)) & ~packet_discard_set;
//-------------------------------------------------------//
quick_fifo  #(.FIFO_WIDTH( 11),        
            .FIFO_DEPTH_BITS(9),
            .FIFO_ALMOSTFULL_THRESHOLD(2**9 -2)
            ) p_cntrl_fifo(
        .clk                (clk),
        .reset_n            (rst_n),
        .din                ({packet_discard, next_packet_size}),
        .we                 (p_cntrl_fifo_we),
        .re                 (p_cntrl_fifo_re),
        .dout               ({p_ctnrl_discard, p_ctnrl_size}),
        .empty              (),
        .valid              (p_cntrl_fifo_valid),
        .full               (),
        .count              (),
        .almostfull         ()
    );
//-------------------------------------------------------//
assign p_cntrl_fifo_re = (p_cntrl_fifo_valid & (next_cntrl_cnt == p_ctnrl_size))? (p_ctnrl_discard | pfifo_out_ready) : 1'b0;
assign p_fifo_re       = (p_cntrl_fifo_valid)? (p_ctnrl_discard | pfifo_out_ready) : 1'b0;
assign next_cntrl_cnt  = cntrl_cnt + 10'd1;

always@(posedge clk) begin
    if(~rst_n) begin
        cntrl_cnt <= 0;
    end 
    else begin
        if(p_fifo_re) begin
            if(next_cntrl_cnt == p_ctnrl_size) begin 
                cntrl_cnt <= 0;
            end 
            else begin 
                cntrl_cnt <= next_cntrl_cnt;
            end
        end
    end
end

//-------------------------------------------------------//

quick_fifo  #(.FIFO_WIDTH( $bits(PacketWord)),        
            .FIFO_DEPTH_BITS(9),
            .FIFO_ALMOSTFULL_THRESHOLD(2**9 -8)
            ) p_fifo(
        .clk                (clk),
        .reset_n            (rst_n),
        .din                (p_fifo_in),
        .we                 (pfifo_in.valid & ~packet_discard & ~packet_discard_set),
        .re                 (p_fifo_re),
        .dout               (p_fifo_dout),
        .empty              (),
        .valid              (pfifo_valid),
        .full               (pfifo_full),
        .count              (),
        .almostfull         ()
    );


assign p_fifo_in  = {pfifo_in.data, pfifo_in.last, pfifo_in.valid, pfifo_in.first, pfifo_in.header.src_addr, pfifo_in.header.dest_addr, pfifo_in.header.metadata};
assign pfifo_dout = '{data:p_fifo_dout[$bits(PacketWord)-1:3*NET_ADDRESS_WIDTH+3], 
                      last:p_fifo_dout[3*NET_ADDRESS_WIDTH+2], 
                      valid:p_fifo_dout[3*NET_ADDRESS_WIDTH+1], 
                      first:p_fifo_dout[3*NET_ADDRESS_WIDTH], 
                      header:'{src_addr: p_fifo_dout[3*NET_ADDRESS_WIDTH-1:2*NET_ADDRESS_WIDTH],
                               dest_addr:p_fifo_dout[2*NET_ADDRESS_WIDTH-1:NET_ADDRESS_WIDTH], 
                               metadata:p_fifo_dout[NET_ADDRESS_WIDTH-1:0]}
                     };

assign pfifo_out.data   = pfifo_dout.data;
assign pfifo_out.last   = pfifo_dout.last;
assign pfifo_out.valid  = p_cntrl_fifo_valid & ~p_ctnrl_discard;
assign pfifo_out.first  = pfifo_dout.first;
assign pfifo_out.header = pfifo_dout.header;

//-------------------------------------------------------//

endmodule