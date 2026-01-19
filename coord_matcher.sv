//-------------------------------------------------------------------====
// coord_matcher.sv - Coordinate Matching with FMC Receiver FSM Support
//-------------------------------------------------------------------====
// - trigger logic for 3-pixel unpacking FSM timing
// - line/frame tracking for robust pointer management
// - Maintained 2-stage pipeline (compare ? priority encode)
//-------------------------------------------------------------------====

`timescale 1ns / 1ps
import params_pkg::*;

module coord_matcher (
    input  logic       i_clk,
    input  logic       i_rst_n,
    
    // Pixel Stream from FMC Receiver
    input  logic [COORD_WIDTH-1:0] i_curr_x,
    input  logic [COORD_WIDTH-1:0] i_curr_y,
    input  logic       i_valid,

    // Synchronized Control Signals from FMC Receiver
    input  logic       i_sync_lval,    // Line valid @ 500 MHz
    input  logic       i_sync_fval,    // Frame valid @ 500 MHz
    
    // Match Outputs
    output logic       o_match_found,
    output logic [QUBIT_ID_WIDTH-1:0] o_qubit_index,
    output logic       o_valid_out
);

    //-------------------------------------------------------------------
    // Qubit Coordinate Lookup Table
    //-------------------------------------------------------------------
    logic [COORD_WIDTH-1:0] q_x [0:NUM_QUBITS-1];
    logic [COORD_WIDTH-1:0] q_y [0:NUM_QUBITS-1];

    qubit_lookup_parallel u_lut (
        .o_q_x(q_x),
        .o_q_y(q_y)
    );

    //-------------------------------------------------------------------
    // Pipeline Stage 1: Parallel Comparison
    //-------------------------------------------------------------------
    // TRIGGER LOGIC:
    // - FMC receiver unpacks 3 pixels per group with FSM
    // - X counter increments during P0, P1, P2 states
    // - Trigger when current pixel position matches qubit center +1
    //   (accounts for 3x3 window filling from left to right)
    //
    // WINDOW CAPTURE GEOMETRY:
    // - For qubit at (Qx, Qy), 3x3 window:
    //   [Qx-1, Qx, Qx+1] x [Qy-2, Qy-1, Qy]
    // - Trigger when input pixel is at (Qx+1, Qy) - rightmost pixel of bottom row
    // - This ensures the sliding window has filled completely
    //-------------------------------------------------------------------
    
    logic [NUM_QUBITS-1:0] matches_;
    logic valid_p1;
    logic sync_lval_p1, sync_fval_p1;  // Pipeline sync signals for diagnostics
    
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            matches_       <= '0;
            valid_p1       <= 1'b0;
            sync_lval_p1   <= 1'b0;
            sync_fval_p1   <= 1'b0;
        end else begin
            // Pipeline valid and sync signals
            valid_p1     <= i_valid;
            sync_lval_p1 <= i_sync_lval;
            sync_fval_p1 <= i_sync_fval;
            
            if (i_valid && i_sync_fval && i_sync_lval) begin
                // Only match during active frame and line
                for (int i = 0; i < NUM_QUBITS; i++) begin
                    // CRITICAL TRIGGER CONDITION:
                    // Match when X = qubit_x + 1 (one pixel right of center)
                    // and Y = qubit_y (on same row as qubit center)
                    // This captures window [Qx-1, Qx, Qx+1] at Y=[Qy-2, Qy-1, Qy]
                    // because the sliding window has been filling from left-to-right
                    // and will have accumulated the correct 3x3 region
                    if ((i_curr_x == (q_x[i] + 'd1)) && (i_curr_y == q_y[i])) begin
                        matches_[i] <= 1'b1;
                    end else begin
                        matches_[i] <= 1'b0;
                    end
                end
            end else begin
                // Clear matches outside active region or when invalid
                matches_ <= '0;
            end
        end
    end

    //-------------------------------------------------------------------
    // Pipeline Stage 2: Priority Encoder
    //-------------------------------------------------------------------
    // Reverse iteration ensures lower index wins if multiple matches occur
    // (Should never happen with proper qubit spacing, but provides deterministic behavior)
    //-------------------------------------------------------------------
    
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            o_match_found <= 1'b0;
            o_qubit_index <= 'd0;
            o_valid_out   <= 1'b0;
        end else begin
            o_valid_out <= valid_p1;
            
            // Default: No match
            o_match_found <= 1'b0;
            o_qubit_index <= 'd0;
            
            // Priority encode from high to low (lower index has priority)
            for (int i = NUM_QUBITS-1; i >= 0; i--) begin
                if (matches_[i]) begin
                    o_match_found <= 1'b1;
                    o_qubit_index <= QUBIT_ID_WIDTH'(i);
                end
            end
        end
    end



// synthesis translate_off
    // Check that only one match occurs at a time
    logic [7:0] match_count;
    always_comb begin
        match_count = 0;
        for (int i = 0; i < NUM_QUBITS; i++) begin
            match_count += matches_[i];
        end
    end
    
    property p_single_match;
        @(posedge i_clk) disable iff (!i_rst_n)
        (match_count > 0) |-> (match_count == 1);
    endproperty
    
    assert property (p_single_match)
    else $warning("Multiple qubit matches detected at (%0d, %0d) - check qubit spacing!", 
                  i_curr_x, i_curr_y);
// synthesis translate_on
    
endmodule
