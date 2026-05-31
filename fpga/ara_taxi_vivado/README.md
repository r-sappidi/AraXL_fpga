# Ara + Taxi Vivado Project

This directory creates a Vivado project that contains the Ara RTL and the Taxi
PCIe/DMA/AXI/AXIS RTL. It is intended as the starting point for building the
real FPGA top that connects Ara to the Taxi PCIe DMA path.

From this directory:

```sh
make vivado
```

That creates and opens:

```text
build/ara_taxi/ara_taxi.xpr
```

Defaults:

- Part: `xcvu9p-flga2104-2L-e` (VCU118)
- Top: `ara_soc`
- Ara config: `NR_LANES=4`, `VLEN=4096`, `NR_CLUSTERS=2`
- Xilinx PCIe4 IP: created from Taxi's VCU118 `pcie4_uscale_plus_0.tcl`

Common overrides:

```sh
make vivado PART=<xilinx-part> TOP=<top-module>
make vivado NR_LANES=2 VLEN=2048 NR_CLUSTERS=1
make vivado CREATE_PCIE_IP=0
```

This project does not yet wire Ara to Taxi. It gives Vivado one project that
contains both codebases plus the PCIe hard-IP shell so the integration wrapper
can be developed in place.
