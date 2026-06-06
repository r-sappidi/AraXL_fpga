# Apply LiteFury PCIe GT lane placement after the XDMA netlist is open.
# XDMA emits default GT LOCs; clear all lanes first so lane swaps do not collide.
set_msg_config -id {Constraints 18-4427} -new_severity WARNING

proc litefury_gt_cell {lane} {
    set pattern [format {.*i_xdma.*/pipe_lane\[%d\]\.gt_wrapper_i/gtp_channel\.gtpe2_channel_i$} $lane]
    set cells [get_cells -hierarchical -regexp $pattern]
    if {[llength $cells] != 1} {
        error "Expected one XDMA GT cell for lane $lane, matched [llength $cells]: $cells"
    }
    return $cells
}

set litefury_gt_lane0 [litefury_gt_cell 0]
set litefury_gt_lane1 [litefury_gt_cell 1]
set litefury_gt_lane2 [litefury_gt_cell 2]
set litefury_gt_lane3 [litefury_gt_cell 3]

reset_property LOC [list $litefury_gt_lane0 $litefury_gt_lane1 $litefury_gt_lane2 $litefury_gt_lane3]

set_property LOC GTPE2_CHANNEL_X0Y6 $litefury_gt_lane0
set_property LOC GTPE2_CHANNEL_X0Y4 $litefury_gt_lane1
set_property LOC GTPE2_CHANNEL_X0Y5 $litefury_gt_lane2
set_property LOC GTPE2_CHANNEL_X0Y7 $litefury_gt_lane3

set_property PACKAGE_PIN A10 [get_ports {pci_exp_rxn[0]}]
set_property PACKAGE_PIN B10 [get_ports {pci_exp_rxp[0]}]
set_property PACKAGE_PIN A6  [get_ports {pci_exp_txn[0]}]
set_property PACKAGE_PIN B6  [get_ports {pci_exp_txp[0]}]

set_property PACKAGE_PIN A8 [get_ports {pci_exp_rxn[1]}]
set_property PACKAGE_PIN B8 [get_ports {pci_exp_rxp[1]}]
set_property PACKAGE_PIN A4 [get_ports {pci_exp_txn[1]}]
set_property PACKAGE_PIN B4 [get_ports {pci_exp_txp[1]}]

set_property PACKAGE_PIN C11 [get_ports {pci_exp_rxn[2]}]
set_property PACKAGE_PIN D11 [get_ports {pci_exp_rxp[2]}]
set_property PACKAGE_PIN C5  [get_ports {pci_exp_txn[2]}]
set_property PACKAGE_PIN D5  [get_ports {pci_exp_txp[2]}]

set_property PACKAGE_PIN C9 [get_ports {pci_exp_rxn[3]}]
set_property PACKAGE_PIN D9 [get_ports {pci_exp_rxp[3]}]
set_property PACKAGE_PIN C7 [get_ports {pci_exp_txn[3]}]
set_property PACKAGE_PIN D7 [get_ports {pci_exp_txp[3]}]

# The XDMA<->CVA6-SoC axi_cdc crosses the 125 MHz XDMA AXI clock (clk_125mhz)
# and the MMCM-derived 25 MHz SoC clock via gray-coded async FIFOs. Declare the
# two domains asynchronous so the crossings are not timed as related clocks.
set soc_clk [get_clocks -quiet -of_objects \
    [get_pins -quiet -hierarchical -filter {NAME =~ *i_soc_mmcm/CLKOUT0}]]
set axi_clk [get_clocks -quiet clk_125mhz]
if {[llength $soc_clk] == 1 && [llength $axi_clk] == 1} {
    set_clock_groups -asynchronous -group $axi_clk -group $soc_clk
    puts "Declared async clock groups: $axi_clk <-> $soc_clk"
} else {
    puts "WARNING: CDC clock grouping skipped (soc_clk='$soc_clk' axi_clk='$axi_clk')"
}

puts "Applied LiteFury XDMA GT LOCs:"
puts "  lane 0 -> GTPE2_CHANNEL_X0Y6 ($litefury_gt_lane0)"
puts "  lane 1 -> GTPE2_CHANNEL_X0Y4 ($litefury_gt_lane1)"
puts "  lane 2 -> GTPE2_CHANNEL_X0Y5 ($litefury_gt_lane2)"
puts "  lane 3 -> GTPE2_CHANNEL_X0Y7 ($litefury_gt_lane3)"
