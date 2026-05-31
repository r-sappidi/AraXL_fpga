# Repo-level Vivado project for browsing/integrating Ara with Taxi PCIe/DMA RTL.

PROJECT ?= ara_taxi
PART ?= xcvu9p-flga2104-2L-e
TOP ?= ara_soc
NR_LANES ?= 4
VLEN ?= 4096
NR_CLUSTERS ?= 2
CREATE_PCIE_IP ?= 1
VIVADO ?= $(firstword $(shell command -v vivado 2>/dev/null) $(wildcard $(HOME)/2025.2/Vivado/bin/vivado) $(wildcard $(HOME)/20*/Vivado/bin/vivado) $(wildcard /opt/Xilinx/Vivado/*/bin/vivado))

BUILD_DIR ?= build
XPR := $(BUILD_DIR)/$(PROJECT)/$(PROJECT).xpr

.PHONY: all xpr vivado litefury-xpr litefury-vivado check-vivado clean

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

clean:
	rm -rf $(BUILD_DIR) *.jou *.log .Xil
