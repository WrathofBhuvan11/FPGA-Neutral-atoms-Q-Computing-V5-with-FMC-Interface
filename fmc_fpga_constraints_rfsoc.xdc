#################################################################################
# XDC Constraints for datastream_preprocessor 
# Target: AMD Zynq UltraScale+ RFSoC XCZU49DR-2FFVF1760 (ZCU216 Board)
# Application: FMC Camera Link -> Quantum State Detection
# Reference: UG1390 (ZCU216 Evaluation Board User Guide)
#################################################################################

#################################################################################
# PART 1: DEVICE CONFIGURATION
#################################################################################
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 1.8 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 85.0 [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 8 [current_design]
set_property CONFIG_MODE SPIx8 [current_design]

#################################################################################
# PART 2: CLOCK CONSTRAINTS - TIMING-17 COMPLIANT
#################################################################################

#------------------------------------------------------------------------------
# 1. PRIMARY INPUT CLOCK (85 MHz Differential LVDS from Camera via FMC+)
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

# --- FMC+ CAMERA INTERFACE (LVDS 1.8V with Termination) ---
# ZCU216 FMC+ Banks 66/67 @ 1.8V VCCO
set_property IOSTANDARD LVDS [get_ports i_fmc_clk_p]
set_property IOSTANDARD LVDS [get_ports i_fmc_clk_n]
set_property DIFF_TERM_ADV TERM_100 [get_ports i_fmc_clk_p]
set_property DIFF_TERM_ADV TERM_100 [get_ports i_fmc_clk_n]

set_property IOSTANDARD LVDS [get_ports {i_fmc_lvds_in_p[*]}]
set_property IOSTANDARD LVDS [get_ports {i_fmc_lvds_in_n[*]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {i_fmc_lvds_in_p[*]}]
set_property DIFF_TERM_ADV TERM_100 [get_ports {i_fmc_lvds_in_n[*]}]

# IDELAYCTRL and IDELAY configuration
set_property IODELAY_GROUP idelay_grp [get_cells idelayctrl_inst]
set_property IODELAY_GROUP idelay_grp [get_cells -hier -filter {REF_NAME == simple_iserdes_8to1 || ORIG_REF_NAME == simple_iserdes_8to1}]

# --- RESET (LVCMOS18 with Pull-up from User Pushbutton) ---
set_property IOSTANDARD LVCMOS18 [get_ports i_rst_n]
set_property PULLUP TRUE [get_ports i_rst_n]

# --- SPI INTERFACE (LVCMOS18 - Bank 89) ---
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

# --- USER LED OUTPUTS (LVCMOS18 - RGB LEDs on Bank 87/88/89) ---
set_property IOSTANDARD LVCMOS18 [get_ports {o_qubit_state[*]}]
set_property IOSTANDARD LVCMOS18 [get_ports o_qubit_valid]
set_property DRIVE 8 [get_ports {o_qubit_state[*]}]
set_property DRIVE 8 [get_ports o_qubit_valid]
set_property SLEW SLOW [get_ports {o_qubit_state[*]}]
set_property SLEW SLOW [get_ports o_qubit_valid]

# --- PMOD DEBUG OUTPUTS (LVCMOS18 - Bank 88) ---
set_property IOSTANDARD LVCMOS18 [get_ports {o_qubit_base_id[*]}]
set_property SLEW FAST [get_ports {o_qubit_base_id[*]}]
set_property DRIVE 8 [get_ports {o_qubit_base_id[*]}]

#################################################################################
# PART 4: PHYSICAL PIN ASSIGNMENTS - ZCU216 SPECIFIC
#################################################################################

#------------------------------------------------------------------------------
# FMC+ HSPC CONNECTOR (J28) - LVDS Signals
# Reference: ZCU216 User Guide UG1390, FMC+ Pin Mapping
#------------------------------------------------------------------------------

# --- CAMERA CLOCK (CLK0_M2C differential pair on FMC+) ---
# Bank 67 (LA[00:16] lower half)
set_property PACKAGE_PIN J10 [get_ports i_fmc_clk_p]    ; # FMC_CLK0_M2C_P (LA17_CC_P)
set_property PACKAGE_PIN H10 [get_ports i_fmc_clk_n]    ; # FMC_CLK0_M2C_N (LA17_CC_N)

# Clock can come from non-GCIO pin on FMC - allow fabric routing
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets clk_buf_inst/O]

#------------------------------------------------------------------------------
# --- CAMERA DATA LANES (11 Differential Pairs) ---
# Using LA[00:10] pins on FMC+ HSPC connector
# Banks 66 & 67 @ 1.8V
#------------------------------------------------------------------------------

# Lane 0: LA00 (Bank 67)
set_property PACKAGE_PIN D11 [get_ports {i_fmc_lvds_in_p[0]}]  ; # FMC_LA00_CC_P
set_property PACKAGE_PIN C11 [get_ports {i_fmc_lvds_in_n[0]}]  ; # FMC_LA00_CC_N

# Lane 1: LA01 (Bank 67)
set_property PACKAGE_PIN E10 [get_ports {i_fmc_lvds_in_p[1]}]  ; # FMC_LA01_CC_P
set_property PACKAGE_PIN D10 [get_ports {i_fmc_lvds_in_n[1]}]  ; # FMC_LA01_CC_N

# Lane 2: LA02 (Bank 67)
set_property PACKAGE_PIN G11 [get_ports {i_fmc_lvds_in_p[2]}]  ; # FMC_LA02_P
set_property PACKAGE_PIN F11 [get_ports {i_fmc_lvds_in_n[2]}]  ; # FMC_LA02_N

# Lane 3: LA03 (Bank 67)
set_property PACKAGE_PIN H9  [get_ports {i_fmc_lvds_in_p[3]}]  ; # FMC_LA03_P
set_property PACKAGE_PIN G9  [get_ports {i_fmc_lvds_in_n[3]}]  ; # FMC_LA03_N

# Lane 4: LA04 (Bank 67)
set_property PACKAGE_PIN F10 [get_ports {i_fmc_lvds_in_p[4]}]  ; # FMC_LA04_P
set_property PACKAGE_PIN E9  [get_ports {i_fmc_lvds_in_n[4]}]  ; # FMC_LA04_N

# Lane 5: LA05 (Bank 67)
set_property PACKAGE_PIN G8  [get_ports {i_fmc_lvds_in_p[5]}]  ; # FMC_LA05_P
set_property PACKAGE_PIN F8  [get_ports {i_fmc_lvds_in_n[5]}]  ; # FMC_LA05_N

# Lane 6: LA06 (Bank 67)
set_property PACKAGE_PIN K9  [get_ports {i_fmc_lvds_in_p[6]}]  ; # FMC_LA06_P
set_property PACKAGE_PIN J9  [get_ports {i_fmc_lvds_in_n[6]}]  ; # FMC_LA06_N

# Lane 7: LA07 (Bank 67)
set_property PACKAGE_PIN K8  [get_ports {i_fmc_lvds_in_p[7]}]  ; # FMC_LA07_P
set_property PACKAGE_PIN J8  [get_ports {i_fmc_lvds_in_n[7]}]  ; # FMC_LA07_N

# Lane 8: LA08 (Bank 67)
set_property PACKAGE_PIN H11 [get_ports {i_fmc_lvds_in_p[8]}]  ; # FMC_LA08_P
set_property PACKAGE_PIN H12 [get_ports {i_fmc_lvds_in_n[8]}]  ; # FMC_LA08_N

# Lane 9: LA09 (Bank 67)
set_property PACKAGE_PIN K11 [get_ports {i_fmc_lvds_in_p[9]}]  ; # FMC_LA09_P
set_property PACKAGE_PIN J11 [get_ports {i_fmc_lvds_in_n[9]}]  ; # FMC_LA09_N

# Lane 10: LA10 (Bank 67)
set_property PACKAGE_PIN E12 [get_ports {i_fmc_lvds_in_p[10]}] ; # FMC_LA10_P
set_property PACKAGE_PIN D12 [get_ports {i_fmc_lvds_in_n[10]}] ; # FMC_LA10_N

#------------------------------------------------------------------------------
# USER I/O - ZCU216 Board Resources
#------------------------------------------------------------------------------

# --- RESET INPUT (User Pushbutton SW8 - Center button) ---
# Bank 89 @ 1.8V
set_property PACKAGE_PIN AV21 [get_ports i_rst_n]  ; # GPIO_PB_C (Center pushbutton)

#------------------------------------------------------------------------------
# --- SPI CONFIGURATION INTERFACE (PL GPIO - Bank 89) ---
# Using available PL GPIO pins for SPI communication
#------------------------------------------------------------------------------
set_property PACKAGE_PIN BA20 [get_ports o_spi_sclk]  ; # PL GPIO (Bank 89)
set_property PACKAGE_PIN BA21 [get_ports o_spi_mosi]  ; # PL GPIO (Bank 89)
set_property PACKAGE_PIN AY20 [get_ports i_spi_miso]  ; # PL GPIO (Bank 89)
set_property PACKAGE_PIN AY21 [get_ports o_spi_ss]    ; # PL GPIO (Bank 89)

#------------------------------------------------------------------------------
# --- USER LEDs (Quantum State Display) ---
# Using RGB LEDs on Bank 87/88 - Green channels
# ZCU216 has 8 RGB LEDs (DS46-DS53)
#------------------------------------------------------------------------------
# Qubit State[3:0] -> First 4 Green LED channels
set_property PACKAGE_PIN AT20 [get_ports {o_qubit_state[0]}]  ; # RGB_G_LED0 (Bank 87)
set_property PACKAGE_PIN AT19 [get_ports {o_qubit_state[1]}]  ; # RGB_G_LED1 (Bank 87)
set_property PACKAGE_PIN AW22 [get_ports {o_qubit_state[2]}]  ; # RGB_G_LED2 (Bank 87)
set_property PACKAGE_PIN AW23 [get_ports {o_qubit_state[3]}]  ; # RGB_G_LED3 (Bank 87)

# Valid indicator -> Green LED 4
set_property PACKAGE_PIN BA23 [get_ports o_qubit_valid]       ; # RGB_G_LED4 (Bank 88)

#------------------------------------------------------------------------------
# --- PMOD0 (J46) Debug Outputs (Qubit Base ID[6:0]) ---
# Bank 88 @ 1.8V - Standard 2x6 PMOD connector
#------------------------------------------------------------------------------
set_property PACKAGE_PIN AY24 [get_ports {o_qubit_base_id[0]}]  ; # PMOD0_0
set_property PACKAGE_PIN AY25 [get_ports {o_qubit_base_id[1]}]  ; # PMOD0_1
set_property PACKAGE_PIN BA24 [get_ports {o_qubit_base_id[2]}]  ; # PMOD0_2
set_property PACKAGE_PIN BA25 [get_ports {o_qubit_base_id[3]}]  ; # PMOD0_3
set_property PACKAGE_PIN AW25 [get_ports {o_qubit_base_id[4]}]  ; # PMOD0_4
set_property PACKAGE_PIN AW26 [get_ports {o_qubit_base_id[5]}]  ; # PMOD0_5
set_property PACKAGE_PIN AV24 [get_ports {o_qubit_base_id[6]}]  ; # PMOD0_6

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
# --- SPI INTERFACE TIMING (Matches Actual SPI Clock Divider) ---
#------------------------------------------------------------------------------
# RTL generates SPI clock at 510 MHz / 26 = 19.6 MHz (period = 51 ns)
set_output_delay -clock clk_sys_510 -max 10.0 [get_ports o_spi_sclk]
set_output_delay -clock clk_sys_510 -min -2.0 [get_ports o_spi_sclk]
set_output_delay -clock clk_sys_510 -max 10.0 [get_ports o_spi_mosi]
set_output_delay -clock clk_sys_510 -min -2.0 [get_ports o_spi_mosi]
set_output_delay -clock clk_sys_510 -max 10.0 [get_ports o_spi_ss]
set_output_delay -clock clk_sys_510 -min -2.0 [get_ports o_spi_ss]
set_input_delay -clock clk_sys_510 -max 15.0 [get_ports i_spi_miso]
set_input_delay -clock clk_sys_510 -min 0.0 [get_ports i_spi_miso]

# SPI multicycle paths (slow configuration interface)
set_multicycle_path 26 -setup \
    -from [get_clocks clk_sys_510] \
    -to [get_ports {o_spi_sclk o_spi_mosi o_spi_ss}]

set_multicycle_path 25 -hold \
    -from [get_clocks clk_sys_510] \
    -to [get_ports {o_spi_sclk o_spi_mosi o_spi_ss}]

#------------------------------------------------------------------------------
# --- QUANTUM STATE OUTPUTS (Relaxed for LED/Debug Outputs) ---
#------------------------------------------------------------------------------
# False paths for LED indicators - no real timing requirements
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

# IDELAYCTRL reference clock frequency (510 MHz on ZCU216)
set_property IDELAYCTRL_REFCLK_FREQUENCY 510.0 [get_cells idelayctrl_inst]

# ISERDES bit rotation multicycle path
set_multicycle_path 1 -setup \
    -from [get_pins -hier -filter {NAME =~ *gen_deser[*]*/data_prev_reg[*]/C}] \
    -to [get_pins -hier -filter {NAME =~ *gen_deser[*]*/data_out_reg[*]/D}]

set_multicycle_path 0 -hold \
    -from [get_pins -hier -filter {NAME =~ *gen_deser[*]*/data_prev_reg[*]/C}] \
    -to [get_pins -hier -filter {NAME =~ *gen_deser[*]*/data_out_reg[*]/D}]

#################################################################################
# PART 9: PHYSICAL CONSTRAINTS
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

#################################################################################
# PART 10: ZCU216-SPECIFIC OPTIMIZATIONS
#################################################################################

# Utilize UltraScale+ high-performance features
set_property DCI_CASCADE {32 34} [get_iobanks 67]  ; # DCI cascading for better signal integrity

# I/O bank voltage configuration check
# Bank 66: 1.8V (FMC LA[17:33])
# Bank 67: 1.8V (FMC LA[00:16])
# Bank 87: 1.8V (RGB LEDs)
# Bank 88: 1.8V (PMOD, LEDs)
# Bank 89: 1.8V (GPIO, SPI)
