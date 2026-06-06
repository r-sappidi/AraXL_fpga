# Repo-level Vivado project for browsing/integrating Ara with Taxi PCIe/DMA RTL.

PROJECT ?= ara_taxi
PART ?= xcvu9p-flga2104-2L-e
TOP ?= ara_soc
NR_LANES ?= 4
VLEN ?= 4096
NR_CLUSTERS ?= 2
CREATE_PCIE_IP ?= 1
ARAXL_XSIM_PART ?= xc7a100tlfgg484-2L
ARAXL_XSIM_TOP ?= litefury_araxl_xdma_top
ARAXL_XSIM_NR_LANES ?= 4
ARAXL_XSIM_NR_CLUSTERS ?= 2
VIVADO ?= $(firstword $(shell command -v vivado 2>/dev/null) $(wildcard $(HOME)/2025.2/Vivado/bin/vivado) $(wildcard $(HOME)/20*/Vivado/bin/vivado) $(wildcard /opt/Xilinx/Vivado/*/bin/vivado))

BUILD_DIR ?= build
XPR := $(BUILD_DIR)/$(PROJECT)/$(PROJECT).xpr

.PHONY: all xpr vivado litefury-xpr litefury-vivado litefury-cva6-xpr litefury-cva6-synth litefury-cva6-impl xdma-example-xsim pcie7x-rp araxl-xdma-xsim-setup araxl-xdma-boundary-xsim check-vivado clean

all: xpr

xpr: $(XPR)

check-vivado:
	@if [ -z "$(VIVADO)" ]; then \
		echo "Vivado not found. Set VIVADO=/path/to/vivado or source Xilinx settings64.sh."; \
		exit 127; \
	fi

$(XPR): create_project.tcl | check-vivado
	"$(VIVADO)" -nojournal -nolog -mode batch -source create_project.tcl -tclargs \
		$(PROJECT) $(PART) $(TOP) $(NR_LANES) $(VLEN) $(NR_CLUSTERS) $(CREATE_PCIE_IP) $(BUILD_DIR)

vivado: $(XPR) | check-vivado
	"$(VIVADO)" $(XPR)

litefury-xpr:
	$(MAKE) xpr PART=xc7a100tlfgg484-2L TOP=litefury_araxl_xdma_top NR_LANES=2 NR_CLUSTERS=1 CREATE_PCIE_IP=1

litefury-vivado:
	$(MAKE) vivado PART=xc7a100tlfgg484-2L TOP=litefury_araxl_xdma_top NR_LANES=2 NR_CLUSTERS=1 CREATE_PCIE_IP=1

litefury-cva6-xpr:
	$(MAKE) xpr PROJECT=litefury_cva6_xdma PART=xc7a100tlfgg484-2L TOP=litefury_cva6_xdma_top NR_LANES=1 NR_CLUSTERS=1 CREATE_PCIE_IP=1

litefury-cva6-synth: litefury-cva6-xpr
	"$(VIVADO)" -nojournal -nolog -mode batch -source synth_project.tcl -tclargs build/litefury_cva6_xdma/litefury_cva6_xdma.xpr

IMPL_TO_STEP  ?= write_bitstream
IMPL_STRATEGY ?=
litefury-cva6-impl: litefury-cva6-xpr
	"$(VIVADO)" -nojournal -nolog -mode batch -source impl_project.tcl -tclargs build/litefury_cva6_xdma/litefury_cva6_xdma.xpr $(IMPL_TO_STEP) $(IMPL_STRATEGY)

xdma-example-xsim: $(XPR) | check-vivado
	"$(VIVADO)" -nojournal -nolog -mode batch -source tb/xdma_xsim/create_xdma_example.tcl

# 7-series (GTPE2) root-port BFM, harvested from a pcie_7x example design, used
# to drive the Artix-7 XDMA endpoint (the UltraScale RP cannot train against it).
PCIE7X_RP_BFM := build/pcie7x_rp/pcie7x_ep_ex/imports/xilinx_pcie_2_1_rport_7x.v

pcie7x-rp: $(PCIE7X_RP_BFM)

$(PCIE7X_RP_BFM): tb/xdma_xsim/create_pcie7x_rp.tcl | check-vivado
	"$(VIVADO)" -nojournal -nolog -mode batch -source tb/xdma_xsim/create_pcie7x_rp.tcl

araxl-xdma-xsim-setup: check-vivado
	"$(VIVADO)" -nojournal -nolog -mode batch -source create_project.tcl -tclargs \
		$(PROJECT) $(ARAXL_XSIM_PART) $(ARAXL_XSIM_TOP) $(ARAXL_XSIM_NR_LANES) $(VLEN) $(ARAXL_XSIM_NR_CLUSTERS) 1 $(BUILD_DIR)
	"$(VIVADO)" -nojournal -nolog -mode batch -source tb/xdma_xsim/prepare_araxl_xdma_xsim.tcl

ARAXL_APP ?= ../../apps/bin/dotproduct
ARAXL_PAYLOAD_HEX ?= build/araxl_xdma_payload.hex
ARAXL_PAYLOAD_BIN ?= build/araxl_xdma_payload.bin

# Memory cap for the long-running xsim. Without it, a runaway xsim exhausts
# RAM+swap and the kernel OOM killer takes the terminal down with it. With it,
# only the simulation job is killed (cleanly) when the limit is hit.
XSIM_MEM_MAX ?= 24G
XSIM_SWAP_MAX ?= 2G
# ulimit -v (virtual memory, KB) used when systemd --user scopes aren't available.
XSIM_VMEM_KB ?= 26000000

ARAXL_RUN_CMD = "$(VIVADO)" -nojournal -nolog -mode batch -source tb/xdma_xsim/run_araxl_dotproduct_xsim.tcl -tclargs \
	$(abspath $(ARAXL_PAYLOAD_HEX)) $$(cat $(abspath $(ARAXL_PAYLOAD_HEX)).len)

../../apps/bin/dotproduct:
	$(MAKE) -C ../../apps bin/dotproduct nr_clusters=$(ARAXL_XSIM_NR_CLUSTERS) config=$(ARAXL_XSIM_NR_LANES)_lanes

$(ARAXL_PAYLOAD_HEX): $(ARAXL_APP)
	python3 tb/xdma_xsim/elf_to_xdma_hex.py $< $@ --bin $(ARAXL_PAYLOAD_BIN) > $@.len

# NOTE: the full-execution AraXL sim (formerly araxl-dotproduct-xsim) is removed:
# xsim cannot settle the pulp axi_xbar, so program execution never ran. Only the
# XDMA-load boundary test below (fabric stubbed) is retained -- it validates the
# real XDMA H2C path to the L2 boundary without executing.
araxl-xdma-boundary-xsim: araxl-xdma-xsim-setup $(ARAXL_PAYLOAD_HEX) | check-vivado
	@if systemd-run --user --scope --quiet -p MemoryMax=$(XSIM_MEM_MAX) -p MemorySwapMax=$(XSIM_SWAP_MAX) true >/dev/null 2>&1; then \
		echo "Running XDMA boundary xsim under systemd scope (MemoryMax=$(XSIM_MEM_MAX), MemorySwapMax=$(XSIM_SWAP_MAX))"; \
		systemd-run --user --scope --quiet \
			-p MemoryMax=$(XSIM_MEM_MAX) -p MemorySwapMax=$(XSIM_SWAP_MAX) \
			env ARAXL_EXTRA_DEFINES="XSIM_XDMA_AXI_STUB" $(ARAXL_RUN_CMD); \
	else \
		echo "systemd --user scopes unavailable; capping with ulimit -v $(XSIM_VMEM_KB) KB"; \
		( ulimit -v $(XSIM_VMEM_KB); env ARAXL_EXTRA_DEFINES="XSIM_XDMA_AXI_STUB" $(ARAXL_RUN_CMD) ); \
	fi

clean:
	rm -rf $(BUILD_DIR) *.jou *.log .Xil
