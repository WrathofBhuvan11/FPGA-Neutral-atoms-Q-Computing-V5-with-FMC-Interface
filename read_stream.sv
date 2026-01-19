module read_streamer (
    input               i_clk,
    input               i_rst_n,
    input  logic        i_start,
    
    // Read Interface (To Memory Banks)
    output logic        o_rd_en,
    output logic [BANK_ADDR_WIDTH-1:0]  o_rd_addr, // Row index 0..24
    
    // 4 Parallel Input Lanes (From Memory Banks)
    input  logic [ROI_BITS-1:0] i_rd_data_0,
    input  logic [ROI_BITS-1:0] i_rd_data_1,
    input  logic [ROI_BITS-1:0] i_rd_data_2,
    input  logic [ROI_BITS-1:0] i_rd_data_3,

    // Turbo Parallel Outputs (To Decision Engine)
    output logic [ROI_BITS-1:0] o_pixeldata_lane_0,
    output logic [ROI_BITS-1:0] o_pixeldata_lane_1,
    output logic [ROI_BITS-1:0] o_pixeldata_lane_2,
    output logic [ROI_BITS-1:0] o_pixeldata_lane_3,
    output logic [QUBIT_ID_WIDTH-1:0]  o_pixeldata_lane_base_id, // Identifies the batch (e.g., 0, 4, 8...)
    output logic        o_pixeldata_lane_valid
);

    localparam MAX_ROW = ROWS_PER_BANK - 1;

    // Pipeline Logic
    // Counter and State
    logic [ROW_COUNT_WIDTH-1:0] row_cnt; 
    logic       reading;    
    logic       valid_pipe; 
    logic [QUBIT_ID_WIDTH-1:0] id_pipe;

    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            o_rd_en                  <= 0;
            o_rd_addr                <= 0;
            row_cnt                  <= 0;
            reading                  <= 0;
            
            valid_pipe               <= 0;
            id_pipe                  <= '0;
            
            // Reset Outputs
            o_pixeldata_lane_valid   <= 0;
            o_pixeldata_lane_base_id <= '0;
            o_pixeldata_lane_0       <= '0; o_pixeldata_lane_1 <= '0; 
            o_pixeldata_lane_2       <= '0; o_pixeldata_lane_3 <= '0;
        end else begin
            
            // 1. Address Generation (Full Speed: 1 Row/Cycle)
            if (i_start) begin
                reading   <= 1;
                row_cnt   <= 0;
                o_rd_en   <= 1;
                o_rd_addr <= 0; // Request Row 0
            end else if (reading) begin
                o_rd_en <= 1;
                if (row_cnt == ROW_COUNT_WIDTH'(MAX_ROW)) begin
                    reading <= 0; 
                    row_cnt <= 0;
                    o_rd_en <= 0; // Stop reading
                end else begin
                    row_cnt   <= row_cnt + 1;
                    o_rd_addr <= row_cnt + 1; // Pipeline address for next cycle
                end
            end else begin
                o_rd_en <= 0;
            end

            // 2. Control Pipeline (Intermediate Stage)
            // Cycle 0 (Start): reading <= 1. 
            // Cycle 1: reading is 1. valid_pipe captures 1.
            // Cycle 2: valid_pipe is 1. Output stage captures 1.
            valid_pipe <= reading;
            
            // ID Pipeline
            // Cycle 0: row_cnt resets to 0. id_pipe captures old row_cnt (X).
            // Cycle 1: row_cnt is 0.        id_pipe captures 0.
            // Cycle 2: Output ID registers 0. (Matches Data)
            id_pipe <= QUBIT_ID_WIDTH'(row_cnt << $clog2(NUM_BANKS));


            // 3. Output Stage (Latency = 3 Cycles Total from Start)
            // Cycle 3: o_pixeldata_lane_valid becomes 1.
            o_pixeldata_lane_valid   <= valid_pipe; 
            o_pixeldata_lane_base_id <= id_pipe;
            
            if (valid_pipe) begin
                o_pixeldata_lane_0 <= i_rd_data_0;
                o_pixeldata_lane_1 <= i_rd_data_1;
                o_pixeldata_lane_2 <= i_rd_data_2;
                o_pixeldata_lane_3 <= i_rd_data_3;
            end else begin
                o_pixeldata_lane_valid <= 0;
            end
        end
    end

endmodule
