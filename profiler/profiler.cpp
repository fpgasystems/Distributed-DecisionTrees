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
Created by Systems Group @ ETHZ on 13/11/18.
---Decision Trees profiler---
Input: Problem size
Output: 
- Number of FPGAs required for a given problem size
- Corresponding throughput
*/
#include <iostream>
#include <fstream>
#include <algorithm>
#include <math.h>
using namespace std;

/*User inputs*/
#define N_trees 512
#define Depth_tree 12
#define Size_tuple_Bytes 128 //32*4 Bytes
#define Freq_input 150 //MHz
#define Ncu_input  4
#define Npe_input  8
#define max_nodes_in_fpga  8192
#define max_mem_throughput_measured 93.75 //Mega Tuples per second
#define PCIe_BW 2.2 //GBps
#define Network_BW 3 //GBps

double compute_rate_PE(int);
double compute_rate_engine(int, int, int, int);
double throughput_engine(int, int, int, int, int);
double throughput_memory(double, int);
double throughput_distributed_engine(int, double);
double throughput_network(double, int);
double system_throughput(double , double);

int main() {
	long int max_trees_size_in_fpga = Ncu_input * Npe_input * max_nodes_in_fpga;
	long int user_desired_tree_size = N_trees * (pow(2,Depth_tree));
	long int max_number_of_fpgas_needed = 0;
	double throughput_consumed = 0;
	double dist_throughput = 0;
	long int min_num_of_fpgas_needed = 0;

	cout << "max_trees_size_in_fpga = " << max_trees_size_in_fpga << "\n";
	cout << "user_desired_tree_size = " << user_desired_tree_size << "\n";
	double throughput_engine_v = throughput_engine(int(Freq_input), int(Ncu_input), int(Npe_input),	int(Depth_tree), int(N_trees));

	if (user_desired_tree_size <= max_trees_size_in_fpga) {
		max_number_of_fpgas_needed = 1;
		dist_throughput = throughput_distributed_engine(max_number_of_fpgas_needed, throughput_engine_v);
	}
	else
	{
		throughput_consumed = throughput_engine_v * Size_tuple_Bytes;

		//Maximum number of FPGAs needed:
		max_number_of_fpgas_needed = PCIe_BW*1e9 / throughput_consumed;

		//Minimum number of FPGAs needed:
		min_num_of_fpgas_needed = (pow(2, Depth_tree) * N_trees) / max_trees_size_in_fpga;

		dist_throughput = throughput_distributed_engine(min_num_of_fpgas_needed, throughput_engine_v);
		cout << "Minimum no.of.fpgas_needed = " << min_num_of_fpgas_needed << "\n";
		cout << "Corresponding Throughput = " << dist_throughput << "\n";
	}
	cout << "Maximum no.of.fpgas_needed = " << max_number_of_fpgas_needed << "\n";
	dist_throughput = throughput_distributed_engine(max_number_of_fpgas_needed, throughput_engine_v);
	cout << "Corresponding Throughput = " << dist_throughput << "\n";
	system("pause");
	return 0;
} //End of main()

/*Helper functions*/
double compute_rate_PE(int depth_tree) {
	return (double(1) / double(depth_tree)); /*Infer operations per cycle*/
}

double compute_rate_engine(int freq, int Ncu, int Ncupe, int depth_tree) {
	return (double(freq*Ncu*Ncupe) / double(depth_tree)); /*Infer operations per second*/
}

double throughput_engine (int freq, int Ncu, int Ncupe, int depth_tree, int Ntrees) {
	double ret_val = 0;
	ret_val = double(freq*1e6*Ncu*Ncupe) / double(depth_tree * Ntrees); /*Tuples per second*/
	cout << "ret_val = " << ret_val << "\n";
	return ret_val;
}

double throughput_memory(double BW, int size_tuple) {
	return double(BW) / double(size_tuple); /*Tuples per second*/
}

double throughput_distributed_engine(int Nfpgas, double throughput_engine) {
	return  double(Nfpgas * throughput_engine); /*Tuples per second*/
}

double throughput_network(double BW, int size_tuple) {
	return  double(BW) / double(size_tuple); /*Tuples per second*/
}

double system_throughput(double T_e, double T_m) {
	return min(T_e, T_m); /*Tuples per second*/
}


