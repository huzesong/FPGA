///////////////////////////////////////////////////////////////////////////////
// Module: aurora_rx_module
// Description: RX data path module for Aurora 64B66B (Streaming mode).
//
// This module receives AXI4-Stream data from the Aurora IP core and
// provides a user-facing output interface.
//
// Streaming mode: No tlast or tkeep signals. Data flows continuously
// as a stream without frame boundaries.
//
// Features:
//   - AXI4-Stream RX input from Aurora IP (Streaming: tdata, tvalid)
//   - Simple data output interface (data, valid)
//   - Data gating when channel is not up
//   - Receive beat counter for diagnostics
//   - Error monitoring (hard_err, soft_err)
//
// Data width: 256 bits (4 lanes x 64 bits)
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module aurora_rx_module #(
    parameter DATA_WIDTH = 256                  // AXI4-Stream data width
) (
    //=========================================================================
    // Clock and Reset
    //=========================================================================
    input  wire                     user_clk,       // Aurora user clock
    input  wire                     reset,          // Active-high reset (sync to user_clk)

    //=========================================================================
    // Aurora Status
    //=========================================================================
    input  wire                     channel_up,     // Aurora channel is up
    input  wire                     hard_err,       // Hard error from Aurora
    input  wire                     soft_err,       // Soft error from Aurora

    //=========================================================================
    // AXI4-Stream RX Interface (from Aurora IP, Streaming mode)
    //=========================================================================
    input  wire [DATA_WIDTH-1:0]    m_axi_rx_tdata,
    input  wire                     m_axi_rx_tvalid,

    //=========================================================================
    // User RX Data Interface
    //=========================================================================
    output wire [DATA_WIDTH-1:0]    rx_dout,        // RX data output
    output wire                     rx_dout_valid,  // RX data valid

    //=========================================================================
    // Diagnostics
    //=========================================================================
    output reg  [31:0]              rx_count,       // Received beat counter
    output reg                      rx_error        // RX error flag (hard_err or soft_err)
);

    //=========================================================================
    // Internal signals
    //=========================================================================
    wire    rx_enable;          // RX path enable

    //=========================================================================
    // RX Enable Logic
    //
    // Only pass received data when:
    //   1. Reset is not active
    //   2. Aurora channel is up
    //=========================================================================
    assign rx_enable = ~reset & channel_up;

    //=========================================================================
    // User RX Data Output (Streaming mode: no tkeep, no tlast)
    //
    // Pass AXI4-Stream RX data to user interface.
    // Data is gated by rx_enable.
    //=========================================================================
    assign rx_dout       = rx_enable ? m_axi_rx_tdata : {DATA_WIDTH{1'b0}};
    assign rx_dout_valid = m_axi_rx_tvalid & rx_enable;

    //=========================================================================
    // RX Beat Counter
    //
    // Counts received valid data beats for diagnostics.
    //=========================================================================
    always @(posedge user_clk) begin
        if (reset || !channel_up) begin
            rx_count <= 32'd0;
        end else if (m_axi_rx_tvalid) begin
            rx_count <= rx_count + 32'd1;
        end
    end

    //=========================================================================
    // RX Error Monitoring
    //
    // Captures hard and soft errors from Aurora core.
    //=========================================================================
    always @(posedge user_clk) begin
        if (reset) begin
            rx_error <= 1'b0;
        end else begin
            rx_error <= hard_err | soft_err;
        end
    end

endmodule
