`timescale 1ns / 1ps
import params_pkg::*;
 
module datastream_preprocessor (
    // FMC Interface Clocks
    input  logic        i_fmc_clk_p, i_fmc_clk_n, // 85 MHz from Camera
    input  logic        i_rst_n,

    // SPI Configuration Interface
    output logic        o_spi_sclk,
    output logic        o_spi_mosi,
    input  logic        i_spi_miso,
    output logic        o_spi_ss,
    
    // FMC Camera Link Data Inputs (Differential LVDS)
    input  logic [10:0] i_fmc_lvds_in_p,
    input  logic [10:0] i_fmc_lvds_in_n,
    
    // FINAL OUTPUT: QUANTUM STATE STREAM
    output logic [3:0]  o_qubit_state,      
    output logic [6:0]  o_qubit_base_id,    
    output logic        o_qubit_valid       
);

    // ---------------------------------------------------------------------------
    // 1. CLOCKING & RESET ARCHITECTURE
    // ---------------------------------------------------------------------------
    logic clk_85_ibuf;      // Unbuffered output from IBUFGDS
    logic clk_85_buffered;  // Globally routed clock
    logic clk_340;          // 340 MHz serial clock (0 degree)
    logic clk_340_inv_unbuf;  // 340 MHz inverted unbuffered (180 degree)
    logic clk_340_inv;      // 340 MHz inverted buffered
    logic clk_fpga_510_unbuff, clk_fpga_510;          // Internal 510 MHz clock
    logic mmcm_locked;
    logic sys_rst;

    // Differential input buffer
    IBUFGDS clk_buf_inst (
        .I(i_fmc_clk_p), .IB(i_fmc_clk_n), .O(clk_85_ibuf) 
    );

    // Global clock buffer
    BUFG bufg_85_inst (
        .I(clk_85_ibuf), .O(clk_85_buffered)
    );

    // MMCM: 85 MHz -> 340 MHz (serial) + 340 MHz inverted + 510 MHz (processing)
    logic clkfb;

    MMCME4_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(12.0),       // VCO = 85 * 12 = 1020 MHz
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(11.764),       // 85 MHz = 11.764 ns
        .CLKOUT0_DIVIDE_F(3.0),       // 1020 / 3 = 340 MHz (0 degree phase)
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0),
        .CLKOUT1_DIVIDE(2),           // 1020 / 2 = 510 MHz
        .CLKOUT1_DUTY_CYCLE(0.5),
        .CLKOUT1_PHASE(0.0),
        .DIVCLK_DIVIDE(1),            // Input divider (no division)
        .REF_JITTER1(0.010),          // Input jitter specification
        .STARTUP_WAIT("FALSE")        // Don't wait for startup
    ) mmcm_inst (
        .CLKIN1(clk_85_buffered),
        .CLKFBIN(clkfb),
        .CLKFBOUT(clkfb),
        .CLKOUT0(clk_340),
        .CLKOUT0B(clk_340_inv_unbuf),  // Inverted 340 MHz (180 degree phase)
        .CLKOUT1(clk_fpga_510_unbuff),
        .CLKOUT2(), .CLKOUT3(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .CLKFBOUTB(), .CLKOUT1B(), .CLKOUT2B(), .CLKOUT3B(),
        .PWRDWN(1'b0),
        .RST(~i_rst_n),  // Active-high reset
        .LOCKED(mmcm_locked)
    );
    
    // BUFG for inverted 340 MHz clock - ensures dedicated global routing
    BUFG bufg_340_inv_inst (
        .I(clk_340_inv_unbuf), .O(clk_340_inv)
    );
    
    // BUFG for 510 MHz
    BUFG bufg_510_inst (
        .I(clk_fpga_510_unbuff), .O(clk_fpga_510)
    );

    // System Reset Generation (Active High internally)
    assign sys_rst = ~i_rst_n || ~mmcm_locked;

    // Reset synchronizers
    logic rst_n_510, rst_n_85;
    (* ASYNC_REG = "TRUE" *) logic rst_sync_510_s1, rst_sync_510_s2;
    (* ASYNC_REG = "TRUE" *) logic rst_sync_85_s1, rst_sync_85_s2;

    always_ff @(posedge clk_fpga_510) begin
        rst_sync_510_s1 <= ~sys_rst;
        rst_sync_510_s2 <= rst_sync_510_s1;
    end
    assign rst_n_510 = rst_sync_510_s2;

    always_ff @(posedge clk_85_buffered) begin
        rst_sync_85_s1 <= ~sys_rst;
        rst_sync_85_s2 <= rst_sync_85_s1;
    end
    assign rst_n_85 = rst_sync_85_s2;

    // ---------------------------------------------------------------------------
    // 2. ISERDES DESERIALIZATION (11 lanes - 8 bits = 88 bits)
    // ---------------------------------------------------------------------------
    logic idelay_rdy;
    
    IDELAYCTRL #(
        .SIM_DEVICE("7SERIES.ULTRASCALE")
    ) idelayctrl_inst (
        .RDY(idelay_rdy),
        .REFCLK(clk_fpga_510),  // 510 MHz reference
        .RST(sys_rst)
    );

    // IDELAY tap values per lane
    logic [8:0] idelay_taps [10:0];
    
    initial begin
        for (int j = 0; j < 11; j++) begin
            idelay_taps[j] = 9'd256;  // Mid-range, tune in hardware
        end
    end
    
    //--------------------------------------------------------------
    // ISERDES with IDELAY and dedicated inverted clock
    //--------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < 11; i++) begin : gen_deser
            simple_iserdes_8to1 iserdes_inst (
                .clk_serial     (clk_340),
                .clk_serial_inv (clk_340_inv),      // Dedicated inverted clock
                .clk_parallel   (clk_85_buffered),
                .rst            (sys_rst),
                .idelay_rdy     (idelay_rdy),
                .idelay_tap     (idelay_taps[i]),
                .data_p         (i_fmc_lvds_in_p[i]),
                .data_n         (i_fmc_lvds_in_n[i]),
                .data_out       (deser_lane[i])
            );
        end
    endgenerate
    
    logic [7:0] deser_lane [10:0];
    logic [87:0] fmc_word;

    // Assemble 88-bit word
    generate
        for (i = 0; i < 11; i++) begin : gen_word
             assign fmc_word[i*8 +: 8] = deser_lane[i];
        end
    endgenerate

    // ---------------------------------------------------------------------------
    // 3. SIGNAL EXTRACTION (85 MHz Domain)
    // ---------------------------------------------------------------------------
    logic [63:0] cam_data;       // Capture all 8 pixels (Lanes 0-7)
    logic cam_fval, cam_lval, cam_dval;

    always_ff @(posedge clk_85_buffered) begin
        if (~rst_n_85) begin
            cam_data <= '0; cam_fval <= 0; cam_lval <= 0; cam_dval <= 0;
        end else begin
            // Capture 8 pixels (64 bits)
            cam_data <= fmc_word[63:0];
            
            // Extract sync signals (Table 6-6 from FMC Manual)
            cam_dval <= fmc_word[79];  // from X-link; CameraDVAL (Primary Valid)
            cam_fval <= fmc_word[78];  // from X-link; FVAL
            cam_lval <= fmc_word[77];  // from X-link; LVAL
        end
    end
    

    // ---------------------------------------------------------------------------
    // 4. FMC RECEIVER (CDC 85 -> 510 MHz + Pixel Logic)
    // ---------------------------------------------------------------------------
    // contains CDC 85 -> 510 MHz + Pixel Logic
    logic        core_pixel_valid;
    logic [15:0] core_pixel_data; // carry 2 pixels at once
    logic [8:0]  proc_x, proc_y;
    logic        fmc_sync_lval, fmc_sync_fval;
    logic        fmc_fifo_empty, fmc_fifo_full;
    logic        frame_done_pulse;
    
    fmc_receiver fmc_rx_inst (
        .i_cam_clk(clk_85_buffered),
        .i_clk_500(clk_fpga_510),
        .i_rst_n(rst_n_510),
        .i_cam_data(cam_data),
        .i_cam_fval(cam_fval),
        .i_cam_lval(cam_lval),
        .i_cam_dval(cam_dval),
        .o_pixel_data(core_pixel_data), // Now 16 bits (2 pixels)
        .o_pixel_valid(core_pixel_valid), // Valid for PAIR
        // 512x512
        .o_pixel_x(proc_x),
        .o_pixel_y(proc_y),
        .o_frame_done(frame_done_pulse),
        .o_sync_lval(fmc_sync_lval),
        .o_sync_fval(fmc_sync_fval),
        .o_fifo_empty(fmc_fifo_empty),
        .o_fifo_full(fmc_fifo_full)
    );

    // Downstream (Running at 510 MHz)
    // ---------------------------------------------------------------------------
    // 4. COORDINATE MATCHER
    // ---------------------------------------------------------------------------
    logic       match_found;
    logic [6:0] match_idx;
    logic       match_valid, match_offset;

    coord_matcher u_match (
        .i_clk(clk_fpga_510),
        .i_rst_n(rst_n_510),
        .i_curr_x(proc_x),
        .i_curr_y(proc_y),
        .i_valid(core_pixel_valid),

        // Sync signals from FMC receiver
        .i_sync_lval(fmc_sync_lval), 
        .i_sync_fval(fmc_sync_fval), 

        .o_match_found(match_found),
        .o_match_offset(match_offset),
        .o_qubit_index(match_idx),
        .o_valid_out(match_valid)
    );

    // ---------------------------------------------------------------------------
    // 5. ROI EXTRACTOR
    // ---------------------------------------------------------------------------
    logic [71:0] roi_flat;
    logic [6:0]  roi_idx;
    logic        roi_wr_en;

    roi_extractor u_extract (
        .i_clk(clk_fpga_510),
        .i_rst_n(rst_n_510),
        .i_pixel_data(core_pixel_data),
        .i_pixel_valid(core_pixel_valid),
        .i_match_trigger(match_found),
        .i_match_offset(match_offset),
        // Sync signals from FMC receiver
        .i_sync_lval(fmc_sync_lval), 
        .i_sync_fval(fmc_sync_fval), 

        .i_qubit_index(match_idx),
        .o_roi_flat(roi_flat),
        .o_qubit_index(roi_idx),
        .o_write_enable(roi_wr_en)
    );

    // ---------------------------------------------------------------------------
    // 6. ROI STORAGE (Dual-Bank Ping-Pong)
    // ---------------------------------------------------------------------------
    // Write side is now 510 MHz. Read side is also 510 MHz.
    // #TODO- maybe in the future to optimise- not important for now
    
    logic [71:0] rd_data_0, rd_data_1, rd_data_2, rd_data_3;
    logic        frame_ready;
    logic        start_read;
    
    roi_storage u_storage (
        .i_wr_clk(clk_fpga_510),
        .i_rd_clk(clk_fpga_510),
        .i_rst_n(rst_n_510),
        
        // Write Port
        .i_wr_en(roi_wr_en),
        .i_wr_addr(roi_idx),
        .i_wr_data(roi_flat),
        .i_frame_done(frame_done_pulse), 
        
        // Read Port (Controlled by Read Streamer)
        .i_rd_en(u_stream.o_rd_en),       // Connected to streamer below
        .i_rd_addr(u_stream.o_rd_addr),   // Connected to streamer below
        
        // Outputs
        .o_rd_data_0(rd_data_0),
        .o_rd_data_1(rd_data_1),
        .o_rd_data_2(rd_data_2),
        .o_rd_data_3(rd_data_3),
        .o_frame_ready(frame_ready)
    );

    // ---------------------------------------------------------------------------
    // 7. READ STREAMER (Turbo Parallel)
    // ---------------------------------------------------------------------------
    // Trigger read when frame is ready
    assign start_read = frame_ready; 

    // Internal wires for loopback
    logic [71:0] pd_lane_0, pd_lane_1, pd_lane_2, pd_lane_3;
    logic [6:0]  pd_base_id;
    logic        pd_valid;

    read_streamer u_stream (
        .i_clk(clk_fpga_510),
        .i_rst_n(rst_n_510),
        .i_start(start_read),
        
        // To Storage
        .o_rd_en(),   // Output to u_storage
        .o_rd_addr(), // Output to u_storage
        
        // From Storage
        .i_rd_data_0(rd_data_0),
        .i_rd_data_1(rd_data_1),
        .i_rd_data_2(rd_data_2),
        .i_rd_data_3(rd_data_3),
        
        // To Gaussian Engine
        .o_pixeldata_lane_0(pd_lane_0),
        .o_pixeldata_lane_1(pd_lane_1),
        .o_pixeldata_lane_2(pd_lane_2),
        .o_pixeldata_lane_3(pd_lane_3),
        .o_pixeldata_lane_base_id(pd_base_id),
        .o_pixeldata_lane_valid(pd_valid)
    );

    // ---------------------------------------------------------------------------
    // 8. GAUSSIAN FILTER BANK (4 Parallel Engines)
    // ---------------------------------------------------------------------------
    // Instantiating 4 parallel engines
    // Based on ROI 3x3 Image this module will estimate Qubit state 0/1

    genvar k;
    generate
        for (k = 0; k < 4; k++) begin : gen_filter
            logic [71:0] lane_data;
            assign lane_data = (k==0) ? pd_lane_0 : 
                               (k==1) ? pd_lane_1 : 
                               (k==2) ? pd_lane_2 : pd_lane_3;
            
            logic [6:0] eng_id_in;
            assign eng_id_in = pd_base_id + k; // ID 0,1,2,3...
            
            logic eng_decision;
            logic eng_valid;
            logic [6:0] eng_id_out;
            
            gaussian_filter_engine u_eng (
                .i_clk(clk_fpga_510),     
                .i_rst_n(rst_n_510),
                .i_roi_data(lane_data),
                .i_valid(pd_valid),
                .i_base_id(eng_id_in),
                .o_decision(eng_decision),
                .o_score(),
                .o_base_id(eng_id_out),
                .o_valid(eng_valid)
            );
       
            // Map to internal signals
            assign o_qubit_state[k] = eng_decision;
            
            // Just take valid/ID from lane 0 (they are synchronized)
            if (k == 0) begin
                assign o_qubit_valid   = eng_valid;
                assign o_qubit_base_id = eng_id_out; 
            end
        end
    endgenerate
 
    // ---------------------------------------------------------------------------
    // 9. SPI CONFIG 
    // ---------------------------------------------------------------------------
    spi_config u_spi (
        .i_clk(clk_fpga_510),           
        .i_rst_n(rst_n_510),
        .i_init_en(1'b1),
        .o_mosi(o_spi_mosi),
        .i_miso(i_spi_miso),
        .o_clk(o_spi_sclk),
        .o_ss(o_spi_ss)
    );
 
endmodule

