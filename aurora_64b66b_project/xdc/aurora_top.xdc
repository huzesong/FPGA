##############################################################################
## Constraints file for Aurora 64B66B Dual Channel Design
## Target: xc7vx690tffg1927-2L
## Aurora IP: Aurora 64B66B (11.2) - Framing mode, 10 Gbps, 4 lanes
## Two channels on adjacent GT quads sharing reference clock
##############################################################################

##############################################################################
## Clock Constraints
##############################################################################

# GT Reference Clock - 156.25 MHz
set_property PACKAGE_PIN AK8 [get_ports gt_refclk_p]
set_property PACKAGE_PIN AK7 [get_ports gt_refclk_n]
create_clock -period 6.400 -name gt_refclk [get_ports gt_refclk_p]

# System Clock - 50 MHz
set_property PACKAGE_PIN H19 [get_ports sys_clk_p]
set_property PACKAGE_PIN G18 [get_ports sys_clk_n]
set_property IOSTANDARD LVDS [get_ports sys_clk_p]
set_property IOSTANDARD LVDS [get_ports sys_clk_n]
create_clock -period 20.000 -name sys_clk [get_ports sys_clk_p]

##############################################################################
## System Reset
##############################################################################
set_property PACKAGE_PIN AR13 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS18 [get_ports sys_rst_n]

##############################################################################
## Channel 0 - GT Quad 0 (GTHQ0)
##############################################################################

# Channel 0 TX
set_property PACKAGE_PIN AM5 [get_ports {ch0_txp[0]}]
set_property PACKAGE_PIN AM4 [get_ports {ch0_txn[0]}]
set_property PACKAGE_PIN AN3 [get_ports {ch0_txp[1]}]
set_property PACKAGE_PIN AN2 [get_ports {ch0_txn[1]}]
set_property PACKAGE_PIN AP5 [get_ports {ch0_txp[2]}]
set_property PACKAGE_PIN AP4 [get_ports {ch0_txn[2]}]
set_property PACKAGE_PIN AR3 [get_ports {ch0_txp[3]}]
set_property PACKAGE_PIN AR2 [get_ports {ch0_txn[3]}]

# Channel 0 RX
set_property PACKAGE_PIN AM9 [get_ports {ch0_rxp[0]}]
set_property PACKAGE_PIN AM8 [get_ports {ch0_rxn[0]}]
set_property PACKAGE_PIN AN7 [get_ports {ch0_rxp[1]}]
set_property PACKAGE_PIN AN6 [get_ports {ch0_rxn[1]}]
set_property PACKAGE_PIN AP9 [get_ports {ch0_rxp[2]}]
set_property PACKAGE_PIN AP8 [get_ports {ch0_rxn[2]}]
set_property PACKAGE_PIN AR7 [get_ports {ch0_rxp[3]}]
set_property PACKAGE_PIN AR6 [get_ports {ch0_rxn[3]}]

##############################################################################
## Channel 1 - GT Quad 1 (GTHQ1, adjacent to GTHQ0)
##############################################################################

# Channel 1 TX
set_property PACKAGE_PIN AJ5 [get_ports {ch1_txp[0]}]
set_property PACKAGE_PIN AJ4 [get_ports {ch1_txn[0]}]
set_property PACKAGE_PIN AK3 [get_ports {ch1_txp[1]}]
set_property PACKAGE_PIN AK2 [get_ports {ch1_txn[1]}]
set_property PACKAGE_PIN AL5 [get_ports {ch1_txp[2]}]
set_property PACKAGE_PIN AL4 [get_ports {ch1_txn[2]}]
set_property PACKAGE_PIN AM3 [get_ports {ch1_txp[3]}]
set_property PACKAGE_PIN AM2 [get_ports {ch1_txn[3]}]

# Channel 1 RX
set_property PACKAGE_PIN AJ9 [get_ports {ch1_rxp[0]}]
set_property PACKAGE_PIN AJ8 [get_ports {ch1_rxn[0]}]
set_property PACKAGE_PIN AK5 [get_ports {ch1_rxp[1]}]
set_property PACKAGE_PIN AK4 [get_ports {ch1_rxn[1]}]
set_property PACKAGE_PIN AL9 [get_ports {ch1_rxp[2]}]
set_property PACKAGE_PIN AL8 [get_ports {ch1_rxn[2]}]
set_property PACKAGE_PIN AM7 [get_ports {ch1_rxp[3]}]
set_property PACKAGE_PIN AM6 [get_ports {ch1_rxn[3]}]

##############################################################################
## Status LEDs
##############################################################################
set_property PACKAGE_PIN AP12 [get_ports {channel_up[0]}]
set_property PACKAGE_PIN AN12 [get_ports {channel_up[1]}]
set_property PACKAGE_PIN AM12 [get_ports {error_flag[0]}]
set_property PACKAGE_PIN AL12 [get_ports {error_flag[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {channel_up[*]}]
set_property IOSTANDARD LVCMOS18 [get_ports {error_flag[*]}]

##############################################################################
## Clock Domain Crossings
##############################################################################
set_false_path -to [get_pins -hierarchical -filter {NAME =~ */rst_sync_r1*/D}]
set_false_path -to [get_pins -hierarchical -filter {NAME =~ */rst_sync_r2*/D}]

##############################################################################
## Timing Exceptions
##############################################################################
# User clock generated from Aurora tx_out_clk
create_generated_clock -name user_clk -source [get_pins u_clock_module/u_bufg_user_clk/I] \
    -divide_by 1 [get_pins u_clock_module/u_bufg_user_clk/O]

set_clock_groups -asynchronous \
    -group [get_clocks sys_clk] \
    -group [get_clocks gt_refclk] \
    -group [get_clocks user_clk]
