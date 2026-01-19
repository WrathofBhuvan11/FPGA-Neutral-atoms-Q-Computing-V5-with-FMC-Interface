module roi_storage (
    input  logic             i_wr_clk,
    input  logic             i_rd_clk,
    input  logic             i_rst_n,
    
    // Write Port (Sequential - Camera Domain)
    input  logic             i_wr_en,
    input  logic [QUBIT_ID_WIDTH-1:0] i_wr_addr,
    input  logic [ROI_BITS-1:0]       i_wr_data, //ROI_BITS assumed 72
    input  logic             i_frame_done, 
    
    // Read Port (Parallel - FPGA Domain)
    input  logic             i_rd_en,
    input  logic [BANK_ADDR_WIDTH-1:0] i_rd_addr,
    
    // 4 Parallel Output Lanes
    output logic [ROI_BITS-1:0]      o_rd_data_0,
    output logic [ROI_BITS-1:0]      o_rd_data_1,
    output logic [ROI_BITS-1:0]      o_rd_data_2,
    output logic [ROI_BITS-1:0]      o_rd_data_3,
    output logic             o_frame_ready

);

    // 1. Storage: 4 Lanes per Bank (Total 8 small RAM blocks)
    // Depth = 100 qubits / 4 = 25. Using 32 for power of 2.
    (* ram_style = "block" *) logic [ROI_BITS-1:0] bank0_0 [0:BANK_DEPTH-1];
    (* ram_style = "block" *) logic [ROI_BITS-1:0] bank0_1 [0:BANK_DEPTH-1];
    (* ram_style = "block" *) logic [ROI_BITS-1:0] bank0_2 [0:BANK_DEPTH-1];
    (* ram_style = "block" *) logic [ROI_BITS-1:0] bank0_3 [0:BANK_DEPTH-1];

    (* ram_style = "block" *) logic [ROI_BITS-1:0] bank1_0 [0:BANK_DEPTH-1];
    (* ram_style = "block" *) logic [ROI_BITS-1:0] bank1_1 [0:BANK_DEPTH-1];
    (* ram_style = "block" *) logic [ROI_BITS-1:0] bank1_2 [0:BANK_DEPTH-1];
    (* ram_style = "block" *) logic [ROI_BITS-1:0] bank1_3 [0:BANK_DEPTH-1];

    logic wr_bank_sel; 
    logic rd_bank_sel;
    logic frame_done_toggle;
    logic frame_done_sync1, frame_done_sync2, frame_done_sync3;

    // 2. Ping-Pong Control 
    always_ff @(posedge i_wr_clk ) begin
        if (!i_rst_n) begin
            frame_done_toggle <= 1'b0;
            wr_bank_sel <= 1'b0;
        end else if (i_frame_done) begin
            frame_done_toggle <= ~frame_done_toggle;
            wr_bank_sel <= ~wr_bank_sel;
        end
    end

    // 3. Write Logic (Demux to Lanes)
    // Demux logic with parameterized widths
    logic [$clog2(NUM_BANKS)-1:0] lane_sel;
    logic [BANK_ADDR_WIDTH-1:0]   row_addr;
    
    assign lane_sel = i_wr_addr[$clog2(NUM_BANKS)-1:0];
    assign row_addr = i_wr_addr[QUBIT_ID_WIDTH-1:$clog2(NUM_BANKS)];

    always_ff @(posedge i_wr_clk) begin
        if (i_wr_en) begin
            if (wr_bank_sel == 0) begin
                case (lane_sel)
                    2'd0: bank0_0[row_addr] <= i_wr_data;
                    2'd1: bank0_1[row_addr] <= i_wr_data;
                    2'd2: bank0_2[row_addr] <= i_wr_data;
                    2'd3: bank0_3[row_addr] <= i_wr_data;
                endcase
            end else begin
                case (lane_sel)
                    2'd0: bank1_0[row_addr] <= i_wr_data;
                    2'd1: bank1_1[row_addr] <= i_wr_data;
                    2'd2: bank1_2[row_addr] <= i_wr_data;
                    2'd3: bank1_3[row_addr] <= i_wr_data;
                endcase
            end
        end
    end

    // 4. Read Logic (Parallel Read from all 4 Lanes)
    always_ff @(posedge i_rd_clk ) begin
        if (!i_rst_n) begin
            // Reset logic for sync signals
            frame_done_sync1 <= 0; frame_done_sync2 <= 0; frame_done_sync3 <= 0;
            o_frame_ready <= 0; rd_bank_sel <= 1;
        end else begin
            // Sync Logic
            frame_done_sync1 <= frame_done_toggle;
            frame_done_sync2 <= frame_done_sync1;
            frame_done_sync3 <= frame_done_sync2;
            
            if (frame_done_sync2 ^ frame_done_sync3) begin
                o_frame_ready <= 1'b1;
                rd_bank_sel   <= ~frame_done_sync2; 
            end else begin
                o_frame_ready <= 1'b0;
            end

            // Memory Read (Output all 4 lanes)
            if (rd_bank_sel == 0) begin
                o_rd_data_0 <= bank0_0[i_rd_addr];
                o_rd_data_1 <= bank0_1[i_rd_addr];
                o_rd_data_2 <= bank0_2[i_rd_addr];
                o_rd_data_3 <= bank0_3[i_rd_addr];
            end else begin
                o_rd_data_0 <= bank1_0[i_rd_addr];
                o_rd_data_1 <= bank1_1[i_rd_addr];
                o_rd_data_2 <= bank1_2[i_rd_addr];
                o_rd_data_3 <= bank1_3[i_rd_addr];
            end
        end
    end

endmodule

