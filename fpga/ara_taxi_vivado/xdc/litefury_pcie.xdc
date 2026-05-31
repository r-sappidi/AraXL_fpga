# LiteFury Artix-7 PCIe constraints.
#
# The XDMA IP is the PCIe endpoint. LiteFury routes the M.2 PCIe lanes in an
# order that does not match Vivado's default 7-series XDMA lane locations, so
# these constraints intentionally override the generated IP GT channel LOCs.

set_property PACKAGE_PIN J1 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]
set_false_path -from [get_ports sys_rst_n]

set_property PACKAGE_PIN G1 [get_ports pcie_clkreq_l]
set_property IOSTANDARD LVCMOS33 [get_ports pcie_clkreq_l]

set_property PACKAGE_PIN F6 [get_ports sys_clk]
create_clock -name pcie_refclk -period 10.000 [get_ports sys_clk]

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

proc araxl_set_gt_loc {pattern loc} {
    set cells [get_cells -hierarchical -filter "NAME =~ $pattern"]
    if {[llength $cells] > 0} {
        reset_property LOC $cells
        set_property LOC $loc $cells
    } else {
        puts "Warning: no GT cell matched $pattern"
    }
}

araxl_set_gt_loc {*i_xdma/inst/gt_top_i/pipe_wrapper_i/pipe_lane[0].gt_wrapper_i/gtp_channel.gtpe2_channel_i} GTPE2_CHANNEL_X0Y6
araxl_set_gt_loc {*i_xdma/inst/gt_top_i/pipe_wrapper_i/pipe_lane[1].gt_wrapper_i/gtp_channel.gtpe2_channel_i} GTPE2_CHANNEL_X0Y4
araxl_set_gt_loc {*i_xdma/inst/gt_top_i/pipe_wrapper_i/pipe_lane[2].gt_wrapper_i/gtp_channel.gtpe2_channel_i} GTPE2_CHANNEL_X0Y5
araxl_set_gt_loc {*i_xdma/inst/gt_top_i/pipe_wrapper_i/pipe_lane[3].gt_wrapper_i/gtp_channel.gtpe2_channel_i} GTPE2_CHANNEL_X0Y7

set_property BITSTREAM.CONFIG.OVERTEMPPOWERDOWN ENABLE [current_design]
set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN Div-1 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
