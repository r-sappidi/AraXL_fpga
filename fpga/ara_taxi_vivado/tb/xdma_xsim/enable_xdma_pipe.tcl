# Enable PIPE-mode simulation on the existing xdma_1 IP so the wrapper exposes
# its PIPE interface (common_commands_*, pipe_tx/rx_0_sigs) for a GT-less PIPE
# interconnect to the matching pcie3_uscale_rp root port.
set script_dir [file normalize [file dirname [info script]]]
set fpga_dir   [file normalize [file join $script_dir ../..]]
set main_xpr   [file normalize [file join $fpga_dir build ara_taxi ara_taxi.xpr]]

open_project $main_xpr
set ip [get_ips xdma_1]
puts "BEFORE pipe_sim=[get_property CONFIG.pipe_sim $ip]"
set_property CONFIG.pipe_sim {true} $ip
puts "AFTER pipe_sim=[get_property CONFIG.pipe_sim $ip]"
reset_target {simulation} $ip
generate_target {simulation} $ip
puts "XDMA_PIPE_REGEN_DONE"
close_project
exit
