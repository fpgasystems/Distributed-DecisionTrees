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
 
package DTEngine_Types;

parameter   DATA_BUS_WIDTH                  = 128;

parameter   NUM_FPGA_DEVICES                = 20;
parameter   NUM_FPGA_DEVICES_BITS           = 5;

parameter   NUM_PUS_PER_CLUSTER_BITS        = 3;
parameter   NUM_PUS_PER_CLUSTER             = 8;
parameter   NUM_DTPU_CLUSTERS 		        = 8;
parameter   NUM_DTPU_CLUSTERS_BITS          = 3;
parameter   NUM_TREES_PER_PU                = 32;

parameter   FEATURES_DISTR_DELAY            = 8;

parameter   DATA_PRECISION                  = 32;
parameter   FIXED_POINT_ARITHMATIC          = ((DATA_PRECISION < 32)? 1 : 0);

parameter   TREE_WEIGHTS_PROG               = 1'b0;
parameter   TREE_FEATURE_INDEX_PROG         = 1'b1;

parameter   WAIT_CYCLES_FOR_LAST_TREE       = 16;
parameter   FP_ADDER_LATENCY                = 2;

parameter   PACKET_SIZE_BITS                = 8;
parameter   PCIE_PACKET_SIZE_BITS           = 12;

parameter   DEVICE_ADDRESS_WIDTH            = 5;


// Streams types
parameter  [15:0]     	                    DATA_STREAM        = 1, 
											TREE_WEIGHT_STREAM = 2, 
											TREE_FINDEX_STREAM = 3, 
											RESULTS_STREAM     = 4;




typedef struct packed
{
	logic  [DATA_BUS_WIDTH-1:0]         data;
	logic                               data_valid;
	logic                               last;
	logic                               prog_mode;  //1: weights, 0 feature indexes
} CoreDataIn;




endpackage




