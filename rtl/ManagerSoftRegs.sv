
import ShellTypes::*;
import SL3Types::*;
import NetTypes::*;
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
 
module ManagerSoftRegs (
	input  wire                                  clk,    // Clock
	input  wire                                  rst_n,  // Asynchronous reset active low


	input  SoftRegReq                             softreg_req,
    output SoftRegResp                            softreg_resp,

    output SoftRegReq                             user_softreg_req,
    input  SoftRegResp                            user_softreg_resp,

    // router
    input  wire  [63:0]                    		  stateReg, 
    input  wire  [63:0]                    		  routerConfig_l, 
    input  wire  [63:0]                    		  routerConfig_h, 
    input  wire  [63:0]                    		  routerTable_l, 
    input  wire  [63:0]                    		  routerTable_h, 

    input  wire  [63:0]                           rx_lane_regs[NUM_SL3_LANES-1:0],
    input  wire  [63:0]                           tx_lane_regs[NUM_SL3_LANES-1:0], 
    input  wire  [63:0]                           error_status_1, 
    input  wire  [63:0]                           error_status_2,
    input  wire  [63:0]                           error_status_3,
    input  wire  [63:0]                           tx_line_count,
    // PCIE Shim
    input  wire  [31:0]                           pcie_user_received_count, 
    input  wire  [31:0]                           pcie_user_sent_count, 

    input  wire [63:0]                            appStatus[5:0]
	
);

reg   wait_user_resp;
// Write SoftRegs FSM

always@(posedge clk) begin 
	if(~rst_n) begin
		user_softreg_req <= '{valid:1'b0, isWrite:1'b0, addr:32'b0, data:64'b0};
	end
	else begin 
		user_softreg_req <= '{valid:1'b0, isWrite:softreg_req.isWrite, addr:softreg_req.addr, data:softreg_req.data};
		if(softreg_req.valid && (softreg_req.addr >= 200)) begin
			user_softreg_req.valid <= 1'b1;
		end 
		else if(softreg_req.valid && softreg_req.isWrite) begin 
			/*case(softreg_req.addr)
            	100: 
            	110: 
            	120: 
            	130: 
            	140: 
        	endcase*/
		end
	end 
end

// Read SoftRegs FSM
always@(posedge clk) begin 
	if(~rst_n) begin
		softreg_resp   <= '{valid:1'b0, data:64'b0};
		wait_user_resp <= 1'b0;
	end
	else begin 
		// if we pass a read request for the user  set a flag to wait for response.
		if(user_softreg_req.valid && ~user_softreg_req.isWrite) begin
			wait_user_resp <= 1'b1;
		end

		// send response
		if(wait_user_resp) begin
			softreg_resp <= '{valid: user_softreg_resp.valid, data:user_softreg_resp.data};
			if(user_softreg_resp.valid) begin
				wait_user_resp <= 1'b0;
			end
		end
		else if(softreg_req.valid && ~softreg_req.isWrite && !(softreg_req.addr >= 200)) begin
			softreg_resp.valid <= 1'b1;
			case(softreg_req.addr)
            	100: softreg_resp.data <= stateReg;
            	110: softreg_resp.data <= routerConfig_l;
           		120: softreg_resp.data <= routerConfig_h;
           		130: softreg_resp.data <= routerTable_l;
           		140: softreg_resp.data <= routerTable_h;
           		150: softreg_resp.data <= tx_lane_regs[0];
           		155: softreg_resp.data <= tx_lane_regs[1];
           		160: softreg_resp.data <= tx_lane_regs[2];
           		165: softreg_resp.data <= tx_lane_regs[3];
           		170: softreg_resp.data <= rx_lane_regs[0];
           		175: softreg_resp.data <= rx_lane_regs[1];
           		180: softreg_resp.data <= rx_lane_regs[2];
           		185: softreg_resp.data <= rx_lane_regs[3];
           		190: softreg_resp.data <= error_status_1;
           		195: softreg_resp.data <= error_status_2;
              196: softreg_resp.data <= error_status_3;
              197: softreg_resp.data <= tx_line_count;
           		//
           		101: softreg_resp.data <= pcie_user_received_count;
           		102: softreg_resp.data <= pcie_user_sent_count;

           		// app status counters
           		121: softreg_resp.data <= appStatus[0];
           		122: softreg_resp.data <= appStatus[1];
           		123: softreg_resp.data <= appStatus[2];
           		124: softreg_resp.data <= appStatus[3];
           		125: softreg_resp.data <= appStatus[4];
           		126: softreg_resp.data <= appStatus[5];
           		default: softreg_resp.data <= 64'b0;
        	endcase
		end
		else begin 
			softreg_resp <= '{valid:1'b0, data:64'b0};
		end
	end 
end

endmodule