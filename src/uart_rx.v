// =============================================================================
// Module: uart_rx
// Description: Standard UART receiver with configurable clock frequency and
//              baud rate. Uses 1 start bit, 8 data bits (LSB first), 1 stop bit,
//              no parity. Input is double-registered for metastability protection.
//
// Parameters:
//   CLK_FREQ  - System clock frequency in Hz (default 50 MHz)
//   BAUD_RATE - UART baud rate (default 9600)
//
// Inputs:
//   clk        - System clock
//   rst_n      - Active-low synchronous reset
//   rx         - UART receive line (idle high)
//
// Outputs:
//   data [7:0] - Received byte (valid when data_valid is high)
//   data_valid - Pulses high for one clock cycle when a valid byte is ready
// =============================================================================
module uart_rx #(
    parameter CLK_FREQ  = 50_000_000,
    parameter BAUD_RATE = 9600
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        data_valid
);

    // Cycles per bit period and half period for mid-bit sampling
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    localparam HALF_BIT     = CLKS_PER_BIT / 2;

    // State encoding
    localparam ST_IDLE  = 2'd0;
    localparam ST_START = 2'd1;
    localparam ST_DATA  = 2'd2;
    localparam ST_STOP  = 2'd3;

    // Double-register the RX line to prevent metastability
    reg rx_ff1, rx_ff2;
    always @(posedge clk) begin
        rx_ff1 <= rx;
        rx_ff2 <= rx_ff1;
    end

    reg  [1:0]  state;
    reg  [15:0] clk_cnt;    // Bit-period counter (up to ~5208 for 9600 baud @ 50 MHz)
    reg  [2:0]  bit_cnt;    // Data bit counter (0-7)
    reg  [7:0]  rx_shift;   // Shift register (LSB first)

    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= ST_IDLE;
            clk_cnt    <= 16'd0;
            bit_cnt    <= 3'd0;
            rx_shift   <= 8'd0;
            data       <= 8'd0;
            data_valid <= 1'b0;
        end else begin
            data_valid <= 1'b0;   // Default: de-assert

            case (state)
                // -----------------------------------------------------------------
                // IDLE: Wait for a falling edge on RX (start bit)
                // -----------------------------------------------------------------
                ST_IDLE: begin
                    if (!rx_ff2) begin
                        state   <= ST_START;
                        clk_cnt <= 16'd0;
                    end
                end

                // -----------------------------------------------------------------
                // START: Sample at the centre of the start bit to confirm it
                // -----------------------------------------------------------------
                ST_START: begin
                    if (clk_cnt == HALF_BIT - 1) begin
                        if (!rx_ff2) begin          // Start bit confirmed
                            state   <= ST_DATA;
                            clk_cnt <= 16'd0;
                            bit_cnt <= 3'd0;
                        end else begin              // Glitch: return to idle
                            state <= ST_IDLE;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                // -----------------------------------------------------------------
                // DATA: Sample each data bit at the centre of its bit period
                // -----------------------------------------------------------------
                ST_DATA: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_shift <= {rx_ff2, rx_shift[7:1]}; // Shift in LSB first
                        clk_cnt  <= 16'd0;
                        if (bit_cnt == 3'd7) begin
                            state <= ST_STOP;
                        end else begin
                            bit_cnt <= bit_cnt + 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                // -----------------------------------------------------------------
                // STOP: Sample the stop bit; output data if it is valid (high)
                // -----------------------------------------------------------------
                ST_STOP: begin
                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        if (rx_ff2) begin           // Valid stop bit
                            data       <= rx_shift;
                            data_valid <= 1'b1;
                        end
                        state   <= ST_IDLE;
                        clk_cnt <= 16'd0;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
