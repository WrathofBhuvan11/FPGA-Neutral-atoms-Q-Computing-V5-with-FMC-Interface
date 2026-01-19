#################################################################################
# XDC Constraints for datastream_preprocessor 
# Target: Xilinx Zynq UltraScale+ XCZU7EV-2FFVC1156 (ZCU106 Board)
# Application: FMC-200A Camera Link -> Quantum State Detection

#################################################################################
# PART 1: DEVICE CONFIGURATION
#################################################################################
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 85.0 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]

#################################################################################
# PART 2: CLOCK CONSTRAINTS - TIMING-17 COMPLIANT
#################################################################################

#------------------------------------------------------------------------------
# 1. PRIMARY INPUT CLOCK (85 MHz Differential LVDS from Camera)
#------------------------------------------------------------------------------
create_clock -period 11.764 -name fmc_clk_in [get_ports i_fmc_clk_p]
set_input_jitter fmc_clk_in 0.100

#------------------------------------------------------------------------------
# 2. BUFFERED 85 MHz (IBUFGDS -> BUFG output)
#------------------------------------------------------------------------------
create_generated_clock -name clk_85_buffered \
    -source [get_ports i_fmc_clk_p] \
    -multiply_by 1 \
    [get_pins bufg_85_inst/O]

#------------------------------------------------------------------------------
# 3. MMCM FEEDBACK CLOCK (CRITICAL for Timing-17)
#------------------------------------------------------------------------------
create_generated_clock -name clk_fb \
    -source [get_pins mmcm_inst/CLKFBIN] \
    -multiply_by 12 \
    -master_clock clk_85_buffered \
    [get_pins mmcm_inst/CLKFBOUT]

#------------------------------------------------------------------------------
# 4. 340 MHz SERIAL CLOCK (MMCM CLKOUT0 - Unbuffered)
#------------------------------------------------------------------------------
create_generated_clock -name clk_serial_340 \
    -source [get_pins mmcm_inst/CLKFBIN] \
    -multiply_by 12 -divide_by 3 \
    -master_clock clk_85_buffered \
    [get_pins mmcm_inst/CLKOUT0]

#------------------------------------------------------------------------------
# 5. 340 MHz INVERTED CLOCK (MMCM CLKOUT0B with 180 degree phase shift)
#------------------------------------------------------------------------------
# 5A. Unbuffered output from MMCM
create_generated_clock -name clk_340_inv_unbuf \
    -source [get_pins mmcm_inst/CLKFBIN] \
    -edges {1 2 3} \
    -edge_shift {0.000 1.471 2.941} \
    -master_clock clk_85_buffered \
    [get_pins mmcm_inst/CLKOUT0B]

# 5B. Buffered through BUFG (drives ISERDES CLK_B)
create_generated_clock -name clk_340_inv \
    -source [get_pins mmcm_inst/CLKOUT0B] \
    -multiply_by 1 \
    [get_pins bufg_340_inv_inst/O]

#------------------------------------------------------------------------------
# 6. 510 MHz SYSTEM CLOCK (MMCM CLKOUT1 - Main Processing Clock)
#------------------------------------------------------------------------------
# 6A. Unbuffered output from MMCM
create_generated_clock -name clk_sys_510_unbuf \
    -source [get_pins mmcm_inst/CLKFBIN] \
    -multiply_by 12 -divide_by 2 \
    -master_clock clk_85_buffered \
    [get_pins mmcm_inst/CLKOUT1]

# 6B. Buffered through BUFG (drives all 510 MHz logic)
create_generated_clock -name clk_sys_510 \
    -source [get_pins mmcm_inst/CLKOUT1] \
    -multiply_by 1 \
    [get_pins bufg_510_inst/O]

#------------------------------------------------------------------------------
# 7. CLOCK UNCERTAINTY
#------------------------------------------------------------------------------
set_clock_uncertainty 0.200 [get_clocks fmc_clk_in]
set_clock_uncertainty 0.080 [get_clocks {clk_85_buffered}]
set_clock_uncertainty 0.050 [get_clocks {clk_fb}]
set_clock_uncertainty 0.040 [get_clocks {clk_serial_340 clk_340_inv*}]
set_clock_uncertainty 0.050 [get_clocks {clk_sys_510*}]

#------------------------------------------------------------------------------
# 8. CLOCK DOMAIN GROUPS (TIMING-17 COMPLIANT)
#------------------------------------------------------------------------------
# fmc_clk_in and clk_85_buffered are the SAME clock (just buffered)
# Separates:
# - Group 1: Input clock + buffered version (85 MHz - SAME CLOCK!)
# - Group 2: 340 MHz serial capture domain (ISERDES CLK/CLK_B only, no user logic)
# - Group 3: 510 MHz system processing domain (async FIFO CDC in fmc_receiver.sv)
#
# This suppresses false hold paths from fmc_clk_in -> clk_340 while preserving
# proper timing analysis for fmc_clk_in -> clk_85_buffered (same clock).

set_clock_groups -asynchronous \
    -group {fmc_clk_in clk_85_buffered} \
    -group [get_clocks -filter {NAME =~ *340*}] \
    -group [get_clocks -filter {NAME =~ *510*}]

# MMCM feedback clock is physically exclusive with outputs
set_clock_groups -physically_exclusive \
    -group {clk_fb} \
    -group {clk_serial_340 clk_340_inv_unbuf clk_sys_510_unbuf}

#################################################################################
# PART 3: I/O STANDARDS & ELECTRICAL PROPERTIES
#################################################################################

# --- FMC CAMERA INTERFACE (LVDS 1.8V with Termination) ---
set_property IOSTANDARD LVDS [get_ports i_fmc_clk_p]
set_property IOSTANDARD LVDS [get_ports i_fmc_clk_n]
set_property DIFF_TERM TRUE [get_ports i_fmc_clk_p]
set_property DIFF_TERM TRUE [get_ports i_fmc_clk_n]

set_property IOSTANDARD LVDS [get_ports {i_fmc_lvds_in_p[*]}]
set_property IOSTANDARD LVDS [get_ports {i_fmc_lvds_in_n[*]}]
set_property DIFF_TERM TRUE [get_ports {i_fmc_lvds_in_p[*]}]
set_property DIFF_TERM TRUE [get_ports {i_fmc_lvds_in_n[*]}]

# IDELAYCTRL and IDELAY configuration
set_property IODELAY_GROUP idelay_grp [get_cells idelayctrl_inst]
set_property IODELAY_GROUP idelay_grp [get_cells -hier -filter {REF_NAME == simple_iserdes_8to1 || ORIG_REF_NAME == simple_iserdes_8to1}]

# --- RESET (LVCMOS18 with Pull-up) ---
set_property IOSTANDARD LVCMOS18 [get_ports i_rst_n]
set_property PULLUP TRUE [get_ports i_rst_n]

# --- SPI INTERFACE (LVCMOS18) ---
set_property IOSTANDARD LVCMOS18 [get_ports o_spi_sclk]
set_property IOSTANDARD LVCMOS18 [get_ports o_spi_mosi]
set_property IOSTANDARD LVCMOS18 [get_ports i_spi_miso]
set_property IOSTANDARD LVCMOS18 [get_ports o_spi_ss]
set_property SLEW FAST [get_ports o_spi_sclk]
set_property SLEW FAST [get_ports o_spi_mosi]
set_property SLEW FAST [get_ports o_spi_ss]
set_property DRIVE 8 [get_ports o_spi_sclk]
set_property DRIVE 8 [get_ports o_spi_mosi]
set_property DRIVE 8 [get_ports o_spi_ss]


# --- USER LEDS (LVCMOS12 - Bank 66 @ 1.2V on ZCU106) ---
set_property IOSTANDARD LVCMOS12 [get_ports {o_qubit_state[*]}]
set_property IOSTANDARD LVCMOS12 [get_ports o_qubit_valid]
set_property DRIVE 8 [get_ports {o_qubit_state[*]}]
set_property DRIVE 8 [get_ports o_qubit_valid]
set_property SLEW SLOW [get_ports {o_qubit_state[*]}]
set_property SLEW SLOW [get_ports o_qubit_valid]

# --- PMOD DEBUG OUTPUTS (LVCMOS12 - Bank 66 @ 1.2V) ---
set_property IOSTANDARD LVCMOS12 [get_ports {o_qubit_base_id[*]}]
set_property SLEW FAST [get_ports {o_qubit_base_id[*]}]
set_property DRIVE 8 [get_ports {o_qubit_base_id[*]}]

#################################################################################
# PART 4: PHYSICAL PIN ASSIGNMENTS
#################################################################################

# --- CAMERA CLOCK (Differential Pair) ---
set_property PACKAGE_PIN D23 [get_ports i_fmc_clk_p]
set_property PACKAGE_PIN C23 [get_ports i_fmc_clk_n]

# Allow fabric routing for non-GCIO clock input
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets clk_buf_inst/O]

# --- CAMERA DATA LANES (11 Differential Pairs) ---
set_property PACKAGE_PIN F22 [get_ports {i_fmc_lvds_in_p[0]}]
set_property PACKAGE_PIN E22 [get_ports {i_fmc_lvds_in_n[0]}]
set_property PACKAGE_PIN H22 [get_ports {i_fmc_lvds_in_p[1]}]
set_property PACKAGE_PIN G22 [get_ports {i_fmc_lvds_in_n[1]}]
set_property PACKAGE_PIN K21 [get_ports {i_fmc_lvds_in_p[2]}]
set_property PACKAGE_PIN J21 [get_ports {i_fmc_lvds_in_n[2]}]
set_property PACKAGE_PIN M22 [get_ports {i_fmc_lvds_in_p[3]}]
set_property PACKAGE_PIN L22 [get_ports {i_fmc_lvds_in_n[3]}]
set_property PACKAGE_PIN N22 [get_ports {i_fmc_lvds_in_p[4]}]
set_property PACKAGE_PIN N23 [get_ports {i_fmc_lvds_in_n[4]}]
set_property PACKAGE_PIN P21 [get_ports {i_fmc_lvds_in_p[5]}]
set_property PACKAGE_PIN P22 [get_ports {i_fmc_lvds_in_n[5]}]
set_property PACKAGE_PIN R21 [get_ports {i_fmc_lvds_in_p[6]}]
set_property PACKAGE_PIN R22 [get_ports {i_fmc_lvds_in_n[6]}]
set_property PACKAGE_PIN T23 [get_ports {i_fmc_lvds_in_p[7]}]
set_property PACKAGE_PIN T24 [get_ports {i_fmc_lvds_in_n[7]}]
set_property PACKAGE_PIN U22 [get_ports {i_fmc_lvds_in_p[8]}]
set_property PACKAGE_PIN U23 [get_ports {i_fmc_lvds_in_n[8]}]
set_property PACKAGE_PIN V23 [get_ports {i_fmc_lvds_in_p[9]}]
set_property PACKAGE_PIN V24 [get_ports {i_fmc_lvds_in_n[9]}]
set_property PACKAGE_PIN W23 [get_ports {i_fmc_lvds_in_p[10]}]
set_property PACKAGE_PIN W24 [get_ports {i_fmc_lvds_in_n[10]}]

# --- RESET INPUT ---
set_property PACKAGE_PIN E23 [get_ports i_rst_n]

# --- SPI CONFIGURATION INTERFACE ---
set_property PACKAGE_PIN AA22 [get_ports o_spi_sclk]
set_property PACKAGE_PIN AB22 [get_ports o_spi_mosi]
set_property PACKAGE_PIN AC22 [get_ports i_spi_miso]
set_property PACKAGE_PIN AD22 [get_ports o_spi_ss]

# --- USER LEDs (Quantum State Display - Bank 66) ---
set_property PACKAGE_PIN AL11 [get_ports {o_qubit_state[0]}]
set_property PACKAGE_PIN AL13 [get_ports {o_qubit_state[1]}]
set_property PACKAGE_PIN AK13 [get_ports {o_qubit_state[2]}]
set_property PACKAGE_PIN AE15 [get_ports {o_qubit_state[3]}]
set_property PACKAGE_PIN AM8  [get_ports o_qubit_valid]

# --- PMOD1 (J87) Debug Outputs (Qubit Base ID - Bank 66) ---
set_property PACKAGE_PIN AN8  [get_ports {o_qubit_base_id[0]}]
set_property PACKAGE_PIN AN9  [get_ports {o_qubit_base_id[1]}]
set_property PACKAGE_PIN AP11 [get_ports {o_qubit_base_id[2]}]
set_property PACKAGE_PIN AN11 [get_ports {o_qubit_base_id[3]}]
set_property PACKAGE_PIN AP9  [get_ports {o_qubit_base_id[4]}]
set_property PACKAGE_PIN AP10 [get_ports {o_qubit_base_id[5]}]
set_property PACKAGE_PIN AP12 [get_ports {o_qubit_base_id[6]}]

#################################################################################
# PART 5: INPUT/OUTPUT TIMING CONSTRAINTS
#################################################################################

# --- CAMERA DATA INPUTS (Source-Synchronous to fmc_clk_in) ---
# Rising edge capture
set_input_delay -clock fmc_clk_in -max 1.5 [get_ports {i_fmc_lvds_in_p[*]}]
set_input_delay -clock fmc_clk_in -min -1.0 [get_ports {i_fmc_lvds_in_p[*]}]
set_input_delay -clock fmc_clk_in -max 1.5 [get_ports {i_fmc_lvds_in_n[*]}]
set_input_delay -clock fmc_clk_in -min -1.0 [get_ports {i_fmc_lvds_in_n[*]}]

# Falling edge capture (DDR sampling)
set_input_delay -clock fmc_clk_in -max 1.5 -clock_fall -add_delay [get_ports {i_fmc_lvds_in_p[*]}]
set_input_delay -clock fmc_clk_in -min -1.0 -clock_fall -add_delay [get_ports {i_fmc_lvds_in_p[*]}]
set_input_delay -clock fmc_clk_in -max 1.5 -clock_fall -add_delay [get_ports {i_fmc_lvds_in_n[*]}]
set_input_delay -clock fmc_clk_in -min -1.0 -clock_fall -add_delay [get_ports {i_fmc_lvds_in_n[*]}]

# --- RESET INPUT (Asynchronous - False path declared later) ---
set_input_delay -clock clk_85_buffered -max 5.0 [get_ports i_rst_n]
set_input_delay -clock clk_85_buffered -min 0.0 [get_ports i_rst_n]

#------------------------------------------------------------------------------
# --- SPI INTERFACE TIMING ( Match Actual SPI Clock Divider) ---
#------------------------------------------------------------------------------
# RTL generates SPI clock at 510 MHz / 26 = 19.6 MHz (period = 51 ns)
# These outputs change slowly relative to 510 MHz system clock
# Relaxed constraints to match actual slow SPI timing

set_output_delay -clock clk_sys_510 -max 10.0 [get_ports o_spi_sclk]
set_output_delay -clock clk_sys_510 -min -2.0 [get_ports o_spi_sclk]
set_output_delay -clock clk_sys_510 -max 10.0 [get_ports o_spi_mosi]
set_output_delay -clock clk_sys_510 -min -2.0 [get_ports o_spi_mosi]
set_output_delay -clock clk_sys_510 -max 10.0 [get_ports o_spi_ss]
set_output_delay -clock clk_sys_510 -min -2.0 [get_ports o_spi_ss]
set_input_delay -clock clk_sys_510 -max 15.0 [get_ports i_spi_miso]
set_input_delay -clock clk_sys_510 -min 0.0 [get_ports i_spi_miso]

# SPI is one time configuration interface - slow signals
set_multicycle_path 26 -setup \
    -from [get_clocks clk_sys_510] \
    -to [get_ports {o_spi_sclk o_spi_mosi o_spi_ss}]

set_multicycle_path 25 -hold \
    -from [get_clocks clk_sys_510] \
    -to [get_ports {o_spi_sclk o_spi_mosi o_spi_ss}]

#------------------------------------------------------------------------------
# --- QUANTUM STATE OUTPUTS (Relaxed for LED/Debug Outputs) ---
#------------------------------------------------------------------------------
# These drive LEDs and debug pins with NO real timing requirements
# Original 2.0 ns max was IMPOSSIBLE at 510 MHz (period = 1.961 ns)
# LEDs update at qubit detection rate (~kHz), not 510 MHz
# SOLUTION: Mark as false paths OR use very loose constraints

# False paths - for LEDs - they're just indicators)
set_false_path -from [get_clocks clk_sys_510] -to [get_ports {o_qubit_state[*]}]
set_false_path -from [get_clocks clk_sys_510] -to [get_ports o_qubit_valid]
set_false_path -from [get_clocks clk_sys_510] -to [get_ports {o_qubit_base_id[*]}]

#################################################################################
# PART 6: CLOCK DOMAIN CROSSING (CDC) CONSTRAINTS
#################################################################################

# 1. ASYNC FIFO (85 MHz Camera Domain <-> 510 MHz Processing Domain)
set_max_delay -datapath_only \
    -from [get_clocks clk_85_buffered] \
    -to [get_clocks clk_sys_510] 8.0

set_max_delay -datapath_only \
    -from [get_clocks clk_sys_510] \
    -to [get_clocks clk_85_buffered] 8.0

# 2. ROI STORAGE PING-PONG CDC (510 MHz domain)
set_max_delay -datapath_only 2.0 \
    -from [get_pins -hier -filter {NAME =~ *u_storage/frame_done_toggle_reg/C}] \
    -to [get_pins -hier -filter {NAME =~ *u_storage/frame_done_sync1_reg/D}]

#################################################################################
# PART 7: FALSE PATHS & TIMING EXCEPTIONS
#################################################################################

# 1. ASYNCHRONOUS RESET INPUT
set_false_path -from [get_ports i_rst_n] -to [all_registers]

# 2. INTERNAL RESET SYNCHRONIZER CHAINS
set_false_path -from [get_pins -hier -filter {NAME =~ *sys_rst*}] \
               -to [get_pins -hier -filter {NAME =~ *rst_sync*_s1*/D}]

# 3. MMCM LOCK SIGNAL (Asynchronous to all domains)
set_false_path -from [get_pins mmcm_inst/LOCKED] -to [all_registers]

# 4. FRAME DONE TOGGLE (First stage of CDC synchronizer)
set_false_path -from [get_pins -hier -filter {NAME =~ *frame_done_toggle_reg*/C}] \
               -to [get_pins -hier -filter {NAME =~ *frame_done_sync1_reg*/D}]

#################################################################################
# PART 8: ISERDES AND IDELAY CONSTRAINTS
#################################################################################

# IDELAYCTRL reference clock frequency
set_property IDELAYCTRL_REFCLK_FREQUENCY 510.0 [get_cells idelayctrl_inst]

# ISERDES bit rotation multicycle path
set_multicycle_path 1 -setup \
    -from [get_pins -hier -filter {NAME =~ *gen_deser[*]*/data_prev_reg[*]/C}] \
    -to [get_pins -hier -filter {NAME =~ *gen_deser[*]*/data_out_reg[*]/D}]

set_multicycle_path 0 -hold \
    -from [get_pins -hier -filter {NAME =~ *gen_deser[*]*/data_prev_reg[*]/C}] \
    -to [get_pins -hier -filter {NAME =~ *gen_deser[*]*/data_out_reg[*]/D}]

#################################################################################
# PART 10: PHYSICAL CONSTRAINTS
#################################################################################

# Clock routing strategy
set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets clk_85_buffered]
set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets clk_340_inv]
set_property CLOCK_DEDICATED_ROUTE BACKBONE [get_nets clk_fpga_510]

# High priority clock nets
set_property HIGH_PRIORITY true [get_nets clk_85_buffered]
set_property HIGH_PRIORITY true [get_nets clk_340_inv]
set_property HIGH_PRIORITY true [get_nets clk_fpga_510]

# BRAM inference for line buffers
set_property RAM_STYLE BLOCK [get_cells -hier -filter {NAME =~ *u_extract/lb0_reg*}]
set_property RAM_STYLE BLOCK [get_cells -hier -filter {NAME =~ *u_extract/lb1_reg*}]

# BRAM inference for ROI storage banks
set_property RAM_STYLE BLOCK [get_cells -hier -filter {NAME =~ *u_storage/bank*_reg*}]

# DSP inference for Gaussian multipliers
set_property USE_DSP48 yes [get_cells -hier -filter {NAME =~ *gen_filter[*]*/prod_reg*}]

# ASYNC_REG attributes for synchronizers
set_property ASYNC_REG TRUE [get_cells -hier -filter {NAME =~ *rst_sync*_s1_reg}]
set_property ASYNC_REG TRUE [get_cells -hier -filter {NAME =~ *rst_sync*_s2_reg}]
set_property ASYNC_REG TRUE [get_cells -hier -filter {NAME =~ *frame_done_sync*_reg}]

