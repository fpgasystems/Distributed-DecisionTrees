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
---Decision Trees profiler used for Performance prediction---
Input: Problem size
Output:
- Performance scaling with number of FPGAs and tree depth level
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
double system_throughput(double , double, double, int);

int main() {
	int number_of_FPGAs[5] = { 1, 2, 4, 8, 16};
	int tree_depth_level[8] = {6, 7, 8, 9, 10, 11, 12, 13};
	double throughput_engine_v = 0;
	double throughput_distributed_engine_v = 0;
	double T_network = 0;
	double T_memory = 0;
	double system_throughput_v = 0;

	T_network = double(Network_BW*1e9) / double(Size_tuple_Bytes);
	T_memory = double(PCIe_BW*1e9) / double(Size_tuple_Bytes);

	cout << "Throughput of the memory = " << T_memory << "\n";
	cout << "Throughput of the Network = " << T_network << "\n";

	cout << "Througput Estimation for different number of FPGAs with different tree depth levels.. \n";
	cout << "Number of FPGAs:\t\t Tree depth level:\t\t Throughput: \t\t \n";

	for (int i=0; i < sizeof (number_of_FPGAs) / sizeof (int); i++ ){
		for (int j=0 ; j < sizeof (tree_depth_level) / sizeof (int); j++){
			 throughput_engine_v = throughput_engine (int(Freq_input), int(Ncu_input), int(Npe_input), (tree_depth_level[j]-1) /* skip the leaf nodes*/,  int(N_trees));
			 throughput_distributed_engine_v = throughput_distributed_engine(number_of_FPGAs[i],throughput_engine_v);
			 system_throughput_v = system_throughput(throughput_distributed_engine_v, T_memory, T_network, number_of_FPGAs[i]);
			 cout << number_of_FPGAs[i] << "\t\t\t\t " << tree_depth_level[j] <<  "\t\t\t\t " << system_throughput_v << "\n";
		}
	}
} //End of main()

/* Helper functions*/
double compute_rate_PE(int depth_tree) {
	return (double(1) / double(depth_tree)); /*Infer operations per cycle*/
}

double compute_rate_engine(int freq, int Ncu, int Ncupe, int depth_tree) {
	return (double(freq*Ncu*Ncupe) / double(depth_tree)); /*Infer operations per second*/
}

double throughput_engine (int freq,
						 int Ncu,
						 int Ncupe,
						 int depth_tree,
						 int Ntrees) {
	double ret_val = 0;
	ret_val = double(freq*1e6*Ncu*Ncupe) / double(depth_tree * Ntrees); /*Tuples per second*/
	return ret_val;
}

double throughput_distributed_engine(int Nfpgas, double throughput_engine) {
	return  double(Nfpgas * throughput_engine); /*Tuples per second*/
}

double system_throughput(double T_engine, double T_memory, double T_network, int n_fpgas) {
	double ret_val = 0;
	if (n_fpgas > 1){
		ret_val = min(min(T_engine, T_memory), T_network);/*Tuples per second*/
	}
	else if (n_fpgas == 1){
		ret_val = min(T_engine, T_memory); /*Tuples per second*/
	}
	return ret_val;
}
