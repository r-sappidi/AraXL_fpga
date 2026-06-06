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

# PCIe 100 MHz reference clock on the GTP MGTREFCLK0_216 differential pair.
# F6 = MGTREFCLK0P_216, E6 = MGTREFCLK0N_216. No IOSTANDARD: GT refclk pins are
# in the transceiver bank and are buffered by an IBUFDS_GTE2 in the top level.
set_property PACKAGE_PIN F6 [get_ports sys_clk_p]
set_property PACKAGE_PIN E6 [get_ports sys_clk_n]
create_clock -name pcie_refclk -period 10.000 [get_ports sys_clk_p]



set_property BITSTREAM.CONFIG.OVERTEMPPOWERDOWN ENABLE [current_design]
set_property BITSTREAM.CONFIG.EXTMASTERCCLK_EN Div-1 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.SPI_FALL_EDGE YES [current_design]
# Boot fast enough to be PCIe-ready before the host (or a Thunderbolt enclosure's
# switch) probes the link. Default 3 MHz takes ~seconds to load from the 256Mb
# SPI flash, missing the enumeration window; 66 MHz x4 loads in well under 100 ms.
set_property BITSTREAM.CONFIG.CONFIGRATE 66 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
