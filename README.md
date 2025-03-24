# RedMulE-FT
RedMulE-FT is a runtime-configurable fault-tolerant extension of the RedMulE matrix multiplication accelerator, balancing fault tolerance, area overhead, and performance impacts. The fault tolerance mode is configured in a shadowed context register file before task execution. By combining replication with error-detecting codes to protect the data path, RedMulE-FT achieves an 11x uncorrected fault reduction with only 2.3% area overhead. Full protection extends to control signals, resulting in no functional errors after 1M injections during our extensive fault injection simulation campaign, with a total area overhead of 25.2% while maintaining a 500MHz frequency in a 12nm technology.

**RedMulE-FT was forked from the [RedMulE](https://github.com/pulp-platform/redmule) repository, which is an open-source hardware accelerator based on the HWPE template. See the original README [here](README_RedMulE.md).**

## Getting Started

### Install Dependencies
If you are working on ETH workstations the `scripts/setup.sh` should suffice to export the path to the bender, to the SDK, and to the toolchain. Otherwise, it is recommended to install a riscv [toolchain](https://github.com/pulp-platform/pulp-riscv-gnu-toolchain) and export the following environment variables:
```bash
export PATH=/absolute/path/to/riscv/toolchain/bin:$PATH
export PULP_RISCV_GCC_TOOLCHAIN=/absolute/path/to/riscv/toolchain
export PULP_CC=/your/riscv/gcc
export PULP_LD=/your/riscv/gcc
export PATH=/absolute/path/to/gcc/bin:$PATH
```
Install bender by executing:
```bash
make bender
```
Bender installation is not mandatory. If any bender version is already installed, it is just needed to add the absolute path to the `bender` binary to the `PATH` variable.

Additionally, you need to download [InjectaFault](https://github.com/pulp-platform/InjectaFault) to run the fault injection campaign.
The path to InjectaFault is specified in [vulnerability_analysis.tcl](vulnerability_analysis/vulnerability_analysis.tcl) and defaults to `../InjectaFault`. If you have InjectaFault installed in a different location, you can change the path in the tcl script.

```bash
git clone https://github.com/xeratec/injectafault ../InjectaFault
```

The golden model makes use of Python3.6 virtual environment, Numpy and Pytorch. These modules have
to be installed if they are not already present. To simplify this procedure, the `golden-model` folder
contains a `setup-py.sh` that can be sourced to install all these modules, and to export the
required environment variables.
```bash
cd golden-model
source setup-py.sh
```

### Build Hardware

Clone the dependencies and generate the compilation script by running:
```bash
make update-ips
```

Build the hardware:
```bash
make build-hw
```

### Run Simulations
Clone the pulp-sdk (if not already cloned somewhere else):
```bash
make sdk
```

Source the relative setup script:
```bash
source /absolute-path-to-the/pulp-sdk/configs/pulp-open.sh
```

The previous `make` command clones the pulp-sdk under `sw`, so it is possible to:
```bash
source sw/pulp-sdk/configs/pulp-open.sh
```

Now, it is possible to execute the test:
```bash
# Compile the Software
make all SOFTWARE_ENABLE_REDUNDANCY=1

# Start RTL Simulation in GUI Mode
make run \
  HARDWARE_FULL_REDUNDANCY=1 \
  HARDWARE_ECC=1 \
  gui=1
```

### Run Fault Injection
To run the fault injection on the full protected RedMulE-FT version, run:
```bash
# Compile the Software
make all SOFTWARE_ENABLE_REDUNDANCY=1

# Start RTL Fault Injection Simulation
make analysis \
  HARDWARE_FULL_REDUNDANCY=1 \
  HARDWARE_ECC=1 \
  tests=1 \
  seed=0
```

To run a parallel multi-threaded fault injection campaign run:
```bash
# Get Usage Help Message
./scripts/parallel_fault_injection.sh

# Run 1M injections with 10 parallel threads
./scripts/parallel_fault_injection.sh 1 1 1 1000000 10
```

## License and Citation
RedMulE-FT is an open-source project and, wherever not explicitly stated, all hardware sources
are licensed under the SolderPad Hardware License Version 0.51, and all software sources
are licensed under the Apache License Version 2.0.
If you want to use RedMulE-FT for academic purposes, please cite it as:

```
@INPROCEEDINGS{wiese_redumule-ft,
  author={Philip Wiese, Maurus Item, Luca Bertaccini, Yvan Tortorella, Angelo Garofalo, and Luca Benini},
  title={RedMulE-FT: A Reconfigurable Fault-Tolerant Matrix Multiplication Engine},
  year={2025},
  booktitle = {Proceedings of the 22nd ACM International Conference on Computing Frontiers: Workshops and Special Sessions},
  series = {CF '25 Companion}
  location = {Cagliari, Italy},
  publisher = {Association for Computing Machinery},
  address = {New York, NY, USA},
  numpages = {4},
  url = {TBD},
  doi = {TBD},
  isbn = {TBD},
  pages = {TBD},
}
```
