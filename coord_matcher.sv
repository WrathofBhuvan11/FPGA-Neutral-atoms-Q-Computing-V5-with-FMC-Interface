//-------------------------------------------------------------------====
// coord_matcher.sv - Parallel 2-Pixel Coordinate Matching
//-------------------------------------------------------------------====
// - Checks both Pixel 0 and Pixel 1 against qubit LUT simultaneously
// - Outputs match_offset to indicate which pixel matched
// - Compatible with 2-pixel-per-cycle FMC receiver @ 510 MHz
// - Maintained 2-stage pipeline (compare ? priority encode)
//-------------------------------------------------------------------====

`timescale 1ns / 1ps
import params_pkg::*;

module coord_matcher (
    input  logic       i_clk,
    input  logic       i_rst_n,
    
    // Pixel Stream from FMC Receiver (now carries 2 pixels)
    input  logic [COORD_WIDTH-1:0] i_curr_x,  // X coordinate of Pixel 0
    input  logic [COORD_WIDTH-1:0] i_curr_y,
    input  logic       i_valid,

    // Synchronized Control Signals from FMC Receiver
    input  logic       i_sync_lval,    // Line valid @ 510 MHz
    input  logic       i_sync_fval,    // Frame valid @ 510 MHz
    
    // Match Outputs
    output logic       o_match_found,
    output logic [QUBIT_ID_WIDTH-1:0] o_qubit_index,
    output logic       o_match_offset,  // 0=Pixel 0 matched, 1=Pixel 1 matched
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
    // Pipeline Stage 1: Parallel Comparison (2 Pixels)
    //-------------------------------------------------------------------
    // TRIGGER LOGIC (for 2-pixel mode):
    // - FMC receiver outputs 2 pixels per cycle at 510 MHz
    // - X coordinate represents Pixel 0, Pixel 1 is at X+1
    // - Check both pixels against qubit center +1 position
    // - Track which pixel matched via match_offset
    //
    // WINDOW CAPTURE GEOMETRY:
    // - For qubit at (Qx, Qy), 3x3 window:
    //   [Qx-1, Qx, Qx+1] x [Qy-2, Qy-1, Qy]
    // - Trigger when either pixel is at (Qx+1, Qy)
    //-------------------------------------------------------------------
    
    logic [NUM_QUBITS-1:0] matches_;
    logic [NUM_QUBITS-1:0] match_offset_reg;  // Track which pixel matched
    logic valid_p1;
    logic sync_lval_p1, sync_fval_p1;  // Pipeline sync signals for diagnostics
    logic match_p1, match_p0;
    
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            matches_         <= '0;
            match_offset_reg <= '0;
            valid_p1         <= 1'b0;
            sync_lval_p1     <= 1'b0;
            sync_fval_p1     <= 1'b0;
        end else begin
            // Pipeline valid and sync signals
            valid_p1     <= i_valid;
            sync_lval_p1 <= i_sync_lval;
            sync_fval_p1 <= i_sync_fval;
            
            if (i_valid && i_sync_fval && i_sync_lval) begin
                // Only match during active frame and line
                for (int i = 0; i < NUM_QUBITS; i++) begin
                    // Check BOTH pixels in the pair
                    match_p0 = (i_curr_x == (q_x[i] + 'd1)) && (i_curr_y == q_y[i]);
                    match_p1 = ((i_curr_x + 1) == (q_x[i] + 'd1)) && (i_curr_y == q_y[i]);
                    
                    if (match_p0 || match_p1) begin
                        matches_[i] <= 1'b1;
                        match_offset_reg[i] <= match_p1;  // 0 for P0, 1 for P1
                    end else begin
                        matches_[i] <= 1'b0;
                        match_offset_reg[i] <= 1'b0;
                    end
                end
            end else begin
                // Clear matches outside active region or when invalid
                matches_ <= '0;
                match_offset_reg <= '0;
            end
        end
    end

    //-------------------------------------------------------------------
    // Pipeline Stage 2: Priority Encoder
    //-------------------------------------------------------------------
    // Outputs the matched qubit index and which pixel matched
    //-------------------------------------------------------------------
    
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            o_match_found  <= 1'b0;
            o_qubit_index  <= 'd0;
            o_match_offset <= 1'b0;
            o_valid_out    <= 1'b0;
        end else begin
            o_valid_out <= valid_p1;
            
            // Default: No match
            o_match_found  <= 1'b0;
            o_qubit_index  <= 'd0;
            o_match_offset <= 1'b0;
            
            // Priority encode from high to low (lower index has priority)
            for (int i = NUM_QUBITS-1; i >= 0; i--) begin
                if (matches_[i]) begin
                    o_match_found  <= 1'b1;
                    o_qubit_index  <= QUBIT_ID_WIDTH'(i);
                    o_match_offset <= match_offset_reg[i];
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
