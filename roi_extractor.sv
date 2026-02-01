//-----------------------------------------------------------------
// roi_extractor.sv - Wide ROI Extraction (2-Pixel Mode)
//-----------------------------------------------------------------
// - Handles 16-bit input (2 pixels per cycle)
// - 4-column sliding window to support both pixel positions
// - Dynamic window selection based on match_offset
// - Compatible with 510 MHz 2-pixel-per-cycle processing
//-----------------------------------------------------------------

`timescale 1ns / 1ps
import params_pkg::*;

module roi_extractor (
    input  logic       i_clk,
    input  logic       i_rst_n,
    
    // Pixel Stream from FMC Receiver (16-bit for 2 pixels)
    input  logic [15:0] i_pixel_data,  // [15:8]=Pixel 1, [7:0]=Pixel 0
    input  logic       i_pixel_valid,
    
    // Synchronized Control Signals from FMC Receiver
    input  logic       i_sync_lval,    // Line valid @ 510 MHz
    input  logic       i_sync_fval,    // Frame valid @ 510 MHz
    
    // Match Trigger from Coord Matcher
    input  logic       i_match_trigger,
    input  logic       i_match_offset,  // Which pixel matched (0/1)
    input  logic [QUBIT_ID_WIDTH-1:0] i_qubit_index,

    // Output to ROI Storage
    output logic [ROI_BITS-1:0] o_roi_flat,
    output logic [QUBIT_ID_WIDTH-1:0] o_qubit_index,
    output logic                o_write_enable
);

    //-----------------------------------------------------------------
    // Line Buffers - Store 2 Previous Rows (WIDE: 16-bit)
    //-----------------------------------------------------------------
    // Each entry stores 2 pixels (16 bits)
    // Buffer depth is halved since we store 2 pixels per address
    localparam LB_DEPTH = (IMAGE_WIDTH + 1) / 2;  // Ceil division
    
    (* ram_style = "block" *) logic [15:0] lb0 [0:LB_DEPTH-1];  // Y-1
    (* ram_style = "block" *) logic [15:0] lb1 [0:LB_DEPTH-1];  // Y-2
    
    //-----------------------------------------------------------------
    // Pointer Management
    //-----------------------------------------------------------------
    logic [COORD_WIDTH-1:0] wr_ptr;   // Write pointer (counts pixel pairs)
    logic [COORD_WIDTH-1:0] rd_ptr;   // Read pointer
    
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
    // Sliding Window Registers - 4 Columns x 3 Rows
    //-----------------------------------------------------------------
    // Expanded to 4 columns to handle both pixel alignment cases
    // Col 0 is newest, Col 3 is oldest
    logic [7:0] win_r0 [0:3];  // Current row (Y)
    logic [7:0] win_r1 [0:3];  // Previous row (Y-1)
    logic [7:0] win_r2 [0:3];  // Two rows back (Y-2)
    
    // Data read from line buffers (16 bits = 2 pixels)
    logic [15:0] r_lb0, r_lb1;
    
    //-----------------------------------------------------------------
    // Pipeline Stage 1: Input Delay for Alignment
    //-----------------------------------------------------------------
    logic [15:0] pixel_d1;
    logic       valid_d1;
    logic       match_d1;
    logic       offset_d1;
    logic [QUBIT_ID_WIDTH-1:0] index_d1;
    
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            pixel_d1  <= '0;
            valid_d1  <= 1'b0;
            match_d1  <= 1'b0;
            offset_d1 <= 1'b0;
            index_d1  <= '0;
        end else begin
            pixel_d1  <= i_pixel_data;
            valid_d1  <= i_pixel_valid;
            match_d1  <= i_match_trigger;
            offset_d1 <= i_match_offset;
            index_d1  <= i_qubit_index;
        end
    end
    
    //-----------------------------------------------------------------
    // Line Buffer Read Path (Using Read Pointer)
    //-----------------------------------------------------------------
    
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
                // Read from line buffers (16-bit reads)
                r_lb0 <= lb0[rd_ptr];
                r_lb1 <= lb1[rd_ptr];
                
                // Increment read pointer
                if (rd_ptr == LB_DEPTH-1)
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
            
            for (int k = 0; k < 4; k++) begin
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
                
                // Update Line Buffers (Cascade Write) - 16 bits
                lb0[wr_ptr] <= pixel_d1;   // Store 2 pixels to LB0
                lb1[wr_ptr] <= r_lb0;      // Shift LB0 data to LB1
                
                // Update Sliding Window (2 pixels at a time, left-to-right shift)
                // Row 0: Current input row (Y)
                // win_r0[3:2] <= win_r0[1:0];              // Shift old columns
                win_r0[3]   <= win_r0[1];                // Shift old columns
                win_r0[2]   <= win_r0[0];
                win_r0[1]   <= pixel_d1[15:8];           // Pixel 1
                win_r0[0]   <= pixel_d1[7:0];            // Pixel 0
                
                 // Row 1: From LB0 (Y-1)
                win_r1[3]   <= win_r1[1];
                win_r1[2]   <= win_r1[0];
                win_r1[1]   <= r_lb0[15:8];
                win_r1[0]   <= r_lb0[7:0];
                
                // Row 2: From LB1 (Y-2)
                win_r2[3]   <= win_r2[1];
                win_r2[2]   <= win_r2[0];
                win_r2[1]   <= r_lb1[15:8];
                win_r2[0]   <= r_lb1[7:0];
                
                // Increment write pointer
                if (wr_ptr == LB_DEPTH-1)
                    wr_ptr <= '0;
                else
                    wr_ptr <= wr_ptr + 1;
            end

            // ROI Capture Logic
            o_write_enable <= i_match_trigger && i_sync_fval && i_sync_lval;
            o_qubit_index  <= i_qubit_index;
            
            /*
            if (i_match_trigger && i_sync_fval && i_sync_lval) begin
                // Select 3x3 window
                // Since Qubits are aligned to Even pixels (100, 120...), 
                // ALWAYS want the ROI centered on Pixel 0.
                // Indices: [3]=Left(Old Odd), [0]=Center(New Even), [1]=Right(New Odd)
                
                o_roi_flat <= {
                    win_r0[3], win_r0[0], win_r0[1],  // Bottom row (Y)
                    win_r1[3], win_r1[0], win_r1[1],  // Middle row (Y-1)
                    win_r2[3], win_r2[0], win_r2[1]   // Top row (Y-2)
                };
            end 
            */
            if (i_match_trigger && i_sync_fval && i_sync_lval) begin
                if (i_match_offset == 1'b0) begin
                    // Pixel 0 matched -> Qubit at ODD X
                    // Trigger when i_curr_x = Qx+1 (even)
                    // Window: [3]=Qx, [2]=Qx-1, [1]=Qx+2, [0]=Qx+1
                    // Need: [Qx-1, Qx, Qx+1] = [2, 3, 0]
                    o_roi_flat <= {
                        win_r0[2], win_r0[3], win_r0[0],  // [Qx-1, Qx, Qx+1]
                        win_r1[2], win_r1[3], win_r1[0],
                        win_r2[2], win_r2[3], win_r2[0]
                    };
                end else begin
                    // Pixel 1 matched -> Qubit at EVEN X
                    // Trigger when i_curr_x = Qx (even), Pixel 1 = Qx+1
                    // Window: [3]=Qx-1, [2]=Qx-2, [1]=Qx+1, [0]=Qx
                    // Need: [Qx-1, Qx, Qx+1] = [3, 0, 1]
                    o_roi_flat <= {
                        win_r0[3], win_r0[0], win_r0[1],  // [Qx-1, Qx, Qx+1]
                        win_r1[3], win_r1[0], win_r1[1],
                        win_r2[3], win_r2[0], win_r2[1]
                    };
                end
            end

        end
    end
    

endmodule
