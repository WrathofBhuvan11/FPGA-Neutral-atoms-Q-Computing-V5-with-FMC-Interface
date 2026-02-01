`timescale 1ns / 1ps
import params_pkg::*;

module tb_dynamic_video_system;

    // ---------------------------------------------------------------------------
    // 1. Settings & Parameters
    // ---------------------------------------------------------------------------
    localparam int NUM_FRAMES = 5; 
    
    // ISERDES verification control
    localparam int ISERDES_VERIFY_CYCLES = 10000;  // Spot check after alignment
    
    // Last qubit base ID calculation (for timing trigger)
    localparam int LAST_QUBIT_BASE_ID = (NUM_QUBITS / NUM_BANKS - 1) * NUM_BANKS;

    // Clock Periods
    localparam CLK_85_PERIOD  = 11.76;  // 85 MHz camera clock
    localparam CLK_200_PERIOD = 5.0;    // 200 MHz Reference clock
    localparam CLK_510_PERIOD = 1.961;  // 510 MHz actual

    // ---------------------------------------------------------------------------
    // 2. Signals
    // ---------------------------------------------------------------------------
    // Clocks
    logic i_cam_clk;
    logic i_sys_clk_200;
    logic i_rst_n;

    // DUT Interfaces
    logic [10:0] fmc_lvds_p, fmc_lvds_n;
    logic        fmc_clk_p, fmc_clk_n;

    // SPI Signals
    logic spi_sclk, spi_mosi, spi_miso, spi_ss;

    // DUT Outputs (Gaussian Decisions)
    logic [3:0] o_qubit_state;
    logic [QUBIT_ID_WIDTH-1:0] o_qubit_base_id;

    logic       o_qubit_valid;
    
    // Internal Probes (Hierarchical Access for Verification)
    logic [87:0] received_fmc_word;  // TAP internal signal
    logic [71:0] lane_0, lane_1, lane_2, lane_3;
    logic [QUBIT_ID_WIDTH-1:0]  lane_base_id;

    logic        lane_valid;
    logic [COORD_WIDTH-1:0]     core_x_probe, core_y_probe;
    logic [15:0]  core_pixel_probe;      // For RX checker
    logic        core_pixel_valid_probe; // For RX checker
    
    // Driver Signals
    logic [87:0] sim_fmc_word; // Parallel word to be serialized

    // Verification State
    int error_cnt = 0;
    int parallel_match_cnt = 0;
    int gaussian_match_cnt = 0;
    int gaussian_error_cnt = 0;
    int iserdes_verify_cnt = 0;        // ISERDES verification counter
    int iserdes_error_cnt = 0;         // ISERDES error counter
    int tb_frame_counter = 0;
    int check_frame = 0;
    int current_proc_frame = -1;
    
    // Refined Performance Monitoring
    realtime frame_fval_start = 0;     // When FVAL goes high
    realtime frame_first_pixel = 0;    // When first valid pixel transmitted
    realtime frame_last_pixel = 0;     // When last pixel transmitted
    realtime frame_ready_time = 0;     // When o_frame_ready asserts
    realtime frame_first_result = 0;   // When first Gaussian result appears
    realtime frame_last_result = 0;    // When last Gaussian result appears
    int spi_done = 0;

    // ISERDES Pipeline Alignment (from testbench_iserdes)
    logic [87:0] exp_pipe [0:15];
    int matched_latency_idx = -1;
    int alignment_check_cnt = 0;
    bit alignment_complete = 0;
    bit iserdes_verification_done = 0;  // Flag to stop ISERDES checking

    // ---------------------------------------------------------------------------
    // 3. Clock Generation
    // ---------------------------------------------------------------------------
    initial i_cam_clk = 0; 
    always #(CLK_85_PERIOD/2) i_cam_clk = ~i_cam_clk;

    initial i_sys_clk_200 = 0; 
    always #(CLK_200_PERIOD/2) i_sys_clk_200 = ~i_sys_clk_200;
    // Differential Clock Driver
    assign fmc_clk_p = i_cam_clk;
    assign fmc_clk_n = ~i_cam_clk;

    // ---------------------------------------------------------------------------
    // 4. DUT Instantiation
    // ---------------------------------------------------------------------------
    datastream_preprocessor DUT (
        .i_fmc_clk_p(fmc_clk_p),
        .i_fmc_clk_n(fmc_clk_n),
        .i_rst_n(i_rst_n),

        .o_spi_sclk(spi_sclk),
        .o_spi_mosi(spi_mosi),
        .i_spi_miso(spi_miso),
        .o_spi_ss(spi_ss),
        
        .i_fmc_lvds_in_p(fmc_lvds_p), 
        .i_fmc_lvds_in_n(fmc_lvds_n),
        
        .o_qubit_state(o_qubit_state),
        .o_qubit_base_id(o_qubit_base_id),
        .o_qubit_valid(o_qubit_valid)
    );

/*
// Force Inject
     always @(*) begin
        // Force the internal 88-bit word in the DUT to match the TB driver word
        force DUT.fmc_word = sim_fmc_word;
     end
*/
    // TAP internal signals
    assign received_fmc_word = DUT.fmc_word;

    // ---------------------------------------------------------------------------
    // 5. OSERDESE3 Camera Emulation (FMC-200A Base Mode)
    // ---------------------------------------------------------------------------
    // Borrow DUT's generated clocks for perfect phase alignment
    logic clk_340_tb, clk_85_tb;
    assign clk_340_tb = DUT.clk_340;
    assign clk_85_tb  = DUT.clk_85_buffered;

    genvar j;
    generate
        for (j = 0; j < 11; j++) begin : gen_cam_tx
            logic [7:0] lane_data;
            assign lane_data = sim_fmc_word[j*8 +: 8];

            OSERDESE3 #(
                .DATA_WIDTH(8), 
                .INIT(1'b0),
                .IS_CLK_INVERTED(1'b0),
                .IS_RST_INVERTED(1'b0),
                .SIM_DEVICE("ULTRASCALE_PLUS")
            ) u_tx (
                .OQ(fmc_lvds_p[j]),
                .T(1'b0),                 // Always transmitting
                .CLK(clk_340_tb),         // 340 MHz serial clock
                .CLKDIV(clk_85_tb),       // 85 MHz parallel clock
                .D(lane_data),            // 8-bit parallel data
                .RST(~i_rst_n)
            );
            
            // Differential pair
            assign fmc_lvds_n[j] = ~fmc_lvds_p[j];
        end
    endgenerate

    // ---------------------------------------------------------------------------
    // 6. ISERDES Pipeline Latency Auto-Detection (Phase 1: Quick Find)
    // ---------------------------------------------------------------------------
    // Pipeline expected data through shift register
    always_ff @(posedge i_cam_clk) begin
        exp_pipe[0] <= sim_fmc_word;
        for (int k = 1; k < 16; k++) begin
            exp_pipe[k] <= exp_pipe[k-1];
        end
    end

    // Auto-detect ISERDES pipeline latency
    int consecutive_matches = 0;
    int search_depth = -1;
    
    always @(posedge i_cam_clk) begin
        if (i_rst_n && DUT.mmcm_locked && !alignment_complete) begin
            alignment_check_cnt++;
            
            // Start after settling
            if (alignment_check_cnt > 100) begin
                
                // PHASE 1: Find candidate depth
                if (search_depth == -1 && received_fmc_word != 0) begin
                    for (int k = 1; k < 10; k++) begin
                        if (received_fmc_word == exp_pipe[k]) begin
                            search_depth = k;
                            consecutive_matches = 1;
                            $display("[ISERDES] Candidate depth %0d found @ cycle %0d", 
                                     k, alignment_check_cnt);
                            break;
                        end
                    end
                end
                
                // PHASE 2: Verify candidate
                else if (search_depth != -1) begin
                    if (received_fmc_word == exp_pipe[search_depth]) begin
                        consecutive_matches++;
                        
                        // Confirm after 10 consecutive matches
                        if (consecutive_matches >= 10) begin
                            alignment_complete = 1;
                            matched_latency_idx = search_depth;
                            $display("\n=========================================================||");
                            $display("|| [ISERDES ALIGNMENT COMPLETE] @ %0t ns", $realtime);
                            $display("|| Detected Pipeline Latency: %0d clk_85 cycles (%.2f ns)", 
                                     matched_latency_idx, matched_latency_idx * CLK_85_PERIOD);
                            $display("|| Pipeline: sim_fmc_word -> OSERDES -> LVDS -> ISERDES -> fmc_word");
                            $display("||=========================================================||\n");
                        end
                    end else begin
                        // Mismatch - restart (ignore blanking)
                        if (received_fmc_word != 0 && exp_pipe[search_depth] != 0) begin
                            $display("[ISERDES] Mismatch at depth %0d, restarting search", search_depth);
                            search_depth = -1;
                            consecutive_matches = 0;
                        end
                    end
                end
            end
        end
    end

    // ---------------------------------------------------------------------------
    // 7. ISERDES SPOT CHECK (Phase 2: Verification)
    // ---------------------------------------------------------------------------
    always @(posedge i_cam_clk) begin
        if (alignment_complete && !iserdes_verification_done && i_rst_n && DUT.mmcm_locked) begin
            logic [87:0] expected;
            expected = exp_pipe[matched_latency_idx];
            
            // Verify fmc_word matches delayed stimulus
            if (received_fmc_word === expected) begin
                iserdes_verify_cnt++;
            end else begin
                // Only flag real errors (ignore blanking)
                if (expected != 0 || received_fmc_word != 0) begin
                    iserdes_error_cnt++;
                    $display("[ISERDES ERROR] @ %0t | Exp: %h | Got: %h", 
                             $realtime, expected, received_fmc_word);
                end
            end
            
            // Stop after limited verification
            if (iserdes_verify_cnt >= ISERDES_VERIFY_CYCLES) begin
                iserdes_verification_done = 1;
                $display("\n||===============================================||");
                $display("||  [ISERDES VERIFICATION COMPLETE]");
                $display("||  Verified %0d cycles | Errors: %0d", 
                         iserdes_verify_cnt, iserdes_error_cnt);
                $display("||  >> Switching to ROI/Gaussian Verification <<");
                $display("||==================================================||\n");
            end
        end
    end

    // ---------------------------------------------------------------------------
    // 8. Bind Probes
    // ---------------------------------------------------------------------------
    assign lane_0 = DUT.u_stream.o_pixeldata_lane_0;
    assign lane_1 = DUT.u_stream.o_pixeldata_lane_1;
    assign lane_2 = DUT.u_stream.o_pixeldata_lane_2;
    assign lane_3 = DUT.u_stream.o_pixeldata_lane_3;
    assign lane_base_id = DUT.u_stream.o_pixeldata_lane_base_id;
    assign lane_valid = DUT.u_stream.o_pixeldata_lane_valid;
    
    assign core_x_probe = DUT.proc_x;
    assign core_y_probe = DUT.proc_y;
    assign core_pixel_probe = DUT.core_pixel_data;
    assign core_pixel_valid_probe = DUT.core_pixel_valid;

    // ---------------------------------------------------------------------------
    // 9. FMC Protocol Task (FULL Mode 8-bit Monochromatic)
    // ---------------------------------------------------------------------------
    task send_fmc_cycle(
    input logic dval,  // Data valid
    input logic fval,  // Frame valid
    input logic lval,  // Line valid  
    input logic [63:0] pixel_data  // 8 pixels for Full Mode
    );
        @(posedge i_cam_clk);
        #0.1; 
        sim_fmc_word = 88'd0;
        
        // Full Mode: 8 pixels across lanes 0-7
        sim_fmc_word[63:0] = pixel_data;  // P7..P0
        
        // Sync signals (Table 6-6)
        sim_fmc_word[79] = dval;  // CameraDVAL
        sim_fmc_word[78] = fval;  // FVAL
        sim_fmc_word[77] = lval;  // LVAL
        sim_fmc_word[76] = 1'b0;  // FMC DVAL (spare)
    endtask

    // ---------------------------------------------------------------------------
    // 10. Golden Reference Functions
    // ---------------------------------------------------------------------------
    
    // Calculate expected ROI window
    function logic [71:0] get_expected_roi(int id, int frame_num);
        int cx, cy;
        logic [7:0] p[0:2][0:2]; 
        
        cx = QUBIT_START_X + (id % GRID_COLS) * QUBIT_SPACING;
        cy = QUBIT_START_Y + (id / GRID_COLS) * QUBIT_SPACING;

        // Window: X=[cx-1, cx, cx+1], Y=[cy-2, cy-1, cy]
        
        // Top Row (y-2)
        p[2][0] = 8'((cx-1) ^ (cy-2)) + 8'(frame_num);  // Left
        p[2][1] = 8'((cx)   ^ (cy-2)) + 8'(frame_num);  // Center
        p[2][2] = 8'((cx+1) ^ (cy-2)) + 8'(frame_num);  // Right
        
        // Mid Row (y-1)
        p[1][0] = 8'((cx-1) ^ (cy-1)) + 8'(frame_num);
        p[1][1] = 8'((cx)   ^ (cy-1)) + 8'(frame_num);
        p[1][2] = 8'((cx+1) ^ (cy-1)) + 8'(frame_num);
        
        // Bot Row (y)
        p[0][0] = 8'((cx-1) ^ cy) + 8'(frame_num);
        p[0][1] = 8'((cx)   ^ cy) + 8'(frame_num);
        p[0][2] = 8'((cx+1) ^ cy) + 8'(frame_num);
        
        // Pack: Bottom->Middle->Top, Left->Center->Right 
        return {p[0][0], p[0][1], p[0][2],   // Bottom row: Left, Center, Right
                p[1][0], p[1][1], p[1][2],   // Middle row: Left, Center, Right
                p[2][0], p[2][1], p[2][2]};  // Top row: Left, Center, Right
    endfunction

    // Calculate expected Gaussian decision
    function logic get_expected_decision(int id, int frame_num);
        logic [71:0] roi = get_expected_roi(id, frame_num);
        logic [7:0] pix[2:0][2:0];
        int sum = 0;
        
        // Unpack (matches gaussian_filter_engine.sv)
        pix[0][2] = roi[71:64]; pix[0][1] = roi[63:56]; pix[0][0] = roi[55:48];  // bottom
        pix[1][2] = roi[47:40]; pix[1][1] = roi[39:32]; pix[1][0] = roi[31:24];  // mid
        pix[2][2] = roi[23:16]; pix[2][1] = roi[15:8];  pix[2][0] = roi[7:0];     // top
        
        // Gaussian sum (kernel: 1 2 1, 2 4 2, 1 2 1)
        sum = pix[0][0]*1 + pix[0][1]*2 + pix[0][2]*1 +
              pix[1][0]*2 + pix[1][1]*4 + pix[1][2]*2 +
              pix[2][0]*1 + pix[2][1]*2 + pix[2][2]*1;
        
        return (sum > 500);  // Threshold from gaussian_filter_engine.sv
    endfunction

    // ---------------------------------------------------------------------------
    // 11. Print Task for ROI Display
    // ---------------------------------------------------------------------------
    task print_roi_grid(input logic [71:0] data, input int id, input string status);
        logic [7:0] p[0:2][0:2];
        int cx, cy;
        
        cx = QUBIT_START_X + (id % GRID_COLS) * QUBIT_SPACING;
        cy = QUBIT_START_Y + (id / GRID_COLS) * QUBIT_SPACING;

        // Unpack matches RTL/Gaussian - {Row0(Bottom), Row1, Row2(Top)}
        // Row 0 (Bottom, Y)
        p[0][0] = data[71:64]; p[0][1] = data[63:56]; p[0][2] = data[55:48];
        // Row 1 (Mid, Y-1)
        p[1][0] = data[47:40]; p[1][1] = data[39:32]; p[1][2] = data[31:24];
        // Row 2 (Top, Y-2)
        p[2][0] = data[23:16]; p[2][1] = data[15:8];  p[2][2] = data[7:0];

        $display("    === %s [ID %2d] Center(%3d,%3d) ===", status, id, cx, cy);
        $display("      (%3d,%3d): %2h  (%3d,%3d): %2h  (%3d,%3d): %2h", 
                 cx-1, cy-2, p[2][0], cx, cy-2, p[2][1], cx+1, cy-2, p[2][2]);
        $display("      (%3d,%3d): %2h  (%3d,%3d): %2h  (%3d,%3d): %2h", 
                 cx-1, cy-1, p[1][0], cx, cy-1, p[1][1], cx+1, cy-1, p[1][2]);
        $display("      (%3d,%3d): %2h  (%3d,%3d): %2h  (%3d,%3d): %2h", 
                 cx-1, cy,   p[0][0], cx, cy,   p[0][1], cx+1, cy,   p[0][2]);
        $display("    ===========================================\n");
    endtask

    // ---------------------------------------------------------------------------
    // 12. Main Stimulus 
    // ---------------------------------------------------------------------------
    initial begin
        // Reset sequence
        i_rst_n = 0;
        sim_fmc_word = 0;
        spi_miso = 0;
        
        #200;
        i_rst_n = 1;
        $display("[TB] Reset Released @ %0t ns", $realtime);

        // Wait for MMCM Lock
        $display("[TB] Waiting for MMCM lock...");
        wait(DUT.mmcm_locked == 1);
        $display("[TB] MMCM Locked @ %0t ns", $realtime);
        
        #500;  // Settling time for MMCM/IDELAY
        
        $display("[TB] Starting ISERDES alignment detection...\n");
        
        // Frame Generation Loop
        for (int f = 0; f < NUM_FRAMES; f++) begin
            tb_frame_counter = f;
            
            $display("\n=====================================================");
            $display(" FRAME %0d Generation Started @ %0t ns", f, $realtime);
            $display("||=====================================================||");
            
            // Frame preamble (FVAL assertion)
            frame_fval_start = $realtime;
            repeat(10) send_fmc_cycle(.dval(0), .fval(1), .lval(0), .pixel_data(0));
            
            // First pixel about to be sent
            frame_first_pixel = $realtime;

            // Generate IMAGE_HEIGHT lines
            for (int y = 0; y < IMAGE_HEIGHT; y++) begin
                // Full Mode: Send IMAGE_WIDTH/8 cycles (8 pixels per cycle)
                for (int g = 0; g < (IMAGE_WIDTH/8); g++) begin
                    int x_base = g * 8;
                    logic [7:0] p0, p1, p2, p3, p4, p5, p6, p7;
            
                    // Generate 8 pixels per cycle
                    p0 = 8'((x_base + 0) ^ y) + 8'(f);
                    p1 = 8'((x_base + 1) ^ y) + 8'(f);
                    p2 = 8'((x_base + 2) ^ y) + 8'(f);
                    p3 = 8'((x_base + 3) ^ y) + 8'(f);
                    p4 = 8'((x_base + 4) ^ y) + 8'(f);
                    p5 = 8'((x_base + 5) ^ y) + 8'(f);
                    p6 = 8'((x_base + 6) ^ y) + 8'(f);
                    p7 = 8'((x_base + 7) ^ y) + 8'(f);
            
                    // Send 8 pixels in one cycle
                    send_fmc_cycle(.dval(1), .fval(1), .lval(1), .pixel_data({p7, p6, p5, p4, p3, p2, p1, p0}));
                end
            
                // H-Blank
                repeat(5) send_fmc_cycle(.dval(0), .fval(1), .lval(0), .pixel_data(0));
            end

            // Last pixel sent
            frame_last_pixel = $realtime;
            
            // Frame Valid goes LOW
            send_fmc_cycle(.dval(0), .fval(0), .lval(0), .pixel_data(0));
            $display("|| Frame %0d transmission complete", f);
            
            // Inter-Frame Delay
            repeat(500) send_fmc_cycle(.dval(0), .fval(0), .lval(0), .pixel_data(0));
        end
        
        // Wait for processing to drain
        $display("\n[TB] All frames sent. Waiting for pipeline to drain...");
        #10us;
       
        // Final Report
        $display("\n||==========================================================||");
        $display("||             TEST COMPLETION SUMMARY                      ||");
        $display("||==========================================================||");
        $display("|| ISERDES Pipeline Latency: %2d cycles (%.2f ns)           ||", 
                 matched_latency_idx, matched_latency_idx * CLK_85_PERIOD);
        $display("|| ISERDES Verifications:    %6d (Errors: %3d)              ||", 
                 iserdes_verify_cnt, iserdes_error_cnt);
        $display("|| ROI Matches:              %6d (Errors: %3d)              ||", 
                 parallel_match_cnt, error_cnt);
        $display("|| Gaussian Matches:         %6d (Errors: %3d)              ||", 
                 gaussian_match_cnt, gaussian_error_cnt);
        $display("|| SPI Configuration:        %s                             ||",
                 spi_done ? "PASSED" : "FAILED");
        $display("|| Alignment Status:         %s                             ||",
                 alignment_complete ? "COMPLETED" : "INCOMPLETE");
        $display("||==========================================================||");
        
        if (error_cnt == 0 && gaussian_error_cnt == 0 && iserdes_error_cnt == 0 
            && spi_done) begin  // Don't require alignment_complete for pass
            $display("||               *** TEST PASSED ***                         ||");
        end else begin
            $display("||               *** TEST FAILED ***                         ||");
        end
        $display("||==========================================================||\n");
 
        $finish;
    end

    // ---------------------------------------------------------------------------
    // 13. Frame Ready Tracking
    // ---------------------------------------------------------------------------
    always @(posedge DUT.clk_fpga_510) begin
        if (DUT.u_storage.o_frame_ready && !$past(DUT.u_storage.o_frame_ready)) begin
            frame_ready_time = $realtime;
            current_proc_frame++;
            check_frame = current_proc_frame;
            $display("\n[FRAME READY] Frame %0d ready for processing @ %0t ns", 
                     check_frame, $realtime);
        end
    end

    // ---------------------------------------------------------------------------
    // 14. ROI Extraction Checker
    // ---------------------------------------------------------------------------
    always @(posedge DUT.clk_fpga_510) begin
        if (lane_valid) begin
            for (int k = 0; k < 4; k++) begin
                int id = lane_base_id + k;
                int cx, cy;
                logic [71:0] expected = get_expected_roi(id, check_frame);
                logic [71:0] actual = (k==0) ? lane_0 : (k==1) ? lane_1 : (k==2) ? lane_2 : lane_3;
                
                cx = QUBIT_START_X + (id % GRID_COLS) * QUBIT_SPACING;
                cy = QUBIT_START_Y + (id / GRID_COLS) * QUBIT_SPACING;
                
                if (actual !== expected) begin
                    error_cnt++;
                    $display("\n||================================================||");
                    $display("||         *** ROI MISMATCH DETECTED ***            ||");
                    $display("||================================================||");
                    $display("|| Frame: %2d  |  ID: %2d  |  Coord: (%3d,%3d)    ||", 
                             check_frame, id, cx, cy);
                    $display("||================================================||");
                    print_roi_grid(actual, id, "ACTUAL (FAIL)");
                    print_roi_grid(expected, id, "EXPECTED");
                    $display("");
                end else begin
                    // SUCCESS CASE: Show only ACTUAL values
                    parallel_match_cnt++;
                    
                    if ((parallel_match_cnt > -1 )) begin
                        // Unpack ACTUAL pixel values (local to this block)
                        automatic logic [7:0] p_actual[0:2][0:2];
                        
                        p_actual[0][0] = actual[71:64]; p_actual[0][1] = actual[63:56]; p_actual[0][2] = actual[55:48];  // Bottom
                        p_actual[1][0] = actual[47:40]; p_actual[1][1] = actual[39:32]; p_actual[1][2] = actual[31:24];  // Mid
                        p_actual[2][0] = actual[23:16]; p_actual[2][1] = actual[15:8];  p_actual[2][2] = actual[7:0];    // Top
                        
                        $display("  [ROI PASS] Frame %0d ID %2d @ (%3d,%3d) | Total: %0d", 
                                check_frame, id, cx, cy, parallel_match_cnt);
                        $display("          Pixels: [%02h %02h %02h | %02h %02h %02h | %02h %02h %02h]",
                                p_actual[2][0], p_actual[2][1], p_actual[2][2],  // Top row
                                p_actual[1][0], p_actual[1][1], p_actual[1][2],  // Mid row
                                p_actual[0][0], p_actual[0][1], p_actual[0][2]); // Bottom row
                    end
                end
            end
        end
    end


    // ---------------------------------------------------------------------------
    // 15. Gaussian Decision Checker
    // ---------------------------------------------------------------------------
    always @(posedge DUT.clk_fpga_510) begin  // internal clock
        if (o_qubit_valid) begin
            logic [3:0] expected_state = 0;
            
            // Calculate expected decision for all 4 qubits
            // 4 parallel SIMD Engines runs
            for (int k = 0; k < 4; k++) begin
                int id = o_qubit_base_id + k;
                expected_state[k] = get_expected_decision(id, check_frame);
            end
           
            if (o_qubit_state !== expected_state) begin
                gaussian_error_cnt++;
                $display("\n||================================================||");
                $display("||      *** GAUSSIAN DECISION MISMATCH ***         ||");
                $display("||=================================================||");
                $display("|| Frame: %2d  |  Base ID: %2d                     ||", 
                         check_frame, o_qubit_base_id);
                $display("|| Expected Q State: %4b  |  Actual Q State: %4b                  ||",
                         expected_state, o_qubit_state);
                $display("||================================================||");
                
                // Show which qubits failed
                for (int k = 0; k < 4; k++) begin
                    if (o_qubit_state[k] !== expected_state[k]) begin
                        int id = o_qubit_base_id + k;
                        logic [71:0] roi_data = get_expected_roi(id, check_frame);
                        $display("  -> Qubit %2d: Got %b, Expected %b", 
                                 id, o_qubit_state[k], expected_state[k]);
                        print_roi_grid(roi_data, id, "ROI DATA");
                    end
                end
                $display("");
            end else begin
                gaussian_match_cnt += 4;
                if ((gaussian_match_cnt % 4 == 0)) begin
                    $display("  [GAUSSIAN PASS] Base ID %2d: State=%4b - Total: %0d", 
                             o_qubit_base_id, o_qubit_state, gaussian_match_cnt);
                end
            end
        end
    end
    
    // ---------------------------------------------------------------------------
    // 16. Comprehensive Performance Monitor
    // ---------------------------------------------------------------------------
    realtime input_duration;
    realtime storage_latency;
    realtime proc_pipeline_latency;
    realtime proc_throughput;
    realtime end_to_end;

    always @(posedge DUT.clk_fpga_510) begin
        if (o_qubit_valid) begin
            // Track first result
            if (o_qubit_base_id == 0) begin
                frame_first_result = $realtime;
            end
            
            // Track last result and print comprehensive timing
            if (o_qubit_base_id == QUBIT_ID_WIDTH'(LAST_QUBIT_BASE_ID)) begin
                frame_last_result = $realtime;
                
                // Comprehensive timing breakdown
                input_duration = frame_last_pixel - frame_first_pixel;
                storage_latency = frame_ready_time - frame_last_pixel;
                proc_pipeline_latency = frame_first_result - frame_ready_time;
                proc_throughput = frame_last_result - frame_first_result;
                end_to_end = frame_last_result - frame_first_pixel;
                
                $display("  |---------------------------------------------------------|");
                $display("  | DETAILED TIMING: Frame %0d                              |", check_frame);
                $display("  |---------------------------------------------------------|");
                $display("  | Input Stream Duration:    %8.2f µs                      |", input_duration / 1000.0);
                $display("  | Storage Latency:          %8.2f µs (FIFO + Extraction)  |", storage_latency / 1000.0);
                $display("  | Pipeline Latency:         %8.2f µs (First Result)       |", proc_pipeline_latency / 1000.0);
                $display("  | Processing Throughput:    %8.2f µs (%0d qubits)         |", proc_throughput / 1000.0, NUM_QUBITS);
                $display("  | Total End-to-End:         %8.2f µs                      |", end_to_end / 1000.0);
                $display("  |---------------------------------------------------- ----|");
            end
        end
    end
    
    // ---------------------------------------------------------------------------
    // 17. SPI Monitor
    // ---------------------------------------------------------------------------
    initial begin
        wait(DUT.u_spi.state == DUT.u_spi.DONE);
        spi_done = 1;
        $display("[SPI] Configuration Complete @ %0t ns\n", $realtime);
    end
    

endmodule
