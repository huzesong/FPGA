///////////////////////////////////////////////////////////////////////////////
// Module: aurora_tx_module
// Description: TX data path module for Aurora 64B66B (Streaming mode).
//
// This module provides a user-facing data interface and converts it to
// AXI4-Stream format for the Aurora IP core TX path.
//
// Streaming mode: No tlast or tkeep signals. Data flows continuously
// as a stream without frame boundaries.
//
// Features:
//   - Simple user interface (data, valid, ready)
//   - AXI4-Stream TX output to Aurora IP (Streaming: tdata, tvalid, tready)
//   - Handles back-pressure from Aurora (s_axi_tx_tready)
//   - Data gating when channel is not up
//
// Data width: 256 bits (4 lanes x 64 bits)
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module aurora_tx_module #(
    parameter DATA_WIDTH = 256                  // AXI4-Stream data width
) (
    //=========================================================================
    // Clock and Reset
    //=========================================================================
    input  wire                     user_clk,       // Aurora user clock
    input  wire                     reset,          // Active-high reset (sync to user_clk)

    //=========================================================================
    // User TX Data Interface
    //=========================================================================
    input  wire [DATA_WIDTH-1:0]    tx_din,         // TX data input
    input  wire                     tx_din_valid,   // TX data valid
    output wire                     tx_ready,       // TX ready (can accept data)

    //=========================================================================
    // Aurora Status
    //=========================================================================
    input  wire                     channel_up,     // Aurora channel is up

    //=========================================================================
    // AXI4-Stream TX Interface (to Aurora IP, Streaming mode)
    //=========================================================================
    output wire [DATA_WIDTH-1:0]    s_axi_tx_tdata,
    output wire                     s_axi_tx_tvalid,
    input  wire                     s_axi_tx_tready
);

    //=========================================================================
    // Internal signals
    //=========================================================================
    wire    tx_enable;          // TX path enable (channel up and not reset)

    //=========================================================================
    // TX Enable Logic
    //
    // Only allow data transmission when:
    //   1. Reset is not active
    //   2. Aurora channel is up (link established)
    //=========================================================================
    assign tx_enable = ~reset & channel_up;

    //=========================================================================
    // AXI4-Stream TX Output (Streaming mode: no tkeep, no tlast)
    //
    // Connect user data interface to Aurora AXI4-Stream TX.
    // Data is gated by tx_enable to prevent sending during link down.
    //=========================================================================
    assign s_axi_tx_tdata  = tx_din;
    assign s_axi_tx_tvalid = tx_din_valid & tx_enable;

    //=========================================================================
    // TX Ready
    //
    // Indicates that the TX path can accept data.
    // Ready when Aurora is ready (tready) and channel is up.
    //=========================================================================
    assign tx_ready = s_axi_tx_tready & tx_enable;

endmodule
