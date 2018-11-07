// Copyright (c) 2013-2015, Intel Corporation
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of source code must retain the above copyright notice,
// this list of conditions and the following disclaimer.
// * Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
// * Neither the name of Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

import NetTypes::*;

module routing_table(
    input  wire                                                   clk,
    input  wire                                                   we,
    input  wire                                                   re, 
    input  wire [ROUTING_TABLE_SIZE_BITS-1:0]                     raddr,
    input  wire [ROUTING_TABLE_WORD_BITS-1:0]                     waddr,
    input  wire [ROUTING_TABLE_WORD_WIDTH-1:0]                    din,
    output reg  [CONN_ID_WIDTH-1:0]                               dout,
    output reg                                                    valid
);



localparam NUM_WORDS = 2**ROUTING_TABLE_WORD_BITS;

`ifdef VENDOR_XILINX
    (* ram_extract = "yes", ram_style = "block" *)
    reg  [ROUTING_TABLE_WORD_WIDTH-1:0]         mem[0:NUM_WORDS-1];
`else
(* ramstyle = "no_rw_check" *) reg  [ROUTING_TABLE_WORD_WIDTH-1:0] mem[0:NUM_WORDS-1];
`endif

reg  [RT_WORD_CONN_BITS-1:0]              entry_addr;
reg  [ROUTING_TABLE_WORD_WIDTH-1:0]       dout_wd;
wire [CONN_ID_WIDTH-1:0]                  word_entries[0:NUM_CONN_ID_PER_RT_WORD-1];

genvar i;

    always @(posedge clk) begin

        // write port 
        if (we)
            mem[ waddr ] <= din;
        
        // read port 
        dout_wd    <= mem[ raddr[ROUTING_TABLE_SIZE_BITS-1: RT_WORD_CONN_BITS] ];
        valid      <= re;

        entry_addr <= raddr[RT_WORD_CONN_BITS-1:0];
    end

    generate for (i = 0; i < NUM_CONN_ID_PER_RT_WORD; i=i+1) begin: selectEntry
        assign word_entries[i] = dout_wd[(i+1)*CONN_ID_WIDTH-1:i*CONN_ID_WIDTH];
    end
    endgenerate

    assign dout = word_entries[ entry_addr ];

			
endmodule

