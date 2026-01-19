`timescale 1ns / 1ps
//-----------------------------------------------------------------=
// Module: spi_config
// Synchronous SPI Master for FMC-200A Camera Link Configuration
// Optimized for 500 MHz operation with timing-friendly sync reset
//
// Features:
//   - Synchronous reset for better timing closure @ 500 MHz
//   - Synthesizable ROM via pure function
//   - SPI Mode 0 (CPOL=0, CPHA=0) per FMC-200A spec
//   - Auto-configuration on startup for Base Camera Link mode
//-----------------------------------------------------------------

module spi_config (
    // System Interface
    input  logic i_clk,        // 500 MHz System Clock
    input  logic i_rst_n,      // Active-Low Synchronous Reset
    input  logic i_init_en,    // Start Configuration (tie high for auto-start)
    
    // SPI Physical Interface (to FMC-200A FPGA)
    output logic o_mosi,       // Master Out Slave In
    input  logic i_miso,       // Master In Slave Out (unused in this design)
    output logic o_clk,        // SPI Clock (SCLK) ~20.8 MHz
    output logic o_ss          // Slave Select (Active Low)
);

    //-----------------------------------------------------------------
    // PARAMETERS
    //-----------------------------------------------------------------
    localparam int CLK_DIV     = 26; // for 510MHz // 24;  // 500 MHz / 24 = 20.833 MHz SPI Clock
    localparam int NUM_CMDS    = 4;   // Number of config commands
    localparam int TRANS_BITS  = 15;  // SPI transaction size

    //-----------------------------------------------------------------
    // FSM STATE ENCODING
    //-----------------------------------------------------------------
    typedef enum logic [2:0] {
        IDLE,       // Wait for init trigger
        START,      // Assert SS, load command
        TX_BIT,     // Shift out bits
        NEXT_CMD,   // Deassert SS, advance to next command
        DONE        // All configs sent, hold here
    } state_t;
    
    state_t state, state_next;

    //-----------------------------------------------------------------
    // SYNTHESIZABLE ROM: FMC-200A BASE MODE CONFIGURATION
    //-----------------------------------------------------------------
    // Configuration Sequence for Base Mode:
    //   1. Mode Configuration (0x00): Base mode, cameras out of reset
    //   2. Camera A Setup (0x15): 8-bit pixels, 3 channels (24-bit total)
    //   3. X Bit Slip (0x06): Default alignment value
    //   4. Camera A Control (0x09): CC pins to GPIO mode
    
    function automatic logic [15:0] get_fmc_config(input int idx);
        case (idx)
            0: return 16'h0003;  // Addr 0x00: Base mode, cameras active
            1: return 16'h1530;  // Addr 0x15: 8-bit, 3 channels
            2: return 16'h0605;  // Addr 0x06: X bit slip = 5
            3: return 16'h0900;  // Addr 0x09: CC to GPIO
            default: return 16'h0000;
        endcase
    endfunction

    //-----------------------------------------------------------------
    // INTERNAL SIGNALS
    //-----------------------------------------------------------------
    // Clock divider
    logic [7:0]  clk_cnt;
    logic        sclk_reg;
    logic        sclk_rise, sclk_fall;
    
    // FSM control
    logic [3:0]  cmd_idx;
    logic [4:0]  bit_cnt;
    logic [15:0] shift_reg;
    logic [15:0] current_cmd;
    
    // Next-state outputs
    logic        o_mosi_next;
    logic        o_ss_next;

    //-----------------------------------------------------------------
    // SPI CLOCK GENERATION
    //-----------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            clk_cnt   <= 8'd0;
            sclk_reg  <= 1'b0;
            sclk_rise <= 1'b0;
            sclk_fall <= 1'b0;
        end else begin
            sclk_rise <= 1'b0;
            sclk_fall <= 1'b0;
            
            if (clk_cnt == (CLK_DIV/2 - 1)) begin
                clk_cnt  <= 8'd0;
                sclk_reg <= ~sclk_reg;
                
                if (sclk_reg == 1'b0)
                    sclk_rise <= 1'b1;
                else
                    sclk_fall <= 1'b1;
            end else begin
                clk_cnt <= clk_cnt + 8'd1;
            end
        end
    end
    
    assign o_clk = (o_ss) ? 1'b0 : sclk_reg;

    //-----------------------------------------------------------------
    // SPI MASTER FSM - STATE REGISTER
    //-----------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            state       <= IDLE;
            o_ss        <= 1'b1;
            o_mosi      <= 1'b0;
            cmd_idx     <= 4'd0;
            bit_cnt     <= 5'd0;
            shift_reg   <= 16'd0;
            current_cmd <= 16'd0;
        end else begin
            state  <= state_next;
            o_ss   <= o_ss_next;
            o_mosi <= o_mosi_next;
            
            case (state)
                IDLE: begin
                    if (i_init_en) begin
                        cmd_idx     <= 4'd0;
                        current_cmd <= get_fmc_config(4'd0);
                    end
                end

                START: begin
                    if (sclk_fall) begin
                        shift_reg <= current_cmd;
                        bit_cnt   <= 5'd15;
                    end
                end

                TX_BIT: begin
                    if (sclk_fall) begin
                        if (bit_cnt != 5'd0) begin
                            bit_cnt   <= bit_cnt - 5'd1;
                            shift_reg <= {shift_reg[14:0], 1'b0};
                        end
                    end
                end

                NEXT_CMD: begin
                    if (sclk_fall) begin
                        if (cmd_idx != NUM_CMDS - 1) begin
                            cmd_idx     <= cmd_idx + 4'd1;
                            current_cmd <= get_fmc_config(cmd_idx + 4'd1);
                        end
                    end
                end

                DONE: begin
                    // Stay here
                end
                
                default: begin
                    // Error state
                end
            endcase
        end
    end

    //-----------------------------------------------------------------
    // FSM - NEXT STATE & OUTPUT LOGIC
    //-----------------------------------------------------------------
    always_comb begin
        // Default assignments
        state_next  = state;
        o_ss_next   = o_ss;
        o_mosi_next = o_mosi;
        
        case (state)
            IDLE: begin
                o_ss_next   = 1'b1;
                o_mosi_next = 1'b0;
                
                if (i_init_en) begin
                    state_next = START;
                end
            end

            START: begin
                o_ss_next = 1'b0;
                
                if (sclk_fall) begin
                    o_mosi_next = current_cmd[15];
                    state_next  = TX_BIT;
                end
            end

            TX_BIT: begin
                if (sclk_fall) begin
                    if (bit_cnt == 5'd0) begin
                        state_next = NEXT_CMD;
                    end else begin
                        o_mosi_next = shift_reg[14];
                    end
                end
            end

            NEXT_CMD: begin
                if (sclk_fall) begin
                    o_ss_next   = 1'b1;
                    o_mosi_next = 1'b0;
                    
                    if (cmd_idx == NUM_CMDS - 1) begin
                        state_next = DONE;
                    end else begin
                        state_next = START;
                    end
                end
            end

            DONE: begin
                o_ss_next   = 1'b1;
                o_mosi_next = 1'b0;
            end
            
            default: begin
                state_next  = IDLE;
                o_ss_next   = 1'b1;
                o_mosi_next = 1'b0;
            end
        endcase
    end

    //-----------------------------------------------------------------
    // UNUSED SIGNAL HANDLING
    //-----------------------------------------------------------------
    logic _unused_ok;
    assign _unused_ok = &{1'b0, i_miso, 1'b0};

endmodule
