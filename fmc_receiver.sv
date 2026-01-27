`timescale 1ns / 1ps

module fmc_receiver #(
    parameter H_RES = IMAGE_WIDTH, 
    parameter V_RES = IMAGE_HEIGHT
)(
    input logic i_cam_clk,       
    input logic i_clk_500,       
    input logic i_rst_n,         
    input logic [63:0] i_cam_data, // Changed from [23:0] to [63:0] (8 pixels)
    input logic i_cam_fval,
    input logic i_cam_lval,
    input logic i_cam_dval,
    
    // pixel outputs
    output logic o_pixel_valid,
    output logic [15:0] o_pixel_data, // from [7:0] to [15:0] (2 pixels)
    output logic [COORD_WIDTH-1:0] o_pixel_x,
    output logic [COORD_WIDTH-1:0] o_pixel_y,

    // Synchronization flag outputs for ROI extractor
    output logic o_frame_done,      // Single-cycle pulse on falling edge of FVAL
    output logic o_sync_lval,       // Line Valid synchronized to 500MHz
    output logic o_sync_fval,       // Frame Valid synchronized to 500MHz
    output logic o_fifo_empty,      // FIFO empty status (debug)
    output logic o_fifo_full        // FIFO full status (debug)
);

    // Step A: FIFO Configuration
    // 64 bits data + 3 bits sync = 67 bits
    localparam FIFO_WIDTH = 67; 
    localparam FIFO_DEPTH = 1024;

    logic [FIFO_WIDTH-1:0] fifo_din, fifo_dout;
    logic fifo_wr_en, fifo_rd_en;
    logic fifo_empty, fifo_full;

    xpm_fifo_async #(
        .FIFO_MEMORY_TYPE("auto"),
        .FIFO_WRITE_DEPTH(FIFO_DEPTH),
        .WRITE_DATA_WIDTH(FIFO_WIDTH),
        .READ_MODE("fwft"),             
        .FIFO_READ_LATENCY(0),
        .READ_DATA_WIDTH(FIFO_WIDTH),
        .RD_DATA_COUNT_WIDTH($clog2(FIFO_DEPTH)+1),
        .WR_DATA_COUNT_WIDTH($clog2(FIFO_DEPTH)+1)
    ) fifo_inst (
        .rst(~i_rst_n),
        .wr_clk(i_cam_clk),
        .wr_en(fifo_wr_en),
        .din(fifo_din),
        .full(fifo_full),
        .rd_clk(i_clk_500),
        .rd_en(fifo_rd_en),
        .dout(fifo_dout),
        .empty(fifo_empty),
        .sleep(1'b0)
    );

    // Expose FIFO status for debug
    assign o_fifo_empty = fifo_empty;
    assign o_fifo_full  = fifo_full;

    // Write Logic
    always_ff @(posedge i_cam_clk) begin
        if (!i_rst_n) fifo_wr_en <= 1'b0;
        else begin
            // Pack sync signals + 64-bit data
            fifo_din <= {i_cam_fval, i_cam_lval, i_cam_dval, i_cam_data};
            fifo_wr_en <= 1'b1; 
        end
    end

    // Unpacking Logic
    // Step C: FSM States
    typedef enum logic [2:0] {
        IDLE,
        OUTPUT_01,
        OUTPUT_23,
        OUTPUT_45,
        OUTPUT_67
    } state_t;

    state_t state;
   
    // 512x512 max
    logic [COORD_WIDTH-1:0] x, y;

    logic [63:0] current_group; // Holds the 8 pixels
    logic fval, lval, dval; 
    logic prev_lval;
    logic prev_fval; // Added to reset Y on frame start

    // Expose synchronized control signals
    assign o_sync_fval = fval;
    assign o_sync_lval = lval;
   
    // ROI: win_r0[1]=P0, win_r0[0]=P1. Correct [P0, P1] spatial order.
    always_ff @(posedge i_clk_500) begin
        if (!i_rst_n) begin
            state          <= IDLE;
            fifo_rd_en     <= 1'b0;
            o_pixel_valid  <= 1'b0;
            o_pixel_data   <= 16'd0;
            x              <= '0;
            y              <= '0;
            prev_lval      <= 1'b0;
            prev_fval      <= 1'b0;
            o_frame_done   <= 1'b0;
            fval           <= 1'b0;
            lval           <= 1'b0;
            dval           <= 1'b0;
        end else begin
            fifo_rd_en    <= 1'b0; 
            o_pixel_valid <= 1'b0;
            o_frame_done  <= 1'b0;  // Default: no frame done pulse

            case (state)
                IDLE: begin 
                    if (!fifo_empty) begin
                        // Extract sync signals from FIFO (Upper 3 bits of 67)
                        fval = fifo_dout[66];
                        lval = fifo_dout[65];
                        dval = fifo_dout[64];
                        
                        fifo_rd_en <= 1'b1; // Pop the word

                        // Rising Edge of FVAL = Reset Frame
                        if (fval && !prev_fval) begin
                            y <= '0;
                            x <= '0;
                        end
                        
                        // Falling Edge of FVAL = Frame Done (single-cycle pulse)
                        if (!fval && prev_fval) begin
                            o_frame_done <= 1'b1;
                        end
                        
                        prev_fval <= fval;

                        // Falling Edge of LVAL = End of Line, Increment Y
                        if (fval && prev_lval && !lval) begin
                            x <= '0;
                            y <= y + 1;
                        end
                        prev_lval <= lval;

                        // Check for valid data payload
                        if (lval && dval) begin
                            current_group <= fifo_dout[63:0]; // Capture 8 pixels
                            state         <= OUTPUT_01;
                        end else begin
                            state <= IDLE;
                        end
                    end
                end

                OUTPUT_01: begin // Step B & C: Output Pixels 0 & 1
                    if (x < (H_RES)) begin 
                        o_pixel_valid <= 1'b1;
                        o_pixel_data  <= current_group[15:0];
                        // o_pixel_data <= {current_group[7:0], current_group[15:8]}; 
                        o_pixel_x     <= x;
                        o_pixel_y     <= y;
                        x             <= x + 2; // Increment by 2
                    end
                    state <= OUTPUT_23;
                end

                OUTPUT_23: begin // Output Pixels 2 & 3
                    if (x < (H_RES)) begin
                        o_pixel_valid <= 1'b1;
                        o_pixel_data  <= current_group[31:16];
                        // o_pixel_data <= {current_group[23:16], current_group[31:24]};
                        o_pixel_x     <= x;
                        o_pixel_y     <= y;
                        x             <= x + 2;
                    end
                    state <= OUTPUT_45;
                end

                OUTPUT_45: begin // Output Pixels 4 & 5
                    if (x < (H_RES)) begin
                        o_pixel_valid <= 1'b1;
                        o_pixel_data  <= current_group[47:32];
                        // o_pixel_data <= {current_group[39:32], current_group[47:40]};
                        o_pixel_x     <= x;
                        o_pixel_y     <= y;
                        x             <= x + 2;
                    end
                    state <= OUTPUT_67; 
                end

                OUTPUT_67: begin // Output Pixels 6 & 7
                    if (x < (H_RES)) begin
                        o_pixel_valid <= 1'b1;
                        o_pixel_data  <= current_group[63:48];
                        // o_pixel_data <= {current_group[55:48], current_group[63:56]};
                        o_pixel_x     <= x;
                        o_pixel_y     <= y;
                        x             <= x + 2;
                    end
                    state <= IDLE; // Done with this group
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule
