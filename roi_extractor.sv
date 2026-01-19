//-----------------------------------------------------------------
// roi_extractor.sv - ROI Extraction with FMC Receiver Sync Support
//-----------------------------------------------------------------
// - Enhanced line buffer pointer control using LVAL edges
// - frame/line state tracking for cleaner operation
// - Compatible with new FMC receiver's 3-pixel unpacking FSM
//-----------------------------------------------------------------

`timescale 1ns / 1ps
import params_pkg::*;

module roi_extractor (
    input  logic       i_clk,
    input  logic       i_rst_n,
    
    // Pixel Stream from FMC Receiver
    input  logic [7:0] i_pixel_data,
    input  logic       i_pixel_valid,
    
    // Synchronized Control Signals from FMC Receiver
    input  logic       i_sync_lval,    // Line valid @ 500 MHz
    input  logic       i_sync_fval,    // Frame valid @ 500 MHz
    
    // Match Trigger from Coord Matcher
    input  logic       i_match_trigger,
    input  logic [QUBIT_ID_WIDTH-1:0] i_qubit_index,

    // Output to ROI Storage
    output logic [ROI_BITS-1:0] o_roi_flat,
    output logic [QUBIT_ID_WIDTH-1:0] o_qubit_index,
    output logic                o_write_enable
);

    //-----------------------------------------------------------------
    // Line Buffers - Store 2 Previous Rows
    //-----------------------------------------------------------------
    // Need Y-1 and Y-2 rows to form 3x3 window with current row
    (* ram_style = "block" *) logic [7:0] lb0 [0:IMAGE_WIDTH-1];  // Y-1
    (* ram_style = "block" *) logic [7:0] lb1 [0:IMAGE_WIDTH-1];  // Y-2
    
    //-----------------------------------------------------------------
    // Pointer Management
    //-----------------------------------------------------------------
    logic [COORD_WIDTH-1:0] wr_ptr;   // Write pointer (delayed domain)
    logic [COORD_WIDTH-1:0] rd_ptr;   // Read pointer (immediate domain)
    
    // Edge detection for line buffer pointer reset
    logic sync_lval_r, sync_fval_r;
    
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            sync_lval_r <= 1'b0;
            sync_fval_r <= 1'b0;
        end else begin
            sync_lval_r <= i_sync_lval;
            sync_fval_r <= i_sync_fval;
        end
    end
    
    // Detect line/frame transitions
    wire lval_falling = sync_lval_r && !i_sync_lval;
    wire lval_rising  = !sync_lval_r && i_sync_lval;
    wire fval_falling = sync_fval_r && !i_sync_fval;
    
    //-----------------------------------------------------------------
    // Sliding Window Registers - 3x3 Pixel Array
    //-----------------------------------------------------------------
    logic [7:0] win_r0 [0:2];  // Current row (Y)
    logic [7:0] win_r1 [0:2];  // Previous row (Y-1)
    logic [7:0] win_r2 [0:2];  // Two rows back (Y-2)
    
    // Data read from line buffers
    logic [7:0] r_lb0, r_lb1;
    
    //-----------------------------------------------------------------
    // Pipeline Stage 1: Input Delay for Alignment
    //-----------------------------------------------------------------
    logic [7:0] pixel_d1;
    logic       valid_d1;
    logic       match_d1;
    logic [QUBIT_ID_WIDTH-1:0] index_d1;
    
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            pixel_d1 <= '0;
            valid_d1 <= 1'b0;
            match_d1 <= 1'b0;
            index_d1 <= '0;
        end else begin
            pixel_d1 <= i_pixel_data;
            valid_d1 <= i_pixel_valid;
            match_d1 <= i_match_trigger;
            index_d1 <= i_qubit_index;
        end
    end
    
    //-----------------------------------------------------------------
    // Line Buffer Read Path (Using Read Pointer)
    //-----------------------------------------------------------------
    // Read pointer tracks immediate input to pre-fetch data from line buffers
    // This compensates for 1-cycle BRAM read latency
    
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            rd_ptr <= '0;
        end else begin
            if (fval_falling) begin
                // Reset pointer at end of frame
                rd_ptr <= '0;
            end else if (lval_rising) begin
                // Reset pointer at start of new line
                rd_ptr <= '0;
            end else if (i_pixel_valid && i_sync_lval) begin
                // Read from line buffers
                r_lb0 <= lb0[rd_ptr];
                r_lb1 <= lb1[rd_ptr];
                
                // Increment read pointer
                if (rd_ptr == IMAGE_WIDTH-1)
                    rd_ptr <= '0;
                else
                    rd_ptr <= rd_ptr + 1;
            end
        end
    end
    
    //-----------------------------------------------------------------
    // Main Processing: Window Update & Line Buffer Write
    //-----------------------------------------------------------------
    
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            wr_ptr <= '0;
            o_write_enable <= 1'b0;
            o_qubit_index  <= '0;
            o_roi_flat     <= '0;
            
            for (int k = 0; k < 3; k++) begin
                win_r0[k] <= '0;
                win_r1[k] <= '0;
                win_r2[k] <= '0;
            end
        end else begin
            
            // Pointer Management with Sync Signals
            if (fval_falling) begin
                wr_ptr <= '0;
            end else if (lval_rising) begin
                wr_ptr <= '0;
            end else if (valid_d1 && i_sync_lval) begin
                // Active pixel processing
                
                // Update Line Buffers (Cascade Write)
                lb0[wr_ptr] <= pixel_d1;   // Store current pixel to LB0
                lb1[wr_ptr] <= r_lb0;      // Shift LB0 data to LB1
                
                // Update Sliding Window (Left-to-Right Shift)
                // Row 0: Current input row (Y)
                win_r0[0] <= pixel_d1;
                win_r0[1] <= win_r0[0];
                win_r0[2] <= win_r0[1];
                
                // Row 1: From LB0 (Y-1)
                win_r1[0] <= r_lb0;
                win_r1[1] <= win_r1[0];
                win_r1[2] <= win_r1[1];
                
                // Row 2: From LB1 (Y-2)
                win_r2[0] <= r_lb1;
                win_r2[1] <= win_r2[0];
                win_r2[2] <= win_r2[1];
                
                // Increment write pointer
                if (wr_ptr == IMAGE_WIDTH-1)
                    wr_ptr <= '0;
                else
                    wr_ptr <= wr_ptr + 1;
            end

            // ROI Capture Logic
            o_write_enable <= i_match_trigger && i_sync_fval && i_sync_lval;  // Use i_match_trigger directly
            o_qubit_index  <= i_qubit_index;  //  Use i_qubit_index directly
            
            if (i_match_trigger && i_sync_fval && i_sync_lval) begin  // Use i_match_trigger directly
                o_roi_flat <= {
                    // Pack 3x3 window into 72-bit flat vector
                    win_r0[2], win_r0[1], win_r0[0], // Bottom row (Y)
                    win_r1[2], win_r1[1], win_r1[0], // Middle row (Y-1)
                    win_r2[2], win_r2[1], win_r2[0]  // Top row (Y-2)
                };
            end
             
        end
    end
    
    // DEBUG: Simulation Checks
    // synthesis translate_off
    // Verify pointer doesn't overflow
    always @(posedge i_clk) begin
        if (wr_ptr >= IMAGE_WIDTH)
            $error("DUT - ROI Extractor: Write pointer overflow! wr_ptr=%0d", wr_ptr);
        if (rd_ptr >= IMAGE_WIDTH)
            $error("DUT - ROI Extractor: Read pointer overflow! rd_ptr=%0d", rd_ptr);
    end
    // synthesis translate_on

endmodule
