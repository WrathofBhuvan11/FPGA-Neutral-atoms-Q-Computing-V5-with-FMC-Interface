`timescale 1ns / 1ps

module fmc_receiver #(
    parameter H_RES = IMAGE_WIDTH, 
    parameter V_RES = IMAGE_HEIGHT
)(
    input logic i_cam_clk,       
    input logic i_clk_500,       
    input logic i_rst_n,         
    input logic [23:0] i_cam_data,
    input logic i_cam_fval,
    input logic i_cam_lval,
    input logic i_cam_dval,
    
    // pixel outputs
    output logic o_pixel_valid,
    output logic [7:0] o_pixel_data,
    output logic [COORD_WIDTH-1:0] o_pixel_x,
    output logic [COORD_WIDTH-1:0] o_pixel_y,

    // Synchronization flag outputs for ROI extractor
    output logic o_frame_done,      // Single-cycle pulse on falling edge of FVAL
    output logic o_sync_lval,       // Line Valid synchronized to 500MHz
    output logic o_sync_fval,       // Frame Valid synchronized to 500MHz
    output logic o_fifo_empty,      // FIFO empty status (debug)
    output logic o_fifo_full        // FIFO full status (debug)
);

    localparam FIFO_WIDTH = 27; 
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
            fifo_din <= {i_cam_fval, i_cam_lval, i_cam_dval, i_cam_data};
            fifo_wr_en <= 1'b1; 
        end
    end

    // Unpacking Logic
    logic [2:0] state;
   
    // 512x512 max
    logic [COORD_WIDTH-1:0] x, y;

    logic [23:0] current_group;
    logic fval, lval, dval; 
    logic prev_lval;
    logic prev_fval; // Added to reset Y on frame start

    // Expose synchronized control signals
    assign o_sync_fval = fval;
    assign o_sync_lval = lval;
    
    always_ff @(posedge i_clk_500) begin
        if (!i_rst_n) begin
            state          <= 3'd0;
            fifo_rd_en     <= 1'b0;
            o_pixel_valid  <= 1'b0;
            o_pixel_data   <= 8'd0;
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
                3'd0: begin // IDLE
                    if (!fifo_empty) begin
                        // Extract sync signals from FIFO
                        fval = fifo_dout[26];
                        lval = fifo_dout[25];
                        dval = fifo_dout[24];
                        
                        fifo_rd_en <= 1'b1;

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

                        if (lval && dval) begin
                            current_group <= fifo_dout[23:0];
                            state         <= 3'd2;
                        end else begin
                            state <= 3'd0;
                        end
                    end
                end

                3'd2: begin // OUTPUT P0
                    if (x < (H_RES)) begin 
                        o_pixel_valid <= 1'b1;
                        o_pixel_data  <= current_group[7:0];
                        o_pixel_x     <= x;
                        o_pixel_y     <= y;
                    end
                    x     <= x + 1;
                    state <= 3'd3;
                end

                3'd3: begin // OUTPUT P1
                    if (x < (H_RES)) begin
                        o_pixel_valid <= 1'b1;
                        o_pixel_data  <= current_group[15:8];
                        o_pixel_x     <= x;
                        o_pixel_y     <= y;
                    end
                    x     <= x + 1;
                    state <= 3'd4;
                end

                3'd4: begin // OUTPUT P2
                    if (x < (H_RES)) begin
                        o_pixel_valid <= 1'b1;
                        o_pixel_data  <= current_group[23:16];
                        o_pixel_x     <= x;
                        o_pixel_y     <= y;
                    end
                    x     <= x + 1;
                    state <= 3'd0; 
                end
            endcase
        end
    end
endmodule
