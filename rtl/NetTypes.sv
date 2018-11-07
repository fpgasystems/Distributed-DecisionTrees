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
 
package NetTypes;

parameter CONN_ID_WIDTH        = 2;          // MAX 4 connections per device

parameter NUM_SL3_LANES        = 4;
parameter LANE_ID_WIDTH        = 2;
parameter LANE_ID_LIST_WIDTH   = LANE_ID_WIDTH*NUM_SL3_LANES;

parameter USER_ID_WIDTH        = 4;          // USER Modules in the USER Logic Area
parameter DEVICE_ID_WIDTH      = 10;         // Maximum number of devices in the network = 1024
parameter NET_ADDRESS_WIDTH    = 16;
parameter USER_METADATA_WIDTH  = 16;

parameter USER_DATA_BUS_WIDTH  = 128;
parameter MAX_NUM_USER_STREAMS = 8;
parameter MAXIMUM_NUM_USERS    = 1;
parameter MAX_NUM_USER_MODULES = 32;


parameter RT_WORD_CONN_BITS        = 4;
parameter ROUTING_TABLE_SIZE_BITS  = 13;      // 8192 Connection IDs in one BRAM
parameter ROUTING_TABLE_WORD_WIDTH = 32;      // One word includes 8 Connection IDs
parameter ROUTING_TABLE_WORD_BITS  = ROUTING_TABLE_SIZE_BITS - RT_WORD_CONN_BITS;
parameter NUM_CONN_ID_PER_RT_WORD  = ROUTING_TABLE_WORD_WIDTH / CONN_ID_WIDTH;

parameter [USER_ID_WIDTH-1:0] CONTROLLER_ID = 4'b1111;



parameter INIT_CREDITS = 512;


typedef struct packed
{
	logic  [USER_DATA_BUS_WIDTH-1:0]    data;
	logic                               last;
	logic                               valid;
	logic  [NET_ADDRESS_WIDTH-1:0]      address;
	logic  [USER_METADATA_WIDTH-1:0]    metadata;
} UserPacketWord;

typedef struct packed
{
	logic  [NET_ADDRESS_WIDTH-1:0]      dest_addr;
	logic  [NET_ADDRESS_WIDTH-1:0]      src_addr;
	logic  [USER_METADATA_WIDTH-1:0]    metadata;
} PacketHeader;

typedef struct packed
{
	logic  [USER_DATA_BUS_WIDTH-1:0]    data;
	logic                               last;
	logic                               valid;
	logic                               first;
	PacketHeader                        header;
} PacketWord;


typedef struct packed
{
	PacketWord                          packet_word;
	logic                               controller_packet;
	logic  [CONN_ID_WIDTH-1:0]          connection_id;
} NetworkLayerPacketTX;


endpackage