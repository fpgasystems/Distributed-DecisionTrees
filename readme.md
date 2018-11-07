
# Distributed Inference over Decision Tree Ensembles 

This operator is a distributed version of our previous implementation on a single FPGA to a cluster of Catapult FPGAs (Academic Catapult v1.2). 

# Architecture

The figure below depicts the architecture of the distributed inference engine on a single FPGA. The modules in the design are annotated with the SystemVerilog file (\*.sv) which includes its implementation. The Core module (DTEngine/Core.sv) is extracted from the previous implementation on the Intel's HARP machine. 

![Engine Architecture](arch.png)

- PCIeShim.sv: This module multiplexes PCIe traffic for the CPU to either router_node or DTInference.sv
- ManagerSoftRegs.sv: This multiplexes soft register interface between the router_node and DTInference modules.
- node_router.sv (in router directory): This module routes traffic to/from remote FPGAs.

The Following files reside in the DTEngine folder:
- InputDistriputor.sv: This module functions as a crossbar passing input data/trees either from PCIe or SL3 to the Core module. It also implements broadcasting functions to broadcast either trees or data through the SL3 to other FPGAs.
- SL3TxMux.sv: This module multiplexes outgoing SL3 traffic from either broadcasted data/trees (from InputDistributor.sv) or combined results (from ResultsCombiner.sv)
- ResultsCombiner.sv: This module either aggregates local results with incoming results over SL3, or write local and remote results in order. It works as a crossbar to output results to PCIe or  SL3.
- PCIeReceiver.sv: This module routes incoming CPU traffic to either local core or to remote FPGA (connection to SL3TxMux not shown in the block diagram).
- EngineCSR.sv: This module holds all engine parameters needed for its operation. 

# Reference Articles

[1] Muhsen Owaida, Gustavo Alonso. Application Partitioning on FPGA Clusters: Inference over Decision Tree Ensembles. In FPL 2018.



