///////////////////////////////////////////////////////////////////////////////
// Module: aurora_top
// Description: Top-level module for dual Aurora 64B66B design (Streaming mode).
//
// This module instantiates two Aurora 64B66B channels on adjacent GT quads
// (GTHQ0 and GTHQ1) with shared clock resources.
//
// Architecture:
//   ┌──────────────────────────────────────────────────────────────┐
//   │                      aurora_top                              │
//   │                                                              │
//   │  ┌──────────────────────────────────────┐                    │
//   │  │        aurora_clock_module            │                    │
//   │  │  ┌───────────┐  ┌────────┐ ┌────────┐│                    │
//   │  │  │IBUFDS_GTE2│  │QPLL(0)│ │QPLL(1)││                    │
//   │  │  └─────┬─────┘  └───┬────┘ └───┬────┘│                    │
//   │  │        │ refclk     │qpll0     │qpll1│                    │
//   │  │        └────────────┼──────────┘     │                    │
//   │  │  ┌──────┐           │                │                    │
//   │  │  │ BUFG ├─ user_clk,sync_clk ──────►│                    │
//   │  │  └──┬───┘                            │                    │
//   │  │     │ tx_out_clk_ch0                 │                    │
//   │  └─────┼────────────────────────────────┘                    │
//   │        │                                                     │
//   │  ┌─────▼──────────┐   ┌──────────────────┐                  │
//   │  │ aurora_channel │   │ aurora_channel   │                  │
//   │  │   Channel 0    │   │   Channel 1     │                  │
//   │  │   (GTHQ0)      │   │   (GTHQ1)       │                  │
//   │  │  ┌───┐ ┌───┐  │   │  ┌───┐ ┌───┐   │                  │
//   │  │  │TX │ │RX │  │   │  │TX │ │RX │   │                  │
//   │  │  └───┘ └───┘  │   │  └───┘ └───┘   │                  │
//   │  │  ┌──────────┐  │   │  ┌──────────┐   │                  │
//   │  │  │Aurora IP │  │   │  │Aurora IP │   │                  │
//   │  │  │(4 lanes) │  │   │  │(4 lanes) │   │                  │
//   │  │  └──────────┘  │   │  └──────────┘   │                  │
//   │  └────────────────┘   └──────────────────┘                  │
//   └──────────────────────────────────────────────────────────────┘
//
// IP Core: Aurora 64B66B (11.2), Streaming mode
// Chip: xc7vx690tffg1927-2L
// Tool: Vivado 2018.3
//
// GT Configuration:
//   - GT Type: v7gth (GTHE2)
//   - Lanes: 4 per channel (8 total)
//   - Channel 0: GTHQ0 (lanes 1-4)
//   - Channel 1: GTHQ1 (lanes 1-4)
//   - GT Refclk1: GTHQ0 (shared to GTHQ1)
//   - GT Refclk2: None
///////////////////////////////////////////////////////////////////////////////

`timescale 1ns / 1ps

module aurora_top #(
    parameter DATA_WIDTH = 256,                 // AXI4-Stream data width (4 lanes x 64 bits)
    parameter LANE_NUM   = 4                    // Number of GT lanes per channel
) (
    //=========================================================================
    // System Clock and Reset
    //=========================================================================
    input  wire                     init_clk_in,        // Board system clock (e.g., 50/100 MHz)
    input  wire                     sys_rst_n,          // Active-low system reset

    //=========================================================================
    // GT Reference Clock (Differential)
    //=========================================================================
    input  wire                     gt_refclk_p,        // GT reference clock positive
    input  wire                     gt_refclk_n,        // GT reference clock negative

    //=========================================================================
    // Channel 0 - GT Serial Interface (GTHQ0)
    //=========================================================================
    input  wire [LANE_NUM-1:0]      ch0_rxp,            // Channel 0 serial RX positive
    input  wire [LANE_NUM-1:0]      ch0_rxn,            // Channel 0 serial RX negative
    output wire [LANE_NUM-1:0]      ch0_txp,            // Channel 0 serial TX positive
    output wire [LANE_NUM-1:0]      ch0_txn,            // Channel 0 serial TX negative

    //=========================================================================
    // Channel 1 - GT Serial Interface (GTHQ1)
    //=========================================================================
    input  wire [LANE_NUM-1:0]      ch1_rxp,            // Channel 1 serial RX positive
    input  wire [LANE_NUM-1:0]      ch1_rxn,            // Channel 1 serial RX negative
    output wire [LANE_NUM-1:0]      ch1_txp,            // Channel 1 serial TX positive
    output wire [LANE_NUM-1:0]      ch1_txn,            // Channel 1 serial TX negative

    //=========================================================================
    // Channel 0 - User TX Data Interface (Streaming mode)
    //=========================================================================
    input  wire [DATA_WIDTH-1:0]    ch0_tx_din,         // Channel 0 TX data
    input  wire                     ch0_tx_din_valid,   // Channel 0 TX data valid
    output wire                     ch0_tx_ready,       // Channel 0 TX ready

    //=========================================================================
    // Channel 1 - User TX Data Interface (Streaming mode)
    //=========================================================================
    input  wire [DATA_WIDTH-1:0]    ch1_tx_din,         // Channel 1 TX data
    input  wire                     ch1_tx_din_valid,   // Channel 1 TX data valid
    output wire                     ch1_tx_ready,       // Channel 1 TX ready

    //=========================================================================
    // Channel 0 - User RX Data Interface (Streaming mode)
    //=========================================================================
    output wire [DATA_WIDTH-1:0]    ch0_rx_dout,        // Channel 0 RX data
    output wire                     ch0_rx_dout_valid,  // Channel 0 RX data valid

    //=========================================================================
    // Channel 1 - User RX Data Interface (Streaming mode)
    //=========================================================================
    output wire [DATA_WIDTH-1:0]    ch1_rx_dout,        // Channel 1 RX data
    output wire                     ch1_rx_dout_valid,  // Channel 1 RX data valid

    //=========================================================================
    // Status Outputs
    //=========================================================================
    output wire                     ch0_channel_up,     // Channel 0 link is up
    output wire [LANE_NUM-1:0]      ch0_lane_up,        // Channel 0 per-lane link up
    output wire                     ch0_hard_err,       // Channel 0 hard error
    output wire                     ch0_soft_err,       // Channel 0 soft error
    output wire                     ch1_channel_up,     // Channel 1 link is up
    output wire [LANE_NUM-1:0]      ch1_lane_up,        // Channel 1 per-lane link up
    output wire                     ch1_hard_err,       // Channel 1 hard error
    output wire                     ch1_soft_err,       // Channel 1 soft error

    //=========================================================================
    // Clock Output (optional, for user logic)
    //=========================================================================
    output wire                     user_clk_out        // Aurora user clock output
);

    //=========================================================================
    // Internal signals - Clocks
    //=========================================================================
    wire        gt_refclk;
    wire        user_clk;
    wire        sync_clk;
    wire        init_clk;
    wire        drp_clk;

    //=========================================================================
    // Internal signals - QPLL Channel 0
    //=========================================================================
    wire        qpll0_outclk;
    wire        qpll0_outrefclk;
    wire        qpll0_lock;
    wire        qpll0_refclklost;
    wire        qpll0_reset;

    //=========================================================================
    // Internal signals - QPLL Channel 1
    //=========================================================================
    wire        qpll1_outclk;
    wire        qpll1_outrefclk;
    wire        qpll1_lock;
    wire        qpll1_refclklost;
    wire        qpll1_reset;

    //=========================================================================
    // Internal signals - Resets
    //=========================================================================
    wire        sys_rst;
    wire        reset_pb;
    wire        pma_init;

    //=========================================================================
    // Internal signals - TX output clock from Channel 0
    //=========================================================================
    wire        tx_out_clk_ch0;

    //=========================================================================
    // System reset polarity conversion
    //=========================================================================
    assign sys_rst = ~sys_rst_n;

    //=========================================================================
    // User clock output
    //=========================================================================
    assign user_clk_out = user_clk;

    //=========================================================================
    // Clock and Reset Module
    //=========================================================================
    aurora_clock_module u_clock_module (
        .gt_refclk_p                (gt_refclk_p),
        .gt_refclk_n                (gt_refclk_n),
        .init_clk_in                (init_clk_in),
        .tx_out_clk_ch0             (tx_out_clk_ch0),
        .qpll_reset_ch0             (qpll0_reset),
        .qpll_reset_ch1             (qpll1_reset),
        .sys_rst                    (sys_rst),
        .gt_refclk                  (gt_refclk),
        .user_clk                   (user_clk),
        .sync_clk                   (sync_clk),
        .init_clk                   (init_clk),
        .drp_clk                    (drp_clk),
        .qpll0_outclk               (qpll0_outclk),
        .qpll0_outrefclk            (qpll0_outrefclk),
        .qpll0_lock                 (qpll0_lock),
        .qpll0_refclklost           (qpll0_refclklost),
        .qpll1_outclk               (qpll1_outclk),
        .qpll1_outrefclk            (qpll1_outrefclk),
        .qpll1_lock                 (qpll1_lock),
        .qpll1_refclklost           (qpll1_refclklost),
        .reset_pb                   (reset_pb),
        .pma_init                   (pma_init)
    );

    //=========================================================================
    // Aurora Channel 0 (GTHQ0)
    //=========================================================================
    aurora_channel #(
        .DATA_WIDTH                 (DATA_WIDTH),
        .LANE_NUM                   (LANE_NUM)
    ) u_aurora_ch0 (
        .user_clk                   (user_clk),
        .sync_clk                   (sync_clk),
        .init_clk                   (init_clk),
        .drp_clk                    (drp_clk),
        .gt_refclk                  (gt_refclk),
        .reset_pb                   (reset_pb),
        .pma_init                   (pma_init),
        .qpll_outclk                (qpll0_outclk),
        .qpll_outrefclk             (qpll0_outrefclk),
        .qpll_lock                  (qpll0_lock),
        .qpll_refclklost            (qpll0_refclklost),
        .qpll_reset                 (qpll0_reset),
        .rxp                        (ch0_rxp),
        .rxn                        (ch0_rxn),
        .txp                        (ch0_txp),
        .txn                        (ch0_txn),
        .tx_din                     (ch0_tx_din),
        .tx_din_valid               (ch0_tx_din_valid),
        .tx_ready                   (ch0_tx_ready),
        .rx_dout                    (ch0_rx_dout),
        .rx_dout_valid              (ch0_rx_dout_valid),
        .channel_up                 (ch0_channel_up),
        .lane_up                    (ch0_lane_up),
        .hard_err                   (ch0_hard_err),
        .soft_err                   (ch0_soft_err),
        .tx_out_clk                 (tx_out_clk_ch0),
        .rx_count                   (),
        .rx_error                   ()
    );

    //=========================================================================
    // Aurora Channel 1 (GTHQ1)
    //=========================================================================
    aurora_channel #(
        .DATA_WIDTH                 (DATA_WIDTH),
        .LANE_NUM                   (LANE_NUM)
    ) u_aurora_ch1 (
        .user_clk                   (user_clk),
        .sync_clk                   (sync_clk),
        .init_clk                   (init_clk),
        .drp_clk                    (drp_clk),
        .gt_refclk                  (gt_refclk),
        .reset_pb                   (reset_pb),
        .pma_init                   (pma_init),
        .qpll_outclk                (qpll1_outclk),
        .qpll_outrefclk             (qpll1_outrefclk),
        .qpll_lock                  (qpll1_lock),
        .qpll_refclklost            (qpll1_refclklost),
        .qpll_reset                 (qpll1_reset),
        .rxp                        (ch1_rxp),
        .rxn                        (ch1_rxn),
        .txp                        (ch1_txp),
        .txn                        (ch1_txn),
        .tx_din                     (ch1_tx_din),
        .tx_din_valid               (ch1_tx_din_valid),
        .tx_ready                   (ch1_tx_ready),
        .rx_dout                    (ch1_rx_dout),
        .rx_dout_valid              (ch1_rx_dout_valid),
        .channel_up                 (ch1_channel_up),
        .lane_up                    (ch1_lane_up),
        .hard_err                   (ch1_hard_err),
        .soft_err                   (ch1_soft_err),
        .tx_out_clk                 (),
        .rx_count                   (),
        .rx_error                   ()
    );

endmodule
