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

The XDMA top keeps the Ara core in reset after AXI reset while leaving the SoC
fabric, L2, and control registers accessible from the external AXI master. After
loading a program into L2 at 0x8000_0000, write bit 0 of the 64-bit
core-release register at 0xD000_0028 to start execution.

This project gives Vivado one project that contains both codebases plus the PCIe
hard-IP shell so the integration wrapper can be developed in place.
