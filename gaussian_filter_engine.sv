`timescale 1ns / 1ps

module gaussian_filter_engine #(
    // Gaussian Kernel Weights (Fixed Point 8-bit signed)
    // Standard 3x3 approximation:
    // 1  2  1
    // 2  4  2
    // 1  2  1
    parameter signed [7:0] W_00 = 8'd1, parameter signed [7:0] W_01 = 8'd2, parameter signed [7:0] W_02 = 8'd1,
    parameter signed [7:0] W_10 = 8'd2, parameter signed [7:0] W_11 = 8'd4, parameter signed [7:0] W_12 = 8'd2,
    parameter signed [7:0] W_20 = 8'd1, parameter signed [7:0] W_21 = 8'd2, parameter signed [7:0] W_22 = 8'd1,
    
    // Threshold for Decision (Scale this based on pixel brightness)
    // If avg pixel is 50, Sum ~ 800. Threshold at 600.
    parameter int THRESHOLD = 500
)(
    input  logic        i_clk,
    input  logic        i_rst_n,
    input  logic [71:0] i_roi_data,
    input  logic        i_valid,
    input  logic [6:0]  i_base_id,
    
    output logic        o_decision, // 1 = Rydberg, 0 = Ground
    output logic [15:0] o_score,    // Debug score
    output logic [6:0]  o_base_id,  // ALIGNED Output ID
    output logic        o_valid     // ALIGNED Output Valid
);

    // --- Stage 0: Unpacking (Combinational) ---
    // p[row][0] = LEFT, p[row][1] = CENTER, p[row][2] = RIGHT
    logic [7:0] p[2:0][2:0];
    always_comb begin
        // Row 0 (Bottom): LEFT, CENTER, RIGHT
        p[0][0] = i_roi_data[71:64]; p[0][1] = i_roi_data[63:56]; p[0][2] = i_roi_data[55:48];
        // Row 1 (Mid): LEFT, CENTER, RIGHT
        p[1][0] = i_roi_data[47:40]; p[1][1] = i_roi_data[39:32]; p[1][2] = i_roi_data[31:24];
        // Row 2 (Top): LEFT, CENTER, RIGHT
        p[2][0] = i_roi_data[23:16]; p[2][1] = i_roi_data[15:8];  p[2][2] = i_roi_data[7:0];
    end

    // --- Pipeline Registers ---
    // Stage 1: Multiply
    logic signed [15:0] prod_reg [2:0][2:0];
    logic               valid_s1;
    logic [6:0]         id_s1;

    // Stage 2: Partial Sums (breaks critical path)
    logic signed [16:0] sum_row0, sum_row1, sum_row2;
    logic               valid_s2;
    logic [6:0]         id_s2;

    // Stage 3: Final Sum
    logic signed [19:0] sum_total_reg;
    logic               valid_s3;
    logic [6:0]         id_s3;

    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            valid_s1 <= 0; valid_s2 <= 0; valid_s3 <= 0; o_valid <= 0;
            o_decision <= 0; o_score <= 0; o_base_id <= 0;
        end else begin
            // ---------------------------------------------------------------
            // STAGE 1: MULTIPLY (9 parallel multipliers)
            // ---------------------------------------------------------------
            prod_reg[0][0] <= $signed({1'b0, p[0][0]}) * W_00;
            prod_reg[0][1] <= $signed({1'b0, p[0][1]}) * W_01;
            prod_reg[0][2] <= $signed({1'b0, p[0][2]}) * W_02;
            
            prod_reg[1][0] <= $signed({1'b0, p[1][0]}) * W_10;
            prod_reg[1][1] <= $signed({1'b0, p[1][1]}) * W_11;
            prod_reg[1][2] <= $signed({1'b0, p[1][2]}) * W_12;
            
            prod_reg[2][0] <= $signed({1'b0, p[2][0]}) * W_20;
            prod_reg[2][1] <= $signed({1'b0, p[2][1]}) * W_21;
            prod_reg[2][2] <= $signed({1'b0, p[2][2]}) * W_22;
            
            valid_s1 <= i_valid;
            id_s1    <= i_base_id; // Capture ID

            // ---------------------------------------------------------------
            // STAGE 2: PARTIAL SUMS (3 row sums, breaks 9-input adder tree)
            // ---------------------------------------------------------------
            sum_row0 <= prod_reg[0][0] + prod_reg[0][1] + prod_reg[0][2];
            sum_row1 <= prod_reg[1][0] + prod_reg[1][1] + prod_reg[1][2];
            sum_row2 <= prod_reg[2][0] + prod_reg[2][1] + prod_reg[2][2];
                         
            valid_s2 <= valid_s1;
            id_s2    <= id_s1;     // Pipeline ID

            // ---------------------------------------------------------------
            // STAGE 3: FINAL SUM (3-input adder)
            // ---------------------------------------------------------------
            sum_total_reg <= sum_row0 + sum_row1 + sum_row2;
            
            valid_s3 <= valid_s2;
            id_s3    <= id_s2;

            // ---------------------------------------------------------------
            // STAGE 4: DECISION & OUTPUT
            // Critical path = comparator + mux
            // ---------------------------------------------------------------
            if (sum_total_reg > THRESHOLD) o_decision <= 1'b1;
            else                           o_decision <= 1'b0;
            
            o_score   <= sum_total_reg[15:0];
            o_valid   <= valid_s3;
            o_base_id <= id_s3;
        end
    end

endmodule
