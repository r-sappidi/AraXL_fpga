# Generate a 7-series pcie_7x endpoint example design solely to harvest its
# GTPE2 root-port BFM (xilinx_pcie_2_1_rport_7x + pci_exp_usrapp_*), which we
# will use to drive the Artix-7 XDMA endpoint in board_araxl_xdma.v. Link params
# (x4, Gen1 2.5GT/s, 100MHz refclk) match the XDMA endpoint so the BFM trains.
set script_dir [file normalize [file dirname [info script]]]
set fpga_dir   [file normalize [file join $script_dir ../..]]
set build_dir  [file normalize [file join $fpga_dir build]]
set proj_dir   [file join $build_dir pcie7x_rp]
set part       xc7a100tlfgg484-2L

file delete -force $proj_dir
create_project -force pcie7x_rp $proj_dir -part $part
set_property target_language Verilog [current_project]

create_ip -name pcie_7x -vendor xilinx.com -library ip -module_name pcie7x_ep
set_property -dict [list \
  CONFIG.Maximum_Link_Width {X4} \
  CONFIG.Link_Speed {2.5_GT/s} \
  CONFIG.Ref_Clk_Freq {100_MHz} \
  CONFIG.PCIe_Blk_Locn {X0Y0} \
] [get_ips pcie7x_ep]

puts "CHECK Device_Port_Type=[get_property CONFIG.Device_Port_Type [get_ips pcie7x_ep]]"
puts "CHECK Maximum_Link_Width=[get_property CONFIG.Maximum_Link_Width [get_ips pcie7x_ep]]"
puts "CHECK Link_Speed=[get_property CONFIG.Link_Speed [get_ips pcie7x_ep]]"
puts "CHECK Ref_Clk_Freq=[get_property CONFIG.Ref_Clk_Freq [get_ips pcie7x_ep]]"

generate_target all [get_ips pcie7x_ep]
if {[catch {open_example_project -force -dir $proj_dir [get_ips pcie7x_ep]} msg]} {
    puts "OPEN_EXAMPLE_ERROR: $msg"
    exit 1
}
puts "EXAMPLE_DONE example_dir=[file join $proj_dir pcie7x_ep_ex]"
exit
