module simple_iserdes_8to1 #(
    parameter real REFCLK_FREQUENCY = 510.0
)(
    input  logic       clk_serial,
    input  logic       clk_serial_inv,  // Dedicated inverted clock from MMCM
    input  logic       clk_parallel,
    input  logic       rst,
    
    input  logic       idelay_rdy,      // From IDELAYCTRL
    input  logic [8:0] idelay_tap,      // Delay value (0-511 taps)
    
    input  logic       data_p,
    input  logic       data_n,
    output logic [7:0] data_out
);

    
    logic data_ibuf;
    logic data_delayed;  // Output from IDELAY
    
    IBUFDS #(
        .DIFF_TERM("TRUE"),
        .IOSTANDARD("LVDS")
    ) ibufds_inst (
        .I(data_p), .IB(data_n), .O(data_ibuf)
    );

    // IDELAY Instance (between IBUFDS and ISERDES)
    IDELAYE3 #(
        .CASCADE("NONE"),
        .DELAY_FORMAT("COUNT"),
        .DELAY_SRC("IDATAIN"),
        .DELAY_TYPE("VAR_LOAD"),
        .DELAY_VALUE(256),               // Default mid-range
        .IS_CLK_INVERTED(1'b0),
        .IS_RST_INVERTED(1'b0),
        .REFCLK_FREQUENCY(REFCLK_FREQUENCY),
        .SIM_DEVICE("ULTRASCALE_PLUS"),
        .UPDATE_MODE("ASYNC")
    ) idelay_inst (
        .CASC_OUT(),
        .CNTVALUEOUT(),
        .DATAOUT(data_delayed),          // To ISERDES
        .CASC_IN(1'b0),
        .CASC_RETURN(1'b0),
        .CE(1'b0),
        .CLK(clk_parallel),
        .CNTVALUEIN(idelay_tap),         // Programmable delay
        .DATAIN(1'b0),
        .EN_VTC(idelay_rdy),             // From IDELAYCTRL
        .IDATAIN(data_ibuf),             // From IBUFDS
        .INC(1'b0),
        .LOAD(1'b1),                     // Always load mode
        .RST(rst)
    );

    logic [7:0] data_raw;
    
    ISERDESE3 #(
        .DATA_WIDTH(8),
        .FIFO_ENABLE("FALSE"),
        .FIFO_SYNC_MODE("FALSE"),
        .IS_CLK_B_INVERTED(1'b0),      // No parameter inversion
        .IS_CLK_INVERTED(1'b0),
        .IS_RST_INVERTED(1'b0),
        .SIM_DEVICE("ULTRASCALE_PLUS")
    ) iserdes_inst (
        .Q(data_raw),
        .CLK(clk_serial),
        .CLK_B(clk_serial_inv),        // Use dedicated inverted clock
        .CLKDIV(clk_parallel),
        .D(data_delayed),                
        .RST(rst),
        .FIFO_RD_CLK(1'b0),
        .FIFO_RD_EN(1'b0),
        .FIFO_EMPTY()
    );

    // Rotation logic stays the same
    logic [7:0] data_prev;
    always_ff @(posedge clk_parallel) begin
        if (rst) begin
            data_prev <= 8'h00;
            data_out  <= 8'h00;
        end else begin
            data_prev <= data_raw;
            data_out <= {data_raw[3:0], data_prev[7:4]};
        end
    end

endmodule
