# Fast discovery pass: create the 7-series pcie_7x IP with defaults and dump the
# config properties (+ allowed values) we need to build a GTPE2 root-port BFM
# that matches the Artix-7 XDMA endpoint. Does NOT generate targets (fast).
set script_dir [file normalize [file dirname [info script]]]
set fpga_dir   [file normalize [file join $script_dir ../..]]
set build_dir  [file normalize [file join $fpga_dir build]]
set proj_dir   [file join $build_dir pcie7x_disc]
set part       xc7a100tlfgg484-2L

file delete -force $proj_dir
create_project -force pcie7x_disc $proj_dir -part $part
set_property target_language Verilog [current_project]

if {[catch {create_ip -name pcie_7x -vendor xilinx.com -library ip -module_name pcie7x_probe} msg]} {
    puts "CREATE_IP_ERROR: $msg"
    exit 1
}
set ip [get_ips pcie7x_probe]
puts "==== pcie_7x available CONFIG properties (name = current_value) ===="
foreach p [lsort [list_property $ip CONFIG.*]] {
    puts "$p = [get_property $p $ip]"
}
puts "==== allowed values for key properties ===="
foreach p {CONFIG.Device_Port_Type CONFIG.Maximum_Link_Width CONFIG.Link_Speed CONFIG.Ref_Clk_Freq CONFIG.Trgt_Link_Speed CONFIG.PCIe_Blk_Locn CONFIG.mode_selection} {
    if {[lsearch -exact [list_property $ip] $p] >= 0} {
        puts "$p -> {[list_property_value $p $ip]}"
    } else {
        puts "$p -> (no such property)"
    }
}
exit
