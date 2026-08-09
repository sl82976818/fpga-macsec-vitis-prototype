# SPDX-License-Identifier: BSD-2-Clause-Views
# Base constraints derived from the Corundum FPGA NIC project
# (fpga/mqnic/Nexus_K3P_S/fpga_25g/fpga_k35.xdc).
# Copyright (c) 2019-2023 The Regents of the University of California
#
# Modified by Le Sun, 2026 for the FPGA AES-GCM / experimental MACsec prototype.
# Modifications Copyright (c) 2026 Le Sun.
# Changes: MACsec GMAC pblock + async clock groups (see
#          patches/corundum/fpga_k35_xdc_macsec.patch).
#
# XDC constraints for the Cisco Nexus K35-S
# part: xcku035-fbva676-2-e

# General configuration
set_property CFGBVS GND [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS true [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN Pullup [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
set_property BITSTREAM.CONFIG.BPI_SYNC_MODE Type2 [current_design]
set_property CONFIG_MODE BPI16 [current_design]
set_property BITSTREAM.CONFIG.OVERTEMPSHUTDOWN Enable [current_design]

# 100 MHz system clock
set_property -dict {LOC AK17 IOSTANDARD LVDS} [get_ports clk_300mhz_p]
set_property -dict {LOC AK16 IOSTANDARD LVDS} [get_ports clk_300mhz_n]
create_clock -period 3.333 -name clk_300mhz_p [get_ports clk_300mhz_p]

#SW-N
set_property -dict {LOC AD10 IOSTANDARD LVCMOS18} [get_ports reset]
# LEDs


# GPIO
#set_property -dict {LOC W26  IOSTANDARD LVCMOS18} [get_ports gpio[0]]
#set_property -dict {LOC Y26  IOSTANDARD LVCMOS18} [get_ports gpio[1]]
#set_property -dict {LOC AB26 IOSTANDARD LVCMOS18} [get_ports gpio[2]]
#set_property -dict {LOC AC26 IOSTANDARD LVCMOS18} [get_ports gpio[3]]

# SMA  TO FMC


# SFP+ Interfaces   TO  KCU105
set_property -dict {LOC T2} [get_ports sfp0_rx_p]
set_property -dict {LOC T1} [get_ports sfp0_rx_n]
set_property -dict {LOC U4} [get_ports sfp0_tx_p]
set_property -dict {LOC U3} [get_ports sfp0_tx_n]
#set_property -dict {LOC V2} [get_ports sfp1_rx_p]
#set_property -dict {LOC V1} [get_ports sfp1_rx_n]
#set_property -dict {LOC W4} [get_ports sfp1_tx_p]
#set_property -dict {LOC W3} [get_ports sfp1_tx_n]

#si570  -- 156.25MHz
#set_property -dict {LOC P6} [get_ports sfp_mgt_refclk_0_p]
#set_property -dict {LOC P5} [get_ports sfp_mgt_refclk_0_n]
#SMA  -- 163.5MHz
set_property -dict {LOC V6} [get_ports sfp_mgt_refclk_0_p]
set_property -dict {LOC V5} [get_ports sfp_mgt_refclk_0_n]


set_property -dict {LOC D23 IOSTANDARD LVDS} [get_ports gtrefclk_out_p]
set_property -dict {LOC C23 IOSTANDARD LVDS} [get_ports gtrefclk_out_n]

#set_property -dict {LOC AL8 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports sfp_1_tx_disable]
#set_property -dict {LOC D28 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports sfp_2_tx_disable]

# 156.25MHz MGT reference clock
create_clock -period 6.400 -name sfp_mgt_refclk [get_ports sfp_mgt_refclk_0_p]
#SMA  -- 163.5MHz
#create_clock -period 6.116 -name sfp_mgt_refclk [get_ports sfp_mgt_refclk_0_p]
#led
set_property -dict {LOC AP8 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports sfp_1_led]
set_property -dict {LOC H23 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports sfp_2_led]
set_property -dict {LOC P20 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports mmcm_locked_led]
set_property -dict {LOC P21 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports pcie_lnk_up_led]
set_property -dict {LOC N22 IOSTANDARD LVCMOS18 SLEW SLOW DRIVE 12} [get_ports clk_100mhz_ibufg_led]




# PCIe Interface
#set_property -dict {LOC P2  } [get_ports {pcie_rx_p[0]}] ;# MGTHRXP3_225 GTHE3_CHANNEL_X0Y7 / GTHE3_COMMON_X0Y1
#set_property -dict {LOC P1  } [get_ports {pcie_rx_n[0]}] ;# MGTHRXN3_225 GTHE3_CHANNEL_X0Y7 / GTHE3_COMMON_X0Y1
#set_property -dict {LOC R4  } [get_ports {pcie_tx_p[0]}] ;# MGTHTXP3_225 GTHE3_CHANNEL_X0Y7 / GTHE3_COMMON_X0Y1
#set_property -dict {LOC R3  } [get_ports {pcie_tx_n[0]}] ;# MGTHTXN3_225 GTHE3_CHANNEL_X0Y7 / GTHE3_COMMON_X0Y1
#set_property -dict {LOC T2  } [get_ports {pcie_rx_p[1]}] ;# MGTHRXP2_225 GTHE3_CHANNEL_X0Y6 / GTHE3_COMMON_X0Y1
#set_property -dict {LOC T1  } [get_ports {pcie_rx_n[1]}] ;# MGTHRXN2_225 GTHE3_CHANNEL_X0Y6 / GTHE3_COMMON_X0Y1
#set_property -dict {LOC U4  } [get_ports {pcie_tx_p[1]}] ;# MGTHTXP2_225 GTHE3_CHANNEL_X0Y6 / GTHE3_COMMON_X0Y1
#set_property -dict {LOC U3  } [get_ports {pcie_tx_n[1]}] ;# MGTHTXN2_225 GTHE3_CHANNEL_X0Y6 / GTHE3_COMMON_X0Y1
#set_property -dict {LOC V2  } [get_ports {pcie_rx_p[2]}] ;# MGTHRXP1_225 GTHE3_CHANNEL_X0Y5 / GTHE3_COMMON_X0Y1
#set_property -dict {LOC V1  } [get_ports {pcie_rx_n[2]}] ;# MGTHRXN1_225 GTHE3_CHANNEL_X0Y5 / GTHE3_COMMON_X0Y1
#set_property -dict {LOC W4  } [get_ports {pcie_tx_p[2]}] ;# MGTHTXP1_225 GTHE3_CHANNEL_X0Y5 / GTHE3_COMMON_X0Y1
#set_property -dict {LOC W3  } [get_ports {pcie_tx_n[2]}] ;# MGTHTXN1_225 GTHE3_CHANNEL_X0Y5 / GTHE3_COMMON_X0Y1
#set_property -dict {LOC Y2  } [get_ports {pcie_rx_p[3]}] ;# MGTHRXP0_225 GTHE3_CHANNEL_X0Y4 / GTHE3_COMMON_X0Y1
#set_property -dict {LOC Y1  } [get_ports {pcie_rx_n[3]}] ;# MGTHRXN0_225 GTHE3_CHANNEL_X0Y4 / GTHE3_COMMON_X0Y1
#set_property -dict {LOC AA4 } [get_ports {pcie_tx_p[3]}] ;# MGTHTXP0_225 GTHE3_CHANNEL_X0Y4 / GTHE3_COMMON_X0Y1
#set_property -dict {LOC AA3 } [get_ports {pcie_tx_n[3]}] ;# MGTHTXN0_225 GTHE3_CHANNEL_X0Y4 / GTHE3_COMMON_X0Y1
#set_property -dict {LOC AB2 } [get_ports {pcie_rx_p[4]}] ;# MGTHRXP3_224 GTHE3_CHANNEL_X0Y3 / GTHE3_COMMON_X0Y0
#set_property -dict {LOC AB1 } [get_ports {pcie_rx_n[4]}] ;# MGTHRXN3_224 GTHE3_CHANNEL_X0Y3 / GTHE3_COMMON_X0Y0
#set_property -dict {LOC AB6 } [get_ports {pcie_tx_p[4]}] ;# MGTHTXP3_224 GTHE3_CHANNEL_X0Y3 / GTHE3_COMMON_X0Y0
#set_property -dict {LOC AB5 } [get_ports {pcie_tx_n[4]}] ;# MGTHTXN3_224 GTHE3_CHANNEL_X0Y3 / GTHE3_COMMON_X0Y0
#set_property -dict {LOC AD2 } [get_ports {pcie_rx_p[5]}] ;# MGTHRXP2_224 GTHE3_CHANNEL_X0Y2 / GTHE3_COMMON_X0Y0
#set_property -dict {LOC AD1 } [get_ports {pcie_rx_n[5]}] ;# MGTHRXN2_224 GTHE3_CHANNEL_X0Y2 / GTHE3_COMMON_X0Y0
#set_property -dict {LOC AC4 } [get_ports {pcie_tx_p[5]}] ;# MGTHTXP2_224 GTHE3_CHANNEL_X0Y2 / GTHE3_COMMON_X0Y0
#set_property -dict {LOC AC3 } [get_ports {pcie_tx_n[5]}] ;# MGTHTXN2_224 GTHE3_CHANNEL_X0Y2 / GTHE3_COMMON_X0Y0
#set_property -dict {LOC AE4 } [get_ports {pcie_rx_p[6]}] ;# MGTHRXP1_224 GTHE3_CHANNEL_X0Y1 / GTHE3_COMMON_X0Y0
#set_property -dict {LOC AE3 } [get_ports {pcie_rx_n[6]}] ;# MGTHRXN1_224 GTHE3_CHANNEL_X0Y1 / GTHE3_COMMON_X0Y0
#set_property -dict {LOC AD6 } [get_ports {pcie_tx_p[6]}] ;# MGTHTXP1_224 GTHE3_CHANNEL_X0Y1 / GTHE3_COMMON_X0Y0
#set_property -dict {LOC AD5 } [get_ports {pcie_tx_n[6]}] ;# MGTHTXN1_224 GTHE3_CHANNEL_X0Y1 / GTHE3_COMMON_X0Y0
#set_property -dict {LOC AF2 } [get_ports {pcie_rx_p[7]}] ;# MGTHRXP0_224 GTHE3_CHANNEL_X0Y0 / GTHE3_COMMON_X0Y0
#set_property -dict {LOC AF1 } [get_ports {pcie_rx_n[7]}] ;# MGTHRXN0_224 GTHE3_CHANNEL_X0Y0 / GTHE3_COMMON_X0Y0
#set_property -dict {LOC AF6 } [get_ports {pcie_tx_p[7]}] ;# MGTHTXP0_224 GTHE3_CHANNEL_X0Y0 / GTHE3_COMMON_X0Y0
#set_property -dict {LOC AF5 } [get_ports {pcie_tx_n[7]}] ;# MGTHTXN0_224 GTHE3_CHANNEL_X0Y0 / GTHE3_COMMON_X0Y0
set_property -dict {LOC AB6} [get_ports pcie_mgt_refclk_p]
set_property -dict {LOC AB5} [get_ports pcie_mgt_refclk_n]
#set_property LOC PCIE_3_1_X0Y0 [get_cells pcie3_ultrascale_inst/inst/pcie3_ultrascale_0_pcie3_uscale_top_inst/pcie3_uscale_wrapper_inst/PCIE_3_1_inst]
set_property LOC PCIE_3_1_X0Y0 [get_cells pcie3_ultrascale_inst/inst/pcie3_ultrascale_0_pcie3_uscale_top_inst/pcie3_uscale_wrapper_inst/PCIE_3_1_inst]
set_property PACKAGE_PIN K22 [get_ports pcie_reset_n]
set_property PULLUP true [get_ports pcie_reset_n]

# 100 MHz MGT reference clock
create_clock -period 10.000 -name pcie_mgt_refclk [get_ports pcie_mgt_refclk_p]

set_false_path -from [get_ports pcie_reset_n]
set_input_delay 0.000 [get_ports pcie_reset_n]

# BPI flash


set_property IOSTANDARD LVCMOS18 [get_ports pcie_reset_n]



set_property PACKAGE_PIN AP10 [get_ports i2c_rst_n]
set_property PACKAGE_PIN J24 [get_ports i2c_scl]
set_property PACKAGE_PIN J25 [get_ports i2c_sda]
set_property IOSTANDARD LVCMOS18 [get_ports i2c_rst_n]
set_property IOSTANDARD LVCMOS18 [get_ports i2c_scl]
set_property IOSTANDARD LVCMOS18 [get_ports i2c_sda]

#set_false_path -from [get_clocks -of_objects [get_pins sfp_phy_quad_inst/phy1.eth_xcvr_phy_1/phy_inst/eth_phy_10g_rx_inst/clkrxphy/inst/mmcme3_adv_inst/CLKOUT0]] -to [get_clocks -of_objects [get_pins sfp_phy_quad_inst/phy1.eth_xcvr_phy_1/xcvr_gth_com_usp.eth_xcvr_gth_full_inst/inst/gen_gtwizard_gthe3_top.eth_xcvr_gth_full_gtwizard_gthe3_inst/gen_gtwizard_gthe3.gen_rx_user_clocking_internal.gen_single_instance.gtwiz_userclk_rx_inst/gen_gtwiz_userclk_rx_main.bufg_gt_usrclk2_inst/O]]
#set_false_path -from [get_clocks -of_objects [get_pins sfp_phy_quad_inst/phy1.eth_xcvr_phy_1/phy_inst/eth_phy_10g_tx_inst/clktxphy/inst/mmcme3_adv_inst/CLKOUT0]] -to [get_clocks -of_objects [get_pins sfp_phy_quad_inst/phy1.eth_xcvr_phy_1/xcvr_gth_com_usp.eth_xcvr_gth_full_inst/inst/gen_gtwizard_gthe3_top.eth_xcvr_gth_full_gtwizard_gthe3_inst/gen_gtwizard_gthe3.gen_tx_user_clocking_internal.gen_single_instance.gtwiz_userclk_tx_inst/gen_gtwiz_userclk_tx_main.bufg_gt_usrclk2_inst/O]]

#set_false_path -from [get_clocks -of_objects [get_pins sfp_phy_quad_inst/phy1.eth_xcvr_phy_1/xcvr_gth_com_usp.eth_xcvr_gth_full_inst/inst/gen_gtwizard_gthe3_top.eth_xcvr_gth_full_gtwizard_gthe3_inst/gen_gtwizard_gthe3.gen_rx_user_clocking_internal.gen_single_instance.gtwiz_userclk_rx_inst/gen_gtwiz_userclk_rx_main.bufg_gt_usrclk2_inst/O]] -to [get_clocks -of_objects [get_pins sfp_phy_quad_inst/phy1.eth_xcvr_phy_1/phy_inst/eth_phy_10g_rx_inst/clkrxphy/inst/mmcme3_adv_inst/CLKOUT0]]
#set_false_path -from [get_clocks -of_objects [get_pins sfp_phy_quad_inst/phy1.eth_xcvr_phy_1/xcvr_gth_com_usp.eth_xcvr_gth_full_inst/inst/gen_gtwizard_gthe3_top.eth_xcvr_gth_full_gtwizard_gthe3_inst/gen_gtwizard_gthe3.gen_tx_user_clocking_internal.gen_single_instance.gtwiz_userclk_tx_inst/gen_gtwiz_userclk_tx_main.bufg_gt_usrclk2_inst/O]] -to [get_clocks -of_objects [get_pins sfp_phy_quad_inst/phy1.eth_xcvr_phy_1/phy_inst/eth_phy_10g_tx_inst/clktxphy/inst/mmcme3_adv_inst/CLKOUT0]]

# Disable legacy interface pblock; it is currently constraining several
# pcie_user_clk critical paths (event_fifo -> cqm BRAM) and reducing placer freedom.
delete_pblocks [get_pblocks -quiet pblock_1]

# SFP TX/RX recovered clocks are asynchronous to PCIe user clock.
# CDC is handled in logic/FIFOs; these paths must not be timed as synchronous.
set_clock_groups -asynchronous -group [get_clocks -quiet pcie_user_clk] -group [get_clocks -quiet {sfp0_rx_clk_int sfp0_tx_clk_int}]

# SFP recovered RX/TX clocks are independent recovered domains; do not time
# direct crossings as synchronous paths.
set_clock_groups -asynchronous \
    -group [get_clocks -quiet sfp0_rx_clk_int] \
    -group [get_clocks -quiet sfp0_tx_clk_int]

# --------------------------------------------------------------------------
# Timing closure assists for current critical regions
# --------------------------------------------------------------------------

# --------------------------------------------------------------------------
# R4 timing partition cleanup
# --------------------------------------------------------------------------
# 1) clk_out2_clk_wiz_0 (125/156 domain) is asynchronous to recovered SFP
#    TX/RX clocks. Without this, FIFO reset/control crossings are timed as
#    synchronous setup paths and create artificial violations.
set_clock_groups -asynchronous \
    -group [get_clocks -quiet clk_out2_clk_wiz_0] \
    -group [get_clocks -quiet {sfp0_rx_clk_int sfp0_tx_clk_int}]

# 2) Disable legacy MACsec pblock constraints that were causing overlap/
#    over-utilization and long detours in timing-critical paths.
delete_pblocks [get_pblocks -quiet pblock_macsec_gmac]
delete_pblocks [get_pblocks -quiet pblock_macsec_rx]
