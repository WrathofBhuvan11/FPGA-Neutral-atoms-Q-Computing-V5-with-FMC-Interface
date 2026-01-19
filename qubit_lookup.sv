// ---------------------------------------------------------------------------
// Synthesizable Qubit Coordinate Lookup Table (Parallel Array Interface)
// ---------------------------------------------------------------------------
// - Generates all 100 qubit coordinates in parallel using localparam
// - 10x10 grid starting at (100, 100) with 20-pixel spacing
// - Used by coord_matcher for parallel comparison against all qubits
// ---------------------------------------------------------------------------

`timescale 1ns / 1ps
import params_pkg::*;

module qubit_lookup_parallel (
    output logic [COORD_WIDTH-1:0] o_q_x [0:NUM_QUBITS-1],
    output logic [COORD_WIDTH-1:0] o_q_y [0:NUM_QUBITS-1]
);

    // Generate all coordinates combinationally
    // placeholder
    genvar i;
    generate
        for (i = 0; i < NUM_QUBITS; i++) begin : qubit_lookup_gen
            localparam int ROW = i / GRID_COLS;
            localparam int COL = i % GRID_COLS;
            
            assign o_q_x[i] = QUBIT_START_X + (COL * QUBIT_SPACING);
            assign o_q_y[i] = QUBIT_START_Y + (ROW * QUBIT_SPACING);
        end
    endgenerate

endmodule
