###############################################################################
## Constraints for Aurora 64B66B Dual-Channel Design
##
## Target: xc7vx690tffg1927-2L
## Tool: Vivado 2018.3
##
## Note: Pin assignments below are examples for the xc7vx690tffg1927-2L.
##       Verify and update the actual pin locations based on your board
##       schematic and the specific GTHQ0/GTHQ1 bank assignments.
###############################################################################

###############################################################################
## GT Reference Clock Constraints
##
## The GT reference clock is a differential clock driving the IBUFDS_GTE2.
## Typical frequency: 161.1328125 MHz for 10.3125 Gbps Aurora 64B66B.
## Update the period and pin locations for your specific design.
###############################################################################
create_clock -period 6.206 -name gt_refclk [get_ports gt_refclk_p]

## GT Reference Clock Pin Assignment (GTHQ0 MGTREFCLK0)
## Update these pins based on your board schematic
# set_property PACKAGE_PIN <pin> [get_ports gt_refclk_p]
# set_property PACKAGE_PIN <pin> [get_ports gt_refclk_n]

###############################################################################
## Init Clock Constraints
##
## The initialization clock is provided from the board system clock.
## Typical frequency: 100 MHz.
###############################################################################
# create_clock -period 10.000 -name init_clk [get_ports init_clk_in]

## Init Clock Pin Assignment
## Update these pins based on your board schematic
# set_property PACKAGE_PIN <pin> [get_ports init_clk_in]
# set_property IOSTANDARD LVCMOS18 [get_ports init_clk_in]

###############################################################################
## System Reset Pin Assignment
###############################################################################
# set_property PACKAGE_PIN <pin> [get_ports sys_rst_n]
# set_property IOSTANDARD LVCMOS18 [get_ports sys_rst_n]

###############################################################################
## GT Serial Interface Pin Assignments
##
## Channel 0 - GTHQ0 (Lanes 1-4)
## These are the MGT serial pins for the first Aurora channel.
## Pin assignments are determined by the GT quad location.
###############################################################################
## Channel 0 TX
# set_property PACKAGE_PIN <pin> [get_ports {ch0_txp[0]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch0_txn[0]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch0_txp[1]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch0_txn[1]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch0_txp[2]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch0_txn[2]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch0_txp[3]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch0_txn[3]}]

## Channel 0 RX
# set_property PACKAGE_PIN <pin> [get_ports {ch0_rxp[0]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch0_rxn[0]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch0_rxp[1]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch0_rxn[1]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch0_rxp[2]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch0_rxn[2]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch0_rxp[3]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch0_rxn[3]}]

###############################################################################
## Channel 1 - GTHQ1 (Lanes 1-4, adjacent to GTHQ0)
## Pin assignments are determined by the GT quad location.
###############################################################################
## Channel 1 TX
# set_property PACKAGE_PIN <pin> [get_ports {ch1_txp[0]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch1_txn[0]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch1_txp[1]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch1_txn[1]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch1_txp[2]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch1_txn[2]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch1_txp[3]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch1_txn[3]}]

## Channel 1 RX
# set_property PACKAGE_PIN <pin> [get_ports {ch1_rxp[0]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch1_rxn[0]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch1_rxp[1]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch1_rxn[1]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch1_rxp[2]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch1_rxn[2]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch1_rxp[3]}]
# set_property PACKAGE_PIN <pin> [get_ports {ch1_rxn[3]}]

###############################################################################
## GT Quad Location Constraints
##
## Constrain the GT Common (QPLL) instances to specific GT quads.
## Channel 0 -> GTHQ0, Channel 1 -> GTHQ1.
## These ensure the GTHE2_COMMON primitives are placed correctly.
###############################################################################
# set_property LOC GTHE2_COMMON_X0Y0 [get_cells u_clock_module/gt_common_ch0/gthe2_common_inst]
# set_property LOC GTHE2_COMMON_X0Y1 [get_cells u_clock_module/gt_common_ch1/gthe2_common_inst]

###############################################################################
## False Path Constraints
##
## Cross-domain signals that don't need timing analysis.
###############################################################################
set_false_path -from [get_ports sys_rst_n]

## False paths for reset synchronizers
set_false_path -to [get_pins -hierarchical -filter {NAME =~ *reset_sync*/D}]

###############################################################################
## Max Delay Constraints
##
## Limit delay on status signals crossing between clock domains.
###############################################################################
# set_max_delay -datapath_only 5.0 -from [get_cells -hierarchical -filter {NAME =~ *channel_up*}]

###############################################################################
## Clock Domain Crossing Constraints
##
## The init_clk and user_clk are asynchronous to each other.
###############################################################################
# set_clock_groups -asynchronous -group [get_clocks init_clk] -group [get_clocks -of_objects [get_pins u_clock_module/bufg_user_clk_inst/O]]
