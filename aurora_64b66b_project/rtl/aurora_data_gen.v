///////////////////////////////////////////////////////////////////////////////
// Module: aurora_data_gen
// Description: Data generation module for Aurora 64B66B (Streaming mode).
//
// Generates a continuous 256-bit data stream where each 32-bit field
// increments by 1 from the previous field. The 256-bit word contains
// 8 x 32-bit fields:
//
//   tx_data = { counter+7, counter+6, counter+5, counter+4,
//               counter+3, counter+2, counter+1, counter+0 }
//
// On each valid data beat (tx_valid & tx_ready), the counter advances
// by 8 so the next beat continues the sequence:
//
//   Beat 0: { 7, 6, 5, 4, 3, 2, 1, 0 }
//   Beat 1: { 15, 14, 13, 12, 11, 10, 9, 8 }
//   Beat 2: { 23, 22, 21, 20, 19, 18, 17, 16 }
//   ...
//
// The module starts generating data once channel_up is asserted and
// respects back-pressure via the tx_ready signal.
//
// Data width: 256 bits (8 x 32-bit incrementing fields)
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module aurora_data_gen #(
    parameter DATA_WIDTH = 256                  // Must be 256 (8 x 32-bit)
) (
    //=========================================================================
    // Clock and Reset
    //=========================================================================
    input  wire                     user_clk,       // Aurora user clock
    input  wire                     reset,          // Active-high reset (sync to user_clk)

    //=========================================================================
    // Control
    //=========================================================================
    input  wire                     channel_up,     // Aurora channel is up
    input  wire                     tx_ready,       // Aurora TX ready (back-pressure)

    //=========================================================================
    // TX Data Output
    //=========================================================================
    output reg  [DATA_WIDTH-1:0]    tx_data,        // 256-bit TX data (8 x 32-bit)
    output reg                      tx_valid        // TX data valid
);

    //=========================================================================
    // Internal signals
    //=========================================================================
    reg  [31:0] counter;        // Base counter for 32-bit incrementing pattern

    //=========================================================================
    // Counter Logic
    //
    // Counter increments by 8 on each valid data beat (since we output
    // 8 x 32-bit values per clock cycle). Counter resets when channel
    // goes down or on system reset.
    //=========================================================================
    always @(posedge user_clk) begin
        if (reset || !channel_up) begin
            counter <= 32'd0;
        end else if (tx_valid && tx_ready) begin
            counter <= counter + 32'd8;
        end
    end

    //=========================================================================
    // Data Generation
    //
    // 256-bit output composed of 8 x 32-bit fields, each incrementing by 1.
    // tx_data[31:0]    = counter + 0
    // tx_data[63:32]   = counter + 1
    // tx_data[95:64]   = counter + 2
    // tx_data[127:96]  = counter + 3
    // tx_data[159:128] = counter + 4
    // tx_data[191:160] = counter + 5
    // tx_data[223:192] = counter + 6
    // tx_data[255:224] = counter + 7
    //=========================================================================
    always @(posedge user_clk) begin
        if (reset || !channel_up) begin
            tx_data  <= {DATA_WIDTH{1'b0}};
            tx_valid <= 1'b0;
        end else begin
            tx_data[ 31:  0] <= counter + 32'd0;
            tx_data[ 63: 32] <= counter + 32'd1;
            tx_data[ 95: 64] <= counter + 32'd2;
            tx_data[127: 96] <= counter + 32'd3;
            tx_data[159:128] <= counter + 32'd4;
            tx_data[191:160] <= counter + 32'd5;
            tx_data[223:192] <= counter + 32'd6;
            tx_data[255:224] <= counter + 32'd7;
            tx_valid         <= 1'b1;
        end
    end

endmodule
